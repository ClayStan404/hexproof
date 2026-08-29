// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestPlayLandIsAtomicAdvisoryAndTurnScoped(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("guest-conn", "Guest", false, ""); err != nil {
		t.Fatalf("join guest: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1, StartingSeat: 0, ActiveSeat: 0,
		CurrentPhase: protocol.GamePhaseFirstMain,
		Seats: []PlayerGameState{
			{
				Seat: 0, DisplayName: "Host", Life: 20,
				Hand: []protocol.GameCard{
					{ID: "s0-land", Name: "Forest", TypeLine: "Basic Land — Forest", OwnerSeat: 0},
					{ID: "s0-spell", Name: "Growth Spiral", TypeLine: "Instant", OwnerSeat: 0},
				},
				Battlefield: []protocol.GameCard{},
			},
			{Seat: 1, DisplayName: "Guest", Life: 20},
		},
		Stack: []protocol.GameSharedCard{}, Log: []protocol.GameLogEntry{},
		NextLogID: 1,
	}
	position := &protocol.CardPosition{X: 0.4, Y: 0.9}

	result, err := r.PlayLand("host-conn", protocol.GamePlayLand{
		CardID: "s0-land", Position: position,
	})
	if err != nil {
		t.Fatalf("play first land: %v", err)
	}
	if result.Reply == nil || result.Reply.Type != protocol.TypeGameLandPlayed ||
		!result.ProjectGame || r.Game.LandPlaysThisTurn != 1 ||
		len(r.Game.Seats[0].Hand) != 1 || len(r.Game.Seats[0].Battlefield) != 1 {
		t.Fatalf("first land result/state = %+v / %+v", result, r.Game)
	}
	if strings.Contains(string(result.Reply.Payload), "Forest") {
		t.Fatalf("land acknowledgement leaked private hand name: %s", result.Reply.Payload)
	}
	for _, viewer := range []string{"host-conn", "guest-conn"} {
		snapshot, snapshotErr := r.GameSnapshot(viewer)
		if snapshotErr != nil || snapshot.LandPlaysThisTurn != 1 {
			t.Fatalf("%s projected count = %d, err %v",
				viewer, snapshot.LandPlaysThisTurn, snapshotErr)
		}
	}
	played := r.Game.Seats[0].Battlefield[0]
	if played.ID != "s0-land" || played.Position == nil ||
		played.Position.X != position.X || played.Position.Y != position.Y {
		t.Fatalf("played land = %+v", played)
	}

	// Printed type and the ordinary one-land allowance are advisory. A player
	// may explicitly continue for a card effect or table agreement, including
	// with unusual phase and stack coordination state.
	r.Game.CurrentPhase = protocol.GamePhaseUpkeep
	r.Game.Stack = []protocol.GameSharedCard{{
		GameCard: protocol.GameCard{ID: "stack-1", Name: "Pending spell", OwnerSeat: 0},
	}}
	if _, err := r.PlayLand("host-conn", protocol.GamePlayLand{
		CardID: "s0-spell", Position: position,
	}); err != nil {
		t.Fatalf("advisory second/non-land play: %v", err)
	}
	if r.Game.LandPlaysThisTurn != 2 || len(r.Game.Seats[0].Hand) != 0 ||
		len(r.Game.Seats[0].Battlefield) != 2 {
		t.Fatalf("advisory play state = %+v", r.Game)
	}

	if _, err := r.SetLandPlayCount("host-conn",
		protocol.GameSetLandPlayCount{Value: 1}); err != nil {
		t.Fatalf("correct count: %v", err)
	}
	if r.Game.LandPlaysThisTurn != 1 {
		t.Fatalf("corrected count = %d", r.Game.LandPlaysThisTurn)
	}
	if _, err := r.SetLandPlayCount("guest-conn",
		protocol.GameSetLandPlayCount{Value: 3}); err == nil ||
		err.Error() != protocol.ErrNotActivePlayer {
		t.Fatalf("inactive correction err = %v", err)
	}
	if _, err := r.SetLandPlayCount("host-conn",
		protocol.GameSetLandPlayCount{Value: -1}); err == nil ||
		err.Error() != protocol.ErrInvalidCounter {
		t.Fatalf("negative correction err = %v", err)
	}

	if _, err := r.NextTurn("host-conn"); err != nil {
		t.Fatalf("next turn: %v", err)
	}
	if r.Game.ActiveSeat != 1 || r.Game.LandPlaysThisTurn != 0 {
		t.Fatalf("turn reset = active %d count %d",
			r.Game.ActiveSeat, r.Game.LandPlaysThisTurn)
	}
}

func TestPlayLandValidationDoesNotPartiallyMutate(t *testing.T) {
	r := newTestRoom(t, 1, false)
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1, StartingSeat: 0, ActiveSeat: 0,
		CurrentPhase:      protocol.GamePhaseFirstMain,
		LandPlaysThisTurn: 1,
		Seats: []PlayerGameState{{
			Seat: 0, DisplayName: "Host", Life: 20,
			Hand: []protocol.GameCard{{
				ID: "s0-land", Name: "Island", OwnerSeat: 0,
			}},
			Battlefield: []protocol.GameCard{},
		}},
		Log: []protocol.GameLogEntry{}, NextLogID: 1,
	}

	if _, err := r.PlayLand("host-conn", protocol.GamePlayLand{
		CardID: "s0-land", Position: nil,
	}); err == nil || err.Error() != protocol.ErrInvalidMove {
		t.Fatalf("invalid position err = %v", err)
	}
	if r.Game.LandPlaysThisTurn != 1 || len(r.Game.Seats[0].Hand) != 1 ||
		len(r.Game.Seats[0].Battlefield) != 0 || len(r.Game.Log) != 0 {
		t.Fatalf("invalid play mutated state = %+v", r.Game)
	}

	position := &protocol.CardPosition{X: 0.3, Y: 0.8}
	if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: "s0-land", FromZone: protocol.ZoneHand,
		ToZone: protocol.ZoneBattlefield, Position: position,
	}); err != nil {
		t.Fatalf("ordinary hand move: %v", err)
	}
	if r.Game.LandPlaysThisTurn != 1 {
		t.Fatalf("ordinary move changed recorded count to %d", r.Game.LandPlaysThisTurn)
	}
}
