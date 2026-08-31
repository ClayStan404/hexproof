// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"encoding/json"
	"testing"
)

func TestNormalizePromptContext(t *testing.T) {
	raw := json.RawMessage(`{"promptId":91,"decidingPlayerId":"player-0",
      "sourceCard":{"id":"secret-source","identity":{"name":"Circle of Protection: Red","setCode":"4ED","cardNumber":"17"}},
      "input":{"type":"chooseBoolean","presentation":{
        "title":"Pay {1} to prevent damage?","description":"Choose whether to pay.",
        "text":"otherwise: \"3 damage is dealt.\"","targets":[
          {"kind":"card","id":"secret-target"},{"kind":"player","id":"player-0"}]},
        "confirmLabel":"Pay","denyLabel":"Decline"}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || len(view.ContextCards) != 1 ||
		view.ContextCards[0].ID != "context-card:0" ||
		view.ContextCards[0].Name != "Circle of Protection: Red" ||
		len(view.ContextTargets) != 2 ||
		view.ContextTargets[1].ResponseID != "context-target:1" ||
		view.ContextText != `otherwise: "3 damage is dealt."` {
		t.Fatalf("prompt context = %+v, %v", view, err)
	}
	response, err := BuildPromptResponse(raw, 0, 91, PromptResponse{
		ResponseID: "$submit", ChoiceIDs: []string{"choice:1"},
	})
	if err != nil || string(response) !=
		`{"output":{"type":"decision","value":true},"type":"chooseBoolean"}` {
		t.Fatalf("contextual boolean response = %s, %v", response, err)
	}
}

func TestNormalizePromptContextRejectsMalformedDisplayState(t *testing.T) {
	for _, fragment := range []string{
		`"sourceCard":{"id":"","identity":{"name":"Source"}},`,
		`"sourceCard":{"id":"source","identity":{"name":""}},`,
		``,
	} {
		targets := `[{"kind":"card","id":"target"}]`
		if fragment == "" {
			targets = `[{"kind":"card","id":"same"},{"kind":"card","id":"same"}]`
		}
		raw := json.RawMessage(`{"promptId":92,"decidingPlayerId":"player-0",` + fragment +
			`"input":{"type":"chooseBoolean","presentation":{"targets":` + targets +
			`},"confirmLabel":"Yes","denyLabel":"No"}}`)
		if _, err := NormalizePrompt(raw); err == nil {
			t.Fatalf("invalid prompt context unexpectedly normalized: %s", raw)
		}
	}
}
