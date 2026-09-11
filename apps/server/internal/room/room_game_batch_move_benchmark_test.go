// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"fmt"
	"testing"

	"hexproof/server/internal/protocol"
)

func BenchmarkBatchLibraryTop(b *testing.B) {
	for _, count := range []int{100, 1000} {
		b.Run(fmt.Sprint(count), func(b *testing.B) {
			r, err := New("BENCH1", "Batch", protocol.FormatModern, protocol.MatchBO1,
				protocol.CardLoadBackground, 2, true, false, "Host", "host-conn", testNow)
			if err != nil {
				b.Fatal(err)
			}
			r.Phase = protocol.RoomPhaseStarted
			r.Game = &GameState{Number: 1, Seats: make([]PlayerGameState, 2)}
			library := make([]protocol.GameCard, count)
			graveyard := make([]protocol.GameCard, count)
			ids := make([]string, count)
			for i := range count {
				library[i] = protocol.GameCard{ID: fmt.Sprintf("library-%d", i), OwnerSeat: 0}
				ids[i] = fmt.Sprintf("grave-%d", i)
				graveyard[i] = protocol.GameCard{ID: ids[i], OwnerSeat: 0}
			}
			request := protocol.GameMoveCards{CardIDs: ids, FromZone: protocol.ZoneGraveyard, ToZone: protocol.ZoneLibrary, LibraryPlacement: "top"}
			b.ReportAllocs()
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				r.Game.Seats[0] = PlayerGameState{Seat: 0, DisplayName: "Host", Library: append([]protocol.GameCard(nil), library...), Graveyard: graveyard}
				r.Game.Log = nil
				r.Game.NextLogID = 1
				if _, err := r.MoveCards("host-conn", request); err != nil {
					b.Fatal(err)
				}
			}
		})
	}
}
