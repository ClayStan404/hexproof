// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"reflect"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestGameLogWindowKeepsChronologyAndIndependentProjections(t *testing.T) {
	for _, mode := range []string{"manual", "rules live", "rules review"} {
		t.Run(mode, func(t *testing.T) {
			r := rulesLogTestRoom(t)
			if mode == "manual" {
				r.RulesMode = protocol.RulesModeManual
				r.Game = &GameState{NextLogID: 1}
			}
			appendEntry := func() {
				if mode == "manual" {
					r.appendGameLog("chat", 0, "Public message.")
				} else {
					r.AppendRulesLog("chat", 0, "Public message.")
				}
			}
			currentLog := func() []protocol.GameLogEntry {
				if mode == "manual" {
					return r.Game.Log
				}
				return r.RulesLog
			}
			project := func() protocol.GameSnapshot {
				t.Helper()
				var snapshot protocol.GameSnapshot
				var err error
				if mode == "manual" {
					snapshot, err = r.GameSnapshot("alice")
				} else {
					snapshot, err = r.RulesGameSnapshot("alice")
				}
				if err != nil {
					t.Fatal(err)
				}
				return snapshot
			}
			for range protocol.MaxRetainedGameLog {
				appendEntry()
			}
			if mode == "rules review" {
				if _, err := r.CompleteRulesGame(0, testNow); err != nil {
					t.Fatal(err)
				}
			}
			prior := project()
			priorLog := append([]protocol.GameLogEntry{}, prior.Log...)
			// Cross several allocation windows and evict every original entry.
			added := protocol.MaxRetainedGameLog + 2*gameLogAppendReserve
			for range added {
				appendEntry()
				if len(currentLog()) != protocol.MaxRetainedGameLog {
					t.Fatalf("retention length = %d", len(currentLog()))
				}
			}
			log := currentLog()
			for index, entry := range log {
				if entry.ID != int64(added+index+1) || entry.Text != "Public message." {
					t.Fatalf("chronology lost at %d: %+v", index, entry)
				}
			}
			if !reflect.DeepEqual(prior.Log, priorLog) {
				t.Fatal("later journal changes mutated an earlier projection")
			}
			total := int64(added + protocol.MaxRetainedGameLog)
			if mode == "manual" && r.Game.NextLogID != total+1 {
				t.Fatalf("next log ID = %d, want %d", r.Game.NextLogID, total+1)
			}
			latest := project()
			wantStart := total - protocol.MaxProjectedGameLog + 1
			if len(latest.Log) != protocol.MaxProjectedGameLog || latest.LogStartID != wantStart ||
				!latest.LogTruncated || latest.Log[0].ID != wantStart ||
				latest.Log[len(latest.Log)-1].ID != total {
				t.Fatalf("projected tail = length %d, start %d, truncated %v",
					len(latest.Log), latest.LogStartID, latest.LogTruncated)
			}
			if mode != "manual" {
				projected, start, truncated := r.RulesLogProjection()
				if start != wantStart || !truncated || !reflect.DeepEqual(projected, latest.Log) {
					t.Fatal("direct rules log projection differs from the snapshot tail")
				}
				projected[0].Text = "changed direct projection"
				if log[len(log)-protocol.MaxProjectedGameLog].Text != "Public message." {
					t.Fatal("direct rules log projection aliases the live journal")
				}
			}
			latest.Log[0].Text = "changed projection"
			if log[len(log)-protocol.MaxProjectedGameLog].Text != "Public message." {
				t.Fatal("projection mutation reached the live journal")
			}
			if mode == "rules review" {
				if !reflect.DeepEqual(r.Game.Log, r.RulesLog) || r.Game.NextLogID != r.RulesNextLogID {
					t.Fatal("review shell diverged from the authoritative public journal")
				}
				r.Game.Log[0].Text = "changed shell"
				if r.RulesLog[0].Text != "Public message." {
					t.Fatal("review shell shares the authoritative journal's backing array")
				}
			}
		})
	}
}

func TestGameLogWindowReleasesDiscardedEntries(t *testing.T) {
	log := make([]protocol.GameLogEntry, protocol.MaxRetainedGameLog, protocol.MaxRetainedGameLog+gameLogAppendReserve)
	for index := range log {
		log[index] = protocol.GameLogEntry{ID: int64(index + 1), Text: "old text"}
	}
	backing := log
	log = appendRetainedGameLog(log, protocol.GameLogEntry{ID: protocol.MaxRetainedGameLog + 1, Text: "new text"})
	if backing[0] != (protocol.GameLogEntry{}) {
		t.Fatal("evicted entry still retains strings in the backing array")
	}
	if log[0].ID != 2 || log[len(log)-1].Text != "new text" {
		t.Fatal("eviction changed retained entries")
	}
}

func TestRulesLogShellResynchronizesAfterLifecycleChanges(t *testing.T) {
	r := rulesLogTestRoom(t)
	for range protocol.MaxRetainedGameLog + gameLogAppendReserve {
		r.AppendRulesLog("chat", 0, "Original match.")
	}
	if _, err := r.CompleteRulesGame(0, testNow); err != nil {
		t.Fatal(err)
	}
	assertSynchronized := func() {
		t.Helper()
		if r.Game.NextLogID != r.RulesNextLogID || !reflect.DeepEqual(r.Game.Log, r.RulesLog) {
			t.Fatal("replacement shell retained stale public history")
		}
	}
	// Shell creation copies the journal at the same length and next ID.
	r.Game = r.rulesMetadataState()
	r.AppendRulesLog("chat", 0, "Replacement shell.")
	assertSynchronized()
	// Departure handling can append to the manual metadata shell independently.
	r.appendGameLog("departure", 1, "Manual terminal metadata.")
	r.AppendRulesLog("chat", 0, "Authoritative rules chat.")
	assertSynchronized()
	// Reset must replace old content even when a later match reaches the same IDs.
	r.ResetRulesLog()
	for range protocol.MaxRetainedGameLog + gameLogAppendReserve {
		r.AppendRulesLog("chat", 0, "New match.")
	}
	assertSynchronized()
	for _, entry := range r.Game.Log {
		if entry.Text != "New match." {
			t.Fatalf("new match retained old content: %+v", entry)
		}
	}
	before := r.RulesNextLogID
	r.prepareNextRulesGame(1)
	r.AppendRulesLog("rules_start", 1, "Next game.")
	if r.Game != nil || r.RulesNextLogID != before+1 {
		t.Fatal("next game recreated a shell or reset public journal IDs")
	}
}

func TestEmptyGameLogProjectsNextIDWithoutTruncation(t *testing.T) {
	log, startID, truncated := projectGameLog(nil, 1)
	if len(log) != 0 || startID != 1 || truncated {
		t.Fatalf("empty projection = log=%v start=%d truncated=%v",
			log, startID, truncated)
	}
}
