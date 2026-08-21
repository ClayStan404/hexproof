// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"testing"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func newCriticalErrorRoom(t *testing.T, h *Handler,
	allowSpectators bool) (*room.Room, *Session) {
	t.Helper()
	host := &Session{
		ConnectionID: "host-conn",
		DisplayName:  "Alice",
		RemoteIP:     "127.0.0.1",
		Send:         make(chan []byte, 8),
	}
	r, _, _, operation, err := h.hub.CreateRoom(
		"Critical error room", protocol.FormatModern, protocol.MatchBO1,
		protocol.CardLoadPreload, 2, allowSpectators, "", host)
	if err != nil {
		t.Fatalf("CreateRoom: %v", err)
	}
	operation.opMu.Unlock()
	return r, host
}

func joinCriticalSession(t *testing.T, h *Handler, r *room.Room,
	sess *Session, asSpectator bool) {
	t.Helper()
	operation, err := h.hub.beginJoin(r.ID, "")
	if err != nil {
		t.Fatalf("beginJoin: %v", err)
	}
	_, _, err = h.hub.joinRoom(operation, sess, asSpectator)
	operation.opMu.Unlock()
	if err != nil {
		t.Fatalf("joinRoom: %v", err)
	}
}

func criticalCommandEnvelope(t *testing.T, messageType, id string,
	payload any) protocol.Envelope {
	t.Helper()
	envelope, err := protocol.NewEnvelope(messageType, payload)
	if err != nil {
		t.Fatalf("NewEnvelope(%s): %v", messageType, err)
	}
	envelope.ID = id
	return envelope
}

func assertCriticalWireError(t *testing.T, payload protocol.ErrorPayload,
	code, message string) {
	t.Helper()
	if payload.Code != code || payload.Message != message {
		t.Fatalf("wire error = %#v, want code=%q message=%q", payload, code, message)
	}
}

func TestCriticalRoomErrorsUseStableWireMessages(t *testing.T) {
	t.Run("spectator limit", func(t *testing.T) {
		h := NewHandler()
		r, _ := newCriticalErrorRoom(t, h, true)
		for index := 0; index < protocol.MaxSpectators; index++ {
			joinCriticalSession(t, h, r, &Session{
				ConnectionID: "spectator-" + string(rune('a'+index)),
				DisplayName:  "Watcher",
				RemoteIP:     "127.0.1.1",
				Send:         make(chan []byte, 8),
			}, true)
		}
		overflow := &Session{
			ConnectionID: "spectator-overflow",
			DisplayName:  "Overflow",
			RemoteIP:     "127.0.1.2",
			Send:         make(chan []byte, 8),
		}
		request := criticalCommandEnvelope(t, protocol.TypeRoomJoin, "join-request",
			protocol.RoomJoin{RoomID: r.ID, AsSpectator: true})
		if err := h.handleRoomJoin(overflow, request); err != nil {
			t.Fatalf("handleRoomJoin: %v", err)
		}
		assertCriticalWireError(t, readWireError(t, overflow),
			protocol.ErrSpectatorLimit, protocol.ErrSpectatorLimit)
	})

	t.Run("host only", func(t *testing.T) {
		h := NewHandler()
		r, _ := newCriticalErrorRoom(t, h, false)
		guest := &Session{
			ConnectionID: "guest-conn",
			DisplayName:  "Bob",
			RemoteIP:     "127.0.2.1",
			Send:         make(chan []byte, 8),
		}
		joinCriticalSession(t, h, r, guest, false)
		if err := h.handleRoomDisband(guest, criticalCommandEnvelope(t,
			protocol.TypeRoomDisband, "disband-request", struct{}{})); err != nil {
			t.Fatalf("handleRoomDisband: %v", err)
		}
		assertCriticalWireError(t, readWireError(t, guest),
			protocol.ErrNotHost, "host only")
	})

	t.Run("deck required", func(t *testing.T) {
		h := NewHandler()
		r, host := newCriticalErrorRoom(t, h, false)
		joinCriticalSession(t, h, r, &Session{
			ConnectionID: "guest-conn",
			DisplayName:  "Bob",
			RemoteIP:     "127.0.3.1",
			Send:         make(chan []byte, 8),
		}, false)
		if err := h.handlePlayerReady(host, criticalCommandEnvelope(t,
			protocol.TypePlayerReady, "ready-request",
			protocol.PlayerReady{Ready: true})); err != nil {
			t.Fatalf("handlePlayerReady: %v", err)
		}
		assertCriticalWireError(t, readWireError(t, host),
			protocol.ErrDeckRequired, protocol.ErrDeckRequired)
	})
}
