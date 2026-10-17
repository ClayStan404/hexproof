// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"encoding/json"
	"testing"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
)

type priorityPublicationRuntime struct {
	*modelTestRuntime
	terminal bool
	ended    int
	prompts  int
}

func (f *priorityPublicationRuntime) Prompt(context.Context, string, int) (json.RawMessage, error) {
	f.prompts++
	if f.submitted > 0 {
		if f.terminal {
			return nil, nil
		}
		return json.RawMessage(`{"promptId":2,"decidingPlayerId":"player-0","input":{"type":"acknowledge"}}`), nil
	}
	return json.RawMessage(`{"promptId":1,"decidingPlayerId":"player-0","input":{"type":"chooseAction","actions":[],"autoPassEligible":true}}`), nil
}

func (f *priorityPublicationRuntime) SnapshotView(_ context.Context, _ string, viewer int) (forge.GameView, error) {
	conceded := -1
	if f.terminal && f.submitted > 0 {
		conceded = 0
	}
	raw, _ := json.Marshal(forgeLifecycleSnapshot(f.gameID, viewer, conceded))
	view, err := forge.DecodeSnapshotView(raw)
	view.Turn = 1 + f.submitted
	return view, err
}

func (f *priorityPublicationRuntime) GameOver(context.Context, string) (bool, error) {
	return f.terminal && f.submitted > 0, nil
}

func (f *priorityPublicationRuntime) EndGame(context.Context, string) error {
	f.ended++
	return nil
}

func TestDelegatedPriorityPublishesCurrentSnapshotAndResult(t *testing.T) {
	for _, terminal := range []bool{false, true} {
		name := "advances"
		if terminal {
			name = "finishes"
		}
		t.Run(name, func(t *testing.T) {
			h, r, host, _, prior := modelTestRoom(t)
			runtime := &priorityPublicationRuntime{modelTestRuntime: prior, terminal: terminal}
			game := h.forgeGames[r.ID]
			game.client = runtime
			h.forgeGames[r.ID] = game
			h.setPriorityPreference(r.ID, 0, priorityPreference{})
			for len(host.Send) > 0 {
				<-host.Send
			}
			entry, err := h.hub.lockRoomOperation(r.ID)
			if err != nil {
				t.Fatal(err)
			}
			defer entry.opMu.Unlock()
			reply := h.publishRulesDecision(r, game, host.ConnectionID, "decision",
				protocol.RulesRespond{PromptID: 1, ResponseID: "$pass"}, false, false)
			if reply == nil || len(reply.Envelopes) != 3 {
				t.Fatal("decision publication failed")
			}
			assertRulesSnapshotPromptPair(t, reply.Envelopes[1], reply.Envelopes[2])
			var snapshot protocol.RulesGameSnapshot
			if err := reply.Envelopes[1].DecodePayload(&snapshot); err != nil {
				t.Fatal(err)
			}
			var prompt protocol.RulesPrompt
			if err := reply.Envelopes[2].DecodePayload(&prompt); err != nil {
				t.Fatal(err)
			}
			if runtime.submitted != 1 || snapshot.Turn != 2 || snapshot.GameOver != terminal {
				t.Fatalf("passes=%d, published turn=%d gameOver=%v, terminal=%v",
					runtime.submitted, snapshot.Turn, snapshot.GameOver, terminal)
			}
			if prompt.Pending == terminal || (!terminal && prompt.Kind != "acknowledge") {
				t.Fatalf("prompt disagrees with the post-pass snapshot: %+v", prompt)
			}
			if terminal {
				if r.Game == nil || r.Game.Result == nil || r.Game.Result.WinnerSeat != 1 || r.Score[1] != 1 || runtime.ended != 1 {
					t.Fatalf("delegated completion was not committed: game=%+v score=%v ended=%d", r.Game, r.Score, runtime.ended)
				}
				if _, active := h.forgeGame(r.ID); active {
					t.Fatal("completed delegated pass retained an active engine")
				}
			} else if r.Game != nil || runtime.ended != 0 {
				t.Fatal("nonterminal delegated pass completed the room")
			}
			for len(host.Send) > 0 {
				env, err := protocol.ParseEnvelope(<-host.Send)
				if err != nil {
					t.Fatal(err)
				}
				if env.Type == protocol.TypeRulesSnapshot {
					var sent protocol.RulesGameSnapshot
					if env.DecodePayload(&sent) != nil || sent.Turn != 2 || sent.GameOver != terminal {
						t.Fatal("hub delivery differed from the responding peer's post-pass snapshot")
					}
				}
			}
		})
	}
}

