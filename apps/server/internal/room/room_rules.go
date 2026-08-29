// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"time"

	"hexproof/server/internal/protocol"
)

// CompleteRulesGame records the result of an externally authoritative rules
// game. It creates only the minimal result shell needed by the existing match,
// sideboard, retention, and return-to-room flows; no Forge card state is copied
// into the manual tabletop reducer.
func (r *Room) CompleteRulesGame(winnerSeat int, now time.Time) (Result, error) {
	if r.RulesMode != protocol.RulesModeForge || r.Phase != protocol.RoomPhaseStarted ||
		r.Game != nil || now.IsZero() {
		return Result{}, newError(protocol.ErrGameNotStarted)
	}
	if winnerSeat >= 0 && (winnerSeat >= len(r.Seats) || !r.Seats[winnerSeat].Occupied) {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	gameNumber := r.DrawnGames + 1
	for _, wins := range r.Score {
		gameNumber += wins
	}
	if len(r.Score) != len(r.Seats) {
		r.Score = make([]int, len(r.Seats))
	}
	if winnerSeat >= 0 {
		r.Score[winnerSeat]++
	} else {
		r.DrawnGames++
	}
	matchFinished := true

	game := &GameState{
		Number: gameNumber, StartingSeat: -1, TurnOrder: []int{}, ActiveSeat: -1,
		CurrentPhase: protocol.GamePhaseEnd,
		Seats:        make([]PlayerGameState, len(r.Seats)),
		Stack:        []protocol.GameSharedCard{}, Revealed: []protocol.GameSharedCard{},
		Arrows: []protocol.GameArrow{}, Attachments: []protocol.GameAttachment{},
		CommanderDamage: make(map[string]map[int]int), Log: []protocol.GameLogEntry{},
		NextLogID: 1, NextTokenID: 1, NextCardCounterID: 1,
		Result: &protocol.GameResult{
			Reason: protocol.GameResultRules, WinnerSeat: winnerSeat,
			ConcededSeat: -1, MatchFinished: matchFinished,
		},
	}
	for seatIndex, seat := range r.Seats {
		game.Seats[seatIndex] = PlayerGameState{
			Seat: seatIndex, DisplayName: seat.DisplayName,
			Eliminated: !seat.Occupied, CommanderTaxes: make(map[string]int),
		}
	}
	r.Game = game
	return Result{Broadcast: []protocol.Envelope{r.snapshotEnvelope()}}, nil
}
