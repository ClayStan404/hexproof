// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package cluster

import (
	"context"
	"sync"
	"time"
)

// Agent serializes reports and reservation completion. A completed ticket is
// released only with a snapshot taken after its domain operation has finished.
// A replaced node is fenced until an operator restarts it; it must not fight
// the replacement for ownership by repeatedly registering the same node ID.
type Agent struct {
	reportSequence     uint64
	mu                 sync.Mutex
	service            Service
	nodeID, generation string
	fenced             bool
	snapshot           func() Report
	completed          []string
	cancel             context.CancelFunc
	done               chan struct{}
	capabilities       Result
}

func Start(service Service, nodeID string, snapshot func() Report) *Agent {
	ctx, cancel := context.WithCancel(context.Background())
	a := &Agent{service: service, nodeID: nodeID, snapshot: snapshot, cancel: cancel, done: make(chan struct{})}
	_ = a.Publish(ctx, "")
	go func() {
		defer close(a.done)
		ticker := time.NewTicker(2 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				_ = a.Publish(ctx, "")
			}
		}
	}()
	return a
}

func (a *Agent) Close() { a.cancel(); <-a.done }

func (a *Agent) request(ctx context.Context, q Request) (Result, error) {
	if a.fenced {
		return Result{}, ErrFenced
	}
	if a.generation == "" {
		out, err := a.service.Do(ctx, Request{Operation: "register", NodeID: a.nodeID})
		if err != nil {
			return Result{}, err
		}
		a.generation = out.Generation
	}
	q.NodeID, q.Generation = a.nodeID, a.generation
	out, err := a.service.Do(ctx, q)
	if err == ErrFenced {
		a.fenced = true
	}
	if err == ErrRegistration {
		a.generation = ""
	}
	return out, err
}

func (a *Agent) Publish(ctx context.Context, completed string) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	if completed != "" {
		a.completed = append(a.completed, completed)
	}
	// Tokens have a short lifetime; bound the retry queue during an outage.
	if len(a.completed) > 2048 {
		a.completed = a.completed[len(a.completed)-2048:]
	}
	a.reportSequence++
	r := a.snapshot()
	out, err := a.request(ctx, Request{Operation: "report", ReportSequence: a.reportSequence, Report: &r, Completed: a.completed})
	if err == nil {
		a.completed = nil
		a.capabilities = out
	}
	return err
}

func (a *Agent) Do(ctx context.Context, q Request) (Result, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	// Register/report is owned by Publish. New requests cannot silently use a
	// registration without a health/capacity snapshot after coordinator restart.
	if a.generation == "" || a.fenced {
		return Result{}, ErrUnavailable
	}
	return a.request(ctx, q)
}

func (a *Agent) Capabilities() Result {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.capabilities
}
