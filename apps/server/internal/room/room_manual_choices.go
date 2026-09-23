// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"fmt"
	"hexproof/server/internal/protocol"
)

// ChooseStartingPlayer is available only to the previous loser before locking in.
func (r *Room) ChooseStartingPlayer(connID string, request protocol.SideboardChooseStartingPlayer) (Result, error) {
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
	sideboard := r.Game.Sideboard
	if r.RulesMode == protocol.RulesModeForge || seat != sideboard.PreviousLoser ||
		request.StartingSeat < 0 || request.StartingSeat >= len(r.Seats) || !r.Seats[request.StartingSeat].Occupied {
		return Result{}, newError(protocol.ErrInvalidMessage)
	}
	chosen := request.StartingSeat
	sideboard.ChosenStartingSeat = &chosen
	sideboard.Players[seat].Ready = false
	reply, _ := protocol.NewEnvelope(protocol.TypeSideboardStartingPlayerChosen,
		protocol.SideboardStartingPlayerChosen{RoomID: r.ID, StartingSeat: chosen})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// SetLibraryTopRevealed changes public visibility without moving or fixing a card.
// Projection derives the top card after every atomic library mutation.
func (r *Room) SetLibraryTopRevealed(connID string, request protocol.GameSetLibraryTopRevealed) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	if r.RulesMode == protocol.RulesModeForge {
		return Result{}, newError(protocol.ErrInvalidMessage)
	}
	player := &r.Game.Seats[seat]
	if player.LibraryTopRevealed != request.Revealed {
		player.LibraryTopRevealed = request.Revealed
		action := "stopped playing with their library top revealed"
		if request.Revealed {
			action = "is playing with their library top revealed"
		}
		r.appendGameLog("library_top_revealed", seat, fmt.Sprintf("%s %s.", player.DisplayName, action))
	}
	reply, _ := protocol.NewEnvelope(protocol.TypeGameLibraryTopRevealedSet,
		protocol.GameLibraryTopRevealedSet{RoomID: r.ID, Seat: seat, Revealed: request.Revealed})
	return Result{Reply: &reply, ProjectGame: true}, nil
}
