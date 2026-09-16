// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestCardNamePromptUsesFreeTextWithoutPrivateCandidates(t *testing.T) {
	raw := json.RawMessage(`{"promptId":9,"decidingPlayerId":"player-1","input":{"type":"chooseCardName","message":"Choose a nonland card name","canCancel":true}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || !view.Supported || !view.Cancellable || view.Kind != "chooseCardName" ||
		view.Detail != "Choose a nonland card name" || len(view.Choices) != 0 || len(view.Cards) != 0 {
		t.Fatalf("card-name prompt = %+v, error = %v", view, err)
	}
	for _, name := range []string{"Black Lotus", "  Fblthp, the Lost  ", "未在本地目录收录的牌名"} {
		response, err := BuildPromptResponse(raw, 1, 9, PromptResponse{ResponseID: "$submit", Name: name})
		if err != nil {
			t.Fatal(err)
		}
		var decoded struct {
			Type   string `json:"type"`
			Output struct {
				Type string `json:"type"`
				Name string `json:"name"`
			} `json:"output"`
		}
		if err := json.Unmarshal(response, &decoded); err != nil || decoded.Type != "chooseCardName" ||
			decoded.Output.Type != "cardName" || decoded.Output.Name != strings.TrimSpace(name) {
			t.Fatalf("canonical naming response = %s, error = %v", response, err)
		}
	}
	if _, err := BuildPromptResponse(raw, 1, 9, PromptResponse{ResponseID: "$cancel"}); err != nil {
		t.Fatal(err)
	}
	for _, answer := range []PromptResponse{
		{ResponseID: "$submit", Name: " "},
		{ResponseID: "$submit", Name: strings.Repeat("x", 257)},
		{ResponseID: "$submit", Name: "Black\nLotus"},
		{ResponseID: "$submit", Name: "Black Lotus", CardIDs: []string{"card:0"}},
		{ResponseID: "$submit", Name: "Black Lotus", ChoiceIDs: []string{"choice:0"}},
		{ResponseID: "$cancel", Name: "Black Lotus"},
		{ResponseID: "Black Lotus", Name: "Black Lotus"},
	} {
		if _, err := BuildPromptResponse(raw, 1, 9, answer); err == nil {
			t.Fatalf("accepted invalid naming response: %+v", answer)
		}
	}
	answer := PromptResponse{ResponseID: "$submit", Name: "Black Lotus"}
	for _, ids := range [][2]int{{0, 9}, {1, 8}} {
		if _, err := BuildPromptResponse(raw, ids[0], int64(ids[1]), answer); err == nil {
			t.Fatal("accepted another player's or stale naming decision")
		}
	}
	mandatory := json.RawMessage(strings.Replace(string(raw), `"canCancel":true`, `"canCancel":false`, 1))
	if _, err := BuildPromptResponse(mandatory, 1, 9, PromptResponse{ResponseID: "$cancel"}); err == nil {
		t.Fatal("accepted cancellation of mandatory naming")
	}
	other := json.RawMessage(`{"promptId":9,"decidingPlayerId":"player-1","input":{"type":"chooseAction","actions":[]}}`)
	if _, err := BuildPromptResponse(other, 1, 9, PromptResponse{ResponseID: "$pass", Name: "Black Lotus"}); err == nil {
		t.Fatal("accepted a card name in an unrelated prompt")
	}
}
