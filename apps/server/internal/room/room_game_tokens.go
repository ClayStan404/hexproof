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

// CreateToken creates one English-catalog token directly on the acting
// player's battlefield. Token identity is public from creation onward.
func (r *Room) CreateToken(connID string, request protocol.GameCreateToken) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	name := strings.TrimSpace(request.Name)
	setCode := strings.TrimSpace(request.SetCode)
	collectorNumber := strings.TrimSpace(request.CollectorNumber)
	typeLine := strings.TrimSpace(request.TypeLine)
	if name == "" || !utf8.ValidString(name) ||
		utf8.RuneCountInString(name) > protocol.MaxTokenNameRunes ||
		setCode == "" || utf8.RuneCountInString(setCode) > protocol.MaxSetCodeRunes ||
		collectorNumber == "" ||
		utf8.RuneCountInString(collectorNumber) > protocol.MaxCollectorNumberRunes ||
		utf8.RuneCountInString(typeLine) > protocol.MaxTypeLineRunes ||
		!validCardPosition(request.Position) {
		return Result{}, newError(protocol.ErrInvalidToken)
	}
	for _, value := range []string{name, setCode, collectorNumber, typeLine} {
		for _, char := range value {
			if unicode.IsControl(char) {
				return Result{}, newError(protocol.ErrInvalidToken)
			}
		}
	}
	tokenCount := 0
	for _, card := range r.Game.Seats[seat].Battlefield {
		if card.Token {
			tokenCount++
		}
	}
	if tokenCount >= protocol.MaxTokensPerSeat {
		return Result{}, newError(protocol.ErrInvalidToken)
	}
	if r.Game.NextTokenID <= 0 {
		r.Game.NextTokenID = 1
	}

	cardID := fmt.Sprintf("s%d-t%d", seat, r.Game.NextTokenID)
	r.Game.NextTokenID++
	position := *request.Position
	card := protocol.GameCard{
		ID:              cardID,
		Name:            name,
		SetCode:         strings.ToUpper(setCode),
		CollectorNumber: collectorNumber,
		TypeLine:        typeLine,
		OwnerSeat:       seat,
		Position:        &position,
		Token:           true,
	}
	r.Game.Seats[seat].Battlefield = append(r.Game.Seats[seat].Battlefield, card)
	r.appendGameLog("create_token", seat,
		fmt.Sprintf("%s created a %s token.", r.Game.Seats[seat].DisplayName, name))
	reply, _ := protocol.NewEnvelope(protocol.TypeGameTokenCreated,
		protocol.GameTokenCreated{RoomID: r.ID, Seat: seat, CardID: cardID})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// AdjustCommanderTax updates the acting commander's dedicated manual tax.
