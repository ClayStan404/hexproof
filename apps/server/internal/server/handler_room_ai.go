// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func (h *Handler) handleRoomAIConfigure(sess *Session, env protocol.Envelope) error {
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	var request protocol.RoomAIConfigure
	if env.DecodePayload(&request) != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, "invalid AI configuration")
		return nil
	}
	operation, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	defer operation.opMu.Unlock()
	result, err := h.hub.reduceRoom(r, func(locked *room.Room) (room.Result, error) { return locked.ConfigureAI(sess.ConnectionID, request) })
	if err != nil {
		code, _ := ErrCode(err)
		if code == "" {
			code = protocol.ErrInvalidMessage
		}
		h.sendError(sess, env.ID, code, "AI configuration was rejected")
		return nil
	}
	result.Reply.ID = env.ID
	h.send(sess, *result.Reply)
	h.fanout(r, result.Broadcast)
	return nil
}
