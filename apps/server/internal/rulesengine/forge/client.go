// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Package forge owns the private JSONL process boundary to Hexproof's pinned
// headless Forge runtime. It has no room, WebSocket, or projection concerns.
package forge

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"hexproof/server/internal/forgediag"
)

const (
	maxRequestBytes         = 4 << 20
	defaultMaxResponseBytes = 16 << 20
	defaultStartTimeout     = 45 * time.Second
	closeTimeout            = 2 * time.Second
)

// ProcessConfig describes one long-lived Forge harness process.
type ProcessConfig struct {
	Command string
	Args    []string
	Dir     string
	Env     []string
	// Deprecated: raw engine output is discarded. Safe evidence is available
	// through FailureSource; a caller-owned writer cannot stall the drain.
	Stderr           io.Writer
	MaxResponseBytes int
	StartTimeout     time.Duration
	IsolatedProfile  bool
}

// JavaProcessConfig returns the standard command line for an extracted Forge
// runtime package.
func JavaProcessConfig(javaCommand, harnessJAR, forgeHome string) ProcessConfig {
	if strings.TrimSpace(javaCommand) == "" {
		javaCommand = "java"
	}
	return ProcessConfig{
		Command:         javaCommand,
		IsolatedProfile: true,
		Args: []string{
			"-jar", harnessJAR,
			"--interactive-server",
			"--forge-home", forgeHome,
		},
	}
}

// JavaOverlayProcessConfig loads the verified bundled adapter before classes
// in the immutable base JAR and its manifest-listed runtime dependencies.
func JavaOverlayProcessConfig(javaCommand, harnessJAR, forgeHome, overlayJAR string) ProcessConfig {
	config := JavaProcessConfig(javaCommand, harnessJAR, forgeHome)
	config.Args = append([]string{"-cp", overlayJAR + string(os.PathListSeparator) + harnessJAR,
		"org.hexproof.forge.NativeHost"}, config.Args[2:]...)
	return config
}

type rpcRequest struct {
	After            int64  `json:"after,omitempty"`
	Command          string `json:"command"`
	Payload          string `json:"payload,omitempty"`
	SessionID        string `json:"sessionId,omitempty"`
	PlayerIndex      *int   `json:"playerIndex,omitempty"`
	Viewer           *int   `json:"viewer,omitempty"`
	Viewers          []int  `json:"viewers,omitempty"`
	PreviousPromptID int64  `json:"previousPromptId,omitempty"`
	TimeoutMs        int    `json:"timeoutMs,omitempty"`
}

type rpcResponse struct {
	WorkerFatal  bool            `json:"workerFatal,omitempty"`
	FailureInfo  json.RawMessage `json:"failureInfo,omitempty"`
	StartFailure json.RawMessage `json:"startFailure,omitempty"`
	Fatal        bool            `json:"fatal,omitempty"`
	OK           bool            `json:"ok"`
	Result       string          `json:"result"`
	Error        string          `json:"error"`
}

type rpcResult struct {
	value string
	err   error
}

type rpcJob struct {
	ctx        context.Context
	request    rpcRequest
	noResponse bool
	started    chan struct{}
	result     chan rpcResult
}

// Client owns one game. The default transport is a dedicated ordered process;
// a pool lease uses request IDs while retaining per-game call ordering.
type Client struct {
	diagnostics     *diagnosticCollector
	supportsReplay  bool
	supportsAI      bool
	supportsDuelAI  bool
	adapterRevision int
	aiGame          atomic.Bool
	shared          *sharedLease
	command         *exec.Cmd
	stdin           io.WriteCloser
	requests        chan rpcJob
	done            chan struct{}
	reaped          chan struct{}

	maxResponseBytes int
	closing          atomic.Bool
	invalid          atomic.Bool
	killOnce         sync.Once
	closeOnce        sync.Once
	closeErr         error
	waitMu           sync.Mutex
	waitErr          error
	boundaryErr      error
	profileDir       string
}

