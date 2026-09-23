// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"fmt"
	"reflect"
	"slices"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
	"hexproof/server/internal/rulesinput"
)

func TestRulesPromptsKeepRequiredWireArrays(t *testing.T) {
	for _, kind := range []string{
		"", "diceRolled", "mulligan", "mulliganPutBack", "chooseAction", "payManaCost",
		"chooseCards", "revealCards", "chooseBoardTargets", "chooseAttackers", "chooseBlockers",
		"chooseBoolean", "chooseColor", "chooseFromSelection", "chooseNumber", "reorder", "scry",
		"chooseDamageAssignmentOrder", "chooseCombatDamageAssignment", "unsupported",
	} {
		t.Run(kind, func(t *testing.T) {
			prompt := emptyRulesPrompt("ROOM", "game-1")
			if kind != "" {
				view := forge.PromptView{PromptID: 1, Kind: kind, Supported: kind != "unsupported"}
				if kind == "scry" {
					view.ScryDestinations = []string{"libraryTop", "libraryBottom"}
				}
				if kind == "chooseCombatDamageAssignment" {
					view.DamageAssignmentMode = protocol.RulesDamageUnordered
				}
				var err error
				prompt, err = projectedRulesPrompt("ROOM", "game-1", view, forgeRoomGame{}, nil)
				if err != nil {
					t.Fatal(err)
				}
			}
			envelope, err := protocol.NewEnvelope(protocol.TypeRulesPrompt, prompt)
			if err != nil {
				t.Fatal(err)
			}
			assertNormalizedRulesWireArrays(t, envelope)
		})
	}
}

func TestRulesCombatSourceWithNoTargetsKeepsWireArray(t *testing.T) {
	prompt, err := projectedRulesPrompt("ROOM", "game-1", forge.PromptView{
		PromptID: 1, Kind: "chooseBlockers", Supported: true,
		CombatSources: []forge.PromptCombatSource{{ResponseID: "combat-source:0", ID: "card-a"}},
	}, forgeRoomGame{}, &forge.GameView{
		Zones: []forge.ZoneView{{Cards: []forge.CardView{{ID: "card-a", Visibility: "visible",
			Identity: &forge.CardIdentityView{Name: "Grizzly Bears"}}}}},
	})
	if err != nil {
		t.Fatal(err)
	}
	envelope, err := protocol.NewEnvelope(protocol.TypeRulesPrompt, prompt)
	if err != nil {
		t.Fatal(err)
	}
	assertNormalizedRulesWireArrays(t, envelope)
}

func TestProjectedRulesPromptPreservesReadOnlyCards(t *testing.T) {
	view, err := forge.NormalizePrompt(json.RawMessage(`{"promptId":1,"decidingPlayerId":"player-0","input":{
        "type":"chooseCards","min":0,"max":1,"cards":[
        {"id":"hidden-library-land","identity":{"name":"Forest"},"readOnly":true},
        {"id":"candidate","identity":{"name":"Island"}}]}}`))
	if err != nil {
		t.Fatal(err)
	}
	prompt, err := projectedRulesPrompt("ROOM", "game-1", view, forgeRoomGame{}, nil)
	if err != nil || len(prompt.Cards) != 2 || !prompt.Cards[0].ReadOnly || prompt.Cards[1].ReadOnly {
		t.Fatalf("combined prompt = %+v, %v", prompt, err)
	}
	data, err := json.Marshal(prompt)
	if err != nil || strings.Contains(string(data), "hidden-library-land") || !strings.Contains(string(data), `"readOnly":true`) {
		t.Fatalf("read-only identity projection = %s, %v", data, err)
	}
}

// Go accepts both null and [] when decoding a slice; Qt's protocol model
// correctly requires arrays. Check the wire before decoding it into Go DTOs,
// including nested arrays and any future array fields added to these types.
func assertNormalizedRulesWireArrays(t *testing.T, envelope protocol.Envelope) {
	t.Helper()
	var expected reflect.Type
	switch envelope.Type {
	case protocol.TypeRulesPrompt:
		expected = reflect.TypeOf(protocol.RulesPrompt{})
	case protocol.TypeRulesSnapshot:
		expected = reflect.TypeOf(protocol.RulesGameSnapshot{})
	default:
		return
	}
	var decoded any
	if err := json.Unmarshal(envelope.Payload, &decoded); err != nil {
		t.Fatal(err)
	}
	assertRulesArrayFields(t, envelope.Type, decoded, expected)
}

