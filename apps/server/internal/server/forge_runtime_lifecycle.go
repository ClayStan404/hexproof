// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"hexproof/server/internal/rulesengine/forge"
)

const forgeRestartCooldown = time.Second

var errForgeCapacity = errors.New("Forge game capacity is full")

// forgeRuntimeLifecycle owns runtime admission, process leases and shutdown.
// mu also protects Handler's game/player-host registries: changing a binding and
// its runtime ownership must remain one critical section. Locked helpers never
// acquire a room lock or perform process I/O, preserving the existing lock order.
type forgeRuntimeLifecycle struct {
	mu           sync.Mutex
	config       *forge.ProcessConfig
	pool         *forge.Pool
	nativeAI     bool
	nativeDuelAI bool
	maxGames     int
	clients      map[forge.Runtime]struct{}
	reservations map[string]forge.Runtime
	closed       bool
	starting     chan struct{}
	startCancel  context.CancelFunc
	retryAfter   time.Time
}

func newForgeRuntimeLifecycle(config Config) (*forgeRuntimeLifecycle, error) {
	var runtimeConfig *forge.ProcessConfig
	var forgeNativeAI, forgeNativeDuelAI bool
	var forgePool *forge.Pool
	if config.ForgeRuntime != nil {
		var probe *forge.Client
		var probeErr error
		if config.ForgeGamesPerJVM > 1 {
			forgePool, probeErr = forge.NewPool(*config.ForgeRuntime, config.ForgeGamesPerJVM)
			if probeErr == nil {
				probe, probeErr = forgePool.Acquire(context.Background())
			}
		} else {
			probe, probeErr = forge.Start(context.Background(), *config.ForgeRuntime)
		}
		if probeErr != nil {
			if forgePool != nil {
				_ = forgePool.Close()
			}
			return nil, fmt.Errorf("configure Forge runtime: %w", probeErr)
		}
		forgeNativeAI = probe.SupportsAI()
		forgeNativeDuelAI = probe.SupportsDuelAI()
		if closeErr := probe.Close(); closeErr != nil {
			if forgePool != nil {
				_ = forgePool.Close()
			}
			return nil, fmt.Errorf("close Forge runtime probe: %w", closeErr)
		}
		copy := *config.ForgeRuntime
		copy.Args = append([]string(nil), config.ForgeRuntime.Args...)
		copy.Env = append([]string(nil), config.ForgeRuntime.Env...)
		runtimeConfig = &copy
	}
	return &forgeRuntimeLifecycle{
		config: runtimeConfig, pool: forgePool,
		nativeAI: forgeNativeAI, nativeDuelAI: forgeNativeDuelAI,
		maxGames:     config.MaxForgeGames,
		clients:      make(map[forge.Runtime]struct{}),
		reservations: make(map[string]forge.Runtime),
	}, nil
}

func (f *forgeRuntimeLifecycle) capabilities() (rules, ai, duelAI bool) {
	if f == nil {
		return false, false, false
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	rules = !f.closed && f.config != nil && !time.Now().Before(f.retryAfter)
	return rules, rules && f.nativeAI, rules && f.nativeAI && f.nativeDuelAI
}

func (f *forgeRuntimeLifecycle) occupied() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.occupiedLocked()
}

// The room/hosting coordinator holds mu when changing an associated binding.
func (f *forgeRuntimeLifecycle) trackLocked(client forge.Runtime) {
	f.clients[client] = struct{}{}
}

func (f *forgeRuntimeLifecycle) forgetLocked(client forge.Runtime) {
	delete(f.clients, client)
}

func (f *forgeRuntimeLifecycle) acceptsGameLocked(client forge.Runtime) bool {
	_, tracked := f.clients[client]
	return !f.closed && tracked && client.Healthy()
}

func (f *forgeRuntimeLifecycle) reserveLocked(roomID string, client forge.Runtime) {
	if _, local := client.(*forge.Client); local {
		f.reservations[roomID] = client
	}
}

func (f *forgeRuntimeLifecycle) releaseReservationLocked(roomID string) {
	delete(f.reservations, roomID)
}

