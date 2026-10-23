// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
)

func relayFixture(t *testing.T, delay time.Duration) (*websocket.Conn, <-chan struct{}, <-chan string) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	received := make(chan string, 8)
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		connection, err := websocket.Accept(w, r, nil)
		if err != nil {
			return
		}
		defer connection.CloseNow()
		for {
			kind, payload, err := connection.Read(ctx)
			if err != nil {
				return
			}
			received <- string(payload)
			if connection.Write(ctx, kind, payload) != nil {
				return
			}
		}
	}))
	done := make(chan struct{})
	proxy := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer close(done)
		relay(ctx, w, r, "ws"+strings.TrimPrefix(backend.URL, "http"), delay)
	}))
	t.Cleanup(func() {
		cancel()
		proxy.Close()
		backend.Close()
	})
	connection, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(proxy.URL, "http"), nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { connection.CloseNow() })
	return connection, done, received
}

func TestRelayDelaysOnlyFirstSubmissionAndPreservesFrames(t *testing.T) {
	const delay = 200 * time.Millisecond
	connection, _, _ := relayFixture(t, delay)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	for index, frame := range []struct {
		kind    websocket.MessageType
		payload string
	}{
		{websocket.MessageBinary, "unchanged binary frame"},
		{websocket.MessageText, `{"type":"limited.submit_deck","mainboardInstanceIds":["one"]}`},
		{websocket.MessageText, `{"type":"limited.submit_deck","mainboardInstanceIds":["two"]}`},
	} {
		started := time.Now()
		if err := connection.Write(ctx, frame.kind, []byte(frame.payload)); err != nil {
			t.Fatal(err)
		}
		kind, payload, err := connection.Read(ctx)
		if err != nil {
			t.Fatal(err)
		}
		elapsed := time.Since(started)
		if kind != frame.kind || string(payload) != frame.payload {
			t.Fatalf("frame %d changed: %v %q", index, kind, payload)
		}
		if index == 1 && elapsed < delay {
			t.Fatalf("first submission reply arrived too early: %s", elapsed)
		}
		if index != 1 && elapsed >= delay {
			t.Fatalf("ordinary or later reply was delayed: frame %d took %s", index, elapsed)
		}
	}
}

func TestRelayDisconnectCancelsPendingDelay(t *testing.T) {
	connection, done, received := relayFixture(t, time.Minute)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if err := connection.Write(ctx, websocket.MessageText, []byte(`{"type":"limited.submit_deck"}`)); err != nil {
		t.Fatal(err)
	}
	select {
	case <-received:
	case <-ctx.Done():
		t.Fatal("submission did not reach the backend")
	}
	connection.CloseNow()
	select {
	case <-done:
	case <-ctx.Done():
		t.Fatal("relay remained blocked in the reply delay after disconnect")
	}
}