// Start launches and probes a Forge harness. A failed probe terminates the
// child, so callers never receive a half-initialized client.
func Start(ctx context.Context, config ProcessConfig) (*Client, error) {
	if strings.TrimSpace(config.Command) == "" {
		return nil, processError("executable_missing", errors.New("forge runtime command is required"))
	}
	if config.MaxResponseBytes <= 0 {
		config.MaxResponseBytes = defaultMaxResponseBytes
	}
	if config.StartTimeout <= 0 {
		config.StartTimeout = defaultStartTimeout
	}

	command := exec.Command(config.Command, config.Args...)
	configurePlatformProcess(command)
	command.Dir = config.Dir
	command.Env = append(os.Environ(), config.Env...)
	profileDir := ""
	profileTransferred := false
	if config.IsolatedProfile {
		var err error
		profileDir, err = os.MkdirTemp("", "hexproof-forge-")
		if err != nil {
			return nil, processError("profile_create_failed", err)
		}
		command.Env = append(command.Env, "HEXPROOF_FORGE_PROFILE="+profileDir)
		defer func() {
			if !profileTransferred {
				_ = os.RemoveAll(profileDir)
			}
		}()
	}
	stdin, err := command.StdinPipe()
	if err != nil {
		return nil, processError("pipe_setup_failed", err)
	}
	stdout, err := command.StdoutPipe()
	if err != nil {
		return nil, processError("pipe_setup_failed", err)
	}
	stderr, err := command.StderrPipe()
	if err != nil {
		return nil, processError("pipe_setup_failed", err)
	}
	if err := command.Start(); err != nil {
		return nil, executableError(err)
	}

	client := &Client{
		diagnostics:      newDiagnosticCollector(),
		command:          command,
		stdin:            stdin,
		requests:         make(chan rpcJob, 32),
		done:             make(chan struct{}),
		reaped:           make(chan struct{}),
		maxResponseBytes: config.MaxResponseBytes,
		profileDir:       profileDir,
	}
	profileTransferred = true
	go client.captureStderr(stderr, config.Stderr)
	go client.run(stdout)
	go client.wait()

	probeContext, cancelProbe := context.WithTimeout(ctx, config.StartTimeout)
	defer cancelProbe()
	capabilities, err := client.call(probeContext, rpcRequest{Command: "reset"}, false, true)
	if err != nil {
		if probeContext.Err() != nil {
			err = probeContext.Err()
		}
		client.kill()
		<-client.done
		return nil, probeError(err)
	}
	client.supportsAI = runtimeSupportsAI(capabilities)
	client.supportsDuelAI = runtimeSupportsCapability(capabilities, "forge-duel-ai-v1")
	client.supportsReplay = runtimeSupportsReplay(capabilities)
	client.adapterRevision = runtimeAdapterRevision(capabilities)
	client.diagnostics.bind("", "", client.adapterRevision)
	return client, nil
}

func (client *Client) wait() {
	err := client.command.Wait()
	client.diagnostics.exit(err)
	client.waitMu.Lock()
	client.waitErr = err
	client.waitMu.Unlock()
	// The process exit is known before profile cleanup, which can be slow on
	// antivirus-scanned or busy storage. Keep Done's full cleanup guarantee.
	close(client.reaped)
	// This exact directory was created by Start, never supplied by a caller.
	// Reap before cleanup so even a killed JVM cannot leave mutable preferences
	// shared with the next game or retain a growing set of per-game profiles.
	if client.profileDir != "" {
		_ = os.RemoveAll(client.profileDir)
	}
	close(client.done)
}

func (client *Client) waitError() error {
	client.waitMu.Lock()
	defer client.waitMu.Unlock()
	if client.boundaryErr != nil {
		return client.boundaryErr
	}
	if client.waitErr == nil {
		return &ProcessError{Code: "process_exited", ExitCode: intPointer(0), cause: ErrClosed}
	}
	err := processError("process_exited", errors.Join(ErrRuntime, client.waitErr))
	var exit *exec.ExitError
	if errors.As(client.waitErr, &exit) {
		err.ExitCode = intPointer(exit.ExitCode())
		if exit.ExitCode() < 0 {
			err.Code = "process_signalled"
		}
	}
	return err
}

// Done closes after a dedicated child is reaped, or shared game cleanup is
// acknowledged. Worker failure closes its leases only after process reaping.
// Supervisors must not assume that a retained Client is still live.
func (client *Client) Done() <-chan struct{} { return client.done }

