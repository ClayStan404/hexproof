// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func (h *Handler) handleGameDeclareDraw(sess *Session,
	env protocol.Envelope) error {
	var request protocol.GameDeclareDraw
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.DeclareDraw(sess.ConnectionID, r)
		}, gameCommandOptions{broadcast: true, scheduleSideboard: true})
}

func (h *Handler) handleGameRestart(sess *Session,
	env protocol.Envelope) error {
	var request protocol.GameRestart
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.RestartGame(sess.ConnectionID, r)
		}, gameCommandOptions{broadcast: true})
}

func (h *Handler) handleGameRoll(sess *Session,
	env protocol.Envelope) error {
	var request protocol.GameRoll
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.RollDice(sess.ConnectionID, request, r)
		}, gameCommandOptions{broadcast: true})
}

func (h *Handler) handleGameFlipCoin(sess *Session,
	env protocol.Envelope) error {
	var request protocol.GameFlipCoin
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.FlipCoin(sess.ConnectionID, r)
		}, gameCommandOptions{broadcast: true})
}

func (h *Handler) handleGameRandomSelect(sess *Session,
	env protocol.Envelope) error {
	var request protocol.GameRandomSelect
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.RandomSelect(sess.ConnectionID, request, r)
		}, gameCommandOptions{broadcast: true})
}

type gameCommandOptions struct {
	broadcast         bool
	projectAlways     bool
	scheduleSideboard bool
}

func (h *Handler) handleGameCommand(sess *Session, env protocol.Envelope,
	request any, reduce func(*room.Room) (room.Result, error),
	options gameCommandOptions) error {
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	if err := env.DecodePayload(request); err != nil {
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
	res, err := reduce(r)
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
	if options.broadcast {
		h.fanout(r, res.Broadcast)
	}
	if options.projectAlways || res.ProjectGame {
		h.fanoutGameProjections(r)
	}
	if options.scheduleSideboard && !res.SideboardDeadline.IsZero() {
		h.scheduleSideboardExpiration(r, res.SideboardDeadline)
	}
	return nil
}
