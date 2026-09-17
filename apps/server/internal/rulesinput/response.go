// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Package rulesinput validates the same typed choices on hub and peer paths.
package rulesinput

import (
	"encoding/json"
	"errors"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
	"strings"
)

func Valid(request protocol.RulesRespond) bool {
	return (request.PeerBinding == "" || len(request.PeerBinding) == 64) && request.PromptID > 0 && strings.TrimSpace(request.ResponseID) != "" && len(request.ResponseID) <= 128 && len(request.Name) <= 1024 &&
		validSelectionIDs(request.CardIDs, false) && validSelectionIDs(request.TargetIDs, true) &&
		validChoiceIDs(request.ChoiceIDs) && validOrderIDs(request.OrderedIDs) && ValidScryPiles(request.ScryPiles) &&
		validAssignments(request.Assignments) && validDamageOrderIDs(request.DamageOrderIDs) && validDamageAssignments(request.DamageAssignments)
}

// Build does not authorize the room or public prompt identifier. The caller
// must bind those to the current player and decision before calling it.
func Build(request protocol.RulesRespond, raw json.RawMessage, player int) (json.RawMessage, error) {
	view, err := forge.NormalizePrompt(raw)
	if err != nil || !Valid(request) || view.PlayerIndex != player {
		return nil, errors.New("invalid Forge response")
	}
	if view.Kind == "chooseCombatDamageAssignment" {
		targets := make([]protocol.RulesPromptDamageTarget, 0, len(view.DamageTargets))
		for _, target := range view.DamageTargets {
			lethal := -1
			if target.Kind == "card" && !target.Defender {
				if target.LethalDamage == nil || *target.LethalDamage < 0 || *target.LethalDamage > 100000 {
					return nil, errors.New("invalid damage threshold")
				}
				lethal = *target.LethalDamage
			} else if target.Kind != "card" && target.Kind != "player" && target.Kind != "defender" {
				return nil, errors.New("invalid damage target")
			}
			targets = append(targets, protocol.RulesPromptDamageTarget{ResponseID: target.ResponseID, LethalDamage: lethal})
		}
		if !ValidDamageDistribution(targets, view.TotalDamage, view.DamageAssignmentMode, request.DamageAssignments) {
			return nil, errors.New("invalid combat damage distribution")
		}
	}
	return forge.BuildPromptResponse(raw, player, view.PromptID, forge.PromptResponse{
		ResponseID: request.ResponseID, CardIDs: request.CardIDs, TargetIDs: request.TargetIDs,
		Assignments: promptAssignments(request.Assignments), ChoiceIDs: request.ChoiceIDs, OrderedIDs: request.OrderedIDs,
		ScryPiles: promptScryPiles(request.ScryPiles), DamageOrderIDs: request.DamageOrderIDs,
		DamageAssignments: DamageAssignments(request.DamageAssignments), ChosenNumber: request.ChosenNumber, Name: request.Name,
	})
}

func validChoiceIDs(ids []string) bool {
	if len(ids) > 512 {
		return false
	}
	for _, id := range ids {
		if len(id) > 128 || !strings.HasPrefix(id, "choice:") {
			return false
		}
	}
	return true
}

func validAssignments(assignments []protocol.RulesPromptAssignment) bool {
	if len(assignments) > 512 {
		return false
	}
	for _, assignment := range assignments {
		if len(assignment.SourceID) > 128 || len(assignment.TargetID) > 128 ||
			!strings.HasPrefix(assignment.SourceID, "combat-source:") ||
			!strings.HasPrefix(assignment.TargetID, "combat-target:") {
			return false
		}
	}
	return true
}

func promptAssignments(assignments []protocol.RulesPromptAssignment) []forge.PromptAssignment {
	result := make([]forge.PromptAssignment, 0, len(assignments))
	for _, assignment := range assignments {
		result = append(result, forge.PromptAssignment{
			SourceID: assignment.SourceID, TargetID: assignment.TargetID,
		})
	}
	return result
}

func validDamageOrderIDs(ids []string) bool {
	if len(ids) > 512 {
		return false
	}
	seen := make(map[string]struct{}, len(ids))
	for _, id := range ids {
		if len(id) > 128 || !strings.HasPrefix(id, "damage-target:") {
			return false
		}
		if _, duplicate := seen[id]; duplicate {
			return false
		}
		seen[id] = struct{}{}
	}
	return true
}

