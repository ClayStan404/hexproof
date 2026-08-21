// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"fmt"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestGameLogRetentionAndProjectionAreBounded(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{{
			Seat: 0, DisplayName: "Host",
		}},
		NextLogID: 1,
	}
	total := protocol.MaxRetainedGameLog + 25
	for index := 0; index < total; index++ {
		r.appendGameLog("test", 0, fmt.Sprintf("entry %d", index+1))
	}
	if len(r.Game.Log) != protocol.MaxRetainedGameLog ||
		r.Game.Log[0].ID != 26 ||
		r.Game.Log[len(r.Game.Log)-1].ID != int64(total) ||
		r.Game.NextLogID != int64(total+1) {
		t.Fatalf("retained log bounds = first=%+v last=%+v len=%d next=%d",
			r.Game.Log[0], r.Game.Log[len(r.Game.Log)-1],
			len(r.Game.Log), r.Game.NextLogID)
	}

	snapshot, err := r.GameSnapshot("host-conn")
	if err != nil {
		t.Fatalf("game snapshot: %v", err)
	}
	wantStart := int64(total - protocol.MaxProjectedGameLog + 1)
	if len(snapshot.Log) != protocol.MaxProjectedGameLog ||
		snapshot.LogStartID != wantStart || !snapshot.LogTruncated ||
		snapshot.Log[0].ID != wantStart ||
		snapshot.Log[len(snapshot.Log)-1].ID != int64(total) {
		t.Fatalf("projected log = start=%d truncated=%v first=%+v last=%+v len=%d",
			snapshot.LogStartID, snapshot.LogTruncated,
			snapshot.Log[0], snapshot.Log[len(snapshot.Log)-1],
			len(snapshot.Log))
	}
}

func TestEmptyGameLogProjectsNextIDWithoutTruncation(t *testing.T) {
	log, startID, truncated := projectGameLog(nil, 1)
	if len(log) != 0 || startID != 1 || truncated {
		t.Fatalf("empty projection = log=%v start=%d truncated=%v",
			log, startID, truncated)
	}
}
