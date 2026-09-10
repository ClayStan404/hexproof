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
	return r.completeRulesGame(winnerSeat, protocol.GameResultRules, -1, now), nil
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
			winnerSeat, protocol.GameResultConcede, concededSeat, now)
		matchFinished = r.Game.Result.MatchFinished
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
	if r.MatchMode == protocol.MatchBO3 && !r.canSideboard() {
		return newError(protocol.ErrGameSetupFailed)
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

func (r *Room) completeRulesGame(winnerSeat int, reason string, concededSeat int, now time.Time) Result {
	gameNumber := r.rulesGameNumber()
	if len(r.Score) != len(r.Seats) {
		r.Score = make([]int, len(r.Seats))
	}
	if winnerSeat >= 0 {
		r.Score[winnerSeat]++
	} else if reason == protocol.GameResultRules {
		r.DrawnGames++
	}

	matchFinished := r.MatchMode != protocol.MatchBO3 || winnerSeat >= 0 && r.Score[winnerSeat] >= 2
	game := r.rulesMetadataState()
	game.Number = gameNumber
	game.Result = &protocol.GameResult{
		Reason: reason, WinnerSeat: winnerSeat,
		ConcededSeat: concededSeat, MatchFinished: matchFinished,
	}
	r.Game = game
	result := Result{Broadcast: []protocol.Envelope{r.snapshotEnvelope()}, ProjectGame: true}
	if !matchFinished {
		previousLoser := -1
		if winnerSeat >= 0 {
			previousLoser = 1 - winnerSeat
		}
		r.beginSideboard(previousLoser, now.Add(sideboardDuration))
		result.SideboardDeadline = r.Game.Sideboard.Deadline
	}
	return result
}

// rulesMetadataState has no engine cards or actions. It is a projection-only
// shell while a game is live and becomes authoritative only for its result and
// pending registered-deck partition after Forge finishes that game.
func (r *Room) rulesMetadataState() *GameState {
	startingSeat := -1
	if r.RulesStartingSeat != nil {
		startingSeat = *r.RulesStartingSeat
	}
	game := &GameState{
		Number: r.rulesGameNumber(), StartingSeat: startingSeat, TurnOrder: []int{}, ActiveSeat: -1,
		CurrentPhase: protocol.GamePhaseEnd,
		Seats:        make([]PlayerGameState, len(r.Seats)),
		Stack:        []protocol.GameSharedCard{}, Revealed: []protocol.GameSharedCard{},
		Arrows: []protocol.GameArrow{}, Attachments: []protocol.GameAttachment{},
		CommanderDamage: make(map[string]map[int]int), Log: append([]protocol.GameLogEntry{}, r.RulesLog...),
		NextLogID: r.RulesNextLogID, NextTokenID: 1, NextCardCounterID: 1,
	}
	for seatIndex, seat := range r.Seats {
		game.Seats[seatIndex] = PlayerGameState{
			Seat: seatIndex, DisplayName: seat.DisplayName,
			Eliminated: !seat.Occupied, CommanderTaxes: make(map[string]int),
		}
	}
	return game
}

// RulesGameSnapshot reuses the ordinary match/sideboard metadata contract,
// without copying or reconstructing any live engine zones in the manual game.
func (r *Room) RulesGameSnapshot(connID string) (protocol.GameSnapshot, error) {
	if r.RulesMode != protocol.RulesModeForge {
		return protocol.GameSnapshot{}, newError(protocol.ErrGameNotStarted)
	}
	view := *r
	if view.Game == nil {
		view.Game = r.rulesMetadataState()
	}
	return view.GameSnapshot(connID)
}

func (r *Room) prepareNextRulesGame(startingSeat int) {
	r.Game = nil
	r.LoadID++
	r.RulesStartingSeat = nil
	if startingSeat >= 0 {
		r.RulesStartingSeat = &startingSeat
	}
}

// RestartRulesGame preserves the match score, game number, and original turn
// order. A fresh runtime session supplies all shuffled cards and opening hands.
func (r *Room) RestartRulesGame(connID string) (Result, error) {
	if r.RulesMode != protocol.RulesModeForge || r.Phase != protocol.RoomPhaseStarted || r.Game != nil {
		return Result{}, newError(protocol.ErrGameNotStarted)
	}
	if !r.IsHost(connID) {
		return Result{}, newError(protocol.ErrNotHost)
	}
	if r.RulesStartingSeat == nil {
		return Result{}, newError(protocol.ErrGameNotStarted)
	}
	r.prepareNextRulesGame(*r.RulesStartingSeat)
	reply, _ := protocol.NewEnvelope(protocol.TypeGameRestarted, protocol.GameRestarted{
		RoomID: r.ID, GameNumber: r.rulesGameNumber(), StartingSeat: *r.RulesStartingSeat,
	})
	return Result{Reply: &reply, Broadcast: []protocol.Envelope{
		reply.WithSeq(r.allocSeq()), r.snapshotEnvelope(),
	}, StartRulesGame: true}, nil
}
