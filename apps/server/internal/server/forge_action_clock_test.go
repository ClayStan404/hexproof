// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

type clockResponseRuntime struct {
	*modelTestRuntime
	onSubmit func()
	reject   bool
}

func (f *clockResponseRuntime) SubmitAction(ctx context.Context, session string, response json.RawMessage) error {
	if f.onSubmit != nil {
		f.onSubmit()
	}
	if f.reject {
		return errors.New("rejected")
	}
	return f.modelTestRuntime.SubmitAction(ctx, session, response)
}

func enableRuntimeClock(t *testing.T, h *Handler, r *room.Room) {
	t.Helper()
	operation, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		t.Fatal(err)
	}
	defer operation.opMu.Unlock()
	r.EnableActionClock(time.Now())
	h.refreshModelDecision(r)
}

func assertRuntimeClockSeat(t *testing.T, r *room.Room, expected int) {
	t.Helper()
	running := r.Snapshot().ActionClockRunning
	if expected < 0 && running == nil {
		return
	}
	if running == nil || *running != expected {
		t.Fatalf("clock owner=%v, expected seat %d", running, expected)
	}
}

func TestForgeActionClockUsesDecidingPlayerInsteadOfPriority(t *testing.T) {
	h, r, _, _, _ := modelTestRoom(t)
	operation, _ := h.hub.lockRoomOperation(r.ID)
	defer operation.opMu.Unlock()
	r.EnableActionClock(time.Now())
	game, _ := h.forgeGame(r.ID)
	state, err := h.prepareForgePublication(r, game, false)
	if err != nil {
		t.Fatal(err)
	}
	var snapshot protocol.RulesGameSnapshot
	for _, env := range state.projections {
		if env.DecodePayload(&snapshot) != nil {
			t.Fatal("invalid rules snapshot")
		}
	}
	if snapshot.PrioritySeat != 0 {
		t.Fatal("fixture must give priority to the human")
	}
	assertRuntimeClockSeat(t, r, 1)
}

func TestForgeActionClockTerminalPublicationDoesNotRequestExpiredPrompt(t *testing.T) {
	h, r, _, _, prior := modelTestRoom(t)
	operation, _ := h.hub.lockRoomOperation(r.ID)
	defer operation.opMu.Unlock()
	r.EnableActionClock(time.Now())
	prior.submitted = 1
	runtime := &priorityPublicationRuntime{modelTestRuntime: prior, terminal: true}
	game := h.forgeGames[r.ID]
	game.client = runtime
	h.forgeGames[r.ID] = game
	state, err := h.prepareForgePublication(r, game, false)
	if err != nil || !state.gameOver || runtime.prompts != 0 || runtime.ended != 1 {
		t.Fatalf("terminal clock publication requested an expired prompt: calls=%d ended=%d err=%v", runtime.prompts, runtime.ended, err)
	}
	assertRuntimeClockSeat(t, r, -1)
	for _, remaining := range r.Snapshot().ActionClockMs {
		if remaining != room.ActionClockDuration.Milliseconds() {
			t.Fatal("engine completion spent player decision time")
		}
	}
}

func TestModelActionClockPausesOnFailureAndResumesOnRetry(t *testing.T) {
	h, r, host, worker, _ := modelTestRoom(t)
	decision := modelDecision(t, worker)
	enableRuntimeClock(t, h, r)
	assertRuntimeClockSeat(t, r, 1)
	h.handleModelFailure(r.ID, worker, protocol.AIFailure{RequestID: decision.RequestID, Code: "provider_error"})
	assertRuntimeClockSeat(t, r, -1)
	remaining := r.Snapshot().ActionClockMs
	operation, _ := h.hub.lockRoomOperation(r.ID)
	h.refreshForgeActionClock(r)
	operation.opMu.Unlock()
	assertRuntimeClockSeat(t, r, -1)
	if actual := r.Snapshot().ActionClockMs; actual[0] != remaining[0] || actual[1] != remaining[1] {
		t.Fatal("failed model refresh spent paused time")
	}
	retry, _ := protocol.NewEnvelope(protocol.TypeRoomAIRetry, protocol.RoomAIRetry{})
	if err := h.handleModelRetry(host, retry); err != nil {
		t.Fatal(err)
	}
	assertRuntimeClockSeat(t, r, 1)
	if next := modelDecision(t, worker); next.RequestID == decision.RequestID {
		t.Fatal("retry retained revoked model work")
	}
}

