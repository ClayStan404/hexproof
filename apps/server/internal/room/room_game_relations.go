// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"fmt"
	"strings"

	"hexproof/server/internal/protocol"
)

// SetArrow updates temporary public relations. Combat sources are controlled
// battlefield cards; ordinary targets may also originate from an owned stack
// card. Empty sources clear all of the acting player's relations; sources
// without a kind clear only those sources.
func (r *Room) SetArrow(connID string, request protocol.GameSetArrow) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	sourceIDs, valid := normalizedUniqueCardIDs(
		request.SourceCardIDs, protocol.MaxCombatArrowSources)
	if !valid {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	tappedSourceIDs, valid := normalizedUniqueCardIDs(
		request.TappedSourceCardIDs, protocol.MaxCombatArrowSources)
	if !valid {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	kind := strings.TrimSpace(request.Kind)
	targetID := strings.TrimSpace(request.TargetCardID)
	clearAll := len(sourceIDs) == 0
	if clearAll && (kind != "" || targetID != "" || request.TargetSeat != nil ||
		len(tappedSourceIDs) != 0) {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	clearSources := !clearAll && kind == "" && targetID == "" && request.TargetSeat == nil
	if clearSources && len(tappedSourceIDs) != 0 {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	if !clearAll && !clearSources {
		if err := r.validateArrowTarget(seat, sourceIDs, kind, targetID,
			request.TargetSeat); err != nil {
			return Result{}, err
		}
		if !validTappedAttackSources(sourceIDs, tappedSourceIDs, kind) {
			return Result{}, newError(protocol.ErrInvalidTarget)
		}
	}

	removeSources := make(map[string]bool, len(sourceIDs))
	for _, sourceID := range sourceIDs {
		removeSources[sourceID] = true
	}
	next := r.Game.Arrows[:0]
	for _, arrow := range r.Game.Arrows {
		remove := arrow.Seat == seat && (clearAll || removeSources[arrow.SourceCardID])
		if !remove {
			next = append(next, arrow)
		}
	}
	r.Game.Arrows = next
	if !clearAll && !clearSources {
		for _, sourceID := range sourceIDs {
			arrow := protocol.GameArrow{
				Seat: seat, SourceCardID: sourceID, Kind: kind,
				TargetCardID: targetID,
			}
			if request.TargetSeat != nil {
				targetSeat := *request.TargetSeat
				arrow.TargetSeat = &targetSeat
			}
			r.Game.Arrows = append(r.Game.Arrows, arrow)
		}
		for _, sourceID := range tappedSourceIDs {
			_, cardIndex, _ := r.battlefieldCard(sourceID)
			r.Game.Seats[seat].Battlefield[cardIndex].Tapped = true
		}
		r.appendArrowLog(seat, sourceIDs, kind, targetID, request.TargetSeat)
	}
	reply, _ := protocol.NewEnvelope(protocol.TypeGameArrowSet,
		protocol.GameArrowSet{
			RoomID: r.ID, Seat: seat, SourceCardIDs: sourceIDs,
			Kind: kind, Clear: clearAll || clearSources,
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

func validTappedAttackSources(sourceIDs, tappedSourceIDs []string, kind string) bool {
	if len(tappedSourceIDs) == 0 {
		return true
	}
	if kind != protocol.ArrowKindAttack {
		return false
	}
	sources := make(map[string]bool, len(sourceIDs))
	for _, sourceID := range sourceIDs {
		sources[sourceID] = true
	}
	for _, sourceID := range tappedSourceIDs {
		if !sources[sourceID] {
			return false
		}
	}
	return true
}

func normalizedUniqueCardIDs(raw []string, maximum int) ([]string, bool) {
	if len(raw) > maximum {
		return nil, false
	}
	result := make([]string, 0, len(raw))
	seen := make(map[string]bool, len(raw))
	for _, rawID := range raw {
		cardID := strings.TrimSpace(rawID)
		if cardID == "" || seen[cardID] {
			return nil, false
		}
		seen[cardID] = true
		result = append(result, cardID)
	}
	return result, true
}

func (r *Room) validateArrowTarget(seat int, sourceIDs []string, kind,
	targetID string, targetSeat *int) error {
	switch kind {
	case protocol.ArrowKindAttack:
		if !r.validBattlefieldArrowSources(seat, sourceIDs) {
			return newError(protocol.ErrInvalidTarget)
		}
		if seat != r.Game.ActiveSeat ||
			r.Game.CurrentPhase != protocol.GamePhaseDeclareAttackers {
			return newError(protocol.ErrInvalidTarget)
		}
		hasCardTarget := targetID != ""
		hasSeatTarget := targetSeat != nil
		if hasCardTarget == hasSeatTarget {
			return newError(protocol.ErrInvalidTarget)
		}
		if hasCardTarget {
			controlledBy, _, found := r.battlefieldCard(targetID)
			if !found || controlledBy == seat || r.Game.Seats[controlledBy].Eliminated {
				return newError(protocol.ErrInvalidTarget)
			}
		} else if *targetSeat == seat || *targetSeat < 0 ||
			*targetSeat >= len(r.Game.Seats) ||
			r.Game.Seats[*targetSeat].Eliminated {
			return newError(protocol.ErrInvalidTarget)
		}
	case protocol.ArrowKindBlock:
		if !r.validBattlefieldArrowSources(seat, sourceIDs) {
			return newError(protocol.ErrInvalidTarget)
		}
		if r.Game.CurrentPhase != protocol.GamePhaseDeclareBlockers ||
			targetID == "" || targetSeat != nil {
			return newError(protocol.ErrInvalidTarget)
		}
		attackFound := false
		for _, arrow := range r.Game.Arrows {
			if arrow.Kind != protocol.ArrowKindAttack ||
				arrow.SourceCardID != targetID {
				continue
			}
			targetsPlayer := arrow.TargetSeat != nil && *arrow.TargetSeat == seat
			controlledBy, _, cardFound := r.battlefieldCard(arrow.TargetCardID)
			targetsPermanent := arrow.TargetCardID != "" && cardFound &&
				controlledBy == seat
			if targetsPlayer || targetsPermanent {
				attackFound = true
				break
			}
		}
		if !attackFound {
			return newError(protocol.ErrInvalidTarget)
		}
	case protocol.ArrowKindTarget:
		if !r.validTargetArrowSources(seat, sourceIDs) {
			return newError(protocol.ErrInvalidTarget)
		}
		hasCardTarget := targetID != ""
		hasSeatTarget := targetSeat != nil
		if hasCardTarget == hasSeatTarget {
			return newError(protocol.ErrInvalidTarget)
		}
		if hasCardTarget {
			if !r.battlefieldCardExists(targetID) {
				return newError(protocol.ErrInvalidTarget)
			}
			for _, sourceID := range sourceIDs {
				if sourceID == targetID {
					return newError(protocol.ErrInvalidTarget)
				}
			}
		} else if *targetSeat < 0 || *targetSeat >= len(r.Game.Seats) ||
			r.Game.Seats[*targetSeat].Eliminated {
			return newError(protocol.ErrInvalidTarget)
		}
	default:
		return newError(protocol.ErrInvalidTarget)
	}
	return nil
}

func (r *Room) validBattlefieldArrowSources(seat int, sourceIDs []string) bool {
	for _, sourceID := range sourceIDs {
		sourceSeat, _, found := r.battlefieldCard(sourceID)
		if !found || sourceSeat != seat {
			return false
		}
	}
	return true
}

func (r *Room) validTargetArrowSources(seat int, sourceIDs []string) bool {
	for _, sourceID := range sourceIDs {
		sourceSeat, _, found := r.battlefieldCard(sourceID)
		if found && sourceSeat == seat {
			continue
		}
		stackSource := false
		for _, shared := range r.Game.Stack {
			if shared.ID == sourceID && shared.OwnerSeat == seat {
				stackSource = true
				break
			}
		}
		if !stackSource {
			return false
		}
	}
	return true
}

func (r *Room) appendArrowLog(seat int, sourceIDs []string, kind, targetID string,
	targetSeat *int) {
	count := len(sourceIDs)
	switch kind {
	case protocol.ArrowKindAttack:
		if targetSeat != nil {
			r.appendGameLog("combat", seat,
				fmt.Sprintf("%s declared %d attacker(s) toward %s.",
					r.Game.Seats[seat].DisplayName, count,
					r.Game.Seats[*targetSeat].DisplayName))
		} else if controlledBy, _, found := r.battlefieldCard(targetID); found {
			r.appendGameLog("combat", seat,
				fmt.Sprintf("%s declared %d attacker(s) toward a battlefield permanent controlled by %s.",
					r.Game.Seats[seat].DisplayName, count,
					r.Game.Seats[controlledBy].DisplayName))
		}
	case protocol.ArrowKindBlock:
		r.appendGameLog("combat", seat,
			fmt.Sprintf("%s declared %d blocker(s).",
				r.Game.Seats[seat].DisplayName, count))
	}
}

// SetAttachment attaches one of the acting player's battlefield cards to any
// unattached battlefield card, or detaches it when TargetCardID is empty.
func (r *Room) SetAttachment(connID string,
	request protocol.GameSetAttachment) (Result, error) {
	if err := r.requireActiveGame(); err != nil {
		return Result{}, err
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	sourceID := strings.TrimSpace(request.SourceCardID)
	targetID := strings.TrimSpace(request.TargetCardID)
	sourceSeat, sourceIndex, found := r.battlefieldCard(sourceID)
	if !found ||
		r.Game.Seats[sourceSeat].Battlefield[sourceIndex].OwnerSeat != seat {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	if targetID != "" {
		if targetID == sourceID || !r.battlefieldCardExists(targetID) {
			return Result{}, newError(protocol.ErrInvalidTarget)
		}
		for _, attachment := range r.Game.Attachments {
			if attachment.SourceCardID == targetID {
				return Result{}, newError(protocol.ErrInvalidTarget)
			}
		}
	}
	next := r.Game.Attachments[:0]
	for _, attachment := range r.Game.Attachments {
		remove := attachment.SourceCardID == sourceID
		if targetID != "" {
			remove = remove || attachment.TargetCardID == sourceID
		}
		if !remove {
			next = append(next, attachment)
		}
	}
	r.Game.Attachments = next
	detached := targetID == ""
	if !detached {
		r.Game.Attachments = append(r.Game.Attachments, protocol.GameAttachment{
			OwnerSeat: seat, SourceCardID: sourceID, TargetCardID: targetID,
		})
		r.snapSameLaneAttachment(sourceID, targetID)
		r.appendGameLog("attach", seat,
			fmt.Sprintf("%s attached a permanent.", r.Game.Seats[seat].DisplayName))
	} else {
		r.appendGameLog("detach", seat,
			fmt.Sprintf("%s detached a permanent.", r.Game.Seats[seat].DisplayName))
	}
	r.removeArrowsForCard(sourceID)
	reply, _ := protocol.NewEnvelope(protocol.TypeGameAttachmentSet,
		protocol.GameAttachmentSet{
			RoomID: r.ID, OwnerSeat: seat,
			SourceCardID: sourceID, Detached: detached,
		})
	return Result{Reply: &reply, ProjectGame: true}, nil
}

const (
	attachmentStackStepX = 0.04
	attachmentStackStepY = 0.05
)

func attachmentStackPosition(base protocol.CardPosition, index int) protocol.CardPosition {
	step := float64(index + 1)
	return protocol.CardPosition{
		X: clampUnit(base.X + attachmentStackStepX*step),
		Y: clampUnit(base.Y + attachmentStackStepY*step),
	}
}

func clampUnit(value float64) float64 {
	if value < 0 {
		return 0
	}
	if value > 1 {
		return 1
	}
	return value
}

func (r *Room) snapSameLaneAttachment(sourceID, targetID string) {
	sourceSeat, sourceIndex, found := r.battlefieldCard(sourceID)
	if !found {
		return
	}
	targetSeat, targetIndex, found := r.battlefieldCard(targetID)
	if !found || sourceSeat != targetSeat {
		return
	}
	target := r.Game.Seats[targetSeat].Battlefield[targetIndex]
	if target.Position == nil {
		return
	}
	stackIndex := 0
	for _, attachment := range r.Game.Attachments {
		if attachment.TargetCardID != targetID ||
			attachment.SourceCardID == sourceID {
			continue
		}
		attachedSeat, _, attached := r.battlefieldCard(attachment.SourceCardID)
		if attached && attachedSeat == targetSeat {
			stackIndex++
		}
	}
	position := attachmentStackPosition(*target.Position, stackIndex)
	r.Game.Seats[sourceSeat].Battlefield[sourceIndex].Position = &position
}

func (r *Room) shiftSameLaneAttachments(targetID string, seat int,
	oldPosition, newPosition *protocol.CardPosition) {
	if oldPosition == nil || newPosition == nil {
		return
	}
	dx := newPosition.X - oldPosition.X
	dy := newPosition.Y - oldPosition.Y
	if dx == 0 && dy == 0 {
		return
	}
	for _, attachment := range r.Game.Attachments {
		if attachment.TargetCardID != targetID {
			continue
		}
		sourceSeat, sourceIndex, found := r.battlefieldCard(attachment.SourceCardID)
		if !found || sourceSeat != seat {
			continue
		}
		current := r.Game.Seats[sourceSeat].Battlefield[sourceIndex].Position
		if current == nil {
			continue
		}
		next := protocol.CardPosition{
			X: clampUnit(current.X + dx),
			Y: clampUnit(current.Y + dy),
		}
		r.Game.Seats[sourceSeat].Battlefield[sourceIndex].Position = &next
	}
}

func (r *Room) battlefieldCard(cardID string) (int, int, bool) {
	for seat := range r.Game.Seats {
		for index := range r.Game.Seats[seat].Battlefield {
			if r.Game.Seats[seat].Battlefield[index].ID == cardID {
				return seat, index, true
			}
		}
	}
	return -1, -1, false
}

func (r *Room) battlefieldCardExists(cardID string) bool {
	_, _, found := r.battlefieldCard(cardID)
	return found
}

func (r *Room) removeArrowsForCard(cardID string) {
	next := r.Game.Arrows[:0]
	for _, arrow := range r.Game.Arrows {
		if arrow.SourceCardID != cardID && arrow.TargetCardID != cardID {
			next = append(next, arrow)
		}
	}
	r.Game.Arrows = next
}

func (r *Room) removeCardRelations(cardID string) {
	r.removeArrowsForCard(cardID)
	next := r.Game.Attachments[:0]
	for _, attachment := range r.Game.Attachments {
		if attachment.SourceCardID != cardID &&
			attachment.TargetCardID != cardID {
			next = append(next, attachment)
		}
	}
	r.Game.Attachments = next
}