// Healthy reports whether the established transport can still accept work.
// It is not a substitute for handling a failure during the next RPC.
func (client *Client) Healthy() bool {
	if client.shared != nil && !client.shared.worker.healthy() {
		return false
	}
	if client.closing.Load() || client.invalid.Load() {
		return false
	}
	select {
	case <-client.done:
		return false
	default:
		return true
	}
}

// Invalidate permanently stops this runtime after a failed protocol boundary.
// Existing sessions must never be reconstructed on a replacement process.
func (client *Client) Invalidate() { client.kill() }

func (client *Client) captureStderr(reader io.Reader, _ io.Writer) {
	defer client.diagnostics.drained()
	drainDiagnostics(reader, client.diagnostics.streamAccept)
}

func (client *Client) run(stdout io.Reader) {
	writer := bufio.NewWriter(client.stdin)
	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 64<<10), client.maxResponseBytes)

	for {
		select {
		case <-client.done:
			return
		case job := <-client.requests:
			if err := job.ctx.Err(); err != nil {
				job.result <- rpcResult{err: err}
				continue
			}
			client.diagnostics.begin(job.request.Command)
			close(job.started)
			// Close the cancellation race between the first context check and
			// announcing that the request has started. Either the caller now
			// kills an in-flight call, or we avoid sending the canceled job.
			if err := job.ctx.Err(); err != nil {
				job.result <- rpcResult{err: err}
				continue
			}
			requestBytes, err := json.Marshal(job.request)
			if err == nil && len(requestBytes) > maxRequestBytes {
				job.result <- rpcResult{err: errors.New("forge runtime request exceeds the configured limit")}
				continue
			}
			if err == nil {
				_, err = writer.Write(requestBytes)
			}
			if err == nil {
				err = writer.WriteByte('\n')
			}
			if err == nil {
				err = writer.Flush()
			}
			if err != nil {
				job.result <- rpcResult{err: client.failProcess(processError("pipe_write_failed", errors.Join(ErrRuntime, err)))}
				return
			}
			if job.noResponse {
				job.result <- rpcResult{}
				continue
			}
			if !scanner.Scan() {
				err = scanner.Err()
				if errors.Is(err, bufio.ErrTooLong) {
					err = ErrResponseTooLarge
				} else if err == nil {
					err = io.ErrUnexpectedEOF
				}
				job.result <- rpcResult{err: client.readFailure(err)}
				return
			}
			var response rpcResponse
			if err := json.Unmarshal(scanner.Bytes(), &response); err != nil {
				job.result <- rpcResult{err: client.failProcess(processError("protocol_invalid", ErrRuntime))}
				return
			}
			if !response.OK {
				if response.Fatal {
					client.diagnostics.accept(forgediag.ParseCapsule(response.FailureInfo))
					client.diagnostics.boundary("native_failure")
				}
				var failure error = &rejectedRequest{failure: bytes.Clone(response.StartFailure)}
				if response.Fatal {
					failure = fmt.Errorf("%w: request failed", ErrRuntime)
				}
				if job.request.Command == "reset" {
					failure = processError("probe_rejected", ErrRuntime)
				}
				if response.Fatal {
					client.failProcess(failure)
				}
				// Upstream exceptions can contain private card names or decks.
				// Rejected player actions or decks are recoverable, but failed
				// authoritative queries leave the shared runtime untrustworthy.
				switch job.request.Command {
				case "getSnapshot", "getSnapshots", "getPrompt", "awaitPrompt", "getGameOver":
					client.failProcess(failure)
				}
				job.result <- rpcResult{err: failure}
				continue
			}
			job.result <- rpcResult{value: response.Result}
		}
	}
}

func (client *Client) call(ctx context.Context, request rpcRequest, noResponse,
	allowClosing bool) (string, error) {
	if client.shared != nil {
		return client.shared.call(ctx, request)
	}
	if client.closing.Load() && !allowClosing {
		return "", ErrClosed
	}
	if client.invalid.Load() {
		return "", ErrRuntime
	}
	job := rpcJob{
		ctx:        ctx,
		request:    request,
		noResponse: noResponse,
		started:    make(chan struct{}),
		result:     make(chan rpcResult, 1),
	}
	select {
	case client.requests <- job:
	case <-ctx.Done():
		return "", ctx.Err()
	case <-client.done:
		return "", client.waitError()
	}

	select {
	case result := <-job.result:
		return result.value, result.err
	case <-ctx.Done():
		select {
		case <-job.started:
			if errors.Is(ctx.Err(), context.DeadlineExceeded) {
				client.diagnostics.boundary("execution_timeout")
			}
			client.kill()
		default:
		}
		return "", ctx.Err()
	case <-client.done:
		return "", client.waitError()
	}
}

