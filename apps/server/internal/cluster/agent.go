// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package cluster

import (
	"context"
	"log/slog"
	"sync"
	"time"

	"hexproof/server/internal/syncutil"
)

const agentRequestTimeout = 3 * time.Second
const maxAgentRequests = 8

// Agent orders reports and completed reservations while independent RPCs and
// cached capability reads remain independent of report/network latency.
// Registration is owned by publication; a fenced process never re-registers.
type Agent struct {
	mu                   sync.Mutex
	publishGate          syncutil.Gate
	service              Service
	nodeID, generation   string
	reported, fenced     bool
	snapshot             func() Report
	reportSequence       uint64
	lastReportedSequence uint64
	completed            map[string]struct{}
	capabilities         Result
	ctx                  context.Context
	cancel               context.CancelFunc
	done, wake           chan struct{}
	slots                chan struct{}
	lastReport           time.Time
	lastReportError      string
	reportFailures       uint64
}

func Start(service Service, nodeID string, snapshot func() Report) *Agent {
	ctx, cancel := context.WithCancel(context.Background())
	a := &Agent{service: service, nodeID: nodeID, snapshot: snapshot, ctx: ctx,
		cancel: cancel, done: make(chan struct{}), wake: make(chan struct{}, 1),
		slots: make(chan struct{}, maxAgentRequests), completed: make(map[string]struct{})}
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
			case <-a.wake:
			}
			_ = a.Publish(ctx, "")
		}
	}()
	return a
}

func (a *Agent) Close() { a.cancel(); <-a.done }

func (a *Agent) requestContext(parent context.Context) (context.Context, func()) {
	ctx, cancel := context.WithTimeout(parent, agentRequestTimeout)
	stop := context.AfterFunc(a.ctx, cancel)
	if a.ctx.Err() != nil {
		cancel()
	}
	return ctx, func() { stop(); cancel() }
}

// Complete queues committed work independently of a departed player's context.
// The publisher snapshots state only after the token has entered this queue.
func (a *Agent) Complete(token string) {
	a.mu.Lock()
	if token != "" && len(a.completed) < 2048 {
		a.completed[token] = struct{}{}
	}
	a.mu.Unlock()
	select {
	case a.wake <- struct{}{}:
	default:
	}
}

// acceptResult rejects replies belonging to a registration that has since
// become invalid. A delayed response can never fence a newer registration.
func (a *Agent) acceptResult(generation string, err error) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.generation != generation || a.fenced {
		return ErrUnavailable
	}
	switch err {
	case ErrFenced:
		a.fenced = true
		a.reported = false
	case ErrRegistration:
		a.generation = ""
		a.reported = false
	}
	return err
}

func (a *Agent) Publish(parent context.Context, completed string) error {
	return a.publish(parent, completed, nil)
}

// Refresh shares a publication with concurrent readers only if its snapshot
// started after this read. Local read-after-write discovery remains immediate.
func (a *Agent) Refresh(ctx context.Context) error {
	a.mu.Lock()
	observed := a.reportSequence
	a.mu.Unlock()
	return a.publish(ctx, "", &observed)
}

func (a *Agent) publish(parent context.Context, completed string, observed *uint64) (err error) {
	if completed != "" {
		a.Complete(completed)
	}
	ctx, cancel := a.requestContext(parent)
	defer cancel()
	if err = a.publishGate.Lock(ctx); err != nil {
		return err
	}
	defer a.publishGate.Unlock()
	defer func() { a.recordPublication(err) }()
	a.mu.Lock()
	generation, fenced := a.generation, a.fenced
	refreshed := observed != nil && a.reported && a.lastReportedSequence > *observed
	a.mu.Unlock()
	if fenced {
		return ErrFenced
	}
	if refreshed {
		return nil
	}
	if generation == "" {
		out, callErr := a.service.Do(ctx, Request{Operation: "register", NodeID: a.nodeID})
		if callErr != nil {
			return callErr
		}
		if ctx.Err() != nil {
			return ctx.Err()
		}
		generation = out.Generation
		a.mu.Lock()
		a.generation, a.reported = generation, false
		a.mu.Unlock()
	}
	a.mu.Lock()
	a.reportSequence++
	sequence := a.reportSequence
	sent := make([]string, 0, len(a.completed))
	for token := range a.completed {
		sent = append(sent, token)
	}
	a.mu.Unlock()
	report := a.snapshot()
	if err = ctx.Err(); err != nil {
		return err
	}
	out, callErr := a.service.Do(ctx, Request{Operation: "report", NodeID: a.nodeID,
		Generation: generation, ReportSequence: sequence, Report: &report, Completed: sent})
	if err = a.acceptResult(generation, callErr); err != nil {
		return err
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	// Another concurrent RPC may have invalidated this generation meanwhile.
	if a.generation != generation || a.fenced {
		return ErrUnavailable
	}
	for _, token := range sent {
		delete(a.completed, token)
	}
	a.capabilities, a.reported = out, true
	a.lastReportedSequence = sequence
	a.lastReport = time.Now()
	return nil
}

func (a *Agent) Do(parent context.Context, q Request) (Result, error) {
	ctx, cancel := a.requestContext(parent)
	defer cancel()
	if err := ctx.Err(); err != nil {
		return Result{}, err
	}
	select {
	case a.slots <- struct{}{}:
		defer func() { <-a.slots }()
	case <-ctx.Done():
		return Result{}, ctx.Err()
	}
	if err := ctx.Err(); err != nil {
		return Result{}, err
	}
	a.mu.Lock()
	generation, ready := a.generation, a.reported && !a.fenced
	a.mu.Unlock()
	if generation == "" || !ready {
		return Result{}, ErrUnavailable
	}
	q.NodeID, q.Generation = a.nodeID, generation
	out, err := a.service.Do(ctx, q)
	if err = a.acceptResult(generation, err); err != nil {
		return Result{}, err
	}
	return out, nil
}

func (a *Agent) Capabilities() Result {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.capabilities
}

// Status contains bounded operational metadata, never resources or credentials.
type Status struct {
	Ready              bool      `json:"ready"`
	LastReport         time.Time `json:"lastReport,omitempty"`
	LastError          string    `json:"lastError,omitempty"`
	ReportFailures     uint64    `json:"reportFailures"`
	InFlight           int       `json:"inFlight"`
	PendingCompletions int       `json:"pendingCompletions"`
}

func (a *Agent) Status() Status {
	a.mu.Lock()
	defer a.mu.Unlock()
	return Status{Ready: a.reported && !a.fenced && a.ctx.Err() == nil &&
		time.Since(a.lastReport) < NodeLifetime, LastReport: a.lastReport,
		LastError: a.lastReportError, ReportFailures: a.reportFailures,
		InFlight: len(a.slots), PendingCompletions: len(a.completed)}
}

func (a *Agent) recordPublication(err error) {
	category := ""
	if err != nil {
		category = "unavailable"
		switch err {
		case ErrFenced:
			category = "fenced"
		case ErrRegistration:
			category = "registration_required"
		case context.Canceled:
			category = "cancelled"
		case context.DeadlineExceeded:
			category = "timeout"
		}
	}
	a.mu.Lock()
	changed := a.lastReportError != category
	a.lastReportError = category
	if err != nil {
		a.reportFailures++
	}
	a.mu.Unlock()
	if changed && category != "cancelled" {
		if category == "" {
			slog.Info("cluster publication recovered")
		} else {
			slog.Warn("cluster publication failed", "category", category)
		}
	}
}
