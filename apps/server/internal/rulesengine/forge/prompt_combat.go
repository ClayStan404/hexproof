// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"encoding/json"
	"errors"
	"strconv"
	"strings"
)

func normalizeAttackers(input promptInput) ([]PromptCombatSource, []PromptCombatTarget, error) {
	if len(input.Attackers) > maxPromptCards || len(input.AttackTargets) > maxPromptOptions {
		return nil, nil, errors.New("Forge attacker prompt has too many choices")
	}
	targets := make([]PromptCombatTarget, 0, len(input.AttackTargets))
	targetIDs := make(map[string]string, len(input.AttackTargets))
	for index, target := range input.AttackTargets {
		if !validAttackTargetKind(target.Kind) || !validPromptObjectID(target.ID) {
			return nil, nil, errors.New("Forge attacker prompt has an invalid defender")
		}
		if _, duplicate := targetIDs[target.ID]; duplicate {
			return nil, nil, errors.New("Forge attacker prompt repeats a defender")
		}
		responseID := "combat-target:" + strconv.Itoa(index)
		targetIDs[target.ID] = responseID
		targets = append(targets, PromptCombatTarget{
			ResponseID: responseID, Kind: target.Kind, ID: target.ID,
			Label: firstPromptText(target.Label, "Defender"), Maximum: len(input.Attackers),
		})
	}
	sources := make([]PromptCombatSource, 0, len(input.Attackers))
	seenAttackers := make(map[string]struct{}, len(input.Attackers))
	for index, attacker := range input.Attackers {
		if !validPromptObjectID(attacker.AttackerID) {
			return nil, nil, errors.New("Forge attacker prompt has an invalid attacker")
		}
		if _, duplicate := seenAttackers[attacker.AttackerID]; duplicate {
			return nil, nil, errors.New("Forge attacker prompt repeats an attacker")
		}
		seenAttackers[attacker.AttackerID] = struct{}{}
		validTargets, err := opaqueCombatIDs(attacker.ValidTargetIDs, targetIDs)
		if err != nil {
			return nil, nil, errors.New("Forge attacker prompt has invalid legal defenders")
		}
		sources = append(sources, PromptCombatSource{
			ResponseID: "combat-source:" + strconv.Itoa(index), ID: attacker.AttackerID,
			ValidTargetIDs: validTargets, MustAssignIfAble: attacker.MustAttack,
		})
	}
	return sources, targets, nil
}

func normalizeBlockers(input promptInput) ([]PromptCombatSource, []PromptCombatTarget, error) {
	if len(input.Attackers) > maxPromptCards || len(input.AvailableBlockerIDs) > maxPromptCards {
		return nil, nil, errors.New("Forge blocker prompt has too many choices")
	}
	blockerIndexes := make(map[string]int, len(input.AvailableBlockerIDs))
	for index, blockerID := range input.AvailableBlockerIDs {
		if !validPromptObjectID(blockerID) {
			return nil, nil, errors.New("Forge blocker prompt has an invalid blocker")
		}
		if _, duplicate := blockerIndexes[blockerID]; duplicate {
			return nil, nil, errors.New("Forge blocker prompt repeats a blocker")
		}
		blockerIndexes[blockerID] = index
	}
	sources := make([]PromptCombatSource, len(input.AvailableBlockerIDs))
	for index, blockerID := range input.AvailableBlockerIDs {
		sources[index] = PromptCombatSource{
			ResponseID: "combat-source:" + strconv.Itoa(index), ID: blockerID,
			ValidTargetIDs: []string{},
		}
	}
	targets := make([]PromptCombatTarget, 0, len(input.Attackers))
	seenAttackers := make(map[string]struct{}, len(input.Attackers))
	for index, attacker := range input.Attackers {
		if !validPromptObjectID(attacker.AttackerID) || attacker.MinBlockers < 0 {
			return nil, nil, errors.New("Forge blocker prompt has an invalid attacker")
		}
		if _, duplicate := seenAttackers[attacker.AttackerID]; duplicate {
			return nil, nil, errors.New("Forge blocker prompt repeats an attacker")
		}
		seenAttackers[attacker.AttackerID] = struct{}{}
		targetResponseID := "combat-target:" + strconv.Itoa(index)
		validBlockers := make(map[string]int, len(attacker.ValidBlockerIDs))
		for _, blockerID := range attacker.ValidBlockerIDs {
			blockerIndex, exists := blockerIndexes[blockerID]
			if !exists {
				return nil, nil, errors.New("Forge blocker prompt references an unavailable blocker")
			}
			if _, duplicate := validBlockers[blockerID]; duplicate {
				return nil, nil, errors.New("Forge blocker prompt repeats a legal blocker")
			}
			validBlockers[blockerID] = blockerIndex
		}
		maximum := len(validBlockers)
		if attacker.MaxBlockers != nil {
			if *attacker.MaxBlockers < 0 {
				return nil, nil, errors.New("Forge blocker prompt has an invalid maximum")
			}
			if *attacker.MaxBlockers < maximum {
				maximum = *attacker.MaxBlockers
			}
		}
		minimum := attacker.MinBlockers
		if attacker.MustBeBlocked && minimum < 1 {
			minimum = 1
		}
		// A minimum that cannot be reached makes this attacker unblockable. Keep
		// it visible as a combat target, but do not advertise pairings that can
		// only produce an invalid partial block.
		if maximum >= minimum {
			for _, blockerIndex := range validBlockers {
				sources[blockerIndex].ValidTargetIDs = append(
					sources[blockerIndex].ValidTargetIDs, targetResponseID)
			}
		}
		targets = append(targets, PromptCombatTarget{
			ResponseID: targetResponseID, Kind: "attacker", ID: attacker.AttackerID,
			Label: "Attacker", Minimum: minimum, Maximum: maximum,
			MustReceiveIfAble: attacker.MustBeBlocked,
		})
	}
	return sources, targets, nil
}

