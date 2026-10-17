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
)

func (h *Handler) handleRulesRespond(sess *Session, env protocol.Envelope) error {
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	var request protocol.RulesRespond
	if err := env.DecodePayload(&request); err != nil || !rulesinput.Valid(request) {
		message := "invalid rules response"
		if err != nil {
			message = err.Error()
		}
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, message)
		return nil
	}
	operation, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		code, _ := ErrCode(err)
		h.sendError(sess, env.ID, code, err.Error())
		return nil
	}
	defer operation.opMu.Unlock()
	defer h.refreshPlayerHostStatus(r)

	if h.replayPeerReceipt(r, sess, env.ID, request) {
		return nil
	}
	seat, err := h.hub.RulesActorSeat(r, sess.ConnectionID)
	if err != nil {
		code, _ := ErrCode(err)
		h.sendError(sess, env.ID, code, err.Error())
		return nil
	}
	if h.playerHostPaused(r) {
		h.sendError(sess, env.ID, protocol.ErrRulesActionRejected, "The host is reconnecting; the game is paused")
		return nil
	}
	game, ok := h.forgeGame(r.ID)
	if !ok {
		h.sendError(sess, env.ID, protocol.ErrRulesUnavailable,
			"Forge game session is unavailable")
		return nil
	}
	playerIndex, ok := game.seatToPlayer[seat]
	if !ok {
		h.sendError(sess, env.ID, protocol.ErrRulesUnavailable,
			"Forge player mapping is unavailable")
		return nil
	}

	ctx, cancel := context.WithTimeout(context.Background(), runtimeTimeout(game.client, forgePromptTimeout))
	rawPrompt, promptErr := game.client.Prompt(ctx, game.sessionID, playerIndex)
	cancel()
	if promptErr != nil {
		h.sendError(sess, env.ID, protocol.ErrRulesUnavailable,
			"Forge prompt is unavailable")
		return nil
	}
	promptView, err := forge.NormalizePrompt(rawPrompt)
	if err != nil || !game.promptState.matches(request.PromptID, promptView.PromptID) {
		h.sendError(sess, env.ID, protocol.ErrRulesActionRejected,
			"The Forge decision is stale or no longer available")
		return nil
	}
	if promptView.Kind == "chooseCombatDamageAssignment" {
		ctx, cancel = context.WithTimeout(context.Background(), runtimeTimeout(game.client, forgeSnapshotTimeout))
		snapshot, snapshotErr := game.client.SnapshotView(ctx, game.sessionID, playerIndex)
		cancel()
		if snapshotErr != nil {
			h.sendError(sess, env.ID, protocol.ErrRulesUnavailable,
				"Forge damage state is unavailable")
			return nil
		}
		_, damageTargets, projectionErr := projectedRulesDamage(promptView.DamageSource,
			promptView.DamageTargets, true, game, snapshot)
		if projectionErr != nil || !rulesinput.ValidDamageDistribution(
			damageTargets, promptView.TotalDamage, promptView.DamageAssignmentMode, request.DamageAssignments) {
			h.sendError(sess, env.ID, protocol.ErrRulesActionRejected,
				"The combat damage assignment is invalid")
			return nil
		}
	}
	response, err := rulesinput.Build(request, rawPrompt, playerIndex)
	if err != nil {
		h.sendError(sess, env.ID, protocol.ErrRulesActionRejected,
			"The selection does not satisfy this Forge decision")
		return nil
	}
	if !h.pauseActionClockLocked(r) {
		h.sendError(sess, env.ID, protocol.ErrGameFinished, "the action clock finished the match")
		return nil
	}
	ctx, cancel = context.WithTimeout(context.Background(), runtimeTimeout(game.client, forgePromptTimeout))
	game.diagnostics.action(promptView.Kind, game.playerToSeat[playerIndex], false)
	if remote, ok := game.client.(*forgehost.Runtime); ok {
		err = remote.SubmitPlayerAction(ctx, game.sessionID, response, request.PeerBinding, env.ID)
	} else {
		err = game.client.SubmitAction(ctx, game.sessionID, response)
	}
	cancel()
	if err != nil {
		if game.nativeAI && !game.client.Healthy() {
			h.failForgeGame(r)
		} else {
			h.reconcileForgeActionClock(r, game, &promptView)
		}
		h.sendError(sess, env.ID, protocol.ErrRulesActionRejected,
			"Forge rejected the decision")
		return nil
	}
	if err := waitForForgePromptChange(game, promptView.PromptID); err != nil {
		h.failClosedGameProjections(r, err)
		return nil
	}

	h.publishRulesDecision(r, game, sess.ConnectionID, env.ID, request, false, false)
	return nil
}

// Caller holds opMu. Both transports use the identical redaction and match
// lifecycle path; only delivery of the responding peer's envelopes differs.
// An adopted direct commit defers priority until the worker confirms its reply.
func (h *Handler) publishRulesDecision(r *room.Room, game forgeRoomGame, connectionID string, operationID string,
	request protocol.RulesRespond, direct, deferPriority bool) *forgehost.PeerReply {

	state, err := h.prepareForgePublication(r, game, deferPriority)
	if err != nil {
		h.failClosedGameProjections(r, err)
		return nil
	}
	reply, _ := protocol.NewEnvelope(protocol.TypeRulesResponded,
		protocol.RulesResponded{RoomID: r.ID, PromptID: request.PromptID})
	reply.ID = operationID
	peerReply := &forgehost.PeerReply{BindingID: request.PeerBinding, OperationID: operationID,
		Envelopes: []protocol.Envelope{reply, state.projections[connectionID], state.prompts[connectionID]}}
	h.savePeerReceipt(r.ID, game, connectionID, request, peerReply)
	if direct && !state.gameOver {
		delete(state.projections, connectionID)
		delete(state.prompts, connectionID)
	} else {
		if sess := h.sessionByConn(connectionID); sess != nil {
			h.send(sess, reply)
		}
	}
	h.sendForgePublication(r, state)
	return peerReply
}
