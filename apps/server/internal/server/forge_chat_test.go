// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func TestForgeChatPublishesMetadataWithoutQueryingAnEngine(t *testing.T) {
	h, err := NewHandlerWithConfig(DefaultConfig())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = h.Close() })
	host := &Session{ConnectionID: "host", DisplayName: "Alice", Send: make(chan []byte, 16)}
	observer := &Session{ConnectionID: "observer", DisplayName: "Observer", Send: make(chan []byte, 16)}
	r, _, _, entry, err := h.hub.CreateRoomWithRulesMode("Rules chat",
		protocol.FormatModern, protocol.DeckFormatCustom, protocol.MatchBO1,
		protocol.CardLoadBackground, protocol.RulesModeForge, 2, true, false, "", host)
	if err != nil {
		t.Fatal(err)
	}
	r.Seats[1] = room.Seat{Occupied: true, DisplayName: "Bob", ConnectionID: "bob"}
	r.Spectators = []room.Spectator{{DisplayName: observer.DisplayName, ConnectionID: observer.ConnectionID}}
	r.Phase = protocol.RoomPhaseStarted
	r.ResetRulesLog()
	entry.opMu.Unlock()
	for _, sess := range []*Session{host, observer} {
		sess.setRoom(r)
		h.sessions[sess.ConnectionID] = sess
	}
	for _, terminal := range []bool{false, true} {
		if terminal {
			if _, err := r.CompleteRulesGame(1, time.Now()); err != nil {
				t.Fatal(err)
			}
		}
		request, _ := protocol.NewEnvelope(protocol.TypeGameSay, protocol.GameSay{Message: "Hello players"})
		request.ID = "public-chat"
		if err := h.handleGameSay(observer, request); err != nil {
			t.Fatal(err)
		}
		observerMessages := receiveForgeSessionEnvelopes(t, observer, 2)
		hostMessages := receiveForgeSessionEnvelopes(t, host, 1)
		if observerMessages[0].Type != protocol.TypeGameSaid || observerMessages[0].ID != request.ID ||
			observerMessages[1].Type != protocol.TypeGameSnapshot || hostMessages[0].Type != protocol.TypeGameSnapshot {
			t.Fatalf("chat did not use metadata-only fanout: %v / %v", envelopeTypes(observerMessages), envelopeTypes(hostMessages))
		}
		for _, envelope := range []protocol.Envelope{observerMessages[1], hostMessages[0]} {
			var snapshot protocol.GameSnapshot
			if err := envelope.DecodePayload(&snapshot); err != nil {
				t.Fatal(err)
			}
			if len(snapshot.Log) == 0 || !strings.Contains(snapshot.Log[len(snapshot.Log)-1].Text, "Observer: Hello players") {
				t.Fatalf("missing public chat: %+v", snapshot.Log)
			}
		}
	}
	if len(h.forgeClients) != 0 || len(h.forgeGames) != 0 {
		t.Fatal("public chat started or queried an engine")
	}
}