func TestAcceptedForgeAnswersPauseDuringEngineSubmission(t *testing.T) {
	for _, model := range []bool{false, true} {
		name := "human"
		if model {
			name = "model"
		}
		t.Run(name, func(t *testing.T) {
			h, r, host, worker, prior := modelTestRoom(t)
			decision := modelDecision(t, worker)
			runtime := &clockResponseRuntime{modelTestRuntime: prior}
			operation, _ := h.hub.lockRoomOperation(r.ID)
			game := h.forgeGames[r.ID]
			game.client = runtime
			h.forgeGames[r.ID] = game
			if model {
				h.modelWorkers[r.ID].pending.game = game
			} else {
				prior.submitted, prior.serial = 1, 2
				h.pauseModelWorker(r.ID, "", false)
			}
			r.EnableActionClock(time.Now())
			h.refreshModelDecision(r)
			var prompt protocol.RulesPrompt
			if !model {
				prompts, err := h.rulesPrompts(r)
				if err != nil || prompts[host.ConnectionID].DecodePayload(&prompt) != nil || !prompt.Pending {
					t.Fatal("missing human decision")
				}
			}
			operation.opMu.Unlock()
			submitted := false
			runtime.onSubmit = func() {
				submitted = true
				assertRuntimeClockSeat(t, r, -1)
			}
			if model {
				h.handleModelAnswer(r.ID, worker, protocol.AIAnswer{RequestID: decision.RequestID,
					Response: protocol.RulesRespond{PromptID: decision.Prompt.PromptID, ResponseID: "$ack"}})
			} else {
				answer, _ := protocol.NewEnvelope(protocol.TypeRulesRespond,
					protocol.RulesRespond{PromptID: prompt.PromptID, ResponseID: "$ack"})
				if err := h.handleRulesRespond(host, answer); err != nil {
					t.Fatal(err)
				}
			}
			if !submitted {
				t.Fatal("valid answer did not reach the engine")
			}
			assertRuntimeClockSeat(t, r, 0)
		})
	}
}

func TestRejectedForgeSubmissionResumesCurrentDecisionClock(t *testing.T) {
	h, r, host, _, prior := modelTestRoom(t)
	operation, _ := h.hub.lockRoomOperation(r.ID)
	prior.submitted, prior.serial = 1, 2
	runtime := &clockResponseRuntime{modelTestRuntime: prior, reject: true}
	game := h.forgeGames[r.ID]
	game.client = runtime
	h.forgeGames[r.ID] = game
	h.pauseModelWorker(r.ID, "", false)
	r.EnableActionClock(time.Now())
	h.refreshModelDecision(r)
	prompts, err := h.rulesPrompts(r)
	var prompt protocol.RulesPrompt
	if err != nil || prompts[host.ConnectionID].DecodePayload(&prompt) != nil {
		t.Fatal("missing decision")
	}
	operation.opMu.Unlock()
	answer, _ := protocol.NewEnvelope(protocol.TypeRulesRespond,
		protocol.RulesRespond{PromptID: prompt.PromptID, ResponseID: "$ack"})
	if err := h.handleRulesRespond(host, answer); err != nil {
		t.Fatal(err)
	}
	assertRuntimeClockSeat(t, r, 0)
	if prior.submitted != 1 {
		t.Fatal("rejected answer advanced the game")
	}
}

func TestForgeActionClockPausesForUnavailablePlayerHost(t *testing.T) {
	h, r, _, _, _ := modelTestRoom(t)
	operation, _ := h.hub.lockRoomOperation(r.ID)
	defer operation.opMu.Unlock()
	r.EnableActionClock(time.Now())
	h.refreshModelDecision(r)
	assertRuntimeClockSeat(t, r, 1)
	r.HostingMode = protocol.HostingModePlayer
	h.refreshPlayerHostStatus(r)
	assertRuntimeClockSeat(t, r, -1)
	if !h.actionClockInputPaused(r) {
		t.Fatal("unavailable host did not block timer/projection restart")
	}
}

func TestPlayerHostStateFreezesClockBeforeRoomOperationUnlock(t *testing.T) {
	h, r, _, _, _ := modelTestRoom(t)
	operation, _ := h.hub.lockRoomOperation(r.ID)
	defer operation.opMu.Unlock()
	started := time.Now().Add(-2 * time.Second)
	r.EnableActionClock(started)
	r.AdvanceActionClock(started, 0)
	previousSeq := r.ActionClockSeq()
	r.HostingMode = protocol.HostingModePlayer
	// State delivery does not wait for the already-owned operation lock.
	h.sendPlayerHostState(r)
	assertRuntimeClockSeat(t, r, -1)
	if r.ActionClockSeq() == previousSeq {
		t.Fatal("outage did not invalidate the previous timeout")
	}
	remaining := r.Snapshot().ActionClockMs
	if remaining[0] >= room.ActionClockDuration.Milliseconds()-1900 || remaining[1] != room.ActionClockDuration.Milliseconds() {
		t.Fatalf("outage charged the wrong budget: %v", remaining)
	}
	h.sendPlayerHostState(r)
	if actual := r.Snapshot().ActionClockMs; actual[0] != remaining[0] || actual[1] != remaining[1] {
		t.Fatal("repeated disconnected status charged paused time")
	}
}

