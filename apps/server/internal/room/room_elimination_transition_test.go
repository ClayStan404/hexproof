// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"fmt"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestCommanderEliminationClearsUnanswerableHoldAndExpiredTurnState(t *testing.T) {
	for _, departure := range []string{"concede", "leave", "kick", "expiry"} {
		for _, active := range []bool{false, true} {
			t.Run(fmt.Sprintf("%s/active=%t", departure, active), func(t *testing.T) {
				r := newTestRoom(t, 4, true)
				for _, connection := range []string{"g1", "g2"} {
					if _, err := r.Join(connection, connection, false, ""); err != nil {
						t.Fatal(err)
					}
				}
				if _, err := r.Join("observer", "Observer", true, ""); err != nil {
					t.Fatal(err)
				}
				r.Phase = protocol.RoomPhaseStarted
				r.Game = &GameState{
					Number: 1, ActiveSeat: 0, TurnOrder: []int{0, 1, 2},
					CurrentPhase: protocol.GamePhaseDeclareBlockers, LandPlaysThisTurn: 2,
					NextLogID: 1,
					Arrows:    []protocol.GameArrow{{SourceCardID: "previous-turn", Kind: protocol.ArrowKindAttack}},
					Seats: []PlayerGameState{
						{Seat: 0, DisplayName: "Host", ResponseStatus: protocol.ResponseStatusHold},
						{Seat: 1, DisplayName: "g1", ResponseStatus: protocol.ResponseStatusHold},
						{Seat: 2, DisplayName: "g2", ResponseStatus: protocol.ResponseStatusPass},
						{Seat: 3, Eliminated: true},
					},
				}
				if active {
					r.Game.ActiveSeat = 1
				}
				var err error
				switch departure {
				case "concede":
					_, err = r.ConcedeAt("g1", testNow)
				case "leave":
					_, err = r.Leave("g1")
				case "kick":
					seat := 1
					_, err = r.Kick("host-conn", &seat, nil)
				case "expiry":
					_, _, err = r.ExpireDisconnected("g1")
				}
				if err != nil {
					t.Fatal(err)
				}
				if !r.Game.Seats[1].Eliminated || r.Game.Seats[1].ResponseStatus != "" {
					t.Fatalf("eliminated player retained an unanswerable signal: %+v", r.Game.Seats[1])
				}
				if active {
					if r.Game.ActiveSeat != 2 || r.Game.CurrentPhase != protocol.GamePhaseUntap ||
						r.Game.LandPlaysThisTurn != 0 || len(r.Game.Arrows) != 0 ||
						r.Game.Seats[0].ResponseStatus != "" {
						t.Fatalf("new turn retained old coordination state: %+v", r.Game)
					}
				} else if r.Game.ActiveSeat != 0 ||
					r.Game.CurrentPhase != protocol.GamePhaseDeclareBlockers ||
					r.Game.LandPlaysThisTurn != 2 || len(r.Game.Arrows) != 1 ||
					r.Game.Seats[0].ResponseStatus != protocol.ResponseStatusHold {
					t.Fatalf("non-active elimination changed the ongoing turn: %+v", r.Game)
				}
				for _, viewer := range []string{"host-conn", "g2", "observer"} {
					view, err := r.GameSnapshot(viewer)
					if err != nil || view.Seats[1].ResponseStatus != "" {
						t.Fatalf("stale eliminated signal for %s: %+v, %v", viewer, view, err)
					}
				}
			})
		}
	}
}
