// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func (h *Hub) UpdateRulesPublicLog(r *room.Room, snapshot protocol.RulesGameSnapshot) {
	entry := h.roomEntryFor(r.ID)
	if entry == nil {
		return
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()
	if entry.room == r {
		r.ObserveRulesPublicState(snapshot)
		r.RecordRulesReview(snapshot)
	}
}

func (h *Hub) RulesReviewProjection(r *room.Room, seq int64) (protocol.Envelope, bool) {
	entry := h.roomEntryFor(r.ID)
	if entry == nil {
		return protocol.Envelope{}, false
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()
	if entry.room != r {
		return protocol.Envelope{}, false
	}
	return r.RulesReviewProjection(seq)
}
