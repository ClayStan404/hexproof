// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forgehost

import (
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
)

func peerExecutor(t *testing.T) (*Executor, PeerContext, PeerAction) {
	t.Helper()
	e := NewExecutor("ROOM", fixtureStart, nil)
	t.Cleanup(func() { e.Cancel("") })
	engine := NewID()
	p := e.Execute(t.Context(), Request{RoomID: "ROOM", EngineID: engine, ID: 1, Command: "start", Start: &forge.StartGameRequest{
		GameID: "game", Variant: "Constructed", Players: make([]forge.PlayerConfig, 2),
	}})
	if p.Error != "" {
		t.Fatal(p.Error)
	}
	binding := PeerContext{BindingID: NewID(), GameID: "game", EngineID: engine, PlayerIndex: 0, PublicPromptID: 91, NativePromptID: 1, Revision: 1}
	e.SetPeerContext(&binding)
	action := PeerAction{BindingID: binding.BindingID, OperationID: "decision-one", Request: protocol.RulesRespond{PromptID: 91, ResponseID: "$pass", PeerBinding: binding.BindingID}}
	return e, binding, action
}

func TestPeerFallbackAndDuplicatesMutateExactlyOnce(t *testing.T) {
	e, binding, action := peerExecutor(t)
	commit, reply := e.ExecutePeer(t.Context(), action)
	if commit == nil || reply != nil || commit.Publication.Revision != 2 {
		t.Fatal("direct mutation missing")
	}
	again, _ := e.ExecutePeer(t.Context(), action)
	if again == nil || again.Publication.Revision != 2 {
		t.Fatal("duplicate not retained")
	}
	response := e.Execute(t.Context(), Request{RoomID: "ROOM", EngineID: binding.EngineID, ID: 2, Command: "action",
		Action: commit.Action, PeerBinding: binding.BindingID, OperationID: action.OperationID})
	if response.Error != "" || response.Publication.Revision != 2 || e.runtime.(*fixtureRuntime).actions != 1 {
		t.Fatal("fallback repeated or lost mutation")
	}
	e.ConfirmPeer(&PeerReply{BindingID: binding.BindingID, OperationID: action.OperationID, Envelopes: []protocol.Envelope{{Type: protocol.TypeRulesResponded}}})
	if repeated, cached := e.ExecutePeer(t.Context(), action); repeated != nil || cached == nil || cached.Error != "" {
		t.Fatal("confirmed reply was not cached")
	}
}

func TestPeerRejectsWrongLeaseAndUnconfirmedNextDecision(t *testing.T) {
	for _, mode := range []string{"binding", "payloadBinding", "prompt", "seat", "revision", "expired", "engine"} {
		t.Run(mode, func(t *testing.T) {
			e, binding, action := peerExecutor(t)
			switch mode {
			case "binding":
				action.BindingID = NewID()
			case "payloadBinding":
				action.Request.PeerBinding = NewID()
			case "prompt":
				action.Request.PromptID++
			case "seat":
				binding.PlayerIndex = 1
			case "revision":
				binding.Revision++
			case "engine":
				binding.EngineID = NewID()
			}
			e.SetPeerContext(&binding)
			if mode == "expired" {
				e.peerExpires = time.Now().Add(-time.Second)
			}
			if commit, _ := e.ExecutePeer(t.Context(), action); commit != nil || e.runtime.(*fixtureRuntime).actions != 0 {
				t.Fatal("invalid lease mutated engine")
			}
		})
	}
	e, binding, action := peerExecutor(t)
	commit, _ := e.ExecutePeer(t.Context(), action)
	if commit == nil {
		t.Fatal("missing first mutation")
	}
	binding.Revision, binding.NativePromptID, binding.PublicPromptID = 2, 2, 92
	e.SetPeerContext(&binding)
	action.OperationID, action.Request.PromptID = "next", 92
	if next, _ := e.ExecutePeer(t.Context(), action); next != nil || e.runtime.(*fixtureRuntime).actions != 1 {
		t.Fatal("published an unconfirmed successor")
	}
}
