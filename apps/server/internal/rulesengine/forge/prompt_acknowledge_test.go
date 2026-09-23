// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"encoding/json"
	"testing"
)

func TestNormalizeAndBuildAcknowledgement(t *testing.T) {
	raw := json.RawMessage(`{"promptId":74,"decidingPlayerId":"player-0","input":{
      "type":"acknowledge","presentation":{"title":"AI deck advisory",
      "description":"Forge AI may not play these cards well:\nPrismatic Ending\nWrath of the Skies"}}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || !view.Supported || view.Kind != "acknowledge" ||
		view.Title != "AI deck advisory" ||
		view.Detail != "Forge AI may not play these cards well:\nPrismatic Ending\nWrath of the Skies" ||
		len(view.Options) != 1 || len(view.Choices) != 0 ||
		view.Options[0] != (PromptOption{ResponseID: "$ack", Kind: "acknowledge", Label: "Continue"}) {
		t.Fatalf("acknowledgement prompt = %+v, %v", view, err)
	}
	response, err := BuildPromptResponse(raw, 0, 74, PromptResponse{ResponseID: "$ack"})
	if err != nil || string(response) != `{"output":{"type":"acknowledged"},"type":"acknowledge"}` {
		t.Fatalf("acknowledgement response = %s, %v", response, err)
	}
	for _, ids := range [][2]int{{1, 74}, {0, 73}} {
		if _, err := BuildPromptResponse(raw, ids[0], int64(ids[1]), PromptResponse{ResponseID: "$ack"}); err == nil {
			t.Fatalf("foreign or stale acknowledgement accepted: %v", ids)
		}
	}
	number := 1
	for _, answer := range []PromptResponse{
		{ResponseID: "$submit"},
		{ResponseID: "choice:0"},
		{ResponseID: "$ack", CardIDs: []string{"card:0"}},
		{ResponseID: "$ack", TargetIDs: []string{"target:0"}},
		{ResponseID: "$ack", Assignments: []PromptAssignment{{SourceID: "source:0", TargetID: "target:0"}}},
		{ResponseID: "$ack", ChoiceIDs: []string{"choice:0"}},
		{ResponseID: "$ack", OrderedIDs: []string{"item:0"}},
		{ResponseID: "$ack", ScryPiles: []PromptScryPile{{Destination: "top", CardIDs: []string{"card:0"}}}},
		{ResponseID: "$ack", DamageOrderIDs: []string{"target:0"}},
		{ResponseID: "$ack", DamageAssignments: []PromptDamageAssignment{{TargetID: "target:0", Damage: 1}}},
		{ResponseID: "$ack", ChosenNumber: &number},
		{ResponseID: "$ack", Name: "Prismatic Ending"},
	} {
		if _, err := BuildPromptResponse(raw, 0, 74, answer); err == nil {
			t.Fatalf("unexpected acknowledgement payload accepted: %+v", answer)
		}
	}
}

func TestAcknowledgementDefaultsToGameNotice(t *testing.T) {
	raw := json.RawMessage(`{"promptId":75,"decidingPlayerId":"player-0",
      "input":{"type":"acknowledge","presentation":{"description":"The game will continue."}}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || view.Title != "Game notice" || view.Detail != "The game will continue." {
		t.Fatalf("generic acknowledgement prompt = %+v, %v", view, err)
	}
}
