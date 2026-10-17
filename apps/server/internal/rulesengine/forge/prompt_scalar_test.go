// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"encoding/json"
	"testing"
)

func TestNormalizeAndBuildBoolean(t *testing.T) {
	raw := json.RawMessage(`{"promptId":20,"decidingPlayerId":"player-0","input":{
      "type":"chooseBoolean","presentation":{"title":"Use replacement effect?"},
      "confirmLabel":"Use it","denyLabel":"Decline"}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || !view.Supported || len(view.Choices) != 2 ||
		view.Choices[0].Label != "Decline" || view.Choices[1].Label != "Use it" ||
		view.ChoiceMinimum != 1 || view.ChoiceMaximum != 1 {
		t.Fatalf("boolean prompt = %+v, %v", view, err)
	}
	response, err := BuildPromptResponse(raw, 0, 20, PromptResponse{
		ResponseID: "$submit", ChoiceIDs: []string{"choice:1"},
	})
	if err != nil || string(response) !=
		`{"output":{"type":"decision","value":true},"type":"chooseBoolean"}` {
		t.Fatalf("boolean response = %s, %v", response, err)
	}
	for _, choices := range [][]string{nil, {"choice:0", "choice:1"}, {"choice:2"}} {
		if _, err := BuildPromptResponse(raw, 0, 20, PromptResponse{
			ResponseID: "$submit", ChoiceIDs: choices,
		}); err == nil {
			t.Fatalf("invalid boolean choice unexpectedly succeeded: %v", choices)
		}
	}
}

func TestNormalizeAndBuildNumber(t *testing.T) {
	raw := json.RawMessage(`{"promptId":21,"decidingPlayerId":"player-1","input":{
      "type":"chooseNumber","presentation":{"description":"Choose X."},"min":-2,"max":7}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || view.NumberMinimum != -2 || view.NumberMaximum != 7 ||
		len(view.Choices) != 0 {
		t.Fatalf("number prompt = %+v, %v", view, err)
	}
	chosen := 0
	response, err := BuildPromptResponse(raw, 1, 21, PromptResponse{
		ResponseID: "$submit", ChosenNumber: &chosen,
	})
	if err != nil || string(response) !=
		`{"output":{"chosenNumber":0,"type":"numberDecision"},"type":"chooseNumber"}` {
		t.Fatalf("number response = %s, %v", response, err)
	}
	tooLarge := 8
	for _, answer := range []PromptResponse{
		{ResponseID: "$submit"},
		{ResponseID: "$submit", ChosenNumber: &tooLarge},
		{ResponseID: "$cancel", ChosenNumber: &chosen},
	} {
		if _, err := BuildPromptResponse(raw, 1, 21, answer); err == nil {
			t.Fatalf("invalid number response unexpectedly succeeded: %+v", answer)
		}
	}
}

func TestNormalizeAndBuildColors(t *testing.T) {
	raw := json.RawMessage(`{"promptId":22,"decidingPlayerId":"player-0","input":{
      "type":"chooseColor","validColors":["White","Blue","Black"],
      "amount":2,"repeatAllowed":true}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || len(view.Choices) != 3 || !view.Choices[0].CanRepeat ||
		view.ChoiceMinimum != 2 || view.ChoiceMaximum != 2 {
		t.Fatalf("color prompt = %+v, %v", view, err)
	}
	response, err := BuildPromptResponse(raw, 0, 22, PromptResponse{
		ResponseID: "$submit", ChoiceIDs: []string{"choice:1", "choice:1"},
	})
	if err != nil || string(response) !=
		`{"output":{"chosenColors":{"Blue":2},"type":"colorDecision"},"type":"chooseColor"}` {
		t.Fatalf("color response = %s, %v", response, err)
	}
	if _, err := BuildPromptResponse(raw, 0, 22, PromptResponse{
		ResponseID: "$submit", ChoiceIDs: []string{"choice:0"},
	}); err == nil {
		t.Fatal("incomplete color response unexpectedly succeeded")
	}
}

func TestSacrificialManaChoicesSuspendAndResumePayment(t *testing.T) {
	// Native Lotus Bloom opens its sacrifice confirmation and generic enum
	// chooser inside the spell's payment. Each replaces the previous prompt.
	initial := json.RawMessage(`{"promptId":30,"decidingPlayerId":"player-0","input":{
      "type":"payManaCost","paymentId":"sa:50","manaCost":"{2}",
      "actions":[{"id":"activate-lotus","type":"activateAbility","cardId":"card:lotus","label":"Lotus Bloom"}]}}`)
	confirmation := json.RawMessage(`{"promptId":31,"decidingPlayerId":"player-0","input":{
      "type":"chooseBoolean","presentation":{"title":"Confirm decision","description":"Sacrifice Lotus Bloom?"},
      "confirmLabel":"Yes","denyLabel":"No"}}`)
	colors := json.RawMessage(`{"promptId":32,"decidingPlayerId":"player-0","input":{
      "type":"chooseFromSelection","presentation":{"title":"Select Mana to Produce","description":""},
      "options":[{"label":"WHITE","weight":1,"canRepeat":false},{"label":"BLUE","weight":1,"canRepeat":false},
        {"label":"BLACK","weight":1,"canRepeat":false},{"label":"RED","weight":1,"canRepeat":false},
        {"label":"GREEN","weight":1,"canRepeat":false}],"minTotal":1,"maxTotal":1}}`)
	resumed := json.RawMessage(`{"promptId":33,"decidingPlayerId":"player-0","input":{
      "type":"payManaCost","paymentId":"sa:50","manaCost":"{1}","canConfirmFromPool":true,
      "actions":[{"id":"activate-plains","type":"activateAbility","cardId":"card:plains","label":"Plains"}]}}`)
	for _, stage := range []struct {
		raw      json.RawMessage
		promptID int64
		answer   PromptResponse
		want     string
	}{
		{initial, 30, PromptResponse{ResponseID: "action:0"},
			`{"output":{"actionId":"activate-lotus","type":"act"},"type":"payManaCost"}`},
		{confirmation, 31, PromptResponse{ResponseID: "$submit", ChoiceIDs: []string{"choice:1"}},
			`{"output":{"type":"decision","value":true},"type":"chooseBoolean"}`},
		{colors, 32, PromptResponse{ResponseID: "$submit", ChoiceIDs: []string{"choice:1"}},
			`{"output":{"chosenIndices":[1],"type":"selectionDecision"},"type":"chooseFromSelection"}`},
		{resumed, 33, PromptResponse{ResponseID: "$pay"},
			`{"output":{"auto":false,"type":"pay"},"type":"payManaCost"}`},
	} {
		response, err := BuildPromptResponse(stage.raw, 0, stage.promptID, stage.answer)
		if err != nil || string(response) != stage.want {
			t.Fatalf("payment stage %d response = %s, %v", stage.promptID, response, err)
		}
	}
	for _, stage := range []struct {
		raw      json.RawMessage
		promptID int64
		answer   PromptResponse
	}{
		{confirmation, 30, PromptResponse{ResponseID: "action:0"}},
		{colors, 32, PromptResponse{ResponseID: "$auto-pay"}},
		{colors, 32, PromptResponse{ResponseID: "$submit", ChoiceIDs: []string{"choice:1", "choice:1"}}},
		{resumed, 32, PromptResponse{ResponseID: "$submit", ChoiceIDs: []string{"choice:1"}}},
	} {
		if _, err := BuildPromptResponse(stage.raw, 0, stage.promptID, stage.answer); err == nil {
			t.Fatalf("stale or incompatible nested payment answer succeeded: %+v", stage.answer)
		}
	}
	view, err := NormalizePrompt(resumed)
	if err != nil || view.PaymentID != "sa:50" || view.Options[0].CardID != "card:plains" {
		t.Fatalf("resumed payment = %+v, %v", view, err)
	}
}

func TestNormalizeAndBuildWeightedSelection(t *testing.T) {
	raw := json.RawMessage(`{"promptId":23,"decidingPlayerId":"player-0","input":{
      "type":"chooseFromSelection","presentation":{"title":"Choose modes"},
      "options":[
        {"label":"First mode","weight":1,"canRepeat":false},
        {"label":"Second mode","weight":2,"canRepeat":true}],
      "minTotal":3,"maxTotal":4}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || len(view.Choices) != 2 || view.Choices[1].Weight != 2 ||
		!view.Choices[1].CanRepeat || view.ChoiceMinimum != 3 || view.ChoiceMaximum != 4 {
		t.Fatalf("selection prompt = %+v, %v", view, err)
	}
	response, err := BuildPromptResponse(raw, 0, 23, PromptResponse{
		ResponseID: "$submit", ChoiceIDs: []string{"choice:1", "choice:0"},
	})
	if err != nil || string(response) !=
		`{"output":{"chosenIndices":[1,0],"type":"selectionDecision"},"type":"chooseFromSelection"}` {
		t.Fatalf("selection response = %s, %v", response, err)
	}
	for _, choices := range [][]string{
		{"choice:0", "choice:0", "choice:1"},
		{"choice:1"},
		{"choice:1", "choice:1", "choice:1"},
	} {
		if _, err := BuildPromptResponse(raw, 0, 23, PromptResponse{
			ResponseID: "$submit", ChoiceIDs: choices,
		}); err == nil {
			t.Fatalf("invalid weighted selection unexpectedly succeeded: %v", choices)
		}
	}
}

func TestNormalizeScalarPromptsRejectInvalidBounds(t *testing.T) {
	for _, input := range []string{
		`{"type":"chooseNumber"}`,
		`{"type":"chooseNumber","min":2,"max":1}`,
		`{"type":"chooseColor","validColors":[]}`,
		`{"type":"chooseColor","validColors":["White"],"amount":2,"repeatAllowed":false}`,
		`{"type":"chooseColor","validColors":["White","White"],"amount":1}`,
		`{"type":"chooseFromSelection","options":[{"label":"Mode","weight":2}],"minTotal":1,"maxTotal":1}`,
		`{"type":"chooseFromSelection","options":[]}`,
	} {
		raw := json.RawMessage(`{"promptId":24,"decidingPlayerId":"player-0","input":` + input + `}`)
		if _, err := NormalizePrompt(raw); err == nil {
			t.Fatalf("invalid scalar prompt unexpectedly succeeded: %s", raw)
		}
	}
}
