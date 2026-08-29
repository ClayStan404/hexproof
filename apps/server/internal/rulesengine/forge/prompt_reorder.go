// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"encoding/json"
	"errors"
	"strconv"
	"strings"
)

func normalizeReorderItems(items []promptOrderItem) ([]PromptOrderItem, error) {
	if len(items) > maxPromptCards {
		return nil, errors.New("Forge reorder prompt has too many items")
	}
	result := make([]PromptOrderItem, 0, len(items))
	seen := make(map[string]struct{}, len(items))
	for index, item := range items {
		if strings.TrimSpace(item.ID) == "" || len(item.ID) > maxPromptText {
			return nil, errors.New("Forge reorder prompt has an invalid item id")
		}
		if _, duplicate := seen[item.ID]; duplicate {
			return nil, errors.New("Forge reorder prompt contains duplicate items")
		}
		seen[item.ID] = struct{}{}
		result = append(result, PromptOrderItem{
			ResponseID: "order:" + strconv.Itoa(index), ID: item.ID,
			Name:            boundedPromptText(item.Card.Identity.Name),
			SetCode:         boundedPromptText(item.Card.Identity.SetCode),
			CollectorNumber: boundedPromptText(item.Card.Identity.CardNumber),
			Token:           item.Card.Identity.IsToken, Oracle: boundedPromptText(item.Oracle),
		})
	}
	return result, nil
}

func reorderOutput(raw json.RawMessage, responseID string, orderedIDs []string) (any, error) {
	if responseID != "$submit" {
		return nil, errors.New("unknown reorder response")
	}
	_, input, _, err := decodePrompt(raw)
	if err != nil || input.Type != "reorder" {
		return nil, errors.New("invalid reorder prompt")
	}
	items, err := normalizeReorderItems(input.Items)
	if err != nil || len(orderedIDs) != len(items) {
		return nil, errors.New("invalid reorder item count")
	}
	ordered := make([]string, 0, len(orderedIDs))
	seen := make(map[int]struct{}, len(orderedIDs))
	for _, responseItemID := range orderedIDs {
		if !strings.HasPrefix(responseItemID, "order:") {
			return nil, errors.New("invalid reorder response id")
		}
		index, err := strconv.Atoi(strings.TrimPrefix(responseItemID, "order:"))
		if err != nil || index < 0 || index >= len(input.Items) {
			return nil, errors.New("reorder response is no longer available")
		}
		if _, duplicate := seen[index]; duplicate {
			return nil, errors.New("reorder response contains a duplicate item")
		}
		seen[index] = struct{}{}
		ordered = append(ordered, input.Items[index].ID)
	}
	return map[string]any{
		"type": "reorderDecision", "orderedIds": ordered,
	}, nil
}
