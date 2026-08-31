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
	if err := r.validateRulesResult(winnerSeat, now); err != nil {
		return Result{}, err
	}
	return r.completeRulesGame(winnerSeat, protocol.GameResultRules, -1), nil
}

// ApplyRulesConcede records the public acknowledgement for an authoritative
// Forge concession. Multiplayer concessions keep the engine game live; only a
// terminal projection creates the ordinary Hexproof result shell.
func (r *Room) ApplyRulesConcede(concededSeat, winnerSeat int, matchFinished bool,
	now time.Time) (Result, error) {
	if err := r.validateRulesResult(winnerSeat, now); err != nil {
		return Result{}, err
	}
	if concededSeat < 0 || concededSeat >= len(r.Seats) ||
		!r.Seats[concededSeat].Occupied || winnerSeat == concededSeat {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	if !matchFinished {
		if r.Format != protocol.FormatEDH || winnerSeat >= 0 {
			return Result{}, newError(protocol.ErrUnsupportedFormat)
		}
	}
	gameNumber := r.rulesGameNumber()
	result := Result{}
	if matchFinished {
		result = r.completeRulesGame(
			winnerSeat, protocol.GameResultConcede, concededSeat)
	}
	reply, _ := protocol.NewEnvelope(protocol.TypeGameConceded,
		protocol.GameConceded{
			RoomID: r.ID, GameNumber: gameNumber, ConcededSeat: concededSeat,
			WinnerSeat: winnerSeat, Score: append([]int{}, r.Score...),
			MatchFinished: matchFinished,
		})
	result.Reply = &reply
	return result, nil
}

func (r *Room) validateRulesResult(winnerSeat int, now time.Time) error {
	if r.RulesMode != protocol.RulesModeForge || r.Phase != protocol.RoomPhaseStarted ||
		r.Game != nil || now.IsZero() {
		return newError(protocol.ErrGameNotStarted)
	}
	if winnerSeat < -1 ||
		(winnerSeat >= 0 && (winnerSeat >= len(r.Seats) || !r.Seats[winnerSeat].Occupied)) {
		return newError(protocol.ErrInvalidTarget)
	}
	return nil
}

func (r *Room) rulesGameNumber() int {
	gameNumber := r.DrawnGames + 1
	for _, wins := range r.Score {
		gameNumber += wins
	}
	return gameNumber
}

func (r *Room) completeRulesGame(winnerSeat int, reason string, concededSeat int) Result {
	gameNumber := r.rulesGameNumber()
	if len(r.Score) != len(r.Seats) {
		r.Score = make([]int, len(r.Seats))
	}
	if winnerSeat >= 0 {
		r.Score[winnerSeat]++
	} else if reason == protocol.GameResultRules {
		r.DrawnGames++
	}

	game := &GameState{
		Number: gameNumber, StartingSeat: -1, TurnOrder: []int{}, ActiveSeat: -1,
		CurrentPhase: protocol.GamePhaseEnd,
		Seats:        make([]PlayerGameState, len(r.Seats)),
		Stack:        []protocol.GameSharedCard{}, Revealed: []protocol.GameSharedCard{},
		Arrows: []protocol.GameArrow{}, Attachments: []protocol.GameAttachment{},
		CommanderDamage: make(map[string]map[int]int), Log: []protocol.GameLogEntry{},
		NextLogID: 1, NextTokenID: 1, NextCardCounterID: 1,
		Result: &protocol.GameResult{
			Reason: reason, WinnerSeat: winnerSeat,
			ConcededSeat: concededSeat, MatchFinished: true,
		},
	}
	for seatIndex, seat := range r.Seats {
		game.Seats[seatIndex] = PlayerGameState{
			Seat: seatIndex, DisplayName: seat.DisplayName,
			Eliminated: !seat.Occupied, CommanderTaxes: make(map[string]int),
		}
	}
	r.Game = game
	return Result{Broadcast: []protocol.Envelope{r.snapshotEnvelope()}}
}
