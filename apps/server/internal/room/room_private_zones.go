// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"fmt"
	"hexproof/server/internal/protocol"
	"math"
	"strings"
)

// Reveal publishes either the acting player's entire hand or the requested
// subset into the shared reveal area. Revealed cards leave the hand until
// their owner moves them back.
func (r *Room) Reveal(connID string, request protocol.GameReveal) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	if request.Zone != protocol.ZoneHand {
		return Result{}, newError(protocol.ErrInvalidZone)
	}

	state := &r.Game.Seats[seat]
	selected := make(map[string]struct{}, len(request.CardIDs))
	for _, cardID := range request.CardIDs {
		cardID = strings.TrimSpace(cardID)
		if cardID == "" {
			return Result{}, newError(protocol.ErrInvalidMove)
		}
		if _, duplicate := selected[cardID]; duplicate {
			return Result{}, newError(protocol.ErrInvalidMove)
		}
		selected[cardID] = struct{}{}
	}
	if len(selected) > len(state.Hand) {
		return Result{}, newError(protocol.ErrCardNotFound)
	}

	revealAll := len(selected) == 0
	revealed := make([]protocol.GameCard, 0, len(state.Hand))
	remaining := make([]protocol.GameCard, 0, len(state.Hand))
	for _, card := range state.Hand {
		if revealAll {
			revealed = append(revealed, card)
			continue
		}
		if _, ok := selected[card.ID]; ok {
			revealed = append(revealed, card)
			delete(selected, card.ID)
		} else {
			remaining = append(remaining, card)
		}
	}
	if len(selected) != 0 {
		return Result{}, newError(protocol.ErrCardNotFound)
	}
	if len(revealed) == 0 {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	state.Hand = remaining
	for _, card := range revealed {
		r.putOwnedCard(state, seat, protocol.ZoneReveal, card)
	}
	r.appendGameLog("reveal", seat,
		fmt.Sprintf("%s revealed %d card(s) from hand.", state.DisplayName, len(revealed)))
	reply, _ := protocol.NewEnvelope(protocol.TypeGameRevealed,
		protocol.GameRevealed{
			RoomID: r.ID,
			Seat:   seat,
			Zone:   protocol.ZoneHand,
			Count:  len(revealed),
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// RecallRevealed returns all of the acting player's shared revealed cards to
// their hand in one authoritative operation.
func (r *Room) RecallRevealed(connID string) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	recalled := make([]protocol.GameCard, 0)
	remaining := make([]protocol.GameSharedCard, 0, len(r.Game.Revealed))
	for _, shared := range r.Game.Revealed {
		if shared.OwnerSeat == seat {
			card := shared.GameCard
			card.Position = nil
			card.Tapped = false
			card.Counters = nil
			card.FaceDown = false
			recalled = append(recalled, card)
		} else {
			remaining = append(remaining, shared)
		}
	}
	if len(recalled) == 0 {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	r.Game.Revealed = remaining
	r.Game.Seats[seat].Hand = append(r.Game.Seats[seat].Hand, recalled...)
	r.appendGameLog("recall_revealed", seat,
		fmt.Sprintf("%s returned %d revealed card(s) to hand.",
			r.Game.Seats[seat].DisplayName, len(recalled)))
	reply, _ := protocol.NewEnvelope(protocol.TypeGameRevealedRecalled,
		protocol.GameRevealedRecalled{
			RoomID: r.ID,
			Seat:   seat,
			Count:  len(recalled),
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// DumpZone returns a private snapshot of the acting player's own library. A
// remote source must go through ZoneDumpTarget and DumpApprovedZone instead.
func (r *Room) DumpZone(connID string, request protocol.GameDumpZone) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	if request.Zone != protocol.ZoneLibrary {
		return Result{}, newError(protocol.ErrInvalidZone)
	}
	if request.TopCount < 0 || request.TopCount > protocol.MaxDeckCards {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	if request.Seat != nil && *request.Seat != seat {
		return Result{}, newError(protocol.ErrApprovalRequired)
	}

	state := &r.Game.Seats[seat]
	cards := state.Library
	if request.TopCount > 0 && request.TopCount < len(cards) {
		cards = cards[:request.TopCount]
	}
	if request.TopCount > 0 {
		r.appendGameLog("library_look", seat,
			fmt.Sprintf("%s looked at the top %d card(s) of their library.",
				state.DisplayName, len(cards)))
	} else {
		r.appendGameLog("library_search", seat,
			fmt.Sprintf("%s is searching their library.", state.DisplayName))
	}
	reply, _ := protocol.NewEnvelope(protocol.TypeGameZoneDumped,
		protocol.GameZoneDumped{
			RoomID:     r.ID,
			Zone:       request.Zone,
			SourceSeat: seat,
			TopCount:   request.TopCount,
			Cards:      cloneGameCards(cards),
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// ZoneDumpTarget validates a request to inspect another player's library.
func (r *Room) ZoneDumpTarget(connID string,
	request protocol.GameDumpZone) (ZoneDumpTarget, error) {
	if err := r.requireActiveGame(); err != nil {
		return ZoneDumpTarget{}, err
	}
	requesterSeat, err := r.playerSeat(connID, false)
	if err != nil {
		return ZoneDumpTarget{}, err
	}
	if request.Zone != protocol.ZoneLibrary {
		return ZoneDumpTarget{}, newError(protocol.ErrInvalidZone)
	}
	// Match DumpZone so an out-of-range count is rejected before it can create
	// a pending approval the target would have to answer.
	if request.TopCount < 0 || request.TopCount > protocol.MaxDeckCards {
		return ZoneDumpTarget{}, newError(protocol.ErrInvalidMove)
	}
	if request.Seat == nil || *request.Seat == requesterSeat {
		return ZoneDumpTarget{}, newError(protocol.ErrInvalidTarget)
	}
	targetSeat := *request.Seat
	if targetSeat < 0 || targetSeat >= len(r.Seats) ||
		!r.Seats[targetSeat].Occupied {
		return ZoneDumpTarget{}, newError(protocol.ErrInvalidTarget)
	}
	return ZoneDumpTarget{
		RequesterSeat: requesterSeat,
		RequesterName: r.Seats[requesterSeat].DisplayName,
		TargetSeat:    targetSeat,
		TargetConnID:  r.Seats[targetSeat].ConnectionID,
		TopCount:      request.TopCount,
	}, nil
}

// DumpApprovedZone returns a target player's library only after the server
// layer has validated that player's explicit approval.
func (r *Room) DumpApprovedZone(connID string, targetSeat int,
	approvalID string, topCount int) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	requesterSeat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	if targetSeat < 0 || targetSeat >= len(r.Seats) ||
		!r.Seats[targetSeat].Occupied {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	if strings.TrimSpace(approvalID) == "" {
		return Result{}, newError(protocol.ErrApprovalRequired)
	}
	if topCount < 0 || topCount > protocol.MaxDeckCards {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	cards := r.Game.Seats[targetSeat].Library
	if topCount > 0 && topCount < len(cards) {
		cards = cards[:topCount]
	}
	if topCount > 0 {
		r.appendGameLog("library_look", requesterSeat,
			fmt.Sprintf("%s looked at the top %d card(s) of %s's library.",
				r.Game.Seats[requesterSeat].DisplayName, len(cards),
				r.Game.Seats[targetSeat].DisplayName))
	} else {
		r.appendGameLog("library_search", requesterSeat,
			fmt.Sprintf("%s is searching %s's library.",
				r.Game.Seats[requesterSeat].DisplayName,
				r.Game.Seats[targetSeat].DisplayName))
	}
	reply, _ := protocol.NewEnvelope(protocol.TypeGameZoneDumped,
		protocol.GameZoneDumped{
			RoomID:     r.ID,
			Zone:       protocol.ZoneLibrary,
			SourceSeat: targetSeat,
			ApprovalID: approvalID,
			TopCount:   topCount,
			Cards:      cloneGameCards(cards),
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// SearchLibrary moves selected cards out of the acting player's private
// library. The shared log reveals their names only when explicitly requested.
func (r *Room) SearchLibrary(connID string,
	request protocol.GameSearchLibrary) (Result, error) {
	return r.searchLibrary(connID, request, false)
}

// SearchApprovedLibrary moves selected cards from a remote private library
// after the server layer consumes the matching one-use approval.
func (r *Room) SearchApprovedLibrary(connID string,
	request protocol.GameSearchLibrary) (Result, error) {
	return r.searchLibrary(connID, request, true)
}

func (r *Room) searchLibrary(connID string, request protocol.GameSearchLibrary,
	allowRemote bool) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	if request.FaceDown {
		request.Reveal = false
	}
	actorSeat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	sourceSeat := actorSeat
	if request.SourceSeat != nil {
		sourceSeat = *request.SourceSeat
	}
	if sourceSeat < 0 || sourceSeat >= len(r.Seats) ||
		!r.Seats[sourceSeat].Occupied {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	if sourceSeat != actorSeat && (!allowRemote ||
		strings.TrimSpace(request.ApprovalID) == "") {
		return Result{}, newError(protocol.ErrApprovalRequired)
	}
	destinationSeat := actorSeat
	if request.ToSeat != nil {
		destinationSeat = *request.ToSeat
	}
	if destinationSeat < 0 || destinationSeat >= len(r.Seats) ||
		!r.Seats[destinationSeat].Occupied {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	if sourceSeat == actorSeat && destinationSeat != actorSeat {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	if sourceSeat != actorSeat && destinationSeat != actorSeat &&
		destinationSeat != sourceSeat {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	cardIDs := append([]string(nil), request.CardIDs...)
	if len(cardIDs) == 0 && strings.TrimSpace(request.CardID) != "" {
		cardIDs = append(cardIDs, request.CardID)
	}
	if len(cardIDs) == 0 || len(cardIDs) > protocol.MaxDeckCards {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	if !validLibraryDestination(request.ToZone) {
		return Result{}, newError(protocol.ErrInvalidZone)
	}
	if request.ToZone == protocol.LibraryDestinationGraveyard ||
		request.ToZone == protocol.LibraryDestinationExile {
		destinationSeat = sourceSeat
	}
	if (request.ToZone == protocol.LibraryDestinationTop ||
		request.ToZone == protocol.LibraryDestinationBottom) &&
		destinationSeat != sourceSeat {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	if request.ToZone == protocol.LibraryDestinationBattlefield {
		if !validCardPosition(request.Position) {
			return Result{}, newError(protocol.ErrInvalidPosition)
		}
	} else if request.Position != nil {
		return Result{}, newError(protocol.ErrInvalidPosition)
	}
	if request.FaceDown && request.ToZone != protocol.LibraryDestinationBattlefield {
		return Result{}, newError(protocol.ErrInvalidMove)
	}

	sourceState := &r.Game.Seats[sourceSeat]
	actorState := &r.Game.Seats[actorSeat]
	destinationState := &r.Game.Seats[destinationSeat]
	requested := make(map[string]int, len(cardIDs))
	for index, rawID := range cardIDs {
		cardID := strings.TrimSpace(rawID)
		if cardID == "" {
			return Result{}, newError(protocol.ErrInvalidMove)
		}
		if _, duplicate := requested[cardID]; duplicate {
			return Result{}, newError(protocol.ErrInvalidMove)
		}
		requested[cardID] = index
		cardIDs[index] = cardID
	}
	selectedByID := make(map[string]protocol.GameCard, len(cardIDs))
	remaining := make([]protocol.GameCard, 0, len(sourceState.Library)-len(cardIDs))
	for _, card := range sourceState.Library {
		if _, wanted := requested[card.ID]; wanted {
			selectedByID[card.ID] = card
		} else {
			remaining = append(remaining, card)
		}
	}
	if len(selectedByID) != len(cardIDs) {
		return Result{}, newError(protocol.ErrCardNotFound)
	}
	cards := make([]protocol.GameCard, 0, len(cardIDs))
	for _, cardID := range cardIDs {
		card := selectedByID[cardID]
		card.OwnerSeat = sourceSeat
		card.Position = nil
		cards = append(cards, card)
	}
	if request.Randomize {
		if err := r.shuffle(cards); err != nil {
			return Result{}, newError(protocol.ErrGameSetupFailed)
		}
	}
	sourceState.Library = remaining

	switch request.ToZone {
	case protocol.LibraryDestinationHand:
		destinationState.Hand = append(destinationState.Hand, cards...)
	case protocol.LibraryDestinationBattlefield:
		for index := range cards {
			cards[index].Position =
				battlefieldBatchPosition(*request.Position, index, len(cards))
			cards[index].Tapped = false
			cards[index].Counters = nil
			cards[index].FaceDown = request.FaceDown
			destinationState.Battlefield =
				append(destinationState.Battlefield, cards[index])
		}
	case protocol.LibraryDestinationTop:
		sourceState.Library = append(cards, sourceState.Library...)
	case protocol.LibraryDestinationBottom:
		sourceState.Library = append(sourceState.Library, cards...)
	case protocol.LibraryDestinationGraveyard:
		destinationState.Graveyard = append(destinationState.Graveyard, cards...)
	case protocol.LibraryDestinationExile:
		destinationState.Exile = append(destinationState.Exile, cards...)
	}

	cardDescription := fmt.Sprintf("%d card(s)", len(cards))
	if request.Reveal {
		names := make([]string, 0, len(cards))
		for _, card := range cards {
			names = append(names, card.Name)
		}
		cardDescription = strings.Join(names, ", ")
	}
	libraryOwner := "their"
	if sourceSeat != actorSeat {
		libraryOwner = sourceState.DisplayName + "'s"
	}
	r.appendGameLog("library_search", actorSeat,
		fmt.Sprintf("%s searched %s library and put %s %s.",
			actorState.DisplayName, libraryOwner, cardDescription,
			r.libraryDestinationPhrase(
				request.ToZone, actorSeat, destinationSeat, request.FaceDown)))

	reply, _ := protocol.NewEnvelope(protocol.TypeGameLibrarySearched,
		protocol.GameLibrarySearched{
			RoomID:     r.ID,
			Seat:       actorSeat,
			SourceSeat: sourceSeat,
			ToSeat:     destinationSeat,
			ToZone:     request.ToZone,
			Revealed:   request.Reveal,
			Count:      len(cards),
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// ResolveLibraryView atomically resolves a private top-X view: selected cards
// move to hand, battlefield, or the source library top/bottom, and every
// remaining viewed card returns to the chosen end in explicit or randomized
// order.
func (r *Room) ResolveLibraryView(connID string,
	request protocol.GameResolveLibraryView) (Result, error) {
	return r.resolveLibraryView(connID, request, false)
}

// ResolveApprovedLibraryView resolves a remote top-X view after the server
// layer validates the corresponding one-use approval.
func (r *Room) ResolveApprovedLibraryView(connID string,
	request protocol.GameResolveLibraryView) (Result, error) {
	return r.resolveLibraryView(connID, request, true)
}

func (r *Room) resolveLibraryView(connID string,
	request protocol.GameResolveLibraryView, allowRemote bool) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	actorSeat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	sourceSeat := actorSeat
	if request.SourceSeat != nil {
		sourceSeat = *request.SourceSeat
	}
	if sourceSeat < 0 || sourceSeat >= len(r.Seats) ||
		!r.Seats[sourceSeat].Occupied {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	if sourceSeat != actorSeat && (!allowRemote ||
		strings.TrimSpace(request.ApprovalID) == "") {
		return Result{}, newError(protocol.ErrApprovalRequired)
	}
	if len(request.Assignments) > 0 {
		return r.resolveAssignedLibraryView(actorSeat, sourceSeat, request)
	}
	if request.RandomizeTop || request.RandomizeBottom {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	selectedIDs := append([]string{}, request.SelectedCardIDs...)
	remainderIDs := append([]string{}, request.RemainderCardIDs...)
	count := len(selectedIDs) + len(remainderIDs)
	sourceState := &r.Game.Seats[sourceSeat]
	destinationState := &r.Game.Seats[actorSeat]
	if count == 0 || count > protocol.MaxDeckCards || count > len(sourceState.Library) ||
		(request.RemainderPlacement != protocol.LibraryPlacementTop &&
			request.RemainderPlacement != protocol.LibraryPlacementBottom) {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	if len(selectedIDs) > 0 {
		if !validLibraryViewDestination(request.ToZone) {
			return Result{}, newError(protocol.ErrInvalidZone)
		}
		if request.ToZone == protocol.LibraryDestinationBattlefield {
			if !validCardPosition(request.Position) {
				return Result{}, newError(protocol.ErrInvalidPosition)
			}
		} else if request.Position != nil || request.FaceDown {
			return Result{}, newError(protocol.ErrInvalidMove)
		}
	} else if request.ToZone != "" || request.Position != nil || request.FaceDown {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	prefixByID := make(map[string]protocol.GameCard, count)
	for _, card := range sourceState.Library[:count] {
		prefixByID[card.ID] = card
	}
	seen := make(map[string]struct{}, count)
	resolveIDs := func(ids []string) ([]protocol.GameCard, error) {
		cards := make([]protocol.GameCard, 0, len(ids))
		for _, rawID := range ids {
			id := strings.TrimSpace(rawID)
			card, found := prefixByID[id]
			if id == "" || !found {
				return nil, newError(protocol.ErrCardNotFound)
			}
			if _, duplicate := seen[id]; duplicate {
				return nil, newError(protocol.ErrInvalidMove)
			}
			seen[id] = struct{}{}
			cards = append(cards, card)
		}
		return cards, nil
	}
	selected, err := resolveIDs(selectedIDs)
	if err != nil {
		return Result{}, err
	}
	remainder, err := resolveIDs(remainderIDs)
	if err != nil {
		return Result{}, err
	}
	if len(seen) != count {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	if request.RandomizeRemainder {
		if err := r.shuffle(remainder); err != nil {
			return Result{}, newError(protocol.ErrGameSetupFailed)
		}
	}
	for index := range selected {
		selected[index].OwnerSeat = sourceSeat
	}
	suffix := append([]protocol.GameCard{}, sourceState.Library[count:]...)
	if request.RemainderPlacement == protocol.LibraryPlacementTop {
		sourceState.Library = append(remainder, suffix...)
	} else {
		sourceState.Library = append(suffix, remainder...)
	}
	switch request.ToZone {
	case protocol.LibraryDestinationHand:
		destinationState.Hand = append(destinationState.Hand, selected...)
	case protocol.LibraryDestinationBattlefield:
		for index := range selected {
			selected[index].Position = battlefieldBatchPosition(
				*request.Position, index, len(selected))
			selected[index].Tapped = false
			selected[index].Counters = nil
			selected[index].FaceDown = request.FaceDown
			destinationState.Battlefield = append(
				destinationState.Battlefield, selected[index])
		}
	case protocol.LibraryDestinationTop:
		sourceState.Library = append(selected, sourceState.Library...)
	case protocol.LibraryDestinationBottom:
		sourceState.Library = append(sourceState.Library, selected...)
	}
	libraryOwner := "their"
	if sourceSeat != actorSeat {
		libraryOwner = sourceState.DisplayName + "'s"
	}
	logText := fmt.Sprintf("%s resolved the top %d card(s) of %s library.",
		destinationState.DisplayName, count, libraryOwner)
	if len(selected) > 0 {
		destinationSeat := actorSeat
		if request.ToZone == protocol.LibraryDestinationTop ||
			request.ToZone == protocol.LibraryDestinationBottom {
			destinationSeat = sourceSeat
		}
		logText = fmt.Sprintf(
			"%s resolved the top %d card(s) of %s library and put %d card(s) %s.",
			destinationState.DisplayName, count, libraryOwner,
			len(selected), r.libraryDestinationPhrase(
				request.ToZone, actorSeat, destinationSeat, request.FaceDown))
	}
	r.appendGameLog("library_view", actorSeat, logText)
	reply, _ := protocol.NewEnvelope(protocol.TypeGameLibraryViewResolved,
		protocol.GameLibraryViewResolved{RoomID: r.ID, Seat: actorSeat,
			MovedCount: len(selected), RemainderCount: len(remainder)})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

func (r *Room) resolveAssignedLibraryView(actorSeat, sourceSeat int,
	request protocol.GameResolveLibraryView) (Result, error) {
	if len(request.SelectedCardIDs) > 0 || len(request.RemainderCardIDs) > 0 ||
		request.ToZone != "" || request.FaceDown || request.RandomizeRemainder ||
		(request.RemainderPlacement != protocol.LibraryPlacementTop &&
			request.RemainderPlacement != protocol.LibraryPlacementBottom) {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	count := len(request.Assignments)
	sourceState := &r.Game.Seats[sourceSeat]
	actorState := &r.Game.Seats[actorSeat]
	if count == 0 || count > protocol.MaxDeckCards || count > len(sourceState.Library) {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	hasBattlefield := false
	for _, assignment := range request.Assignments {
		if !validLibraryDestination(assignment.ToZone) {
			return Result{}, newError(protocol.ErrInvalidZone)
		}
		if assignment.ToZone == protocol.LibraryDestinationBattlefield {
			hasBattlefield = true
		} else if assignment.FaceDown {
			return Result{}, newError(protocol.ErrInvalidMove)
		}
	}
	if hasBattlefield {
		if !validCardPosition(request.Position) {
			return Result{}, newError(protocol.ErrInvalidPosition)
		}
	} else if request.Position != nil {
		return Result{}, newError(protocol.ErrInvalidPosition)
	}

	prefixByID := make(map[string]protocol.GameCard, count)
	for _, card := range sourceState.Library[:count] {
		prefixByID[card.ID] = card
	}
	seen := make(map[string]struct{}, count)
	top := make([]protocol.GameCard, 0, count)
	bottom := make([]protocol.GameCard, 0, count)
	hand := make([]protocol.GameCard, 0, count)
	battlefield := make([]protocol.GameCard, 0, count)
	graveyard := make([]protocol.GameCard, 0, count)
	exile := make([]protocol.GameCard, 0, count)
	destinationKinds := make(map[string]struct{})
	for _, assignment := range request.Assignments {
		cardID := strings.TrimSpace(assignment.CardID)
		card, found := prefixByID[cardID]
		if cardID == "" || !found {
			return Result{}, newError(protocol.ErrCardNotFound)
		}
		if _, duplicate := seen[cardID]; duplicate {
			return Result{}, newError(protocol.ErrInvalidMove)
		}
		seen[cardID] = struct{}{}
		destinationKinds[assignment.ToZone] = struct{}{}
		card.OwnerSeat = sourceSeat
		card.Position = nil
		card.Tapped = false
		card.Counters = nil
		card.FaceDown = false
		switch assignment.ToZone {
		case protocol.LibraryDestinationHand:
			hand = append(hand, card)
		case protocol.LibraryDestinationBattlefield:
			card.FaceDown = assignment.FaceDown
			battlefield = append(battlefield, card)
		case protocol.LibraryDestinationGraveyard:
			graveyard = append(graveyard, card)
		case protocol.LibraryDestinationExile:
			exile = append(exile, card)
		case protocol.LibraryDestinationTop:
			top = append(top, card)
		case protocol.LibraryDestinationBottom:
			bottom = append(bottom, card)
		}
	}
	if len(seen) != count {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	if request.RandomizeTop {
		if err := r.shuffle(top); err != nil {
			return Result{}, newError(protocol.ErrGameSetupFailed)
		}
	}
	if request.RandomizeBottom {
		if err := r.shuffle(bottom); err != nil {
			return Result{}, newError(protocol.ErrGameSetupFailed)
		}
	}

	suffix := append([]protocol.GameCard{}, sourceState.Library[count:]...)
	sourceState.Library = append(top, suffix...)
	sourceState.Library = append(sourceState.Library, bottom...)
	actorState.Hand = append(actorState.Hand, hand...)
	for index := range battlefield {
		battlefield[index].Position = battlefieldBatchPosition(
			*request.Position, index, len(battlefield))
		actorState.Battlefield = append(actorState.Battlefield, battlefield[index])
	}
	sourceState.Graveyard = append(sourceState.Graveyard, graveyard...)
	sourceState.Exile = append(sourceState.Exile, exile...)

	libraryOwner := "their"
	if sourceSeat != actorSeat {
		libraryOwner = sourceState.DisplayName + "'s"
	}
	r.appendGameLog("library_view", actorSeat,
		fmt.Sprintf("%s resolved the top %d card(s) of %s library across %d destination(s).",
			actorState.DisplayName, count, libraryOwner, len(destinationKinds)))
	libraryCount := len(top) + len(bottom)
	reply, _ := protocol.NewEnvelope(protocol.TypeGameLibraryViewResolved,
		protocol.GameLibraryViewResolved{RoomID: r.ID, Seat: actorSeat,
			MovedCount: count - libraryCount, RemainderCount: libraryCount})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

func battlefieldBatchPosition(anchor protocol.CardPosition, index, count int) *protocol.CardPosition {
	columns := int(math.Ceil(math.Sqrt(float64(count))))
	rows := int(math.Ceil(float64(count) / float64(columns)))
	column := index % columns
	row := index / columns
	xSpacing := 0.09
	if columns > 1 {
		xSpacing = math.Min(xSpacing, 0.9/float64(columns-1))
	}
	ySpacing := 0.09
	if rows > 1 {
		ySpacing = math.Min(ySpacing, 0.9/float64(rows-1))
	}
	xRadius := float64(columns-1) * xSpacing / 2
	yRadius := float64(rows-1) * ySpacing / 2
	centerX := math.Max(xRadius, math.Min(1-xRadius, anchor.X))
	centerY := math.Max(yRadius, math.Min(1-yRadius, anchor.Y))
	x := centerX + (float64(column)-float64(columns-1)/2)*xSpacing
	y := centerY + (float64(row)-float64(rows-1)/2)*ySpacing
	position := protocol.CardPosition{
		X: math.Max(0, math.Min(1, x)),
		Y: math.Max(0, math.Min(1, y)),
	}
	return &position
}

// ReorderLibrary replaces the acting player's current top prefix with the same
// identities in a caller-selected order.
func (r *Room) ReorderLibrary(connID string,
	request protocol.GameReorderLibrary) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	count := len(request.CardIDs)
	if count == 0 || count > protocol.MaxDeckCards ||
		count > len(r.Game.Seats[seat].Library) {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	state := &r.Game.Seats[seat]
	prefixByID := make(map[string]protocol.GameCard, count)
	for _, card := range state.Library[:count] {
		prefixByID[card.ID] = card
	}
	ordered := make([]protocol.GameCard, 0, count)
	seen := make(map[string]struct{}, count)
	for _, rawID := range request.CardIDs {
		cardID := strings.TrimSpace(rawID)
		card, found := prefixByID[cardID]
		if cardID == "" || !found {
			return Result{}, newError(protocol.ErrCardNotFound)
		}
		if _, duplicate := seen[cardID]; duplicate {
			return Result{}, newError(protocol.ErrInvalidMove)
		}
		seen[cardID] = struct{}{}
		ordered = append(ordered, card)
	}
	state.Library = append(ordered,
		append([]protocol.GameCard(nil), state.Library[count:]...)...)
	r.appendGameLog("library_reorder", seat,
		fmt.Sprintf("%s reordered the top %d card(s) of their library.",
			state.DisplayName, count))
	reply, _ := protocol.NewEnvelope(protocol.TypeGameLibraryReordered,
		protocol.GameLibraryReordered{
			RoomID: r.ID,
			Seat:   seat,
			Count:  count,
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

func validLibraryDestination(destination string) bool {
	switch destination {
	case protocol.LibraryDestinationHand,
		protocol.LibraryDestinationBattlefield,
		protocol.LibraryDestinationTop,
		protocol.LibraryDestinationBottom,
		protocol.LibraryDestinationGraveyard,
		protocol.LibraryDestinationExile:
		return true
	default:
		return false
	}
}

func validLibraryViewDestination(destination string) bool {
	switch destination {
	case protocol.LibraryDestinationHand,
		protocol.LibraryDestinationBattlefield,
		protocol.LibraryDestinationTop,
		protocol.LibraryDestinationBottom:
		return true
	default:
		return false
	}
}

func (r *Room) libraryDestinationPhrase(destination string, actorSeat, seat int,
	faceDown bool) string {
	owner := ""
	if seat != actorSeat && seat >= 0 && seat < len(r.Game.Seats) {
		owner = r.Game.Seats[seat].DisplayName + "'s "
	}
	switch destination {
	case protocol.LibraryDestinationHand:
		return "into " + owner + "hand"
	case protocol.LibraryDestinationBattlefield:
		if faceDown {
			return "face down onto " + owner + "battlefield"
		}
		return "onto " + owner + "battlefield"
	case protocol.LibraryDestinationTop:
		return "on top of their library"
	case protocol.LibraryDestinationBottom:
		return "on bottom of their library"
	case protocol.LibraryDestinationGraveyard:
		return "into " + owner + "graveyard"
	case protocol.LibraryDestinationExile:
		return "into " + owner + "exile"
	default:
		return ""
	}
}
