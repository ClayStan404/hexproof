// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"log"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func (h *Handler) observeActionClock(r *room.Room, prioritySeat int) {
	if r == nil {
		return
	}
	operation, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		return
	}
	operation.mu.Lock()
	if operation.room.ActionClockSeq() == 0 {
		operation.mu.Unlock()
		operation.opMu.Unlock()
		return
	}
	previous := -1
	if running := operation.room.Snapshot().ActionClockRunning; running != nil {
		previous = *running
	}
	now := time.Now().UTC()
	if operation.room.Game != nil && operation.room.Game.Sideboard != nil {
		prioritySeat = -1
	}
	expired := operation.room.AdvanceActionClock(now, prioritySeat)
	deadline := operation.room.ActionClockDeadline(now)
	seq := operation.room.ActionClockSeq()
	current := -1
	if running := operation.room.Snapshot().ActionClockRunning; running != nil {
		current = *running
	}
	var broadcast []protocol.Envelope
	var forfeit room.Result
	if expired >= 0 {
		forfeit, err = operation.room.ForfeitActionClock(expired, now)
	} else if previous != current {
		broadcast = []protocol.Envelope{operation.room.SnapshotEnvelope()}
	}
	loserID, winnerWins, loserWins := actionClockScore(operation.room, expired)
	operation.mu.Unlock()
	if err != nil && expired >= 0 {
		operation.opMu.Unlock()
		log.Printf("action clock forfeit for room %s: %v", r.ID, err)
		return
	}
	if expired >= 0 {
		h.cancelActionClock(r.ID)
		if game, ok := h.forgeGame(r.ID); ok {
			h.finishForgeGame(r.ID, game, false)
		}
		if forfeit.Reply != nil {
			h.fanout(r, forfeit.Broadcast)
		}
		h.fanoutRulesMetadata(r)
		tournamentID, pairingID := r.TournamentID, r.TournamentPairingID
		operation.opMu.Unlock()
		h.applyActionClockTimeout(tournamentID, pairingID, loserID, winnerWins, loserWins)
		return
	}
	if len(broadcast) > 0 {
		h.fanout(r, broadcast)
	}
	operation.opMu.Unlock()
	h.scheduleActionClock(r.ID, deadline, seq)
}

func (h *Handler) scheduleActionClock(roomID string, deadline time.Time, seq uint64) {
	h.actionClockMu.Lock()
	previous := h.actionClockTimers[roomID]
	delete(h.actionClockTimers, roomID)
	h.actionClockMu.Unlock()
	if previous != nil {
		previous.Stop()
	}
	if deadline.IsZero() {
		return
	}
	delay := time.Until(deadline)
	if delay < 0 {
		delay = 0
	}
	var timer *time.Timer
	timer = time.AfterFunc(delay, func() {
		h.expireActionClock(roomID, seq, timer)
	})
	h.actionClockMu.Lock()
	if current := h.actionClockTimers[roomID]; current != nil {
		current.Stop()
	}
	h.actionClockTimers[roomID] = timer
	h.actionClockMu.Unlock()
}

func (h *Handler) cancelActionClock(roomID string) {
	h.actionClockMu.Lock()
	timer := h.actionClockTimers[roomID]
	delete(h.actionClockTimers, roomID)
	h.actionClockMu.Unlock()
	if timer != nil {
		timer.Stop()
	}
}

func (h *Handler) expireActionClock(roomID string, seq uint64, timer *time.Timer) {
	h.actionClockMu.Lock()
	if h.actionClockTimers[roomID] != timer {
		h.actionClockMu.Unlock()
		return
	}
	delete(h.actionClockTimers, roomID)
	h.actionClockMu.Unlock()

	operation, err := h.hub.lockRoomOperation(roomID)
	if err != nil {
		return
	}
	operation.mu.Lock()
	if operation.room.ActionClockSeq() != seq {
		operation.mu.Unlock()
		operation.opMu.Unlock()
		return
	}
	running := operation.room.ActionClockDeadline(time.Now().UTC())
	seat := -1
	if clockSeat := operation.room.Snapshot().ActionClockRunning; clockSeat != nil {
		seat = *clockSeat
	}
	if running.After(time.Now()) || seat < 0 {
		operation.mu.Unlock()
		operation.opMu.Unlock()
		return
	}
	forfeit, err := operation.room.ForfeitActionClock(seat, time.Now().UTC())
	loserID, winnerWins, loserWins := actionClockScore(operation.room, seat)
	tournamentID := operation.room.TournamentID
	pairingID := operation.room.TournamentPairingID
	broadcastRoom := operation.room
	operation.mu.Unlock()
	if err != nil {
		operation.opMu.Unlock()
		return
	}
	if game, ok := h.forgeGame(roomID); ok {
		h.finishForgeGame(roomID, game, false)
	}
	h.fanout(broadcastRoom, forfeit.Broadcast)
	h.fanoutRulesMetadata(broadcastRoom)
	operation.opMu.Unlock()
	h.applyActionClockTimeout(tournamentID, pairingID, loserID, winnerWins, loserWins)
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
	err = entry.event.ApplyTimeout(pairingID, loserID, winnerWins, loserWins, time.Now().UTC())
	entry.mu.Unlock()
	if err != nil {
		log.Printf("tournament timeout result for %s: %v", tournamentID, err)
		return
	}
	h.fanoutTournament(tournamentID)
}
