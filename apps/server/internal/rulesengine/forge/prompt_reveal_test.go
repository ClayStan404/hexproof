// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"encoding/json"
	"testing"
)

func TestNormalizeAndBuildRevealCards(t *testing.T) {
	raw := json.RawMessage(`{"promptId":71,"decidingPlayerId":"player-1","input":{
      "type":"revealCards","presentation":{"title":"Reveal your hand",
      "description":"These cards are revealed to you."},"zone":"hand",
      "ownerPlayerId":"player-0","cards":[
        {"id":"card-a","identity":{"name":"Plains","setCode":"M21","cardNumber":"309"}},
        {"id":"card-b","identity":{"name":"Soldier","setCode":"TM21",
        "cardNumber":"1","isToken":true}}
      ]}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || !view.Supported || view.Title != "Reveal your hand" ||
		view.Detail != "These cards are revealed to you." || len(view.Cards) != 2 ||
		view.Cards[0].ID != "reveal:0" || view.Cards[1].ID != "reveal:1" ||
		view.Cards[1].CollectorNumber != "1" ||
		!view.Cards[1].Token || len(view.Options) != 1 ||
		view.Options[0].ResponseID != "$ack" {
		t.Fatalf("reveal prompt = %+v, %v", view, err)
	}
	encoded, err := json.Marshal(view)
	if err != nil || containsBytes(encoded, []byte("card-a")) ||
		containsBytes(encoded, []byte("card-b")) ||
		containsBytes(encoded, []byte("ownerPlayerId")) ||
		containsBytes(encoded, []byte(`"zone"`)) {
		t.Fatalf("normalized reveal leaked upstream state: %s, %v", encoded, err)
	}
	response, err := BuildPromptResponse(raw, 1, 71, PromptResponse{ResponseID: "$ack"})
	if err != nil || string(response) !=
		`{"output":{"type":"revealCardsAcknowledged"},"type":"revealCards"}` {
		t.Fatalf("reveal response = %s, %v", response, err)
	}

	for _, answer := range []PromptResponse{
		{ResponseID: "$submit"},
		{ResponseID: "$ack", CardIDs: []string{"card-a"}},
		{ResponseID: "$ack", TargetIDs: []string{"target:0"}},
	} {
		if _, err := BuildPromptResponse(raw, 1, 71, answer); err == nil {
			t.Fatalf("invalid reveal response unexpectedly succeeded: %+v", answer)
		}
	}
	if _, err := BuildPromptResponse(raw, 0, 71,
		PromptResponse{ResponseID: "$ack"}); err == nil {
		t.Fatal("foreign reveal acknowledgement unexpectedly succeeded")
	}
}

func TestRevealCardsAllowsNotificationWithoutCards(t *testing.T) {
	raw := json.RawMessage(`{"promptId":72,"decidingPlayerId":"player-0",
      "input":{"type":"revealCards","presentation":{"title":"A card was revealed"},
      "cards":[]}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || !view.Supported || view.Title != "A card was revealed" ||
		len(view.Cards) != 0 {
		t.Fatalf("notification reveal = %+v, %v", view, err)
	}
	if _, err := BuildPromptResponse(raw, 0, 72,
		PromptResponse{ResponseID: "$ack"}); err != nil {
		t.Fatalf("notification acknowledgement: %v", err)
	}
}

func TestRevealCardsRejectsInvalidCardIdentities(t *testing.T) {
	for _, cards := range []string{
		`[{"id":"","identity":{"name":"Plains"}}]`,
		`[{"id":"card-a"},{"id":"card-a"}]`,
	} {
		raw := json.RawMessage(`{"promptId":73,"decidingPlayerId":"player-0",
          "input":{"type":"revealCards","cards":` + cards + `}}`)
		if _, err := NormalizePrompt(raw); err == nil {
			t.Fatalf("invalid reveal cards unexpectedly normalized: %s", cards)
		}
	}
}