func assertRulesArrayFields(t *testing.T, path string, decoded any, expected reflect.Type) {
	t.Helper()
	switch expected.Kind() {
	case reflect.Pointer:
		if decoded != nil {
			assertRulesArrayFields(t, path, decoded, expected.Elem())
		}
	case reflect.Struct:
		object, ok := decoded.(map[string]any)
		if !ok {
			t.Fatalf("%s is not an object", path)
		}
		for index := 0; index < expected.NumField(); index++ {
			field := expected.Field(index)
			tag := strings.Split(field.Tag.Get("json"), ",")
			name := tag[0]
			if _, present := object[name]; !present && slices.Contains(tag[1:], "omitempty") {
				// Optional compatibility fields may be absent. If present,
				// arrays still must be actual arrays rather than JSON null.
				continue
			}
			if name != "" && name != "-" {
				assertRulesArrayFields(t, path+"."+name, object[name], field.Type)
			}
		}
	case reflect.Slice:
		array, ok := decoded.([]any)
		if !ok {
			t.Fatalf("%s must be a JSON array, not null or absent", path)
		}
		for index, item := range array {
			assertRulesArrayFields(t, fmt.Sprintf("%s[%d]", path, index), item, expected.Elem())
		}
	}
}

func TestProjectedRulesPromptTargetsUseViewerProjection(t *testing.T) {
	game := forgeRoomGame{
		gameID: "game-1", playerToSeat: map[int]int{0: 2, 1: 0},
	}
	prompt, err := projectedRulesPrompt("ROOM", "game-1", forge.PromptView{
		PromptID: 8, PlayerIndex: 0, Kind: "chooseBoardTargets", Supported: true,
		Title: "Choose targets", MinSelected: 1, MaxSelected: 2, Cancellable: true,
		Targets: []forge.PromptTarget{
			{ResponseID: "target:0", Kind: "player", ID: "player-1"},
			{ResponseID: "target:1", Kind: "card", ID: "card-a", Selected: true},
			{ResponseID: "target:2", Kind: "spell", ID: "stack-a"},
		},
	}, game, &forge.GameView{
		Players: []forge.PlayerView{{ID: "player-0", Name: "Alice"},
			{ID: "player-1", Name: "Bob"}},
		Zones: []forge.ZoneView{{Zone: "battlefield", OwnerID: "player-0",
			Cards: []forge.CardView{{
				Visibility: "visible", ID: "card-a",
				Identity: &forge.CardIdentityView{
					Name: "Lightning Bolt", SetCode: "M11", CardNumber: "149",
				},
			}}}},
		Stack: []forge.StackObjectView{{
			ID: "stack-a", Identity: forge.CardIdentityView{
				Name: "Counterspell", SetCode: "MH2", CardNumber: "267",
			},
		}},
	})
	if err != nil {
		t.Fatalf("projectedRulesPrompt: %v", err)
	}
	if len(prompt.Targets) != 3 || prompt.Targets[0].Label != "Bob · Seat 1" ||
		prompt.Targets[0].Seat == nil || *prompt.Targets[0].Seat != 0 ||
		prompt.Targets[1].Seat != nil || prompt.Targets[2].Seat != nil ||
		prompt.Targets[1].Name != "Lightning Bolt" ||
		!prompt.Targets[1].Selected || prompt.Targets[0].Selected || prompt.Targets[2].Selected ||
		prompt.Targets[2].Name != "Counterspell" || prompt.Minimum != 1 ||
		prompt.Maximum != 2 || !prompt.Cancellable {
		t.Fatalf("prompt targets = %+v", prompt)
	}
	encoded, err := json.Marshal(prompt)
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}
	if strings.Contains(string(encoded), "player-1") {
		t.Fatalf("prompt leaked Forge player id: %s", encoded)
	}
	if !strings.Contains(string(encoded), `"seat":0`) {
		t.Fatalf("zero-based player seat was omitted: %s", encoded)
	}
}

