// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"hexproof/server/internal/forgehost"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
	"hexproof/server/internal/rulesinput"
	"time"
)

const modelDecisionTimeout = 5 * time.Minute

// scheduleModelDecision captures only the AI seat's permitted observation at
// a stable input boundary. The caller holds opMu; inference happens remotely.
func (h *Handler) scheduleModelDecision(r *room.Room, game forgeRoomGame, view *forge.PromptView) {
	if !protocol.IsModelAISource(r.AISource) {
		return
	}
	if view == nil || game.playerToSeat[view.PlayerIndex] != 1 {
		h.pauseModelWorker(r.ID, "", false)
		return
	}
	h.modelMu.Lock()
	worker := h.modelWorkers[r.ID]
	if worker == nil || worker.connection == nil || worker.pending != nil || worker.state == "paused" {
		h.modelMu.Unlock()
		return
	}
	connection := worker.connection
	h.modelMu.Unlock()
	if !view.Supported {
		h.pauseModelWorker(r.ID, "unsupported_prompt", false)
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), runtimeTimeout(game.client, forgeSnapshotTimeout))
	snapshot, err := game.client.SnapshotView(ctx, game.sessionID, view.PlayerIndex)
	cancel()
	if err != nil {
		h.pauseModelWorker(r.ID, "engine_unavailable", false)
		return
	}
	projection, err := normalizeForgeSnapshot(r.ID, game, snapshot)
	if err != nil {
		h.pauseModelWorker(r.ID, "engine_unavailable", false)
		return
	}
	prompt, err := projectedRulesPrompt(r.ID, game.gameID, *view, game, &snapshot)
	if err != nil {
		h.pauseModelWorker(r.ID, "unsupported_prompt", false)
		return
	}
	prompt.PromptID, err = h.publicForgePromptID(game, view.PromptID)
	if err != nil {
		h.pauseModelWorker(r.ID, "engine_unavailable", false)
		return
	}
	request := &modelRequest{id: forgehost.NewID(), game: game, player: view.PlayerIndex, enginePromptID: view.PromptID, publicPromptID: prompt.PromptID}
	h.modelMu.Lock()
	if h.modelWorkers[r.ID] != worker || worker.connection != connection || worker.pending != nil || worker.state == "paused" {
		h.modelMu.Unlock()
		return
	}
	worker.pending, worker.state, worker.code = request, "thinking", ""
	request.timer = time.AfterFunc(modelDecisionTimeout, func() { h.expireModelDecision(r.ID, request) })
	h.modelMu.Unlock()
	h.sendModel(connection, protocol.TypeAIDecision, protocol.AIDecision{RequestID: request.id, GameID: game.gameID, SeatIndex: 1, Prompt: prompt, Snapshot: projection})
	h.publishModelStatus(r)
}

func (h *Handler) refreshModelDecision(r *room.Room) {
	game, exists := h.forgeGame(r.ID)
	if !exists {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), runtimeTimeout(game.client, forgePromptTimeout))
	view, err := currentRulesPrompt(ctx, game)
	cancel()
	if err != nil {
		h.pauseModelWorker(r.ID, "engine_unavailable", false)
		return
	}
	h.scheduleModelDecision(r, game, view)
}

func (h *Handler) expireModelDecision(roomID string, expected *modelRequest) {
	operation, err := h.hub.lockRoomOperation(roomID)
	if err != nil {
		return
	}
	defer operation.opMu.Unlock()
	h.modelMu.Lock()
	worker := h.modelWorkers[roomID]
	current := worker != nil && worker.pending == expected
	h.modelMu.Unlock()
	if current {
		h.pauseModelWorker(roomID, "timeout", false)
	}
}

func (h *Handler) handleModelRetry(sess *Session, env protocol.Envelope) error {
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	operation, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		return nil
	}
	defer operation.opMu.Unlock()
	if !r.IsHost(sess.ConnectionID) {
		h.sendError(sess, env.ID, protocol.ErrNotHost, "host only")
		return nil
	}
	if !protocol.IsModelAISource(r.AISource) {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, "no model opponent")
		return nil
	}
	h.pauseModelWorker(r.ID, "", false)
	h.modelMu.Lock()
	worker := h.modelWorkers[r.ID]
	connected := worker != nil && worker.connection != nil
	h.modelMu.Unlock()
	if !connected {
		h.grantModelWorker(sess, r)
	} else {
		h.refreshModelDecision(r)
	}
	h.modelMu.Lock()
	worker = h.modelWorkers[r.ID]
	status := protocol.RoomAIStatus{RoomID: r.ID, State: "waiting"}
	if worker != nil {
		status.State, status.Code = worker.state, worker.code
	}
	h.modelMu.Unlock()
	reply, _ := protocol.NewEnvelope(protocol.TypeRoomAIStatus, status)
	reply.ID = env.ID
	h.send(sess, reply)
	return nil
}

