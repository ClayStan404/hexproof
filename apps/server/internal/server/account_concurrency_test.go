// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"sync"
	"testing"
	"time"

	"hexproof/server/internal/accounts"
	"hexproof/server/internal/protocol"
)

type accountGateService struct {
	slow             string
	entered, release chan struct{}
	calls            chan context.Context
}

func (s *accountGateService) Do(ctx context.Context, q accounts.Request) (accounts.Result, error) {
	if s.calls != nil {
		s.calls <- ctx
	}
	if q.SessionToken == s.slow {
		close(s.entered)
		select {
		case <-s.release:
		case <-ctx.Done():
			return accounts.Result{}, ctx.Err()
		}
	}
	return accounts.Result{Profile: accounts.Profile{ID: q.SessionToken}}, nil
}

func accountGateSession(id string) *Session {
	s := &Session{ConnectionID: id, DisplayName: "Player", Send: make(chan []byte, 4)}
	s.setAccount(accountBinding{ID: id, Token: id})
	return s
}

func TestAccountAdmissionDoesNotShareHashBuckets(t *testing.T) {
	h := NewHandler()
	t.Cleanup(func() { h.Close() })
	seen := map[byte]string{}
	var first, second string
	for i := 0; i < 257; i++ {
		id := fmt.Sprintf("%032x", i)
		bucket := sha256.Sum256([]byte(id))[0]
		if previous, ok := seen[bucket]; ok {
			first, second = previous, id
			break
		}
		seen[bucket] = id
	}
	service := &accountGateService{slow: first, entered: make(chan struct{}), release: make(chan struct{})}
	var once sync.Once
	release := func() { once.Do(func() { close(service.release) }) }
	t.Cleanup(release)
	h.accounts = service
	a, b := accountGateSession(first), accountGateSession(second)
	h.accountConnections[first], h.accountConnections[second] = a, b
	env := protocol.Envelope{Type: protocol.TypeSessionPing}
	slow, fast := make(chan error, 1), make(chan error, 1)
	go func() { slow <- h.dispatch(context.Background(), nil, a, env) }()
	<-service.entered
	go func() { fast <- h.dispatch(context.Background(), nil, b, env) }()
	select {
	case err := <-fast:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("unrelated account waited behind slow authority")
	}
	release()
	if err := <-slow; err != nil {
		t.Fatal(err)
	}
}

func TestDispatchCancellationReachesAuthorityAndSkipsAdmission(t *testing.T) {
	h := NewHandler()
	t.Cleanup(func() { h.Close() })
	service := &accountGateService{slow: "owner", entered: make(chan struct{}), release: make(chan struct{}), calls: make(chan context.Context, 4)}
	h.accounts = service
	s := accountGateSession("owner")
	h.accountConnections["owner"] = s
	env := protocol.Envelope{Type: protocol.TypeSessionPing}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- h.dispatch(ctx, nil, s, env) }()
	<-service.entered
	downstream := <-service.calls
	cancel()
	select {
	case <-downstream.Done():
	case <-time.After(time.Second):
		t.Fatal("authority did not observe request cancellation")
	}
	<-done
	if err := h.dispatch(ctx, nil, s, env); !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
	select {
	case <-service.calls:
		t.Fatal("already-cancelled dispatch called authority")
	default:
	}
}