func TestRulesPromptProjectionDoesNotAdvanceSnapshotPosition(t *testing.T) {
	h, r, host, _, prior := modelTestRoom(t)
	runtime := &priorityPublicationRuntime{modelTestRuntime: prior}
	game := h.forgeGames[r.ID]
	game.client = runtime
	h.forgeGames[r.ID] = game
	h.setPriorityPreference(r.ID, 0, priorityPreference{})
	entry, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		t.Fatal(err)
	}
	defer entry.opMu.Unlock()
	projections, err := h.rulesProjections(r)
	if err != nil {
		t.Fatal(err)
	}
	prompts, err := h.rulesPrompts(r)
	if err != nil {
		t.Fatal(err)
	}
	h.fanoutRulesTable(r)
	var snapshot protocol.RulesGameSnapshot
	var prompt protocol.RulesPrompt
	if projections[host.ConnectionID].DecodePayload(&snapshot) != nil ||
		prompts[host.ConnectionID].DecodePayload(&prompt) != nil {
		t.Fatal("invalid rules projection")
	}
	if runtime.submitted != 0 || snapshot.Turn != 1 || !prompt.Pending || prompt.Kind != "chooseAction" {
		t.Fatalf("read-only publication advanced the engine: passes=%d snapshot=%+v prompt=%+v", runtime.submitted, snapshot, prompt)
	}
}

func TestForgePublicationAlreadyTerminalDoesNotRequestPrompt(t *testing.T) {
	h, r, _, _, prior := modelTestRoom(t)
	prior.submitted = 1
	runtime := &priorityPublicationRuntime{modelTestRuntime: prior, terminal: true}
	game := h.forgeGames[r.ID]
	game.client = runtime
	h.forgeGames[r.ID] = game
	entry, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		t.Fatal(err)
	}
	defer entry.opMu.Unlock()
	state, err := h.prepareForgePublication(r, game, false)
	if err != nil || !state.gameOver || runtime.prompts != 0 || runtime.ended != 1 {
		t.Fatalf("terminal publication requested an expired prompt: state=%+v promptCalls=%d ended=%d err=%v",
			state, runtime.prompts, runtime.ended, err)
	}
}

func TestRulesPriorityPreferenceDoesNotConsumeCurrentPrompt(t *testing.T) {
	h, r, host, _, prior := modelTestRoom(t)
	runtime := &priorityPublicationRuntime{modelTestRuntime: prior}
	game := h.forgeGames[r.ID]
	game.client = runtime
	h.forgeGames[r.ID] = game
	h.setPriorityPreference(r.ID, 0, priorityPreference{fullControl: true})
	env, err := protocol.NewEnvelope(protocol.TypeRulesPriority, protocol.RulesPriority{
		RoomID: r.ID, Stops: []string{},
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := h.handleRulesPriority(host, env); err != nil {
		t.Fatal(err)
	}
	prefs, known := h.priorityPreferenceFor(r.ID, 0)
	if !known || prefs.fullControl || runtime.submitted != 0 || runtime.prompts != 0 {
		t.Fatalf("preference update consumed the decision before its explicit response: prefs=%+v passes=%d promptCalls=%d",
			prefs, runtime.submitted, runtime.prompts)
	}
}
