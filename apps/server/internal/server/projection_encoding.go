// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import "hexproof/server/internal/protocol"

// Projection builders already share an immutable redacted envelope among
// spectators. Keep that sharing through final wire encoding, instead of copying
// and scanning the full board and log once per spectator. Private projections
// remain distinct: only identical backing payloads AND envelope headers combine.
// The cache lasts for one fanout; nothing can survive a role or room transition.
func (h *Handler) sendProjectionSet(projections map[string]protocol.Envelope) {
	// Ordinary two/four-player tables need no grouping allocations. Sharing is
	// most useful when a table also has several spectators.
	if len(projections) <= 4 {
		for connectionID, envelope := range projections {
			if session := h.sessionByConn(connectionID); session != nil {
				h.send(session, envelope)
			}
		}
		return
	}
	type key struct {
		kind, id string
		sequence int64
		hasSeq   bool
		payload  *byte
		length   int
	}
	type audience struct {
		envelope protocol.Envelope
		members  []*Session
	}
	audiences := make(map[key]*audience)
	for connectionID, envelope := range projections {
		session := h.sessionByConn(connectionID)
		if session == nil {
			continue
		}
		if len(envelope.Payload) == 0 {
			h.send(session, envelope)
			continue
		}
		identity := key{envelope.Type, envelope.ID, envelope.SeqValue(), envelope.HasSeq(),
			&envelope.Payload[0], len(envelope.Payload)}
		group := audiences[identity]
		if group == nil {
			group = &audience{envelope: envelope}
			audiences[identity] = group
		}
		group.members = append(group.members, session)
	}
	for _, group := range audiences {
		h.fanoutTo(group.members, []protocol.Envelope{group.envelope})
	}
}
