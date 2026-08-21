// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"errors"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func TestGameProjectionsRejectsStaleRoomPointer(t *testing.T) {
	h := NewHandler()
	live, _ := newCriticalErrorRoom(t, h, false)
	stale := &room.Room{ID: live.ID}

	_, err := h.hub.GameProjections(stale)
	code, ok := ErrCode(err)
	if !ok || code != protocol.ErrRoomNotFound {
		t.Fatalf("stale room pointer error = %v code %q, want %q",
			err, code, protocol.ErrRoomNotFound)
	}
}

func TestFanoutGameProjectionsFailClosedWhenRoomMissing(t *testing.T) {
	h := NewHandler()
	r, host := newCriticalErrorRoom(t, h, false)
	h.registerSession(host)

	h.hub.RemoveRoom(r.ID)
	h.fanoutGameProjections(r)

	assertCriticalWireError(t, readWireError(t, host),
		protocol.ErrInternal, "internal server error")

	select {
	case _, ok := <-host.Send:
		if ok {
			t.Fatal("session stayed open after projection fan-out failure")
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for fail-closed disconnect")
	}
}

func TestFanoutToFailClosedWhenMarshalFails(t *testing.T) {
	h := NewHandler()
	r, host := newCriticalErrorRoom(t, h, false)
	h.registerSession(host)
	h.marshalEnvelope = func(env protocol.Envelope) ([]byte, error) {
		if env.Type == protocol.TypeRoomSnapshot {
			return nil, errors.New("marshal boom")
		}
		return env.Marshal()
	}

	snapshot, err := protocol.NewEnvelope(protocol.TypeRoomSnapshot, protocol.RoomSnapshot{
		RoomID: r.ID,
	})
	if err != nil {
		t.Fatalf("NewEnvelope: %v", err)
	}
	h.fanout(r, []protocol.Envelope{snapshot})

	assertCriticalWireError(t, readWireError(t, host),
		protocol.ErrInternal, "internal server error")

	select {
	case _, ok := <-host.Send:
		if ok {
			t.Fatal("session stayed open after broadcast marshal failure")
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for fail-closed disconnect")
	}
}

func TestSendFailClosedWhenMarshalFails(t *testing.T) {
	h := NewHandler()
	_, host := newCriticalErrorRoom(t, h, false)
	h.marshalEnvelope = func(env protocol.Envelope) ([]byte, error) {
		if env.Type == protocol.TypeRoomCreated {
			return nil, errors.New("marshal boom")
		}
		return env.Marshal()
	}

	created, err := protocol.NewEnvelope(protocol.TypeRoomCreated, protocol.RoomCreated{
		RoomID: "ROOM01",
	})
	if err != nil {
		t.Fatalf("NewEnvelope: %v", err)
	}
	h.send(host, created)

	assertCriticalWireError(t, readWireError(t, host),
		protocol.ErrInternal, "internal server error")

	select {
	case _, ok := <-host.Send:
		if ok {
			t.Fatal("session stayed open after send marshal failure")
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for fail-closed disconnect")
	}
}

func fillSessionSend(sess *Session) {
	pad := []byte("pad")
	for {
		select {
		case sess.Send <- pad:
		default:
			return
		}
	}
}

func assertSessionClosed(t *testing.T, sess *Session, why string) {
	t.Helper()
	deadline := time.After(time.Second)
	for {
		select {
		case _, ok := <-sess.Send:
			if !ok {
				return
			}
		case <-deadline:
			t.Fatalf("session stayed open after %s", why)
		}
	}
}

func TestSendFailClosedWhenSendBufferFull(t *testing.T) {
	h := NewHandler()
	_, host := newCriticalErrorRoom(t, h, false)
	fillSessionSend(host)

	created, err := protocol.NewEnvelope(protocol.TypeRoomCreated, protocol.RoomCreated{
		RoomID: "ROOM01",
	})
	if err != nil {
		t.Fatalf("NewEnvelope: %v", err)
	}
	h.send(host, created)
	assertSessionClosed(t, host, "send buffer overflow")
}

func TestFanoutToFailClosedOnlyBackpressuredMember(t *testing.T) {
	h := NewHandler()
	_, host := newCriticalErrorRoom(t, h, false)
	guest := &Session{
		ConnectionID: "guest-conn",
		DisplayName:  "Bob",
		RemoteIP:     "127.0.0.2",
		Send:         make(chan []byte, 8),
	}
	fillSessionSend(host)

	snapshot, err := protocol.NewEnvelope(protocol.TypeRoomSnapshot, protocol.RoomSnapshot{
		RoomID: "ROOM01",
	})
	if err != nil {
		t.Fatalf("NewEnvelope: %v", err)
	}
	h.fanoutTo([]*Session{host, guest}, []protocol.Envelope{snapshot})

	assertSessionClosed(t, host, "fan-out buffer overflow")

	select {
	case data := <-guest.Send:
		env, err := protocol.ParseEnvelope(data)
		if err != nil || env.Type != protocol.TypeRoomSnapshot {
			t.Fatalf("healthy member received %#v err=%v", env, err)
		}
	case <-time.After(time.Second):
		t.Fatal("healthy member did not receive fan-out")
	}
	select {
	case <-guest.Send:
		t.Fatal("healthy member was closed after sibling overflow")
	default:
	}
}
