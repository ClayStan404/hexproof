// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"reflect"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestCommanderTurnOrderUsesRollsAndTieBreaks(t *testing.T) {
	r := &Room{}
	randomValues := []int{17, 4, 17, 3, 14}
	r.randomIndex = func(maximum int) (int, error) {
		if maximum != commanderOpeningRollSides || len(randomValues) == 0 {
			t.Fatalf("unexpected random request: maximum=%d remaining=%v",
				maximum, randomValues)
		}
		value := randomValues[0]
		randomValues = randomValues[1:]
		return value, nil
	}

	order, rounds, err := r.rollCommanderTurnOrder([]int{0, 1, 2})
	if err != nil {
		t.Fatalf("roll commander turn order: %v", err)
	}
	if !reflect.DeepEqual(order, []int{2, 0, 1}) {
		t.Fatalf("turn order = %v, want [2 0 1]", order)
	}
	if len(rounds) != 2 || rounds[0].TieBreak || !rounds[1].TieBreak ||
		!reflect.DeepEqual(rounds[0].Values, []int{18, 5, 18}) ||
		!reflect.DeepEqual(rounds[1].Seats, []int{0, 2}) ||
		!reflect.DeepEqual(rounds[1].Values, []int{4, 15}) {
		t.Fatalf("roll rounds = %+v", rounds)
	}
}

func TestNextActiveSeatFollowsTurnOrderAndSkipsEliminatedSeats(t *testing.T) {
	r := &Room{Game: &GameState{
		TurnOrder: []int{2, 0, 3, 1},
		Seats:     make([]PlayerGameState, 4),
	}}
	if next := r.nextActiveSeat(2); next != 0 {
		t.Fatalf("next active seat after 2 = %d, want 0", next)
	}
	r.Game.Seats[0].Eliminated = true
	if next := r.nextActiveSeat(2); next != 3 {
		t.Fatalf("next active seat after eliminated seat 0 = %d, want 3", next)
	}
	r.Game.Seats[3].Eliminated = true
	if next := r.nextActiveSeat(2); next != 1 {
		t.Fatalf("next active seat after eliminated seats = %d, want 1", next)
	}
}

func TestRestartGamePreservesCommanderTurnOrder(t *testing.T) {
	r := newTestRoom(t, 4, true)
	for index, connID := range []string{"guest-1", "guest-2"} {
		if _, err := r.Join(connID, "Guest "+string(rune('1'+index)), false, ""); err != nil {
			t.Fatalf("join %s: %v", connID, err)
		}
	}
	for index := 0; index < 3; index++ {
		deck := testDeck(protocol.FormatEDH)
		r.Seats[index].Deck = &deck
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number:       1,
		StartingSeat: 2,
		TurnOrder:    []int{2, 0, 1},
		ActiveSeat:   0,
		Seats: []PlayerGameState{
			{Seat: 0, DisplayName: "Host"},
			{Seat: 1, DisplayName: "Guest 1"},
			{Seat: 2, DisplayName: "Guest 2"},
			{Seat: 3, Eliminated: true},
		},
	}
	r.randomIndex = func(maximum int) (int, error) { return 0, nil }

	if _, err := r.RestartGame("host-conn"); err != nil {
		t.Fatalf("restart commander game: %v", err)
	}
	if !reflect.DeepEqual(r.Game.TurnOrder, []int{2, 0, 1}) ||
		r.Game.StartingSeat != 2 || r.Game.ActiveSeat != 2 {
		t.Fatalf("restarted order/start = %v/%d/%d",
			r.Game.TurnOrder, r.Game.StartingSeat, r.Game.ActiveSeat)
	}
	if len(r.Game.Log) == 0 || r.Game.Log[0].Kind != "restart" ||
		!strings.Contains(r.Game.Log[0].Text, "restarted Game 1") {
		t.Fatalf("restart log = %+v", r.Game.Log)
	}
}
