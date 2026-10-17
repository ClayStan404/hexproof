// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
)

// The native boundary changes from a self-owned draw trigger to a fresh
// empty-stack end-step decision, and only then to mandatory cleanup discards.
type endStepPriorityRuntime struct {
	*modelTestRuntime
	stage             int
	afterDrawEligible bool
}

func (f *endStepPriorityRuntime) Prompt(context.Context, string, int) (json.RawMessage, error) {
	input := map[string]any{"type": "chooseAction", "actions": []any{}, "autoPassEligible": true}
	if f.stage == 1 {
		input["autoPassEligible"] = f.afterDrawEligible
		if !f.afterDrawEligible {
			input["actions"] = []any{map[string]any{
				"id": "native-drawn-action", "type": "cast", "cardId": "drawn-1", "label": "Cast fresh instant",
			}}
		}
	} else if f.stage == 2 {
		input = map[string]any{"type": "chooseCards", "min": 2, "max": 2,
			"cards": []any{
				map[string]any{"id": "private-0", "identity": map[string]any{"name": "Private Alice"}},
				map[string]any{"id": "drawn-1", "identity": map[string]any{"name": "Fresh instant"}},
			}, "presentation": map[string]any{"title": "Discard to maximum hand size"}}
	}
	return json.Marshal(map[string]any{"promptId": f.stage + 1, "decidingPlayerId": "player-0", "input": input})
}

func (f *endStepPriorityRuntime) SubmitAction(_ context.Context, _ string, raw json.RawMessage) error {
	var response struct {
		Type   string `json:"type"`
		Output struct {
			Type         string `json:"type"`
			ExhaustStack bool   `json:"exhaustStack"`
		} `json:"output"`
	}
	if err := json.Unmarshal(raw, &response); err != nil {
		return err
	}
	if response.Type != "chooseAction" || response.Output.Type != "pass" || response.Output.ExhaustStack ||
		f.stage > 1 || (f.stage == 1 && !f.afterDrawEligible) {
		return fmt.Errorf("unexpected delegated input at stage %d: %s", f.stage, raw)
	}
	f.stage++
	f.submitted++
	return nil
}

func (f *endStepPriorityRuntime) SnapshotView(_ context.Context, _ string, viewer int) (forge.GameView, error) {
	raw, _ := json.Marshal(forgeLifecycleSnapshot(f.gameID, viewer, -1))
	view, err := forge.DecodeSnapshotView(raw)
	view.Step = "endOfTurn"
	if f.stage == 0 {
		view.Stack = []forge.StackObjectView{{ID: "draw-trigger", SourceID: "necrodominance",
			ControllerID: "player-0", OwnerID: "player-0",
			Identity: forge.CardIdentityView{Name: "Necrodominance"}, Text: "Draw cards"}}
	} else {
		view.Zones[0].Count = 7
		if viewer == 0 {
			for i := 1; i <= 6; i++ {
				view.Zones[0].Cards = append(view.Zones[0].Cards, forge.CardView{
					Visibility: "visible", ID: fmt.Sprintf("drawn-%d", i),
					Identity: &forge.CardIdentityView{Name: "Fresh instant"},
					OwnerID:  "player-0", ControllerID: "player-0",
				})
			}
		}
	}
	if f.stage == 2 {
		view.Step = "cleanup"
	}
	return view, err
}

