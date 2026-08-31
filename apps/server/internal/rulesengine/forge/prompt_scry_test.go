// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"encoding/json"
	"testing"
)

func TestNormalizeAndBuildScry(t *testing.T) {
	raw := json.RawMessage(`{"promptId":72,"decidingPlayerId":"player-1","input":{
      "type":"scry","presentation":{"title":"Scry 2","description":"Sort the top cards."},
      "cards":[
        {"id":"secret-card-a","identity":{"name":"Island","setCode":"M21","cardNumber":"310"}},
        {"id":"secret-card-b","identity":{"name":"Opt","setCode":"M21","cardNumber":"59"}}
      ],"zones":["libraryTop","libraryBottom"]}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || !view.Supported || view.Title != "Scry 2" ||
		len(view.Cards) != 2 || view.Cards[0].ID != "scry:0" ||
		view.Cards[1].ID != "scry:1" || len(view.ScryDestinations) != 2 ||
		view.ScryDestinations[1] != "libraryBottom" {
		t.Fatalf("scry prompt = %+v, %v", view, err)
	}
	encoded, err := json.Marshal(view)
	if err != nil || containsBytes(encoded, []byte("secret-card-a")) ||
		containsBytes(encoded, []byte("secret-card-b")) {
		t.Fatalf("normalized scry leaked upstream ids: %s, %v", encoded, err)
	}
	response, err := BuildPromptResponse(raw, 1, 72, PromptResponse{
		ResponseID: "$submit",
		ScryPiles: []PromptScryPile{
			{Destination: "libraryTop", CardIDs: []string{"scry:1"}},
			{Destination: "libraryBottom", CardIDs: []string{"scry:0"}},
		},
	})
	if err != nil || string(response) !=
		`{"output":{"type":"scryDecision","zoneCardIds":[["secret-card-b"],["secret-card-a"]]},"type":"scry"}` {
		t.Fatalf("scry response = %s, %v", response, err)
	}
}

func TestScryRejectsInvalidAssignments(t *testing.T) {
	raw := json.RawMessage(`{"promptId":73,"decidingPlayerId":"player-0","input":{
      "type":"scry","cards":[
        {"id":"card-a","identity":{"name":"Island"}},
        {"id":"card-b","identity":{"name":"Opt"}}
      ],"zones":["libraryTop","graveyard"]}}`)
	valid := []PromptScryPile{
		{Destination: "libraryTop", CardIDs: []string{"scry:0"}},
		{Destination: "graveyard", CardIDs: []string{"scry:1"}},
	}
	tests := []PromptResponse{
		{ResponseID: "$cancel", ScryPiles: valid},
		{ResponseID: "$submit", ScryPiles: valid[:1]},
		{ResponseID: "$submit", ScryPiles: []PromptScryPile{
			{Destination: "graveyard", CardIDs: []string{"scry:0"}},
			{Destination: "libraryTop", CardIDs: []string{"scry:1"}},
		}},
		{ResponseID: "$submit", ScryPiles: []PromptScryPile{
			{Destination: "libraryTop", CardIDs: []string{"scry:0"}},
			{Destination: "graveyard", CardIDs: []string{"scry:0"}},
		}},
		{ResponseID: "$submit", ScryPiles: []PromptScryPile{
			{Destination: "libraryTop", CardIDs: []string{"scry:0"}},
			{Destination: "graveyard", CardIDs: []string{}},
		}},
		{ResponseID: "$submit", ScryPiles: valid, OrderedIDs: []string{"order:0"}},
	}
	for _, answer := range tests {
		if _, err := BuildPromptResponse(raw, 0, 73, answer); err == nil {
			t.Fatalf("invalid scry response unexpectedly succeeded: %+v", answer)
		}
	}
	if _, err := BuildPromptResponse(raw, 1, 73, PromptResponse{
		ResponseID: "$submit", ScryPiles: valid,
	}); err == nil {
		t.Fatal("foreign scry response unexpectedly succeeded")
	}
}

func TestNormalizeScryRejectsInvalidPrompt(t *testing.T) {
	for _, input := range []string{
		`{"cards":[],"zones":[]}`,
		`{"cards":[],"zones":["battlefield"]}`,
		`{"cards":[],"zones":["libraryTop","libraryTop"]}`,
		`{"cards":[{"id":"same"},{"id":"same"}],"zones":["libraryTop"]}`,
	} {
		raw := json.RawMessage(`{"promptId":74,"decidingPlayerId":"player-0",` +
			`"input":{"type":"scry",` + input[1:])
		if _, err := NormalizePrompt(raw); err == nil {
			t.Fatalf("invalid scry prompt unexpectedly normalized: %s", raw)
		}
	}
}
