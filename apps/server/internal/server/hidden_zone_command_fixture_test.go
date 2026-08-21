// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

func receiveGameSnapshot(t *testing.T, sess *Session, operation string) protocol.GameSnapshot {
	t.Helper()
	envelope := receivePrivateZoneEnvelope(t, sess)
	if envelope.Type != protocol.TypeGameSnapshot {
		t.Fatalf("%s received %q, want game.snapshot", operation, envelope.Type)
	}
	var snapshot protocol.GameSnapshot
	if err := envelope.DecodePayload(&snapshot); err != nil {
		t.Fatalf("decode %s snapshot: %v", operation, err)
	}
	return snapshot
}

func marshalGameSnapshot(t *testing.T, role string, snapshot protocol.GameSnapshot) []byte {
	t.Helper()
	data, err := json.Marshal(snapshot)
	if err != nil {
		t.Fatalf("marshal %s snapshot: %v", role, err)
	}
	return data
}

func TestDrawMatchesGoldenFixtureAndPrivateHandProjection(t *testing.T) {
	setup := newPrivateZoneConsentSetup(t)
	setup.room.Game.Seats[0].Library = []protocol.GameCard{
		{ID: "draw-1", Name: "Lightning Bolt", OwnerSeat: 0},
		{ID: "draw-2", Name: "Counterspell", OwnerSeat: 0},
		{ID: "draw-3", Name: "Dark Ritual", OwnerSeat: 0},
		{ID: "draw-4", Name: "Ancestral Recall", OwnerSeat: 0},
	}

	request := loadPrivateZoneFixture(t, "game-draw.json")
	if err := setup.handler.handleGameDraw(setup.host, request); err != nil {
		t.Fatalf("handle draw: %v", err)
	}
	drawn := receivePrivateZoneEnvelope(t, setup.host)
	assertPrivateZoneFixture(t, "game-drawn.json", setup.room.ID, drawn)
	drawnData, err := drawn.Marshal()
	if err != nil {
		t.Fatalf("marshal draw acknowledgement: %v", err)
	}
	for _, name := range []string{"Lightning Bolt", "Counterspell", "Dark Ritual", "Ancestral Recall"} {
		if strings.Contains(string(drawnData), name) {
			t.Fatalf("draw acknowledgement leaked %q: %s", name, drawnData)
		}
	}

	owner := receiveGameSnapshot(t, setup.host, "draw owner")
	opponent := receiveGameSnapshot(t, setup.guest, "draw opponent")
	spectator := receiveGameSnapshot(t, setup.spectator, "draw spectator")
	if len(owner.Seats[0].Hand) != 3 || owner.Seats[0].HandCount != 3 ||
		owner.Seats[0].LibraryCount != 1 {
		t.Fatalf("owner draw projection = %+v", owner.Seats[0])
	}
	for role, snapshot := range map[string]protocol.GameSnapshot{
		"opponent": opponent, "spectator": spectator,
	} {
		seat := snapshot.Seats[0]
		if len(seat.Hand) != 0 || seat.HandCount != 3 || seat.LibraryCount != 1 {
			t.Fatalf("%s draw projection = %+v", role, seat)
		}
		encoded := marshalGameSnapshot(t, role, snapshot)
		for _, name := range []string{"Lightning Bolt", "Counterspell", "Dark Ritual", "Ancestral Recall"} {
			if strings.Contains(string(encoded), name) {
				t.Fatalf("%s learned drawn or remaining identity %q: %s", role, name, encoded)
			}
		}
	}
	for role, snapshot := range map[string]protocol.GameSnapshot{
		"owner": owner, "opponent": opponent, "spectator": spectator,
	} {
		if len(snapshot.Log) != 1 || snapshot.Log[0].Kind != "draw" ||
			snapshot.Log[0].Text != "Alice drew 3 cards." {
			t.Fatalf("%s draw log = %+v", role, snapshot.Log)
		}
		if strings.Contains(snapshot.Log[0].Text, "Lightning Bolt") ||
			strings.Contains(snapshot.Log[0].Text, "Counterspell") ||
			strings.Contains(snapshot.Log[0].Text, "Dark Ritual") {
			t.Fatalf("%s draw log leaked identity: %+v", role, snapshot.Log)
		}
	}
	ownerData := marshalGameSnapshot(t, "owner", owner)
	if strings.Contains(string(ownerData), "Ancestral Recall") {
		t.Fatalf("owner learned remaining library identity: %s", ownerData)
	}
}

