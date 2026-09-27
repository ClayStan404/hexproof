// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package benchutil

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestPercentileUsesNearestRank(t *testing.T) {
	values := make([]time.Duration, 100)
	for i := range values {
		values[i] = time.Duration(i+1) * time.Millisecond
	}
	for _, percent := range []int{50, 95, 99, 100} {
		if got := percentile(values, percent); got != float64(percent) {
			t.Fatalf("p%d = %g", percent, got)
		}
	}
	if got := percentile([]time.Duration{time.Millisecond, 2 * time.Millisecond, 3 * time.Millisecond}, 50); got != 2 {
		t.Fatalf("odd sample median = %g", got)
	}
}

func TestStallDelaysOnlyOneCallAndCanBeCancelled(t *testing.T) {
	var stall Stall
	entered, release := stall.arm()
	defer release()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() { done <- stall.Wait(ctx) }()
	select {
	case <-entered:
	case <-time.After(time.Second):
		t.Fatal("stall was not entered")
	}
	second, cancelSecond := context.WithTimeout(context.Background(), time.Second)
	defer cancelSecond()
	if err := stall.Wait(second); err != nil {
		t.Fatal("second call was delayed", err)
	}
	cancel()
	select {
	case err := <-done:
		if !errors.Is(err, context.Canceled) {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("stall ignored cancellation")
	}
	release()
	release()
}
