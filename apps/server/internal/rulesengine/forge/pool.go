// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"context"
	"encoding/json"
	"errors"
	"sync"
	"time"
)

const sharedWorkerGames = 64

type pooledWorker struct {
	worker *sharedWorker
	leases map[*Client]bool
	games  int
	idle   *time.Timer
}

// Pool admits isolated games to bounded shared JVMs. The room coordinator owns
// the total game limit. Workers retire after 64 leases or one idle minute, and
// transport failure affects at most GamesPerWorker games. It never retries a
// mutation on another worker or reconstructs a lost game.
type Pool struct {
	mu          sync.Mutex
	config      ProcessConfig
	capacity    int
	workers     []*pooledWorker
	starting    chan struct{}
	startCancel context.CancelFunc
	closed      bool
	idleTimeout time.Duration
}

func NewPool(config ProcessConfig, gamesPerWorker int) (*Pool, error) {
	if gamesPerWorker < 2 || gamesPerWorker > 4 {
		return nil, errors.New("shared Forge capacity must be between 2 and 4")
	}
	config.Args = append([]string(nil), config.Args...)
	config.Env = append([]string(nil), config.Env...)
	return &Pool{config: config, capacity: gamesPerWorker, idleTimeout: time.Minute}, nil
}

func (pool *Pool) Acquire(ctx context.Context) (*Client, error) {
	for {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		pool.mu.Lock()
		if pool.closed {
			pool.mu.Unlock()
			return nil, ErrClosed
		}
		for _, entry := range pool.workers {
			if entry.worker.healthy() && entry.games < sharedWorkerGames && len(entry.leases) < pool.capacity {
				client := pool.lease(entry)
				pool.mu.Unlock()
				return client, nil
			}
		}
		if starting := pool.starting; starting != nil {
			pool.mu.Unlock()
			select {
			case <-starting:
				continue
			case <-ctx.Done():
				return nil, ctx.Err()
			}
		}
		starting := make(chan struct{})
		startCtx, cancel := context.WithCancel(ctx)
		pool.starting, pool.startCancel = starting, cancel
		pool.mu.Unlock()
		worker, err := startSharedWorker(startCtx, pool.config, pool.capacity)
		cancel()
		pool.mu.Lock()
		if err == nil && pool.closed {
			// Keep the startup barrier until the just-created child is reaped.
			pool.mu.Unlock()
			worker.kill()
			<-worker.done
			pool.mu.Lock()
			err = ErrClosed
		}
		var client *Client
		if err == nil {
			entry := &pooledWorker{worker: worker, leases: make(map[*Client]bool)}
			pool.workers = append(pool.workers, entry)
			client = pool.lease(entry)
			go pool.watch(entry)
		}
		pool.starting, pool.startCancel = nil, nil
		close(starting)
		pool.mu.Unlock()
		return client, err
	}
}

// lease and release keep slot ownership under pool.mu; Done closes only after
// native game cleanup is acknowledged or the entire worker has been reaped.
func (pool *Pool) lease(entry *pooledWorker) *Client {
	if entry.idle != nil {
		entry.idle.Stop()
		entry.idle = nil
	}
	client := &Client{done: make(chan struct{}), supportsAI: entry.worker.supportsAI, supportsReplay: entry.worker.supportsReplay}
	client.shared = &sharedLease{client: client, pool: pool, entry: entry, worker: entry.worker, gate: make(chan struct{}, 1)}
	entry.leases[client] = true
	entry.games++
	return client
}

func (pool *Pool) remove(entry *pooledWorker) {
	for i, existing := range pool.workers {
		if existing == entry {
			pool.workers = append(pool.workers[:i], pool.workers[i+1:]...)
			break
		}
	}
	if entry.idle != nil {
		entry.idle.Stop()
	}
}

func (pool *Pool) watch(entry *pooledWorker) {
	<-entry.worker.done
	pool.mu.Lock()
	pool.remove(entry)
	clients := make([]*Client, 0, len(entry.leases))
	for client := range entry.leases {
		clients = append(clients, client)
	}
	pool.mu.Unlock()
	for _, client := range clients {
		client.shared.finish()
	}
}

func (pool *Pool) release(entry *pooledWorker, client *Client) {
	pool.mu.Lock()
	defer pool.mu.Unlock()
	delete(entry.leases, client)
	if len(entry.leases) != 0 || !entry.worker.healthy() {
		return
	}
	if pool.closed || entry.games >= sharedWorkerGames {
		entry.worker.kill()
		return
	}
	entry.idle = time.AfterFunc(pool.idleTimeout, func() {
		pool.mu.Lock()
		defer pool.mu.Unlock()
		if len(entry.leases) == 0 {
			entry.worker.kill()
		}
	})
}

func (pool *Pool) Close() error {
	pool.mu.Lock()
	pool.closed = true
	if pool.startCancel != nil {
		pool.startCancel()
	}
	starting := pool.starting
	workers := append([]*pooledWorker(nil), pool.workers...)
	for _, entry := range workers {
		entry.worker.kill()
	}
	pool.mu.Unlock()
	if starting != nil {
		<-starting
	}
	for _, entry := range workers {
		<-entry.worker.done
	}
	return nil
}

type sharedLease struct {
	client    *Client
	pool      *Pool
	entry     *pooledWorker
	worker    *sharedWorker
	gate      chan struct{}
	finished  sync.Once
	sessionID string // protected by gate
	ended     bool   // protected by gate
}

func (lease *sharedLease) finish() {
	lease.finished.Do(func() {
		lease.pool.release(lease.entry, lease.client)
		close(lease.client.done)
	})
}

func (lease *sharedLease) call(ctx context.Context, request rpcRequest) (string, error) {
	select {
	case lease.gate <- struct{}{}:
	case <-ctx.Done():
		return "", ctx.Err()
	case <-lease.client.done:
		return "", ErrClosed
	}
	defer func() { <-lease.gate }()
	if !lease.client.Healthy() || lease.ended {
		return "", ErrClosed
	}
	if request.Command == "startGame" {
		if lease.sessionID != "" {
			return "", errors.New("Forge lease already owns a game")
		}
	} else if lease.sessionID == "" || request.SessionID != lease.sessionID {
		return "", errors.New("Forge request does not belong to this lease")
	}
	result, err := lease.worker.call(ctx, request)
	if err == nil && request.Command == "startGame" {
		var handle SessionHandle
		if json.Unmarshal([]byte(result), &handle) != nil || handle.SessionID == "" {
			// Without a valid handle we cannot target cleanup safely.
			lease.worker.kill()
			return "", ErrRuntime
		}
		lease.sessionID = handle.SessionID
	}
	if err == nil && (request.Command == "endGame" || request.Command == "abortGame") {
		lease.ended = true
	}
	if err != nil {
		switch request.Command {
		case "getSnapshot", "getPrompt", "getGameOver":
			lease.client.kill()
		}
	}
	return result, err
}

func (lease *sharedLease) close() error {
	client := lease.client
	client.closeOnce.Do(func() {
		client.closing.Store(true)
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		select {
		case lease.gate <- struct{}{}:
			if lease.worker.healthy() && !lease.ended && lease.sessionID != "" {
				_, client.closeErr = lease.worker.call(ctx, rpcRequest{Command: "abortGame", SessionID: lease.sessionID})
			}
			<-lease.gate
		case <-ctx.Done():
			client.closeErr = ctx.Err()
		case <-client.done:
			return
		}
		if client.closeErr != nil {
			lease.worker.kill()
		}
		if !lease.worker.healthy() {
			<-lease.worker.done
		}
		lease.finish()
	})
	return client.closeErr
}
