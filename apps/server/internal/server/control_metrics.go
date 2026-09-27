// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"errors"
	"sync"
	"sync/atomic"
	"time"

	"hexproof/server/internal/accounts"
	"hexproof/server/internal/cluster"
	"hexproof/server/internal/syncutil"
)

// Only aggregate timings and fixed error categories are recorded. There are no
// account, room, credential, request-body, or unbounded message-type labels.
type timingSnapshot struct {
	Calls     uint64    `json:"calls"`
	Failed    uint64    `json:"failed"`
	Cancelled uint64    `json:"cancelled"`
	InFlight  int       `json:"inFlight"`
	TotalMS   float64   `json:"totalMs"`
	MaxMS     float64   `json:"maxMs"`
	Buckets   [7]uint64 `json:"buckets"`
	LastError string    `json:"lastError,omitempty"`
}

type operationTiming struct {
	mu    sync.Mutex
	state timingSnapshot
}

func (m *operationTiming) start() func(error) {
	started := time.Now()
	m.mu.Lock()
	m.state.InFlight++
	m.mu.Unlock()
	return func(err error) {
		elapsed := float64(time.Since(started)) / float64(time.Millisecond)
		m.mu.Lock()
		defer m.mu.Unlock()
		m.state.InFlight--
		m.state.Calls++
		m.state.TotalMS += elapsed
		m.state.MaxMS = max(m.state.MaxMS, elapsed)
		bucket := 6
		for i, limit := range [...]float64{10, 50, 100, 500, 1000, 5000} {
			if elapsed <= limit {
				bucket = i
				break
			}
		}
		m.state.Buckets[bucket]++
		m.state.LastError = controlErrorCategory(err)
		if err != nil {
			m.state.Failed++
			if errors.Is(err, context.Canceled) {
				m.state.Cancelled++
			}
		}
	}
}

func (m *operationTiming) snapshot() timingSnapshot {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.state
}

func controlErrorCategory(err error) string {
	switch {
	case err == nil:
		return ""
	case errors.Is(err, context.Canceled):
		return "cancelled"
	case errors.Is(err, context.DeadlineExceeded):
		return "timeout"
	case errors.Is(err, accounts.ErrInvalid), errors.Is(err, cluster.ErrInvalid):
		return "rejected"
	case errors.Is(err, accounts.ErrLimit), errors.Is(err, cluster.ErrFull):
		return "capacity"
	default:
		return "unavailable"
	}
}

type controlMetrics struct {
	accountRPC    operationTiming
	accountGate   operationTiming
	clusterView   operationTiming
	sendFailures  atomic.Uint64
	readinessGate syncutil.Gate
	lastProbe     time.Time // protected by readinessGate
	accountReady  bool
	accountError  string
}

func (h *Handler) lockAccount(ctx context.Context, id string) (func(), error) {
	finish := h.control.accountGate.start()
	release, err := h.accountLocks.Lock(ctx, id)
	finish(err)
	return release, err
}

// All session send paths use this boundary, including private projections and
// model workers that already have serialized payloads.
func (h *Handler) queueSessionMessage(sess *Session, data []byte) bool {
	if sess.trySend(data) {
		return true
	}
	h.control.sendFailures.Add(1)
	return false
}
