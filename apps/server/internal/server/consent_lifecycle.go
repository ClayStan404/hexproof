// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import "hexproof/server/internal/room"

// Membership changes can finish an EDH game without passing through the generic
// game-command handler. A final departure also expires requests between other
// seats, including players eliminated earlier but still connected to the table.
// The caller holds the room operation lock.
func (h *Handler) discardFinishedGameConsent(r *room.Room) {
	entry := h.hub.roomEntryFor(r.ID)
	if entry == nil {
		return
	}
	entry.mu.Lock()
	finished := entry.room == r && r.Game != nil && r.Game.Result != nil
	entry.mu.Unlock()
	if finished {
		h.discardRoomConsentRequests(r.ID)
	}
}

// A consent grant applies only to the current game. Restarting or beginning a
// new game can reuse physical card IDs, so pending decisions and approved grants
// must not cross that boundary. Call while holding this room's operation lock;
// approval handlers hold the same lock through validation and use.
func (h *Handler) discardRoomConsentRequests(roomID string) {
	h.zoneDumpMu.Lock()
	for approvalID, request := range h.zoneDumpRequests {
		if request.roomID == roomID {
			delete(h.zoneDumpRequests, approvalID)
		}
	}
	h.zoneDumpMu.Unlock()
	h.publicZoneMoveMu.Lock()
	for approvalID, request := range h.publicZoneMoveRequests {
		if request.roomID == roomID {
			delete(h.publicZoneMoveRequests, approvalID)
		}
	}
	h.publicZoneMoveMu.Unlock()
}
