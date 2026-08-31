// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Package forge owns the private JSONL process boundary to Hexproof's pinned
// headless Forge runtime. It has no room, WebSocket, or projection concerns.
package forge

import (
	"bufio"
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
)

const (
	maxRequestBytes         = 4 << 20
	defaultMaxResponseBytes = 16 << 20
	defaultStartTimeout     = 45 * time.Second
	closeTimeout            = 2 * time.Second
)

// ProcessConfig describes one long-lived Forge harness process.
type ProcessConfig struct {
	Command          string
	Args             []string
	Dir              string
	Env              []string
	Stderr           io.Writer
	MaxResponseBytes int
	StartTimeout     time.Duration
}

// JavaProcessConfig returns the standard command line for an extracted Forge
// runtime package.
func JavaProcessConfig(javaCommand, harnessJAR, forgeHome string) ProcessConfig {
	if strings.TrimSpace(javaCommand) == "" {
		javaCommand = "java"
	}
	return ProcessConfig{
		Command: javaCommand,
		Args: []string{
			"-jar", harnessJAR,
			"--interactive-server",
			"--forge-home", forgeHome,
		},
	}
}

type rpcRequest struct {
	Command     string `json:"command"`
	Payload     string `json:"payload,omitempty"`
	SessionID   string `json:"sessionId,omitempty"`
	PlayerIndex *int   `json:"playerIndex,omitempty"`
	Viewer      *int   `json:"viewer,omitempty"`
}

type rpcResponse struct {
	OK     bool   `json:"ok"`
	Result string `json:"result"`
	Error  string `json:"error"`
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

// Client serializes calls because the upstream transport returns ordered JSON
// lines without request identifiers. Concurrent callers are safe.
type Client struct {
	command  *exec.Cmd
	stdin    io.WriteCloser
	requests chan rpcJob
	done     chan struct{}

	maxResponseBytes int
	closing          atomic.Bool
	killOnce         sync.Once
	closeOnce        sync.Once
	closeErr         error
	waitMu           sync.Mutex
	waitErr          error
}

// Start launches and probes a Forge harness. A failed probe terminates the
// child, so callers never receive a half-initialized client.
func Start(ctx context.Context, config ProcessConfig) (*Client, error) {
	if strings.TrimSpace(config.Command) == "" {
		return nil, errors.New("forge runtime command is required")
	}
	if config.MaxResponseBytes <= 0 {
		config.MaxResponseBytes = defaultMaxResponseBytes
	}
	if config.StartTimeout <= 0 {
		config.StartTimeout = defaultStartTimeout
	}

	command := exec.Command(config.Command, config.Args...)
	command.Dir = config.Dir
	command.Env = append(os.Environ(), config.Env...)
	stdin, err := command.StdinPipe()
	if err != nil {
		return nil, fmt.Errorf("forge runtime stdin: %w", err)
	}
	stdout, err := command.StdoutPipe()
	if err != nil {
		return nil, fmt.Errorf("forge runtime stdout: %w", err)
	}
	stderr, err := command.StderrPipe()
	if err != nil {
		return nil, fmt.Errorf("forge runtime stderr: %w", err)
	}
	if err := command.Start(); err != nil {
		return nil, fmt.Errorf("start forge runtime: %w", err)
	}

	client := &Client{
		command:          command,
		stdin:            stdin,
		requests:         make(chan rpcJob, 32),
		done:             make(chan struct{}),
		maxResponseBytes: config.MaxResponseBytes,
	}
	go client.captureStderr(stderr, config.Stderr)
	go client.run(stdout)
	go client.wait()

	probeContext, cancelProbe := context.WithTimeout(ctx, config.StartTimeout)
	defer cancelProbe()
	if _, err := client.call(probeContext, rpcRequest{Command: "reset"}, false, true); err != nil {
		client.kill()
		<-client.done
		return nil, fmt.Errorf("probe forge runtime: %w", err)
	}
	return client, nil
}

func (client *Client) wait() {
	err := client.command.Wait()
	client.waitMu.Lock()
	client.waitErr = err
	client.waitMu.Unlock()
	close(client.done)
}

func (client *Client) waitError() error {
	client.waitMu.Lock()
	defer client.waitMu.Unlock()
	if client.waitErr == nil {
		return ErrClosed
	}
	return fmt.Errorf("%w: process exited: %v", ErrRuntime, client.waitErr)
}

func (client *Client) captureStderr(reader io.Reader, destination io.Writer) {
	if destination == nil {
		destination = io.Discard
	}
	scanner := bufio.NewScanner(reader)
	scanner.Buffer(make([]byte, 4096), 256<<10)
	for scanner.Scan() {
		_, _ = fmt.Fprintln(destination, scanner.Text())
	}
	// Always drain the pipe if an oversized diagnostic line stops Scanner.
	_, _ = io.Copy(io.Discard, reader)
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
			close(job.started)
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
				job.result <- rpcResult{err: fmt.Errorf("%w: write request: %v", ErrRuntime, err)}
				client.kill()
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
				job.result <- rpcResult{err: fmt.Errorf("%w: read response: %w", ErrRuntime, err)}
				client.kill()
				return
			}
			var response rpcResponse
			if err := json.Unmarshal(scanner.Bytes(), &response); err != nil {
				job.result <- rpcResult{err: fmt.Errorf("%w: decode response: %v", ErrRuntime, err)}
				client.kill()
				return
			}
			if !response.OK {
				job.result <- rpcResult{err: fmt.Errorf("%w: %s", ErrRuntime,
					boundedMessage(response.Error, 512))}
				continue
			}
			job.result <- rpcResult{value: response.Result}
		}
	}
}

func boundedMessage(value string, limit int) string {
	value = strings.TrimSpace(value)
	if len(value) <= limit {
		return value
	}
	return value[:limit] + "…"
}

func (client *Client) call(ctx context.Context, request rpcRequest, noResponse,
	allowClosing bool) (string, error) {
	if client.closing.Load() && !allowClosing {
		return "", ErrClosed
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
			client.kill()
		default:
		}
		return "", ctx.Err()
	case <-client.done:
		return "", client.waitError()
	}
}

func (client *Client) kill() {
	client.killOnce.Do(func() {
		if client.command.Process != nil {
			_ = client.command.Process.Kill()
		}
	})
}

// StartGame creates an interactive Forge session.
func (client *Client) StartGame(ctx context.Context,
	request StartGameRequest) (SessionHandle, error) {
	if err := request.validate(); err != nil {
		return SessionHandle{}, err
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
		return SessionHandle{}, err
	}
	var handle SessionHandle
	if err := json.Unmarshal([]byte(result), &handle); err != nil {
		return SessionHandle{}, fmt.Errorf("%w: decode start result: %v", ErrRuntime, err)
	}
	if strings.TrimSpace(handle.SessionID) == "" ||
		len(handle.PlayerIndexes) != len(request.Players) {
		return SessionHandle{}, fmt.Errorf("%w: invalid session handle", ErrRuntime)
	}
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
	return decodeOptionalJSON(result, err)
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
		return nil, fmt.Errorf("%w: invalid snapshot JSON", ErrRuntime)
	}
	return json.RawMessage(result), nil
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

// Close asks the harness to exit, then forcibly terminates it if its game
// threads do not unwind within a short deadline.
func (client *Client) Close() error {
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
