// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"strings"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
)

func (h *Handler) handleRulesRespond(sess *Session, env protocol.Envelope) error {
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	var request protocol.RulesRespond
	if err := env.DecodePayload(&request); err != nil || request.PromptID <= 0 ||
		strings.TrimSpace(request.ResponseID) == "" || len(request.ResponseID) > 128 ||
		!validRulesPromptSelectionIDs(request.CardIDs, false) ||
		!validRulesPromptSelectionIDs(request.TargetIDs, true) ||
		!validRulesPromptChoiceIDs(request.ChoiceIDs) ||
		!validRulesPromptOrderIDs(request.OrderedIDs) ||
		!validRulesPromptAssignments(request.Assignments) {
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

	seat, err := h.hub.RulesActorSeat(r, sess.ConnectionID)
	if err != nil {
		code, _ := ErrCode(err)
		h.sendError(sess, env.ID, code, err.Error())
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

	ctx, cancel := context.WithTimeout(context.Background(), forgePromptTimeout)
	rawPrompt, promptErr := game.client.Prompt(ctx, game.sessionID, playerIndex)
	cancel()
	if promptErr != nil {
		h.sendError(sess, env.ID, protocol.ErrRulesUnavailable,
			"Forge prompt is unavailable")
		return nil
	}
	response, err := forge.BuildPromptResponse(rawPrompt, playerIndex, request.PromptID,
		forge.PromptResponse{
			ResponseID: request.ResponseID, CardIDs: request.CardIDs,
			TargetIDs: request.TargetIDs, Assignments: forgePromptAssignments(request.Assignments),
			ChoiceIDs: request.ChoiceIDs, OrderedIDs: request.OrderedIDs,
			ChosenNumber: request.ChosenNumber,
		})
	if err != nil {
		h.sendError(sess, env.ID, protocol.ErrRulesActionRejected,
			"The Forge decision is stale or no longer available")
		return nil
	}
	ctx, cancel = context.WithTimeout(context.Background(), forgePromptTimeout)
	err = game.client.SubmitAction(ctx, game.sessionID, response)
	cancel()
	if err != nil {
		h.sendError(sess, env.ID, protocol.ErrRulesActionRejected,
			"Forge rejected the decision")
		return nil
	}
	if err := waitForForgePromptChange(game, request.PromptID); err != nil {
		h.failClosedGameProjections(r, err)
		return nil
	}

	projections, err := h.rulesProjections(r)
	if err != nil {
		h.failClosedGameProjections(r, err)
		return nil
	}
	gameOver, winnerSeat, err := rulesProjectionResult(projections)
	if err != nil {
		h.failClosedGameProjections(r, err)
		return nil
	}
	var prompts map[string]protocol.Envelope
	var resultBroadcast []protocol.Envelope
	if gameOver {
		prompts, err = h.clearedRulesPrompts(r, game)
		if err == nil {
			var result room.Result
			result, err = h.hub.CompleteRulesGame(r, winnerSeat)
			resultBroadcast = result.Broadcast
		}
		if err != nil {
			h.failClosedGameProjections(r, err)
			return nil
		}
		h.finishForgeGame(r.ID, game)
	} else {
		prompts, err = h.rulesPrompts(r)
		if err != nil {
			h.failClosedGameProjections(r, err)
			return nil
		}
	}
	reply, _ := protocol.NewEnvelope(protocol.TypeRulesResponded,
		protocol.RulesResponded{RoomID: r.ID, PromptID: request.PromptID})
	reply.ID = env.ID
	h.send(sess, reply)
	h.sendRulesProjections(projections)
	h.sendRulesPrompts(prompts)
	if gameOver {
		h.fanout(r, resultBroadcast)
	}
	return nil
}

func validRulesPromptChoiceIDs(ids []string) bool {
	if len(ids) > 512 {
		return false
	}
	for _, id := range ids {
		if len(id) > 128 || !strings.HasPrefix(id, "choice:") {
			return false
		}
	}
	return true
}

func validRulesPromptAssignments(assignments []protocol.RulesPromptAssignment) bool {
	if len(assignments) > 512 {
		return false
	}
	for _, assignment := range assignments {
		if len(assignment.SourceID) > 128 || len(assignment.TargetID) > 128 ||
			!strings.HasPrefix(assignment.SourceID, "combat-source:") ||
			!strings.HasPrefix(assignment.TargetID, "combat-target:") {
			return false
		}
	}
	return true
}

func forgePromptAssignments(assignments []protocol.RulesPromptAssignment) []forge.PromptAssignment {
	result := make([]forge.PromptAssignment, 0, len(assignments))
	for _, assignment := range assignments {
		result = append(result, forge.PromptAssignment{
			SourceID: assignment.SourceID, TargetID: assignment.TargetID,
		})
	}
	return result
}

func validRulesPromptSelectionIDs(ids []string, opaque bool) bool {
	if len(ids) > 512 {
		return false
	}
	for _, id := range ids {
		if strings.TrimSpace(id) == "" || len(id) > 512 ||
			(opaque && !strings.HasPrefix(id, "target:")) {
			return false
		}
	}
	return true
}

func validRulesPromptOrderIDs(ids []string) bool {
	if len(ids) > 512 {
		return false
	}
	for _, id := range ids {
		if len(id) > 128 || !strings.HasPrefix(id, "order:") {
			return false
		}
	}
	return true
}
