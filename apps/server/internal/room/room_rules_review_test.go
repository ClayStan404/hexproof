// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"testing"
	"time"

	"hexproof/server/internal/protocol"
)

func TestRulesReviewNeverCrossesGameBoundary(t *testing.T) {
	r := rulesLogTestRoom(t)
	snapshot := protocol.RulesGameSnapshot{RoomID: r.ID, GameID: "first", GameOver: true}
	r.RecordRulesReview(snapshot)
	if _, ok := r.RulesReviewProjection(1); ok {
		t.Fatal("review was exposed before the terminal result was committed")
	}
	if _, err := r.CompleteRulesGame(1, time.Now()); err != nil {
		t.Fatal(err)
	}
	if _, ok := r.RulesReviewProjection(2); !ok {
		t.Fatal("completed public review was lost")
	}
	r.prepareNextRulesGame(0)
	if _, ok := r.RulesReviewProjection(3); ok {
		t.Fatal("old review remained available during the next game")
	}
	if _, err := r.CompleteRulesGame(0, time.Now()); err != nil {
		t.Fatal(err)
	}
	if _, ok := r.RulesReviewProjection(4); ok {
		t.Fatal("missing next-game publication resurrected the previous board")
	}
}