func TestStaleForgeFinishDoesNotPauseCurrentClock(t *testing.T) {
	h, r, _, _, _ := modelTestRoom(t)
	operation, _ := h.hub.lockRoomOperation(r.ID)
	defer operation.opMu.Unlock()
	r.EnableActionClock(time.Now())
	h.refreshModelDecision(r)
	game := h.forgeGames[r.ID]
	stale := game
	stale.sessionID = "old-session"
	h.finishForgeGame(r.ID, stale, false)
	assertRuntimeClockSeat(t, r, 1)
	if h.modelWorkers[r.ID].state != "thinking" {
		t.Fatal("stale completion canceled current model inference")
	}
	h.closeForgeGame(r.ID, true)
	assertRuntimeClockSeat(t, r, -1)
	if !r.ActionClockEnabled || r.Snapshot().ActionClockMs[1] > room.ActionClockDuration.Milliseconds() {
		t.Fatal("closing a game changed its configured match budget")
	}
}

func TestForgeRestartAdjudicatesQueuedClockExpiryBeforeReset(t *testing.T) {
	h, r := timedTestRoom(t, -time.Second)
	operation, _ := h.hub.lockRoomOperation(r.ID)
	operation.mu.Lock()
	startingSeat := 0
	r.RulesStartingSeat = &startingSeat
	loadID := r.LoadID
	hostID := r.Seats[0].ConnectionID
	operation.mu.Unlock()
	operation.opMu.Unlock()
	host := h.sessionByConn(hostID)
	restart, _ := protocol.NewEnvelope(protocol.TypeGameRestart, protocol.GameRestart{})
	restart.ID = "restart-after-deadline"
	if err := h.handleForgeRestart(host, restart, r); err != nil {
		t.Fatal(err)
	}
	operation.mu.Lock()
	if r.Phase != protocol.RoomPhaseStarted || r.LoadID != loadID || r.Game == nil || r.Game.Result == nil ||
		!r.Game.Result.MatchFinished || r.Game.Result.Reason != protocol.GameResultTimeout || r.Game.Result.WinnerSeat != 1 {
		t.Fatalf("restart erased the expired match: phase=%s load=%d result=%+v", r.Phase, r.LoadID, r.Game)
	}
	operation.mu.Unlock()
	foundError := false
	for len(host.Send) > 0 {
		env, err := protocol.ParseEnvelope(<-host.Send)
		if err != nil || env.Type == protocol.TypeGameRestarted {
			t.Fatal("expired match published restart success")
		}
		if env.Type == protocol.TypeError && env.ID == restart.ID {
			var failure protocol.ErrorPayload
			if env.DecodePayload(&failure) != nil || failure.Code != protocol.ErrGameFinished {
				t.Fatal("expired restart did not report the completed match")
			}
			foundError = true
		}
	}
	if !foundError {
		t.Fatal("expired restart left the command unresolved")
	}
}

func TestInvalidForgeRestartDoesNotPauseClock(t *testing.T) {
	for _, actor := range []int{0, 1} {
		t.Run([]string{"missing-starting-seat", "not-host"}[actor], func(t *testing.T) {
			h, r := timedTestRoom(t, time.Minute)
			operation := h.hub.roomEntryFor(r.ID)
			operation.mu.Lock()
			if actor == 1 {
				startingSeat := 0
				r.RulesStartingSeat = &startingSeat
			}
			previousSeq := r.ActionClockSeq()
			actorID := r.Seats[actor].ConnectionID
			operation.mu.Unlock()
			restart, _ := protocol.NewEnvelope(protocol.TypeGameRestart, protocol.GameRestart{})
			if err := h.handleForgeRestart(h.sessionByConn(actorID), restart, r); err != nil {
				t.Fatal(err)
			}
			operation.mu.Lock()
			defer operation.mu.Unlock()
			assertRuntimeClockSeat(t, r, 0)
			if r.ActionClockSeq() != previousSeq || r.Game != nil {
				t.Fatal("invalid restart modified the action clock")
			}
		})
	}
}
