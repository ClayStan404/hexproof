// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"testing"
	"time"

	"hexproof/server/internal/protocol"
)

func TestTournamentSpectatorDoesNotReceiveDeckLoadManifest(t *testing.T) {
	handler := NewHandler()
	host := tournamentAudienceSession("host", "Alice")
	guest := tournamentAudienceSession("guest", "Bob")
	spectator := tournamentAudienceSession("spectator", "Watcher")
	for _, session := range []*Session{host, guest, spectator} {
		handler.registerSession(session)
		t.Cleanup(func() { handler.unregisterSession(session) })
	}

	r, _, _, createOperation, err := handler.hub.createTournamentRoom(
		"Round 1 Table 1", protocol.FormatModern, protocol.DeckFormatModern,
		protocol.MatchBO1, protocol.CardLoadBackground, 2,
		"tournament-1", "pairing-1", "participant-a", host)
	if err != nil {
		t.Fatalf("create tournament room: %v", err)
	}
	createOperation.opMu.Unlock()

	joinOperation, err := handler.hub.beginJoin(r.ID, "")
	if err != nil {
		t.Fatalf("begin player join: %v", err)
	}
	_, _, err = handler.hub.joinTournamentRoom(joinOperation, guest, "participant-b")
	joinOperation.opMu.Unlock()
	if err != nil {
		t.Fatalf("join tournament player: %v", err)
	}

	watchOperation, err := handler.hub.beginJoin(r.ID, "")
	if err != nil {
		t.Fatalf("begin spectator join: %v", err)
	}
	_, _, err = handler.hub.joinRoom(watchOperation, spectator, true)
	watchOperation.opMu.Unlock()
	if err != nil {
		t.Fatalf("join tournament spectator: %v", err)
	}

	publicSnapshot, _ := protocol.NewEnvelope(protocol.TypeRoomSnapshot, r.Snapshot())
	privateManifest, _ := protocol.NewEnvelope(protocol.TypeMatchLoadRequired,
		protocol.MatchLoadRequired{
			LoadID: 1,
			CardKeys: []protocol.CardKey{{
				Name: "Secret sideboard card", SetCode: "TST", CollectorNumber: "1",
			}},
		})
	handler.fanout(r, []protocol.Envelope{publicSnapshot, privateManifest})

	assertTournamentAudienceTypes(t, host,
		protocol.TypeRoomSnapshot, protocol.TypeMatchLoadRequired)
	assertTournamentAudienceTypes(t, guest,
		protocol.TypeRoomSnapshot, protocol.TypeMatchLoadRequired)
	assertTournamentAudienceTypes(t, spectator, protocol.TypeRoomSnapshot)
	select {
	case data := <-spectator.Send:
		envelope, parseErr := protocol.ParseEnvelope(data)
		if parseErr != nil {
			t.Fatalf("parse unexpected spectator envelope: %v", parseErr)
		}
		t.Fatalf("spectator received private tournament envelope %q", envelope.Type)
	case <-time.After(25 * time.Millisecond):
	}

	operation, err := handler.hub.lockRoomOperation(r.ID)
	if err != nil {
		t.Fatalf("lock room for resume: %v", err)
	}
	operation.mu.Lock()
	r.Phase = protocol.RoomPhaseStarted
	operation.mu.Unlock()
	resumed := tournamentAudienceSession("resumed-spectator", "Watcher")
	handler.registerSession(resumed)
	t.Cleanup(func() { handler.unregisterSession(resumed) })
	info, envelopes, err := handler.hub.ResumeRoom(spectator.ConnectionID, resumed, r)
	operation.opMu.Unlock()
	if err != nil {
		t.Fatalf("resume tournament spectator: %v", err)
	}
	if info.Role != protocol.RoleSpectator {
		t.Fatalf("resumed role = %q, want %q", info.Role, protocol.RoleSpectator)
	}
	for _, envelope := range envelopes {
		if envelope.Type == protocol.TypeMatchLoadRequired {
			t.Fatal("resumed tournament spectator received deck load manifest")
		}
	}
}

func tournamentAudienceSession(connectionID, displayName string) *Session {
	return &Session{
		ConnectionID: connectionID,
		DisplayName:  displayName,
		Send:         make(chan []byte, 8),
	}
}

func assertTournamentAudienceTypes(t *testing.T, session *Session, expected ...string) {
	t.Helper()
	for _, expectedType := range expected {
		select {
		case data := <-session.Send:
			envelope, err := protocol.ParseEnvelope(data)
			if err != nil {
				t.Fatalf("parse %s envelope: %v", session.DisplayName, err)
			}
			if envelope.Type != expectedType {
				t.Fatalf("%s envelope = %q, want %q",
					session.DisplayName, envelope.Type, expectedType)
			}
		case <-time.After(time.Second):
			t.Fatalf("%s did not receive %q", session.DisplayName, expectedType)
		}
	}
}