func (r *Room) AdjustCommanderTax(connID string,
	request protocol.GameAdjustCommanderTax) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	if !protocol.IsCommanderFormat(r.Format) ||
		(request.Delta != 1 && request.Delta != -1) {
		return Result{}, newError(protocol.ErrInvalidCounter)
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	state := &r.Game.Seats[seat]
	commanderID := strings.TrimSpace(request.CommanderID)
	if commanderID == "" && len(state.CommanderTaxes) == 1 {
		for id := range state.CommanderTaxes {
			commanderID = id
		}
	}
	current, exists := state.CommanderTaxes[commanderID]
	if !exists {
		return Result{}, newError(protocol.ErrInvalidCounter)
	}
	next := current + request.Delta
	if next < 0 {
		return Result{}, newError(protocol.ErrInvalidCounter)
	}
	state.CommanderTaxes[commanderID] = next
	state.CommanderTax = next
	commanderName := commanderID
	if card, found := r.findOwnedCommander(seat, commanderID); found {
		commanderName = card.Name
	}
	r.appendGameLog("commander_tax", seat,
		fmt.Sprintf("%s set %s command-zone cast count to %d; additional cost is +%d.",
			state.DisplayName, commanderName, next, next*2))
	reply, _ := protocol.NewEnvelope(protocol.TypeGameCommanderTaxAdjusted,
		protocol.GameCommanderTaxAdjusted{
			RoomID:      r.ID,
			Seat:        seat,
			CommanderID: commanderID,
			Value:       next,
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// CastCommander moves one owned commander from the command zone to the shared
// stack and increments only that commander's tax in the same reducer action.
// Manual command-zone moves remain available and intentionally do not imply a
// cast or change tax.
func (r *Room) CastCommander(connID string,
	request protocol.GameCastCommander) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	if !protocol.IsCommanderFormat(r.Format) {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	commanderID := strings.TrimSpace(request.CommanderID)
	if commanderID == "" {
		return Result{}, newError(protocol.ErrInvalidMove)
	}
	state := &r.Game.Seats[seat]
	commanderIndex := -1
	for index, card := range state.CommandZone {
		if card.ID == commanderID && card.Commander && card.OwnerSeat == seat {
			commanderIndex = index
			break
		}
	}
	if commanderIndex < 0 {
		return Result{}, newError(protocol.ErrCardNotFound)
	}
	currentTax, exists := state.CommanderTaxes[commanderID]
	if !exists {
		return Result{}, newError(protocol.ErrInvalidCounter)
	}
	commander := state.CommandZone[commanderIndex]
	state.CommandZone = append(state.CommandZone[:commanderIndex],
		state.CommandZone[commanderIndex+1:]...)
	commander.Position = nil
	commander.Tapped = false
	commander.Counters = nil
	commander.FaceName = ""
	commander.FaceDown = false
	r.putOwnedCard(state, seat, protocol.ZoneStack, commander)
	nextTax := currentTax + 1
	state.CommanderTaxes[commanderID] = nextTax
	state.CommanderTax = nextTax
	r.appendGameLog("commander_cast", seat,
		fmt.Sprintf("%s cast %s from the command zone; the next additional cost is +%d.",
			state.DisplayName, commander.Name, nextTax*2))
	reply, _ := protocol.NewEnvelope(protocol.TypeGameCommanderCast,
		protocol.GameCommanderCast{
			RoomID: r.ID, Seat: seat, CommanderID: commanderID, Tax: nextTax,
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

// SetCommanderDamage updates one physical commander's public damage total
// against one player. A positive delta may optionally reduce that player's
// life in the same transaction; exact values and ordinary deltas are manual
// corrections and do not alter life.
func (r *Room) SetCommanderDamage(connID string,
	request protocol.GameSetCommanderDamage) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	if !protocol.IsCommanderFormat(r.Format) ||
		(request.Value == nil) == (request.Delta == nil) {
		return Result{}, newError(protocol.ErrInvalidCounter)
	}
	actingSeat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	commanderID := strings.TrimSpace(request.CommanderID)
	commander, controllerSeat, found := r.findDesignatedCommander(commanderID)
	if !found {
		return Result{}, newError(protocol.ErrCardNotFound)
	}
	if request.TargetSeat < 0 || request.TargetSeat >= len(r.Game.Seats) {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	allowedCorrection := actingSeat == commander.OwnerSeat ||
		actingSeat == controllerSeat || actingSeat == request.TargetSeat
	if !allowedCorrection {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	if request.ApplyToLife && (request.Delta == nil || *request.Delta <= 0 ||
		request.TargetSeat == controllerSeat ||
		actingSeat != controllerSeat) {
		return Result{}, newError(protocol.ErrInvalidCounter)
	}
	if r.Game.CommanderDamage == nil {
		r.Game.CommanderDamage = make(map[string]map[int]int)
	}
	targets := r.Game.CommanderDamage[commanderID]
	if targets == nil {
		targets = make(map[int]int)
		r.Game.CommanderDamage[commanderID] = targets
	}
	current := targets[request.TargetSeat]
	var next int64
	if request.Value != nil {
		next = int64(*request.Value)
	} else {
		next = int64(current) + int64(*request.Delta)
	}
	if next < 0 || next > int64(protocol.MaxPlayerCounterValue) {
		return Result{}, newError(protocol.ErrInvalidCounter)
	}
	target := &r.Game.Seats[request.TargetSeat]
	nextLife := target.Life
	if request.ApplyToLife {
		candidate := int64(target.Life) - int64(*request.Delta)
		if candidate < int64(protocol.MinPlayerCounterValue) ||
			candidate > int64(protocol.MaxPlayerCounterValue) {
			return Result{}, newError(protocol.ErrInvalidCounter)
		}
		nextLife = int(candidate)
	}
	targets[request.TargetSeat] = int(next)
	target.Life = nextLife
	actorName := r.Game.Seats[actingSeat].DisplayName
	if request.ApplyToLife {
		r.appendGameLog("commander_damage", actingSeat,
			fmt.Sprintf("%s recorded %d combat damage from %s to %s; commander damage is now %d.",
				actorName, *request.Delta, commander.Name,
				target.DisplayName, next))
	} else {
		r.appendGameLog("commander_damage", actingSeat,
			fmt.Sprintf("%s set commander damage from %s to %s to %d.",
				actorName, commander.Name, target.DisplayName, next))
	}
	reply, _ := protocol.NewEnvelope(protocol.TypeGameCommanderDamageSet,
		protocol.GameCommanderDamageSet{
			RoomID: r.ID, CommanderID: commanderID,
			TargetSeat: request.TargetSeat, Value: int(next),
			TargetLife: nextLife, AppliedToLife: request.ApplyToLife,
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

func (r *Room) findOwnedCommander(seat int, cardID string) (protocol.GameCard, bool) {
	card, _, found := r.findDesignatedCommander(cardID)
	return card, found && card.OwnerSeat == seat
}

// findDesignatedCommander searches every public controller zone as well as
// the owner's private zones. This preserves commander identity when control
// changes. A non-battlefield card reports its owner as controller.
func (r *Room) findDesignatedCommander(cardID string) (protocol.GameCard, int, bool) {
	if cardID == "" {
		return protocol.GameCard{}, -1, false
	}
	ownerSeat := -1
	for seatIndex, state := range r.Game.Seats {
		if _, exists := state.CommanderTaxes[cardID]; exists {
			ownerSeat = seatIndex
			break
		}
	}
	if ownerSeat < 0 {
		return protocol.GameCard{}, -1, false
	}
	for controllerSeat, state := range r.Game.Seats {
		for _, card := range state.Battlefield {
			if card.ID == cardID && card.Commander && card.OwnerSeat == ownerSeat {
				return card, controllerSeat, true
			}
		}
	}
	owner := &r.Game.Seats[ownerSeat]
	zones := [][]protocol.GameCard{owner.Library, owner.Hand, owner.Sideboard}
	for _, cards := range zones {
		for _, card := range cards {
			if card.ID == cardID && card.Commander {
				return card, ownerSeat, true
			}
		}
	}
	for _, state := range r.Game.Seats {
		publicZones := [][]protocol.GameCard{
			state.Graveyard, state.Exile, state.CommandZone,
		}
		for _, cards := range publicZones {
			for _, card := range cards {
				if card.ID == cardID && card.Commander &&
					card.OwnerSeat == ownerSeat {
					return card, ownerSeat, true
				}
			}
		}
	}
	for _, card := range r.Game.Stack {
		if card.ID == cardID && card.OwnerSeat == ownerSeat && card.Commander {
			return card.GameCard, ownerSeat, true
		}
	}
	for _, card := range r.Game.Revealed {
		if card.ID == cardID && card.OwnerSeat == ownerSeat && card.Commander {
			return card.GameCard, ownerSeat, true
		}
	}
	return protocol.GameCard{}, -1, false
}