func (client *Client) kill() {
	client.invalid.Store(true)
	if client.shared != nil {
		// A game-level failure releases only this lease. The worker itself
		// is killed when transport state or cleanup cannot be trusted.
		go client.Close()
		return
	}
	client.killOnce.Do(func() {
		client.diagnostics.kill()
		if client.command.Process != nil {
			_ = client.command.Process.Kill()
		}
	})
}

// StartGame creates an interactive Forge session.
func (client *Client) StartGame(ctx context.Context,
	request StartGameRequest) (SessionHandle, error) {
	if err := request.validate(); err != nil {
		return SessionHandle{}, startValidationError(request, err)
	}
	if request.HasAI() {
		if !client.supportsAI || client.shared != nil ||
			(request.Variant == "Commander" && !client.supportsDuelAI) {
			return SessionHandle{}, errors.New("Forge AI requires a capable dedicated runtime")
		}
		client.aiGame.Store(true)
	}
	payload, err := json.Marshal(request)
	if err != nil {
		return SessionHandle{}, fmt.Errorf("encode Forge start request: %w", err)
	}
	result, err := client.call(ctx, rpcRequest{
		Command: "startGame",
		Payload: string(payload),
	}, false, false)
	if err != nil {
		return SessionHandle{}, startRequestError(err, request)
	}
	var handle SessionHandle
	if err := json.Unmarshal([]byte(result), &handle); err != nil {
		client.kill()
		return SessionHandle{}, fmt.Errorf("%w: invalid start result", ErrRuntime)
	}
	if strings.TrimSpace(handle.SessionID) == "" ||
		len(handle.PlayerIndexes) != len(request.Players) {
		client.kill()
		return SessionHandle{}, fmt.Errorf("%w: invalid session handle", ErrRuntime)
	}
	seen := make(map[int]bool, len(handle.PlayerIndexes))
	for _, player := range handle.PlayerIndexes {
		if player < 0 || player >= maxPlayers || seen[player] {
			client.kill()
			return SessionHandle{}, fmt.Errorf("%w: invalid session handle", ErrRuntime)
		}
		seen[player] = true
	}
	client.diagnostics.bind(handle.SessionID, handle.DiagnosticProducerID, client.adapterRevision)
	return handle, nil
}

// SubmitAction forwards one canonical prompt response. Prompt ownership is
// validated by the future rules-room coordinator before this method is called.
func (client *Client) SubmitAction(ctx context.Context, sessionID string,
	action json.RawMessage) error {
	if err := validateSessionID(sessionID); err != nil {
		return err
	}
	if len(action) == 0 || !json.Valid(action) {
		return errors.New("action must be valid JSON")
	}
	if len(action) > maxRequestBytes {
		return errors.New("action exceeds the configured limit")
	}
	_, err := client.call(ctx, rpcRequest{
		Command:   "submitAction",
		SessionID: sessionID,
		Payload:   string(action),
	}, false, false)
	return err
}

// Concede submits Forge's out-of-band directive for one authenticated engine
// player. It is deliberately separate from prompt answers because a player may
// concede while another player's decision is open.
func (client *Client) Concede(ctx context.Context, sessionID string, playerIndex int) error {
	if playerIndex < 0 || playerIndex >= maxPlayers {
		return fmt.Errorf("player index must be between 0 and %d", maxPlayers-1)
	}
	action, err := json.Marshal(struct {
		Type      string `json:"type"`
		Directive struct {
			Type string `json:"type"`
		} `json:"directive"`
		Player int `json:"player"`
	}{Type: "directive", Directive: struct {
		Type string `json:"type"`
	}{Type: "concede"}, Player: playerIndex})
	if err != nil {
		return fmt.Errorf("encode Forge concede directive: %w", err)
	}
	return client.SubmitAction(ctx, sessionID, action)
}

