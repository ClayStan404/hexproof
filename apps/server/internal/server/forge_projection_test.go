// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
)

func TestForgeLinkedExileUsesOnlyVisibleExileObjects(t *testing.T) {
	game := forgeRoomGame{gameID: "game", playerToSeat: map[int]int{0: 0, 1: 1}}
	view := forge.GameView{GameID: "game", ActivePlayerID: "player-0", PriorityPlayerID: "player-1",
		Players: []forge.PlayerView{{ID: "player-0"}, {ID: "player-1"}},
		Zones: []forge.ZoneView{
			{Zone: "battlefield", OwnerID: "player-0", Cards: []forge.CardView{
				{ID: "labyrinth-a", ExiledCardCount: 2, ExiledCardIDs: []string{"visible", "hidden", "hand", "departed", "visible"}},
				{ID: "labyrinth-b"},
			}},
			{Zone: "exile", OwnerID: "player-0", Cards: []forge.CardView{
				{ID: "visible", Visibility: "visible", Identity: &forge.CardIdentityView{Name: "Devourer of Destiny"}},
				{ID: "hidden", Visibility: "hidden", Identity: &forge.CardIdentityView{Name: "SECRET"}},
			}},
			{Zone: "hand", OwnerID: "player-0", Cards: []forge.CardView{
				{ID: "hand", Visibility: "visible", Identity: &forge.CardIdentityView{Name: "Returned card"}},
			}},
		}}
	snapshot, err := normalizeForgeSnapshot("ROOM", game, view)
	if err != nil {
		t.Fatal(err)
	}
	a, b := snapshot.Zones[0].Cards[0], snapshot.Zones[0].Cards[1]
	if a.ExiledCardCount != 2 || !reflect.DeepEqual(a.ExiledCardIDs, []string{"visible"}) ||
		b.ExiledCardCount != 0 || len(b.ExiledCardIDs) != 0 {
		t.Fatalf("unsafe or misattributed linked exile: %+v / %+v", a, b)
	}
}

func TestForgeStackTargetsJoinOnlyViewerObjects(t *testing.T) {
	game := forgeRoomGame{gameID: "game", playerToSeat: map[int]int{0: 1, 1: 0}}
	view := forge.GameView{GameID: "game", ActivePlayerID: "player-0", PriorityPlayerID: "player-1",
		Players: []forge.PlayerView{{ID: "player-0", Name: "Alice"}, {ID: "player-1", Name: "Bob"}},
		Zones: []forge.ZoneView{{Zone: "battlefield", OwnerID: "player-0", Cards: []forge.CardView{
			{ID: "same-name-1", Visibility: "visible", Identity: &forge.CardIdentityView{Name: "Bear"}},
			{ID: "same-name-2", Visibility: "visible", Identity: &forge.CardIdentityView{Name: "Bear"}},
			{ID: "face-down", Visibility: "hidden", Identity: &forge.CardIdentityView{Name: "PRIVATE"}},
		}}},
		Stack: []forge.StackObjectView{
			{ID: "counter", ControllerID: "player-1", Identity: forge.CardIdentityView{Name: "Counterspell"}, Targets: []forge.StackTargetView{
				{Kind: "spell", ID: "spell"}, {Kind: "card", ID: "same-name-2"}, {Kind: "player", ID: "player-0"},
				{Kind: "card", ID: "face-down"}, {Kind: "card", ID: "private-hand"}, {Kind: "spell", ID: "departed-spell"},
				{Kind: "card", ID: "same-name-2"}, {Kind: "player", ID: "player-9"}, {Kind: "unknown", ID: "same-name-1"},
			}},
			{ID: "spell", ControllerID: "player-0"},
		}}
	snapshot, err := normalizeForgeSnapshot("ROOM", game, view)
	if err != nil {
		t.Fatal(err)
	}
	seat := 1
	want := []protocol.RulesStackTarget{{Kind: "spell", ObjectID: "spell"}, {Kind: "card", ObjectID: "same-name-2", Label: "Bear"},
		{Kind: "player", Seat: &seat, Label: "Alice"}, {Kind: "card", ObjectID: "face-down"}}
	if !reflect.DeepEqual(snapshot.Stack[0].Targets, want) {
		t.Fatalf("unsafe or incorrect stack relationships: %#v", snapshot.Stack[0].Targets)
	}
	if snapshot.Stack[0].ID != "counter" || snapshot.Stack[1].ID != "spell" {
		t.Fatal("projection reordered the native top-first stack")
	}
	data, _ := json.Marshal(snapshot.Stack)
	for _, secret := range []string{"PRIVATE", "private-hand", "departed-spell", "player-0", "player-9"} {
		if strings.Contains(string(data), secret) {
			t.Fatalf("stack relationship leaked %q", secret)
		}
	}
}

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

func TestForgeCommanderHistoryCannotRevealHiddenObject(t *testing.T) {
	view := forge.GameView{Zones: []forge.ZoneView{{Zone: "command", Cards: []forge.CardView{
		{ID: "visible", Visibility: "visible", Identity: &forge.CardIdentityView{Name: "Commander"}},
		{ID: "anonymous", Visibility: "visible", Identity: &forge.CardIdentityView{}},
	}}}}
	for _, test := range []struct{ id, zone, expected string }{
		{"visible", "command", "visible"}, {"anonymous", "command", ""},
		{"private", "library", ""}, {"visible", "hand", ""},
	} {
		input := []forge.CommanderView{{Name: "Commander", Casts: 2, Tax: 4, Zone: test.zone, ObjectID: test.id},
			{Name: "Partner", Casts: 0, Tax: 0, Zone: "hidden"}}
		result := projectedRulesCommanders(input, view)
		if len(result) != 2 || result[0].Casts != 2 || result[0].Tax != 4 || result[1].Tax != 0 || result[0].ObjectID != test.expected {
			t.Fatalf("commander projection = %+v", result)
		}
		if test.expected == "" && result[0].Zone != "hidden" {
			t.Fatal("hidden object location leaked")
		}
	}
	view.Stack = []forge.StackObjectView{{SourceID: "spell", Identity: forge.CardIdentityView{Name: "Commander"}}}
	result := projectedRulesCommanders([]forge.CommanderView{{Name: "Commander", Casts: 3, Tax: 6, Zone: "stack", ObjectID: "spell"}}, view)
	if result[0].Zone != "stack" || result[0].ObjectID != "spell" {
		t.Fatal("public stack commander link lost")
	}
}
