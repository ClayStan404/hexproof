// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"errors"
	"strconv"
	"strings"
)

func normalizePromptContext(sourceCard *promptCard, presentation promptPresentation) (
	[]PromptCard, []PromptTarget, string, error) {
	cards := []PromptCard{}
	if sourceCard != nil {
		if strings.TrimSpace(sourceCard.ID) == "" || len(sourceCard.ID) > maxPromptText ||
			strings.TrimSpace(sourceCard.Identity.Name) == "" {
			return nil, nil, "", errors.New("Forge prompt has an invalid source card")
		}
		card := promptCardView(*sourceCard)
		card.ID = "context-card:0"
		cards = append(cards, card)
	}
	if len(presentation.Targets) > maxPromptOptions {
		return nil, nil, "", errors.New("Forge prompt has too many context targets")
	}
	targets := make([]PromptTarget, 0, len(presentation.Targets))
	seen := make(map[string]struct{}, len(presentation.Targets))
	for index, target := range presentation.Targets {
		if target.Kind != "player" && target.Kind != "card" && target.Kind != "spell" {
			return nil, nil, "", errors.New("Forge prompt has an unknown context target kind")
		}
		if strings.TrimSpace(target.ID) == "" || len(target.ID) > maxPromptText {
			return nil, nil, "", errors.New("Forge prompt has an invalid context target")
		}
		key := target.Kind + "\x00" + target.ID
		if _, duplicate := seen[key]; duplicate {
			return nil, nil, "", errors.New("Forge prompt contains duplicate context targets")
		}
		seen[key] = struct{}{}
		targets = append(targets, PromptTarget{
			ResponseID: "context-target:" + strconv.Itoa(index), Kind: target.Kind,
			ID: target.ID,
		})
	}
	return cards, targets, boundedPromptText(presentation.Text), nil
}
