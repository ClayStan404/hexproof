// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"encoding/json"
	"errors"
	"strconv"
	"strings"
)

const (
	minimumPromptNumber = -1 << 31
	maximumPromptNumber = 1<<31 - 1
)

func normalizeBoolean(input promptInput) ([]PromptChoice, int, int, error) {
	return []PromptChoice{
		{ResponseID: "choice:0", Label: firstPromptText(input.DenyLabel, "No"),
			Weight: 1, Value: "false"},
		{ResponseID: "choice:1", Label: firstPromptText(input.ConfirmLabel, "Yes"),
			Weight: 1, Value: "true"},
	}, 1, 1, nil
}

func normalizeNumber(input promptInput) (int, int, error) {
	if input.Min == nil || input.Max == nil || *input.Min < minimumPromptNumber ||
		*input.Max > maximumPromptNumber || *input.Min > *input.Max {
		return 0, 0, errors.New("Forge number prompt has invalid bounds")
	}
	return *input.Min, *input.Max, nil
}

func normalizeColors(input promptInput) ([]PromptChoice, int, int, error) {
	if input.Amount == nil || input.ValidColors == nil || *input.Amount < 0 ||
		*input.Amount > maxPromptCards ||
		len(input.ValidColors) > maxPromptOptions {
		return nil, 0, 0, errors.New("Forge color prompt has invalid bounds")
	}
	if *input.Amount > 0 && len(input.ValidColors) == 0 {
		return nil, 0, 0, errors.New("Forge color prompt has no legal colors")
	}
	if !input.RepeatAllowed && *input.Amount > len(input.ValidColors) {
		return nil, 0, 0, errors.New("Forge color prompt cannot satisfy its amount")
	}
	choices := make([]PromptChoice, 0, len(input.ValidColors))
	seen := make(map[string]struct{}, len(input.ValidColors))
	for index, color := range input.ValidColors {
		color = strings.TrimSpace(color)
		if color == "" || len([]rune(color)) > maxPromptText {
			return nil, 0, 0, errors.New("Forge color prompt has an invalid color")
		}
		if _, duplicate := seen[color]; duplicate {
			return nil, 0, 0, errors.New("Forge color prompt repeats a color")
		}
		seen[color] = struct{}{}
		choices = append(choices, PromptChoice{
			ResponseID: "choice:" + strconv.Itoa(index), Label: color, Weight: 1,
			CanRepeat: input.RepeatAllowed, Value: color,
		})
	}
	return choices, *input.Amount, *input.Amount, nil
}

func normalizeSelection(input promptInput) ([]PromptChoice, int, int, error) {
	if input.SelectionOptions == nil || input.MinTotal == nil || input.MaxTotal == nil ||
		len(input.SelectionOptions) > maxPromptOptions || *input.MinTotal < 0 ||
		*input.MaxTotal < *input.MinTotal || *input.MaxTotal > maxPromptCards {
		return nil, 0, 0, errors.New("Forge selection prompt has invalid bounds")
	}
	choices := make([]PromptChoice, 0, len(input.SelectionOptions))
	for index, option := range input.SelectionOptions {
		if option.Weight <= 0 || option.Weight > maxPromptCards {
			return nil, 0, 0, errors.New("Forge selection prompt has an invalid weight")
		}
		label := boundedPromptText(option.Label)
		if label == "" {
			return nil, 0, 0, errors.New("Forge selection prompt has an empty label")
		}
		choices = append(choices, PromptChoice{
			ResponseID: "choice:" + strconv.Itoa(index), Label: label,
			Weight: option.Weight, CanRepeat: option.CanRepeat, Value: strconv.Itoa(index),
		})
	}
	if !choiceRangeReachable(choices, *input.MinTotal, *input.MaxTotal) {
		return nil, 0, 0, errors.New("Forge selection prompt has no valid choice total")
	}
	return choices, *input.MinTotal, *input.MaxTotal, nil
}