func TestProjectedRulesTargetSeatsDoNotDependOnNamesOrPlayerOrder(t *testing.T) {
	game := forgeRoomGame{playerToSeat: map[int]int{0: 3, 1: 0}}
	view := forge.GameView{
		Players: []forge.PlayerView{{ID: "player-1", Name: "Alex"}, {ID: "player-0", Name: "Alex"}},
		Zones: []forge.ZoneView{{Zone: "battlefield", OwnerID: "player-0", Cards: []forge.CardView{{
			ID: "face-down-card", Visibility: "hidden",
		}}}},
	}
	targets, err := projectedRulesTargets([]forge.PromptTarget{
		{ResponseID: "target:0", Kind: "player", ID: "player-0"},
		{ResponseID: "target:1", Kind: "player", ID: "player-1"},
		{ResponseID: "target:2", Kind: "card", ID: "face-down-card"},
	}, game, view)
	if err != nil {
		t.Fatal(err)
	}
	if len(targets) != 3 || targets[0].Seat == nil || *targets[0].Seat != 3 ||
		targets[1].Seat == nil || *targets[1].Seat != 0 {
		t.Fatalf("player target seats do not match public room seats: %+v", targets)
	}
	if targets[2].ObjectID != "face-down-card" || targets[2].Label != "Face-down card" ||
		targets[2].Seat != nil || targets[2].Name != "" || targets[2].SetCode != "" ||
		targets[2].CollectorNumber != "" {
		t.Fatalf("hidden target identity changed: %+v", targets[2])
	}
	delete(game.playerToSeat, 0)
	if _, err := projectedRulesTargets([]forge.PromptTarget{{
		ResponseID: "target:0", Kind: "player", ID: "player-0",
	}}, game, view); err == nil {
		t.Fatal("player target without a room seat must not be projected")
	}
}

func TestProjectedRulesPromptCombatUsesViewerProjection(t *testing.T) {
	game := forgeRoomGame{
		gameID: "game-1", playerToSeat: map[int]int{0: 2, 1: 0},
	}
	prompt, err := projectedRulesPrompt("ROOM", "game-1", forge.PromptView{
		PromptID: 9, PlayerIndex: 0, Kind: "chooseAttackers", Supported: true,
		Title: "Declare attackers",
		CombatSources: []forge.PromptCombatSource{{
			ResponseID: "combat-source:0", ID: "card-a",
			ValidTargetIDs:   []string{"combat-target:0", "combat-target:1"},
			Maximum:          1,
			MustAssignIfAble: true,
		}},
		CombatTargets: []forge.PromptCombatTarget{
			{ResponseID: "combat-target:0", Kind: "player", ID: "player-1", Maximum: 1},
			{ResponseID: "combat-target:1", Kind: "planeswalker", ID: "card-w", Maximum: 1},
		},
	}, game, &forge.GameView{
		Players: []forge.PlayerView{{ID: "player-0", Name: "Alice"},
			{ID: "player-1", Name: "Bob"}},
		Zones: []forge.ZoneView{{Zone: "battlefield", OwnerID: "player-0",
			Cards: []forge.CardView{
				{Visibility: "visible", ID: "card-a", Identity: &forge.CardIdentityView{
					Name: "Goblin Guide", SetCode: "ZEN", CardNumber: "126",
				}},
				{Visibility: "visible", ID: "card-w", Identity: &forge.CardIdentityView{
					Name: "Jace", SetCode: "WWK", CardNumber: "31",
				}},
			}}},
	})
	if err != nil {
		t.Fatalf("projectedRulesPrompt: %v", err)
	}
	if len(prompt.CombatSources) != 1 || prompt.CombatSources[0].Name != "Goblin Guide" ||
		!prompt.CombatSources[0].MustAssignIfAble || len(prompt.CombatTargets) != 2 ||
		prompt.CombatSources[0].Maximum == nil || *prompt.CombatSources[0].Maximum != 1 ||
		prompt.CombatTargets[0].Label != "Bob · Seat 1" || prompt.CombatTargets[0].Seat == nil || *prompt.CombatTargets[0].Seat != 0 ||
		prompt.CombatTargets[1].Name != "Jace" {
		t.Fatalf("combat prompt = %+v", prompt)
	}
	encoded, err := json.Marshal(prompt)
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}
	if strings.Contains(string(encoded), "player-1") {
		t.Fatalf("combat prompt leaked Forge player id: %s", encoded)
	}
}

