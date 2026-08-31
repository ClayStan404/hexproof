// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"errors"
	"strconv"
	"strings"
)

func normalizeDamageOrder(input promptInput) (*PromptDamageSource, []PromptDamageTarget, error) {
	if err := validateDamageCardIDs(input.AttackerID, input.BlockerIDs); err != nil {
		return nil, nil, err
	}
	return &PromptDamageSource{ID: input.AttackerID}, damageTargets(input.BlockerIDs, "card", false), nil
}

func normalizeCombatDamage(input promptInput) (*PromptDamageSource, []PromptDamageTarget, int,
	bool, error) {
	if input.TotalDamage == nil || *input.TotalDamage < 0 || *input.TotalDamage > 100000 {
		return nil, nil, 0, false, errors.New("Forge damage prompt has invalid total damage")
	}
	if err := validateDamageCardIDs(input.AttackerID, input.BlockerIDs); err != nil {
		return nil, nil, 0, false, err
	}
	targets := damageTargets(input.BlockerIDs, "card", false)
	if defenderID := strings.TrimSpace(input.DefenderID); defenderID != "" {
		if len(defenderID) > maxPromptText {
			return nil, nil, 0, false, errors.New("Forge damage prompt has an invalid defender")
		}
		kind := "card"
		if strings.HasPrefix(defenderID, "player-") {
			kind = "player"
		} else if strings.HasPrefix(defenderID, "defender-") {
			kind = "defender"
		}
		targets = append(targets, PromptDamageTarget{
			ResponseID: "damage-target:" + strconv.Itoa(len(targets)),
			Kind:       kind, ID: defenderID, Defender: true,
		})
	}
	if len(targets) == 0 {
		return nil, nil, 0, false, errors.New("Forge damage prompt has no assignees")
	}
	return &PromptDamageSource{ID: input.AttackerID}, targets, *input.TotalDamage,
		input.AttackerHasDeathtouch, nil
}

func validateDamageCardIDs(sourceID string, targetIDs []string) error {
	if strings.TrimSpace(sourceID) == "" || len(sourceID) > maxPromptText ||
		len(targetIDs) == 0 || len(targetIDs) > maxPromptCards {
		return errors.New("Forge damage prompt has invalid combatants")
	}
	seen := make(map[string]struct{}, len(targetIDs))
	for _, targetID := range targetIDs {
		if strings.TrimSpace(targetID) == "" || len(targetID) > maxPromptText {
			return errors.New("Forge damage prompt has an invalid target")
		}
		if _, duplicate := seen[targetID]; duplicate {
			return errors.New("Forge damage prompt contains duplicate targets")
		}
		seen[targetID] = struct{}{}
	}
	return nil
}

func damageTargets(ids []string, kind string, defender bool) []PromptDamageTarget {
	targets := make([]PromptDamageTarget, 0, len(ids))
	for index, id := range ids {
		targets = append(targets, PromptDamageTarget{
			ResponseID: "damage-target:" + strconv.Itoa(index), Kind: kind,
			ID: id, Defender: defender,
		})
	}
	return targets
}

func damageOrderOutput(raw []byte, responseID string, orderedIDs []string) (any, error) {
	if responseID != "$submit" {
		return nil, errors.New("unknown damage-order response")
	}
	_, input, _, err := decodePrompt(raw)
	if err != nil || input.Type != "chooseDamageAssignmentOrder" {
		return nil, errors.New("invalid damage-order prompt")
	}
	_, targets, err := normalizeDamageOrder(input)
	if err != nil || len(orderedIDs) != len(targets) {
		return nil, errors.New("invalid damage-order item count")
	}
	ordered := make([]string, 0, len(orderedIDs))
	seen := make(map[int]struct{}, len(orderedIDs))
	for _, responseTargetID := range orderedIDs {
		index, err := damageTargetIndex(responseTargetID, len(targets))
		if err != nil {
			return nil, err
		}
		if _, duplicate := seen[index]; duplicate {
			return nil, errors.New("damage order contains a duplicate target")
		}
		seen[index] = struct{}{}
		ordered = append(ordered, input.BlockerIDs[index])
	}
	return map[string]any{
		"type": "damageAssignmentOrderDecision", "orderedBlockerIds": ordered,
	}, nil
}

func combatDamageOutput(raw []byte, responseID string,
	assignments []PromptDamageAssignment) (any, error) {
	if responseID != "$submit" {
		return nil, errors.New("unknown combat-damage response")
	}
	_, input, _, err := decodePrompt(raw)
	if err != nil || input.Type != "chooseCombatDamageAssignment" {
		return nil, errors.New("invalid combat-damage prompt")
	}
	_, targets, totalDamage, _, err := normalizeCombatDamage(input)
	if err != nil || len(assignments) != len(targets) {
		return nil, errors.New("invalid combat-damage assignment count")
	}
	output := make([]map[string]any, 0, len(assignments))
	seen := make(map[int]struct{}, len(assignments))
	assignedDamage := 0
	for _, assignment := range assignments {
		index, indexErr := damageTargetIndex(assignment.TargetID, len(targets))
		if indexErr != nil || assignment.Damage < 0 {
			return nil, errors.New("invalid combat-damage assignment")
		}
		if _, duplicate := seen[index]; duplicate {
			return nil, errors.New("combat damage contains a duplicate target")
		}
		seen[index] = struct{}{}
		if assignment.Damage > totalDamage-assignedDamage {
			return nil, errors.New("combat damage exceeds the available total")
		}
		assignedDamage += assignment.Damage
		output = append(output, map[string]any{
			"assigneeId": targets[index].ID, "damage": assignment.Damage,
		})
	}
	if assignedDamage != totalDamage {
		return nil, errors.New("combat damage does not use the available total")
	}
	return map[string]any{
		"type": "combatDamageAssignmentDecision", "assignments": output,
	}, nil
}

func damageTargetIndex(responseID string, count int) (int, error) {
	if !strings.HasPrefix(responseID, "damage-target:") {
		return 0, errors.New("invalid damage target response id")
	}
	index, err := strconv.Atoi(strings.TrimPrefix(responseID, "damage-target:"))
	if err != nil || index < 0 || index >= count {
		return 0, errors.New("damage target is no longer available")
	}
	return index, nil
}
