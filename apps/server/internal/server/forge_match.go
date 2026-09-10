// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
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
	state, err := h.startForgeGame(r)
	if err == nil {
		return state, true
	}
	reset, resetErr := h.hub.ResetRulesStartFailure(r)
	if resetErr == nil {
		h.fanout(r, reset.Broadcast)
	}
	for _, member := range h.sessionsForRoomPointer(r) {
		id := ""
		if member == actor {
			id = requestID
		}
		h.sendError(member, id, protocol.ErrRulesUnavailable,
			"Forge could not start the game; the room is waiting for players to ready again")
	}
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
	res, err := h.hub.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.RestartRulesGame(sess.ConnectionID)
	})
	if err != nil {
		code, _ := ErrCode(err)
		h.sendError(sess, env.ID, code, "this game cannot be restarted")
		return nil
	}
	h.abortForgeGame(r.ID)
	state, ok := h.prepareForgeTransition(r, sess, env.ID)
	if !ok {
		return nil
	}
	res.Reply.ID = env.ID
	h.send(sess, *res.Reply)
	h.fanout(r, res.Broadcast)
	h.sendRulesProjections(state.projections)
	h.sendRulesPrompts(state.prompts)
	return nil
}
