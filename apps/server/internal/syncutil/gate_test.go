// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package syncutil

import (
	"context"
	"errors"
	"testing"
)

func TestKeyedGateIsolationCancellationAndRelease(t *testing.T) {
	var gates KeyedGate
	ctx := context.Background()
	first, err := gates.Lock(ctx, "first")
	if err != nil {
		t.Fatal(err)
	}
	second, err := gates.Lock(ctx, "second")
	if err != nil {
		t.Fatal(err)
	}
	second()
	cancelled, cancel := context.WithCancel(ctx)
	started, done := make(chan struct{}), make(chan error, 1)
	go func() {
		close(started)
		release, err := gates.Lock(cancelled, "first")
		if release != nil {
			release()
		}
		done <- err
	}()
	<-started
	cancel()
	if err := <-done; !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
	first()
	if len(gates.entries) != 0 {
		t.Fatal("idle identities retained")
	}
	release, err := gates.Lock(ctx, "first")
	if err != nil {
		t.Fatal(err)
	}
	release()
	if len(gates.entries) != 0 {
		t.Fatal("reused key retained")
	}
}