func TestShuffleMatchesGoldenFixtureWithoutOrderDisclosure(t *testing.T) {
	setup := newPrivateZoneConsentSetup(t)
	cards := []protocol.GameCard{
		{ID: "library-card-a", Name: "Demonic Tutor", OwnerSeat: 0},
		{ID: "library-card-b", Name: "Vampiric Tutor", OwnerSeat: 0},
		{ID: "library-card-c", Name: "Mystical Tutor", OwnerSeat: 0},
	}
	setup.room.Game.Seats[0].Library = append([]protocol.GameCard(nil), cards...)

	request := loadPrivateZoneFixture(t, "game-shuffle-library.json")
	if err := setup.handler.handleGameShuffleLibrary(setup.host, request); err != nil {
		t.Fatalf("handle shuffle: %v", err)
	}
	shuffled := receivePrivateZoneEnvelope(t, setup.host)
	assertPrivateZoneFixture(t, "game-library-shuffled.json", setup.room.ID, shuffled)
	shuffledData, err := shuffled.Marshal()
	if err != nil {
		t.Fatalf("marshal shuffle acknowledgement: %v", err)
	}
	for _, card := range cards {
		if strings.Contains(string(shuffledData), card.ID) ||
			strings.Contains(string(shuffledData), card.Name) {
			t.Fatalf("shuffle acknowledgement leaked identity: %s", shuffledData)
		}
	}
	if len(setup.room.Game.Seats[0].Library) != len(cards) {
		t.Fatalf("shuffle changed library size: %+v", setup.room.Game.Seats[0].Library)
	}
	seen := make(map[string]bool, len(cards))
	for _, card := range setup.room.Game.Seats[0].Library {
		seen[card.ID] = true
	}
	for _, card := range cards {
		if !seen[card.ID] {
			t.Fatalf("shuffle lost card %q: %+v", card.ID, setup.room.Game.Seats[0].Library)
		}
	}

	for role, sess := range map[string]*Session{
		"owner": setup.host, "opponent": setup.guest, "spectator": setup.spectator,
	} {
		snapshot := receiveGameSnapshot(t, sess, "shuffle "+role)
		if snapshot.Seats[0].LibraryCount != len(cards) || len(snapshot.Log) != 1 ||
			snapshot.Log[0].Kind != "shuffle_library" ||
			snapshot.Log[0].Text != "Alice shuffled their library." {
			t.Fatalf("%s shuffle projection = seat=%+v log=%+v",
				role, snapshot.Seats[0], snapshot.Log)
		}
		encoded := marshalGameSnapshot(t, role, snapshot)
		for _, card := range cards {
			if strings.Contains(string(encoded), card.ID) ||
				strings.Contains(string(encoded), card.Name) {
				t.Fatalf("%s learned shuffled identity %q: %s", role, card.Name, encoded)
			}
		}
	}
}

