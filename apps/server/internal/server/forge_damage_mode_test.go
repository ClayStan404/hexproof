// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"fmt"
	"testing"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
	"hexproof/server/internal/rulesinput"
)

// This crosses the same native-input normalization, private projection,
// distribution gate, and canonical response encoding used by the room handler.
func TestRulesDamageModesPreserveNativeConstraints(t *testing.T) {
	for _, tc := range []struct {
		name, mode string
		amounts    [3]int
		valid      bool
	}{
		{"ordered requires lethal order", protocol.RulesDamageOrdered, [3]int{1, 5, 0}, false},
		{"unordered accepts nonlethal blocker split", protocol.RulesDamageUnordered, [3]int{1, 5, 0}, true},
		{"unordered rejects nonlethal trample", protocol.RulesDamageUnordered, [3]int{1, 1, 4}, false},
		{"unordered accepts lethal trample", protocol.RulesDamageUnordered, [3]int{2, 2, 2}, true},
		{"divide freely permits native exception", protocol.RulesDamageDivideFreely, [3]int{1, 1, 4}, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			modeField := fmt.Sprintf(",\"damageAssignmentMode\":%q", tc.mode)
			raw := json.RawMessage(`{"promptId":91,"decidingPlayerId":"player-0","input":{` +
				`"type":"chooseCombatDamageAssignment","attackerId":"attacker",` +
				`"blockerDamageHints":[{"id":"first","lethalDamage":2},{"id":"second","lethalDamage":2}],` +
				`"blockerIds":["first","second"],"defenderId":"player-1","totalDamage":6` + modeField + `}}`)
			view, err := forge.NormalizePrompt(raw)
			if err != nil {
				t.Fatal(err)
			}
			game := forgeRoomGame{playerToSeat: map[int]int{0: 0, 1: 1}}
			snapshot := forge.GameView{
				Players: []forge.PlayerView{{ID: "player-0", Name: "A"}, {ID: "player-1", Name: "B"}},
				Zones: []forge.ZoneView{{Zone: "battlefield", Cards: []forge.CardView{
					{ID: "attacker", Visibility: "visible", Identity: &forge.CardIdentityView{Name: "Colossal Dreadmaw"}},
					{ID: "first", Visibility: "visible", Toughness: "2", Identity: &forge.CardIdentityView{Name: "Grizzly Bears"}},
					{ID: "second", Visibility: "visible", Toughness: "2", Identity: &forge.CardIdentityView{Name: "Grizzly Bears"}},
				}}},
			}
			prompt, err := projectedRulesPrompt("ROOM", "game-1", view, game, &snapshot)
			if err != nil {
				t.Fatal(err)
			}
			if prompt.DamageAssignmentMode != tc.mode {
				t.Fatalf("native mode was lost during private projection: %+v", prompt)
			}
			var assignments []protocol.RulesPromptDamageAssignment
			for index, amount := range tc.amounts {
				assignments = append(assignments, protocol.RulesPromptDamageAssignment{
					TargetID: fmt.Sprintf("damage-target:%d", index), Damage: amount,
				})
			}
			accepted := rulesinput.ValidDamageDistribution(prompt.DamageTargets, prompt.TotalDamage,
				prompt.DamageAssignmentMode, assignments)
			if accepted != tc.valid {
				t.Fatalf("mode %q assignment %v accepted=%v, want %v", tc.mode, tc.amounts, accepted, tc.valid)
			}
			if !accepted {
				return
			}
			response, err := forge.BuildPromptResponse(raw, 0, 91, forge.PromptResponse{
				ResponseID: "$submit", DamageAssignments: rulesinput.DamageAssignments(assignments),
			})
			if err != nil {
				t.Fatal(err)
			}
			var envelope struct {
				Type   string `json:"type"`
				Output struct {
					Type        string `json:"type"`
					Assignments []struct {
						ID     string `json:"assigneeId"`
						Damage int    `json:"damage"`
					} `json:"assignments"`
				} `json:"output"`
			}
			if err := json.Unmarshal(response, &envelope); err != nil {
				t.Fatal(err)
			}
			if envelope.Type != "chooseCombatDamageAssignment" || envelope.Output.Type != "combatDamageAssignmentDecision" || len(envelope.Output.Assignments) != 3 {
				t.Fatalf("canonical damage envelope changed: %s", response)
			}
			for index, id := range []string{"first", "second", "player-1"} {
				if envelope.Output.Assignments[index].ID != id || envelope.Output.Assignments[index].Damage != tc.amounts[index] {
					t.Fatalf("native damage answer changed: %s", response)
				}
			}
		})
	}
}

func TestRulesDamageModesRejectUnknownMode(t *testing.T) {
	targets := []protocol.RulesPromptDamageTarget{{ResponseID: "damage-target:0", LethalDamage: 2}}
	assignments := []protocol.RulesPromptDamageAssignment{{TargetID: "damage-target:0", Damage: 6}}
	for _, mode := range []string{"", "free", "unknown", "UNORDERED"} {
		if rulesinput.ValidDamageDistribution(targets, 6, mode, assignments) {
			t.Fatalf("unknown mode %q relaxed damage validation", mode)
		}
		_, err := projectedRulesPrompt("ROOM", "game", forge.PromptView{
			Kind: "chooseCombatDamageAssignment", DamageAssignmentMode: mode,
		}, forgeRoomGame{}, nil)
		if err == nil {
			t.Fatalf("unknown mode %q was published", mode)
		}
	}
}