// start reserves an isolated game lease: a fresh process by
// default, or a slot in an explicitly configured shared worker. Serialize
// admission/cold startups while established games run independently.
func (f *forgeRuntimeLifecycle) start(ctx context.Context, roomID string, dedicated bool, onExit func(forge.Runtime)) (*forge.Client, error) {
	for {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		f.mu.Lock()
		if f.closed || f.config == nil || time.Now().Before(f.retryAfter) {
			f.mu.Unlock()
			return nil, errForgeRuntimeUnavailable
		}
		// Reserve capacity before spawning Java. A process remains charged
		// until Wait has reaped it, even if it is unhealthy or closing. Check
		// Done directly so a next game need not wait for its old watcher.
		occupied := f.occupiedLocked()
		if previous, reserved := f.reservations[roomID]; reserved {
			// Keep the same match's slot across sideboarding/restart, but
			// never overlap its previous JVM with the replacement.
			select {
			case <-previous.Done():
				occupied--
			default:
				f.mu.Unlock()
				select {
				case <-previous.Done():
					continue
				case <-ctx.Done():
					return nil, ctx.Err()
				}
			}
		}
		if occupied >= f.maxGames {
			f.mu.Unlock()
			return nil, errForgeCapacity
		}
		if starting := f.starting; starting != nil {
			f.mu.Unlock()
			select {
			case <-starting:
				continue
			case <-ctx.Done():
				return nil, ctx.Err()
			}
		}
		starting := make(chan struct{})
		delete(f.reservations, roomID)
		f.starting = starting
		startCtx, cancel := context.WithCancel(ctx)
		f.startCancel = cancel
		config := *f.config
		f.mu.Unlock()

		var client *forge.Client
		var err error
		if f.pool != nil && !dedicated {
			client, err = f.pool.Acquire(startCtx)
		} else {
			client, err = forge.Start(startCtx, config)
		}
		cancel()
		f.mu.Lock()
		closed := f.closed
		if err == nil && !closed && client.Healthy() {
			f.clients[client] = struct{}{}
			go onExit(client)
		} else {
			if err == nil {
				err = errForgeRuntimeUnavailable
			}
			f.retryAfter = time.Now().Add(forgeRestartCooldown)
		}
		if err != nil && client != nil {
			// Close must not return while a canceled startup still owns a
			// child. Keep the single-flight notification open until cleanup.
			f.mu.Unlock()
			_ = client.Close()
			f.mu.Lock()
		}
		f.starting = nil
		f.startCancel = nil
		close(starting)
		f.mu.Unlock()
		if err != nil {
			return nil, fmt.Errorf("%w: %w", errForgeRuntimeUnavailable, err)
		}
		return client, nil
	}
}

// Caller holds mu. Count each live/cold/reserved lease exactly once.
func (f *forgeRuntimeLifecycle) occupiedLocked() int {
	occupied := len(f.reservations)
	reservedClients := make(map[forge.Runtime]bool, occupied)
	for _, client := range f.reservations {
		reservedClients[client] = true
	}
	for client := range f.clients {
		if _, local := client.(*forge.Client); !local {
			continue
		}
		if reservedClients[client] {
			continue
		}
		select {
		case <-client.Done():
		default:
			occupied++
		}
	}
	if f.starting != nil {
		occupied++
	}
	return occupied
}

// beginCloseLocked fences new starts and detaches all owned leases atomically
// with Handler's game/player-host registries. The caller releases mu and closes
// player links before waiting, so relay shutdown cannot depend on this lock.
func (f *forgeRuntimeLifecycle) beginCloseLocked() forgeRuntimeShutdown {
	f.closed = true
	if f.startCancel != nil {
		f.startCancel()
	}
	shutdown := forgeRuntimeShutdown{starting: f.starting, clients: f.clients, pool: f.pool}
	f.clients = make(map[forge.Runtime]struct{})
	f.reservations = make(map[string]forge.Runtime)
	return shutdown
}

type forgeRuntimeShutdown struct {
	starting <-chan struct{}
	clients  map[forge.Runtime]struct{}
	pool     *forge.Pool
}

func (s forgeRuntimeShutdown) wait() error {
	if s.starting != nil {
		<-s.starting
	}
	var children sync.WaitGroup
	results := make(chan error, len(s.clients))
	for client := range s.clients {
		children.Add(1)
		go func() {
			defer children.Done()
			results <- client.Close()
		}()
	}
	children.Wait()
	close(results)
	var closeErr error
	for err := range results {
		closeErr = errors.Join(closeErr, err)
	}
	if s.pool != nil {
		closeErr = errors.Join(closeErr, s.pool.Close())
	}
	return closeErr
}
