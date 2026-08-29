// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
)

func normalizePromptCards(handCardIDs []string, cards []promptCard,
	required int) ([]PromptCard, error) {
	if len(handCardIDs) > maxPromptCards || len(cards) > maxPromptCards ||
		required < 0 || required > len(handCardIDs) {
		return nil, errors.New("Forge card-selection prompt has invalid bounds")
	}
	identities := make(map[string]promptCardIdentity, len(cards))
	for _, card := range cards {
		if strings.TrimSpace(card.ID) == "" || len(card.ID) > maxPromptText {
			return nil, errors.New("Forge card-selection prompt has an invalid card id")
		}
		if _, exists := identities[card.ID]; exists {
			return nil, errors.New("Forge card-selection prompt contains duplicate cards")
		}
		identities[card.ID] = card.Identity
	}
	result := make([]PromptCard, 0, len(handCardIDs))
	seen := make(map[string]struct{}, len(handCardIDs))
	for _, cardID := range handCardIDs {
		identity, exists := identities[cardID]
		if !exists || strings.TrimSpace(cardID) == "" {
			return nil, errors.New("Forge card-selection prompt is missing a hand identity")
		}
		if _, duplicate := seen[cardID]; duplicate {
			return nil, errors.New("Forge card-selection prompt repeats a hand card")
		}
		seen[cardID] = struct{}{}
		result = append(result, PromptCard{
			ID: cardID, Name: boundedPromptText(identity.Name),
			SetCode:         boundedPromptText(identity.SetCode),
			CollectorNumber: boundedPromptText(identity.CardNumber), Token: identity.IsToken,
		})
	}
	return result, nil
}

func normalizeChooseCards(input promptInput) ([]PromptCard, int, int, error) {
	if input.Min == nil || input.Max == nil {
		return nil, 0, 0, errors.New("Forge card-selection prompt is missing bounds")
	}
	minimum, maximum := *input.Min, *input.Max
	if minimum < 0 || maximum < minimum || minimum > len(input.Cards) ||
		len(input.Cards) > maxPromptCards {
		return nil, 0, 0, errors.New("Forge card-selection prompt has invalid bounds")
	}
	if maximum > len(input.Cards) {
		maximum = len(input.Cards)
	}
	result := make([]PromptCard, 0, len(input.Cards))
	seen := make(map[string]struct{}, len(input.Cards))
	for _, card := range input.Cards {
		if strings.TrimSpace(card.ID) == "" || len(card.ID) > maxPromptText {
			return nil, 0, 0, errors.New("Forge card-selection prompt has an invalid card id")
		}
		if _, duplicate := seen[card.ID]; duplicate {
			return nil, 0, 0, errors.New("Forge card-selection prompt contains duplicate cards")
		}
		seen[card.ID] = struct{}{}
		result = append(result, promptCardView(card))
	}
	return result, minimum, maximum, nil
}

func promptCardView(card promptCard) PromptCard {
	return PromptCard{
		ID: card.ID, Name: boundedPromptText(card.Identity.Name),
		SetCode:         boundedPromptText(card.Identity.SetCode),
		CollectorNumber: boundedPromptText(card.Identity.CardNumber),
		Token:           card.Identity.IsToken,
	}
}

func cardSelectionRangeDetail(minimum, maximum int) string {
	if minimum == maximum {
		return fmt.Sprintf("Choose exactly %d card(s).", minimum)
	}
	return fmt.Sprintf("Choose between %d and %d card(s).", minimum, maximum)
}

func mulliganPutBackOutput(raw json.RawMessage, responseID string,
	cardIDs []string) (any, error) {
	if responseID != "$submit" {
		return nil, errors.New("unknown mulligan put-back response")
	}
	_, input, _, err := decodePrompt(raw)
	if err != nil || input.Type != "mulliganPutBack" || len(cardIDs) != input.Count {
		return nil, errors.New("invalid mulligan put-back selection")
	}
	allowed := make(map[string]struct{}, len(input.HandCardIDs))
	for _, cardID := range input.HandCardIDs {
		allowed[cardID] = struct{}{}
	}
	selected := make([]string, 0, len(cardIDs))
	seen := make(map[string]struct{}, len(cardIDs))
	for _, cardID := range cardIDs {
		if strings.TrimSpace(cardID) == "" || len(cardID) > maxPromptText {
			return nil, errors.New("mulligan put-back selection has an invalid card id")
		}
		if _, exists := allowed[cardID]; !exists {
			return nil, errors.New("mulligan put-back selection contains a foreign card")
		}
		if _, duplicate := seen[cardID]; duplicate {
			return nil, errors.New("mulligan put-back selection contains a duplicate card")
		}
		seen[cardID] = struct{}{}
		selected = append(selected, cardID)
	}
	return map[string]any{"type": "mulliganPutBackDecision", "cardIds": selected}, nil
}

