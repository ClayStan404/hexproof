// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestNormalizeMulliganActionsHidesNativeIDs(t *testing.T) {
	raw := json.RawMessage(`{"promptId":12,"decidingPlayerId":"player-1","input":{
		"type":"mulligan","mulliganCount":2,"autoPassEligible":true,"actions":[
		{"id":"native-powder-one","type":"activateAbility","cardId":"card-41","label":"Serum Powder — Exile hand and redraw"},
		{"id":"native-powder-two","type":"activateAbility","cardId":"card-43","label":"Serum Powder — Exile hand and redraw"}]}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || !view.Supported || view.Kind != "mulligan" || view.AutoPassEligible ||
		view.Detail != "Mulligans taken: 2" || len(view.Options) != 4 {
		t.Fatalf("mulligan actions = %+v, %v", view, err)
	}
	for index, card := range []string{"card-41", "card-43"} {
		option := view.Options[index]
		if option.ResponseID != []string{"action:0", "action:1"}[index] ||
			option.Kind != "activateAbility" || option.CardID != card || option.Label == "" {
			t.Fatalf("mulligan card action %d = %+v", index, option)
		}
	}
	if view.Options[2].ResponseID != "$keep" || view.Options[3].ResponseID != "$mulligan" {
		t.Fatalf("mulligan decisions lost after native actions: %+v", view.Options)
	}
	encoded, err := json.Marshal(view)
	if err != nil || strings.Contains(string(encoded), "native-powder-") {
		t.Fatalf("native mulligan action leaked: %s, %v", encoded, err)
	}
	for _, malformed := range []json.RawMessage{
		json.RawMessage(`{"promptId":12,"decidingPlayerId":"player-1","input":{"type":"mulligan","actions":[{"id":""}]}}`),
	} {
		if _, err := NormalizePrompt(malformed); err == nil {
			t.Fatal("mulligan accepted an action without a native id")
		}
	}
}

func TestBuildMulliganActionRevalidatesCurrentDecision(t *testing.T) {
	raw := json.RawMessage(`{"promptId":12,"decidingPlayerId":"player-1","input":{
		"type":"mulligan","actions":[{"id":"native-powder-one","type":"activateAbility","cardId":"card-41"},
		{"id":"native-powder-two","type":"activateAbility","cardId":"card-43"}]}}`)
	response, err := BuildPromptResponse(raw, 1, 12, PromptResponse{ResponseID: "action:1"})
	if err != nil || string(response) != `{"output":{"actionId":"native-powder-two","type":"act"},"type":"mulligan"}` {
		t.Fatalf("mulligan native response = %s, %v", response, err)
	}
	for _, test := range []struct {
		name   string
		player int
		prompt int64
		answer PromptResponse
	}{
		{"wrong player", 0, 12, PromptResponse{ResponseID: "action:0"}},
		{"stale prompt", 1, 11, PromptResponse{ResponseID: "action:0"}},
		{"absent action", 1, 12, PromptResponse{ResponseID: "action:2"}},
		{"native id", 1, 12, PromptResponse{ResponseID: "native-powder-one"}},
		{"priority pass", 1, 12, PromptResponse{ResponseID: "$pass"}},
		{"stack pass", 1, 12, PromptResponse{ResponseID: "$pass-stack"}},
		{"card selection", 1, 12, PromptResponse{ResponseID: "action:0", CardIDs: []string{"card-41"}}},
		{"target selection", 1, 12, PromptResponse{ResponseID: "action:0", TargetIDs: []string{"target:0"}}},
		{"choice selection", 1, 12, PromptResponse{ResponseID: "action:0", ChoiceIDs: []string{"choice:0"}}},
		{"number selection", 1, 12, PromptResponse{ResponseID: "action:0", ChosenNumber: new(int)}},
	} {
		t.Run(test.name, func(t *testing.T) {
			if _, err := BuildPromptResponse(raw, test.player, test.prompt, test.answer); err == nil {
				t.Fatal("invalid mulligan action was accepted")
			}
		})
	}
	refreshed := json.RawMessage(`{"promptId":13,"decidingPlayerId":"player-1","input":{"type":"mulligan"}}`)
	if _, err := BuildPromptResponse(refreshed, 1, 13, PromptResponse{ResponseID: "action:0"}); err == nil {
		t.Fatal("an exiled Serum Powder remained available in the replacement hand")
	}
	for _, keep := range []string{"$keep", "$mulligan"} {
		if _, err := BuildPromptResponse(raw, 1, 12, PromptResponse{ResponseID: keep}); err != nil {
			t.Fatalf("native actions prevented %s: %v", keep, err)
		}
	}
}
