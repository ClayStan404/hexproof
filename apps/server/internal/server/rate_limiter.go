// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"sync"
	"time"
)

const maxRateLimitKeys = 4096

type fixedWindowEntry struct {
	start time.Time
	count int
}

// fixedWindowLimiter bounds both request frequency and the number of retained
// client identities. A full limiter fails closed for unseen identities until
// the next cleanup so churn cannot turn the map into unbounded server state.
type fixedWindowLimiter struct {
	mu          sync.Mutex
	window      time.Duration
	maxKeys     int
	nextCleanup time.Time
	entries     map[string]fixedWindowEntry
}

func newFixedWindowLimiter(window time.Duration, maxKeys int) *fixedWindowLimiter {
	return &fixedWindowLimiter{
		window:  window,
		maxKeys: maxKeys,
		entries: make(map[string]fixedWindowEntry),
	}
}

func (l *fixedWindowLimiter) allow(key string, now time.Time, limit int) bool {
	if limit <= 0 {
		return true
	}
	l.mu.Lock()
	defer l.mu.Unlock()

	if l.nextCleanup.IsZero() || !now.Before(l.nextCleanup) {
		for candidateKey, candidate := range l.entries {
			if now.Sub(candidate.start) >= l.window {
				delete(l.entries, candidateKey)
			}
		}
		l.nextCleanup = now.Add(l.window)
	}

	entry, exists := l.entries[key]
	if !exists && len(l.entries) >= l.maxKeys {
		return false
	}
	if !exists || entry.start.IsZero() || now.Sub(entry.start) >= l.window {
		entry = fixedWindowEntry{start: now}
	}
	if entry.count >= limit {
		l.entries[key] = entry
		return false
	}
	entry.count++
	l.entries[key] = entry
	return true
}