func validDamageAssignments(assignments []protocol.RulesPromptDamageAssignment) bool {
	if len(assignments) > 512 {
		return false
	}
	seen := make(map[string]struct{}, len(assignments))
	for _, assignment := range assignments {
		if len(assignment.TargetID) > 128 ||
			!strings.HasPrefix(assignment.TargetID, "damage-target:") || assignment.Damage < 0 {
			return false
		}
		if _, duplicate := seen[assignment.TargetID]; duplicate {
			return false
		}
		seen[assignment.TargetID] = struct{}{}
	}
	return true
}

func DamageAssignmentMode(mode string) (string, bool) {
	switch mode {
	case protocol.RulesDamageOrdered, protocol.RulesDamageUnordered, protocol.RulesDamageDivideFreely:
		return mode, true
	default:
		return "", false
	}
}

func ValidDamageDistribution(targets []protocol.RulesPromptDamageTarget, totalDamage int, mode string,
	assignments []protocol.RulesPromptDamageAssignment) bool {
	mode, supported := DamageAssignmentMode(mode)
	if !supported || totalDamage < 0 || len(assignments) != len(targets) {
		return false
	}
	assigned := make(map[string]int, len(assignments))
	total := 0
	for _, assignment := range assignments {
		if assignment.Damage < 0 {
			return false
		}
		if _, duplicate := assigned[assignment.TargetID]; duplicate {
			return false
		}
		assigned[assignment.TargetID] = assignment.Damage
		if assignment.Damage > totalDamage-total {
			return false
		}
		total += assignment.Damage
	}
	if total != totalDamage {
		return false
	}
	laterDamage := 0
	defenderDamage := 0
	for index := len(targets) - 1; index >= 0; index-- {
		target := targets[index]
		damage, exists := assigned[target.ResponseID]
		if !exists {
			return false
		}
		gatedDamage := laterDamage
		if mode == protocol.RulesDamageUnordered {
			gatedDamage = defenderDamage
		} else if mode == protocol.RulesDamageDivideFreely {
			gatedDamage = 0
		}
		if gatedDamage > 0 && target.LethalDamage >= 0 && damage < target.LethalDamage {
			return false
		}
		if target.LethalDamage == -1 {
			defenderDamage += damage
		}
		laterDamage += damage
	}
	return true
}

func DamageAssignments(assignments []protocol.RulesPromptDamageAssignment) []forge.PromptDamageAssignment {
	result := make([]forge.PromptDamageAssignment, 0, len(assignments))
	for _, assignment := range assignments {
		result = append(result, forge.PromptDamageAssignment{
			TargetID: assignment.TargetID, Damage: assignment.Damage,
		})
	}
	return result
}

func validSelectionIDs(ids []string, opaque bool) bool {
	if len(ids) > 512 {
		return false
	}
	for _, id := range ids {
		if strings.TrimSpace(id) == "" || len(id) > 512 ||
			(opaque && !strings.HasPrefix(id, "target:")) {
			return false
		}
	}
	return true
}

func validOrderIDs(ids []string) bool {
	if len(ids) > 512 {
		return false
	}
	for _, id := range ids {
		if len(id) > 128 || !strings.HasPrefix(id, "order:") {
			return false
		}
	}
	return true
}

func ValidScryPiles(piles []protocol.RulesPromptScryPile) bool {
	if len(piles) > 5 {
		return false
	}
	seen := make(map[string]struct{})
	seenDestinations := make(map[string]struct{}, len(piles))
	total := 0
	for _, pile := range piles {
		if _, supported := map[string]struct{}{
			"libraryTop": {}, "libraryBottom": {}, "graveyard": {}, "exile": {}, "hand": {},
		}[pile.Destination]; !supported {
			return false
		}
		if _, duplicate := seenDestinations[pile.Destination]; duplicate {
			return false
		}
		seenDestinations[pile.Destination] = struct{}{}
		for _, id := range pile.CardIDs {
			total++
			if total > 512 || len(id) > 128 || !strings.HasPrefix(id, "scry:") {
				return false
			}
			if _, duplicate := seen[id]; duplicate {
				return false
			}
			seen[id] = struct{}{}
		}
	}
	return true
}

func promptScryPiles(piles []protocol.RulesPromptScryPile) []forge.PromptScryPile {
	result := make([]forge.PromptScryPile, 0, len(piles))
	for _, pile := range piles {
		result = append(result, forge.PromptScryPile{
			Destination: pile.Destination, CardIDs: append([]string(nil), pile.CardIDs...),
		})
	}
	return result
}
