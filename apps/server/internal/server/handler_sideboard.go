// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"log"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func (h *Handler) scheduleSideboardExpiration(r *room.Room, deadline time.Time) {
	delay := time.Until(deadline)
	if delay < 0 {
		delay = 0
	}
	h.sideboardTimerMu.Lock()
	if previous := h.sideboardTimers[r.ID]; previous != nil {
		previous.Stop()
	}
	var timer *time.Timer
	timer = time.AfterFunc(delay, func() {
		h.sideboardTimerMu.Lock()
		if h.sideboardTimers[r.ID] != timer {
			h.sideboardTimerMu.Unlock()
			return
		}
		delete(h.sideboardTimers, r.ID)
		h.sideboardTimerMu.Unlock()

		operation, err := h.hub.lockRoomOperation(r.ID)
		if err != nil {
			log.Printf("expire sideboard: lock room %s: %v", r.ID, err)
			return
		}
		defer operation.opMu.Unlock()
		res, err := h.hub.ExpireSideboard(r, time.Now().UTC())
		if err != nil {
			log.Printf("expire sideboard for room %s: %v", r.ID, err)
			return
		}
		h.fanout(r, res.Broadcast)
		if res.ProjectGame {
			h.fanoutGameProjections(r)
		}
	})
	h.sideboardTimers[r.ID] = timer
	h.sideboardTimerMu.Unlock()
}

func (h *Handler) handleSideboardMove(sess *Session, env protocol.Envelope) error {
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	var request protocol.SideboardMove
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
	res, err := h.hub.MoveSideboard(sess.ConnectionID, request, r)
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
	h.fanoutGameProjections(r)
	return nil
}

func (h *Handler) handleSideboardSetCommander(sess *Session, env protocol.Envelope) error {
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	var request protocol.SideboardSetCommander
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
	res, err := h.hub.SetSideboardCommander(sess.ConnectionID, request, r)
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
	h.fanoutGameProjections(r)
	return nil
}

func (h *Handler) handleSideboardReady(sess *Session, env protocol.Envelope) error {
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	var request protocol.SideboardReady
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
	res, err := h.hub.SetSideboardReady(sess.ConnectionID, request.Ready, r)
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
	h.fanoutGameProjections(r)
	return nil
}
