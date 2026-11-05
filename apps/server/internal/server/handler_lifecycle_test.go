// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"errors"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"hexproof/server/internal/rulesengine/forge"
)

type shutdownTestRuntime struct {
	forge.Runtime
	close func() error
}

func (r *shutdownTestRuntime) Close() error { return r.close() }

func TestHandlerConcurrentCloseWaitsForAllRuntimeCleanup(t *testing.T) {
	h := NewHandler()
	started := make(chan struct{}, 2)
	release := make(chan struct{})
	var releaseOnce sync.Once
	unblock := func() { releaseOnce.Do(func() { close(release) }) }
	t.Cleanup(func() {
		unblock()
		_ = h.Close()
	})
	h.forge.mu.Lock()
	h.forge.config = &forge.ProcessConfig{}
	h.forge.mu.Unlock()
	wantErr := errors.New("runtime cleanup failed")
	var calls atomic.Int32
	for _, closeErr := range []error{nil, wantErr} {
		client := &shutdownTestRuntime{close: func() error {
			calls.Add(1)
			// Runtime cleanup may consult lifecycle state; shutdown must not
			// hold the registry mutex across runtime I/O.
			if rules, ai, duelAI := h.forge.capabilities(); rules || ai || duelAI {
				t.Error("shutdown advertised an available runtime")
			}
			started <- struct{}{}
			<-release
			return closeErr
		}}
		h.forge.mu.Lock()
		h.forge.trackLocked(client)
		h.forge.mu.Unlock()
	}
	const callers = 4
	results := make(chan error, callers)
	for range callers {
		go func() { results <- h.Close() }()
	}
	for range 2 {
		select {
		case <-started:
		case <-time.After(2 * time.Second):
			t.Fatal("shutdown did not start independent runtime cleanup")
		}
	}
	select {
	case <-results:
		t.Fatal("Close returned before runtime cleanup completed")
	default:
	}
	unblock()
	for range callers {
		select {
		case err := <-results:
			if !errors.Is(err, wantErr) {
				t.Fatalf("concurrent Close lost the cleanup error: %v", err)
			}
		case <-time.After(2 * time.Second):
			t.Fatal("Close did not complete after runtime cleanup")
		}
	}
	if got := calls.Load(); got != 2 {
		t.Fatalf("runtime cleanup ran %d times; want one call per runtime", got)
	}
}
