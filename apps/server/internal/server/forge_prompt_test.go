// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"strings"
	"testing"

	"hexproof/server/internal/rulesengine/forge"
)

func TestProjectedRulesPromptTargetsUseViewerProjection(t *testing.T) {
	game := forgeRoomGame{
		gameID: "game-1", playerToSeat: map[int]int{0: 2, 1: 0},
	}
	prompt, err := projectedRulesPrompt("ROOM", "game-1", forge.PromptView{
		PromptID: 8, PlayerIndex: 0, Kind: "chooseBoardTargets", Supported: true,
		Title: "Choose targets", MinSelected: 1, MaxSelected: 2, Cancellable: true,
		Targets: []forge.PromptTarget{
			{ResponseID: "target:0", Kind: "player", ID: "player-1"},
			{ResponseID: "target:1", Kind: "card", ID: "card-a"},
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
		prompt.Targets[1].Name != "Lightning Bolt" ||
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
		prompt.CombatTargets[0].Label != "Bob · Seat 1" ||
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
			{ID: "card-a", Name: "Plains", SetCode: "M21", CollectorNumber: "309"},
			{ID: "card-b", Name: "Island", SetCode: "M21", CollectorNumber: "310"},
		},
	}, forgeRoomGame{}, nil)
	if err != nil {
		t.Fatalf("projectedRulesPrompt: %v", err)
	}
	if len(prompt.Cards) != 2 || prompt.CardMinimum != 1 || prompt.CardMaximum != 2 {
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
