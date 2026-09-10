// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
)

func TestForgeSpectatorHandPermissionDoesNotExtendOtherPrivateZones(t *testing.T) {
	public := protocol.RulesGameSnapshot{RoomID: "ROOM", GameID: "game-1",
		Zones: []protocol.RulesZoneState{
			{Zone: "hand", OwnerSeat: 0, Count: 1, Cards: []protocol.RulesCardState{}},
			{Zone: "library", OwnerSeat: 0, Count: 53, Cards: []protocol.RulesCardState{}},
			{Zone: "battlefield", OwnerSeat: 0, Count: 1, Cards: []protocol.RulesCardState{{ID: "face-down", FaceDown: true}}},
		}}
	card := func(name string) protocol.RulesCardState {
		return protocol.RulesCardState{ID: name, Visible: true, Identity: &protocol.RulesCardIdentity{Name: name}}
	}
	owner := protocol.RulesGameSnapshot{RoomID: "ROOM", GameID: "game-1",
		Zones: []protocol.RulesZoneState{
			{Zone: "hand", OwnerSeat: 0, Count: 1, Cards: []protocol.RulesCardState{card("Authorized hand")}},
			{Zone: "library", OwnerSeat: 0, Count: 53, Cards: []protocol.RulesCardState{card("SECRET LIBRARY")}},
			{Zone: "sideboard", OwnerSeat: 0, Count: 15, Cards: []protocol.RulesCardState{card("SECRET SIDEBOARD")}},
			{Zone: "battlefield", OwnerSeat: 0, Count: 1, Cards: []protocol.RulesCardState{card("SECRET FACE")}},
		}}
	for _, enabled := range []bool{false, true} {
		result := rulesSpectatorSnapshot(public, map[int]protocol.RulesGameSnapshot{0: owner}, enabled)
		data, _ := json.Marshal(result)
		if strings.Contains(string(data), "SECRET") || strings.Contains(string(data), "Authorized hand") != enabled {
			t.Fatalf("spectator permission=%v leaked/omitted identity: %s", enabled, data)
		}
	}
	if len(public.Zones[0].Cards) != 0 || public.Zones[2].Cards[0].Identity != nil {
		t.Fatal("hand-visible projection mutated the public journal/replay base")
	}
	owner.GameID = "previous-game"
	result := rulesSpectatorSnapshot(public, map[int]protocol.RulesGameSnapshot{0: owner}, true)
	if len(result.Zones[0].Cards) != 0 {
		t.Fatal("hand permission copied an old game's identity")
	}
}

func TestForgeSnapshotUsesRulesTablePhaseKeys(t *testing.T) {
	// Every step emitted by the pinned InteractiveSnapshotExtractor, including
	// both combat damage boundaries and the unchanged main1/main2 wire keys.
	for _, test := range []struct{ upstream, expected string }{
		{"untap", "untap"},
		{"upkeep", "upkeep"},
		{"draw", "draw"},
		{"main1", "main1"},
		{"combatBegin", "begin_combat"},
		{"combatDeclareAttackers", "declare_attackers"},
		{"combatDeclareBlockers", "declare_blockers"},
		{"combatFirstStrikeDamage", "combat_damage"},
		{"combatDamage", "combat_damage"},
		{"combatEnd", "end_combat"},
		{"main2", "main2"},
		{"endOfTurn", "end"},
		{"cleanup", "cleanup"},
	} {
		t.Run(test.upstream, func(t *testing.T) {
			game := forgeRoomGame{gameID: "game-1", playerToSeat: map[int]int{0: 0, 1: 1}}
			view := forge.GameView{
				GameID: game.gameID, Turn: 3, Step: test.upstream,
				ActivePlayerID: "player-0", PriorityPlayerID: "player-1",
				Players: []forge.PlayerView{
					{ID: "player-0", Name: "Alice", Status: "playing", Life: 20},
					{ID: "player-1", Name: "Bob", Status: "playing", Life: 17},
				},
			}
			snapshot, err := normalizeForgeSnapshot("ROOM", game, view)
			if err != nil {
				t.Fatal(err)
			}
			if snapshot.Step != test.expected || snapshot.Turn != 3 || snapshot.ActiveSeat != 0 || snapshot.PrioritySeat != 1 {
				t.Fatalf("projected phase = %q (turn %d, active %d, priority %d), want %q",
					snapshot.Step, snapshot.Turn, snapshot.ActiveSeat, snapshot.PrioritySeat, test.expected)
			}
			if normalizedRulesStep(snapshot.Step) != snapshot.Step {
				t.Fatal("phase normalization changes an already normalized display key")
			}
			envelope, err := protocol.NewEnvelope(protocol.TypeRulesSnapshot, snapshot)
			if err != nil {
				t.Fatal(err)
			}
			assertNormalizedRulesWireArrays(t, envelope)
		})
	}
}
