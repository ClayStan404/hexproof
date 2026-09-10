// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func TestRunningManualRoomSpectatorJoinTargetsGameProjection(t *testing.T) {
	h, r, host, guest := newRunningManualJoinTestRoom(t, protocol.CardLoadPreload)
	spectator := newManualJoinTestSession("spectator-conn", "Watcher")
	h.registerSession(spectator)
	t.Cleanup(func() { h.unregisterSession(spectator) })

	request, err := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{
		RoomID: r.ID, AsSpectator: true,
	})
	if err != nil {
		t.Fatalf("NewEnvelope(room.join): %v", err)
	}
	request.ID = "join-spectator"
	if err := h.handleRoomJoin(spectator, request); err != nil {
		t.Fatalf("handleRoomJoin: %v", err)
	}

	spectatorEnvelopes := assertEnvelopeTypes(t, spectator,
		protocol.TypeRoomJoined,
		protocol.TypeRoomSnapshot,
		protocol.TypeGameSnapshot)
	assertEnvelopeTypes(t, host, protocol.TypeRoomSnapshot)
	assertEnvelopeTypes(t, guest, protocol.TypeRoomSnapshot)

	roomSnapshot := spectatorEnvelopes[1]
	gameSnapshot := spectatorEnvelopes[2]
	if !roomSnapshot.HasSeq() || roomSnapshot.SeqValue() == 0 {
		t.Fatalf("room.snapshot sequence = %d (present=%v), want non-zero",
			roomSnapshot.SeqValue(), roomSnapshot.HasSeq())
	}
	if !gameSnapshot.HasSeq() || gameSnapshot.SeqValue() != roomSnapshot.SeqValue() {
		t.Fatalf("game.snapshot sequence = %d (present=%v), want room.snapshot sequence %d",
			gameSnapshot.SeqValue(), gameSnapshot.HasSeq(), roomSnapshot.SeqValue())
	}

	var snapshot protocol.GameSnapshot
	if err := gameSnapshot.DecodePayload(&snapshot); err != nil {
		t.Fatalf("DecodePayload(game.snapshot): %v", err)
	}
	if len(snapshot.Seats) != 2 {
		t.Fatalf("spectator seat count = %d, want 2", len(snapshot.Seats))
	}
	for seat, state := range snapshot.Seats {
		if state.HandCount != 1 || len(state.Hand) != 0 {
			t.Fatalf("spectator seat %d hand = %+v count=%d, want one redacted card",
				seat, state.Hand, state.HandCount)
		}
	}
}

func TestRunningBackgroundManualRoomSpectatorJoinKeepsSequenceOrder(t *testing.T) {
	h, r, host, guest := newRunningManualJoinTestRoom(t, protocol.CardLoadBackground)
	spectator := newManualJoinTestSession("spectator-conn", "Watcher")
	h.registerSession(spectator)
	t.Cleanup(func() { h.unregisterSession(spectator) })

	request, err := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{
		RoomID: r.ID, AsSpectator: true,
	})
	if err != nil {
		t.Fatalf("NewEnvelope(room.join): %v", err)
	}
	request.ID = "join-background-spectator"
	if err := h.handleRoomJoin(spectator, request); err != nil {
		t.Fatalf("handleRoomJoin: %v", err)
	}

	spectatorEnvelopes := assertEnvelopeTypes(t, spectator,
		protocol.TypeRoomJoined,
		protocol.TypeRoomSnapshot,
		protocol.TypeGameSnapshot,
		protocol.TypeMatchLoadRequired)
	hostEnvelopes := assertEnvelopeTypes(t, host,
		protocol.TypeRoomSnapshot, protocol.TypeMatchLoadRequired)
	guestEnvelopes := assertEnvelopeTypes(t, guest,
		protocol.TypeRoomSnapshot, protocol.TypeMatchLoadRequired)

	roomSeq := spectatorEnvelopes[1].SeqValue()
	if roomSeq == 0 || spectatorEnvelopes[2].SeqValue() != roomSeq {
		t.Fatalf("spectator room/game sequences = %d/%d, want one non-zero sequence",
			roomSeq, spectatorEnvelopes[2].SeqValue())
	}
	loadSeq := spectatorEnvelopes[3].SeqValue()
	if loadSeq != roomSeq+1 ||
		hostEnvelopes[0].SeqValue() != roomSeq ||
		hostEnvelopes[1].SeqValue() != loadSeq ||
		guestEnvelopes[0].SeqValue() != roomSeq ||
		guestEnvelopes[1].SeqValue() != loadSeq {
		t.Fatalf("background join sequences spectator=%d/%d/%d host=%d/%d guest=%d/%d",
			roomSeq, spectatorEnvelopes[2].SeqValue(), loadSeq,
			hostEnvelopes[0].SeqValue(), hostEnvelopes[1].SeqValue(),
			guestEnvelopes[0].SeqValue(), guestEnvelopes[1].SeqValue())
	}
}

