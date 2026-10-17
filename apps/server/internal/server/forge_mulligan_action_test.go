// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

type mulliganActionRuntime struct {
	*modelTestRuntime
	action json.RawMessage
}

func (f *mulliganActionRuntime) Prompt(ctx context.Context, session string, player int) (json.RawMessage, error) {
	if f.submitted != 0 {
		return f.modelTestRuntime.Prompt(ctx, session, player)
	}
	return json.RawMessage(`{"promptId":1,"decidingPlayerId":"player-1","input":{"type":"mulligan","actions":[
		{"id":"private-powder-one","type":"activateAbility","cardId":"card-41","label":"Serum Powder — Exile hand and redraw"},
		{"id":"private-powder-two","type":"activateAbility","cardId":"card-43","label":"Serum Powder — Exile hand and redraw"}]}}`), nil
}

func (f *mulliganActionRuntime) SubmitAction(ctx context.Context, session string, action json.RawMessage) error {
	f.action = append(json.RawMessage(nil), action...)
	return f.modelTestRuntime.SubmitAction(ctx, session, action)
}

func TestMulliganActionsRemainPrivateAndReachModelResponsePath(t *testing.T) {
	h, r, host, worker, prior := modelTestRoom(t)
	h.pauseModelWorker(r.ID, "", false)
	for len(worker.Send) > 0 {
		<-worker.Send
	}
	runtime := &mulliganActionRuntime{modelTestRuntime: prior}
	game := h.forgeGames[r.ID]
	game.client = runtime
	h.forgeGames[r.ID] = game
	spectator := &Session{ConnectionID: "powder-observer", Send: make(chan []byte, 16)}
	entry, err := h.hub.beginJoin(r.ID, "")
	if err != nil {
		t.Fatal(err)
	}
	_, _, err = h.hub.joinRoom(entry, spectator, true)
	entry.opMu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	operation, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		t.Fatal(err)
	}
	prompts, err := h.rulesPrompts(r)
	operation.opMu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	if _, exists := prompts[spectator.ConnectionID]; exists {
		t.Fatal("a spectator received private mulligan actions")
	}
	var humanPrompt protocol.RulesPrompt
	if err := prompts[host.ConnectionID].DecodePayload(&humanPrompt); err != nil {
		t.Fatal(err)
	}
	if humanPrompt.Pending || len(humanPrompt.Options) != 0 ||
		strings.Contains(string(prompts[host.ConnectionID].Payload), "Powder") {
		t.Fatalf("another seat received mulligan actions: %+v", humanPrompt)
	}
	decision := modelDecision(t, worker)
	encoded, _ := json.Marshal(decision.Prompt)
	if decision.Prompt.Kind != "mulligan" || len(decision.Prompt.Options) != 4 ||
		decision.Prompt.Options[1].ResponseID != "action:1" ||
		decision.Prompt.Options[1].CardID != "card-43" || strings.Contains(string(encoded), "private-powder") {
		t.Fatalf("model mulligan options lost their private mapping: %s", encoded)
	}
	h.handleModelAnswer(r.ID, worker, protocol.AIAnswer{RequestID: decision.RequestID,
		Response: protocol.RulesRespond{PromptID: decision.Prompt.PromptID, ResponseID: "action:1"}})
	if runtime.submitted != 1 || string(runtime.action) != `{"output":{"actionId":"private-powder-two","type":"act"},"type":"mulligan"}` {
		t.Fatalf("model mulligan action did not use the canonical private response: %s", runtime.action)
	}
}