func (h *Handler) handleModelFailure(roomID string, sess *Session, failure protocol.AIFailure) {
	operation, err := h.hub.lockRoomOperation(roomID)
	if err != nil {
		return
	}
	defer operation.opMu.Unlock()
	h.modelMu.Lock()
	worker := h.modelWorkers[roomID]
	current := worker != nil && worker.connection == sess && worker.pending != nil && worker.pending.id == failure.RequestID
	h.modelMu.Unlock()
	if !current {
		return
	}
	code := failure.Code
	switch code {
	case "timeout", "provider_error", "invalid_response", "budget_exhausted", "unsupported_prompt":
	default:
		code = "provider_error"
	}
	h.pauseModelWorker(roomID, code, false)
}

func (h *Handler) rejectModelAnswer(roomID string, sess *Session, request *modelRequest) {
	h.modelMu.Lock()
	worker := h.modelWorkers[roomID]
	current := worker != nil && worker.connection == sess && worker.pending == request
	if current {
		request.rejections++
	}
	stop := current && request.rejections > 1
	h.modelMu.Unlock()
	if !current {
		return
	}
	if stop {
		h.pauseModelWorker(roomID, "invalid_response", false)
		return
	}
	h.sendModel(sess, protocol.TypeAIRejected, protocol.AIRejected{RequestID: request.id, Code: "invalid_response"})
}

func (h *Handler) handleModelAnswer(roomID string, sess *Session, answer protocol.AIAnswer) {
	operation, err := h.hub.lockRoomOperation(roomID)
	if err != nil {
		return
	}
	defer operation.opMu.Unlock()
	r := operation.room
	h.modelMu.Lock()
	worker := h.modelWorkers[roomID]
	var request *modelRequest
	if worker != nil && worker.connection == sess && worker.pending != nil && worker.pending.id == answer.RequestID {
		request = worker.pending
	}
	h.modelMu.Unlock()
	if request == nil {
		return
	}
	game, exists := h.forgeGame(roomID)
	if !exists || game.client != request.game.client || game.sessionID != request.game.sessionID || game.gameID != request.game.gameID || !protocol.IsModelAISource(r.AISource) || r.Phase != protocol.RoomPhaseStarted || r.Disbanded {
		h.pauseModelWorker(roomID, "", false)
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), runtimeTimeout(game.client, forgePromptTimeout))
	raw, err := game.client.Prompt(ctx, game.sessionID, request.player)
	cancel()
	if err != nil {
		h.pauseModelWorker(roomID, "engine_unavailable", false)
		return
	}
	view, err := forge.NormalizePrompt(raw)
	if err != nil || view.PromptID != request.enginePromptID || view.PlayerIndex != request.player || !game.promptState.matches(request.publicPromptID, view.PromptID) {
		h.pauseModelWorker(roomID, "", false)
		h.refreshModelDecision(r)
		return
	}
	if answer.Response.PeerBinding != "" || answer.Response.PromptID != request.publicPromptID {
		h.rejectModelAnswer(roomID, sess, request)
		return
	}
	response, err := rulesinput.Build(answer.Response, raw, request.player)
	if err != nil {
		h.rejectModelAnswer(roomID, sess, request)
		return
	}
	ctx, cancel = context.WithTimeout(context.Background(), runtimeTimeout(game.client, forgePromptTimeout))
	err = game.client.SubmitAction(ctx, game.sessionID, response)
	cancel()
	if err != nil {
		if !game.client.Healthy() {
			h.failForgeGame(r)
		} else {
			h.rejectModelAnswer(roomID, sess, request)
		}
		return
	}
	h.modelMu.Lock()
	if h.modelWorkers[roomID] == worker && worker.pending == request {
		request.timer.Stop()
		worker.pending, worker.state, worker.code = nil, "waiting", ""
	}
	h.modelMu.Unlock()
	h.sendModel(sess, protocol.TypeAICancel, protocol.AICancel{RequestID: request.id})
	if err := waitForForgePromptChange(game, view.PromptID); err != nil {
		h.failClosedGameProjections(r, err)
		return
	}
	h.publishRulesDecision(r, game, "", "", answer.Response, false)
}
