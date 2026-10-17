// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"reflect"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func TestRetainedLogWindowIsIndependentDuringLaterAppends(t *testing.T) {
	for _, mode := range []string{"manual", "rules live", "rules completed"} {
		t.Run(mode, func(t *testing.T) {
			now := time.Now().UTC()
			store, err := newRetentionStore(t.TempDir(), time.Hour, 8, 8<<20, now)
			if err != nil {
				t.Fatal(err)
			}
			rulesMode := protocol.RulesModeForge
			if mode == "manual" {
				rulesMode = protocol.RulesModeManual
			}
			r, err := room.NewWithRulesMode("WINDOW", "Public journal", protocol.FormatModern,
				protocol.MatchBO1, protocol.CardLoadBackground, rulesMode, 2, false, false,
				"Alice", "alice", now)
			if err != nil {
				t.Fatal(err)
			}
			r.Seats[1] = room.Seat{Occupied: true, DisplayName: "Bob", ConnectionID: "bob"}
			r.Phase = protocol.RoomPhaseStarted
			if mode == "manual" {
				r.Game = &room.GameState{Number: 1, NextLogID: 1,
					Seats: []room.PlayerGameState{{Seat: 0, DisplayName: "Alice"}, {Seat: 1, DisplayName: "Bob"}}}
			}
			appendPublic := func(message string) {
				t.Helper()
				if mode == "manual" {
					if _, err := r.Say("alice", protocol.GameSay{Message: message}); err != nil {
						t.Fatal(err)
					}
				} else {
					r.AppendRulesLog("chat", 0, message)
				}
			}
			for range protocol.MaxRetainedGameLog + 25 {
				appendPublic("Before capture.")
			}
			if mode == "rules completed" {
				if _, err := r.CompleteRulesGame(0, now); err != nil {
					t.Fatal(err)
				}
			}
			record := store.snapshot(r, now)
			if record == nil || len(record.Game.Log) != protocol.MaxRetainedGameLog {
				t.Fatal("missing bounded capture")
			}
			wantLog := append([]protocol.GameLogEntry{}, record.Game.Log...)
			// The server encodes archives after releasing the room operation lock.
			// Exercise that ownership boundary while the live window evicts entries.
			saved := make(chan error, 1)
			go func() { saved <- store.saveSnapshot(record) }()
			for range 2 * protocol.MaxRetainedGameLog {
				appendPublic("After capture.")
			}
			if err := <-saved; err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(record.Game.Log, wantLog) {
				t.Fatal("later log eviction changed an existing retained snapshot")
			}
			replays, total, err := store.list(now, 0, 8)
			if err != nil || total != 1 {
				t.Fatalf("archive list: total=%d err=%v", total, err)
			}
			loaded, err := store.load(replays[0].ReplayID, now)
			if err != nil || !reflect.DeepEqual(loaded.Log, wantLog) {
				t.Fatalf("persisted public log changed: err=%v", err)
			}
		})
	}
}