func TestProjectedRulesPromptChoicesHideCanonicalValues(t *testing.T) {
	prompt, err := projectedRulesPrompt("ROOM", "game-1", forge.PromptView{
		PromptID: 10, PlayerIndex: 0, Kind: "chooseColor", Supported: true,
		Title: "Choose colors", ChoiceMinimum: 2, ChoiceMaximum: 2,
		Choices: []forge.PromptChoice{
			{ResponseID: "choice:0", Label: "White", Weight: 1, Value: "secret-white"},
			{ResponseID: "choice:1", Label: "Blue", Weight: 1, CanRepeat: true,
				Value: "secret-blue"},
		},
	}, forgeRoomGame{}, nil)
	if err != nil {
		t.Fatalf("projectedRulesPrompt: %v", err)
	}
	if len(prompt.Choices) != 2 || prompt.Choices[1].ResponseID != "choice:1" ||
		!prompt.Choices[1].CanRepeat || prompt.ChoiceMinimum != 2 ||
		prompt.ChoiceMaximum != 2 {
		t.Fatalf("choice prompt = %+v", prompt)
	}
	encoded, err := json.Marshal(prompt)
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}
	if strings.Contains(string(encoded), "secret-white") ||
		strings.Contains(string(encoded), "secret-blue") {
		t.Fatalf("choice prompt leaked canonical value: %s", encoded)
	}
}

func TestProjectedRulesPromptKeepsCardSelectionBounds(t *testing.T) {
	prompt, err := projectedRulesPrompt("ROOM", "game-1", forge.PromptView{
		PromptID: 11, PlayerIndex: 0, Kind: "chooseCards", Supported: true,
		Title: "Choose cards", CardMinimum: 1, CardMaximum: 2,
		Cards: []forge.PromptCard{
			{ID: "card-a", Name: "Plains", SetCode: "M21", CollectorNumber: "309", Selected: true},
			{ID: "card-b", Name: "Island", SetCode: "M21", CollectorNumber: "310"},
		},
	}, forgeRoomGame{}, nil)
	if err != nil {
		t.Fatalf("projectedRulesPrompt: %v", err)
	}
	if len(prompt.Cards) != 2 || prompt.CardMinimum != 1 || prompt.CardMaximum != 2 ||
		!prompt.Cards[0].Selected || prompt.Cards[1].Selected {
		t.Fatalf("card prompt = %+v", prompt)
	}
}

func TestProjectedRulesPromptHidesReorderItemIDs(t *testing.T) {
	prompt, err := projectedRulesPrompt("ROOM", "game-1", forge.PromptView{
		PromptID: 12, PlayerIndex: 0, Kind: "reorder", Supported: true,
		Title: "Order triggers", OrderItems: []forge.PromptOrderItem{
			{ResponseID: "order:0", ID: "secret-trigger", Name: "Teval",
				SetCode: "DFT", CollectorNumber: "199", Oracle: "Create a token."},
		},
	}, forgeRoomGame{}, nil)
	if err != nil {
		t.Fatalf("projectedRulesPrompt: %v", err)
	}
	if len(prompt.OrderItems) != 1 || prompt.OrderItems[0].ResponseID != "order:0" ||
		prompt.OrderItems[0].Oracle != "Create a token." {
		t.Fatalf("reorder prompt = %+v", prompt)
	}
	encoded, err := json.Marshal(prompt)
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}
	if strings.Contains(string(encoded), "secret-trigger") {
		t.Fatalf("reorder prompt leaked upstream item id: %s", encoded)
	}
}

func TestProjectedRulesPromptKeepsOpaqueScryCardsAndDestinations(t *testing.T) {
	prompt, err := projectedRulesPrompt("ROOM", "game-1", forge.PromptView{
		PromptID: 13, PlayerIndex: 0, Kind: "scry", Supported: true,
		Title: "Scry", ScryDestinations: []string{"libraryTop", "libraryBottom"},
		Cards: []forge.PromptCard{
			{ID: "scry:0", Name: "Island", SetCode: "M21", CollectorNumber: "310"},
		},
	}, forgeRoomGame{}, nil)
	if err != nil {
		t.Fatalf("projectedRulesPrompt: %v", err)
	}
	if len(prompt.Cards) != 1 || prompt.Cards[0].ID != "scry:0" ||
		len(prompt.ScryDestinations) != 2 || prompt.ScryDestinations[1] != "libraryBottom" {
		t.Fatalf("scry prompt = %+v", prompt)
	}
}

