// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"fmt"
	"math"

	"hexproof/server/internal/protocol"
)

// MoveCard moves one manual tabletop card instance. Moving a card out of
// another player's public zone requires a one-use server-side approval.
func (r *Room) MoveCard(connID string, move protocol.GameMoveCard) (Result, error) {
	return r.moveCard(connID, move, false)
}

// MoveApprovedCard executes the exact public-zone move retained by the server
// after the source-zone player grants one-use approval.
func (r *Room) MoveApprovedCard(connID string, move protocol.GameMoveCard) (Result, error) {
	return r.moveCard(connID, move, true)
}

func (r *Room) moveCard(connID string, move protocol.GameMoveCard,
	allowRemotePublicSource bool) (Result, error) {
	plan, err := r.planCardMove(connID, &move)
	if err != nil {
		return Result{}, err
	}
	seat := plan.actorSeat
	sourceSeat := plan.sourceSeat
	targetSeat := plan.targetSeat

	candidate, candidateSourceSeat, found := r.movableCard(
		seat, sourceSeat, move.FromZone, move.CardID)
	if !found {
		return Result{}, newError(protocol.ErrCardNotFound)
	}
	var oldBattlefieldPosition *protocol.CardPosition
	if move.FromZone == protocol.ZoneBattlefield && candidate.Position != nil {
		copied := *candidate.Position
		oldBattlefieldPosition = &copied
	}
	ownerSeat := normalizedOwnerSeat(candidate, seat, len(r.Game.Seats))
	if publicPlayerZone(move.ToZone) {
		targetSeat = ownerSeat
	}
	if move.FromZone == move.ToZone && publicPlayerZone(move.ToZone) &&
		candidateSourceSeat == targetSeat {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	if err := validateOwnedCardDestination(
		seat, ownerSeat, move.FromZone, move.ToZone); err != nil {
		return Result{}, err
	}
	if move.ToZone == protocol.ZoneCommand && !candidate.Commander {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	if err := requirePublicSourceApproval(
		seat, sourceSeat, move.FromZone, allowRemotePublicSource); err != nil {
		return Result{}, err
	}

	card, actualSourceSeat, found := r.takeMovableCard(
		seat, sourceSeat, move.FromZone, move.CardID,
		candidate, candidateSourceSeat)
	if !found {
		return Result{}, newError(protocol.ErrCardNotFound)
	}
	wasFaceDown := card.FaceDown
	card.OwnerSeat = ownerSeat
	card.Position = nil
	if move.Position != nil {
		position := *move.Position
		card.Position = &position
	}
	if move.ToZone != protocol.ZoneBattlefield {
		card.Tapped = false
		card.Counters = nil
		card.FaceName = ""
		card.FaceDown = move.ToZone == protocol.ZoneExile && move.FaceDown
	} else if move.FromZone != protocol.ZoneBattlefield || move.FaceName != "" {
		card.FaceName = move.FaceName
		card.FaceDown = move.FaceDown
	}
	removed := card.Token && move.FromZone != move.ToZone &&
		move.ToZone != protocol.ZoneBattlefield
	if !removed {
		if move.ToZone == protocol.ZoneBattlefield {
			r.Game.Seats[targetSeat].Battlefield =
				append(r.Game.Seats[targetSeat].Battlefield, card)
		} else {
			destinationSeat := ownerSeat
			if publicPlayerZone(move.ToZone) {
				destinationSeat = targetSeat
			}
			r.putOwnedCardAt(&r.Game.Seats[destinationSeat], ownerSeat,
				move.ToZone, move.LibraryPlacement, move.LibraryIndex, card)
		}
	}
	if (move.FromZone == protocol.ZoneBattlefield &&
		(move.ToZone != protocol.ZoneBattlefield ||
			actualSourceSeat != targetSeat)) ||
		move.FromZone == protocol.ZoneStack {
		r.removeCardRelations(card.ID)
	} else if move.FromZone == protocol.ZoneBattlefield &&
		move.ToZone == protocol.ZoneBattlefield &&
		actualSourceSeat == targetSeat {
		r.shiftSameLaneAttachments(card.ID, targetSeat,
			oldBattlefieldPosition, card.Position)
	}

	if move.FromZone != move.ToZone {
		hiddenFaceDownIdentity := wasFaceDown &&
			(move.ToZone == protocol.ZoneHand || move.ToZone == protocol.ZoneLibrary)
		if removed {
			if hiddenFaceDownIdentity {
				r.appendGameLog("remove_token", seat,
					fmt.Sprintf("%s removed a face-down token from the battlefield.",
						r.Game.Seats[seat].DisplayName))
			} else {
				r.appendGameLog("remove_token", seat,
					fmt.Sprintf("%s removed token %s from the battlefield.",
						r.Game.Seats[seat].DisplayName, card.Name))
			}
		} else {
			toDescription := move.ToZone
			cardDescription := card.Name
			if (move.FromZone == protocol.ZoneHand ||
				move.FromZone == protocol.ZoneLibrary ||
				move.FromZone == protocol.ZoneSideboard) &&
				(move.ToZone == protocol.ZoneHand ||
					move.ToZone == protocol.ZoneLibrary) {
				cardDescription = "a card"
			}
			if card.FaceDown || hiddenFaceDownIdentity {
				cardDescription = "a face-down card"
			}
			if move.ToZone == protocol.ZoneBattlefield && targetSeat != seat {
				toDescription = fmt.Sprintf("%s's battlefield",
					r.Game.Seats[targetSeat].DisplayName)
			}
			fromDescription := move.FromZone
			if publicPlayerZone(move.FromZone) && actualSourceSeat != seat {
				fromDescription = fmt.Sprintf("%s's %s",
					r.Game.Seats[actualSourceSeat].DisplayName, move.FromZone)
			}
			r.appendGameLog("move_card", seat,
				fmt.Sprintf("%s moved %s from %s to %s.",
					r.Game.Seats[seat].DisplayName, cardDescription,
					fromDescription, toDescription))
		}
	}
	reply, _ := protocol.NewEnvelope(protocol.TypeGameCardMoved,
		protocol.GameCardMoved{
			RoomID:   r.ID,
			Seat:     seat,
			CardID:   card.ID,
			FromZone: move.FromZone,
			FromSeat: actualSourceSeat,
			ToZone:   move.ToZone,
			ToSeat:   targetSeat,
			Position: card.Position,
			Removed:  removed,
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// PublicZoneMoveTarget validates the live source-zone player for a move that
// has already returned approval_required from MoveCard or MoveCards.
func (r *Room) PublicZoneMoveTarget(connID string, sourceSeat int,
	sourceZone, toZone string, cardCount int) (PublicZoneMoveTarget, error) {
	if err := r.requireActiveGame(); err != nil {
		return PublicZoneMoveTarget{}, err
	}
	requesterSeat, err := r.playerSeat(connID, false)
	if err != nil {
		return PublicZoneMoveTarget{}, err
	}
	if !publicPlayerZone(sourceZone) || sourceSeat == requesterSeat ||
		cardCount < 1 || cardCount > protocol.MaxDeckCards {
		return PublicZoneMoveTarget{}, newError(protocol.ErrInvalidTarget)
	}
	if sourceSeat < 0 || sourceSeat >= len(r.Seats) ||
		!r.Seats[sourceSeat].Occupied {
		return PublicZoneMoveTarget{}, newError(protocol.ErrInvalidTarget)
	}
	return PublicZoneMoveTarget{
		RequesterSeat: requesterSeat,
		RequesterName: r.Seats[requesterSeat].DisplayName,
		TargetSeat:    sourceSeat,
		TargetConnID:  r.Seats[sourceSeat].ConnectionID,
		SourceZone:    sourceZone,
		CardCount:     cardCount,
		ToZone:        toZone,
	}, nil
}

func validMoveZone(zone string) bool {
	switch zone {
	case protocol.ZoneHand, protocol.ZoneBattlefield, protocol.ZoneGraveyard,
		protocol.ZoneExile, protocol.ZoneStack, protocol.ZoneReveal,
		protocol.ZoneLibrary, protocol.ZoneCommand, protocol.ZoneSideboard:
		return true
	default:
		return false
	}
}

func publicPlayerZone(zone string) bool {
	return zone == protocol.ZoneGraveyard || zone == protocol.ZoneExile
}

func validCardPosition(position *protocol.CardPosition) bool {
	if position == nil ||
		math.IsNaN(position.X) || math.IsInf(position.X, 0) ||
		math.IsNaN(position.Y) || math.IsInf(position.Y, 0) {
		return false
	}
	return position.X >= 0 && position.X <= 1 && position.Y >= 0 && position.Y <= 1
}

func playerGameZone(state *PlayerGameState, zone string) *[]protocol.GameCard {
	switch zone {
	case protocol.ZoneHand:
		return &state.Hand
	case protocol.ZoneSideboard:
		return &state.Sideboard
	case protocol.ZoneBattlefield:
		return &state.Battlefield
	case protocol.ZoneGraveyard:
		return &state.Graveyard
	case protocol.ZoneExile:
		return &state.Exile
	case protocol.ZoneCommand:
		return &state.CommandZone
	default:
		return nil
	}
}

func (r *Room) sharedGameZone(zone string) *[]protocol.GameSharedCard {
	switch zone {
	case protocol.ZoneStack:
		return &r.Game.Stack
	case protocol.ZoneReveal:
		return &r.Game.Revealed
	default:
		return nil
	}
}

func (r *Room) takeOwnedCard(state *PlayerGameState, ownerSeat int, zone, cardID string) (protocol.GameCard, bool) {
	if playerZone := playerGameZone(state, zone); playerZone != nil {
		for i, card := range *playerZone {
			if card.ID != cardID {
				continue
			}
			*playerZone = append((*playerZone)[:i], (*playerZone)[i+1:]...)
			return card, true
		}
		return protocol.GameCard{}, false
	}
	sharedZone := r.sharedGameZone(zone)
	if sharedZone == nil {
		return protocol.GameCard{}, false
	}
	for i, shared := range *sharedZone {
		if shared.ID != cardID || shared.OwnerSeat != ownerSeat {
			continue
		}
		*sharedZone = append((*sharedZone)[:i], (*sharedZone)[i+1:]...)
		return shared.GameCard, true
	}
	return protocol.GameCard{}, false
}

func (r *Room) movableCard(actorSeat, sourceSeat int,
	zone, cardID string) (protocol.GameCard, int, bool) {
	if zone == protocol.ZoneLibrary {
		if sourceSeat != actorSeat || len(r.Game.Seats[actorSeat].Library) == 0 {
			return protocol.GameCard{}, -1, false
		}
		return r.Game.Seats[actorSeat].Library[0], actorSeat, true
	}
	if zone == protocol.ZoneBattlefield {
		for controllerSeat := range r.Game.Seats {
			for _, card := range r.Game.Seats[controllerSeat].Battlefield {
				if card.ID == cardID &&
					(controllerSeat == actorSeat || card.OwnerSeat == actorSeat) {
					return card, controllerSeat, true
				}
			}
		}
		return protocol.GameCard{}, -1, false
	}
	if publicPlayerZone(zone) {
		for _, card := range *playerGameZone(&r.Game.Seats[sourceSeat], zone) {
			if card.ID == cardID {
				return card, sourceSeat, true
			}
		}
		return protocol.GameCard{}, -1, false
	}
	if sourceSeat != actorSeat {
		return protocol.GameCard{}, -1, false
	}
	if playerZone := playerGameZone(&r.Game.Seats[actorSeat], zone); playerZone != nil {
		for _, card := range *playerZone {
			if card.ID == cardID {
				return card, actorSeat, true
			}
		}
		return protocol.GameCard{}, -1, false
	}
	sharedZone := r.sharedGameZone(zone)
	if sharedZone == nil {
		return protocol.GameCard{}, -1, false
	}
	for _, shared := range *sharedZone {
		if shared.ID == cardID && shared.OwnerSeat == actorSeat {
			return shared.GameCard, actorSeat, true
		}
	}
	return protocol.GameCard{}, -1, false
}

func (r *Room) takeMovableCard(actorSeat, sourceSeat int,
	zone, cardID string, card protocol.GameCard,
	actualSourceSeat int) (protocol.GameCard, int, bool) {
	if zone == protocol.ZoneLibrary {
		state := &r.Game.Seats[actorSeat]
		state.Library = append([]protocol.GameCard(nil), state.Library[1:]...)
		return card, actorSeat, true
	}
	if zone == protocol.ZoneBattlefield {
		cards := &r.Game.Seats[actualSourceSeat].Battlefield
		for index := range *cards {
			if (*cards)[index].ID == cardID {
				*cards = append((*cards)[:index], (*cards)[index+1:]...)
				return card, actualSourceSeat, true
			}
		}
		return protocol.GameCard{}, -1, false
	}
	if publicPlayerZone(zone) {
		card, taken := r.takeOwnedCard(
			&r.Game.Seats[sourceSeat], sourceSeat, zone, cardID)
		return card, sourceSeat, taken
	}
	card, taken := r.takeOwnedCard(
		&r.Game.Seats[actorSeat], actorSeat, zone, cardID)
	return card, actorSeat, taken
}

func (r *Room) putOwnedCard(state *PlayerGameState, ownerSeat int, zone string, card protocol.GameCard) {
	r.putOwnedCardAt(state, ownerSeat, zone, protocol.LibraryPlacementTop, nil, card)
}

func (r *Room) putOwnedCardAt(state *PlayerGameState, ownerSeat int, zone,
	libraryPlacement string, libraryIndex *int, card protocol.GameCard) {
	card.OwnerSeat = ownerSeat
	if publicPlayerZone(zone) && ownerSeat >= 0 && ownerSeat < len(r.Game.Seats) {
		state = &r.Game.Seats[ownerSeat]
	}
	if zone == protocol.ZoneLibrary {
		index := 0
		switch libraryPlacement {
		case protocol.LibraryPlacementBottom:
			index = len(state.Library)
		case protocol.LibraryPlacementIndex:
			index = *libraryIndex
			if index > len(state.Library) {
				index = len(state.Library)
			}
		}
		state.Library = append(state.Library, protocol.GameCard{})
		copy(state.Library[index+1:], state.Library[index:])
		state.Library[index] = card
		return
	}
	if playerZone := playerGameZone(state, zone); playerZone != nil {
		*playerZone = append(*playerZone, card)
		return
	}
	sharedZone := r.sharedGameZone(zone)
	if sharedZone == nil {
		return
	}
	*sharedZone = append(*sharedZone, protocol.GameSharedCard{
		GameCard: card,
	})
}
