// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func newRegressionRoom(t *testing.T, h *Handler, password string) (*room.Room, *Session) {
	t.Helper()
	host := &Session{
		ConnectionID: "host-conn",
		DisplayName:  "Alice",
		ResumeToken:  "resume-host",
		RemoteIP:     "127.0.0.1",
		Send:         make(chan []byte, 8),
	}
	r, _, _, operation, err := h.hub.CreateRoom(
		"Regression room", protocol.FormatModern, protocol.MatchBO1,
		protocol.CardLoadPreload, 2, false, false, password, host)
	if err != nil {
		t.Fatalf("CreateRoom: %v", err)
	}
	operation.opMu.Unlock()
	return r, host
}

func installResumeHold(h *Handler, hold resumeHold) {
	h.resumeMu.Lock()
	h.resumeHolds[hold.token] = hold
	h.resumeMu.Unlock()
}

func assertResumeHoldExpired(t *testing.T, h *Handler, hold resumeHold) {
	t.Helper()
	h.resumeMu.Lock()
	_, exists := h.resumeHolds[hold.token]
	h.resumeMu.Unlock()
	if exists {
		t.Fatal("expired resume hold remained registered")
	}
	if got := h.hub.FindRoom(hold.room.ID); got != nil {
		t.Fatal("expired disconnected host left a zombie room")
	}

	// The scheduled timer may arrive after the synchronous boundary cleanup.
	// A second expiry attempt must remain a no-op.
	h.expireResumeHold(hold)
	if got := h.hub.FindRoom(hold.room.ID); got != nil {
		t.Fatal("duplicate expiry recreated or retained the room")
	}
}

func TestTakeResumeHoldAtExpiryExpiresMembership(t *testing.T) {
	h := NewHandler()
	r, host := newRegressionRoom(t, h, "")
	expiresAt := time.Unix(1_700_000_000, 0).UTC()
	hold := resumeHold{
		token:           host.ResumeToken,
		oldConnectionID: host.ConnectionID,
		displayName:     host.DisplayName,
		room:            r,
		expiresAt:       expiresAt,
	}
	host.setRoom(nil)
	installResumeHold(h, hold)

	if _, ok := h.takeResumeHold(hold.token, expiresAt); ok {
		t.Fatal("resume hold was accepted at its expiry boundary")
	}
	assertResumeHoldExpired(t, h, hold)
}

func TestRestoreResumeHoldAtExpiryExpiresMembership(t *testing.T) {
	h := NewHandler()
	r, host := newRegressionRoom(t, h, "")
	expiresAt := time.Unix(1_700_000_000, 0).UTC()
	hold := resumeHold{
		token:           host.ResumeToken,
		oldConnectionID: host.ConnectionID,
		displayName:     host.DisplayName,
		room:            r,
		expiresAt:       expiresAt,
	}
	host.setRoom(nil)
	installResumeHold(h, hold)

	taken, ok := h.takeResumeHold(hold.token, expiresAt.Add(-time.Nanosecond))
	if !ok {
		t.Fatal("resume hold could not be taken before expiry")
	}
	if !h.restoreResumeHold(taken, expiresAt) {
		t.Fatal("restored boundary hold was not marked expired")
	}
	// handleHello performs this only after releasing the room operation lock.
	h.expireResumeHold(taken)
	assertResumeHoldExpired(t, h, hold)
}

func readWireError(t *testing.T, sess *Session) protocol.ErrorPayload {
	t.Helper()
	select {
	case data := <-sess.Send:
		envelope, err := protocol.ParseEnvelope(data)
		if err != nil {
			t.Fatalf("ParseEnvelope: %v", err)
		}
		if envelope.Type != protocol.TypeError {
			t.Fatalf("response type = %q, want %q", envelope.Type, protocol.TypeError)
		}
		var payload protocol.ErrorPayload
		if err := envelope.DecodePayload(&payload); err != nil {
			t.Fatalf("DecodePayload: %v", err)
		}
		return payload
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for error response")
		return protocol.ErrorPayload{}
	}
}

func roomJoinEnvelope(t *testing.T, roomID, password string) protocol.Envelope {
	t.Helper()
	envelope, err := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{
		RoomID:   roomID,
		Password: password,
	})
	if err != nil {
		t.Fatalf("NewEnvelope: %v", err)
	}
	envelope.ID = "join-request"
	return envelope
}

func TestRoomJoinErrorsUseCleanWireMessages(t *testing.T) {
	t.Run("room full", func(t *testing.T) {
		h := NewHandler()
		r, _ := newRegressionRoom(t, h, "")
		guest := &Session{
			ConnectionID: "guest-conn",
			DisplayName:  "Bob",
			RemoteIP:     "127.0.0.2",
			Send:         make(chan []byte, 8),
		}
		operation, err := h.hub.beginJoin(r.ID, "")
		if err != nil {
			t.Fatalf("beginJoin: %v", err)
		}
		_, _, err = h.hub.joinRoom(operation, guest, false)
		operation.opMu.Unlock()
		if err != nil {
			t.Fatalf("joinRoom: %v", err)
		}

		overflow := &Session{
			ConnectionID: "overflow-conn",
			DisplayName:  "Charlie",
			RemoteIP:     "127.0.0.3",
			Send:         make(chan []byte, 8),
		}
		if err := h.handleRoomJoin(overflow, roomJoinEnvelope(t, r.ID, "")); err != nil {
			t.Fatalf("handleRoomJoin: %v", err)
		}
		payload := readWireError(t, overflow)
		if payload.Code != protocol.ErrRoomFull || payload.Message != protocol.ErrRoomFull {
			t.Fatalf("room-full error = %#v", payload)
		}
	})

	t.Run("wrong password", func(t *testing.T) {
		h := NewHandler()
		r, _ := newRegressionRoom(t, h, "secret")
		joiner := &Session{
			ConnectionID: "joiner-conn",
			DisplayName:  "Bob",
			RemoteIP:     "127.0.0.4",
			Send:         make(chan []byte, 8),
		}
		if err := h.handleRoomJoin(joiner, roomJoinEnvelope(t, r.ID, "wrong")); err != nil {
			t.Fatalf("handleRoomJoin: %v", err)
		}
		payload := readWireError(t, joiner)
		if payload.Code != protocol.ErrWrongPassword || payload.Message != "wrong password" {
			t.Fatalf("wrong-password error = %#v", payload)
		}
	})
}
