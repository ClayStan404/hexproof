// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestMoveLibraryCardsMatchesGoldenFixtureAndPublicProjection(t *testing.T) {
	setup := newPrivateZoneConsentSetup(t)
	setup.room.Game.Seats[0].Library = []protocol.GameCard{
		{ID: "s0-c8", Name: "Island", SetCode: "M21", CollectorNumber: "265", OwnerSeat: 0},
		{ID: "s0-c9", Name: "Demonic Tutor", SetCode: "STA", CollectorNumber: "27", OwnerSeat: 0},
		{ID: "s0-c10", Name: "Forest", SetCode: "M21", CollectorNumber: "274", OwnerSeat: 0},
		{ID: "s0-c11", Name: "Black Lotus", SetCode: "LEA", CollectorNumber: "232", OwnerSeat: 0},
	}

	request := loadPrivateZoneFixture(t, "game-move-library-cards.json")
	if err := setup.handler.handleGameMoveLibraryCards(setup.host, request); err != nil {
		t.Fatalf("handle move library cards: %v", err)
	}

	moved := receivePrivateZoneEnvelope(t, setup.host)
	assertPrivateZoneFixture(t, "game-library-cards-moved.json", setup.room.ID, moved)
	movedData, err := moved.Marshal()
	if err != nil {
		t.Fatalf("marshal move acknowledgement: %v", err)
	}
	for _, hiddenName := range []string{"Island", "Demonic Tutor", "Forest", "Black Lotus"} {
		if strings.Contains(string(movedData), hiddenName) {
			t.Fatalf("move acknowledgement leaked %q: %s", hiddenName, movedData)
		}
	}

	state := setup.room.Game.Seats[0]
	if len(state.Library) != 1 || state.Library[0].ID != "s0-c11" ||
		len(state.Graveyard) != 3 || state.Graveyard[0].ID != "s0-c8" ||
		state.Graveyard[1].ID != "s0-c9" || state.Graveyard[2].ID != "s0-c10" {
		t.Fatalf("move library state = %+v", state)
	}

	for role, sess := range map[string]*Session{
		"owner": setup.host, "opponent": setup.guest, "spectator": setup.spectator,
	} {
		envelope := receivePrivateZoneEnvelope(t, sess)
		if envelope.Type != protocol.TypeGameSnapshot {
			t.Fatalf("%s received %q after public library move", role, envelope.Type)
		}
		var snapshot protocol.GameSnapshot
		if err := envelope.DecodePayload(&snapshot); err != nil {
			t.Fatalf("decode %s snapshot: %v", role, err)
		}
		seat := snapshot.Seats[0]
		if seat.LibraryCount != 1 || len(seat.Graveyard) != 3 ||
			seat.Graveyard[0].Name != "Island" ||
			seat.Graveyard[1].Name != "Demonic Tutor" ||
			seat.Graveyard[2].Name != "Forest" {
			t.Fatalf("%s public projection = %+v", role, seat)
		}
		if len(snapshot.Log) != 1 || snapshot.Log[0].Kind != "move_library_cards" ||
			!strings.Contains(snapshot.Log[0].Text, "3 card(s)") ||
			!strings.Contains(snapshot.Log[0].Text, protocol.ZoneGraveyard) {
			t.Fatalf("%s move log = %+v", role, snapshot.Log)
		}
		for _, movedName := range []string{"Island", "Demonic Tutor", "Forest"} {
			if strings.Contains(snapshot.Log[0].Text, movedName) {
				t.Fatalf("%s log exposed hidden source identity %q: %q",
					role, movedName, snapshot.Log[0].Text)
			}
		}
		encoded, err := json.Marshal(snapshot)
		if err != nil {
			t.Fatalf("marshal %s snapshot: %v", role, err)
		}
		if strings.Contains(string(encoded), "Black Lotus") {
			t.Fatalf("%s learned remaining library identity: %s", role, encoded)
		}
	}
}
