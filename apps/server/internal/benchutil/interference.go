// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Package benchutil contains fixtures for opt-in control-plane benchmarks.
// Application packages must not depend on it outside benchmark/test files.
package benchutil

import (
	"context"
	"slices"
	"sync"
	"testing"
	"time"
)

const (
	Workers = 8
	Delay   = 20 * time.Millisecond
)

type pause struct {
	entered chan struct{}
	release chan struct{}
}

// Stall delays exactly the next matching dependency call. The benchmark starts
// the delay clock only after that call enters and the probe cohort is ready.
type Stall struct {
	mu   sync.Mutex
	next *pause
}

func (s *Stall) arm() (<-chan struct{}, func()) {
	p := &pause{entered: make(chan struct{}), release: make(chan struct{})}
	s.mu.Lock()
	s.next = p
	s.mu.Unlock()
	var once sync.Once
	return p.entered, func() { once.Do(func() { close(p.release) }) }
}

func (s *Stall) Wait(ctx context.Context) error {
	s.mu.Lock()
	p := s.next
	s.next = nil
	s.mu.Unlock()
	if p == nil {
		return nil
	}
	close(p.entered)
	select {
	case <-p.release:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

type sample struct {
	elapsed time.Duration
	err     error
}

func measure(ctx context.Context, call func(context.Context) error) sample {
	start := time.Now()
	err := call(ctx)
	return sample{time.Since(start), err}
}

func percentile(sorted []time.Duration, percent int) float64 {
	index := max(0, (len(sorted)*percent+99)/100-1)
	return float64(sorted[index]) / float64(time.Millisecond)
}

// Run measures a closed-loop burst: one stalled operation and eight probes.
// Each round drains fully. This measures interference, not saturation throughput
// or open-loop queuing; ns/op is per complete nine-request batch.
func Run(b *testing.B, stall *Stall, slow func(context.Context) error, probe func(context.Context, int) error) {
	b.Helper()
	if b.N > 1_000_000/Workers {
		b.Fatal("too many latency samples; reduce -benchtime")
	}
	probes := make([]sample, b.N*Workers)
	slowCalls := make([]sample, b.N)
	b.ResetTimer()
	for round := range b.N {
		func() {
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()
			entered, release := stall.arm()
			defer release()
			done := make(chan sample, 1)
			go func() { done <- measure(ctx, slow) }()
			select {
			case <-entered:
			case result := <-done:
				b.Fatalf("slow operation did not enter the injected stall: %v", result.err)
			case <-ctx.Done():
				b.Fatal("slow operation did not reach the injected stall")
			}
			start := make(chan struct{})
			var started time.Time // Published to all workers by closing start.
			var ready, finished sync.WaitGroup
			ready.Add(Workers)
			finished.Add(Workers)
			for worker := range Workers {
				go func() {
					defer finished.Done()
					ready.Done()
					<-start
					err := probe(ctx, worker)
					probes[round*Workers+worker] = sample{time.Since(started), err}
				}()
			}
			ready.Wait()
			started = time.Now()
			timer := time.AfterFunc(Delay, release)
			defer timer.Stop()
			close(start)
			finished.Wait()
			slowCalls[round] = <-done
		}()
	}
	b.StopTimer()
	b.ReportMetric(float64(Delay)/float64(time.Millisecond), "stall-ms")
	b.ReportMetric(Workers, "probes/batch")
	b.ReportMetric(float64(b.N*(Workers+1))/b.Elapsed().Seconds(), "cohort-requests/s")
	for _, group := range []struct {
		name    string
		samples []sample
	}{{"probe", probes}, {"slow", slowCalls}} {
		latencies := make([]time.Duration, len(group.samples))
		failures := 0
		var firstError error
		for i, result := range group.samples {
			latencies[i] = result.elapsed
			if result.err != nil {
				failures++
				if firstError == nil {
					firstError = result.err
				}
			}
		}
		slices.Sort(latencies)
		b.ReportMetric(percentile(latencies, 50), group.name+"-p50-ms")
		b.ReportMetric(percentile(latencies, 95), group.name+"-p95-ms")
		b.ReportMetric(percentile(latencies, 99), group.name+"-p99-ms")
		b.ReportMetric(percentile(latencies, 100), group.name+"-max-ms")
		b.ReportMetric(float64(failures)*100/float64(len(group.samples)), group.name+"-fail-%")
		if failures != 0 {
			b.Errorf("%s: %d/%d operations failed; first error: %v", group.name, failures, len(group.samples), firstError)
		}
	}
}
