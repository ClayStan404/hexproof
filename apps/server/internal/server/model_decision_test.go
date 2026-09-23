// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"encoding/json"
	"fmt"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
	"strings"
	"testing"
)

type modelTestRuntime struct {
	forge.Runtime
	gameID    string
	serial    int64
	submitted int
}

func (f *modelTestRuntime) Prompt(context.Context, string, int) (json.RawMessage, error) {
	player := 1
	if f.submitted > 0 {
		player = 0
	}
	return json.RawMessage(fmt.Sprintf(`{"promptId":%d,"decidingPlayerId":"player-%d","input":{"type":"acknowledge","presentation":{"title":"Secret model decision"}}}`, f.serial, player)), nil
}
func (f *modelTestRuntime) SnapshotView(_ context.Context, _ string, viewer int) (forge.GameView, error) {
	raw, _ := json.Marshal(forgeLifecycleSnapshot(f.gameID, viewer, -1))
	view, err := forge.DecodeSnapshotView(raw)
	view.IntegrityHash = "must-not-reach-model"
	return view, err
}
func (f *modelTestRuntime) SubmitAction(context.Context, string, json.RawMessage) error {
	f.submitted++
	f.serial++
	return nil
}
func (f *modelTestRuntime) GameOver(context.Context, string) (bool, error) { return false, nil }
func (f *modelTestRuntime) AbortGame(context.Context, string) error        { return nil }
func (f *modelTestRuntime) Close() error                                   { return nil }
func (f *modelTestRuntime) Healthy() bool                                  { return true }

func modelTestRoom(t *testing.T) (*Handler, *room.Room, *Session, *Session, *modelTestRuntime) {
	t.Helper()
	h := NewHandler()
	t.Cleanup(func() { h.Close() })
	host := &Session{ConnectionID: "host", DisplayName: "Human", Send: make(chan []byte, 128)}
	h.registerSession(host)
	r, _, _, entry, err := h.hub.createRoom("Model", protocol.FormatModern, protocol.DeckFormatCustom, protocol.MatchBO1, protocol.CardLoadBackground, protocol.RulesModeForge, "server", 2, true, false, "", "", "", "", host, "", protocol.AISourceLocal)
	if err != nil {
		t.Fatal(err)
	}
	defer entry.opMu.Unlock()
	deck := modernTestDeck("Private deck")
	if _, err = r.ConfigureAI("host", protocol.RoomAIConfigure{Deck: &deck}); err != nil {
		t.Fatal(err)
	}
	if _, err = r.SelectDeck("host", deck); err != nil {
		t.Fatal(err)
	}
	if _, err = r.SetReady("host", true); err != nil {
		t.Fatal(err)
	}
	players, _ := r.RulesStartPlayers()
	native, _, err := forgeStartRequest(r, players)
	if err != nil || native.HasAI() || native.Players[1].AIDifficulty != "" {
		t.Fatalf("model used native AI: %+v %v", native, err)
	}
	runtime := &modelTestRuntime{gameID: native.GameID, serial: 1}
	game := forgeRoomGame{client: runtime, sessionID: "session", gameID: native.GameID, seatToPlayer: map[int]int{0: 0, 1: 1}, playerToSeat: map[int]int{0: 0, 1: 1}, promptState: &forgePromptState{}}
	h.forgeGames[r.ID] = game
	h.grantModelWorker(host, r)
	worker := &Session{Send: make(chan []byte, 64)}
	h.modelWorkers[r.ID].connection = worker
	h.refreshModelDecision(r)
	return h, r, host, worker, runtime
}

func nextModelEnvelope(t *testing.T, worker *Session, kind string) protocol.Envelope {
	t.Helper()
	for len(worker.Send) > 0 {
		env, err := protocol.ParseEnvelope(<-worker.Send)
		if err != nil {
			t.Fatal(err)
		}
		if env.Type == kind {
			return env
		}
	}
	t.Fatalf("missing %s", kind)
	return protocol.Envelope{}
}
func modelDecision(t *testing.T, worker *Session) protocol.AIDecision {
	t.Helper()
	var d protocol.AIDecision
	if err := nextModelEnvelope(t, worker, protocol.TypeAIDecision).DecodePayload(&d); err != nil {
		t.Fatal(err)
	}
	return d
}

func TestModelDecisionUsesOnlyAIViewAndPrivateRole(t *testing.T) {
	h, r, host, worker, _ := modelTestRoom(t)
	decision := modelDecision(t, worker)
	raw, _ := json.Marshal(decision)
	if !strings.Contains(string(raw), "Private Bob") || strings.Contains(string(raw), "Private Alice") || strings.Contains(string(raw), "must-not-reach-model") {
		t.Fatalf("wrong model observation: %s", raw)
	}
	if decision.SeatIndex != 1 || decision.Prompt.PromptID <= 0 {
		t.Fatal("missing binding")
	}
	for len(host.Send) > 0 {
		env, _ := protocol.ParseEnvelope(<-host.Send)
		if strings.Contains(string(env.Payload), "Private Bob") || env.Type == protocol.TypeAIDecision {
			t.Fatal("AI private state reached human channel")
		}
	}
	entry, _ := h.hub.lockRoomOperation(r.ID)
	prompts, err := h.rulesPrompts(r)
	entry.opMu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	var prompt protocol.RulesPrompt
	if err := prompts[host.ConnectionID].DecodePayload(&prompt); err != nil || prompt.Pending || prompt.Title != "" {
		t.Fatalf("human received AI prompt: %+v", prompt)
	}
	if len(worker.Send) != 0 {
		t.Fatal("duplicate publication launched duplicate inference")
	}
}