func chooseCardsOutput(raw json.RawMessage, responseID string,
	cardIDs []string) (any, error) {
	if responseID != "$submit" {
		return nil, errors.New("unknown card-selection response")
	}
	_, input, _, err := decodePrompt(raw)
	if err != nil || input.Type != "chooseCards" {
		return nil, errors.New("invalid card-selection prompt")
	}
	cards, minimum, maximum, err := normalizeChooseCards(input)
	if err != nil || len(cardIDs) < minimum || len(cardIDs) > maximum {
		return nil, errors.New("invalid card-selection cardinality")
	}
	allowed := make(map[string]struct{}, len(cards))
	for _, card := range cards {
		allowed[card.ID] = struct{}{}
	}
	selected := make([]string, 0, len(cardIDs))
	seen := make(map[string]struct{}, len(cardIDs))
	for _, cardID := range cardIDs {
		if strings.TrimSpace(cardID) == "" || len(cardID) > maxPromptText {
			return nil, errors.New("card selection has an invalid card id")
		}
		if _, exists := allowed[cardID]; !exists {
			return nil, errors.New("card selection contains a foreign card")
		}
		if _, duplicate := seen[cardID]; duplicate {
			return nil, errors.New("card selection contains a duplicate card")
		}
		seen[cardID] = struct{}{}
		selected = append(selected, cardID)
	}
	return map[string]any{
		"type": "chooseCardsDecision", "chosenCardIds": selected,
	}, nil
}

func normalizePromptTargets(input promptInput) ([]PromptTarget, int, int, error) {
	if len(input.Candidates) > maxPromptOptions || input.MinTargets < 0 ||
		input.MaxTargets < input.MinTargets || input.ChosenTargets < 0 ||
		input.ChosenTargets > input.MaxTargets {
		return nil, 0, 0, errors.New("Forge target prompt has invalid bounds")
	}
	minimum := input.MinTargets - input.ChosenTargets
	if minimum < 0 {
		minimum = 0
	}
	maximum := input.MaxTargets - input.ChosenTargets
	if maximum > len(input.Candidates) {
		maximum = len(input.Candidates)
	}
	if minimum > maximum {
		return nil, 0, 0, errors.New("Forge target prompt cannot satisfy its bounds")
	}
	targets := make([]PromptTarget, 0, len(input.Candidates))
	seen := make(map[string]struct{}, len(input.Candidates))
	for index, candidate := range input.Candidates {
		if candidate.Kind != "player" && candidate.Kind != "card" && candidate.Kind != "spell" {
			return nil, 0, 0, errors.New("Forge target prompt has an unknown target kind")
		}
		if strings.TrimSpace(candidate.ID) == "" || len(candidate.ID) > maxPromptText {
			return nil, 0, 0, errors.New("Forge target prompt has an invalid target id")
		}
		key := candidate.Kind + "\x00" + candidate.ID
		if _, duplicate := seen[key]; duplicate {
			return nil, 0, 0, errors.New("Forge target prompt contains a duplicate target")
		}
		seen[key] = struct{}{}
		targets = append(targets, PromptTarget{
			ResponseID: "target:" + strconv.Itoa(index), Kind: candidate.Kind,
			ID: candidate.ID, Oracle: boundedPromptText(candidate.Oracle),
		})
	}
	return targets, minimum, maximum, nil
}

func selectionRangeDetail(minimum, maximum int) string {
	if minimum == maximum {
		return fmt.Sprintf("Choose exactly %d target(s).", minimum)
	}
	return fmt.Sprintf("Choose between %d and %d target(s).", minimum, maximum)
}

func boardTargetsOutput(raw json.RawMessage, responseID string,
	targetIDs []string) (any, error) {
	_, input, _, err := decodePrompt(raw)
	if err != nil || input.Type != "chooseBoardTargets" {
		return nil, errors.New("invalid target-selection prompt")
	}
	if responseID == "$cancel" {
		if !input.Cancellable || len(targetIDs) != 0 {
			return nil, errors.New("target selection cannot be cancelled")
		}
		return map[string]any{"type": "cancel"}, nil
	}
	if responseID != "$submit" {
		return nil, errors.New("unknown target-selection response")
	}
	_, minimum, maximum, err := normalizePromptTargets(input)
	if err != nil || len(targetIDs) < minimum || len(targetIDs) > maximum {
		return nil, errors.New("invalid target-selection cardinality")
	}
	chosen := make([]promptTargetRef, 0, len(targetIDs))
	seen := make(map[int]struct{}, len(targetIDs))
	for _, targetID := range targetIDs {
		if !strings.HasPrefix(targetID, "target:") {
			return nil, errors.New("invalid target response id")
		}
		index, err := strconv.Atoi(strings.TrimPrefix(targetID, "target:"))
		if err != nil || index < 0 || index >= len(input.Candidates) {
			return nil, errors.New("target response is no longer available")
		}
		if _, duplicate := seen[index]; duplicate {
			return nil, errors.New("target response contains a duplicate")
		}
		seen[index] = struct{}{}
		chosen = append(chosen, input.Candidates[index])
	}
	return map[string]any{"type": "boardTargets", "chosen": chosen}, nil
}
