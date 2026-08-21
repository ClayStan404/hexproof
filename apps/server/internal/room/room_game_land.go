// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"fmt"
	"strings"

	"hexproof/server/internal/protocol"
)

// PlayLand atomically moves one owned hand card to the active player's
// battlefield and increments the public recorded land-play count. Printed
// type, phase, stack state, and the ordinary one-play allowance remain
// advisory client checks so card effects and table agreements can override
// them without a special server bypass.
func (r *Room) PlayLand(connID string,
	request protocol.GamePlayLand) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	if seat != r.Game.ActiveSeat {
		return Result{}, newError(protocol.ErrNotActivePlayer)
	}

	cardID := strings.TrimSpace(request.CardID)
	faceName := strings.TrimSpace(request.FaceName)
	if cardID == "" || !validCardPosition(request.Position) ||
		!validCardFaceName(faceName) ||
		r.Game.LandPlaysThisTurn < 0 ||
		r.Game.LandPlaysThisTurn >= protocol.MaxPlayerCounterValue {
		return Result{}, newError(protocol.ErrInvalidMove)
	}

	state := &r.Game.Seats[seat]
	cardIndex := -1
	for index := range state.Hand {
		if state.Hand[index].ID == cardID && state.Hand[index].OwnerSeat == seat {
			cardIndex = index
			break
		}
	}
	if cardIndex < 0 {
		return Result{}, newError(protocol.ErrCardNotFound)
	}

	card := state.Hand[cardIndex]
	position := *request.Position
	card.Position = &position
	card.FaceName = faceName
	card.FaceDown = false
	card.Tapped = false
	card.Counters = nil

	state.Hand = append(state.Hand[:cardIndex], state.Hand[cardIndex+1:]...)
	state.Battlefield = append(state.Battlefield, card)
	r.Game.LandPlaysThisTurn++

	displayName := card.Name
	if faceName != "" {
		displayName = faceName
	}
	r.appendGameLog("land_play", seat,
		fmt.Sprintf("%s recorded %s as land play %d this turn.",
			state.DisplayName, displayName, r.Game.LandPlaysThisTurn))
	reply, _ := protocol.NewEnvelope(protocol.TypeGameLandPlayed,
		protocol.GameLandPlayed{
			RoomID: r.ID,
			Seat:   seat,
			CardID: card.ID,
			Count:  r.Game.LandPlaysThisTurn,
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// SetLandPlayCount manually corrects the active turn's public recorded count.
// It does not move a card or enforce an ordinary land-play allowance.
func (r *Room) SetLandPlayCount(connID string,
	request protocol.GameSetLandPlayCount) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	if seat != r.Game.ActiveSeat {
		return Result{}, newError(protocol.ErrNotActivePlayer)
	}
	if request.Value < 0 || request.Value > protocol.MaxPlayerCounterValue {
		return Result{}, newError(protocol.ErrInvalidCounter)
	}

	reply, _ := protocol.NewEnvelope(protocol.TypeGameLandPlayCountSet,
		protocol.GameLandPlayCountSet{
			RoomID: r.ID,
			Seat:   seat,
			Value:  request.Value,
		})
	if request.Value == r.Game.LandPlaysThisTurn {
		return Result{Reply: &reply}, nil
	}
	r.Game.LandPlaysThisTurn = request.Value
	r.appendGameLog("land_play_count", seat,
		fmt.Sprintf("%s set recorded land plays this turn to %d.",
			r.Game.Seats[seat].DisplayName, request.Value))
	return Result{Reply: &reply, ProjectGame: true}, nil
}
