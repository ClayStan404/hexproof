// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"fmt"
	"math"
	"strings"

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
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	if !validMoveZone(move.FromZone) || !validMoveZone(move.ToZone) {
		return Result{}, newError(protocol.ErrInvalidZone)
	}
	if move.ToZone == protocol.ZoneSideboard ||
		(move.FromZone == protocol.ZoneSideboard &&
			move.ToZone != protocol.ZoneHand &&
			move.ToZone != protocol.ZoneBattlefield &&
			move.ToZone != protocol.ZoneGraveyard &&
			move.ToZone != protocol.ZoneExile) {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	if (move.FromZone == protocol.ZoneCommand || move.ToZone == protocol.ZoneCommand) &&
		!protocol.IsCommanderFormat(r.Format) {
		return Result{}, newError(protocol.ErrInvalidZone)
	}
	// A normal library projection does not reveal the top card. Reject this
	// hidden-to-command-zone path before inspecting the card so callers cannot
	// probe whether the unknown top card is a designated commander.
	if move.FromZone == protocol.ZoneLibrary && move.ToZone == protocol.ZoneCommand {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	move.CardID = strings.TrimSpace(move.CardID)
	if move.FromZone != protocol.ZoneLibrary && move.CardID == "" {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	move.FaceName = strings.TrimSpace(move.FaceName)
	if !validCardFaceName(move.FaceName) {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	sourceSeat := seat
	if move.FromSeat != nil {
		if !publicPlayerZone(move.FromZone) {
			return Result{}, newError(protocol.ErrInvalidMove)
		}
		sourceSeat = *move.FromSeat
		if sourceSeat < 0 || sourceSeat >= len(r.Game.Seats) {
			return Result{}, newError(protocol.ErrInvalidTarget)
		}
	}
	targetSeat := seat
	if move.ToZone == protocol.ZoneBattlefield {
		if !validCardPosition(move.Position) {
			return Result{}, newError(protocol.ErrInvalidPosition)
		}
		if move.ToSeat != nil {
			targetSeat = *move.ToSeat
		}
		if targetSeat < 0 || targetSeat >= len(r.Game.Seats) {
			return Result{}, newError(protocol.ErrInvalidTarget)
		}
	} else if publicPlayerZone(move.ToZone) {
		if move.Position != nil {
			return Result{}, newError(protocol.ErrInvalidPosition)
		}
		targetSeat = -1
		if move.ToSeat != nil {
			targetSeat = *move.ToSeat
			if targetSeat < 0 || targetSeat >= len(r.Game.Seats) {
				return Result{}, newError(protocol.ErrInvalidTarget)
			}
		}
	} else if move.Position != nil || move.ToSeat != nil {
		return Result{}, newError(protocol.ErrInvalidPosition)
	}
	if move.FaceDown && (move.ToZone != protocol.ZoneBattlefield ||
		(move.FromZone != protocol.ZoneHand && move.FromZone != protocol.ZoneLibrary)) {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	if move.FromZone == move.ToZone &&
		(move.ToZone != protocol.ZoneBattlefield &&
			(!publicPlayerZone(move.ToZone) || move.ToSeat == nil ||
				sourceSeat == targetSeat)) {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	if move.ToZone == protocol.ZoneLibrary {
		if move.LibraryPlacement == "" {
			move.LibraryPlacement = protocol.LibraryPlacementTop
		}
		switch move.LibraryPlacement {
		case protocol.LibraryPlacementTop, protocol.LibraryPlacementBottom:
			if move.LibraryIndex != nil {
				return Result{}, newError(protocol.ErrInvalidMove)
			}
		case protocol.LibraryPlacementIndex:
			if move.LibraryIndex == nil || *move.LibraryIndex < 0 {
				return Result{}, newError(protocol.ErrInvalidMove)
			}
		default:
			return Result{}, newError(protocol.ErrInvalidMove)
		}
	} else if move.LibraryPlacement != "" || move.LibraryIndex != nil {
		return Result{}, newError(protocol.ErrInvalidMove)
	}

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
	ownerSeat := candidate.OwnerSeat
	if ownerSeat < 0 || ownerSeat >= len(r.Game.Seats) {
		ownerSeat = seat
	}
	if publicPlayerZone(move.ToZone) {
		targetSeat = ownerSeat
	}
	if move.FromZone == move.ToZone && publicPlayerZone(move.ToZone) &&
		candidateSourceSeat == targetSeat {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	if publicPlayerZone(move.FromZone) && ownerSeat != seat &&
		move.ToZone != protocol.ZoneBattlefield &&
		!publicPlayerZone(move.ToZone) {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	if move.ToZone == protocol.ZoneCommand && !candidate.Commander {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	if publicPlayerZone(move.FromZone) && sourceSeat != seat &&
		!allowRemotePublicSource {
		return Result{}, newError(protocol.ErrApprovalRequired)
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
		card.FaceDown = false
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

// MoveCards moves a validated battlefield, graveyard, or exile selection atomically.
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
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	if move.FromZone != protocol.ZoneBattlefield &&
		!publicPlayerZone(move.FromZone) {
		return Result{}, newError(protocol.ErrInvalidZone)
	}
	sourceSeat := seat
	if move.FromSeat != nil {
		if !publicPlayerZone(move.FromZone) {
			return Result{}, newError(protocol.ErrInvalidMove)
		}
		sourceSeat = *move.FromSeat
	}
	if sourceSeat < 0 || sourceSeat >= len(r.Game.Seats) {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}

	targetSeat := -1
	if move.FromZone == protocol.ZoneBattlefield {
		if move.ToZone != protocol.ZoneLibrary &&
			move.ToZone != protocol.ZoneGraveyard &&
			move.ToZone != protocol.ZoneExile {
			return Result{}, newError(protocol.ErrInvalidZone)
		}
		if move.Position != nil || move.ToSeat != nil {
			return Result{}, newError(protocol.ErrInvalidMove)
		}
	} else {
		switch move.ToZone {
		case protocol.ZoneBattlefield:
			if !validCardPosition(move.Position) {
				return Result{}, newError(protocol.ErrInvalidPosition)
			}
			targetSeat = seat
			if move.ToSeat != nil {
				targetSeat = *move.ToSeat
			}
		case protocol.ZoneHand:
			if move.Position != nil || move.ToSeat != nil {
				return Result{}, newError(protocol.ErrInvalidMove)
			}
		case protocol.ZoneLibrary:
			if move.Position != nil || move.ToSeat != nil {
				return Result{}, newError(protocol.ErrInvalidMove)
			}
		case protocol.ZoneGraveyard, protocol.ZoneExile:
			if move.ToZone == move.FromZone {
				return Result{}, newError(protocol.ErrInvalidMove)
			}
			if move.Position != nil {
				return Result{}, newError(protocol.ErrInvalidPosition)
			}
			targetSeat = sourceSeat
			if move.ToSeat != nil {
				targetSeat = *move.ToSeat
			}
		default:
			return Result{}, newError(protocol.ErrInvalidZone)
		}
		if move.ToZone != protocol.ZoneHand &&
			move.ToZone != protocol.ZoneLibrary &&
			(targetSeat < 0 || targetSeat >= len(r.Game.Seats)) {
			return Result{}, newError(protocol.ErrInvalidTarget)
		}
		if move.Randomize {
			return Result{}, newError(protocol.ErrInvalidMove)
		}
	}
	if move.ToZone == protocol.ZoneLibrary {
		if move.LibraryPlacement == "" {
			move.LibraryPlacement = protocol.LibraryPlacementTop
		}
		if move.LibraryPlacement != protocol.LibraryPlacementTop &&
			move.LibraryPlacement != protocol.LibraryPlacementBottom {
			return Result{}, newError(protocol.ErrInvalidMove)
		}
	} else if move.LibraryPlacement != "" {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	if len(move.CardIDs) == 0 || len(move.CardIDs) > protocol.MaxDeckCards {
		return Result{}, newError(protocol.ErrInvalidMove)
	}

	selected := make(map[string]struct{}, len(move.CardIDs))
	cardIDs := make([]string, 0, len(move.CardIDs))
	for _, rawID := range move.CardIDs {
		cardID := strings.TrimSpace(rawID)
		if cardID == "" {
			return Result{}, newError(protocol.ErrInvalidMove)
		}
		if _, duplicate := selected[cardID]; duplicate {
			return Result{}, newError(protocol.ErrInvalidMove)
		}
		selected[cardID] = struct{}{}
		cardIDs = append(cardIDs, cardID)
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
			ownerSeat := cardsByID[cardID].OwnerSeat
			if ownerSeat < 0 || ownerSeat >= len(r.Game.Seats) {
				ownerSeat = seat
			}
			if ownerSeat != seat && move.ToZone != protocol.ZoneBattlefield &&
				!publicPlayerZone(move.ToZone) {
				return Result{}, newError(protocol.ErrInvalidTarget)
			}
		}
	}
	if publicPlayerZone(move.FromZone) && sourceSeat != seat &&
		!allowRemotePublicSource {
		return Result{}, newError(protocol.ErrApprovalRequired)
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

	grouped := make(map[int][]protocol.GameCard)
	ownerOrder := make([]int, 0, len(cards))
	removedTokens := 0
	for index, card := range cards {
		ownerSeat := card.OwnerSeat
		if ownerSeat < 0 || ownerSeat >= len(r.Game.Seats) {
			ownerSeat = seat
		}
		if card.Token && move.ToZone != protocol.ZoneBattlefield {
			removedTokens++
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
			r.Game.Seats[targetSeat].Battlefield =
				append(r.Game.Seats[targetSeat].Battlefield, card)
			continue
		}
		destinationSeat := ownerSeat
		if _, exists := grouped[destinationSeat]; !exists {
			ownerOrder = append(ownerOrder, destinationSeat)
		}
		grouped[destinationSeat] = append(grouped[destinationSeat], card)
	}
	for _, destinationSeat := range ownerOrder {
		ownerCards := grouped[destinationSeat]
		if move.ToZone == protocol.ZoneLibrary &&
			move.LibraryPlacement == protocol.LibraryPlacementTop {
			for index := len(ownerCards) - 1; index >= 0; index-- {
				ownerSeat := ownerCards[index].OwnerSeat
				r.putOwnedCardAt(&r.Game.Seats[destinationSeat], ownerSeat,
					move.ToZone, move.LibraryPlacement, nil, ownerCards[index])
			}
			continue
		}
		for _, card := range ownerCards {
			r.putOwnedCardAt(&r.Game.Seats[destinationSeat], card.OwnerSeat,
				move.ToZone, move.LibraryPlacement, nil, card)
		}
	}

	if move.FromZone == protocol.ZoneBattlefield {
		orderDescription := "in order"
		if move.Randomize {
			orderDescription = "in random order"
		}
		r.appendGameLog("move_cards", seat,
			fmt.Sprintf("%s moved %d battlefield card(s) to %s %s.",
				r.Game.Seats[seat].DisplayName, len(cards)-removedTokens,
				move.ToZone, orderDescription))
	} else {
		fromDescription := move.FromZone
		if sourceSeat != seat {
			fromDescription = fmt.Sprintf("%s's %s",
				r.Game.Seats[sourceSeat].DisplayName, move.FromZone)
		}
		r.appendGameLog("move_cards", seat,
			fmt.Sprintf("%s moved %d card(s) from %s to %s.",
				r.Game.Seats[seat].DisplayName, len(cards)-removedTokens,
				fromDescription, move.ToZone))
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
