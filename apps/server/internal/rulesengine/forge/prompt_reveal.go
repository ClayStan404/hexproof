// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"errors"
	"strconv"
	"strings"
)

// normalizeRevealedCards accepts both an actual disclosure and Forge's
// notification-only reveal prompt, which legitimately contains no cards.
func normalizeRevealedCards(cards []promptCard) ([]PromptCard, error) {
	if len(cards) > maxPromptCards {
		return nil, errors.New("Forge reveal prompt has too many cards")
	}
	result := make([]PromptCard, 0, len(cards))
	seen := make(map[string]struct{}, len(cards))
	for index, card := range cards {
		if strings.TrimSpace(card.ID) == "" || len(card.ID) > maxPromptText {
			return nil, errors.New("Forge reveal prompt has an invalid card id")
		}
		if _, duplicate := seen[card.ID]; duplicate {
			return nil, errors.New("Forge reveal prompt contains duplicate cards")
		}
		seen[card.ID] = struct{}{}
		view := promptCardView(card)
		// Reveals are acknowledgement-only, so the client does not need the
		// canonical Forge object id even as a selection token.
		view.ID = "reveal:" + strconv.Itoa(index)
		result = append(result, view)
	}
	return result, nil
}
