// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"fmt"
	"hexproof/server/internal/protocol"
)

func drawCards(state *PlayerGameState, count int) int {
	if count > len(state.Library) {
		count = len(state.Library)
	}
	if count <= 0 {
		return 0
	}
	state.Hand = append(state.Hand, state.Library[:count]...)
	state.Library = append([]protocol.GameCard(nil), state.Library[count:]...)
	return count
}

// Draw moves server-authoritative library cards into the acting player's
// private hand. The public reply and log reveal only the draw count.
func (r *Room) Draw(connID string, requestedCount int) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	state := &r.Game.Seats[seat]
	if len(state.Library) == 0 {
		return Result{}, newError(protocol.ErrLibraryEmpty)
	}
	if requestedCount < 1 || requestedCount > protocol.MaxDeckCards {
		return Result{}, newError(protocol.ErrInvalidMessage)
	}
	drawn := drawCards(state, requestedCount)
	drawDescription := "a card"
	if drawn != 1 {
		drawDescription = fmt.Sprintf("%d cards", drawn)
	}
	r.appendGameLog("draw", seat,
		fmt.Sprintf("%s drew %s.", state.DisplayName, drawDescription))
	reply, _ := protocol.NewEnvelope(protocol.TypeGameDrawn,
		protocol.GameDrawn{RoomID: r.ID, Seat: seat, Count: drawn})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// MoveLibraryCards moves the acting player's top cards to a public zone while
// keeping the hidden source identities out of the command and acknowledgement.
func (r *Room) MoveLibraryCards(connID string,
	request protocol.GameMoveLibraryCards) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	if request.Count < 1 || request.Count > protocol.MaxDeckCards {
		return Result{}, newError(protocol.ErrInvalidMessage)
	}
	if request.ToZone != protocol.ZoneGraveyard && request.ToZone != protocol.ZoneExile {
		return Result{}, newError(protocol.ErrInvalidZone)
	}
	state := &r.Game.Seats[seat]
	if len(state.Library) == 0 {
		return Result{}, newError(protocol.ErrLibraryEmpty)
	}
	count := min(request.Count, len(state.Library))
	cards := append([]protocol.GameCard(nil), state.Library[:count]...)
	state.Library = append([]protocol.GameCard(nil), state.Library[count:]...)
	for index := range cards {
		cards[index].Position = nil
		cards[index].Tapped = false
		cards[index].Counters = nil
		cards[index].FaceDown = false
	}
	if request.ToZone == protocol.ZoneGraveyard {
		state.Graveyard = append(state.Graveyard, cards...)
	} else {
		state.Exile = append(state.Exile, cards...)
	}
	r.appendGameLog("move_library_cards", seat,
		fmt.Sprintf("%s put %d card(s) from the top of their library into %s.",
			state.DisplayName, count, request.ToZone))
	reply, _ := protocol.NewEnvelope(protocol.TypeGameLibraryCardsMoved,
		protocol.GameLibraryCardsMoved{
			RoomID: r.ID,
			Seat:   seat,
			Count:  count,
			ToZone: request.ToZone,
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// ShuffleLibrary randomizes only the acting player's hidden library and
// publishes an identity-free acknowledgement and log entry.
func (r *Room) ShuffleLibrary(connID string) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	state := &r.Game.Seats[seat]
	shuffled := append([]protocol.GameCard(nil), state.Library...)
	if err := r.shuffle(shuffled); err != nil {
		return Result{}, newError(protocol.ErrGameSetupFailed)
	}
	state.Library = shuffled
	r.appendGameLog("shuffle_library", seat,
		fmt.Sprintf("%s shuffled their library.", state.DisplayName))
	reply, _ := protocol.NewEnvelope(protocol.TypeGameLibraryShuffled,
		protocol.GameLibraryShuffled{RoomID: r.ID, Seat: seat})
	return Result{Reply: &reply, ProjectGame: true}, nil
}
