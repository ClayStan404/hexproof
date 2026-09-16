// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"reflect"
	"testing"

	"hexproof/server/internal/protocol"
)

func assertTurnCounts(t *testing.T, r *Room, want []int) {
	t.Helper()
	got := make([]int, len(r.Game.Seats))
	for index, seat := range r.Game.Seats {
		got[index] = seat.TurnCount
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("turn counts = %v, want %v", got, want)
	}
}

func TestTurnCountsFollowTurnsAndSurviveReconnect(t *testing.T) {
	r := newStartedUtilityRoom(t, protocol.MatchBO3)
	if _, err := r.Join("observer", "Observer", true, ""); err != nil {
		t.Fatal(err)
	}
	if _, err := r.RestartGame("host-conn"); err != nil {
		t.Fatal(err)
	}
	assertTurnCounts(t, r, []int{0, 1})
	if _, err := r.NextTurn("host-conn"); err == nil {
		t.Fatal("inactive player advanced the turn")
	}
	if _, err := r.NextTurn("observer"); err == nil {
		t.Fatal("spectator advanced the turn")
	}
	if _, err := r.SetPhase("guest-conn", protocol.GameSetPhase{Phase: protocol.GamePhaseFirstMain}); err != nil {
		t.Fatal(err)
	}
	if _, err := r.Mulligan("guest-conn"); err != nil {
		t.Fatal(err)
	}
	assertTurnCounts(t, r, []int{0, 1})
	for _, connection := range []string{"guest-conn", "host-conn", "guest-conn"} {
		if _, err := r.NextTurn(connection); err != nil {
			t.Fatal(err)
		}
	}
	assertTurnCounts(t, r, []int{2, 2})
	if _, err := r.Reconnect("guest-conn", "guest-returned"); err != nil {
		t.Fatal(err)
	}
	for _, connection := range []string{"host-conn", "guest-returned", "observer"} {
		view, err := r.GameSnapshot(connection)
		if err != nil {
			t.Fatal(err)
		}
		for _, seat := range view.Seats {
			if seat.TurnCount != 2 {
				t.Fatalf("%s sees incorrect turn count: %+v", connection, seat)
			}
			if connection != r.Seats[seat.Seat].ConnectionID && len(seat.Hand) != 0 {
				t.Fatalf("%s sees another player's hand", connection)
			}
		}
	}
	if _, err := r.RestartGame("host-conn"); err != nil {
		t.Fatal(err)
	}
	assertTurnCounts(t, r, []int{0, 1})
	if _, err := r.NextTurn("guest-returned"); err != nil {
		t.Fatal(err)
	}
	if _, err := r.ConcedeAt("guest-returned", testNow); err != nil {
		t.Fatal(err)
	}
	assertTurnCounts(t, r, []int{1, 1})
}

func TestTurnCountsResetBetweenBO3Games(t *testing.T) {
	r := newStartedUtilityRoom(t, protocol.MatchBO3)
	r.Game.Seats[0].TurnCount = 5
	r.Game.Seats[1].TurnCount = 4
	if _, err := r.DeclareDrawAt("guest-conn", testNow); err != nil {
		t.Fatal(err)
	}
	assertTurnCounts(t, r, []int{5, 4})
	if _, err := r.completeSideboard(protocol.SideboardEndTimeout, false); err != nil {
		t.Fatal(err)
	}
	assertTurnCounts(t, r, []int{0, 1})
}

func TestTurnCountsFollowCommanderOrderAndSkipEliminatedSeats(t *testing.T) {
	r := newTestRoom(t, 4, true)
	for _, connection := range []string{"g1", "g2"} {
		if _, err := r.Join(connection, connection, false, ""); err != nil {
			t.Fatal(err)
		}
	}
	for index := 0; index < 3; index++ {
		deck := testDeck(protocol.FormatEDH)
		r.Seats[index].Deck = &deck
	}
	r.Phase = protocol.RoomPhaseStarted
	r.randomIndex = func(maximum int) (int, error) { return 0, nil }
	if err := r.setupGameNumberWithTurnOrder(1, 2, []int{2, 0, 1}); err != nil {
		t.Fatal(err)
	}
	assertTurnCounts(t, r, []int{0, 0, 1, 0})
	if _, err := r.ConcedeAt("g2", testNow); err != nil {
		t.Fatal(err)
	}
	assertTurnCounts(t, r, []int{1, 0, 1, 0})
	for _, connection := range []string{"host-conn", "g1"} {
		if _, err := r.NextTurn(connection); err != nil {
			t.Fatal(err)
		}
	}
	assertTurnCounts(t, r, []int{2, 1, 1, 0})
}
