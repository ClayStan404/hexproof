// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"fmt"
	"strings"
	"unicode"
	"unicode/utf8"

	"hexproof/server/internal/protocol"
)

// CreateEmblem creates a public command-zone object owned by the selected
// active seat. The acting player may grant an emblem to an opponent, and its
// lifetime belongs to that owner rather than to the creating player.
func (r *Room) CreateEmblem(connID string, request protocol.GameCreateEmblem) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	actor, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	if r.RulesMode == protocol.RulesModeForge {
		return Result{}, newError(protocol.ErrRulesActionRejected)
	}
	if request.Seat == nil || *request.Seat < 0 || *request.Seat >= len(r.Game.Seats) ||
		r.Game.Seats[*request.Seat].Eliminated || r.Game.Seats[*request.Seat].DisplayName == "" {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	fields := []struct {
		value string
		limit int
	}{
		{request.Name, protocol.MaxCardNameRunes},
		{request.SetCode, protocol.MaxSetCodeRunes},
		{request.CollectorNumber, protocol.MaxCollectorNumberRunes},
		{request.TypeLine, protocol.MaxTypeLineRunes},
	}
	for index := range fields {
		value := fields[index].value
		if !utf8.ValidString(value) || utf8.RuneCountInString(value) > fields[index].limit {
			return Result{}, newError(protocol.ErrInvalidMessage)
		}
		for _, character := range value {
			if unicode.IsControl(character) {
				return Result{}, newError(protocol.ErrInvalidMessage)
			}
		}
		fields[index].value = strings.TrimSpace(value)
		if index < 3 && fields[index].value == "" {
			return Result{}, newError(protocol.ErrInvalidMessage)
		}
	}
	owner := *request.Seat
	state := &r.Game.Seats[owner]
	if len(state.Emblems) >= protocol.MaxEmblemsPerSeat {
		return Result{}, newError(protocol.ErrInvalidMessage)
	}
	if r.Game.NextEmblemID <= 0 {
		r.Game.NextEmblemID = 1
	}
	emblem := protocol.GameEmblem{
		ID:   fmt.Sprintf("s%d-e%d", owner, r.Game.NextEmblemID),
		Name: fields[0].value, SetCode: strings.ToUpper(fields[1].value),
		CollectorNumber: fields[2].value, TypeLine: fields[3].value,
	}
	r.Game.NextEmblemID++
	state.Emblems = append(state.Emblems, emblem)
	r.appendGameLog("create_emblem", actor, fmt.Sprintf("%s created a %s emblem for %s.",
		r.Game.Seats[actor].DisplayName, emblem.Name, state.DisplayName))
	reply, _ := protocol.NewEnvelope(protocol.TypeGameEmblemCreated,
		protocol.GameEmblemCreated{RoomID: r.ID, Seat: owner, EmblemID: emblem.ID})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// RemoveEmblem is an owning player's explicit correction. Emblems are never
// offered to card movement, battlefield, token, or commander reducers.
func (r *Room) RemoveEmblem(connID string, request protocol.GameRemoveEmblem) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	if r.RulesMode == protocol.RulesModeForge {
		return Result{}, newError(protocol.ErrRulesActionRejected)
	}
	state := &r.Game.Seats[seat]
	for index, emblem := range state.Emblems {
		if emblem.ID != request.EmblemID {
			continue
		}
		state.Emblems = append(state.Emblems[:index], state.Emblems[index+1:]...)
		r.appendGameLog("remove_emblem", seat,
			fmt.Sprintf("%s removed their %s emblem.", state.DisplayName, emblem.Name))
		reply, _ := protocol.NewEnvelope(protocol.TypeGameEmblemRemoved,
			protocol.GameEmblemRemoved{RoomID: r.ID, Seat: seat, EmblemID: emblem.ID})
		return Result{Reply: &reply, ProjectGame: true}, nil
	}
	return Result{}, newError(protocol.ErrInvalidTarget)
}