func choiceRangeReachable(choices []PromptChoice, minimum, maximum int) bool {
	reachable := make([]bool, maximum+1)
	reachable[0] = true
	for _, choice := range choices {
		if choice.CanRepeat {
			for total := choice.Weight; total <= maximum; total++ {
				reachable[total] = reachable[total] || reachable[total-choice.Weight]
			}
			continue
		}
		for total := maximum; total >= choice.Weight; total-- {
			reachable[total] = reachable[total] || reachable[total-choice.Weight]
		}
	}
	for total := minimum; total <= maximum; total++ {
		if reachable[total] {
			return true
		}
	}
	return false
}

func scalarChoiceOutput(raw json.RawMessage, responseID string, choiceIDs []string) (any, error) {
	if responseID != "$submit" || len(choiceIDs) > maxPromptCards {
		return nil, errors.New("invalid scalar choice response")
	}
	_, input, _, err := decodePrompt(raw)
	if err != nil {
		return nil, err
	}
	var choices []PromptChoice
	var minimum, maximum int
	switch input.Type {
	case "chooseBoolean":
		choices, minimum, maximum, err = normalizeBoolean(input)
	case "chooseColor":
		choices, minimum, maximum, err = normalizeColors(input)
	case "chooseFromSelection":
		choices, minimum, maximum, err = normalizeSelection(input)
	default:
		return nil, errors.New("invalid scalar choice prompt")
	}
	if err != nil {
		return nil, err
	}
	chosen, err := validateScalarChoices(choices, minimum, maximum, choiceIDs)
	if err != nil {
		return nil, err
	}
	switch input.Type {
	case "chooseBoolean":
		return map[string]any{"type": "decision", "value": chosen[0].Value == "true"}, nil
	case "chooseColor":
		colors := make(map[string]int, len(chosen))
		for _, choice := range chosen {
			colors[choice.Value]++
		}
		return map[string]any{"type": "colorDecision", "chosenColors": colors}, nil
	case "chooseFromSelection":
		indices := make([]int, 0, len(chosen))
		for _, choice := range chosen {
			index, conversionErr := strconv.Atoi(choice.Value)
			if conversionErr != nil {
				return nil, errors.New("selection choice is no longer valid")
			}
			indices = append(indices, index)
		}
		return map[string]any{"type": "selectionDecision", "chosenIndices": indices}, nil
	}
	return nil, errors.New("unsupported scalar choice prompt")
}

func validateScalarChoices(choices []PromptChoice, minimum, maximum int,
	choiceIDs []string) ([]PromptChoice, error) {
	byID := make(map[string]PromptChoice, len(choices))
	for _, choice := range choices {
		byID[choice.ResponseID] = choice
	}
	chosen := make([]PromptChoice, 0, len(choiceIDs))
	counts := make(map[string]int, len(choiceIDs))
	total := 0
	for _, choiceID := range choiceIDs {
		choice, exists := byID[choiceID]
		if !exists {
			return nil, errors.New("scalar choice is no longer available")
		}
		counts[choiceID]++
		if counts[choiceID] > 1 && !choice.CanRepeat {
			return nil, errors.New("scalar choice cannot be repeated")
		}
		total += choice.Weight
		if total > maximum {
			return nil, errors.New("scalar choice total exceeds the maximum")
		}
		chosen = append(chosen, choice)
	}
	if total < minimum || total > maximum {
		return nil, errors.New("scalar choice total is outside the required range")
	}
	return chosen, nil
}

func numberOutput(raw json.RawMessage, responseID string, chosenNumber *int) (any, error) {
	if responseID != "$submit" || chosenNumber == nil {
		return nil, errors.New("invalid number response")
	}
	_, input, _, err := decodePrompt(raw)
	if err != nil || input.Type != "chooseNumber" {
		return nil, errors.New("invalid number prompt")
	}
	minimum, maximum, err := normalizeNumber(input)
	if err != nil || *chosenNumber < minimum || *chosenNumber > maximum {
		return nil, errors.New("chosen number is outside the required range")
	}
	return map[string]any{"type": "numberDecision", "chosenNumber": *chosenNumber}, nil
}
