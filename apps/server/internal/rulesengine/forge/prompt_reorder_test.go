// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"encoding/json"
	"testing"
)

func TestNormalizeAndBuildReorder(t *testing.T) {
	raw := json.RawMessage(`{"promptId":61,"decidingPlayerId":"player-1","input":{
      "type":"reorder","presentation":{"title":"Order triggers"},"items":[
        {"id":"secret-trigger-a","card":{"id":"card-a","identity":{"name":"Teval","setCode":"DFT","cardNumber":"199"}},"oracle":"Create a token."},
        {"id":"secret-trigger-b","card":{"id":"card-b","identity":{"name":"Teval's Judgment","setCode":"DFT","cardNumber":"202"}},"oracle":"Choose a mode."}
      ]}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || !view.Supported || view.Title != "Order triggers" ||
		len(view.OrderItems) != 2 || view.OrderItems[0].ResponseID != "order:0" ||
		view.OrderItems[1].Oracle != "Choose a mode." {
		t.Fatalf("reorder prompt = %+v, %v", view, err)
	}
	response, err := BuildPromptResponse(raw, 1, 61, PromptResponse{
		ResponseID: "$submit", OrderedIDs: []string{"order:1", "order:0"},
	})
	if err != nil || string(response) !=
		`{"output":{"orderedIds":["secret-trigger-b","secret-trigger-a"],"type":"reorderDecision"},"type":"reorder"}` {
		t.Fatalf("reorder response = %s, %v", response, err)
	}
	for _, answer := range []PromptResponse{
		{ResponseID: "$submit", OrderedIDs: []string{"order:0"}},
		{ResponseID: "$submit", OrderedIDs: []string{"order:0", "order:0"}},
		{ResponseID: "$submit", OrderedIDs: []string{"order:0", "order:2"}},
		{ResponseID: "$cancel", OrderedIDs: []string{"order:0", "order:1"}},
		{ResponseID: "$submit", OrderedIDs: []string{"order:0", "order:1"}, CardIDs: []string{"card-a"}},
	} {
		if _, err := BuildPromptResponse(raw, 1, 61, answer); err == nil {
			t.Fatalf("invalid reorder unexpectedly succeeded: %+v", answer)
		}
	}
}

func TestNormalizeReorderRejectsDuplicateUpstreamItems(t *testing.T) {
	raw := json.RawMessage(`{"promptId":62,"decidingPlayerId":"player-0","input":{
      "type":"reorder","items":[
        {"id":"same","card":{"id":"card-a","identity":{"name":"Opt"}}},
        {"id":"same","card":{"id":"card-b","identity":{"name":"Ponder"}}}
      ]}}`)
	if _, err := NormalizePrompt(raw); err == nil {
		t.Fatal("duplicate reorder items unexpectedly succeeded")
	}
}
