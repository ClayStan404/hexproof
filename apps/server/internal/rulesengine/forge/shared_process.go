// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

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
)

type sharedRequest struct {
	RequestID uint64 `json:"requestId"`
	rpcRequest
}

type sharedResponse struct {
	RequestID uint64 `json:"requestId"`
	rpcResponse
}

type sharedJob struct {
	id      uint64
	ctx     context.Context
	data    []byte
	started chan struct{}
	result  chan rpcResult
}

// sharedWorker transports independent game calls concurrently. Unknown IDs,
// framing failures and in-flight timeouts invalidate the bounded whole worker:
// the outcome of an engine mutation must never be guessed or silently replayed.
type sharedWorker struct {
	command  *exec.Cmd
	stdin    io.WriteCloser
	jobs     chan *sharedJob
	done     chan struct{}
	invalid  atomic.Bool
	sequence atomic.Uint64
	killOnce sync.Once
	mu       sync.Mutex
	pending  map[uint64]*sharedJob
}

func startSharedWorker(ctx context.Context, config ProcessConfig, capacity int) (*sharedWorker, error) {
	if strings.TrimSpace(config.Command) == "" {
		return nil, errors.New("forge runtime command is required")
	}
	if config.StartTimeout <= 0 {
		config.StartTimeout = defaultStartTimeout
	}
	if config.MaxResponseBytes <= 0 {
		config.MaxResponseBytes = defaultMaxResponseBytes
	}
	args := append(append([]string(nil), config.Args...), "--max-games", strconv.Itoa(capacity))
	command := exec.Command(config.Command, args...)
	configurePlatformProcess(command)
	command.Dir = config.Dir
	command.Env = append(os.Environ(), config.Env...)
	profile := ""
	transferred := false
	if config.IsolatedProfile {
		var err error
		profile, err = os.MkdirTemp("", "hexproof-forge-shared-")
		if err != nil {
			return nil, fmt.Errorf("create Forge worker profile: %w", err)
		}
		command.Env = append(command.Env, "HEXPROOF_FORGE_PROFILE="+profile)
		defer func() {
			if !transferred {
				_ = os.RemoveAll(profile)
			}
		}()
	}
	stdin, err := command.StdinPipe()
	if err != nil {
		return nil, err
	}
	stdout, err := command.StdoutPipe()
	if err != nil {
		return nil, err
	}
	stderr, err := command.StderrPipe()
	if err != nil {
		return nil, err
	}
	if err := command.Start(); err != nil {
		return nil, fmt.Errorf("start shared Forge runtime: %w", err)
	}
	worker := &sharedWorker{command: command, stdin: stdin, jobs: make(chan *sharedJob, 32),
		done: make(chan struct{}), pending: make(map[uint64]*sharedJob)}
	transferred = true
	go captureRuntimeStderr(stderr, config.Stderr)
	go worker.write()
	go worker.read(stdout, config.MaxResponseBytes)
	go func() {
		_ = command.Wait()
		if profile != "" {
			// This exact directory is created above, never supplied by a caller.
			_ = os.RemoveAll(profile)
		}
		worker.mu.Lock()
		clear(worker.pending)
		worker.mu.Unlock()
		close(worker.done)
	}()
	probe, cancel := context.WithTimeout(ctx, config.StartTimeout)
	defer cancel()
	result, err := worker.call(probe, rpcRequest{Command: "reset"})
	var metadata struct {
		Version  int `json:"sharedVersion"`
		Capacity int `json:"capacity"`
	}
	if err == nil && (json.Unmarshal([]byte(result), &metadata) != nil || metadata.Version != 1 || metadata.Capacity != capacity) {
		err = errors.New("runtime does not support the requested shared protocol")
	}
	if err != nil {
		worker.kill()
		<-worker.done
		return nil, fmt.Errorf("probe shared Forge runtime: %w", err)
	}
	return worker, nil
}

func (worker *sharedWorker) healthy() bool {
	if worker.invalid.Load() {
		return false
	}
	select {
	case <-worker.done:
		return false
	default:
		return true
	}
}

func (worker *sharedWorker) kill() {
	worker.invalid.Store(true)
	worker.killOnce.Do(func() { _ = worker.command.Process.Kill() })
}

func (worker *sharedWorker) take(id uint64) *sharedJob {
	worker.mu.Lock()
	defer worker.mu.Unlock()
	job := worker.pending[id]
	delete(worker.pending, id)
	return job
}

func (worker *sharedWorker) write() {
	for {
		select {
		case <-worker.done:
			return
		case job := <-worker.jobs:
			if job.ctx.Err() != nil {
				worker.take(job.id)
				continue
			}
			close(job.started)
			if job.ctx.Err() != nil {
				worker.take(job.id)
				continue
			}
			if _, err := worker.stdin.Write(job.data); err != nil {
				worker.kill()
				return
			}
		}
	}
}

func (worker *sharedWorker) read(stdout io.Reader, maxBytes int) {
	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 64<<10), maxBytes)
	for scanner.Scan() {
		var response sharedResponse
		if json.Unmarshal(scanner.Bytes(), &response) != nil || response.RequestID == 0 {
			break
		}
		job := worker.take(response.RequestID)
		if job == nil {
			break
		}
		result := rpcResult{value: response.Result}
		if !response.OK {
			// Native exception details may contain private deck/card identities.
			result = rpcResult{err: fmt.Errorf("%w: request rejected", ErrRuntime)}
		}
		job.result <- result
	}
	worker.kill()
}

func (worker *sharedWorker) call(ctx context.Context, request rpcRequest) (string, error) {
	if !worker.healthy() {
		return "", ErrClosed
	}
	id := worker.sequence.Add(1)
	data, err := json.Marshal(sharedRequest{RequestID: id, rpcRequest: request})
	if err != nil || len(data) > maxRequestBytes {
		return "", errors.New("invalid or oversized shared Forge request")
	}
	job := &sharedJob{id: id, ctx: ctx, data: append(data, '\n'), started: make(chan struct{}), result: make(chan rpcResult, 1)}
	worker.mu.Lock()
	if len(worker.pending) >= 64 {
		worker.mu.Unlock()
		return "", errors.New("shared Forge request capacity exceeded")
	}
	worker.pending[id] = job
	worker.mu.Unlock()
	select {
	case worker.jobs <- job:
	case <-ctx.Done():
		worker.take(id)
		return "", ctx.Err()
	case <-worker.done:
		worker.take(id)
		return "", ErrClosed
	}
	select {
	case result := <-job.result:
		return result.value, result.err
	case <-ctx.Done():
		select {
		case <-job.started:
			worker.kill()
		default:
			worker.take(id)
		}
		return "", ctx.Err()
	case <-worker.done:
		return "", ErrClosed
	}
}