func TestProjectedRulesPromptDamageUsesViewerProjection(t *testing.T) {
	game := forgeRoomGame{
		gameID: "game-1", playerToSeat: map[int]int{0: 2, 1: 0},
	}
	prompt, err := projectedRulesPrompt("ROOM", "game-1", forge.PromptView{
		PromptID: 14, PlayerIndex: 0, Kind: "chooseCombatDamageAssignment", Supported: true,
		DamageAssignmentMode: protocol.RulesDamageUnordered,
		DamageSource:         &forge.PromptDamageSource{ID: "attacker"}, TotalDamage: 7,
		DamageTargets: []forge.PromptDamageTarget{
			{ResponseID: "damage-target:0", Kind: "card", ID: "blocker", LethalDamage: damageInt(3)},
			{ResponseID: "damage-target:1", Kind: "player", ID: "player-1", Defender: true},
		},
	}, game, &forge.GameView{
		Players: []forge.PlayerView{{ID: "player-0", Name: "Alice"},
			{ID: "player-1", Name: "Bob"}},
		Zones: []forge.ZoneView{{Zone: "battlefield", OwnerID: "player-0",
			Cards: []forge.CardView{
				{Visibility: "visible", ID: "attacker", Identity: &forge.CardIdentityView{
					Name: "Colossal Dreadmaw", SetCode: "M19", CardNumber: "172",
				}},
				{Visibility: "visible", ID: "blocker", Toughness: "4", Damage: 1,
					Identity: &forge.CardIdentityView{
						Name: "Hill Giant", SetCode: "M10", CardNumber: "143",
					}},
			}}},
	})
	if err != nil {
		t.Fatalf("projectedRulesPrompt: %v", err)
	}
	if prompt.DamageSource == nil || prompt.DamageSource.Name != "Colossal Dreadmaw" ||
		len(prompt.DamageTargets) != 2 || prompt.DamageTargets[0].Name != "Hill Giant" ||
		prompt.DamageTargets[0].LethalDamage != 3 ||
		prompt.DamageTargets[1].Label != "Bob · Seat 1" ||
		prompt.DamageTargets[1].LethalDamage != -1 || prompt.TotalDamage != 7 {
		t.Fatalf("damage prompt = %+v", prompt)
	}
	encoded, err := json.Marshal(prompt)
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}
	if strings.Contains(string(encoded), "player-1") {
		t.Fatalf("damage prompt leaked Forge player id: %s", encoded)
	}
}

func TestProjectedRulesDamageKeepsFaceDownObjectsActionable(t *testing.T) {
	view := forge.GameView{Zones: []forge.ZoneView{{Zone: "battlefield", Cards: []forge.CardView{
		{ID: "attacker", Visibility: "visible", FaceDown: true,
			Identity: &forge.CardIdentityView{}, Power: "2", Toughness: "2"},
		{ID: "blocker", Visibility: "visible", FaceDown: true,
			Identity: &forge.CardIdentityView{}, Power: "2", Toughness: "2", Damage: 1},
	}}}}
	source, targets, err := projectedRulesDamage(&forge.PromptDamageSource{ID: "attacker"},
		[]forge.PromptDamageTarget{{ResponseID: "damage-target:0", Kind: "card", ID: "blocker", LethalDamage: damageInt(1)}},
		true, forgeRoomGame{}, view)
	if err != nil {
		t.Fatal(err)
	}
	if source.Label != "Face-down card" || source.ObjectID != "attacker" ||
		source.Name != "" || source.SetCode != "" || source.CollectorNumber != "" {
		t.Fatalf("face-down damage source must have a public label without identity: %+v", source)
	}
	if len(targets) != 1 || targets[0].Label != "Face-down card" ||
		targets[0].ObjectID != "blocker" || targets[0].ResponseID != "damage-target:0" ||
		targets[0].Name != "" || targets[0].SetCode != "" || targets[0].CollectorNumber != "" ||
		targets[0].LethalDamage != 1 {
		t.Fatalf("face-down blocker must retain public damage and response data: %+v", targets)
	}
	view.Zones[0].Cards[1].Visibility = "hidden"
	if _, _, err := projectedRulesDamage(&forge.PromptDamageSource{ID: "attacker"},
		[]forge.PromptDamageTarget{{ResponseID: "damage-target:0", Kind: "card", ID: "blocker", LethalDamage: damageInt(1)}},
		true, forgeRoomGame{}, view); err == nil {
		t.Fatal("a generic label must not make a hidden-zone object targetable")
	}
}

