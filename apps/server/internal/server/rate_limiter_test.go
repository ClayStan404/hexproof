// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"testing"
	"time"
)

func TestFixedWindowLimiterResetsAndSeparatesKeys(t *testing.T) {
	t.Parallel()
	limiter := newFixedWindowLimiter(time.Minute, 8)
	now := time.Unix(1_700_000_000, 0)

	if !limiter.allow("first", now, 2) ||
		!limiter.allow("first", now.Add(time.Second), 2) {
		t.Fatal("expected first two requests to pass")
	}
	if limiter.allow("first", now.Add(2*time.Second), 2) {
		t.Fatal("expected the third request in one window to be denied")
	}
	if !limiter.allow("second", now.Add(2*time.Second), 2) {
		t.Fatal("expected an independent key to have its own budget")
	}
	if !limiter.allow("first", now.Add(time.Minute), 2) {
		t.Fatal("expected an expired window to reset")
	}
}

func TestFixedWindowLimiterBoundsRetainedKeys(t *testing.T) {
	t.Parallel()
	limiter := newFixedWindowLimiter(time.Minute, 2)
	now := time.Unix(1_700_000_000, 0)
	if !limiter.allow("first", now, 1) || !limiter.allow("second", now, 1) {
		t.Fatal("expected entries within the bound to pass")
	}
	if limiter.allow("third", now, 1) {
		t.Fatal("expected an unseen key to fail closed when the map is full")
	}
	if !limiter.allow("third", now.Add(time.Minute), 1) {
		t.Fatal("expected cleanup to admit a new key")
	}
	if got := len(limiter.entries); got > limiter.maxKeys {
		t.Fatalf("retained %d keys, limit is %d", got, limiter.maxKeys)
	}
}
