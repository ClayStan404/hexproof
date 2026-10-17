// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

// Keep the reducer's public state/sequence while deriving recipient-private
// display metadata from current authenticated membership under the room lock.
func (h *Handler) fanoutRoomSnapshot(r *room.Room, envelope protocol.Envelope, members []*Session) {
	var snapshot protocol.RoomSnapshot
	if err := envelope.DecodePayload(&snapshot); err != nil {
		for _, member := range members {
			h.failClosedSession(member, err)
		}
		return
	}
	entry := h.hub.roomEntryFor(r.ID)
	if entry == nil {
		return
	}
	projected := make(map[string]protocol.Envelope, len(members))
	entry.mu.Lock()
	for _, member := range members {
		private := snapshot
		private.OwnDeckName = ""
		if entry.room == r {
			private = r.ProjectRoomSnapshot(member.ConnectionID, snapshot)
		}
		value, err := protocol.NewEnvelope(protocol.TypeRoomSnapshot, private)
		if err != nil {
			entry.mu.Unlock()
			for _, target := range members {
				h.failClosedSession(target, err)
			}
			return
		}
		value.ID, value.SeqPtr = envelope.ID, envelope.SeqPtr
		projected[member.ConnectionID] = value
	}
	entry.mu.Unlock()
	for _, member := range members {
		h.fanoutTo([]*Session{member}, []protocol.Envelope{projected[member.ConnectionID]})
	}
}
