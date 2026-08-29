// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestRevealRecallRoundTripRestoresHandPrivacy(t *testing.T) {
	setup := newPrivateZoneConsentSetup(t)
	setup.room.Game.Seats[0].Hand = []protocol.GameCard{
		{ID: "reveal-a", Name: "Demonic Tutor", SetCode: "STA", CollectorNumber: "27", OwnerSeat: 0},
		{ID: "reveal-b", Name: "Lightning Bolt", SetCode: "M11", CollectorNumber: "149", OwnerSeat: 0},
	}

	revealRequest := loadPrivateZoneFixture(t, "game-reveal.json")
	if err := setup.handler.handleGameReveal(setup.host, revealRequest); err != nil {
		t.Fatalf("handle reveal: %v", err)
	}
	revealed := receivePrivateZoneEnvelope(t, setup.host)
	assertPrivateZoneFixture(t, "game-revealed.json", setup.room.ID, revealed)

	for role, sess := range map[string]*Session{
		"owner": setup.host, "opponent": setup.guest, "spectator": setup.spectator,
	} {
		snapshot := receiveGameSnapshot(t, sess, "reveal "+role)
		if snapshot.Seats[0].HandCount != 0 || len(snapshot.Seats[0].Hand) != 0 ||
			len(snapshot.Revealed) != 2 {
			t.Fatalf("%s reveal projection = seat=%+v revealed=%+v",
				role, snapshot.Seats[0], snapshot.Revealed)
		}
		if snapshot.Revealed[0].Name != "Demonic Tutor" ||
			snapshot.Revealed[1].Name != "Lightning Bolt" {
			t.Fatalf("%s did not receive public reveal identities: %+v", role, snapshot.Revealed)
		}
		if len(snapshot.Log) != 1 || snapshot.Log[0].Kind != "reveal" ||
			snapshot.Log[0].Text != "Alice revealed 2 card(s) from hand." {
			t.Fatalf("%s reveal log = %+v", role, snapshot.Log)
		}
	}

	recallRequest := loadPrivateZoneFixture(t, "game-recall-revealed.json")
	if err := setup.handler.handleGameRecallRevealed(setup.host, recallRequest); err != nil {
		t.Fatalf("handle recall: %v", err)
	}
	recalled := receivePrivateZoneEnvelope(t, setup.host)
	assertPrivateZoneFixture(t, "game-revealed-recalled.json", setup.room.ID, recalled)

	owner := receiveGameSnapshot(t, setup.host, "recall owner")
	opponent := receiveGameSnapshot(t, setup.guest, "recall opponent")
	spectator := receiveGameSnapshot(t, setup.spectator, "recall spectator")
	if len(owner.Revealed) != 0 || owner.Seats[0].HandCount != 2 ||
		len(owner.Seats[0].Hand) != 2 ||
		owner.Seats[0].Hand[0].Name != "Demonic Tutor" ||
		owner.Seats[0].Hand[1].Name != "Lightning Bolt" {
		t.Fatalf("owner recall projection = seat=%+v revealed=%+v",
			owner.Seats[0], owner.Revealed)
	}

	for role, snapshot := range map[string]protocol.GameSnapshot{
		"opponent": opponent, "spectator": spectator,
	} {
		if len(snapshot.Revealed) != 0 || snapshot.Seats[0].HandCount != 2 ||
			len(snapshot.Seats[0].Hand) != 0 {
			t.Fatalf("%s recall projection = seat=%+v revealed=%+v",
				role, snapshot.Seats[0], snapshot.Revealed)
		}
		encoded, err := json.Marshal(snapshot)
		if err != nil {
			t.Fatalf("marshal %s recall snapshot: %v", role, err)
		}
		for _, secret := range []string{"Demonic Tutor", "Lightning Bolt"} {
			if strings.Contains(string(encoded), secret) {
				t.Fatalf("%s retained recalled identity %q: %s", role, secret, encoded)
			}
		}
	}

	for role, snapshot := range map[string]protocol.GameSnapshot{
		"owner": owner, "opponent": opponent, "spectator": spectator,
	} {
		if len(snapshot.Log) != 2 || snapshot.Log[1].Kind != "recall_revealed" ||
			snapshot.Log[1].Text != "Alice returned 2 revealed card(s) to hand." {
			t.Fatalf("%s recall log = %+v", role, snapshot.Log)
		}
	}
}
