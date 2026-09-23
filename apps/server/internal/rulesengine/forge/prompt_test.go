// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestNormalizeChooseActionHidesUpstreamActionIDs(t *testing.T) {
	raw := json.RawMessage(`{
        "promptId":7,"decidingPlayerId":"player-1",
        "input":{"type":"chooseAction","actions":[
          {"id":"secret-action-id","type":"cast","cardId":"hand-2","label":"Cast Lightning Bolt"}
        ]}}
    `)
	view, err := NormalizePrompt(raw)
	if err != nil {
		t.Fatalf("NormalizePrompt: %v", err)
	}
	if view.PromptID != 7 || view.PlayerIndex != 1 || view.Kind != "chooseAction" ||
		!view.Supported || len(view.Options) != 3 ||
		view.Options[0].ResponseID != "action:0" || view.Options[0].CardID != "hand-2" {
		t.Fatalf("prompt view = %+v", view)
	}
	encoded, err := json.Marshal(view)
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}
	if string(encoded) == "" || containsBytes(encoded, []byte("secret-action-id")) {
		t.Fatalf("normalized prompt leaked upstream id: %s", encoded)
	}
}

func TestBuildPromptResponseRevalidatesOwnerPromptAndAction(t *testing.T) {
	raw := json.RawMessage(`{
        "promptId":9,"decidingPlayerId":"player-0",
        "input":{"type":"chooseAction","actions":[
          {"id":"act-opaque","type":"activateAbility","description":"Add {G}."}
        ]}}
    `)
	response, err := BuildPromptResponse(raw, 0, 9, PromptResponse{ResponseID: "action:0"})
	if err != nil {
		t.Fatalf("BuildPromptResponse: %v", err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(response, &decoded); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	output := decoded["output"].(map[string]any)
	if decoded["type"] != "chooseAction" ||
		output["type"] != "act" || output["actionId"] != "act-opaque" {
		t.Fatalf("response = %s", response)
	}
	for _, test := range []struct {
		name       string
		player     int
		promptID   int64
		responseID string
	}{
		{"wrong owner", 1, 9, "action:0"},
		{"stale prompt", 0, 8, "action:0"},
		{"unknown option", 0, 9, "action:1"},
	} {
		t.Run(test.name, func(t *testing.T) {
			if _, err := BuildPromptResponse(raw, test.player, test.promptID, PromptResponse{
				ResponseID: test.responseID,
			}); err == nil {
				t.Fatal("BuildPromptResponse unexpectedly succeeded")
			}
		})
	}
}

func TestNormalizePromptAcknowledgesOpeningRoll(t *testing.T) {
	raw := json.RawMessage(`{
      "promptId":1,"decidingPlayerId":"player-0",
      "input":{"type":"diceRolled","presentation":{"title":"Roll for first player"},
      "sides":20,"rolls":[]}}`)
	view, err := NormalizePrompt(raw)
	if err != nil {
		t.Fatalf("NormalizePrompt: %v", err)
	}
	if !view.Supported || len(view.Options) != 1 || view.Options[0].ResponseID != "$ack" {
		t.Fatalf("view = %+v", view)
	}
	response, err := BuildPromptResponse(raw, 0, 1, PromptResponse{ResponseID: "$ack"})
	if err != nil || string(response) != `{"output":{"type":"diceRolledAcknowledged"},"type":"diceRolled"}` {
		t.Fatalf("BuildPromptResponse = %s, %v", response, err)
	}
}

func TestNormalizeMulliganAndManaResponses(t *testing.T) {
	mulligan := json.RawMessage(`{"promptId":2,"decidingPlayerId":"player-0",
      "input":{"type":"mulligan","mulliganCount":1}}`)
	view, err := NormalizePrompt(mulligan)
	if err != nil || len(view.Options) != 2 || view.Options[0].ResponseID != "$keep" {
		t.Fatalf("mulligan prompt = %+v, %v", view, err)
	}
	response, err := BuildPromptResponse(mulligan, 0, 2,
		PromptResponse{ResponseID: "$mulligan"})
	if err != nil || !containsBytes(response, []byte(`"keep":false`)) {
		t.Fatalf("mulligan response = %s, %v", response, err)
	}

	mana := json.RawMessage(`{"promptId":3,"decidingPlayerId":"player-0",
      "input":{"type":"payManaCost","cardName":"Shock","manaCost":"{R}",
      "canConfirmFromPool":true,"actions":[{"id":"tap:1","type":"activateAbility",
      "description":"{T}: Add {R}."}]}}`)
	view, err = NormalizePrompt(mana)
	if err != nil || len(view.Options) != 4 || view.Detail != "Shock {R}" || view.Title != "Pay Mana Cost: {R}" {
		t.Fatalf("mana prompt = %+v, %v", view, err)
	}
	response, err = BuildPromptResponse(mana, 0, 3,
		PromptResponse{ResponseID: "$auto-pay"})
	if err != nil || !containsBytes(response, []byte(`"auto":true`)) {
		t.Fatalf("mana response = %s, %v", response, err)
	}
}

func TestManaTitleUsesLiveCostAlongsideLongEffectText(t *testing.T) {
	detail := strings.Repeat("A long conditional effect with graveyard, hand and library choices. ", 20) +
		"\n\nPay Mana Cost: {3}{B}{B}"
	for _, cost := range []string{"{3}{B}{B}", "{1}{B}", "0", ""} {
		raw, err := json.Marshal(map[string]any{
			"promptId": 3, "decidingPlayerId": "player-0",
			"input": map[string]any{"type": "payManaCost", "manaCost": cost,
				"presentation": map[string]string{"title": "Pay mana", "description": detail}},
		})
		if err != nil {
			t.Fatal(err)
		}
		view, err := NormalizePrompt(raw)
		want := "Pay mana"
		if cost != "" {
			want = "Pay Mana Cost: " + cost
		}
		if err != nil || view.Title != want || view.Detail == "" || !strings.HasPrefix(detail, view.Detail) ||
			strings.Contains(view.Detail, "Pay Mana Cost:") {
			t.Fatalf("live cost %q: view = %+v, error = %v", cost, view, err)
		}
	}
}

func TestUnknownPromptIsNonInteractive(t *testing.T) {
	raw := json.RawMessage(`{"promptId":4,"decidingPlayerId":"player-0",
      "input":{"type":"futureDecision"}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || view.Supported || len(view.Options) != 0 {
		t.Fatalf("unknown prompt = %+v, %v", view, err)
	}
	if _, err := BuildPromptResponse(raw, 0, 4,
		PromptResponse{ResponseID: "anything"}); err == nil {
		t.Fatal("unsupported prompt response unexpectedly succeeded")
	}
}

func TestNormalizeAndBuildMulliganPutBack(t *testing.T) {
	raw := json.RawMessage(`{"promptId":5,"decidingPlayerId":"player-1","input":{
      "type":"mulliganPutBack","handCardIds":["card-a","card-b","card-c"],"count":2,
      "cards":[
        {"id":"card-a","identity":{"name":"Plains","setCode":"M21","cardNumber":"309"}},
        {"id":"card-b","identity":{"name":"Island","setCode":"M21","cardNumber":"310"}},
        {"id":"card-c","identity":{"name":"Soldier","setCode":"TM21","cardNumber":"1","isToken":true}}
      ]}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || !view.Supported || view.Required != 2 || view.CardMinimum != 2 ||
		view.CardMaximum != 2 || len(view.Cards) != 3 ||
		view.Cards[2].CollectorNumber != "1" || !view.Cards[2].Token {
		t.Fatalf("mulligan put-back prompt = %+v, %v", view, err)
	}
	response, err := BuildPromptResponse(raw, 1, 5, PromptResponse{
		ResponseID: "$submit", CardIDs: []string{"card-c", "card-a"},
	})
	if err != nil || string(response) !=
		`{"output":{"cardIds":["card-c","card-a"],"type":"mulliganPutBackDecision"},"type":"mulliganPutBack"}` {
		t.Fatalf("mulligan put-back response = %s, %v", response, err)
	}
	for _, selection := range [][]string{
		{"card-a"}, {"card-a", "card-a"}, {"card-a", "foreign"},
	} {
		if _, err := BuildPromptResponse(raw, 1, 5, PromptResponse{
			ResponseID: "$submit", CardIDs: selection,
		}); err == nil {
			t.Fatalf("invalid selection unexpectedly succeeded: %v", selection)
		}
	}
}

func TestNormalizeAndBuildChooseCards(t *testing.T) {
	raw := json.RawMessage(`{"promptId":51,"decidingPlayerId":"player-1","input":{
      "type":"chooseCards","presentation":{"title":"Discard","description":"Choose cards."},
      "min":1,"max":2,"cards":[
        {"id":"card-a","identity":{"name":"Plains","setCode":"M21","cardNumber":"309"},"selected":true},
        {"id":"card-b","identity":{"name":"Island","setCode":"M21","cardNumber":"310"}},
        {"id":"card-c","identity":{"name":"Soldier","setCode":"TM21","cardNumber":"1","isToken":true}}
      ]}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || !view.Supported || view.Title != "Discard" || view.CardMinimum != 1 ||
		view.CardMaximum != 2 || len(view.Cards) != 3 || !view.Cards[2].Token ||
		!view.Cards[0].Selected || view.Cards[1].Selected {
		t.Fatalf("choose-cards prompt = %+v, %v", view, err)
	}
	response, err := BuildPromptResponse(raw, 1, 51, PromptResponse{
		ResponseID: "$submit", CardIDs: []string{"card-c", "card-a"},
	})
	if err != nil || string(response) !=
		`{"output":{"chosenCardIds":["card-c","card-a"],"type":"chooseCardsDecision"},"type":"chooseCards"}` {
		t.Fatalf("choose-cards response = %s, %v", response, err)
	}
	for _, answer := range []PromptResponse{
		{ResponseID: "$submit"},
		{ResponseID: "$submit", CardIDs: []string{"card-a", "card-a"}},
		{ResponseID: "$submit", CardIDs: []string{"foreign"}},
		{ResponseID: "$cancel", CardIDs: []string{"card-a"}},
		{ResponseID: "$submit", CardIDs: []string{"card-a"}, TargetIDs: []string{"target:0"}},
	} {
		if _, err := BuildPromptResponse(raw, 1, 51, answer); err == nil {
			t.Fatalf("invalid card selection unexpectedly succeeded: %+v", answer)
		}
	}
}

func TestChooseCardsAllowsOptionalEmptySelection(t *testing.T) {
	raw := json.RawMessage(`{"promptId":52,"decidingPlayerId":"player-0","input":{
      "type":"chooseCards","min":0,"max":3,"cards":[
        {"id":"card-a","identity":{"name":"Opt","setCode":"XLN","cardNumber":"65"}}
      ]}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || view.CardMinimum != 0 || view.CardMaximum != 1 {
		t.Fatalf("optional choose-cards prompt = %+v, %v", view, err)
	}
	response, err := BuildPromptResponse(raw, 0, 52, PromptResponse{ResponseID: "$submit"})
	if err != nil || string(response) !=
		`{"output":{"chosenCardIds":[],"type":"chooseCardsDecision"},"type":"chooseCards"}` {
		t.Fatalf("optional choose-cards response = %s, %v", response, err)
	}
}

func TestChooseCardsReadOnlyDisclosure(t *testing.T) {
	raw := json.RawMessage(`{"promptId":54,"decidingPlayerId":"player-0","input":{
      "type":"chooseCards","min":1,"max":3,"cards":[
        {"id":"land","identity":{"name":"Forest"},"readOnly":true},
        {"id":"creature","identity":{"name":"Grizzly Bears"}},
        {"id":"land-2","identity":{"name":"Forest"},"readOnly":true}]}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || len(view.Cards) != 3 || view.CardMaximum != 1 ||
		view.Cards[0].ID != "reveal:0" || !view.Cards[0].ReadOnly ||
		view.Cards[1].ID != "creature" || view.Cards[1].ReadOnly || view.Cards[2].ID != "reveal:2" {
		t.Fatalf("combined card choice = %+v, %v", view, err)
	}
	for _, id := range []string{"land", "reveal:0", "land-2", "reveal:2"} {
		if _, err := BuildPromptResponse(raw, 0, 54, PromptResponse{ResponseID: "$submit", CardIDs: []string{id}}); err == nil {
			t.Fatalf("read-only card accepted: %s", id)
		}
	}
	if _, err := BuildPromptResponse(raw, 1, 54, PromptResponse{ResponseID: "$submit", CardIDs: []string{"creature"}}); err == nil {
		t.Fatal("other seat accepted the private choice")
	}
	if _, err := BuildPromptResponse(raw, 0, 53, PromptResponse{ResponseID: "$submit", CardIDs: []string{"creature"}}); err == nil {
		t.Fatal("stale choice accepted")
	}
	response, err := BuildPromptResponse(raw, 0, 54, PromptResponse{ResponseID: "$submit", CardIDs: []string{"creature"}})
	if err != nil || string(response) != `{"output":{"chosenCardIds":["creature"],"type":"chooseCardsDecision"},"type":"chooseCards"}` {
		t.Fatalf("eligible choice = %s, %v", response, err)
	}
	for _, invalid := range []string{
		strings.Replace(string(raw), `"min":1`, `"min":2`, 1),
		strings.Replace(string(raw), `"readOnly":true`, `"readOnly":true,"selected":true`, 1),
	} {
		if _, err := NormalizePrompt(json.RawMessage(invalid)); err == nil {
			t.Fatalf("invalid combined prompt accepted: %s", invalid)
		}
	}
}

func TestChooseCardsCancellationPreservesNativePermission(t *testing.T) {
	raw := json.RawMessage(`{"promptId":53,"decidingPlayerId":"player-0","input":{
      "type":"chooseCards","min":1,"max":1,"cancellable":true,
      "cards":[{"id":"card-a","identity":{"name":"Plains"}}]}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || !view.Cancellable {
		t.Fatalf("native cost cancellation missing: %+v, %v", view, err)
	}
	response, err := BuildPromptResponse(raw, 0, 53, PromptResponse{ResponseID: "$cancel"})
	if err != nil || string(response) != `{"output":{"type":"cancel"},"type":"chooseCards"}` {
		t.Fatalf("card cost cancellation = %s, %v", response, err)
	}
	if _, err := BuildPromptResponse(raw, 0, 53, PromptResponse{ResponseID: "$cancel", CardIDs: []string{"card-a"}}); err == nil {
		t.Fatal("cancel accepted a simultaneous card selection")
	}
	required := json.RawMessage(strings.Replace(string(raw), `"cancellable":true`, `"cancellable":false`, 1))
	if _, err := BuildPromptResponse(required, 0, 53, PromptResponse{ResponseID: "$cancel"}); err == nil {
		t.Fatal("mandatory selection accepted cancellation")
	}
}

func TestNormalizeAndBuildBoardTargets(t *testing.T) {
	raw := json.RawMessage(`{"promptId":6,"decidingPlayerId":"player-0","input":{
      "type":"chooseBoardTargets","presentation":{"title":"Choose targets"},
      "candidates":[{"kind":"player","id":"player-1"},{"kind":"card","id":"card-a"},
      {"kind":"spell","id":"stack-2"}],"minTargets":1,"maxTargets":2,
      "chosenTargets":0,"cancellable":true}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || !view.Supported || view.MinSelected != 1 || view.MaxSelected != 2 ||
		!view.Cancellable || len(view.Targets) != 3 || view.Targets[1].ResponseID != "target:1" {
		t.Fatalf("board-target prompt = %+v, %v", view, err)
	}
	response, err := BuildPromptResponse(raw, 0, 6, PromptResponse{
		ResponseID: "$submit", TargetIDs: []string{"target:2", "target:0"},
	})
	if err != nil || string(response) !=
		`{"output":{"chosen":[{"kind":"spell","id":"stack-2"},{"kind":"player","id":"player-1"}],"type":"boardTargets"},"type":"chooseBoardTargets"}` {
		t.Fatalf("board-target response = %s, %v", response, err)
	}
	cancel, err := BuildPromptResponse(raw, 0, 6, PromptResponse{ResponseID: "$cancel"})
	if err != nil || string(cancel) !=
		`{"output":{"type":"cancel"},"type":"chooseBoardTargets"}` {
		t.Fatalf("board-target cancel = %s, %v", cancel, err)
	}
	for _, selection := range [][]string{nil, {"target:0", "target:0"}, {"target:3"}} {
		if _, err := BuildPromptResponse(raw, 0, 6, PromptResponse{
			ResponseID: "$submit", TargetIDs: selection,
		}); err == nil {
			t.Fatalf("invalid target selection unexpectedly succeeded: %v", selection)
		}
	}
}

func TestNativeReservedBoardTargetsRemainSingleClickResponses(t *testing.T) {
	raw := json.RawMessage(`{"promptId":7,"decidingPlayerId":"player-0","input":{
      "type":"chooseBoardTargets","candidates":[
      {"kind":"card","id":"artifact-a","selected":true},
      {"kind":"card","id":"artifact-b","selected":true},
      {"kind":"card","id":"artifact-c","selected":false}],
      "minTargets":0,"maxTargets":1,"chosenTargets":0,"cancellable":true}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || !view.Supported || len(view.Targets) != 3 ||
		!view.Targets[0].Selected || !view.Targets[1].Selected || view.Targets[2].Selected ||
		view.MinSelected != 0 || view.MaxSelected != 1 {
		t.Fatalf("native reservations = %+v, %v", view, err)
	}
	for _, selection := range [][]string{{"target:0"}, {"target:2"}, {}} {
		response, err := BuildPromptResponse(raw, 0, 7, PromptResponse{
			ResponseID: "$submit", TargetIDs: selection,
		})
		if err != nil || strings.Contains(string(response), "selected") {
			t.Fatalf("reservation must not be echoed into the native click: %s, %v", response, err)
		}
	}
	if _, err := BuildPromptResponse(raw, 0, 7, PromptResponse{
		ResponseID: "$submit", TargetIDs: []string{"target:0", "target:1"},
	}); err == nil {
		t.Fatal("native reservations must not widen the per-click response bounds")
	}
}

func TestNormalizeAndBuildAttackers(t *testing.T) {
	raw := json.RawMessage(`{"promptId":7,"decidingPlayerId":"player-0","input":{
      "type":"chooseAttackers","attackers":[
        {"attackerId":"card-a","validTargetIds":["player-1","card-w"],"mustAttack":true},
        {"attackerId":"card-b","validTargetIds":["player-1"],"mustAttack":false}],
      "attackTargets":[
        {"id":"player-1","label":"Bob","kind":"player"},
        {"id":"card-w","label":"Jace","kind":"planeswalker"}]}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || !view.Supported || len(view.CombatSources) != 2 ||
		len(view.CombatTargets) != 2 || !view.CombatSources[0].MustAssignIfAble ||
		view.CombatSources[0].ValidTargetIDs[1] != "combat-target:1" {
		t.Fatalf("attacker prompt = %+v, %v", view, err)
	}
	response, err := BuildPromptResponse(raw, 0, 7, PromptResponse{
		ResponseID: "$submit", Assignments: []PromptAssignment{
			{SourceID: "combat-source:0", TargetID: "combat-target:1"},
		},
	})
	if err != nil || string(response) !=
		`{"output":{"assignments":[{"attackerId":"card-a","targetId":"card-w"}],"type":"declareAttackers"},"type":"chooseAttackers"}` {
		t.Fatalf("attacker response = %s, %v", response, err)
	}
	empty, err := BuildPromptResponse(raw, 0, 7, PromptResponse{
		ResponseID: "$submit", Assignments: nil,
	})
	if err != nil || string(empty) !=
		`{"output":{"assignments":[],"type":"declareAttackers"},"type":"chooseAttackers"}` {
		t.Fatalf("empty attacker response = %s, %v", empty, err)
	}
	for _, assignments := range [][]PromptAssignment{
		{{SourceID: "combat-source:0", TargetID: "combat-target:9"}},
		{{SourceID: "combat-source:0", TargetID: "combat-target:0"},
			{SourceID: "combat-source:0", TargetID: "combat-target:1"}},
	} {
		if _, err := BuildPromptResponse(raw, 0, 7, PromptResponse{
			ResponseID: "$submit", Assignments: assignments,
		}); err == nil {
			t.Fatalf("invalid attacker assignments unexpectedly succeeded: %+v", assignments)
		}
	}
}

func TestNormalizeAndBuildBlockers(t *testing.T) {
	maximum := 1
	raw := json.RawMessage(`{"promptId":8,"decidingPlayerId":"player-1","input":{
      "type":"chooseBlockers","attackers":[
        {"attackerId":"card-a","validBlockerIds":["card-x","card-y"],
         "minBlockers":2,"mustBeBlocked":false},
        {"attackerId":"card-b","validBlockerIds":["card-y","card-z"],
         "minBlockers":1,"maxBlockers":1,"mustBeBlocked":true}],
      "availableBlockerIds":["card-x","card-y","card-z"],
      "blockerAssignmentLimits":[{"blockerId":"card-x","maxAssignments":1},
        {"blockerId":"card-y","maxAssignments":1},{"blockerId":"card-z","maxAssignments":1}]}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || !view.Supported || len(view.CombatSources) != 3 ||
		len(view.CombatTargets) != 2 || view.CombatTargets[0].Minimum != 2 ||
		view.CombatTargets[1].Maximum != maximum ||
		!view.CombatTargets[1].MustReceiveIfAble ||
		len(view.CombatSources[1].ValidTargetIDs) != 2 {
		t.Fatalf("blocker prompt = %+v, %v", view, err)
	}
	response, err := BuildPromptResponse(raw, 1, 8, PromptResponse{
		ResponseID: "$submit", Assignments: []PromptAssignment{
			{SourceID: "combat-source:0", TargetID: "combat-target:0"},
			{SourceID: "combat-source:1", TargetID: "combat-target:0"},
			{SourceID: "combat-source:2", TargetID: "combat-target:1"},
		},
	})
	if err != nil || !containsBytes(response, []byte(`"type":"declareBlockers"`)) ||
		!containsBytes(response, []byte(`"blockerId":"card-z"`)) {
		t.Fatalf("blocker response = %s, %v", response, err)
	}
	empty, err := BuildPromptResponse(raw, 1, 8, PromptResponse{
		ResponseID: "$submit", Assignments: nil,
	})
	if err != nil || string(empty) !=
		`{"output":{"assignments":[],"type":"declareBlockers"},"type":"chooseBlockers"}` {
		t.Fatalf("empty blocker response = %s, %v", empty, err)
	}
	for _, assignments := range [][]PromptAssignment{
		{{SourceID: "combat-source:0", TargetID: "combat-target:0"}},
		{{SourceID: "combat-source:0", TargetID: "combat-target:1"},
			{SourceID: "combat-source:1", TargetID: "combat-target:1"}},
	} {
		if _, err := BuildPromptResponse(raw, 1, 8, PromptResponse{
			ResponseID: "$submit", Assignments: assignments,
		}); err == nil {
			t.Fatalf("invalid blocker assignments unexpectedly succeeded: %+v", assignments)
		}
	}
}

func containsBytes(value, pattern []byte) bool {
	for index := 0; index+len(pattern) <= len(value); index++ {
		matched := true
		for offset := range pattern {
			if value[index+offset] != pattern[offset] {
				matched = false
				break
			}
		}
		if matched {
			return true
		}
	}
	return false
}

func TestManaPromptRespectsNativeButtonAvailability(t *testing.T) {
	raw := json.RawMessage(`{"promptId":5,"decidingPlayerId":"player-0","input":{"type":"payManaCost","actions":[{"id":"native-pool-G","type":"activateAbility","label":"Spend G"}],"canConfirmFromPool":false,"canAutoPay":false,"canCancel":false}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || len(view.Options) != 1 || view.Options[0].Label != "Spend G" {
		t.Fatalf("native mana actions = %+v, error = %v", view.Options, err)
	}
	for _, id := range []string{"$pay", "$auto-pay", "$cancel"} {
		if _, err := BuildPromptResponse(raw, 0, 5, PromptResponse{ResponseID: id}); err == nil {
			t.Fatalf("accepted unavailable native button %s", id)
		}
	}
	if _, err := BuildPromptResponse(raw, 0, 5, PromptResponse{ResponseID: "action:0"}); err != nil {
		t.Fatal(err)
	}
}
