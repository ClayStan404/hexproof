// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"errors"
	"fmt"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
)

func (h *Handler) handleForgeConcede(sess *Session, env protocol.Envelope,
	r *room.Room) error {
	var request protocol.GameConcede
	if err := env.DecodePayload(&request); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
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

	ctx, cancel := context.WithTimeout(context.Background(), forgeSnapshotTimeout)
	view, snapshotErr := game.client.SnapshotView(ctx, game.sessionID, playerIndex)
	cancel()
	if snapshotErr != nil || view.GameID != game.gameID {
		h.sendError(sess, env.ID, protocol.ErrRulesUnavailable,
			"Forge player state is unavailable")
		return nil
	}
	status, found := forgePlayerStatus(view, playerIndex)
	if !found {
		h.sendError(sess, env.ID, protocol.ErrRulesUnavailable,
			"Forge player state is unavailable")
		return nil
	}
	if view.GameOver || status != "playing" {
		h.sendError(sess, env.ID, protocol.ErrGameFinished,
			"player is no longer active")
		return nil
	}

	ctx, cancel = context.WithTimeout(context.Background(), forgePromptTimeout)
	err = game.client.Concede(ctx, game.sessionID, playerIndex)
	cancel()
	if err != nil {
		h.sendError(sess, env.ID, protocol.ErrRulesActionRejected,
			"Forge rejected the concession")
		return nil
	}
	if err := waitForForgeConcede(game, playerIndex); err != nil {
		h.failClosedGameProjections(r, err)
		return nil
	}

	projections, err := h.rulesProjections(r)
	if err != nil {
		h.failClosedGameProjections(r, err)
		return nil
	}
	gameOver, winnerSeat, err := rulesProjectionResult(projections)
	if err != nil || (!gameOver && winnerSeat >= 0) {
		if err == nil {
			err = errors.New("Forge published a winner before the game ended")
		}
		h.failClosedGameProjections(r, err)
		return nil
	}

	var prompts map[string]protocol.Envelope
	if gameOver {
		prompts, err = h.clearedRulesPrompts(r, game)
	} else {
		prompts, err = h.rulesPrompts(r)
	}
	if err != nil {
		h.failClosedGameProjections(r, err)
		return nil
	}
	result, err := h.hub.ApplyRulesConcede(r, seat, winnerSeat, gameOver)
	if err != nil {
		h.failClosedGameProjections(r, err)
		return nil
	}
	if gameOver {
		h.finishForgeGame(r.ID, game)
	}

	result.Reply.ID = env.ID
	h.send(sess, *result.Reply)
	h.sendRulesProjections(projections)
	h.sendRulesPrompts(prompts)
	if gameOver {
		h.fanout(r, result.Broadcast)
	}
	return nil
}

func forgePlayerStatus(view forge.GameView, playerIndex int) (string, bool) {
	for _, player := range view.Players {
		index, err := forge.PlayerIndexFromID(player.ID)
		if err == nil && index == playerIndex {
			return player.Status, true
		}
	}
	return "", false
}

func waitForForgeConcede(game forgeRoomGame, playerIndex int) error {
	ctx, cancel := context.WithTimeout(context.Background(), forgePromptTimeout)
	defer cancel()
	ticker := time.NewTicker(forgePromptPollInterval)
	defer ticker.Stop()
	for {
		view, err := game.client.SnapshotView(ctx, game.sessionID, playerIndex)
		if err != nil {
			return err
		}
		if view.GameID != game.gameID {
			return errors.New("Forge snapshot game id does not match room")
		}
		status, found := forgePlayerStatus(view, playerIndex)
		if !found {
			return errors.New("Forge concession omitted the acting player")
		}
		if status == "conceded" || status == "lost" {
			return nil
		}
		select {
		case <-ctx.Done():
			return fmt.Errorf("Forge did not apply the concession: %w", ctx.Err())
		case <-ticker.C:
		}
	}
}