func TestProjectedRulesPromptContextUsesViewerProjection(t *testing.T) {
	game := forgeRoomGame{
		gameID: "game-1", playerToSeat: map[int]int{0: 2, 1: 0},
	}
	prompt, err := projectedRulesPrompt("ROOM", "game-1", forge.PromptView{
		PromptID: 15, PlayerIndex: 0, Kind: "chooseBoolean", Supported: true,
		ContextText: `otherwise: "3 damage is dealt."`,
		ContextCards: []forge.PromptCard{{
			ID: "context-card:0", Name: "Circle of Protection: Red",
			SetCode: "4ED", CollectorNumber: "17",
		}},
		ContextTargets: []forge.PromptTarget{
			{ResponseID: "context-target:0", Kind: "card", ID: "card-a"},
			{ResponseID: "context-target:1", Kind: "player", ID: "player-1"},
		},
	}, game, &forge.GameView{
		Players: []forge.PlayerView{{ID: "player-0", Name: "Alice"},
			{ID: "player-1", Name: "Bob"}},
		Zones: []forge.ZoneView{{Zone: "battlefield", OwnerID: "player-0",
			Cards: []forge.CardView{{
				Visibility: "visible", ID: "card-a", Identity: &forge.CardIdentityView{
					Name: "Ball Lightning", SetCode: "4ED", CardNumber: "174",
				},
			}}}},
	})
	if err != nil {
		t.Fatalf("projectedRulesPrompt: %v", err)
	}
	if len(prompt.ContextCards) != 1 ||
		prompt.ContextCards[0].Name != "Circle of Protection: Red" ||
		len(prompt.ContextTargets) != 2 ||
		prompt.ContextTargets[0].Name != "Ball Lightning" ||
		prompt.ContextTargets[1].Label != "Bob · Seat 1" ||
		prompt.ContextTargets[1].Seat == nil || *prompt.ContextTargets[1].Seat != 0 ||
		prompt.ContextText != `otherwise: "3 damage is dealt."` {
		t.Fatalf("prompt context = %+v", prompt)
	}
	encoded, err := json.Marshal(prompt)
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}
	if strings.Contains(string(encoded), "secret-source") ||
		strings.Contains(string(encoded), "player-1") {
		t.Fatalf("prompt context leaked Forge ids: %s", encoded)
	}
}

func TestValidRulesDamageDistribution(t *testing.T) {
	targets := []protocol.RulesPromptDamageTarget{
		{ResponseID: "damage-target:0", LethalDamage: 3},
		{ResponseID: "damage-target:1", LethalDamage: 2},
		{ResponseID: "damage-target:2", LethalDamage: -1},
	}
	valid := []protocol.RulesPromptDamageAssignment{
		{TargetID: "damage-target:0", Damage: 3},
		{TargetID: "damage-target:1", Damage: 2},
		{TargetID: "damage-target:2", Damage: 2},
	}
	if !rulesinput.ValidDamageDistribution(targets, 7, protocol.RulesDamageOrdered, valid) {
		t.Fatal("valid combat damage was rejected")
	}
	for _, assignments := range [][]protocol.RulesPromptDamageAssignment{
		valid[:2],
		{{TargetID: "damage-target:0", Damage: 2},
			{TargetID: "damage-target:1", Damage: 3},
			{TargetID: "damage-target:2", Damage: 2}},
		{{TargetID: "damage-target:0", Damage: 3},
			{TargetID: "damage-target:1", Damage: 1},
			{TargetID: "damage-target:2", Damage: 3}},
		{{TargetID: "damage-target:0", Damage: 3},
			{TargetID: "damage-target:0", Damage: 2},
			{TargetID: "damage-target:2", Damage: 2}},
	} {
		if rulesinput.ValidDamageDistribution(targets, 7, protocol.RulesDamageOrdered, assignments) {
			t.Fatalf("invalid combat damage accepted: %+v", assignments)
		}
	}
}

func TestValidRulesPromptScryPiles(t *testing.T) {
	valid := []protocol.RulesPromptScryPile{
		{Destination: "libraryTop", CardIDs: []string{"scry:0"}},
		{Destination: "graveyard", CardIDs: []string{"scry:1"}},
	}
	if !rulesinput.ValidScryPiles(valid) {
		t.Fatal("valid scry piles were rejected")
	}
	for _, piles := range [][]protocol.RulesPromptScryPile{
		{{Destination: "battlefield", CardIDs: []string{"scry:0"}}},
		{{Destination: "libraryTop", CardIDs: []string{"card-a"}}},
		{{Destination: "libraryTop", CardIDs: []string{"scry:0"}},
			{Destination: "graveyard", CardIDs: []string{"scry:0"}}},
		{{Destination: "libraryTop", CardIDs: []string{"scry:0"}},
			{Destination: "libraryTop", CardIDs: []string{"scry:1"}}},
	} {
		if rulesinput.ValidScryPiles(piles) {
			t.Fatalf("invalid scry piles accepted: %+v", piles)
		}
	}
}
