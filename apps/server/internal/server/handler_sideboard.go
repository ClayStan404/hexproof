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
	previous := h.sideboardTimers[r.ID]
	var timer *time.Timer
	timer = time.AfterFunc(delay, func() {
		h.expireSideboard(r, timer)
	})
	h.sideboardTimers[r.ID] = timer
	h.sideboardTimerMu.Unlock()
	if previous != nil {
		previous.Stop()
	}
}

func (h *Handler) expireSideboard(r *room.Room, timer *time.Timer) {
	operation, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		log.Printf("expire sideboard: lock room %s: %v", r.ID, err)
		return
	}
	defer operation.opMu.Unlock()

	h.sideboardTimerMu.Lock()
	if h.sideboardTimers[r.ID] != timer {
		h.sideboardTimerMu.Unlock()
		return
	}
	delete(h.sideboardTimers, r.ID)
	h.sideboardTimerMu.Unlock()

	res, err := h.hub.ExpireSideboard(r, time.Now().UTC())
	if err != nil {
		log.Printf("expire sideboard for room %s: %v", r.ID, err)
		return
	}
	if res.StartRulesGame {
		if state, ok := h.prepareForgeTransition(r, nil, ""); ok {
			h.fanout(r, res.Broadcast)
			h.sendRulesProjections(state.projections)
			h.sendRulesPrompts(state.prompts)
		}
		return
	}
	h.fanout(r, res.Broadcast)
	if res.ProjectGame {
		h.fanoutGameProjections(r)
	}
}

func (h *Handler) cancelSideboardExpiration(roomID string) {
	h.sideboardTimerMu.Lock()
	timer := h.sideboardTimers[roomID]
	delete(h.sideboardTimers, roomID)
	h.sideboardTimerMu.Unlock()
	if timer != nil {
		timer.Stop()
	}
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
	for _, event := range res.Broadcast {
		if event.Type == protocol.TypeSideboardCompleted {
			h.cancelSideboardExpiration(r.ID)
			break
		}
	}
	var started forgeStartState
	if res.StartRulesGame {
		var ok bool
		started, ok = h.prepareForgeTransition(r, sess, env.ID)
		if !ok {
			return nil
		}
	}
	if res.Reply != nil {
		res.Reply.ID = env.ID
		h.send(sess, *res.Reply)
	}
	h.fanout(r, res.Broadcast)
	if res.StartRulesGame {
		h.sendRulesProjections(started.projections)
		h.sendRulesPrompts(started.prompts)
		return nil
	}
	h.fanoutGameProjections(r)
	return nil
}