func combatAssignmentsOutput(raw json.RawMessage, responseID string,
	assignments []PromptAssignment) (any, error) {
	if responseID != "$submit" || len(assignments) > maxPromptCards {
		return nil, errors.New("invalid combat assignment response")
	}
	_, input, _, err := decodePrompt(raw)
	if err != nil || input.Type != "chooseAttackers" && input.Type != "chooseBlockers" {
		return nil, errors.New("invalid combat assignment prompt")
	}
	var sources []PromptCombatSource
	var targets []PromptCombatTarget
	if input.Type == "chooseAttackers" {
		sources, targets, err = normalizeAttackers(input)
	} else {
		sources, targets, err = normalizeBlockers(input)
	}
	if err != nil {
		return nil, err
	}
	sourceByResponse := make(map[string]PromptCombatSource, len(sources))
	for _, source := range sources {
		sourceByResponse[source.ResponseID] = source
	}
	targetByResponse := make(map[string]PromptCombatTarget, len(targets))
	for _, target := range targets {
		targetByResponse[target.ResponseID] = target
	}
	seenSources := make(map[string]struct{}, len(assignments))
	targetCounts := make(map[string]int, len(targets))
	upstream := make([]map[string]string, 0, len(assignments))
	for _, assignment := range assignments {
		source, sourceExists := sourceByResponse[assignment.SourceID]
		target, targetExists := targetByResponse[assignment.TargetID]
		if !sourceExists || !targetExists ||
			!containsPromptID(source.ValidTargetIDs, assignment.TargetID) {
			return nil, errors.New("combat assignment is no longer legal")
		}
		if _, duplicate := seenSources[assignment.SourceID]; duplicate {
			return nil, errors.New("combat source was assigned more than once")
		}
		seenSources[assignment.SourceID] = struct{}{}
		targetCounts[assignment.TargetID]++
		if input.Type == "chooseAttackers" {
			upstream = append(upstream, map[string]string{
				"attackerId": source.ID, "targetId": target.ID,
			})
		} else {
			upstream = append(upstream, map[string]string{
				"blockerId": source.ID, "attackerId": target.ID,
			})
		}
	}
	for _, target := range targets {
		count := targetCounts[target.ResponseID]
		if count > target.Maximum || count > 0 && count < target.Minimum {
			return nil, errors.New("combat target has an invalid assignment count")
		}
	}
	outputType := "declareAttackers"
	if input.Type == "chooseBlockers" {
		outputType = "declareBlockers"
	}
	return map[string]any{"type": outputType, "assignments": upstream}, nil
}

func opaqueCombatIDs(ids []string, available map[string]string) ([]string, error) {
	result := make([]string, 0, len(ids))
	seen := make(map[string]struct{}, len(ids))
	for _, id := range ids {
		responseID, exists := available[id]
		if !exists {
			return nil, errors.New("combat prompt references an unavailable object")
		}
		if _, duplicate := seen[id]; duplicate {
			return nil, errors.New("combat prompt repeats a legal object")
		}
		seen[id] = struct{}{}
		result = append(result, responseID)
	}
	return result, nil
}

func validPromptObjectID(id string) bool {
	return strings.TrimSpace(id) != "" && len(id) <= maxPromptText
}

func validAttackTargetKind(kind string) bool {
	return kind == "player" || kind == "planeswalker" || kind == "battle"
}

func containsPromptID(ids []string, candidate string) bool {
	for _, id := range ids {
		if id == candidate {
			return true
		}
	}
	return false
}
