// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
	"hexproof/server/internal/rulesinput"
)

func TestNativeDamageHintsSurviveProjectionAndDamageGate(t *testing.T) {
	for _, tc := range []struct {
		name         string
		hint         *int
		deathtouch   bool
		expected     int
		blockerSplit int
	}{
		{"ordinary native threshold", damageInt(5), false, 5, 5},
		{"already assigned lethal", damageInt(0), false, 0, 0},
		{"Zilortha power threshold", damageInt(2), false, 2, 2},
		{"already assigned lethal with deathtouch", damageInt(0), true, 0, 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			field := ""
			if tc.hint != nil {
				field = fmt.Sprintf(`,"blockerDamageHints":[{"id":"blocker","lethalDamage":%d}]`, *tc.hint)
			}
			raw := json.RawMessage(fmt.Sprintf(`{"promptId":94,"decidingPlayerId":"player-0","input":{`+
				`"type":"chooseCombatDamageAssignment","attackerId":"attacker","blockerIds":["blocker"],`+
				`"defenderId":"player-1","totalDamage":6,"damageAssignmentMode":"unordered","attackerHasDeathtouch":%t%s}}`, tc.deathtouch, field))
			view, err := forge.NormalizePrompt(raw)
			if err != nil {
				t.Fatal(err)
			}
			snapshot := forge.GameView{
				Players: []forge.PlayerView{{ID: "player-0", Name: "A"}, {ID: "player-1", Name: "B"}},
				Zones: []forge.ZoneView{{Zone: "battlefield", Cards: []forge.CardView{
					{ID: "attacker", Visibility: "visible", Identity: &forge.CardIdentityView{Name: "Colossal Dreadmaw"}},
					{ID: "blocker", Visibility: "visible", Power: "2", Toughness: "5", Damage: 0, Identity: &forge.CardIdentityView{Name: "Watcher in the Web"}},
				}}},
			}
			game := forgeRoomGame{playerToSeat: map[int]int{0: 0, 1: 1}}
			prompt, err := projectedRulesPrompt("ROOM", "game", view, game, &snapshot)
			if err != nil || prompt.DamageTargets[0].LethalDamage != tc.expected {
				t.Fatalf("engine threshold was overwritten by snapshot arithmetic: %+v, %v", prompt, err)
			}
			assignments := []protocol.RulesPromptDamageAssignment{
				{TargetID: "damage-target:0", Damage: tc.blockerSplit},
				{TargetID: "damage-target:1", Damage: 6 - tc.blockerSplit},
			}
			if !rulesinput.ValidDamageDistribution(prompt.DamageTargets, 6, prompt.DamageAssignmentMode, assignments) {
				t.Fatal("the current native lethal threshold still prevents a valid trample allocation")
			}
			response, err := forge.BuildPromptResponse(raw, 0, 94, forge.PromptResponse{
				ResponseID: "$submit", DamageAssignments: rulesinput.DamageAssignments(assignments),
			})
			if err != nil || !strings.Contains(string(response), fmt.Sprintf(`"assigneeId":"blocker","damage":%d`, tc.blockerSplit)) {
				t.Fatalf("native candidate answer changed: %s, %v", response, err)
			}
			// A threshold grants no permission to expose hidden card identity.
			snapshot.Zones[0].Cards[1].Visibility = "hidden"
			if _, err := projectedRulesPrompt("ROOM", "game", view, game, &snapshot); err == nil {
				t.Fatal("native threshold bypassed the viewer's card visibility gate")
			}
		})
	}
}

func damageInt(value int) *int { return &value }

func TestDamageProjectionRequiresNativeThresholdsOnlyForAllocation(t *testing.T) {
	game := forgeRoomGame{}
	snapshot := forge.GameView{Zones: []forge.ZoneView{{Zone: "battlefield", Cards: []forge.CardView{
		{ID: "attacker", Visibility: "visible", Identity: &forge.CardIdentityView{Name: "Colossal Dreadmaw"}},
		{ID: "blocker", Visibility: "visible", Toughness: "5", Damage: 2, Identity: &forge.CardIdentityView{Name: "Watcher in the Web"}},
	}}}}
	source := &forge.PromptDamageSource{ID: "attacker"}
	for _, hint := range []*int{nil, damageInt(-1), damageInt(100001)} {
		targets := []forge.PromptDamageTarget{{ResponseID: "damage-target:0", Kind: "card", ID: "blocker", LethalDamage: hint}}
		if _, _, err := projectedRulesDamage(source, targets, true, game, snapshot); err == nil {
			t.Fatalf("snapshot toughness and damage replaced an invalid native threshold: %v", hint)
		}
	}
	// Ordering callbacks have no damage amounts. They must remain usable without
	// asking the room server to calculate a threshold that Forge did not provide.
	view := forge.PromptView{
		Kind: "chooseDamageAssignmentOrder", DamageSource: source,
		DamageTargets: []forge.PromptDamageTarget{{ResponseID: "damage-target:0", Kind: "card", ID: "blocker"}},
	}
	prompt, err := projectedRulesPrompt("ROOM", "game", view, game, &snapshot)
	if err != nil || len(prompt.DamageTargets) != 1 || prompt.DamageTargets[0].LethalDamage != -1 {
		t.Fatalf("ordering callback unexpectedly required or inferred a damage threshold: %+v, %v", prompt, err)
	}
}
