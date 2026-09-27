// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package accounts

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"
)

func TestSlowWriteIsolatesAccountsAndPreservesCommit(t *testing.T) {
	s, err := Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	ctx := context.Background()
	one, err := s.Do(ctx, Request{Operation: "create", Name: "One", DeviceName: "Desktop"})
	if err != nil {
		t.Fatal(err)
	}
	two, err := s.Do(ctx, Request{Operation: "create", Name: "Two", DeviceName: "Desktop"})
	if err != nil {
		t.Fatal(err)
	}
	entered, release := make(chan struct{}), make(chan struct{})
	var once sync.Once
	unblock := func() { once.Do(func() { close(release) }) }
	t.Cleanup(unblock)
	s.saveRecord = func(r record) error { close(entered); <-release; return s.save(r) }
	writeCtx, cancelWrite := context.WithCancel(ctx)
	defer cancelWrite()
	done := make(chan error, 1)
	go func() {
		_, err := s.Do(writeCtx, Request{Operation: "rename", SessionToken: one.SessionToken, Name: "Renamed"})
		done <- err
	}()
	<-entered
	probe, cancel := context.WithTimeout(ctx, time.Second)
	defer cancel()
	checked, err := s.Do(probe, Request{Operation: "check", SessionToken: two.SessionToken})
	if err != nil || checked.Profile.ID != two.Profile.ID || len(checked.Devices) != 0 {
		t.Fatal("unrelated check blocked or returned device inventory", err)
	}
	waitCtx, cancelWait := context.WithCancel(ctx)
	cancelWait()
	if _, err := s.Do(waitCtx, Request{Operation: "check", SessionToken: one.SessionToken}); !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
	cancelWrite()
	unblock()
	if err := <-done; err != nil {
		t.Fatal("cancelled an already-started durable commit", err)
	}
	checked, err = s.Do(ctx, Request{Operation: "check", SessionToken: one.SessionToken})
	if err != nil || checked.Profile.Name != "Renamed" {
		t.Fatal("disk/memory commit diverged", err)
	}
}

func TestCancelledCreationDoesNotPersist(t *testing.T) {
	s, err := Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := s.Do(ctx, Request{Operation: "create", Name: "Cancelled", DeviceName: "Desktop"}); !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
	if len(s.records) != 0 || s.creating != 0 {
		t.Fatal("cancelled creation mutated the store")
	}
}
