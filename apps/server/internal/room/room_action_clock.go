// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"time"

	"hexproof/server/internal/protocol"
)

// ActionClockDuration is the constructed Forge match action time for one player.
const ActionClockDuration = 25 * time.Minute

// ActionClock is a chess clock. Only the player who currently has priority
// spends time. The first player to reach zero loses the match.
type ActionClock struct {
	Remaining []time.Duration
	Running   int
	Mark      time.Time
	Seq       uint64
}

func (r *Room) EnableActionClock(now time.Time) {
	remaining := make([]time.Duration, len(r.Seats))
	for index := range remaining {
		remaining[index] = ActionClockDuration
	}
	r.actionClock = &ActionClock{Remaining: remaining, Running: -1, Mark: now, Seq: 1}
}

func (r *Room) actionClockMilliseconds() []int64 {
	if r.actionClock == nil {
		return nil
	}
	values := make([]int64, len(r.actionClock.Remaining))
	for index, remaining := range r.actionClock.Remaining {
		if remaining < 0 {
			remaining = 0
		}
		values[index] = remaining.Milliseconds()
	}
	return values
}

func (r *Room) actionClockRunning() *int {
	if r.actionClock == nil || r.actionClock.Running < 0 {
		return nil
	}
	seat := r.actionClock.Running
	return &seat
}

func (r *Room) ActionClockSeq() uint64 {
	if r.actionClock == nil {
		return 0
	}
	return r.actionClock.Seq
}

// AdvanceActionClock charges elapsed time to the running player and then
// starts the supplied priority seat. A negative seat pauses the clock.
// The returned seat is non-negative when that player has just run out of time.
func (r *Room) AdvanceActionClock(now time.Time, prioritySeat int) int {
	clock := r.actionClock
	if clock == nil || now.IsZero() {
		return -1
	}
	if r.Game != nil && r.Game.Result != nil && r.Game.Result.MatchFinished {
		clock.Running = -1
		clock.Mark = now
		clock.Seq++
		return -1
	}
	expired := -1
	if !clock.Mark.IsZero() && clock.Running >= 0 && clock.Running < len(clock.Remaining) {
		elapsed := now.Sub(clock.Mark)
		if elapsed > 0 {
			clock.Remaining[clock.Running] -= elapsed
		}
		if clock.Remaining[clock.Running] <= 0 {
			clock.Remaining[clock.Running] = 0
			expired = clock.Running
		}
	}
	clock.Mark = now
	clock.Seq++
	if expired >= 0 || prioritySeat < 0 || prioritySeat >= len(clock.Remaining) {
		clock.Running = -1
		return expired
	}
	clock.Running = prioritySeat
	return -1
}

func (r *Room) ActionClockDeadline(now time.Time) time.Time {
	clock := r.actionClock
	if clock == nil || clock.Running < 0 || clock.Running >= len(clock.Remaining) {
		return time.Time{}
	}
	return now.Add(clock.Remaining[clock.Running])
}

// SealTournamentDeck freezes the seat's current constructed deck for later rounds.
func (r *Room) SealTournamentDeck(connID string) error {
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return err
	}
	if r.Seats[seat].Deck == nil {
		return newError(protocol.ErrDeckRequired)
	}
	r.Seats[seat].TournamentDeckLocked = true
	return nil
}

// ForfeitActionClock ends the match in favor of the other player.
func (r *Room) ForfeitActionClock(seat int, now time.Time) (Result, error) {
	if r.actionClock == nil || r.RulesMode != protocol.RulesModeForge ||
		r.Phase != protocol.RoomPhaseStarted || now.IsZero() ||
		seat < 0 || seat >= len(r.Seats) || !r.Seats[seat].Occupied || len(r.Seats) != 2 {
		return Result{}, newError(protocol.ErrGameNotStarted)
	}
	if r.Game != nil && r.Game.Result != nil && r.Game.Result.MatchFinished {
		return Result{}, newError(protocol.ErrGameFinished)
	}
	winner := 1 - seat
	needed := 1
	if r.MatchMode == protocol.MatchBO3 {
		needed = 2
	}
	if len(r.Score) != len(r.Seats) {
		r.Score = make([]int, len(r.Seats))
	}
	if r.Score[winner] < needed {
		r.Score[winner] = needed
	}
	if r.Score[seat] >= needed {
		r.Score[seat] = needed - 1
	}
	r.actionClock.Running = -1
	r.actionClock.Remaining[seat] = 0
	r.actionClock.Seq++
	game := r.rulesMetadataState()
	game.Result = &protocol.GameResult{
		Reason: protocol.GameResultTimeout, WinnerSeat: winner,
		ConcededSeat: seat, MatchFinished: true,
	}
	r.Game = game
	reply, _ := protocol.NewEnvelope(protocol.TypeGameConceded, protocol.GameConceded{
		RoomID: r.ID, GameNumber: game.Number, ConcededSeat: seat, WinnerSeat: winner,
		Score: append([]int{}, r.Score...), MatchFinished: true,
	})
	return Result{Reply: &reply, Broadcast: []protocol.Envelope{
		reply.WithSeq(r.allocSeq()), r.snapshotEnvelope(),
	}, ProjectGame: true}, nil
}