func TestMulliganMatchesGoldenFixtureAndPrivateReplacementHand(t *testing.T) {
	setup := newPrivateZoneConsentSetup(t)
	allCards := make([]protocol.GameCard, 10)
	for index := range allCards {
		allCards[index] = protocol.GameCard{
			ID:   fmt.Sprintf("mulligan-%d", index),
			Name: fmt.Sprintf("Private Card %d", index), OwnerSeat: 0,
		}
	}
	setup.room.Game.Seats[0].Hand = append([]protocol.GameCard(nil), allCards[:3]...)
	setup.room.Game.Seats[0].Library = append([]protocol.GameCard(nil), allCards[3:]...)

	request := loadPrivateZoneFixture(t, "game-mulligan.json")
	if err := setup.handler.handleGameMulligan(setup.host, request); err != nil {
		t.Fatalf("handle mulligan: %v", err)
	}
	mulliganed := receivePrivateZoneEnvelope(t, setup.host)
	assertPrivateZoneFixture(t, "game-mulliganed.json", setup.room.ID, mulliganed)
	mulliganedData, err := mulliganed.Marshal()
	if err != nil {
		t.Fatalf("marshal mulligan acknowledgement: %v", err)
	}
	for _, card := range allCards {
		if strings.Contains(string(mulliganedData), card.Name) {
			t.Fatalf("mulligan acknowledgement leaked %q: %s", card.Name, mulliganedData)
		}
	}

	owner := receiveGameSnapshot(t, setup.host, "mulligan owner")
	opponent := receiveGameSnapshot(t, setup.guest, "mulligan opponent")
	spectator := receiveGameSnapshot(t, setup.spectator, "mulligan spectator")
	if len(owner.Seats[0].Hand) != 7 || owner.Seats[0].HandCount != 7 ||
		owner.Seats[0].LibraryCount != 3 || owner.Seats[0].MulliganCount != 1 {
		t.Fatalf("owner mulligan projection = %+v", owner.Seats[0])
	}
	for role, snapshot := range map[string]protocol.GameSnapshot{
		"opponent": opponent, "spectator": spectator,
	} {
		seat := snapshot.Seats[0]
		if len(seat.Hand) != 0 || seat.HandCount != 7 ||
			seat.LibraryCount != 3 || seat.MulliganCount != 1 {
			t.Fatalf("%s mulligan projection = %+v", role, seat)
		}
		encoded := marshalGameSnapshot(t, role, snapshot)
		for _, card := range allCards {
			if strings.Contains(string(encoded), card.Name) {
				t.Fatalf("%s learned replacement identity %q: %s", role, card.Name, encoded)
			}
		}
	}
	for role, snapshot := range map[string]protocol.GameSnapshot{
		"owner": owner, "opponent": opponent, "spectator": spectator,
	} {
		if len(snapshot.Log) != 1 || snapshot.Log[0].Kind != "mulligan" ||
			snapshot.Log[0].Text != "Alice took mulligan 1 and drew 7 cards." {
			t.Fatalf("%s mulligan log = %+v", role, snapshot.Log)
		}
	}
	ownerData := marshalGameSnapshot(t, "owner", owner)
	for _, card := range setup.room.Game.Seats[0].Library {
		if strings.Contains(string(ownerData), card.Name) {
			t.Fatalf("owner learned post-mulligan library identity %q: %s",
				card.Name, ownerData)
		}
	}
}

func TestRandomDiscardMatchesGoldenFixtureAndPublicGraveyardProjection(t *testing.T) {
	setup := newPrivateZoneConsentSetup(t)
	setup.room.Game.Seats[0].Hand = []protocol.GameCard{
		{ID: "discard-a", Name: "Private First", OwnerSeat: 0},
		{ID: "discard-b", Name: "Public Choice", OwnerSeat: 0},
		{ID: "discard-c", Name: "Private Third", OwnerSeat: 0},
	}
	request := loadPrivateZoneFixture(t, "game-discard-hand.json")
	if err := setup.handler.handleGameDiscardHand(setup.host, request); err != nil {
		t.Fatalf("handle discard hand: %v", err)
	}
	discarded := receivePrivateZoneEnvelope(t, setup.host)
	assertPrivateZoneFixture(t, "game-hand-discarded.json", setup.room.ID, discarded)
	discardedData, err := discarded.Marshal()
	if err != nil {
		t.Fatalf("marshal discard acknowledgement: %v", err)
	}
	for _, name := range []string{"Private First", "Public Choice", "Private Third"} {
		if strings.Contains(string(discardedData), name) {
			t.Fatalf("discard acknowledgement leaked %q: %s", name, discardedData)
		}
	}

	owner := receiveGameSnapshot(t, setup.host, "discard owner")
	opponent := receiveGameSnapshot(t, setup.guest, "discard opponent")
	spectator := receiveGameSnapshot(t, setup.spectator, "discard spectator")
	if len(owner.Seats[0].Graveyard) != 1 {
		t.Fatalf("owner discard projection = %+v", owner.Seats[0])
	}
	discardedName := owner.Seats[0].Graveyard[0].Name
	for role, snapshot := range map[string]protocol.GameSnapshot{
		"owner": owner, "opponent": opponent, "spectator": spectator,
	} {
		seat := snapshot.Seats[0]
		if seat.HandCount != 2 || len(seat.Graveyard) != 1 ||
			seat.Graveyard[0].Name != discardedName ||
			len(snapshot.Log) != 1 ||
			snapshot.Log[0].Kind != "discard_random" {
			t.Fatalf("%s discard projection = seat=%+v log=%+v",
				role, seat, snapshot.Log)
		}
		encoded := marshalGameSnapshot(t, role, snapshot)
		if role != "owner" {
			for _, name := range []string{"Private First", "Public Choice", "Private Third"} {
				if name != discardedName && strings.Contains(string(encoded), name) {
					t.Fatalf("%s learned remaining hand identity %q: %s",
						role, name, encoded)
				}
			}
		}
	}
}
