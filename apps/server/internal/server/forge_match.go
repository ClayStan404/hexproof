// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"errors"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
)

// fanoutRulesMetadata publishes only match pacing, the authorized pending
// sideboard, and public logs. It never queries Forge or invents a manual board.
func (h *Handler) fanoutRulesMetadata(r *room.Room) {
	projections, err := h.hub.GameProjections(r)
	if err != nil {
		h.failClosedGameProjections(r, err)
		return
	}
	h.sendProjectionSet(projections)
}

// Reconnect and sideboard updates can inspect the last public table even after
// the runtime has exited. Chat-only metadata updates do not resend this board.
func (h *Handler) fanoutRulesReview(r *room.Room) {
	h.publishForgeReplay(r)
	targets, seq, err := h.hub.RulesProjectionTargets(r)
	if err != nil {
		return
	}
	projection, ok := h.hub.RulesReviewProjection(r, seq)
	if !ok {
		return
	}
	projections := make(map[string]protocol.Envelope, len(targets))
	for connectionID := range targets {
		projections[connectionID] = projection
	}
	h.sendProjectionSet(projections)
}

// RecordRulesStartingSeat stores public initial-turn metadata, never engine
// cards. Once known it remains stable across subsequent turn changes.
func (h *Hub) RecordRulesStartingSeat(r *room.Room, game forgeRoomGame, view forge.GameView) {
	index, err := forge.PlayerIndexFromID(view.StartingPlayerID)
	if err != nil {
		return
	}
	seat, found := game.playerToSeat[index]
	if !found {
		return
	}
	_, _ = h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		if locked.RulesStartingSeat == nil {
			locked.RulesStartingSeat = &seat
		}
		return room.Result{}, nil
	})
}

// prepareForgeTransition runs under the room operation lock. The reducer has
// already selected the next registered partition; failure aborts this match
// to the waiting gate instead of acknowledging a nonexistent next game.
func (h *Handler) prepareForgeTransition(r *room.Room, actor *Session, requestID string) (forgeStartState, bool) {
	if !h.pauseActionClockLocked(r) {
		if actor != nil {
			h.sendError(actor, requestID, protocol.ErrGameFinished, "the action clock finished the match")
		}
		return forgeStartState{}, false
	}
	state, err := h.startForgeGame(r)
	if err == nil {
		return state, true
	}
	if errors.Is(err, errActionClockFinished) {
		return forgeStartState{}, false
	}
	if !h.pauseActionClockLocked(r) {
		return forgeStartState{}, false
	}
	h.abortForgeGame(r.ID)
	reset, resetErr := h.hub.ResetRulesStartFailure(r)
	if resetErr == nil {
		h.fanout(r, reset.Broadcast)
	}
	h.sendForgeStartFailure(r, actor, requestID, err)
	return forgeStartState{}, false
}

func (h *Handler) handleForgeRestart(sess *Session, env protocol.Envelope, r *room.Room) error {
	var request protocol.GameRestart
	if err := env.DecodePayload(&request); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, "invalid restart request")
		return nil
	}
	operation, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		code, _ := ErrCode(err)
		h.sendError(sess, env.ID, code, "room is unavailable")
		return nil
	}
	defer operation.opMu.Unlock()
	operation.mu.Lock()
	restartCode := ""
	switch {
	case r.RulesMode != protocol.RulesModeForge || r.Phase != protocol.RoomPhaseStarted || r.Game != nil:
		restartCode = protocol.ErrGameNotStarted
	case !r.IsHost(sess.ConnectionID):
		restartCode = protocol.ErrNotHost
	case r.RulesStartingSeat == nil:
		restartCode = protocol.ErrGameNotStarted
	}
	operation.mu.Unlock()
	if restartCode != "" {
		h.sendError(sess, env.ID, restartCode, "this game cannot be restarted")
		return nil
	}
	if !h.pauseActionClockLocked(r) {
		h.sendError(sess, env.ID, protocol.ErrGameFinished, "the action clock finished the match")
		return nil
	}
	res, err := h.hub.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.RestartRulesGame(sess.ConnectionID)
	})
	if err != nil {
		code, _ := ErrCode(err)
		h.sendError(sess, env.ID, code, "this game cannot be restarted")
		return nil
	}
	h.closeForgeGame(r.ID, true)
	state, ok := h.prepareForgeTransition(r, sess, env.ID)
	if !ok {
		return nil
	}
	res.Reply.ID = env.ID
	h.send(sess, *res.Reply)
	h.fanout(r, res.Broadcast)
	h.sendForgePublication(r, state)
	return nil
}
