// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"encoding/json"
	"testing"
)

func damageHintPrompt(hints string) json.RawMessage {
	field := ""
	if hints != "" {
		field = `,"blockerDamageHints":` + hints
	}
	return json.RawMessage(`{"promptId":92,"decidingPlayerId":"player-0","input":{` +
		`"type":"chooseCombatDamageAssignment","attackerId":"attacker",` +
		`"blockerIds":["first","second"],"defenderId":"player-1","totalDamage":6,"damageAssignmentMode":"unordered"` + field + `}}`)
}

func TestNativeDamageHintsBindToCurrentCandidates(t *testing.T) {
	view, err := NormalizePrompt(damageHintPrompt(`[{"id":"second","lethalDamage":2},{"id":"first","lethalDamage":0}]`))
	if err != nil {
		t.Fatal(err)
	}
	if len(view.DamageTargets) != 3 || view.DamageTargets[0].LethalDamage == nil ||
		*view.DamageTargets[0].LethalDamage != 0 || view.DamageTargets[1].LethalDamage == nil ||
		*view.DamageTargets[1].LethalDamage != 2 || view.DamageTargets[2].LethalDamage != nil {
		t.Fatalf("native thresholds lost zero, candidate binding, or defender distinction: %+v", view.DamageTargets)
	}
}

func TestNativeDamageHintsRejectIncompleteOrForeignThresholds(t *testing.T) {
	for _, hints := range []string{
		``, `null`, `{}`, `[]`,
		`[{"id":"first","lethalDamage":0}]`,
		`[{"id":"first","lethalDamage":0},{"id":"first","lethalDamage":2}]`,
		`[{"id":"secret-hand-card","lethalDamage":0},{"id":"second","lethalDamage":2}]`,
		`[{"id":"player-1","lethalDamage":0},{"id":"second","lethalDamage":2}]`,
		`[{"id":"first","lethalDamage":-1},{"id":"second","lethalDamage":2}]`,
		`[{"id":"first","lethalDamage":100001},{"id":"second","lethalDamage":2}]`,
		`[{"id":"first"},{"id":"second","lethalDamage":2}]`,
		`[{"id":"first","lethalDamage":null},{"id":"second","lethalDamage":2}]`,
		`[{"id":"first","lethalDamage":0.5},{"id":"second","lethalDamage":2}]`,
		`[{"id":"first","lethalDamage":"0"},{"id":"second","lethalDamage":2}]`,
	} {
		if _, err := NormalizePrompt(damageHintPrompt(hints)); err == nil {
			t.Fatalf("invalid native hint was accepted: %s", hints)
		}
		if _, err := BuildPromptResponse(damageHintPrompt(hints), 0, 92, PromptResponse{
			ResponseID: "$submit", DamageAssignments: []PromptDamageAssignment{
				{TargetID: "damage-target:0", Damage: 2},
				{TargetID: "damage-target:1", Damage: 2},
				{TargetID: "damage-target:2", Damage: 2},
			},
		}); err == nil {
			t.Fatalf("a response bypassed invalid native hints: %s", hints)
		}
	}
}

func TestNativeDamageHintsAllowEmptyBlockersOnlyWithEmptyHints(t *testing.T) {
	raw := json.RawMessage(`{"promptId":93,"decidingPlayerId":"player-0","input":{` +
		`"type":"chooseCombatDamageAssignment","attackerId":"attacker",` +
		`"blockerIds":[],"blockerDamageHints":[],"defenderId":"player-1","totalDamage":6,"damageAssignmentMode":"unordered"}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || len(view.DamageTargets) != 1 || !view.DamageTargets[0].Defender {
		t.Fatalf("native defender-only allocation failed: %+v, %v", view, err)
	}
}
