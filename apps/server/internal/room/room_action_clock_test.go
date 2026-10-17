// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"testing"
	"time"

	"hexproof/server/internal/protocol"
)

func TestConstructedDeckLockRejectsReplacement(t *testing.T) {
	r, err := NewWithRulesMode("LOCK1", "Constructed", protocol.FormatModern, protocol.MatchBO3,
		protocol.CardLoadBackground, protocol.RulesModeForge, 2, true, false,
		"Alice", "alice", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	deck := protocol.DeckSelect{Name: "Private deck", Format: protocol.FormatModern, DeckFormat: r.DeckFormat,
		Mainboard: []protocol.DeckCard{{Name: "Forest", Count: 60, SetCode: "TST", CollectorNumber: "1"}}}
	if _, err := r.SelectDeck("alice", deck); err != nil {
		t.Fatal(err)
	}
	if err := r.SealTournamentDeck("alice"); err != nil {
		t.Fatal(err)
	}
	deck = protocol.DeckSelect{Name: "Other", Format: protocol.FormatModern, DeckFormat: r.DeckFormat,
		Mainboard: []protocol.DeckCard{{Name: "Island", Count: 60, SetCode: "TST", CollectorNumber: "1"}}}
	if _, err := r.SelectDeck("alice", deck); err == nil || err.Error() != protocol.ErrTournamentForbidden {
		t.Fatalf("locked deck change = %v", err)
	}
	if !r.Snapshot().Seats[0].DeckLocked {
		t.Fatal("locked deck was not published")
	}
}

func TestActionClockChargesOnlyThePriorityPlayer(t *testing.T) {
	r := newRulesMatch(t, protocol.FormatModern)
	r.Phase = protocol.RoomPhaseStarted
	start := time.Date(2026, 9, 26, 2, 0, 0, 0, time.UTC)
	r.EnableActionClock(start)
	if expired := r.AdvanceActionClock(start, 0); expired != -1 {
		t.Fatalf("opening priority expired seat %d", expired)
	}
	later := start.Add(time.Minute)
	if expired := r.AdvanceActionClock(later, 1); expired != -1 {
		t.Fatalf("priority pass expired seat %d", expired)
	}
	remaining := r.actionClock.Remaining
	if remaining[0] != ActionClockDuration-time.Minute || remaining[1] != ActionClockDuration {
		t.Fatalf("clock remaining = %v", remaining)
	}
	timeout := later.Add(ActionClockDuration)
	if expired := r.AdvanceActionClock(timeout, 0); expired != 1 {
		t.Fatalf("expired seat = %d, want 1", expired)
	}
	result, err := r.ForfeitActionClock(1, timeout)
	if err != nil || r.Game == nil || r.Game.Result == nil || !r.Game.Result.MatchFinished ||
		r.Game.Result.Reason != protocol.GameResultTimeout || r.Game.Result.WinnerSeat != 0 ||
		r.Score[0] != 2 || r.Game.Number != 1 {
		t.Fatalf("timeout result err=%v game=%+v score=%v", err, r.Game, r.Score)
	}
	if result.Reply == nil || len(result.Broadcast) == 0 {
		t.Fatal("timeout did not publish the match result")
	}
}

func TestActionClockRepeatedObservationKeepsAbsoluteDeadline(t *testing.T) {
	r := newRulesMatch(t, protocol.FormatModern)
	r.Phase = protocol.RoomPhaseStarted
	start := time.Now()
	r.EnableActionClock(start)
	r.AdvanceActionClock(start, 0)
	want := start.Add(ActionClockDuration)
	for _, elapsed := range []time.Duration{time.Second, time.Minute, 24 * time.Minute} {
		now := start.Add(elapsed)
		if expired := r.AdvanceActionClock(now, 0); expired != -1 {
			t.Fatalf("early expiry: %d", expired)
		}
		if got := r.ActionClockDeadline(now.Add(time.Hour)); !got.Equal(want) {
			t.Fatalf("deadline moved with observation: got %v want %v", got, want)
		}
	}
	if expired := r.AdvanceActionClock(want, 0); expired != 0 {
		t.Fatalf("deadline did not expire running seat: %d", expired)
	}
}

func TestActionClockPausePreservesBudgetAndFreshMatchResets(t *testing.T) {
	r := newRulesMatch(t, protocol.FormatModern)
	r.Phase = protocol.RoomPhaseStarted
	start := time.Now()
	r.EnableActionClock(start)
	r.AdvanceActionClock(start, 0)
	r.AdvanceActionClock(start.Add(time.Minute), -1)
	paused := r.actionClock.Remaining[0]
	r.AdvanceActionClock(start.Add(time.Hour), 0)
	if r.actionClock.Remaining[0] != paused {
		t.Fatal("paused engine/sideboard time spent a player's budget")
	}
	r.Game = &GameState{Sideboard: &SideboardState{}}
	r.AdvanceActionClock(start.Add(time.Hour+time.Minute), 1)
	if r.actionClock.Running != -1 || r.actionClock.Remaining[0] != ActionClockDuration-2*time.Minute {
		t.Fatalf("sideboard did not pause cumulative budget: %+v", r.actionClock)
	}
	seq := r.ActionClockSeq()
	r.ResetActionClock(start.Add(2 * time.Hour))
	if r.actionClock.Running != -1 || r.actionClock.Remaining[0] != ActionClockDuration || r.ActionClockSeq() <= seq {
		t.Fatalf("fresh match kept budget or reused old sequence: %+v", r.actionClock)
	}
	r.ActionClockEnabled = false
	r.ResetActionClock(start.Add(3 * time.Hour))
	if r.ActionClockSeq() != 0 || r.Snapshot().ActionClockMs != nil {
		t.Fatal("disabled match exposed a clock")
	}
}

func TestActionClockProjectionChargesElapsedWithoutMutation(t *testing.T) {
	r := newRulesMatch(t, protocol.FormatModern)
	r.Phase = protocol.RoomPhaseStarted
	start := time.Now()
	r.EnableActionClock(start)
	r.AdvanceActionClock(start, 1)
	values := r.actionClockMillisecondsAt(start.Add(90 * time.Second))
	if values[0] != ActionClockDuration.Milliseconds() || values[1] != (ActionClockDuration-90*time.Second).Milliseconds() {
		t.Fatalf("stale projection budget: %v", values)
	}
	if r.actionClock.Remaining[1] != ActionClockDuration || !r.actionClock.Mark.Equal(start) {
		t.Fatal("projection mutated authoritative accounting")
	}
	values = r.actionClockMillisecondsAt(start.Add(time.Hour))
	if values[1] != 0 {
		t.Fatalf("expired projection was negative: %v", values)
	}
}

func TestActionClockRejectsUnsupportedTables(t *testing.T) {
	for _, format := range []string{protocol.FormatModern, protocol.FormatEDH} {
		seats := 2
		if format == protocol.FormatEDH {
			seats = 4
		}
		r, err := NewWithRulesMode("CLOCK", "Unsupported", format, protocol.MatchBO1, protocol.CardLoadBackground, protocol.RulesModeForge, seats, true, false, "Alice", "alice", time.Now())
		if err != nil {
			t.Fatal(err)
		}
		if format == protocol.FormatModern {
			r.RulesMode = protocol.RulesModeManual
		}
		r.EnableActionClock(time.Now())
		if r.ActionClockEnabled || r.ActionClockSeq() != 0 {
			t.Fatalf("unsupported %s table enabled a clock", format)
		}
	}
}
