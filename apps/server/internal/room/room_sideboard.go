// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"hexproof/server/internal/protocol"
	"strings"
	"time"
)

const sideboardDuration = 5 * time.Minute

func (r *Room) beginSideboard(previousLoser int, deadline time.Time) {
	players := make([]SideboardPlayerState, len(r.Seats))
	for index, seat := range r.Seats {
		players[index] = SideboardPlayerState{
			Mainboard:  cloneDeckCards(seat.Deck.Mainboard),
			Sideboard:  cloneDeckCards(seat.Deck.Sideboard),
			Commanders: append([]string{}, deckCommanderNames(*seat.Deck)...),
		}
	}
	r.Game.Sideboard = &SideboardState{
		Deadline:      deadline.UTC(),
		PreviousLoser: previousLoser,
		Players:       players,
	}
}

// SetSideboardCommander changes only the commander designation for the next
// Duel Commander game. It never moves cards or expands the registered deck.
func (r *Room) SetSideboardCommander(connID string,
	request protocol.SideboardSetCommander) (Result, error) {
	if err := r.requireStartedGame(); err != nil {
		return Result{}, err
	}
	if r.Game.Sideboard == nil {
		return Result{}, newError(protocol.ErrNotSideboarding)
	}
	if r.Format != protocol.FormatDuel {
		return Result{}, newError(protocol.ErrInvalidSideboardMove)
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	name := strings.TrimSpace(request.Name)
	player := &r.Game.Sideboard.Players[seat]
	if name == "" || !deckContainsCardName(player.Mainboard, name) {
		return Result{}, newError(protocol.ErrInvalidDeck)
	}
	index := commanderNameIndex(player.Commanders, name)
	if request.Designated {
		if index < 0 {
			if len(player.Commanders) >= protocol.MaxCommanders {
				return Result{}, newError(protocol.ErrInvalidDeck)
			}
			player.Commanders = append(player.Commanders, name)
		}
	} else if index >= 0 {
		player.Commanders = append(player.Commanders[:index], player.Commanders[index+1:]...)
	}
	player.Ready = false
	reply, _ := protocol.NewEnvelope(protocol.TypeSideboardCommanderSet,
		protocol.SideboardCommanderSet{RoomID: r.ID, Seat: seat})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// MoveSideboard moves one copy of an already-registered printing between the
// pending mainboard and sideboard. It never changes the committed match deck
// until every player locks in.
func (r *Room) MoveSideboard(connID string, request protocol.SideboardMove) (Result, error) {
	if err := r.requireStartedGame(); err != nil {
		return Result{}, err
	}
	if r.Game.Sideboard == nil {
		return Result{}, newError(protocol.ErrNotSideboarding)
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	// Duel Commander supports BO3 match pacing, but its registered deck remains
	// fixed between games. Players still use this phase to ready for the next
	// game.
	if r.Format == protocol.FormatDuel {
		return Result{}, newError(protocol.ErrInvalidSideboardMove)
	}
	if request.FromZone == request.ToZone ||
		!validSideboardZone(request.FromZone) ||
		!validSideboardZone(request.ToZone) {
		return Result{}, newError(protocol.ErrInvalidSideboardMove)
	}
	card := protocol.DeckCard{
		Name:            strings.TrimSpace(request.Name),
		Count:           1,
		SetCode:         strings.TrimSpace(request.SetCode),
		CollectorNumber: strings.TrimSpace(request.CollectorNumber),
	}
	if card.Name == "" || card.SetCode == "" || card.CollectorNumber == "" {
		return Result{}, newError(protocol.ErrInvalidSideboardMove)
	}

	player := &r.Game.Sideboard.Players[seat]
	source := &player.Mainboard
	target := &player.Sideboard
	if request.FromZone == protocol.SideboardZoneSide {
		source, target = target, source
	}
	if !moveDeckCardCopy(source, target, card) {
		return Result{}, newError(protocol.ErrInvalidSideboardMove)
	}
	player.Ready = false

	reply, _ := protocol.NewEnvelope(protocol.TypeSideboardMoved,
		protocol.SideboardMoved{RoomID: r.ID, Seat: seat})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// SetSideboardReady locks or unlocks one pending BO3 deck partition. When both
// players lock, the pending partitions commit and the previous loser starts.
func (r *Room) SetSideboardReady(connID string, ready bool) (Result, error) {
	if err := r.requireStartedGame(); err != nil {
		return Result{}, err
	}
	if r.Game.Sideboard == nil {
		return Result{}, newError(protocol.ErrNotSideboarding)
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	player := &r.Game.Sideboard.Players[seat]
	if ready && deckCardCount(player.Mainboard) < protocol.MinMainboardCards {
		return Result{}, newError(protocol.ErrInvalidDeck)
	}
	if ready && r.Format == protocol.FormatDuel &&
		(len(player.Commanders) == 0 || len(player.Commanders) > protocol.MaxCommanders) {
		return Result{}, newError(protocol.ErrInvalidDeck)
	}
	previousReady := player.Ready
	player.Ready = ready
	allReady := true
	for _, player := range r.Game.Sideboard.Players {
		if !player.Ready {
			allReady = false
			break
		}
	}

	reply, _ := protocol.NewEnvelope(protocol.TypeSideboardReadyChanged,
		protocol.SideboardReadyChanged{
			RoomID:          r.ID,
			Seat:            seat,
			Ready:           ready,
			NextGameStarted: allReady,
		})
	result := Result{Reply: &reply, ProjectGame: true}
	if allReady {
		completed, err := r.completeSideboard(protocol.SideboardEndReady, true)
		if err != nil {
			player.Ready = previousReady
			return Result{}, err
		}
		result.Broadcast = completed
	}
	return result, nil
}

// ExpireSideboard force-starts the next game with the previously committed
// deck partitions. The server layer injects now and calls this at the deadline.
func (r *Room) ExpireSideboard(now time.Time) (Result, error) {
	if err := r.requireStartedGame(); err != nil {
		return Result{}, err
	}
	if r.Game.Sideboard == nil {
		return Result{}, newError(protocol.ErrNotSideboarding)
	}
	if now.Before(r.Game.Sideboard.Deadline) {
		return Result{}, newError(protocol.ErrSideboardNotExpired)
	}
	broadcast, err := r.completeSideboard(protocol.SideboardEndTimeout, false)
	if err != nil {
		return Result{}, err
	}
	return Result{Broadcast: broadcast, ProjectGame: true}, nil
}

func (r *Room) completeSideboard(reason string, commit bool) ([]protocol.Envelope, error) {
	sideboard := r.Game.Sideboard
	if sideboard == nil {
		return nil, newError(protocol.ErrNotSideboarding)
	}
	nextGameNumber := r.Game.Number + 1
	var previousDecks []*protocol.DeckSelect
	if commit {
		if len(sideboard.Players) != len(r.Seats) {
			return nil, newError(protocol.ErrGameSetupFailed)
		}
		for index := range r.Seats {
			if r.Seats[index].Deck == nil ||
				deckCardCount(sideboard.Players[index].Mainboard) <
					protocol.MinMainboardCards {
				return nil, newError(protocol.ErrInvalidDeck)
			}
			if r.Format == protocol.FormatDuel &&
				(len(sideboard.Players[index].Commanders) == 0 ||
					len(sideboard.Players[index].Commanders) > protocol.MaxCommanders) {
				return nil, newError(protocol.ErrInvalidDeck)
			}
		}
		previousDecks = make([]*protocol.DeckSelect, len(r.Seats))
		for index := range r.Seats {
			previousDecks[index] = r.Seats[index].Deck
			deck := cloneDeck(*r.Seats[index].Deck)
			deck.Mainboard = cloneDeckCards(sideboard.Players[index].Mainboard)
			deck.Sideboard = cloneDeckCards(sideboard.Players[index].Sideboard)
			if r.Format == protocol.FormatDuel {
				deck.Commanders = append([]string{}, sideboard.Players[index].Commanders...)
				deck.Commander = deck.Commanders[0]
			}
			r.Seats[index].Deck = &deck
		}
	}
	if err := r.setupGameNumber(nextGameNumber, sideboard.PreviousLoser); err != nil {
		for index, deck := range previousDecks {
			r.Seats[index].Deck = deck
		}
		return nil, newError(protocol.ErrGameSetupFailed)
	}
	event, _ := protocol.NewEnvelope(protocol.TypeSideboardCompleted,
		protocol.SideboardCompleted{
			RoomID:     r.ID,
			GameNumber: nextGameNumber,
			Reason:     reason,
		})
	event.SeqPtr = seqPtr(r.allocSeq())
	return []protocol.Envelope{event}, nil
}

func deckContainsCardName(cards []protocol.DeckCard, name string) bool {
	for _, card := range cards {
		if strings.EqualFold(strings.TrimSpace(card.Name), name) {
			return true
		}
	}
	return false
}

func commanderNameIndex(commanders []string, name string) int {
	for index, commander := range commanders {
		if strings.EqualFold(strings.TrimSpace(commander), name) {
			return index
		}
	}
	return -1
}

func validSideboardZone(zone string) bool {
	return zone == protocol.SideboardZoneMain || zone == protocol.SideboardZoneSide
}

func deckCardMatches(left, right protocol.DeckCard) bool {
	return strings.EqualFold(strings.TrimSpace(left.Name), strings.TrimSpace(right.Name)) &&
		strings.EqualFold(strings.TrimSpace(left.SetCode), strings.TrimSpace(right.SetCode)) &&
		strings.TrimSpace(left.CollectorNumber) == strings.TrimSpace(right.CollectorNumber)
}

func moveDeckCardCopy(source, target *[]protocol.DeckCard, requested protocol.DeckCard) bool {
	sourceIndex := -1
	for index, card := range *source {
		if deckCardMatches(card, requested) {
			sourceIndex = index
			break
		}
	}
	if sourceIndex < 0 || (*source)[sourceIndex].Count <= 0 {
		return false
	}
	moved := (*source)[sourceIndex]
	moved.Count = 1
	(*source)[sourceIndex].Count--
	if (*source)[sourceIndex].Count == 0 {
		*source = append((*source)[:sourceIndex], (*source)[sourceIndex+1:]...)
	}
	for index := range *target {
		if deckCardMatches((*target)[index], moved) {
			(*target)[index].Count++
			return true
		}
	}
	*target = append(*target, moved)
	return true
}