func newRunningManualJoinTestRoom(t *testing.T, cardLoadMode string) (
	*Handler, *room.Room, *Session, *Session,
) {
	t.Helper()
	h := NewHandler()
	host := newManualJoinTestSession("host-conn", "Alice")
	guest := newManualJoinTestSession("guest-conn", "Bob")
	h.registerSession(host)
	h.registerSession(guest)
	t.Cleanup(func() {
		h.unregisterSession(host)
		h.unregisterSession(guest)
	})

	r, _, _, operation, err := h.hub.CreateRoom(
		"Manual table", protocol.FormatModern, protocol.MatchBO1,
		cardLoadMode, 2, true, false, "", host)
	if err != nil {
		t.Fatalf("CreateRoom: %v", err)
	}
	operation.opMu.Unlock()

	joinRequest, err := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{
		RoomID: r.ID,
	})
	if err != nil {
		t.Fatalf("NewEnvelope(player room.join): %v", err)
	}
	joinRequest.ID = "join-guest"
	if err := h.handleRoomJoin(guest, joinRequest); err != nil {
		t.Fatalf("handleRoomJoin(guest): %v", err)
	}
	assertEnvelopeTypes(t, guest,
		protocol.TypeRoomJoined, protocol.TypeRoomSnapshot)
	assertEnvelopeTypes(t, host, protocol.TypeRoomSnapshot)

	operation, err = h.hub.lockRoomOperation(r.ID)
	if err != nil {
		t.Fatalf("lockRoomOperation: %v", err)
	}
	operation.mu.Lock()
	r.Phase = protocol.RoomPhaseStarted
	r.LoadID = 7
	r.Score = []int{0, 0}
	r.Game = &room.GameState{
		Number:       1,
		StartingSeat: 0,
		TurnOrder:    []int{0, 1},
		ActiveSeat:   0,
		CurrentPhase: protocol.GamePhaseUntap,
		Seats: []room.PlayerGameState{
			{
				Seat: 0, DisplayName: "Alice", Life: 20,
				Hand: []protocol.GameCard{{
					ID: "alice-secret", Name: "Lightning Bolt",
					SetCode: "M11", CollectorNumber: "149", OwnerSeat: 0,
				}},
			},
			{
				Seat: 1, DisplayName: "Bob", Life: 20,
				Hand: []protocol.GameCard{{
					ID: "bob-secret", Name: "Counterspell",
					SetCode: "MH2", CollectorNumber: "267", OwnerSeat: 1,
				}},
			},
		},
		Stack:       []protocol.GameSharedCard{},
		Revealed:    []protocol.GameSharedCard{},
		Log:         []protocol.GameLogEntry{},
		NextLogID:   1,
		NextTokenID: 1,
	}
	operation.mu.Unlock()
	operation.opMu.Unlock()
	return h, r, host, guest
}

func newManualJoinTestSession(connectionID, displayName string) *Session {
	return &Session{
		ConnectionID: connectionID,
		DisplayName:  displayName,
		RemoteIP:     "127.0.0.1",
		Send:         make(chan []byte, 16),
	}
}

func assertEnvelopeTypes(t *testing.T, session *Session,
	expected ...string) []protocol.Envelope {
	t.Helper()
	envelopes := make([]protocol.Envelope, 0, len(expected))
	for _, expectedType := range expected {
		select {
		case data, ok := <-session.Send:
			if !ok {
				t.Fatalf("%s session closed while waiting for %q",
					session.ConnectionID, expectedType)
			}
			envelope, err := protocol.ParseEnvelope(data)
			if err != nil {
				t.Fatalf("ParseEnvelope(%s): %v", session.ConnectionID, err)
			}
			if envelope.Type != expectedType {
				t.Fatalf("%s envelope = %q, want %q",
					session.ConnectionID, envelope.Type, expectedType)
			}
			envelopes = append(envelopes, envelope)
		case <-time.After(time.Second):
			t.Fatalf("%s did not receive %q", session.ConnectionID, expectedType)
		}
	}
	select {
	case data, ok := <-session.Send:
		if !ok {
			t.Fatalf("%s session closed after expected envelopes", session.ConnectionID)
		}
		envelope, err := protocol.ParseEnvelope(data)
		if err != nil {
			t.Fatalf("ParseEnvelope(unexpected %s): %v", session.ConnectionID, err)
		}
		t.Fatalf("%s received unexpected %q envelope", session.ConnectionID, envelope.Type)
	default:
	}
	return envelopes
}
