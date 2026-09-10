// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"sort"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/tournament"
)

func (h *Handler) allowTournamentCreate(ip string, now time.Time) bool {
	return h.tournamentCreateLimiter.allow(ip, now, h.config.TournamentCreatesPerMinute)
}

func stopTournamentCleanupLocked(entry *tournamentEntry) {
	entry.cleanupGeneration++
	if entry.cleanupTimer != nil {
		entry.cleanupTimer.Stop()
		entry.cleanupTimer = nil
	}
	entry.cleanupDeadline = time.Time{}
}

func (h *Handler) evictExpiredTournaments(now time.Time) {
	for id, entry := range h.tournaments.snapshot() {
		h.tryEvictTournament(id, entry, now)
	}
}

func (h *Handler) tryEvictTournament(id string, entry *tournamentEntry, now time.Time) bool {
	if entry == nil {
		return false
	}
	entry.opMu.Lock()
	defer entry.opMu.Unlock()
	return h.reconcileTournamentRetentionLocked(id, entry, now, false)
}

// Call after releasing room operation locks: tournament operations precede rooms.
func (h *Handler) refreshTournamentRetention(id string) {
	if entry := h.tournaments.entry(id); entry != nil {
		h.tryEvictTournament(id, entry, time.Now().UTC())
	}
}

// entry.opMu serializes recovery and expiry. Activity timestamps intentionally do
// not participate: spectator entry, chat and repeated list requests cannot renew
// an abandoned tournament's grace period.
func (h *Handler) reconcileTournamentRetentionLocked(id string, entry *tournamentEntry,
	now time.Time, immediateEmpty bool) bool {
	h.tournaments.mu.Lock()
	current := !h.tournaments.closed && h.tournaments.events[id] == entry
	h.tournaments.mu.Unlock()
	if !current {
		return false
	}
	online := h.tournamentHasOnlineAuthority(entry) || h.tournamentHasOnlinePlayer(id)
	entry.mu.Lock()
	event := entry.event
	var deadline time.Time
	if event.IsTerminal() {
		if !event.ClosedAt.IsZero() {
			deadline = event.ClosedAt.Add(h.config.TournamentClosedTTL)
		}
	} else if online {
		entry.unattendedSince = time.Time{}
	} else {
		if entry.unattendedSince.IsZero() {
			entry.unattendedSince = now
		}
		ttl := h.config.TournamentAbandonedTTL
		if event.Status == tournament.StatusRegistration {
			ttl = h.config.TournamentInactiveTTL
		}
		deadline = entry.unattendedSince.Add(ttl)
		if immediateEmpty && event.Status == tournament.StatusRegistration && len(event.Participants) == 0 {
			deadline = now
		}
	}
	entry.mu.Unlock()
	if deadline.IsZero() || now.Before(deadline) {
		h.scheduleTournamentCleanup(entry, id, deadline, now)
		return false
	}

	// Online room players and the room's existing transport reconnect holds are
	// authoritative even when nobody has rebound the tournament view. Hold room
	// operations through removal so a concurrent room join/resume cannot slip in.
	rooms := h.tournamentRooms(id)
	for _, roomEntry := range rooms {
		roomEntry.opMu.Lock()
	}
	defer func() {
		for i := len(rooms) - 1; i >= 0; i-- {
			rooms[i].opMu.Unlock()
		}
	}()
	for _, roomEntry := range rooms {
		if h.hub.FindRoom(roomEntry.room.ID) != roomEntry.room {
			continue
		}
		roomEntry.mu.Lock()
		occupied := !roomEntry.room.Disbanded && roomEntry.room.PlayerCount() > 0
		roomEntry.mu.Unlock()
		if occupied {
			// Do not renew unattendedSince. Existing hold expiry also reconciles
			// retention; this retry covers a resume already in flight.
			h.scheduleTournamentCleanup(entry, id, now.Add(time.Second), now)
			return false
		}
	}
	for _, roomEntry := range rooms {
		if h.hub.FindRoom(roomEntry.room.ID) != roomEntry.room {
			continue
		}
		roomEntry.mu.Lock()
		r := roomEntry.room
		r.Disbanded = true
		seq := r.AllocSeq()
		roomEntry.mu.Unlock()
		closed, _ := protocol.NewEnvelope(protocol.TypeRoomDisbanded, protocol.RoomLeft{RoomID: r.ID})
		h.disbandAndFanout(r, []protocol.Envelope{closed.WithSeq(seq)})
		_ = h.removeRoom(r) // entry.opMu is already held; no pairing cleanup re-entry.
	}
	entry.mu.Lock()
	if !event.IsTerminal() {
		event.Status = tournament.StatusCancelled
		event.Stage = protocol.LimitedStageCancelled
		event.ClosedAt = now
		if event.Limited != nil {
			event.Limited.Cancel()
		}
	}
	cube := event.IsCubeRoom()
	entry.mu.Unlock()
	h.fanoutTournamentState(id, nil)
	h.closeTournamentMembers(entry, id)
	removed := h.tournaments.deleteIfSame(id, entry)
	if removed && cube {
		h.hub.releaseCubeRoomID(id)
	}
	return removed
}

