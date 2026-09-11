// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"fmt"

	"hexproof/server/internal/protocol"
)

// MoveCards moves a validated hand, battlefield, graveyard, or exile selection atomically.
// Batch moves keep user-selected order unless Randomize is requested and
// preserve each card's immutable owner across public-zone transitions.
func (r *Room) MoveCards(connID string, move protocol.GameMoveCards) (Result, error) {
	return r.moveCards(connID, move, false)
}

// MoveApprovedCards executes the exact batch public-zone move retained by the
// server after the source-zone player grants one-use approval.
func (r *Room) MoveApprovedCards(connID string, move protocol.GameMoveCards) (Result, error) {
	return r.moveCards(connID, move, true)
}

func (r *Room) moveCards(connID string, move protocol.GameMoveCards,
	allowRemotePublicSource bool) (Result, error) {
	plan, err := r.planCardBatchMove(connID, &move)
	if err != nil {
		return Result{}, err
	}
	seat := plan.actorSeat
	sourceSeat := plan.sourceSeat
	targetSeat := plan.targetSeat
	cardIDs := plan.cardIDs
	selected := make(map[string]struct{}, len(cardIDs))
	for _, cardID := range cardIDs {
		selected[cardID] = struct{}{}
	}

	cardsByID := make(map[string]protocol.GameCard, len(cardIDs))
	if move.FromZone == protocol.ZoneBattlefield {
		for _, cardID := range cardIDs {
			cardSeat, cardIndex, found := r.battlefieldCard(cardID)
			if !found {
				return Result{}, newError(protocol.ErrCardNotFound)
			}
			card := r.Game.Seats[cardSeat].Battlefield[cardIndex]
			if cardSeat != seat && card.OwnerSeat != seat {
				return Result{}, newError(protocol.ErrInvalidTarget)
			}
			cardsByID[cardID] = card
		}
	} else {
		sourceCards := playerGameZone(&r.Game.Seats[sourceSeat], move.FromZone)
		if sourceCards == nil {
			return Result{}, newError(protocol.ErrInvalidZone)
		}
		for _, card := range *sourceCards {
			if _, wanted := selected[card.ID]; wanted {
				cardsByID[card.ID] = card
			}
		}
		if len(cardsByID) != len(cardIDs) {
			return Result{}, newError(protocol.ErrCardNotFound)
		}
		for _, cardID := range cardIDs {
			ownerSeat := normalizedOwnerSeat(cardsByID[cardID], seat, len(r.Game.Seats))
			if err := validateOwnedCardDestination(
				seat, ownerSeat, move.FromZone, move.ToZone); err != nil {
				return Result{}, err
			}
		}
	}
	if err := requirePublicSourceApproval(
		seat, sourceSeat, move.FromZone, allowRemotePublicSource); err != nil {
		return Result{}, err
	}

	cards := make([]protocol.GameCard, 0, len(cardIDs))
	for _, cardID := range cardIDs {
		cards = append(cards, cardsByID[cardID])
	}
	if move.Randomize {
		if err := r.shuffle(cards); err != nil {
			return Result{}, newError(protocol.ErrGameSetupFailed)
		}
	}

	grouped := make(map[int][]protocol.GameCard)
	battlefieldCards := make([]protocol.GameCard, 0, len(cards))
	ownerOrder := make([]int, 0, len(cards))
	removedTokens := 0
	for index, card := range cards {
		ownerSeat := normalizedOwnerSeat(card, seat, len(r.Game.Seats))
		if card.Token && move.ToZone != protocol.ZoneBattlefield {
			removedTokens++
			// The explicit whole-library shuffle still applies when the
			// selected object is a token that disappears on leaving play.
			if move.LibraryPlacement == protocol.LibraryPlacementShuffle {
				if _, exists := grouped[ownerSeat]; !exists {
					ownerOrder = append(ownerOrder, ownerSeat)
					grouped[ownerSeat] = nil
				}
			}
			continue
		}
		card.OwnerSeat = ownerSeat
		card.Position = nil
		card.Tapped = false
		card.Counters = nil
		card.FaceName = ""
		card.FaceDown = false
		if move.ToZone == protocol.ZoneBattlefield {
			card.Position = battlefieldBatchPosition(
				*move.Position, index, len(cards))
			battlefieldCards = append(battlefieldCards, card)
			continue
		}
		destinationSeat := ownerSeat
		if _, exists := grouped[destinationSeat]; !exists {
			ownerOrder = append(ownerOrder, destinationSeat)
		}
		grouped[destinationSeat] = append(grouped[destinationSeat], card)
	}
	// Build library replacements in one pass. Repeated insertion at the top
	// shifts the existing library for every selected card and is quadratic.
	libraries := make(map[int][]protocol.GameCard, len(ownerOrder))
	if move.ToZone == protocol.ZoneLibrary {
		for _, destinationSeat := range ownerOrder {
			current := r.Game.Seats[destinationSeat].Library
			incoming := grouped[destinationSeat]
			next := make([]protocol.GameCard, 0, len(current)+len(incoming))
			if move.LibraryPlacement == protocol.LibraryPlacementTop {
				next = append(next, incoming...)
				next = append(next, current...)
			} else {
				next = append(next, current...)
				next = append(next, incoming...)
			}
			if move.LibraryPlacement == protocol.LibraryPlacementShuffle {
				if err := r.shuffle(next); err != nil {
					return Result{}, newError(protocol.ErrGameSetupFailed)
				}
			}
			libraries[destinationSeat] = next
		}
	}

	if move.FromZone == protocol.ZoneBattlefield {
		for stateIndex := range r.Game.Seats {
			current := r.Game.Seats[stateIndex].Battlefield
			remaining := make([]protocol.GameCard, 0, len(current))
			for _, card := range current {
				if _, ok := selected[card.ID]; ok {
					r.removeCardRelations(card.ID)
					continue
				}
				remaining = append(remaining, card)
			}
			r.Game.Seats[stateIndex].Battlefield = remaining
		}
	} else {
		sourceCards := playerGameZone(&r.Game.Seats[sourceSeat], move.FromZone)
		current := *sourceCards
		remaining := make([]protocol.GameCard, 0, len(current)-len(cards))
		for _, card := range current {
			if _, ok := selected[card.ID]; !ok {
				remaining = append(remaining, card)
			}
		}
		*sourceCards = remaining
	}

	if len(battlefieldCards) > 0 {
		r.Game.Seats[targetSeat].Battlefield = append(r.Game.Seats[targetSeat].Battlefield, battlefieldCards...)
	}
	for _, destinationSeat := range ownerOrder {
		if move.ToZone == protocol.ZoneLibrary {
			r.Game.Seats[destinationSeat].Library = libraries[destinationSeat]
		} else {
			for _, card := range grouped[destinationSeat] {
				r.putOwnedCard(&r.Game.Seats[destinationSeat], destinationSeat, move.ToZone, card)
			}
		}
	}

	fromDescription := move.FromZone
	if publicPlayerZone(move.FromZone) && sourceSeat != seat {
		fromDescription = fmt.Sprintf("%s's %s", r.Game.Seats[sourceSeat].DisplayName, move.FromZone)
	}
	toDescription := move.ToZone
	if move.ToZone == protocol.ZoneLibrary {
		switch move.LibraryPlacement {
		case protocol.LibraryPlacementShuffle:
			toDescription = "library and shuffled the library"
		default:
			orderDescription := "in order"
			if move.Randomize {
				orderDescription = "in random order"
			}
			toDescription = fmt.Sprintf("library (%s, %s)", move.LibraryPlacement, orderDescription)
		}
	} else if move.ToZone == protocol.ZoneBattlefield && targetSeat != seat {
		toDescription = fmt.Sprintf("%s's battlefield", r.Game.Seats[targetSeat].DisplayName)
	}
	r.appendGameLog("move_cards", seat,
		fmt.Sprintf("%s moved %d card(s) from %s to %s.",
			r.Game.Seats[seat].DisplayName, len(cards)-removedTokens, fromDescription, toDescription))
	if removedTokens > 0 {
		r.appendGameLog("remove_token", seat,
			fmt.Sprintf("%s removed %d token(s) from the battlefield.", r.Game.Seats[seat].DisplayName, removedTokens))
	}

	reply, _ := protocol.NewEnvelope(protocol.TypeGameCardsMoved,
		protocol.GameCardsMoved{
			RoomID: r.ID,
			Seat:   seat,
			Count:  len(cards),
			ToZone: move.ToZone,
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}
