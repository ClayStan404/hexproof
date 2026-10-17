// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"testing"
	"time"

	"hexproof/server/internal/protocol"
)

func TestActionClockSetupFailureAndNewMatchResetBudget(t *testing.T) {
	r := newRulesMatch(t, protocol.FormatModern)
	r.EnableActionClock(testNow)
	r.AdvanceActionClock(testNow, 0)
	r.AdvanceActionClock(testNow.Add(time.Minute), 1)
	previousSeq := r.ActionClockSeq()
	r.ResetRulesStartFailure()
	if r.Phase != protocol.RoomPhaseWaiting || !r.ActionClockEnabled ||
		r.actionClock.Running != -1 || r.actionClock.Remaining[0] != ActionClockDuration ||
		r.ActionClockSeq() <= previousSeq {
		t.Fatal("aborted game retained its running clock or spent budget")
	}
	// A new match must establish its own budget even if the prior waiting state
	// retained spent time from an interrupted game.
	r.actionClock.Remaining[0] = time.Second
	for _, connID := range []string{"alice", "bob"} {
		if _, err := r.SetReady(connID, true); err != nil {
			t.Fatal(err)
		}
	}
	if r.Phase != protocol.RoomPhaseStarted || r.actionClock.Running != -1 ||
		r.actionClock.Remaining[0] != ActionClockDuration || r.actionClock.Remaining[1] != ActionClockDuration {
		t.Fatal("new match inherited the previous match's action time")
	}
}

func TestActionClockReturnToRoomResetsPausedBudget(t *testing.T) {
	r := newRulesMatch(t, protocol.FormatModern)
	r.MatchMode = protocol.MatchBO1
	r.EnableActionClock(testNow)
	r.AdvanceActionClock(testNow, 0)
	r.AdvanceActionClock(testNow.Add(time.Minute), -1)
	previousSeq := r.ActionClockSeq()
	if _, err := r.CompleteRulesGame(0, testNow.Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	if _, err := r.ReturnToRoom("alice"); err != nil {
		t.Fatal(err)
	}
	if !r.ActionClockEnabled || r.actionClock.Running != -1 ||
		r.actionClock.Remaining[0] != ActionClockDuration || r.ActionClockSeq() <= previousSeq {
		t.Fatal("returning to the room kept the completed match's action time")
	}
}