// Prompt asks for the current canonical prompt using one engine player index.
// The pinned harness currently returns a session-global prompt, so callers
// must still validate decidingPlayerId before projecting it. A nil result
// means that the runtime has not published a prompt.
func (client *Client) Prompt(ctx context.Context, sessionID string,
	playerIndex int) (json.RawMessage, error) {
	if err := validateSessionID(sessionID); err != nil {
		return nil, err
	}
	if playerIndex < 0 || playerIndex >= maxPlayers {
		return nil, fmt.Errorf("player index must be between 0 and %d", maxPlayers-1)
	}
	result, err := client.call(ctx, rpcRequest{
		Command:     "getPrompt",
		SessionID:   sessionID,
		PlayerIndex: intPointer(playerIndex),
	}, false, false)
	decoded, decodeErr := decodeOptionalJSON(result, err)
	if err == nil && decodeErr != nil {
		client.kill()
	}
	return decoded, decodeErr
}

// Snapshot returns a viewer-specific Forge state. Viewer -1 is the upstream
// spectator projection and must not be substituted for a player projection.
func (client *Client) Snapshot(ctx context.Context, sessionID string,
	viewer int) (json.RawMessage, error) {
	if err := validateSessionID(sessionID); err != nil {
		return nil, err
	}
	if viewer < -1 || viewer >= maxPlayers {
		return nil, fmt.Errorf("viewer must be between -1 and %d", maxPlayers-1)
	}
	result, err := client.call(ctx, rpcRequest{
		Command:   "getSnapshot",
		SessionID: sessionID,
		Viewer:    intPointer(viewer),
	}, false, false)
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(result) == "" || !json.Valid([]byte(result)) {
		client.kill()
		return nil, fmt.Errorf("%w: invalid snapshot JSON", ErrRuntime)
	}
	return json.RawMessage(result), nil
}

// Snapshots returns one projection per viewer. Adapter 29 answers in one
// engine call. Older adapters, and a shared worker that has not reported
// that revision, keep a call per viewer.
func (client *Client) Snapshots(ctx context.Context, sessionID string, viewers []int) ([]json.RawMessage, error) {
	if err := validateSessionID(sessionID); err != nil {
		return nil, err
	}
	if len(viewers) == 0 || len(viewers) > 8 {
		return nil, errors.New("snapshot viewers are required")
	}
	for _, viewer := range viewers {
		if viewer < -1 || viewer >= maxPlayers {
			return nil, fmt.Errorf("viewer must be between -1 and %d", maxPlayers-1)
		}
	}
	if client.adapterRevision < 29 {
		views := make([]json.RawMessage, 0, len(viewers))
		for _, viewer := range viewers {
			view, err := client.Snapshot(ctx, sessionID, viewer)
			if err != nil {
				return nil, err
			}
			views = append(views, view)
		}
		return views, nil
	}
	result, err := client.call(ctx, rpcRequest{
		Command:   "getSnapshots",
		SessionID: sessionID,
		Viewers:   viewers,
	}, false, false)
	if err != nil {
		return nil, err
	}
	var views []json.RawMessage
	if json.Unmarshal([]byte(result), &views) != nil || len(views) != len(viewers) {
		client.kill()
		return nil, fmt.Errorf("%w: invalid snapshot batch", ErrRuntime)
	}
	for _, view := range views {
		if len(view) == 0 || !json.Valid(view) {
			client.kill()
			return nil, fmt.Errorf("%w: invalid snapshot batch", ErrRuntime)
		}
	}
	return views, nil
}

// AwaitPrompt blocks until the session publishes a different prompt, the game
// ends, or the deadline passes. A shared worker stays on the polling loop so
// one game cannot hold the process for every other game.
func (client *Client) AwaitPrompt(ctx context.Context, sessionID string, previous int64) (json.RawMessage, bool, error) {
	if client.shared != nil || client.adapterRevision < 29 {
		return nil, false, nil
	}
	if err := validateSessionID(sessionID); err != nil {
		return nil, false, err
	}
	timeout := 5 * time.Second
	if deadline, ok := ctx.Deadline(); ok {
		timeout = time.Until(deadline)
	}
	if timeout < time.Millisecond {
		return nil, true, ctx.Err()
	}
	if timeout > 30*time.Second {
		timeout = 30 * time.Second
	}
	result, err := client.call(ctx, rpcRequest{
		Command:          "awaitPrompt",
		SessionID:        sessionID,
		PreviousPromptID: previous,
		TimeoutMs:        int(timeout.Milliseconds()),
	}, false, false)
	if err != nil {
		return nil, true, err
	}
	decoded, err := decodeOptionalJSON(result, nil)
	return decoded, true, err
}