func TestDelegatedPriorityRetainsFreshEndStepAction(t *testing.T) {
	h, r, host, _, prior := modelTestRoom(t)
	spectator := &Session{ConnectionID: "end-step-observer", Send: make(chan []byte, 16)}
	entry, err := h.hub.beginJoin(r.ID, "")
	if err != nil {
		t.Fatal(err)
	}
	_, _, err = h.hub.joinRoom(entry, spectator, true)
	entry.opMu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	runtime := &endStepPriorityRuntime{modelTestRuntime: prior}
	game := h.forgeGames[r.ID]
	game.client = runtime
	h.forgeGames[r.ID] = game
	h.setPriorityPreference(r.ID, 0, priorityPreference{})
	entry, err = h.hub.lockRoomOperation(r.ID)
	if err != nil {
		t.Fatal(err)
	}
	defer entry.opMu.Unlock()
	state, err := h.prepareForgePublication(r, game, false)
	if err != nil {
		t.Fatal(err)
	}
	var snapshot protocol.RulesGameSnapshot
	var prompt protocol.RulesPrompt
	if state.projections[host.ConnectionID].DecodePayload(&snapshot) != nil ||
		state.prompts[host.ConnectionID].DecodePayload(&prompt) != nil {
		t.Fatal("invalid end-step publication")
	}
	if runtime.submitted != 1 || snapshot.Step != protocol.GamePhaseEnd || len(snapshot.Stack) != 0 ||
		snapshot.Zones[0].Count != 7 || len(snapshot.Zones[0].Cards) != 7 ||
		!prompt.Pending || prompt.Kind != "chooseAction" || prompt.AutoPassEligible ||
		len(prompt.Options) != 3 || prompt.Options[0].CardID != "drawn-1" || prompt.Options[0].ResponseID != "action:0" {
		t.Fatalf("fresh end-step action was skipped or published with stale state: passes=%d snapshot=%+v prompt=%+v",
			runtime.submitted, snapshot, prompt)
	}
	if _, exposed := state.prompts[spectator.ConnectionID]; exposed {
		t.Fatal("spectator received a private decision")
	}
	public := state.projections[spectator.ConnectionID]
	var publicSnapshot protocol.RulesGameSnapshot
	if public.DecodePayload(&publicSnapshot) != nil || publicSnapshot.Step != protocol.GamePhaseEnd ||
		publicSnapshot.Zones[0].Count != 7 || len(publicSnapshot.Zones[0].Cards) != 0 {
		t.Fatal("spectator publication omitted or exposed the freshly drawn hand")
	}
	if strings.Contains(string(public.Payload), "Fresh instant") || strings.Contains(string(public.Payload), "drawn-") {
		t.Fatal("freshly drawn card identities leaked to the spectator")
	}
}

func TestEndStepPriorityPublicationRespectsHintAndPreferences(t *testing.T) {
	for _, test := range []struct {
		name   string
		prefs  priorityPreference
		passes int
	}{
		{"eligible", priorityPreference{}, 1},
		{"full control", priorityPreference{fullControl: true}, 0},
		{"held response", priorityPreference{hold: true}, 0},
		{"own end stop", priorityPreference{stops: map[string]bool{"own:" + protocol.GamePhaseEnd: true}}, 0},
	} {
		t.Run(test.name, func(t *testing.T) {
			h, r, host, _, prior := modelTestRoom(t)
			runtime := &endStepPriorityRuntime{modelTestRuntime: prior, stage: 1, afterDrawEligible: true}
			game := h.forgeGames[r.ID]
			game.client = runtime
			h.forgeGames[r.ID] = game
			h.setPriorityPreference(r.ID, 0, test.prefs)
			entry, err := h.hub.lockRoomOperation(r.ID)
			if err != nil {
				t.Fatal(err)
			}
			defer entry.opMu.Unlock()
			state, err := h.prepareForgePublication(r, game, false)
			if err != nil {
				t.Fatal(err)
			}
			var snapshot protocol.RulesGameSnapshot
			var prompt protocol.RulesPrompt
			if state.projections[host.ConnectionID].DecodePayload(&snapshot) != nil ||
				state.prompts[host.ConnectionID].DecodePayload(&prompt) != nil {
				t.Fatal("invalid priority publication")
			}
			if runtime.submitted != test.passes || !prompt.Pending {
				t.Fatalf("passes=%d, want=%d, prompt=%+v", runtime.submitted, test.passes, prompt)
			}
			if test.passes == 1 {
				if snapshot.Step != "cleanup" || prompt.Kind != "chooseCards" || prompt.CardMinimum != 2 || prompt.AutoPassEligible {
					t.Fatalf("eligible priority did not stop at the required discard: snapshot=%+v prompt=%+v", snapshot, prompt)
				}
			} else if snapshot.Step != protocol.GamePhaseEnd || prompt.Kind != "chooseAction" || !prompt.AutoPassEligible {
				t.Fatalf("priority preference was ignored: snapshot=%+v prompt=%+v", snapshot, prompt)
			}
		})
	}
}
