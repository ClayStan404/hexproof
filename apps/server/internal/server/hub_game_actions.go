// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

// RollDice produces a public server-generated roll.
func (h *Hub) RollDice(connID string, request protocol.GameRoll,
	r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.RollDice(connID, request)
	})
}

// FlipCoin produces one public server-generated coin result.
func (h *Hub) FlipCoin(connID string, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.FlipCoin(connID)
	})
}

// RandomSelect chooses a public player or battlefield candidate.
func (h *Hub) RandomSelect(connID string, request protocol.GameRandomSelect,
	r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.RandomSelect(connID, request)
	})
}

// CreateToken creates one authoritative battlefield-only token.
func (h *Hub) CreateToken(connID string, request protocol.GameCreateToken,
	r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.CreateToken(connID, request)
	})
}

// PlayLand atomically records one active-player hand-to-battlefield land play.
func (h *Hub) PlayLand(connID string, request protocol.GamePlayLand,
	r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.PlayLand(connID, request)
	})
}

// SetLandPlayCount corrects the active turn's public recorded count.
func (h *Hub) SetLandPlayCount(connID string,
	request protocol.GameSetLandPlayCount, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.SetLandPlayCount(connID, request)
	})
}

// AdjustCommanderTax updates one EDH player's dedicated manual tax control.
func (h *Hub) AdjustCommanderTax(connID string,
	request protocol.GameAdjustCommanderTax, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.AdjustCommanderTax(connID, request)
	})
}

// CastCommander atomically moves an owned commander to the shared stack and
// advances its dedicated tax value.
func (h *Hub) CastCommander(connID string,
	request protocol.GameCastCommander, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.CastCommander(connID, request)
	})
}

// SetCommanderDamage updates one public physical-commander damage total and
// may atomically apply the same positive amount to the target's life.
func (h *Hub) SetCommanderDamage(connID string,
	request protocol.GameSetCommanderDamage, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.SetCommanderDamage(connID, request)
	})
}

// SetArrow replaces one player's temporary public targeting annotation.
func (h *Hub) SetArrow(connID string, request protocol.GameSetArrow,
	r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.SetArrow(connID, request)
	})
}

// SetAttachment changes one public battlefield attachment relation.
func (h *Hub) SetAttachment(connID string,
	request protocol.GameSetAttachment, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.SetAttachment(connID, request)
	})
}

// ArrangeBattlefield atomically updates positions on the acting player's
// battlefield without changing gameplay state.
func (h *Hub) ArrangeBattlefield(connID string,
	request protocol.GameArrangeBattlefield, r *room.Room) (room.Result, error) {
	return h.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		return locked.ArrangeBattlefield(connID, request)
	})
}
