// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"fmt"
	"hexproof/server/internal/protocol"
	"strings"
	"unicode"
	"unicode/utf8"
)

// SetCardFace changes only the rendered face of a controlled battlefield card.
// Card-face legality remains a manual tabletop decision.
func (r *Room) SetCardFace(connID string,
	request protocol.GameSetCardFace) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	cardID := strings.TrimSpace(request.CardID)
	faceName := strings.TrimSpace(request.FaceName)
	if cardID == "" || !validCardFaceName(faceName) {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	cardSeat, cardIndex, found := r.battlefieldCard(cardID)
	if !found {
		return Result{}, newError(protocol.ErrCardNotFound)
	}
	card := &r.Game.Seats[cardSeat].Battlefield[cardIndex]
	if cardSeat != seat {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	card.FaceName = faceName
	reply, _ := protocol.NewEnvelope(protocol.TypeGameCardFaceSet,
		protocol.GameCardFaceSet{
			RoomID: r.ID, Seat: seat, CardID: card.ID, FaceName: faceName,
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

func validCardFaceName(name string) bool {
	if !utf8.ValidString(name) ||
		utf8.RuneCountInString(name) > protocol.MaxCardFaceNameRunes {
		return false
	}
	for _, char := range name {
		if unicode.IsControl(char) {
			return false
		}
	}
	return true
}

// SetFaceDown changes persistent battlefield visibility without changing
// public orientation, counters, position, ownership, or control.
func (r *Room) SetFaceDown(connID string,
	request protocol.GameSetFaceDown) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	cardID := strings.TrimSpace(request.CardID)
	cardSeat, cardIndex, found := r.battlefieldCard(cardID)
	if cardID == "" || !found {
		return Result{}, newError(protocol.ErrCardNotFound)
	}
	card := &r.Game.Seats[cardSeat].Battlefield[cardIndex]
	if cardSeat != seat {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	reply, _ := protocol.NewEnvelope(protocol.TypeGameFaceDownSet,
		protocol.GameFaceDownSet{
			RoomID: r.ID, Seat: seat, CardID: card.ID,
			FaceDown: request.FaceDown,
		})
	if card.FaceDown == request.FaceDown {
		return Result{Reply: &reply}, nil
	}
	card.FaceDown = request.FaceDown
	if card.FaceDown {
		card.FaceName = ""
	}
	action := "face up"
	if card.FaceDown {
		action = "face down"
	}
	r.appendGameLog("face_down", seat,
		fmt.Sprintf("%s turned a battlefield card %s.",
			r.Game.Seats[seat].DisplayName, action))
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// SetTapped changes the orientation of one permanent controlled by the acting
// seat. This is shared manual-tabletop state, not an automatic rules action.
func (r *Room) SetTapped(connID string, request protocol.GameSetTapped) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	cardID := strings.TrimSpace(request.CardID)
	if cardID == "" {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	cardSeat, cardIndex, found := r.battlefieldCard(cardID)
	if !found || cardSeat != seat {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	card := &r.Game.Seats[cardSeat].Battlefield[cardIndex]
	card.Tapped = request.Tapped
	reply, _ := protocol.NewEnvelope(protocol.TypeGameTappedSet,
		protocol.GameTappedSet{
			RoomID: r.ID,
			Seat:   seat,
			CardID: card.ID,
			Tapped: card.Tapped,
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// SetCardCounter mutates public counter state on a permanent controlled by the
// acting seat. Number counters are unnamed; ability counters have stable
// server-assigned ids and user-provided labels.
func (r *Room) SetCardCounter(connID string,
	request protocol.GameSetCardCounter) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	cardID := strings.TrimSpace(request.CardID)
	cardSeat, cardIndex, found := r.battlefieldCard(cardID)
	if cardID == "" || !found || cardSeat != seat {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	if (request.Value == nil) == (request.Delta == nil) {
		return Result{}, newError(protocol.ErrInvalidCounter)
	}
	card := &r.Game.Seats[cardSeat].Battlefield[cardIndex]

	kind := strings.TrimSpace(request.Kind)
	counterID := strings.TrimSpace(request.CounterID)
	label := strings.TrimSpace(request.Label)
	creatingAbility := kind == protocol.CardCounterKindAbility && counterID == ""
	if kind == protocol.CardCounterKindNumber {
		counterID = protocol.CardNumberCounterID
		if label != "" {
			return Result{}, newError(protocol.ErrInvalidCounter)
		}
	} else if kind == protocol.CardCounterKindAbility {
		if creatingAbility {
			if !validCardCounterLabel(label) {
				return Result{}, newError(protocol.ErrInvalidCounter)
			}
			abilityCounterCount := 0
			for _, counter := range card.Counters {
				if counter.Kind == protocol.CardCounterKindAbility {
					abilityCounterCount++
				}
			}
			if abilityCounterCount >= protocol.MaxCardAbilityCounters {
				return Result{}, newError(protocol.ErrInvalidCounter)
			}
			if r.Game.NextCardCounterID <= 0 {
				r.Game.NextCardCounterID = 1
			}
			counterID = fmt.Sprintf("ability-%d", r.Game.NextCardCounterID)
			r.Game.NextCardCounterID++
		}
	} else {
		return Result{}, newError(protocol.ErrInvalidCounter)
	}

	counterIndex := -1
	for index := range card.Counters {
		if card.Counters[index].ID == counterID {
			counterIndex = index
			break
		}
	}
	currentValue := 0
	if counterIndex >= 0 {
		counter := card.Counters[counterIndex]
		if counter.Kind != kind {
			return Result{}, newError(protocol.ErrInvalidCounter)
		}
		currentValue = counter.Value
		if kind == protocol.CardCounterKindAbility {
			label = counter.Label
		}
	} else if kind == protocol.CardCounterKindAbility {
		if !creatingAbility || label == "" {
			return Result{}, newError(protocol.ErrInvalidCounter)
		}
	}

	nextValue := int64(currentValue)
	if request.Value != nil {
		nextValue = int64(*request.Value)
	} else {
		nextValue += int64(*request.Delta)
	}
	if nextValue < 0 || nextValue > int64(protocol.MaxPlayerCounterValue) {
		return Result{}, newError(protocol.ErrInvalidCounter)
	}

	counter := protocol.GameCardCounter{
		ID: counterID, Kind: kind, Label: label, Value: int(nextValue),
	}
	removed := counter.Value == 0
	if removed {
		if counterIndex >= 0 {
			card.Counters = append(card.Counters[:counterIndex],
				card.Counters[counterIndex+1:]...)
		}
	} else if counterIndex >= 0 {
		card.Counters[counterIndex] = counter
	} else {
		card.Counters = append(card.Counters, counter)
	}

	counterName := "number"
	if kind == protocol.CardCounterKindAbility {
		counterName = label
	}
	cardLogName := card.Name
	if card.FaceDown {
		cardLogName = "a face-down card"
	} else if strings.TrimSpace(cardLogName) == "" {
		cardLogName = "a card"
	}
	r.appendGameLog("card_counter", seat,
		fmt.Sprintf("%s set %s on %s to %d.",
			r.Game.Seats[seat].DisplayName, counterName, cardLogName, counter.Value))
	reply, _ := protocol.NewEnvelope(protocol.TypeGameCardCounterSet,
		protocol.GameCardCounterSet{
			RoomID: r.ID, Seat: seat, CardID: card.ID,
			Counter: counter, Removed: removed,
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

func validCardCounterLabel(label string) bool {
	if label == "" || !utf8.ValidString(label) ||
		utf8.RuneCountInString(label) > protocol.MaxCardCounterLabelRunes {
		return false
	}
	for _, char := range label {
		if unicode.IsControl(char) {
			return false
		}
	}
	return true
}
