// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func (h *Handler) handleGameConcede(sess *Session, env protocol.Envelope) error {
	r := sess.Room()
	if r != nil && r.RulesMode == protocol.RulesModeForge {
		return h.handleForgeConcede(sess, env, r)
	}
	var request protocol.GameConcede
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.Concede(sess.ConnectionID, r)
		}, gameCommandOptions{
			broadcast:         true,
			projectAlways:     true,
			scheduleSideboard: true,
		})
}

func (h *Handler) handleGameReturnToRoom(sess *Session, env protocol.Envelope) error {
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	var request protocol.GameReturnToRoom
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
	var retained *retainedRoom
	defer func() {
		operation.opMu.Unlock()
		h.saveRoomRetention(retained)
	}()

	// Preserve the completed match before the reducer clears live game state.
	if err := h.hub.CanReturnToRoom(sess.ConnectionID, r); err != nil {
		code, _ := ErrCode(err)
		if code == "" {
			code = protocol.ErrInvalidMessage
		}
		h.sendError(sess, env.ID, code, err.Error())
		return nil
	}
	retained = h.snapshotRoomRetention(r)
	res, err := h.hub.ReturnToRoom(sess.ConnectionID, r)
	if err != nil {
		code, _ := ErrCode(err)
		if code == "" {
			code = protocol.ErrInvalidMessage
		}
		h.sendError(sess, env.ID, code, err.Error())
		return nil
	}
	if res.Reply != nil {
		res.Reply.ID = env.ID
		h.send(sess, *res.Reply)
	}
	h.fanout(r, res.Broadcast)
	return nil
}

func (h *Handler) handleGameSay(sess *Session, env protocol.Envelope) error {
	var request protocol.GameSay
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.Say(sess.ConnectionID, request, r)
		}, gameCommandOptions{})
}

func (h *Handler) handleGameCreateToken(sess *Session, env protocol.Envelope) error {
	var request protocol.GameCreateToken
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.CreateToken(sess.ConnectionID, request, r)
		}, gameCommandOptions{projectAlways: true})
}

func (h *Handler) handleGamePlayLand(sess *Session, env protocol.Envelope) error {
	var request protocol.GamePlayLand
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.PlayLand(sess.ConnectionID, request, r)
		}, gameCommandOptions{projectAlways: true})
}

func (h *Handler) handleGameSetLandPlayCount(sess *Session,
	env protocol.Envelope) error {
	var request protocol.GameSetLandPlayCount
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.SetLandPlayCount(sess.ConnectionID, request, r)
		}, gameCommandOptions{projectAlways: true})
}

func (h *Handler) handleGameAdjustCommanderTax(sess *Session,
	env protocol.Envelope) error {
	var request protocol.GameAdjustCommanderTax
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.AdjustCommanderTax(sess.ConnectionID, request, r)
		}, gameCommandOptions{projectAlways: true})
}

func (h *Handler) handleGameCastCommander(sess *Session,
	env protocol.Envelope) error {
	var request protocol.GameCastCommander
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.CastCommander(sess.ConnectionID, request, r)
		}, gameCommandOptions{projectAlways: true})
}

func (h *Handler) handleGameSetCommanderDamage(sess *Session,
	env protocol.Envelope) error {
	var request protocol.GameSetCommanderDamage
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.SetCommanderDamage(sess.ConnectionID, request, r)
		}, gameCommandOptions{projectAlways: true})
}

func (h *Handler) handleGameSetArrow(sess *Session,
	env protocol.Envelope) error {
	var request protocol.GameSetArrow
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.SetArrow(sess.ConnectionID, request, r)
		}, gameCommandOptions{projectAlways: true})
}

func (h *Handler) handleGameSetAttachment(sess *Session,
	env protocol.Envelope) error {
	var request protocol.GameSetAttachment
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.SetAttachment(sess.ConnectionID, request, r)
		}, gameCommandOptions{projectAlways: true})
}

func (h *Handler) handleGameArrangeBattlefield(sess *Session,
	env protocol.Envelope) error {
	var request protocol.GameArrangeBattlefield
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.ArrangeBattlefield(sess.ConnectionID, request, r)
		}, gameCommandOptions{projectAlways: true})
}
