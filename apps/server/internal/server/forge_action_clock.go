// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"errors"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
)

var errActionClockFinished = errors.New("the action clock finished the match")

func (h *Handler) hasForgeActionClock(r *room.Room) bool {
	entry := h.hub.roomEntryFor(r.ID)
	if entry == nil || entry.room != r {
		return false
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()
	return r.ActionClockSeq() != 0
}

// Caller owns opMu. Provider inference counts as the model seat's decision
// time; an unavailable worker or host cannot supply a playable decision.
func (h *Handler) actionClockInputPaused(r *room.Room) bool {
	if h.playerHostPaused(r) {
		return true
	}
	if !protocol.IsModelAISource(r.AISource) {
		return false
	}
	h.modelMu.Lock()
	defer h.modelMu.Unlock()
	worker := h.modelWorkers[r.ID]
	return worker == nil || worker.connection == nil || worker.state == "paused"
}

// The deciding player owns the clock, including decisions made while another
// player has priority. No prompt means the engine is still advancing the game.
// Caller owns opMu, so a later answer cannot be overwritten by this publication.
func (h *Handler) reconcileForgeActionClock(r *room.Room, game forgeRoomGame, view *forge.PromptView) bool {
	seat := -1
	if view != nil && !h.actionClockInputPaused(r) {
		if owner, exists := game.playerToSeat[view.PlayerIndex]; exists {
			seat = owner
		}
	}
	return h.observeActionClockLocked(r, seat)
}

// Refreshes an existing input boundary without running smart passes. Host
// reconnect and ordinary projection refresh must preserve the current prompt.
func (h *Handler) refreshForgeActionClock(r *room.Room) bool {
	if !h.hasForgeActionClock(r) {
		return true
	}
	game, exists := h.forgeGame(r.ID)
	if !exists || h.actionClockInputPaused(r) {
		return h.pauseActionClockLocked(r)
	}
	ctx, cancel := context.WithTimeout(context.Background(), runtimeTimeout(game.client, forgePromptTimeout))
	view, err := currentRulesPrompt(ctx, game)
	cancel()
	if err != nil {
		return h.pauseActionClockLocked(r)
	}
	return h.reconcileForgeActionClock(r, game, view)
}
