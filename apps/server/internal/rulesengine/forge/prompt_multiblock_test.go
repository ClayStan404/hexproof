// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"encoding/json"
	"strings"
	"testing"
)

func multiBlockPrompt() json.RawMessage {
	return json.RawMessage(`{"promptId":19,"decidingPlayerId":"player-1","input":{
		"type":"chooseBlockers","availableBlockerIds":["native-palace-guard","native-bears"],
		"blockerAssignmentLimits":[{"blockerId":"native-palace-guard","maxAssignments":2},
			{"blockerId":"native-bears","maxAssignments":1}],
		"attackers":[{"attackerId":"native-attacker-a","validBlockerIds":["native-palace-guard","native-bears"],"minBlockers":1},
			{"attackerId":"native-attacker-b","validBlockerIds":["native-palace-guard","native-bears"],"minBlockers":1},
			{"attackerId":"native-attacker-c","validBlockerIds":["native-palace-guard","native-bears"],"minBlockers":1}]}}`)
}

func TestMultiBlockUsesNativeCapacityAndDistinctPairs(t *testing.T) {
	raw := multiBlockPrompt()
	view, err := NormalizePrompt(raw)
	if err != nil || !view.Supported || len(view.CombatSources) != 2 ||
		view.CombatSources[0].Maximum != 2 || view.CombatSources[1].Maximum != 1 {
		t.Fatalf("native blocker capacities = %+v, %v", view.CombatSources, err)
	}
	pairs := []PromptAssignment{{"combat-source:0", "combat-target:0"}, {"combat-source:0", "combat-target:1"}}
	response, err := BuildPromptResponse(raw, 1, 19, PromptResponse{ResponseID: "$submit", Assignments: pairs})
	if err != nil {
		t.Fatal(err)
	}
	var output struct {
		Output struct {
			Assignments []struct {
				BlockerID  string `json:"blockerId"`
				AttackerID string `json:"attackerId"`
			} `json:"assignments"`
		} `json:"output"`
	}
	if err := json.Unmarshal(response, &output); err != nil {
		t.Fatal(err)
	}
	if len(output.Output.Assignments) != 2 || output.Output.Assignments[0].BlockerID != "native-palace-guard" ||
		output.Output.Assignments[1].BlockerID != "native-palace-guard" ||
		output.Output.Assignments[0].AttackerID != "native-attacker-a" || output.Output.Assignments[1].AttackerID != "native-attacker-b" {
		t.Fatalf("multi-block translation lost a pair: %s", response)
	}
	for name, assignments := range map[string][]PromptAssignment{
		"duplicate pair":            {pairs[0], pairs[0]},
		"native capacity exceeded":  {pairs[0], pairs[1], {"combat-source:0", "combat-target:2"}},
		"ordinary blocker repeated": {{"combat-source:1", "combat-target:0"}, {"combat-source:1", "combat-target:1"}},
		"raw native source":         {{"native-palace-guard", "combat-target:0"}},
		"raw native target":         {{"combat-source:0", "native-attacker-a"}},
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := BuildPromptResponse(raw, 1, 19, PromptResponse{ResponseID: "$submit", Assignments: assignments}); err == nil {
				t.Fatal("accepted invalid multi-block response")
			}
		})
	}
	if _, err := BuildPromptResponse(raw, 0, 19, PromptResponse{ResponseID: "$submit", Assignments: pairs}); err == nil {
		t.Fatal("accepted response from another player")
	}
}

func TestBlockerPromptRequiresCompleteNativeCapacities(t *testing.T) {
	for name, replacement := range map[string]string{
		"missing": ``, "null": `,"blockerAssignmentLimits":null`,
		"empty":                  `,"blockerAssignmentLimits":[]`,
		"partial":                `,"blockerAssignmentLimits":[{"blockerId":"native-palace-guard","maxAssignments":2}]`,
		"duplicate":              `,"blockerAssignmentLimits":[{"blockerId":"native-palace-guard","maxAssignments":2},{"blockerId":"native-palace-guard","maxAssignments":1}]`,
		"foreign":                `,"blockerAssignmentLimits":[{"blockerId":"foreign","maxAssignments":2},{"blockerId":"native-bears","maxAssignments":1}]`,
		"negative":               `,"blockerAssignmentLimits":[{"blockerId":"native-palace-guard","maxAssignments":-1},{"blockerId":"native-bears","maxAssignments":1}]`,
		"missing maximum":        `,"blockerAssignmentLimits":[{"blockerId":"native-palace-guard"},{"blockerId":"native-bears","maxAssignments":1}]`,
		"beyond candidate count": `,"blockerAssignmentLimits":[{"blockerId":"native-palace-guard","maxAssignments":4},{"blockerId":"native-bears","maxAssignments":1}]`,
	} {
		t.Run(name, func(t *testing.T) {
			var envelope map[string]any
			if err := json.Unmarshal(multiBlockPrompt(), &envelope); err != nil {
				t.Fatal(err)
			}
			input := envelope["input"].(map[string]any)
			delete(input, "blockerAssignmentLimits")
			if replacement != "" {
				var fields map[string]any
				if err := json.Unmarshal([]byte("{"+strings.TrimPrefix(replacement, ",")+"}"), &fields); err != nil {
					t.Fatal(err)
				}
				input["blockerAssignmentLimits"] = fields["blockerAssignmentLimits"]
			}
			raw, err := json.Marshal(envelope)
			if err != nil {
				t.Fatal(err)
			}
			if _, err := NormalizePrompt(raw); err == nil {
				t.Fatal("accepted incomplete native capacity metadata")
			}
		})
	}
}

func TestZeroNativeBlockCapacityRejectsAssignments(t *testing.T) {
	raw := json.RawMessage(strings.Replace(string(multiBlockPrompt()), `"maxAssignments":2`, `"maxAssignments":0`, 1))
	view, err := NormalizePrompt(raw)
	if err != nil || view.CombatSources[0].Maximum != 0 {
		t.Fatalf("zero capacity: %+v, %v", view, err)
	}
	if _, err := BuildPromptResponse(raw, 1, 19, PromptResponse{ResponseID: "$submit", Assignments: []PromptAssignment{{"combat-source:0", "combat-target:0"}}}); err == nil {
		t.Fatal("accepted a block beyond zero native capacity")
	}
}
