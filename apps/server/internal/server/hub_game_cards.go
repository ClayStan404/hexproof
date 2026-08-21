// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

// MoveCard applies one authoritative card-instance move for the acting player.
func (h *Hub) MoveCard(connID string, move protocol.GameMoveCard,
	r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.MoveCard(connID, move)
	})
}

// MoveApprovedCard applies the exact public-zone request retained by the
// handler after the source-zone player approves it.
func (h *Hub) MoveApprovedCard(connID string, move protocol.GameMoveCard,
	r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.MoveApprovedCard(connID, move)
	})
}

// MoveCards applies one atomic public battlefield batch move.
func (h *Hub) MoveCards(connID string, move protocol.GameMoveCards,
	r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.MoveCards(connID, move)
	})
}

// MoveApprovedCards applies an approved atomic public-zone batch request.
func (h *Hub) MoveApprovedCards(connID string, move protocol.GameMoveCards,
	r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.MoveApprovedCards(connID, move)
	})
}

// PublicZoneMoveTarget resolves the live player who owns the source zone
// without exposing server connection ids to either client.
func (h *Hub) PublicZoneMoveTarget(connID string, sourceSeat int,
	sourceZone, toZone string, cardCount int,
	r *room.Room) (room.PublicZoneMoveTarget, error) {
	entry := h.roomEntryFor(r.ID)
	if entry == nil {
		return room.PublicZoneMoveTarget{},
			&protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()
	target, err := r.PublicZoneMoveTarget(
		connID, sourceSeat, sourceZone, toZone, cardCount)
	if err != nil {
		return room.PublicZoneMoveTarget{}, mapRoomError(err)
	}
	return target, nil
}
