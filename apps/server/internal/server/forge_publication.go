// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"

	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
)

// prepareForgePublication owns smart-priority advancement before collecting
// snapshots, prompts and the terminal result. Callers hold the room operation
// lock; pure reconnect and receipt replay use the read-only projection helpers.
// An adopted direct commit defers smart passes until its private confirmation.
func (h *Handler) prepareForgePublication(r *room.Room, game forgeRoomGame, deferPriority bool) (forgeStartState, error) {
	state := forgeStartState{}
	if !deferPriority {
		if err := h.advanceRulesPriority(r, game); err != nil {
			return state, err
		}
	}
	if h.hasForgeActionClock(r) {
		ctx, cancel := context.WithTimeout(context.Background(), runtimeTimeout(game.client, forgePromptTimeout))
		gameOver, err := game.client.GameOver(ctx, game.sessionID)
		var view *forge.PromptView
		if err == nil && !gameOver {
			view, err = currentRulesPrompt(ctx, game)
		}
		cancel()
		if err != nil {
			return state, err
		}
		if !h.reconcileForgeActionClock(r, game, view) {
			return state, errActionClockFinished
		}
	}
	var err error
	state.projections, err = h.rulesProjections(r)
	if err != nil {
		return state, err
	}
	var winnerSeat int
	state.gameOver, winnerSeat, err = rulesProjectionResult(state.projections)
	if err != nil {
		return state, err
	}
	if !state.gameOver {
		state.prompts, err = h.rulesPrompts(r)
		if err == nil {
			pairRulesPrompts(state.projections, state.prompts)
		}
		return state, err
	}
	state.prompts, err = h.clearedRulesPrompts(r, game)
	if err != nil {
		return state, err
	}
	pairRulesPrompts(state.projections, state.prompts)
	result, err := h.hub.CompleteRulesGame(r, winnerSeat)
	if err != nil {
		return state, err
	}
	state.resultBroadcast = result.Broadcast
	state.sideboardDeadline = result.SideboardDeadline
	h.finishForgeGame(r.ID, game, !state.sideboardDeadline.IsZero())
	return state, nil
}

func (h *Handler) sendForgePublication(r *room.Room, state forgeStartState) {
	h.sendRulesTable(state.projections, state.prompts)
	if state.gameOver {
		h.fanout(r, state.resultBroadcast)
		if !state.sideboardDeadline.IsZero() {
			h.scheduleSideboardExpiration(r, state.sideboardDeadline)
		}
	}
}
