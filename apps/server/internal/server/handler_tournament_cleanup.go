// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"time"

	"hexproof/server/internal/tournament"
)

func (h *Handler) allowTournamentCreate(ip string, now time.Time) bool {
	return h.tournamentCreateLimiter.allow(
		ip, now, h.config.TournamentCreatesPerMinute)
}

func (h *Handler) tournamentHasBoundSession(tournamentID string) bool {
	h.sessionsMu.RLock()
	defer h.sessionsMu.RUnlock()
	for _, sess := range h.sessions {
		if sess.Tournament().TournamentID == tournamentID {
			return true
		}
	}
	return false
}

func (h *Handler) evictExpiredTournaments(now time.Time) {
	for id, entry := range h.tournaments.snapshot() {
		h.tryEvictTournament(id, entry, now)
	}
}

func tournamentActivityAt(event *tournament.Tournament) time.Time {
	if event == nil {
		return time.Time{}
	}
	if !event.LastActivityAt.IsZero() {
		return event.LastActivityAt
	}
	return event.CreatedAt
}

func (h *Handler) tournamentExpired(event *tournament.Tournament, now time.Time) bool {
	if event == nil {
		return false
	}
	if event.IsTerminal() {
		return !event.ClosedAt.IsZero() &&
			!now.Before(event.ClosedAt.Add(h.config.TournamentClosedTTL))
	}
	activity := tournamentActivityAt(event)
	switch event.Status {
	case tournament.StatusRegistration:
		return !now.Before(activity.Add(h.config.TournamentInactiveTTL))
	case tournament.StatusRunning:
		return !now.Before(activity.Add(h.config.TournamentAbandonedTTL))
	default:
		return false
	}
}

func (h *Handler) tryEvictTournament(id string, entry *tournamentEntry, now time.Time) bool {
	if entry == nil {
		return false
	}
	entry.opMu.Lock()
	defer entry.opMu.Unlock()

	entry.mu.Lock()
	event := entry.event
	expired := h.tournamentExpired(event, now)
	checkPairingRooms := event != nil && !event.IsTerminal()
	entry.mu.Unlock()
	if !expired || h.tournamentHasBoundSession(id) {
		return false
	}
	if checkPairingRooms && h.hub.tournamentHasOccupiedPairingRoom(id) {
		return false
	}
	return h.tournaments.deleteIfSame(id, entry)
}
