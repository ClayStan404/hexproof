// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"log"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

// actionClockTimer is published before its callback can inspect it. The token
// also prevents a stopped timer from acting on a replacement deadline.
type actionClockTimer struct {
	timer *time.Timer
}

func (h *Handler) observeActionClock(r *room.Room, prioritySeat int) {
	if r == nil {
		return
	}
	operation, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		return
	}
	defer operation.opMu.Unlock()
	h.observeActionClockLocked(operation.room, prioritySeat)
}

// observeActionClockLocked requires the caller to own the room operation lock.
// It returns false when the match has ended, including an expired clock.
func (h *Handler) observeActionClockLocked(r *room.Room, prioritySeat int) bool {
	entry := h.hub.roomEntryFor(r.ID)
	if entry == nil || entry.room != r {
		return false
	}
	entry.mu.Lock()
	if r.ActionClockSeq() == 0 {
		entry.mu.Unlock()
		return true
	}
	if h.actionClockInputPaused(r) {
		prioritySeat = -1
	}
	previous := -1
	if running := r.Snapshot().ActionClockRunning; running != nil {
		previous = *running
	}
	now := time.Now()
	expired := r.AdvanceActionClock(now, prioritySeat)
	deadline := r.ActionClockDeadline(now)
	seq := r.ActionClockSeq()
	current := -1
	if running := r.Snapshot().ActionClockRunning; running != nil {
		current = *running
	}
	var broadcast []protocol.Envelope
	var forfeit room.Result
	var err error
	if expired >= 0 {
		forfeit, err = r.ForfeitActionClock(expired, now)
	} else if previous != current {
		broadcast = []protocol.Envelope{r.SnapshotEnvelope()}
	}
	finished := r.Game != nil && r.Game.Result != nil && r.Game.Result.MatchFinished
	loserID, winnerWins, loserWins := actionClockScore(r, expired)
	tournamentID, pairingID := r.TournamentID, r.TournamentPairingID
	entry.mu.Unlock()
	if expired >= 0 {
		h.cancelActionClock(r.ID)
		if err != nil {
			log.Printf("action clock forfeit for room %s: %v", r.ID, err)
			return !finished
		}
		if game, ok := h.forgeGame(r.ID); ok {
			h.finishForgeGame(r.ID, game, false)
		}
		h.fanout(r, forfeit.Broadcast)
		h.fanoutRulesMetadata(r)
		// Event operations also acquire room operations when opening a table.
		// Record the result after releasing this operation rather than reverse
		// that lock order inside a Forge publication.
		go h.applyActionClockTimeout(tournamentID, pairingID, loserID, winnerWins, loserWins)
		return false
	}
	if len(broadcast) > 0 {
		h.fanout(r, broadcast)
	}
	h.scheduleActionClock(r.ID, deadline, seq)
	return !finished
}

func (h *Handler) pauseActionClockLocked(r *room.Room) bool {
	return h.observeActionClockLocked(r, -1)
}

func (h *Handler) scheduleActionClock(roomID string, deadline time.Time, seq uint64) {
	h.actionClockMu.Lock()
	defer h.actionClockMu.Unlock()
	if h.actionClockClosed {
		return
	}
	if previous := h.actionClockTimers[roomID]; previous != nil {
		previous.timer.Stop()
		delete(h.actionClockTimers, roomID)
	}
	if deadline.IsZero() {
		return
	}
	delay := time.Until(deadline)
	if delay < 0 {
		delay = 0
	}
	token := &actionClockTimer{}
	token.timer = time.AfterFunc(delay, func() {
		h.expireActionClock(roomID, seq, token)
	})
	h.actionClockTimers[roomID] = token
}

func (h *Handler) cancelActionClock(roomID string) {
	h.actionClockMu.Lock()
	token := h.actionClockTimers[roomID]
	delete(h.actionClockTimers, roomID)
	h.actionClockMu.Unlock()
	if token != nil {
		token.timer.Stop()
	}
}

func (h *Handler) cancelAllActionClocks() {
	h.actionClockMu.Lock()
	defer h.actionClockMu.Unlock()
	h.actionClockClosed = true
	for roomID, token := range h.actionClockTimers {
		token.timer.Stop()
		delete(h.actionClockTimers, roomID)
	}
}

func (h *Handler) expireActionClock(roomID string, seq uint64, token *actionClockTimer) {
	operation, err := h.hub.lockRoomOperation(roomID)
	if err != nil {
		return
	}
	defer operation.opMu.Unlock()
	h.actionClockMu.Lock()
	if h.actionClockTimers[roomID] != token {
		h.actionClockMu.Unlock()
		return
	}
	delete(h.actionClockTimers, roomID)
	h.actionClockMu.Unlock()
	operation.mu.Lock()
	if operation.room.ActionClockSeq() != seq {
		operation.mu.Unlock()
		return
	}
	now := time.Now()
	deadline := operation.room.ActionClockDeadline(now)
	seat := -1
	if running := operation.room.Snapshot().ActionClockRunning; running != nil {
		seat = *running
	}
	operation.mu.Unlock()
	if seat < 0 || deadline.IsZero() {
		return
	}
	if deadline.After(now) {
		h.scheduleActionClock(roomID, deadline, seq)
		return
	}
	h.observeActionClockLocked(operation.room, seat)
}

func actionClockScore(r *room.Room, loserSeat int) (string, int, int) {
	if r == nil || loserSeat < 0 || loserSeat >= len(r.Seats) {
		return "", 0, 0
	}
	winner := 1 - loserSeat
	if winner < 0 || winner >= len(r.Score) || loserSeat >= len(r.Score) {
		return r.Seats[loserSeat].TournamentParticipantID, 0, 0
	}
	return r.Seats[loserSeat].TournamentParticipantID, r.Score[winner], r.Score[loserSeat]
}

func (h *Handler) applyActionClockTimeout(tournamentID, pairingID, loserID string, winnerWins, loserWins int) {
	if tournamentID == "" || pairingID == "" || loserID == "" {
		return
	}
	entry, err := h.tournaments.lockOperation(tournamentID)
	if err != nil {
		return
	}
	defer entry.opMu.Unlock()
	entry.mu.Lock()
	if entry.event.Coordinator != protocol.LimitedCoordinatorSwiss {
		entry.mu.Unlock()
		return
	}
	err = entry.event.ApplyTimeout(pairingID, loserID, winnerWins, loserWins, time.Now().UTC())
	entry.mu.Unlock()
	if err != nil {
		log.Printf("tournament timeout result for %s: %v", tournamentID, err)
		return
	}
	h.fanoutTournament(tournamentID)
}
