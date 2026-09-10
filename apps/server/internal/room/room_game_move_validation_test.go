// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"encoding/json"
	"fmt"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestBattlefieldMovesRejectEmptyAndEliminatedSeatsAtomically(t *testing.T) {
	for _, targetSeat := range []int{2, 3} {
		for _, sourceZone := range []string{protocol.ZoneHand, protocol.ZoneLibrary,
			protocol.ZoneBattlefield, protocol.ZoneGraveyard} {
			t.Run(fmt.Sprintf("seat%d/%s", targetSeat, sourceZone), func(t *testing.T) {
				r := newTestRoom(t, 4, true)
				r.Phase = protocol.RoomPhaseStarted
				card := protocol.GameCard{ID: "source-card", Name: "Visible card", OwnerSeat: 0}
				actor := PlayerGameState{Seat: 0, DisplayName: "Host"}
				switch sourceZone {
				case protocol.ZoneHand:
					actor.Hand = []protocol.GameCard{card}
				case protocol.ZoneLibrary:
					actor.Library = []protocol.GameCard{card}
				case protocol.ZoneBattlefield:
					actor.Battlefield = []protocol.GameCard{card}
				case protocol.ZoneGraveyard:
					actor.Graveyard = []protocol.GameCard{card}
				}
				r.Game = &GameState{ActiveSeat: 0, Seats: []PlayerGameState{
					actor,
					{Seat: 1, DisplayName: "Guest"},
					{Seat: 2, DisplayName: "Eliminated player", Eliminated: true},
					{Seat: 3, Eliminated: true},
				}, NextLogID: 1}
				before, _ := json.Marshal(r.Game)
				cardID := card.ID
				if sourceZone == protocol.ZoneLibrary {
					cardID = ""
				}
				_, err := r.MoveCard("host-conn", protocol.GameMoveCard{
					CardID: cardID, FromZone: sourceZone, ToZone: protocol.ZoneBattlefield,
					ToSeat: &targetSeat, Position: &protocol.CardPosition{X: 0.5, Y: 0.5},
				})
				if err == nil || err.Error() != protocol.ErrInvalidTarget {
					t.Errorf("move into an unavailable battlefield: %v", err)
				}
				after, _ := json.Marshal(r.Game)
				if string(before) != string(after) {
					t.Fatal("rejected move changed zones/logs or lost a card")
				}
				if sourceZone == protocol.ZoneGraveyard {
					_, err = r.MoveCards("host-conn", protocol.GameMoveCards{
						CardIDs: []string{card.ID}, FromZone: sourceZone, ToZone: protocol.ZoneBattlefield,
						ToSeat: &targetSeat, Position: &protocol.CardPosition{X: 0.5, Y: 0.5},
					})
					if err == nil || err.Error() != protocol.ErrInvalidTarget {
						t.Errorf("batch move into an unavailable battlefield: %v", err)
					}
					after, _ = json.Marshal(r.Game)
					if string(before) != string(after) {
						t.Fatal("rejected batch move changed zones/logs or lost cards")
					}
				}
			})
		}
	}
}

func TestNormalizeLibraryPlacementSharesSingleAndBatchPolicy(t *testing.T) {
	t.Parallel()
	placement := ""
	if err := normalizeLibraryPlacement(protocol.ZoneLibrary, &placement, nil, false); err != nil {
		t.Fatalf("default batch placement: %v", err)
	}
	if placement != protocol.LibraryPlacementTop {
		t.Fatalf("default placement = %q, want top", placement)
	}

	index := 3
	placement = protocol.LibraryPlacementIndex
	if err := normalizeLibraryPlacement(
		protocol.ZoneLibrary, &placement, &index, true); err != nil {
		t.Fatalf("single-card indexed placement: %v", err)
	}
	if err := normalizeLibraryPlacement(
		protocol.ZoneLibrary, &placement, nil, false); err == nil || err.Error() != protocol.ErrInvalidMove {
		t.Fatalf("batch indexed placement error = %v, want %s", err, protocol.ErrInvalidMove)
	}
}

func TestOwnedPublicCardCannotMoveIntoActorHiddenZone(t *testing.T) {
	t.Parallel()
	if err := validateOwnedCardDestination(
		0, 1, protocol.ZoneGraveyard, protocol.ZoneHand); err == nil || err.Error() != protocol.ErrInvalidTarget {
		t.Fatalf("remote hidden-zone move error = %v, want %s", err, protocol.ErrInvalidTarget)
	}
	if err := validateOwnedCardDestination(
		0, 1, protocol.ZoneGraveyard, protocol.ZoneBattlefield); err != nil {
		t.Fatalf("approved public card should remain movable to battlefield: %v", err)
	}
	if err := validateOwnedCardDestination(
		0, 1, protocol.ZoneGraveyard, protocol.ZoneExile); err != nil {
		t.Fatalf("owned public destination should remain allowed: %v", err)
	}
}
