// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"encoding/json"
	"testing"
)

func TestNormalizeAndBuildDamageAssignmentOrder(t *testing.T) {
	raw := json.RawMessage(`{"promptId":81,"decidingPlayerId":"player-0","input":{
      "type":"chooseDamageAssignmentOrder","attackerId":"secret-attacker",
      "blockerIds":["secret-blocker-a","secret-blocker-b"],"blockerCards":[
        {"id":"secret-blocker-a","identity":{"name":"Bear Cub"}},
        {"id":"secret-blocker-b","identity":{"name":"Hill Giant"}}
      ]}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || !view.Supported || view.DamageSource == nil ||
		view.DamageSource.ID != "secret-attacker" || len(view.DamageTargets) != 2 ||
		view.DamageTargets[1].ResponseID != "damage-target:1" {
		t.Fatalf("damage-order prompt = %+v, %v", view, err)
	}
	response, err := BuildPromptResponse(raw, 0, 81, PromptResponse{
		ResponseID: "$submit", DamageOrderIDs: []string{"damage-target:1", "damage-target:0"},
	})
	if err != nil || string(response) !=
		`{"output":{"orderedBlockerIds":["secret-blocker-b","secret-blocker-a"],"type":"damageAssignmentOrderDecision"},"type":"chooseDamageAssignmentOrder"}` {
		t.Fatalf("damage-order response = %s, %v", response, err)
	}
	for _, answer := range []PromptResponse{
		{ResponseID: "$submit", DamageOrderIDs: []string{"damage-target:0"}},
		{ResponseID: "$submit", DamageOrderIDs: []string{"damage-target:0", "damage-target:0"}},
		{ResponseID: "$submit", DamageOrderIDs: []string{"damage-target:0", "damage-target:2"}},
		{ResponseID: "$cancel", DamageOrderIDs: []string{"damage-target:0", "damage-target:1"}},
		{ResponseID: "$submit", DamageOrderIDs: []string{"damage-target:0", "damage-target:1"},
			OrderedIDs: []string{"order:0"}},
	} {
		if _, err := BuildPromptResponse(raw, 0, 81, answer); err == nil {
			t.Fatalf("invalid damage order unexpectedly succeeded: %+v", answer)
		}
	}
}

func TestNormalizeAndBuildCombatDamageAssignment(t *testing.T) {
	raw := json.RawMessage(`{"promptId":82,"decidingPlayerId":"player-1","input":{
      "type":"chooseCombatDamageAssignment","attackerId":"secret-attacker",
      "blockerIds":["secret-blocker-a","secret-blocker-b"],
      "defenderId":"player-0","totalDamage":7,"attackerHasDeathtouch":true}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || !view.Supported || view.TotalDamage != 7 || !view.DamageDeathtouch ||
		len(view.DamageTargets) != 3 || !view.DamageTargets[2].Defender ||
		view.DamageTargets[2].Kind != "player" {
		t.Fatalf("combat-damage prompt = %+v, %v", view, err)
	}
	response, err := BuildPromptResponse(raw, 1, 82, PromptResponse{
		ResponseID: "$submit", DamageAssignments: []PromptDamageAssignment{
			{TargetID: "damage-target:0", Damage: 1},
			{TargetID: "damage-target:1", Damage: 1},
			{TargetID: "damage-target:2", Damage: 5},
		},
	})
	if err != nil || string(response) !=
		`{"output":{"assignments":[{"assigneeId":"secret-blocker-a","damage":1},{"assigneeId":"secret-blocker-b","damage":1},{"assigneeId":"player-0","damage":5}],"type":"combatDamageAssignmentDecision"},"type":"chooseCombatDamageAssignment"}` {
		t.Fatalf("combat-damage response = %s, %v", response, err)
	}
	for _, answer := range []PromptResponse{
		{ResponseID: "$submit", DamageAssignments: []PromptDamageAssignment{
			{TargetID: "damage-target:0", Damage: 7},
		}},
		{ResponseID: "$submit", DamageAssignments: []PromptDamageAssignment{
			{TargetID: "damage-target:0", Damage: 1},
			{TargetID: "damage-target:0", Damage: 1},
			{TargetID: "damage-target:2", Damage: 5},
		}},
		{ResponseID: "$submit", DamageAssignments: []PromptDamageAssignment{
			{TargetID: "damage-target:0", Damage: 1},
			{TargetID: "damage-target:1", Damage: 1},
			{TargetID: "damage-target:2", Damage: 4},
		}},
		{ResponseID: "$submit", DamageAssignments: []PromptDamageAssignment{
			{TargetID: "damage-target:0", Damage: -1},
			{TargetID: "damage-target:1", Damage: 3},
			{TargetID: "damage-target:2", Damage: 5},
		}},
	} {
		if _, err := BuildPromptResponse(raw, 1, 82, answer); err == nil {
			t.Fatalf("invalid combat damage unexpectedly succeeded: %+v", answer)
		}
	}
}

func TestNormalizeDamagePromptsRejectInvalidCombatants(t *testing.T) {
	for _, input := range []string{
		`{"type":"chooseDamageAssignmentOrder","attackerId":"","blockerIds":["a"]}`,
		`{"type":"chooseDamageAssignmentOrder","attackerId":"a","blockerIds":["b","b"]}`,
		`{"type":"chooseCombatDamageAssignment","attackerId":"a","blockerIds":["b"]}`,
		`{"type":"chooseCombatDamageAssignment","attackerId":"a","blockerIds":["b"],"totalDamage":-1}`,
	} {
		raw := json.RawMessage(`{"promptId":83,"decidingPlayerId":"player-0","input":` + input + `}`)
		if _, err := NormalizePrompt(raw); err == nil {
			t.Fatalf("invalid damage prompt unexpectedly normalized: %s", raw)
		}
	}
}
