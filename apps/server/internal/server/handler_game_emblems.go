// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func (h *Handler) handleGameCreateEmblem(sess *Session, env protocol.Envelope) error {
	var request protocol.GameCreateEmblem
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
				return locked.CreateEmblem(sess.ConnectionID, request)
			})
		}, gameCommandOptions{projectAlways: true})
}

func (h *Handler) handleGameRemoveEmblem(sess *Session, env protocol.Envelope) error {
	var request protocol.GameRemoveEmblem
	return h.handleGameCommand(sess, env, &request,
		func(r *room.Room) (room.Result, error) {
			return h.hub.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
				return locked.RemoveEmblem(sess.ConnectionID, request)
			})
		}, gameCommandOptions{projectAlways: true})
}
