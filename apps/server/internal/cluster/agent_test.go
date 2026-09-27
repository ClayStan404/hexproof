// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package cluster

import (
	"context"
	"errors"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

type agentTestService struct {
	Service
	operation        string
	block            atomic.Bool
	entered, release chan struct{}
	lateError        error
}

func (s *agentTestService) Do(ctx context.Context, q Request) (Result, error) {
	if q.Operation == s.operation && s.block.CompareAndSwap(true, false) {
		close(s.entered)
		select {
		case <-s.release:
		case <-ctx.Done():
			return Result{}, ctx.Err()
		}
		if s.lateError != nil {
			return Result{}, s.lateError
		}
	}
	return s.Service.Do(ctx, q)
}

func blockedAgent(t *testing.T, operation string, lateError error) (*Agent, *Coordinator, *agentTestService, func()) {
	t.Helper()
	coordinator, err := New(testConfig())
	if err != nil {
		t.Fatal(err)
	}
	service := &agentTestService{Service: coordinator, operation: operation,
		entered: make(chan struct{}), release: make(chan struct{}), lateError: lateError}
	agent := Start(service, "N1", report)
	t.Cleanup(agent.Close)
	var once sync.Once
	release := func() { once.Do(func() { close(service.release) }) }
	t.Cleanup(release)
	return agent, coordinator, service, release
}

func awaitAgentResult(t *testing.T, done <-chan error) error {
	t.Helper()
	select {
	case err := <-done:
		return err
	case <-time.After(time.Second):
		t.Fatal("unrelated or cancelled operation waited behind network I/O")
		return nil
	}
}

func TestAgentSlowRPCDoesNotBlockCacheOrIndependentRequests(t *testing.T) {
	for _, operation := range []string{"report", "view"} {
		t.Run(operation, func(t *testing.T) {
			a, _, service, release := blockedAgent(t, operation, nil)
			service.block.Store(true)
			slow := make(chan error, 1)
			go func() {
				if operation == "report" {
					slow <- a.Publish(context.Background(), "")
				} else {
					_, err := a.Do(context.Background(), Request{Operation: "view"})
					slow <- err
				}
			}()
			<-service.entered
			cached := make(chan error, 1)
			go func() {
				if !a.Capabilities().Forge {
					cached <- errors.New("lost cached capability")
					return
				}
				if !a.Status().Ready {
					cached <- errors.New("lost fresh report")
					return
				}
				cached <- nil
			}()
			if err := awaitAgentResult(t, cached); err != nil {
				t.Fatal(err)
			}
			ctx, cancel := context.WithCancel(context.Background())
			cancel()
			cancelled := make(chan error, 1)
			go func() { _, err := a.Do(ctx, Request{Operation: "view"}); cancelled <- err }()
			if err := awaitAgentResult(t, cancelled); !errors.Is(err, context.Canceled) {
				t.Fatal(err)
			}
			independent := make(chan error, 1)
			go func() { _, err := a.Do(context.Background(), Request{Operation: "view"}); independent <- err }()
			if err := awaitAgentResult(t, independent); err != nil {
				t.Fatal(err)
			}
			release()
			if err := awaitAgentResult(t, slow); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestAgentCancelledReportWaitAndCompletionRetry(t *testing.T) {
	a, _, service, release := blockedAgent(t, "report", nil)
	service.block.Store(true)
	slow := make(chan error, 1)
	go func() { slow <- a.Publish(context.Background(), "") }()
	<-service.entered
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := a.Publish(ctx, "completed-after-snapshot"); !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
	if a.Status().PendingCompletions != 1 {
		t.Fatal("lost committed completion on caller cancellation")
	}
	release()
	if err := awaitAgentResult(t, slow); err != nil {
		t.Fatal(err)
	}
	if err := a.Publish(context.Background(), ""); err != nil {
		t.Fatal(err)
	}
	if a.Status().PendingCompletions != 0 {
		t.Fatal("successful report retained completion")
	}
}

func TestAgentOldResponseCannotFenceReplacementRegistration(t *testing.T) {
	a, coordinator, service, release := blockedAgent(t, "view", ErrFenced)
	service.block.Store(true)
	slow := make(chan error, 1)
	go func() { _, err := a.Do(context.Background(), Request{Operation: "view"}); slow <- err }()
	<-service.entered
	coordinator.mu.Lock()
	coordinator.states = map[string]nodeState{}
	coordinator.mu.Unlock()
	if err := a.Publish(context.Background(), ""); err != ErrRegistration {
		t.Fatal(err)
	}
	if err := a.Publish(context.Background(), ""); err != nil {
		t.Fatal(err)
	}
	release()
	if err := awaitAgentResult(t, slow); err != ErrUnavailable {
		t.Fatal("accepted old registration reply", err)
	}
	if _, err := a.Do(context.Background(), Request{Operation: "view"}); err != nil {
		t.Fatal("old error fenced new registration", err)
	}
}

func TestAgentCloseCancelsInFlightCallerRPC(t *testing.T) {
	a, _, service, _ := blockedAgent(t, "view", nil)
	service.block.Store(true)
	slow := make(chan error, 1)
	go func() { _, err := a.Do(context.Background(), Request{Operation: "view"}); slow <- err }()
	<-service.entered
	a.Close()
	if err := awaitAgentResult(t, slow); !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
}
