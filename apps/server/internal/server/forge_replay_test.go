// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func TestForgeReplayRetainsPublicJournalWithoutEngineOrPrivateProjection(t *testing.T) {
	now := time.Now().UTC()
	store, err := newRetentionStore(t.TempDir(), time.Hour, 32, 8<<20, now)
	if err != nil {
		t.Fatal(err)
	}
	r, err := room.NewWithRulesMode("PUBLIC", "Forge replay", protocol.FormatModern,
		protocol.MatchBO1, protocol.CardLoadBackground, protocol.RulesModeForge,
		2, true, false, "Alice", "secret-connection", now)
	if err != nil {
		t.Fatal(err)
	}
	r.Seats[1] = room.Seat{Occupied: true, DisplayName: "Bob", ConnectionID: "secret-guest"}
	r.Seats[0].Deck = &protocol.DeckSelect{Name: "SECRET DECK", Mainboard: []protocol.DeckCard{{Name: "SECRET CARD", Count: 7}}}
	r.Phase = protocol.RoomPhaseStarted
	r.ResetRulesLog()
	r.ObserveRulesPublicState(protocol.RulesGameSnapshot{
		RoomID: r.ID, GameID: "PUBLIC-1", Turn: 1, Step: "main1",
		Players: []protocol.RulesPlayerState{{Seat: 0, Life: 20}, {Seat: 1, Life: 20}},
		Zones: []protocol.RulesZoneState{
			{Zone: "hand", OwnerSeat: 0, Count: 7, Cards: []protocol.RulesCardState{{ID: "secret-hand-id", Visible: true,
				Identity: &protocol.RulesCardIdentity{Name: "SECRET HAND"}}}},
			{Zone: "battlefield", OwnerSeat: 0, Count: 1, Cards: []protocol.RulesCardState{{ID: "public-land", Visible: true,
				Identity: &protocol.RulesCardIdentity{Name: "Forest"}}}},
		},
	})
	if _, err := r.SayRules("secret-connection", protocol.GameSay{Message: "Hello Bob"}); err != nil {
		t.Fatal(err)
	}
	for _, terminal := range []bool{false, true} {
		if terminal {
			if _, err := r.CompleteRulesGame(1, now); err != nil {
				t.Fatal(err)
			}
		}
		record := store.snapshot(r, now)
		if record == nil || len(record.Game.Log) == 0 {
			t.Fatalf("missing Forge journal, terminal=%v", terminal)
		}
		if err := store.saveSnapshot(record); err != nil {
			t.Fatal(err)
		}
		replays, total, err := store.list(now, 0, 20)
		if err != nil || total < 1 {
			t.Fatalf("list: %d %v", total, err)
		}
		loaded, err := store.load(replays[0].ReplayID, now)
		if err != nil {
			t.Fatal(err)
		}
		data, _ := json.Marshal(loaded)
		for _, forbidden := range []string{"SECRET", "secret-connection", "secret-guest", "secret-hand-id", "mainboard", "sideboard"} {
			if strings.Contains(string(data), forbidden) {
				t.Fatalf("public replay leaked %s: %s", forbidden, data)
			}
		}
		if !strings.Contains(string(data), "Forest") || !strings.Contains(string(data), "Hello Bob") {
			t.Fatalf("public journal missing in replay: %s", data)
		}
		record.Game.Log[0].Text = "mutated capture"
		if r.RulesLog[0].Text == "mutated capture" {
			t.Fatal("retained record aliases live rules journal")
		}
		now = now.Add(time.Second)
	}
}

func TestForgeCompletedReplayIsNotArchivedAgainAfterReturnAndDisband(t *testing.T) {
	now := time.Now().UTC()
	store, err := newRetentionStore(t.TempDir(), time.Hour, 32, 8<<20, now)
	if err != nil {
		t.Fatal(err)
	}
	r, err := room.NewWithRulesMode("REPLAY", "Finished rules", protocol.FormatModern,
		protocol.MatchBO1, protocol.CardLoadBackground, protocol.RulesModeForge,
		2, true, false, "Alice", "alice", now)
	if err != nil {
		t.Fatal(err)
	}
	r.Seats[1] = room.Seat{Occupied: true, DisplayName: "Bob", ConnectionID: "bob"}
	r.Phase = protocol.RoomPhaseStarted
	r.AppendRulesLog("rules_result", 1, "Bob won the game.")
	if _, err := r.CompleteRulesGame(1, now); err != nil {
		t.Fatal(err)
	}
	// This is the handler's capture-before-reduce, save-after-unlock ordering.
	record := store.snapshot(r, now)
	if _, err := r.ReturnToRoom("alice"); err != nil {
		t.Fatal(err)
	}
	if err := store.saveSnapshot(record); err != nil {
		t.Fatal(err)
	}
	if duplicate := store.snapshot(r, now.Add(time.Second)); duplicate != nil {
		t.Fatal("waiting room reused an already archived journal as an interrupted game")
	}
	if _, err := r.Leave("alice"); err != nil {
		t.Fatal(err)
	}
	if duplicate := store.snapshot(r, now.Add(2*time.Second)); duplicate != nil {
		t.Fatal("disbanding archived the completed Forge journal twice")
	}
	entries, total, err := store.list(now, 0, 20)
	if err != nil || total != 1 {
		t.Fatalf("expected one completed replay: %d %v", total, err)
	}
	loaded, err := store.load(entries[0].ReplayID, now)
	if err != nil || len(loaded.Log) != 1 {
		t.Fatalf("clearing live history damaged the independent completed capture: %+v %v", loaded, err)
	}
}
