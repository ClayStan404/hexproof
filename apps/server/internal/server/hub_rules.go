// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

// RulesPlayerTargets snapshots live seated connections without allocating a
// room sequence. Rules prompts are private point-to-point state, not shared
// room projections, so spectators are deliberately excluded.
func (h *Hub) RulesPlayerTargets(r *room.Room) (map[string]int, error) {
	if r == nil {
		return nil, &protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	entry := h.roomEntryFor(r.ID)
	if entry == nil {
		return nil, &protocolError{code: protocol.ErrRoomNotFound, message: "room not found"}
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()
	if entry.room != r || r.RulesMode != protocol.RulesModeForge ||
		r.Phase != protocol.RoomPhaseStarted {
		return nil, &protocolError{code: protocol.ErrGameNotStarted, message: "game not started"}
	}
	if r.Game != nil {
		return nil, &protocolError{code: protocol.ErrGameFinished, message: "game already finished"}
	}
	targets := make(map[string]int, r.PlayerCount())
	for seatIndex, seat := range r.Seats {
		if seat.Occupied {
			targets[seat.ConnectionID] = seatIndex
		}
	}
	return targets, nil
}

// RulesActorSeat validates that one authenticated connection owns a live seat
// in the active Forge room.
func (h *Hub) RulesActorSeat(r *room.Room, connectionID string) (int, error) {
	targets, err := h.RulesPlayerTargets(r)
	if err != nil {
		return -1, err
	}
	seat, ok := targets[connectionID]
	if !ok {
		return -1, &protocolError{code: protocol.ErrNotPlayer, message: "players only"}
	}
	return seat, nil
}