func (h *Handler) scheduleTournamentCleanup(entry *tournamentEntry, id string, deadline, now time.Time) {
	entry.mu.Lock()
	defer entry.mu.Unlock()
	if entry.cleanupDeadline.Equal(deadline) {
		return
	}
	stopTournamentCleanupLocked(entry)
	if deadline.IsZero() {
		return
	}
	// Serialize scheduling with Close, which releases registry.mu before taking
	// any entry locks and then stops every timer.
	h.tournaments.mu.Lock()
	defer h.tournaments.mu.Unlock()
	if h.tournaments.closed || h.tournaments.events[id] != entry {
		return
	}
	entry.cleanupDeadline = deadline
	generation := entry.cleanupGeneration
	entry.cleanupTimer = time.AfterFunc(deadline.Sub(now), func() {
		entry.opMu.Lock()
		defer entry.opMu.Unlock()
		entry.mu.Lock()
		valid := entry.cleanupGeneration == generation && entry.cleanupDeadline.Equal(deadline)
		if valid {
			entry.cleanupDeadline = time.Time{}
			entry.cleanupTimer = nil
		}
		entry.mu.Unlock()
		if valid {
			h.reconcileTournamentRetentionLocked(id, entry, time.Now().UTC(), false)
		}
	})
}

func (h *Handler) tournamentHasOnlineAuthority(entry *tournamentEntry) bool {
	h.sessionsMu.RLock()
	sessions := make([]*Session, 0, len(h.sessions))
	for _, sess := range h.sessions {
		sessions = append(sessions, sess)
	}
	h.sessionsMu.RUnlock()
	entry.mu.Lock()
	defer entry.mu.Unlock()
	for _, sess := range sessions {
		sess.tournamentMu.RLock()
		binding := sess.tournament
		_, valid := tournamentProjectionIdentity(entry.event, sess, binding)
		sess.tournamentMu.RUnlock()
		if valid && binding.Role != tournament.RoleViewer {
			return true
		}
	}
	return false
}

func (h *Handler) tournamentRooms(id string) []*roomEntry {
	h.hub.mu.Lock()
	rooms := make([]*roomEntry, 0)
	for _, entry := range h.hub.rooms {
		if entry.tournamentID == id {
			rooms = append(rooms, entry)
		}
	}
	h.hub.mu.Unlock()
	sort.Slice(rooms, func(i, j int) bool { return rooms[i].room.ID < rooms[j].room.ID })
	return rooms
}

func (h *Handler) tournamentHasOnlinePlayer(id string) bool {
	for _, entry := range h.tournamentRooms(id) {
		entry.mu.Lock()
		r := entry.room
		connections := make([]string, 0)
		if !r.Disbanded {
			for _, seat := range r.Seats {
				if seat.Occupied && seat.ConnectionID != "" {
					connections = append(connections, seat.ConnectionID)
				}
			}
		}
		entry.mu.Unlock()
		for _, connection := range connections {
			if sess := h.sessionByConn(connection); sess != nil && sess.Room() == r {
				return true
			}
		}
	}
	return false
}

func (h *Handler) closeTournamentMembers(entry *tournamentEntry, id string) {
	type member struct {
		session *Session
		binding tournamentBinding
	}
	h.sessionsMu.RLock()
	members := make([]member, 0)
	for _, sess := range h.sessions {
		if binding := sess.Tournament(); binding.TournamentID == id {
			members = append(members, member{sess, binding})
		}
	}
	h.sessionsMu.RUnlock()
	for _, member := range members {
		h.closeTournamentMembership(entry, member.session, member.binding, "")
	}
}
