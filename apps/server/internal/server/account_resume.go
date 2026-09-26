// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

// A legacy room token proves the held seat, not permission to acquire a second
// participant in its event. Claim that original role before account adoption.
func (h *Handler) adoptAccountResumeHold(hold *resumeHold, accountID string) bool {
	if accountID == "" || hold.accountID != "" {
		return true
	}
	table := h.hub.roomEntryFor(hold.room.ID)
	if table == nil {
		return false
	}
	table.mu.Lock()
	player := table.room == hold.room && hold.room.FindSeatByConnection(hold.oldConnectionID) >= 0
	eventID := table.tournamentID
	table.mu.Unlock()
	if !player {
		return true
	}
	if eventID != "" {
		entry, err := h.tournaments.lockOperation(eventID)
		if err != nil {
			return false
		}
		entry.mu.Lock()
		claimed := entry.event.ClaimConnectionAccount(hold.oldConnectionID, accountID)
		entry.mu.Unlock()
		entry.opMu.Unlock()
		if !claimed {
			return false
		}
	}
	hold.accountID = accountID
	return true
}

func (h *Handler) accountResumeToken(id, roomID string) string {
	if id == "" {
		return ""
	}
	h.resumeMu.Lock()
	defer h.resumeMu.Unlock()
	for token, hold := range h.resumeHolds {
		if hold.accountID == id && (roomID == "" || roomID == hold.room.ID) && time.Now().Before(hold.expiresAt) {
			return token
		}
	}
	return ""
}

func (h *Handler) resumeAccountRoom(sess *Session, roomID string) bool {
	if r := sess.Room(); r != nil {
		return roomID == "" || r.ID == roomID
	}
	token := h.accountResumeToken(sess.Account().ID, roomID)
	if token == "" {
		return false
	}
	hold, ok := h.takeAccountResumeHold(token, sess.Account().ID, time.Now().UTC())
	if !ok {
		return false
	}
	if h.cubeRoomBlocksNavigation(sess, h.hub.TournamentForRoom(hold.room)) {
		if h.restoreResumeHold(hold, time.Now().UTC()) {
			h.expireResumeHold(hold)
		}
		return false
	}
	entry, err := h.hub.lockRoomOperation(hold.room.ID)
	if err != nil {
		return false
	}
	info, envelopes, err := h.hub.ResumeRoom(hold.oldConnectionID, sess, hold.room)
	if err != nil {
		entry.mu.Lock()
		retryable := entry.room == hold.room && !hold.room.Disbanded && hold.room.Member(hold.oldConnectionID)
		entry.mu.Unlock()
		expired := retryable && h.restoreResumeHold(hold, time.Now().UTC())
		entry.opMu.Unlock()
		if expired {
			h.expireResumeHold(hold)
		}
		return false
	}
	h.rebindResumedRoom(sess, hold)
	joined, _ := protocol.NewEnvelope(protocol.TypeRoomJoined, protocol.RoomJoined{RoomID: hold.room.ID, Role: info.Role, Seat: info.Seat})
	h.send(sess, joined)
	h.sendResumedRoomState(sess, hold.room, envelopes)
	entry.opMu.Unlock()
	h.restoreAccountTableEvent(sess, hold.room)
	return true
}

// Callers hold the room operation lock throughout rebinding and projection.
func (h *Handler) rebindResumedRoom(sess *Session, hold resumeHold) {
	h.forgeReplays.rebind(hold.room, hold.oldConnectionID, sess.ConnectionID)
	if aid := sess.Account().ID; aid != "" {
		entry := h.hub.roomEntryFor(hold.room.ID)
		entry.mu.Lock()
		if seat := hold.room.FindSeatByConnection(sess.ConnectionID); seat >= 0 {
			hold.room.Seats[seat].AccountID = aid
		}
		entry.mu.Unlock()
		h.forgeReplays.bindAccount(hold.room, sess.ConnectionID, aid)
	}
	h.forgeMu.Lock()
	if backup := h.playerBackups[hold.room.ID]; backup != nil && backup.connectionID == hold.oldConnectionID {
		backup.connectionID = sess.ConnectionID
	}
	h.forgeMu.Unlock()
}

func (h *Handler) sendResumedRoomState(sess *Session, r *room.Room, envelopes []protocol.Envelope) {
	h.fanoutTo([]*Session{sess}, envelopes)
	h.grantModelWorker(sess, r)
	if r.RulesMode == protocol.RulesModeForge && r.Phase == protocol.RoomPhaseStarted {
		h.fanoutGameProjections(r)
		if _, alive := h.forgeGame(r.ID); alive {
			h.fanoutRulesPrompts(r)
		}
	}
}

// A new device has no local tournament binding. Restore the existing account
// role behind a pairing table only after releasing its room operation lock.
func (h *Handler) restoreAccountTableEvent(sess *Session, r *room.Room) {
	if sess.Account().ID == "" {
		return
	}
	id := h.hub.TournamentForRoom(r)
	if id == "" {
		return
	}
	entry := h.tournaments.entry(id)
	if entry == nil {
		return
	}
	entry.mu.Lock()
	role, _ := entry.event.AccountRole(sess.Account().ID)
	entry.mu.Unlock()
	if role == "" {
		return
	}
	env, _ := protocol.NewEnvelope(protocol.TypeTournamentEnter, protocol.TournamentEnter{TournamentID: id, UseAccount: true})
	_ = h.handleTournamentEnter(sess, env)
}
