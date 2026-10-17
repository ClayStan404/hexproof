// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"testing"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func TestStaleLibrarySearchKeepsWebSocketSessionUsable(t *testing.T) {
	srv, h := newTestServer(t)
	client := dial(t, srv)
	defer client.close()
	client.hello("Alice")
	_, roomID := client.createRoom("Library search", protocol.FormatModern, 2, true, "")
	client.recvType(protocol.TypeRoomSnapshot)
	operation, err := h.hub.lockRoomOperation(roomID)
	if err != nil {
		t.Fatal(err)
	}
	operation.mu.Lock()
	r := operation.room
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &room.GameState{Number: 1, NextLogID: 1, Seats: []room.PlayerGameState{
		{Seat: 0, DisplayName: "Alice", Library: []protocol.GameCard{{
			ID: "remaining", Name: "Remaining card", OwnerSeat: 0,
		}}},
		{Seat: 1, Eliminated: true},
	}}
	operation.mu.Unlock()
	operation.opMu.Unlock()

	search, _ := protocol.NewEnvelope(protocol.TypeGameSearchLibrary, protocol.GameSearchLibrary{
		CardIDs: []string{"remaining", "already-drawn"}, ToZone: protocol.LibraryDestinationHand,
	})
	search.ID = "stale-search"
	client.send(search)
	rejected := client.recvType(protocol.TypeError)
	var failure protocol.ErrorPayload
	if err := rejected.DecodePayload(&failure); err != nil ||
		rejected.ID != search.ID || failure.Code != protocol.ErrCardNotFound {
		t.Fatalf("stale search response = %+v error=%v", rejected, err)
	}

	count := 1
	draw, _ := protocol.NewEnvelope(protocol.TypeGameDraw, protocol.GameDraw{Count: &count})
	draw.ID = "draw-after-rejected-search"
	client.send(draw)
	drawn := client.recvType(protocol.TypeGameDrawn)
	if drawn.ID != draw.ID {
		t.Fatalf("draw response id = %q", drawn.ID)
	}
	view := client.recvType(protocol.TypeGameSnapshot)
	var snapshot protocol.GameSnapshot
	if err := view.DecodePayload(&snapshot); err != nil {
		t.Fatal(err)
	}
	if len(snapshot.Seats) == 0 || len(snapshot.Seats[0].Hand) != 1 ||
		snapshot.Seats[0].Hand[0].ID != "remaining" {
		t.Fatalf("rejected search damaged the library: %+v", snapshot.Seats)
	}
}
