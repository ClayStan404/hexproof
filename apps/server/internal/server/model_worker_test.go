// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"encoding/json"
	"github.com/coder/websocket"
	"hexproof/server/internal/forgehost"
	"hexproof/server/internal/protocol"
	"strings"
	"testing"
	"time"
)

func TestModelWorkerCapabilityRoleIsolationAndRevocation(t *testing.T) {
	cfg := DefaultConfig()
	cfg.AllowPlayerHosting = true
	srv, h := newConfiguredTestServer(t, cfg)
	defer h.Close()
	host := dial(t, srv)
	defer host.close()
	var welcome protocol.SessionWelcome
	if err := host.hello("Human").DecodePayload(&welcome); err != nil {
		t.Fatal(err)
	}
	create, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{Name: "Model", Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatCustom, MatchMode: protocol.MatchBO1, RulesMode: protocol.RulesModeForge, HostingMode: protocol.HostingModePlayer, AISource: protocol.AISourceOnline, AllowSpectators: true})
	create.ID = "create"
	host.send(create)
	var grant protocol.RoomAIWorker
	if err := host.recvType(protocol.TypeRoomAIWorker).DecodePayload(&grant); err != nil {
		t.Fatal(err)
	}
	if grant.Source != protocol.AISourceOnline || len(grant.Token) != 64 {
		t.Fatal("invalid grant")
	}
	bind := func(token string, success bool) *websocket.Conn {
		t.Helper()
		ctx, cancel := context.WithTimeout(t.Context(), 2*time.Second)
		defer cancel()
		conn, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(srv.URL, "http")+"?ai=1", nil)
		if err != nil {
			t.Fatal(err)
		}
		env, _ := protocol.NewEnvelope(protocol.TypeAIAttach, protocol.AIAttach{RoomID: grant.RoomID, Token: token})
		raw, _ := env.Marshal()
		if err := conn.Write(ctx, websocket.MessageText, raw); err != nil {
			t.Fatal(err)
		}
		_, raw, err = conn.Read(ctx)
		if success {
			var attached protocol.Envelope
			if err != nil || json.Unmarshal(raw, &attached) != nil || attached.Type != protocol.TypeAIAttached {
				t.Fatalf("worker rejected: %v %s", err, raw)
			}
		} else if err == nil {
			t.Fatal("invalid worker authorized")
		}
		return conn
	}
	bind(forgehost.NewID(), false).CloseNow()
	worker := bind(grant.Token, true)
	defer worker.CloseNow()
	// The ordinary player role cannot reuse model worker messages.
	env, _ := protocol.NewEnvelope(protocol.TypeAIAnswer, protocol.AIAnswer{RequestID: "anything"})
	env.ID = "ordinary-ai"
	host.send(env)
	var failure protocol.ErrorPayload
	if err := host.recvType(protocol.TypeError).DecodePayload(&failure); err != nil || failure.Code != protocol.ErrInvalidMessage {
		t.Fatal("human role accepted AI answer")
	}
	// Spectator synchronization contains neither the host capability nor private decisions.
	spectator := dial(t, srv)
	defer spectator.close()
	spectator.hello("Observer")
	join, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: grant.RoomID, AsSpectator: true, AcceptPlayerHost: true})
	join.ID = "watch"
	spectator.send(join)
	ping, _ := protocol.NewEnvelope(protocol.TypeSessionPing, protocol.EmptyPayload{})
	ping.ID = "barrier"
	spectator.send(ping)
	for {
		env := spectator.recv()
		if env.Type == protocol.TypeRoomAIWorker || env.Type == protocol.TypeAIDecision || strings.Contains(string(env.Payload), grant.Token) {
			t.Fatal("worker capability leaked to spectator")
		}
		if env.Type == protocol.TypeSessionPong {
			break
		}
	}
	retry, _ := protocol.NewEnvelope(protocol.TypeRoomAIRetry, protocol.RoomAIRetry{})
	retry.ID = "spectator-retry"
	spectator.send(retry)
	if err := spectator.recvType(protocol.TypeError).DecodePayload(&failure); err != nil || failure.Code != protocol.ErrNotHost {
		t.Fatal("spectator retried model")
	}
	// Worker role cannot execute ordinary room commands, even with its token.
	ctx, cancel := context.WithTimeout(t.Context(), 2*time.Second)
	defer cancel()
	raw, _ := create.Marshal()
	if err := worker.Write(ctx, websocket.MessageText, raw); err != nil {
		t.Fatal(err)
	}
	if _, _, err := worker.Read(ctx); err == nil {
		t.Fatal("AI role accepted room.create")
	}
	worker.CloseNow()
	// Restoring the human session rotates its separate model capability.
	oldToken := grant.Token
	host.conn.CloseNow()
	deadline := time.Now().Add(2 * time.Second)
	for {
		h.resumeMu.Lock()
		_, held := h.resumeHolds[welcome.ResumeToken]
		h.resumeMu.Unlock()
		if held {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("human reconnect lease not created")
		}
		time.Sleep(time.Millisecond)
	}
	resumed := dial(t, srv)
	defer resumed.close()
	if got := resumed.resume("Human", welcome.ResumeToken, 0); !got.Resumed || !got.Host {
		t.Fatal("human could not resume model room")
	}
	if err := resumed.recvType(protocol.TypeRoomAIWorker).DecodePayload(&grant); err != nil {
		t.Fatal(err)
	}
	if grant.Token == oldToken {
		t.Fatal("resume retained stale worker capability")
	}
	bind(oldToken, false).CloseNow()
	replacement := bind(grant.Token, true)
	defer replacement.CloseNow()
	host = resumed
	leave, _ := protocol.NewEnvelope(protocol.TypeRoomLeave, protocol.EmptyPayload{})
	leave.ID = "leave"
	host.send(leave)
	host.recvType(protocol.TypeRoomDisbanded)
	host.send(ping)
	host.recvType(protocol.TypeSessionPong)
	h.modelMu.Lock()
	remaining := len(h.modelWorkers)
	h.modelMu.Unlock()
	if remaining != 0 {
		t.Fatal("room leave retained worker grant")
	}
	bind(grant.Token, false).CloseNow()
}
