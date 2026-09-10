// SPDX-License-Identifier: GPL-3.0-or-later
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

func TestGameProjectionUsesSuppliedSequenceWithoutAllocation(t *testing.T) {
	h, r, _, _ := newRunningManualJoinTestRoom(t, protocol.CardLoadPreload)
	spectator := newManualJoinTestSession("spectator-one", "Watcher")
	joinCriticalSession(t, h, r, spectator, true)
	nextSeq := r.NextSeq

	envelope, err := h.hub.GameProjection(r, spectator.ConnectionID, 42)
	if err != nil {
		t.Fatalf("GameProjection: %v", err)
	}
	if envelope.Type != protocol.TypeGameSnapshot ||
		!envelope.HasSeq() || envelope.SeqValue() != 42 {
		t.Fatalf("targeted projection = %+v, want game.snapshot seq 42", envelope)
	}
	if r.NextSeq != nextSeq {
		t.Fatalf("targeted projection advanced NextSeq from %d to %d", nextSeq, r.NextSeq)
	}
	var snapshot protocol.GameSnapshot
	if err := envelope.DecodePayload(&snapshot); err != nil {
		t.Fatalf("DecodePayload: %v", err)
	}
	if len(snapshot.Seats) != 2 ||
		len(snapshot.Seats[0].Hand) != 0 || snapshot.Seats[0].HandCount != 1 ||
		len(snapshot.Seats[1].Hand) != 0 || snapshot.Seats[1].HandCount != 1 {
		t.Fatalf("targeted spectator projection leaked or omitted hands: %+v", snapshot.Seats)
	}
}

func TestGameProjectionsReuseOneSpectatorEnvelope(t *testing.T) {
	h, r, _, _ := newRunningManualJoinTestRoom(t, protocol.CardLoadPreload)
	firstSpectator := newManualJoinTestSession("spectator-one", "Watcher One")
	secondSpectator := newManualJoinTestSession("spectator-two", "Watcher Two")
	joinCriticalSession(t, h, r, firstSpectator, true)
	joinCriticalSession(t, h, r, secondSpectator, true)

	projections, err := h.hub.GameProjections(r)
	if err != nil {
		t.Fatalf("GameProjections: %v", err)
	}
	if len(projections) != 4 {
		t.Fatalf("projection count = %d, want 4", len(projections))
	}
	hostEnvelope := projections["host-conn"]
	guestEnvelope := projections["guest-conn"]
	firstEnvelope := projections[firstSpectator.ConnectionID]
	secondEnvelope := projections[secondSpectator.ConnectionID]
	for connectionID, envelope := range projections {
		if envelope.Type != protocol.TypeGameSnapshot ||
			!envelope.HasSeq() || envelope.SeqValue() != firstEnvelope.SeqValue() {
			t.Fatalf("%s projection = %+v, want shared game.snapshot sequence",
				connectionID, envelope)
		}
		if len(envelope.Payload) == 0 {
			t.Fatalf("%s projection has empty payload", connectionID)
		}
	}
	if &firstEnvelope.Payload[0] != &secondEnvelope.Payload[0] ||
		firstEnvelope.SeqPtr != secondEnvelope.SeqPtr {
		t.Fatal("spectator projections do not reuse one immutable envelope")
	}
	if &hostEnvelope.Payload[0] == &guestEnvelope.Payload[0] ||
		&hostEnvelope.Payload[0] == &firstEnvelope.Payload[0] ||
		&guestEnvelope.Payload[0] == &firstEnvelope.Payload[0] {
		t.Fatal("player-specific projection reused another viewer's payload")
	}

	var hostSnapshot, guestSnapshot, spectatorSnapshot protocol.GameSnapshot
	if err := hostEnvelope.DecodePayload(&hostSnapshot); err != nil {
		t.Fatalf("DecodePayload(host): %v", err)
	}
	if err := guestEnvelope.DecodePayload(&guestSnapshot); err != nil {
		t.Fatalf("DecodePayload(guest): %v", err)
	}
	if err := firstEnvelope.DecodePayload(&spectatorSnapshot); err != nil {
		t.Fatalf("DecodePayload(spectator): %v", err)
	}
	if len(hostSnapshot.Seats[0].Hand) != 1 || len(hostSnapshot.Seats[1].Hand) != 0 ||
		len(guestSnapshot.Seats[0].Hand) != 0 || len(guestSnapshot.Seats[1].Hand) != 1 ||
		len(spectatorSnapshot.Seats[0].Hand) != 0 ||
		len(spectatorSnapshot.Seats[1].Hand) != 0 {
		t.Fatalf("viewer-specific hands host=%+v guest=%+v spectator=%+v",
			hostSnapshot.Seats, guestSnapshot.Seats, spectatorSnapshot.Seats)
	}
}

func TestSendGameProjectionFailClosedOnlyTargetWhenRoomMissing(t *testing.T) {
	h := NewHandler()
	r, host := newCriticalErrorRoom(t, h, true)
	spectator := newManualJoinTestSession("spectator-conn", "Watcher")
	joinCriticalSession(t, h, r, spectator, true)
	h.registerSession(host)
	h.registerSession(spectator)

	h.hub.RemoveRoom(r.ID)
	h.sendGameProjection(r, spectator, 1)

	assertCriticalWireError(t, readWireError(t, spectator),
		protocol.ErrInternal, "internal server error")
	select {
	case _, ok := <-spectator.Send:
		if ok {
			t.Fatal("target session stayed open after projection failure")
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for target fail-closed disconnect")
	}
	select {
	case data := <-host.Send:
		envelope, err := protocol.ParseEnvelope(data)
		if err != nil {
			t.Fatalf("ParseEnvelope(unexpected host message): %v", err)
		}
		t.Fatalf("non-target host received %q after targeted projection failure", envelope.Type)
	default:
	}
	if !host.trySend([]byte("probe")) {
		t.Fatal("non-target host was closed after targeted projection failure")
	}
	<-host.Send
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