// GameOver reports Forge's authoritative terminal state.
func (client *Client) GameOver(ctx context.Context, sessionID string) (bool, error) {
	if err := validateSessionID(sessionID); err != nil {
		return false, err
	}
	result, err := client.call(ctx, rpcRequest{
		Command:   "getGameOver",
		SessionID: sessionID,
	}, false, false)
	if err != nil {
		return false, err
	}
	gameOver, err := strconv.ParseBool(result)
	if err != nil {
		client.kill()
		return false, fmt.Errorf("%w: invalid game-over result", ErrRuntime)
	}
	return gameOver, nil
}

// EndGame closes a normally completed engine session.
func (client *Client) EndGame(ctx context.Context, sessionID string) error {
	return client.endSession(ctx, "endGame", sessionID)
}

// AbortGame closes an engine session that cannot continue.
func (client *Client) AbortGame(ctx context.Context, sessionID string) error {
	return client.endSession(ctx, "abortGame", sessionID)
}

func (client *Client) endSession(ctx context.Context, command, sessionID string) error {
	if err := validateSessionID(sessionID); err != nil {
		return err
	}
	_, err := client.call(ctx, rpcRequest{Command: command, SessionID: sessionID},
		false, false)
	return err
}

func decodeOptionalJSON(result string, err error) (json.RawMessage, error) {
	if err != nil {
		return nil, err
	}
	trimmed := strings.TrimSpace(result)
	if trimmed == "" || trimmed == "null" {
		return nil, nil
	}
	if !json.Valid([]byte(trimmed)) {
		return nil, fmt.Errorf("%w: invalid prompt JSON", ErrRuntime)
	}
	return json.RawMessage(trimmed), nil
}

func intPointer(value int) *int {
	return &value
}

func validateSessionID(sessionID string) error {
	if strings.TrimSpace(sessionID) == "" {
		return errors.New("session id is required")
	}
	if len(sessionID) > 256 {
		return errors.New("session id exceeds 256 bytes")
	}
	return nil
}

// Close cleans up the owned game lease. Dedicated processes exit; shared
// workers retain other games unless bounded native cleanup cannot finish.
func (client *Client) Close() error {
	if client.shared != nil {
		return client.shared.close()
	}
	client.closeOnce.Do(func() {
		client.closing.Store(true)
		ctx, cancel := context.WithTimeout(context.Background(), closeTimeout)
		defer cancel()
		_, writeErr := client.call(ctx, rpcRequest{Command: "quit"}, true, true)
		if writeErr != nil && !errors.Is(writeErr, ErrClosed) {
			client.closeErr = writeErr
		}
		select {
		case <-client.done:
		case <-ctx.Done():
			client.kill()
			<-client.done
			if client.closeErr == nil {
				client.closeErr = ctx.Err()
			}
		}
	})
	return client.closeErr
}

// SupportsAI reports the native distribution capability. Shared leases still
// reject AI start; the coordinator must acquire a dedicated process for it.
func (client *Client) SupportsAI() bool { return client.supportsAI }

func (client *Client) SupportsDuelAI() bool { return client.supportsAI && client.supportsDuelAI }

func runtimeSupportsAI(raw string) bool { return runtimeSupportsCapability(raw, "forge-ai-v1") }

func runtimeSupportsCapability(raw, capability string) bool {
	var metadata struct {
		Capabilities []string `json:"capabilities"`
	}
	if json.Unmarshal([]byte(raw), &metadata) != nil {
		return false
	}
	for _, value := range metadata.Capabilities {
		if value == capability {
			return true
		}
	}
	return false
}

// RequestTimeout bounds the whole native boundary, including AI computation.
func (client *Client) RequestTimeout() time.Duration {
	if client.aiGame.Load() {
		return 35 * time.Second
	}
	return 5 * time.Second
}
