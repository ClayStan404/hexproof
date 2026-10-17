// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func timedTestRoom(t *testing.T, budget time.Duration) (*Handler, *room.Room) {
	t.Helper()
	h := NewHandler()
	t.Cleanup(func() { _ = h.Close() })
	r, _ := newWaitingSupervisedRoom(t, h, "Clock", protocol.RulesModeForge)
	entry, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		t.Fatal(err)
	}
	entry.mu.Lock()
	r.Phase = protocol.RoomPhaseStarted
	start := time.Now().Add(-room.ActionClockDuration + budget)
	r.EnableActionClock(start)
	r.AdvanceActionClock(start, 0)
	entry.mu.Unlock()
	entry.opMu.Unlock()
	return h, r
}

func waitForClockResult(t *testing.T, h *Handler, r *room.Room) {
	t.Helper()
	entry := h.hub.roomEntryFor(r.ID)
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		entry.mu.Lock()
		finished := r.Game != nil && r.Game.Result != nil && r.Game.Result.MatchFinished
		entry.mu.Unlock()
		if finished {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatal("clock did not finish the match without another player action")
}

func TestActionClockAutomaticallyExpiresWithoutMoreInput(t *testing.T) {
	h, r := timedTestRoom(t, 80*time.Millisecond)
	h.observeActionClock(r, 0)
	waitForClockResult(t, h, r)
	entry, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		t.Fatal(err)
	}
	defer entry.opMu.Unlock()
	entry.mu.Lock()
	if r.Game.Result.Reason != protocol.GameResultTimeout || r.Game.Result.WinnerSeat != 1 || r.Score[1] != 1 {
		t.Fatalf("wrong automatic timeout: %+v score %v", r.Game.Result, r.Score)
	}
	seq := r.ActionClockSeq()
	entry.mu.Unlock()
	if h.observeActionClockLocked(r, 0) {
		t.Fatal("finished match resumed its clock")
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()
	if r.Score[1] != 1 || r.ActionClockSeq() <= seq || r.Snapshot().ActionClockRunning != nil {
		t.Fatal("repeated observation changed the result or started another timer")
	}
}

func TestActionClockStaleAndEarlyTimersCannotForfeit(t *testing.T) {
	h, r := timedTestRoom(t, time.Minute)
	h.observeActionClock(r, 0)
	h.actionClockMu.Lock()
	old := h.actionClockTimers[r.ID]
	h.actionClockMu.Unlock()
	entry := h.hub.roomEntryFor(r.ID)
	entry.mu.Lock()
	seq := r.ActionClockSeq()
	deadline := r.ActionClockDeadline(time.Now())
	entry.mu.Unlock()
	h.expireActionClock(r.ID, seq, old)
	h.actionClockMu.Lock()
	current := h.actionClockTimers[r.ID]
	h.actionClockMu.Unlock()
	if current == nil || current == old {
		t.Fatal("early callback discarded the true deadline")
	}
	h.expireActionClock(r.ID, seq, old)
	entry.mu.Lock()
	if r.Game != nil || !r.ActionClockDeadline(time.Now()).Equal(deadline) {
		t.Fatal("early/stale callback changed the game or deadline")
	}
	entry.mu.Unlock()
	h.actionClockMu.Lock()
	defer h.actionClockMu.Unlock()
	if h.actionClockTimers[r.ID] != current {
		t.Fatal("old timer replaced the current timer")
	}
}

func TestActionClockNewMatchInvalidatesOldTimer(t *testing.T) {
	h, r := timedTestRoom(t, time.Minute)
	h.observeActionClock(r, 0)
	h.actionClockMu.Lock()
	old := h.actionClockTimers[r.ID]
	h.actionClockMu.Unlock()
	entry, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		t.Fatal(err)
	}
	entry.mu.Lock()
	seq := r.ActionClockSeq()
	r.ResetActionClock(time.Now())
	entry.mu.Unlock()
	entry.opMu.Unlock()
	h.expireActionClock(r.ID, seq, old)
	entry.mu.Lock()
	defer entry.mu.Unlock()
	if r.Game != nil || r.Snapshot().ActionClockRunning != nil || r.Snapshot().ActionClockMs[0] != room.ActionClockDuration.Milliseconds() {
		t.Fatal("timer from previous match consumed the new match budget")
	}
}
