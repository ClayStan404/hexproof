// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"hexproof/server/internal/protocol"
	"strings"
)

// ArrangeBattlefield atomically updates positions on the acting player's
// battlefield. It preserves every card's zone, controller, tapped state,
// counters, face, attachments, and combat declarations.
func (r *Room) ArrangeBattlefield(connID string,
	request protocol.GameArrangeBattlefield) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	if len(request.Cards) == 0 || len(request.Cards) > protocol.MaxDeckCards {
		return Result{}, newError(protocol.ErrInvalidMove)
	}

	indices := make(map[string]int, len(r.Game.Seats[seat].Battlefield))
	for index, card := range r.Game.Seats[seat].Battlefield {
		indices[card.ID] = index
	}
	positions := make(map[string]protocol.CardPosition, len(request.Cards))
	for _, placement := range request.Cards {
		cardID := strings.TrimSpace(placement.CardID)
		if cardID == "" || !validCardPosition(placement.Position) {
			return Result{}, newError(protocol.ErrInvalidPosition)
		}
		if _, duplicate := positions[cardID]; duplicate {
			return Result{}, newError(protocol.ErrInvalidMove)
		}
		if _, found := indices[cardID]; !found {
			return Result{}, newError(protocol.ErrCardNotFound)
		}
		positions[cardID] = *placement.Position
	}

	for cardID, position := range positions {
		index := indices[cardID]
		resolved := position
		r.Game.Seats[seat].Battlefield[index].Position = &resolved
	}

	reply, _ := protocol.NewEnvelope(protocol.TypeGameBattlefieldArranged,
		protocol.GameBattlefieldArranged{
			RoomID: r.ID,
			Seat:   seat,
			Count:  len(positions),
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}
