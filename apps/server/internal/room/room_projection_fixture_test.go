// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"hexproof/server/internal/protocol"
)

func assertGameSnapshotFixture(t *testing.T, name string, seq int64,
	snapshot protocol.GameSnapshot) {
	t.Helper()
	envelope, err := protocol.NewEnvelope(protocol.TypeGameSnapshot, snapshot)
	if err != nil {
		t.Fatalf("build snapshot envelope: %v", err)
	}
	envelope = envelope.WithSeq(seq)
	got, err := json.MarshalIndent(envelope, "", "  ")
	if err != nil {
		t.Fatalf("marshal snapshot envelope: %v", err)
	}
	got = append(got, '\n')

	fixturePath := filepath.Join("../../../../testdata/protocol/v1", name)
	if os.Getenv("UPDATE_PROTOCOL_FIXTURES") == "1" {
		if err := os.WriteFile(fixturePath, got, 0o644); err != nil {
			t.Fatalf("update fixture: %v", err)
		}
	}
	want, err := os.ReadFile(fixturePath)
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}
	var gotValue, wantValue any
	if err := json.Unmarshal(got, &gotValue); err != nil {
		t.Fatalf("decode generated snapshot: %v", err)
	}
	if err := json.Unmarshal(want, &wantValue); err != nil {
		t.Fatalf("decode fixture snapshot: %v", err)
	}
	if !reflect.DeepEqual(gotValue, wantValue) {
		t.Fatalf("game projection drifted from %s:\nwant: %s\n got: %s",
			name, want, got)
	}
}

func TestFaceDownPrivacyProjectionsMatchGoldenFixtures(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("spectator-conn", "Watcher", true, ""); err != nil {
		t.Fatalf("join spectator: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Score = []int{0, 0}
	faceDownCounters := defaultPlayerCounters()
	faceDownCounters[0].Label = "Poison"
	faceDownCounters[0].Value = 2
	r.Game = &GameState{
		Number:       1,
		StartingSeat: 0,
		ActiveSeat:   0,
		CurrentPhase: protocol.GamePhaseFirstMain,
		Seats: []PlayerGameState{{
			Seat:        0,
			DisplayName: "Alice",
			Life:        20,
			Counters:    faceDownCounters,
			Library:     []protocol.GameCard{{ID: "library-1", OwnerSeat: 0}},
			Hand: []protocol.GameCard{{
				ID: "hand-secret", Name: "Demonic Tutor", SetCode: "UMA",
				CollectorNumber: "93", OwnerSeat: 0,
			}},
			Battlefield: []protocol.GameCard{{
				ID: "face-down-1", Name: "Secret permanent", SetCode: "TST",
				CollectorNumber: "1", OwnerSeat: 0, FaceDown: true,
				Position: &protocol.CardPosition{X: 0.5, Y: 0.4},
			}},
			Graveyard: []protocol.GameCard{},
			Exile:     []protocol.GameCard{},
		}},
		Stack:       []protocol.GameSharedCard{},
		Revealed:    []protocol.GameSharedCard{},
		Arrows:      []protocol.GameArrow{},
		Attachments: []protocol.GameAttachment{},
		Log: []protocol.GameLogEntry{{
			ID: 1, Kind: "set_face_down", Seat: 0,
			Text: "Alice turned a card face down.",
		}},
		NextLogID: 2,
	}

	owner, err := r.GameSnapshot("host-conn")
	if err != nil {
		t.Fatalf("owner snapshot: %v", err)
	}
	spectator, err := r.GameSnapshot("spectator-conn")
	if err != nil {
		t.Fatalf("spectator snapshot: %v", err)
	}
	assertGameSnapshotFixture(t, "game-snapshot-face-down-owner.json", 43, owner)
	assertGameSnapshotFixture(t, "game-snapshot-face-down-spectator.json", 43,
		spectator)
}

func TestPublicMoveProjectionsMatchGoldenFixtures(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("guest-conn", "Bob", false, ""); err != nil {
		t.Fatalf("join guest: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Score = []int{0, 0}
	r.Game = &GameState{
		Number:       1,
		StartingSeat: 1,
		ActiveSeat:   1,
		CurrentPhase: protocol.GamePhaseUntap,
		Seats: []PlayerGameState{
			{
				Seat: 0, DisplayName: "Alice", Life: 20,
				Counters: defaultPlayerCounters(),
				Library:  []protocol.GameCard{{ID: "s0-library-1", OwnerSeat: 0}},
				Hand: []protocol.GameCard{
					{ID: "s0-c1", Name: "Lightning Bolt", SetCode: "M11", CollectorNumber: "149", OwnerSeat: 0},
					{ID: "s0-c2", Name: "Mountain", SetCode: "M11", CollectorNumber: "242", OwnerSeat: 0},
				},
				Battlefield: []protocol.GameCard{}, Graveyard: []protocol.GameCard{},
				Exile: []protocol.GameCard{},
			},
			{
				Seat: 1, DisplayName: "Bob", Life: 20,
				Counters: defaultPlayerCounters(),
				Library:  []protocol.GameCard{{ID: "s1-library-1", OwnerSeat: 1}},
				Hand: []protocol.GameCard{{
					ID: "s1-c1", Name: "Island", SetCode: "M11",
					CollectorNumber: "235", OwnerSeat: 1,
				}},
				Battlefield: []protocol.GameCard{}, Graveyard: []protocol.GameCard{},
				Exile: []protocol.GameCard{},
			},
		},
		Stack:       []protocol.GameSharedCard{},
		Revealed:    []protocol.GameSharedCard{},
		Arrows:      []protocol.GameArrow{},
		Attachments: []protocol.GameAttachment{},
		Log:         []protocol.GameLogEntry{},
		NextLogID:   1,
	}

	if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: "s0-c1", FromZone: protocol.ZoneHand,
		ToZone:   protocol.ZoneBattlefield,
		Position: &protocol.CardPosition{X: 0.25, Y: 0.6},
	}); err != nil {
		t.Fatalf("move card: %v", err)
	}
	owner, err := r.GameSnapshot("host-conn")
	if err != nil {
		t.Fatalf("owner snapshot: %v", err)
	}
	opponent, err := r.GameSnapshot("guest-conn")
	if err != nil {
		t.Fatalf("opponent snapshot: %v", err)
	}
	assertGameSnapshotFixture(t, "game-snapshot-move-owner.json", 14, owner)
	assertGameSnapshotFixture(t, "game-snapshot-move-opponent.json", 14, opponent)
}
