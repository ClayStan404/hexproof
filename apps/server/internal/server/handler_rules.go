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
		!validRulesPromptScryPiles(request.ScryPiles) ||
		!validRulesPromptAssignments(request.Assignments) ||
		!validRulesPromptDamageOrderIDs(request.DamageOrderIDs) ||
		!validRulesPromptDamageAssignments(request.DamageAssignments) {
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
	promptView, err := forge.NormalizePrompt(rawPrompt)
	if err != nil {
		h.sendError(sess, env.ID, protocol.ErrRulesActionRejected,
			"The Forge decision is stale or no longer available")
		return nil
	}
	if promptView.Kind == "chooseCombatDamageAssignment" {
		ctx, cancel = context.WithTimeout(context.Background(), forgeSnapshotTimeout)
		snapshot, snapshotErr := game.client.SnapshotView(ctx, game.sessionID, playerIndex)
		cancel()
		if snapshotErr != nil {
			h.sendError(sess, env.ID, protocol.ErrRulesUnavailable,
				"Forge damage state is unavailable")
			return nil
		}
		_, damageTargets, projectionErr := projectedRulesDamage(promptView.DamageSource,
			promptView.DamageTargets, promptView.DamageDeathtouch, game, snapshot)
		if projectionErr != nil || !validRulesDamageDistribution(
			damageTargets, promptView.TotalDamage, request.DamageAssignments) {
			h.sendError(sess, env.ID, protocol.ErrRulesActionRejected,
				"The combat damage assignment is invalid")
			return nil
		}
	}
	response, err := forge.BuildPromptResponse(rawPrompt, playerIndex, request.PromptID,
		forge.PromptResponse{
			ResponseID: request.ResponseID, CardIDs: request.CardIDs,
			TargetIDs: request.TargetIDs, Assignments: forgePromptAssignments(request.Assignments),
			ChoiceIDs: request.ChoiceIDs, OrderedIDs: request.OrderedIDs,
			ScryPiles:         forgePromptScryPiles(request.ScryPiles),
			DamageOrderIDs:    request.DamageOrderIDs,
			DamageAssignments: forgePromptDamageAssignments(request.DamageAssignments),
			ChosenNumber:      request.ChosenNumber,
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

func validRulesPromptDamageOrderIDs(ids []string) bool {
	if len(ids) > 512 {
		return false
	}
	seen := make(map[string]struct{}, len(ids))
	for _, id := range ids {
		if len(id) > 128 || !strings.HasPrefix(id, "damage-target:") {
			return false
		}
		if _, duplicate := seen[id]; duplicate {
			return false
		}
		seen[id] = struct{}{}
	}
	return true
}

func validRulesPromptDamageAssignments(assignments []protocol.RulesPromptDamageAssignment) bool {
	if len(assignments) > 512 {
		return false
	}
	seen := make(map[string]struct{}, len(assignments))
	for _, assignment := range assignments {
		if len(assignment.TargetID) > 128 ||
			!strings.HasPrefix(assignment.TargetID, "damage-target:") || assignment.Damage < 0 {
			return false
		}
		if _, duplicate := seen[assignment.TargetID]; duplicate {
			return false
		}
		seen[assignment.TargetID] = struct{}{}
	}
	return true
}

func validRulesDamageDistribution(targets []protocol.RulesPromptDamageTarget, totalDamage int,
	assignments []protocol.RulesPromptDamageAssignment) bool {
	if totalDamage < 0 || len(assignments) != len(targets) {
		return false
	}
	assigned := make(map[string]int, len(assignments))
	total := 0
	for _, assignment := range assignments {
		if assignment.Damage < 0 {
			return false
		}
		if _, duplicate := assigned[assignment.TargetID]; duplicate {
			return false
		}
		assigned[assignment.TargetID] = assignment.Damage
		if assignment.Damage > totalDamage-total {
			return false
		}
		total += assignment.Damage
	}
	if total != totalDamage {
		return false
	}
	laterDamage := 0
	for index := len(targets) - 1; index >= 0; index-- {
		target := targets[index]
		damage, exists := assigned[target.ResponseID]
		if !exists {
			return false
		}
		if laterDamage > 0 && target.LethalDamage >= 0 && damage < target.LethalDamage {
			return false
		}
		laterDamage += damage
	}
	return true
}

func forgePromptDamageAssignments(assignments []protocol.RulesPromptDamageAssignment) []forge.PromptDamageAssignment {
	result := make([]forge.PromptDamageAssignment, 0, len(assignments))
	for _, assignment := range assignments {
		result = append(result, forge.PromptDamageAssignment{
			TargetID: assignment.TargetID, Damage: assignment.Damage,
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

func validRulesPromptScryPiles(piles []protocol.RulesPromptScryPile) bool {
	if len(piles) > 5 {
		return false
	}
	seen := make(map[string]struct{})
	seenDestinations := make(map[string]struct{}, len(piles))
	total := 0
	for _, pile := range piles {
		if _, supported := map[string]struct{}{
			"libraryTop": {}, "libraryBottom": {}, "graveyard": {}, "exile": {}, "hand": {},
		}[pile.Destination]; !supported {
			return false
		}
		if _, duplicate := seenDestinations[pile.Destination]; duplicate {
			return false
		}
		seenDestinations[pile.Destination] = struct{}{}
		for _, id := range pile.CardIDs {
			total++
			if total > 512 || len(id) > 128 || !strings.HasPrefix(id, "scry:") {
				return false
			}
			if _, duplicate := seen[id]; duplicate {
				return false
			}
			seen[id] = struct{}{}
		}
	}
	return true
}

func forgePromptScryPiles(piles []protocol.RulesPromptScryPile) []forge.PromptScryPile {
	result := make([]forge.PromptScryPile, 0, len(piles))
	for _, pile := range piles {
		result = append(result, forge.PromptScryPile{
			Destination: pile.Destination, CardIDs: append([]string(nil), pile.CardIDs...),
		})
	}
	return result
}
