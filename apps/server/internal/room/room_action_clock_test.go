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
		r.Score[0] != 2 {
		t.Fatalf("timeout result err=%v game=%+v score=%v", err, r.Game, r.Score)
	}
	if result.Reply == nil || len(result.Broadcast) == 0 {
		t.Fatal("timeout did not publish the match result")
	}
}