func TestModelAnswersValidateRetryAndRejectStaleWork(t *testing.T) {
	h, r, host, worker, runtime := modelTestRoom(t)
	d := modelDecision(t, worker)
	invalid := protocol.AIAnswer{RequestID: d.RequestID, Response: protocol.RulesRespond{PromptID: d.Prompt.PromptID, ResponseID: "forged"}}
	h.handleModelAnswer(r.ID, worker, invalid)
	nextModelEnvelope(t, worker, protocol.TypeAIRejected)
	if runtime.submitted != 0 {
		t.Fatal("invalid model response advanced engine")
	}
	h.handleModelFailure(r.ID, worker, protocol.AIFailure{RequestID: d.RequestID, Code: "private exception and token"})
	if h.modelWorkers[r.ID].code != "provider_error" {
		t.Fatal("provider error escaped controlled vocabulary")
	}
	retry, _ := protocol.NewEnvelope(protocol.TypeRoomAIRetry, protocol.RoomAIRetry{})
	retry.ID = "retry"
	if err := h.handleModelRetry(host, retry); err != nil {
		t.Fatal(err)
	}
	fresh := modelDecision(t, worker)
	if fresh.RequestID == d.RequestID || fresh.Prompt.PromptID != d.Prompt.PromptID {
		t.Fatal("retry did not revoke request while preserving decision")
	}
	old := protocol.AIAnswer{RequestID: d.RequestID, Response: protocol.RulesRespond{PromptID: d.Prompt.PromptID, ResponseID: "$ack"}}
	h.handleModelAnswer(r.ID, worker, old)
	if runtime.submitted != 0 {
		t.Fatal("old answer advanced engine")
	}
	valid := protocol.AIAnswer{RequestID: fresh.RequestID, Response: protocol.RulesRespond{PromptID: fresh.Prompt.PromptID, ResponseID: "$ack"}}
	stranger := &Session{Send: make(chan []byte, 1)}
	h.handleModelAnswer(r.ID, stranger, valid)
	if runtime.submitted != 0 {
		t.Fatal("foreign worker advanced engine")
	}
	h.handleModelAnswer(r.ID, worker, valid)
	h.handleModelAnswer(r.ID, worker, valid)
	if runtime.submitted != 1 {
		t.Fatalf("answer committed %d times", runtime.submitted)
	}
}

func TestModelTimeoutRestartAndDisconnectCancelPending(t *testing.T) {
	h, r, host, worker, runtime := modelTestRoom(t)
	d := modelDecision(t, worker)
	req := h.modelWorkers[r.ID].pending
	h.expireModelDecision(r.ID, req)
	if h.modelWorkers[r.ID].state != "paused" || h.modelWorkers[r.ID].code != "timeout" {
		t.Fatal("deadline did not pause model")
	}
	nextModelEnvelope(t, worker, protocol.TypeAICancel)
	h.handleModelAnswer(r.ID, worker, protocol.AIAnswer{RequestID: d.RequestID, Response: protocol.RulesRespond{PromptID: d.Prompt.PromptID, ResponseID: "$ack"}})
	if runtime.submitted != 0 {
		t.Fatal("deadline answer advanced engine")
	}
	entry, _ := h.hub.lockRoomOperation(r.ID)
	oldToken := h.modelWorkers[r.ID].token
	h.grantModelWorker(host, r)
	if h.modelWorkers[r.ID].token == oldToken || h.modelWorkers[r.ID].connection != nil {
		t.Fatal("grant replacement kept old worker")
	}
	h.abortForgeGame(r.ID)
	h.revokeModelWorker(r.ID)
	entry.opMu.Unlock()
	if _, ok := h.modelWorkers[r.ID]; ok {
		t.Fatal("deleted room retained model credentials")
	}
}

func TestModelRepairIsBoundedAndWorkerFailureCannotExposeDiagnostics(t *testing.T) {
	h, r, _, worker, runtime := modelTestRoom(t)
	d := modelDecision(t, worker)
	answer := protocol.AIAnswer{RequestID: d.RequestID, Response: protocol.RulesRespond{PromptID: d.Prompt.PromptID, ResponseID: "$ack", PeerBinding: strings.Repeat("a", 64)}}
	h.handleModelAnswer(r.ID, worker, answer)
	nextModelEnvelope(t, worker, protocol.TypeAIRejected)
	h.handleModelAnswer(r.ID, worker, answer)
	if h.modelWorkers[r.ID].state != "paused" || h.modelWorkers[r.ID].pending != nil || runtime.submitted != 0 {
		t.Fatal("invalid repair did not pause safely")
	}
	nextModelEnvelope(t, worker, protocol.TypeAICancel)
	// Revoking the room's token also invalidates late responses without a JVM call.
	entry, _ := h.hub.lockRoomOperation(r.ID)
	h.pauseModelWorker(r.ID, "worker_disconnected", true)
	entry.opMu.Unlock()
	if h.modelWorkers[r.ID].token != "" || h.modelWorkers[r.ID].connection != nil {
		t.Fatal("human disconnect retained active model capability")
	}
	answer.Response.PeerBinding = ""
	h.handleModelAnswer(r.ID, worker, answer)
	if runtime.submitted != 0 {
		t.Fatal("disconnected worker advanced engine")
	}
}
