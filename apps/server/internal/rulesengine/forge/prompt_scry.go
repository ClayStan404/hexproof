// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"encoding/json"
	"errors"
	"strconv"
	"strings"
)

const maxScryDestinations = 5

var supportedScryDestinations = map[string]struct{}{
	"libraryTop": {}, "libraryBottom": {}, "graveyard": {}, "exile": {}, "hand": {},
}

func normalizeScry(input promptInput) ([]PromptCard, []string, error) {
	if len(input.Cards) > maxPromptCards || len(input.Zones) == 0 ||
		len(input.Zones) > maxScryDestinations {
		return nil, nil, errors.New("Forge scry prompt has invalid bounds")
	}
	destinations := make([]string, 0, len(input.Zones))
	seenDestinations := make(map[string]struct{}, len(input.Zones))
	for _, destination := range input.Zones {
		if _, supported := supportedScryDestinations[destination]; !supported {
			return nil, nil, errors.New("Forge scry prompt has an unsupported destination")
		}
		if _, duplicate := seenDestinations[destination]; duplicate {
			return nil, nil, errors.New("Forge scry prompt contains duplicate destinations")
		}
		seenDestinations[destination] = struct{}{}
		destinations = append(destinations, destination)
	}

	cards := make([]PromptCard, 0, len(input.Cards))
	seenCards := make(map[string]struct{}, len(input.Cards))
	for index, card := range input.Cards {
		if strings.TrimSpace(card.ID) == "" || len(card.ID) > maxPromptText {
			return nil, nil, errors.New("Forge scry prompt has an invalid card id")
		}
		if _, duplicate := seenCards[card.ID]; duplicate {
			return nil, nil, errors.New("Forge scry prompt contains duplicate cards")
		}
		seenCards[card.ID] = struct{}{}
		view := promptCardView(card)
		view.ID = "scry:" + strconv.Itoa(index)
		cards = append(cards, view)
	}
	return cards, destinations, nil
}

func scryOutput(raw json.RawMessage, responseID string, piles []PromptScryPile) (any, error) {
	if responseID != "$submit" {
		return nil, errors.New("unknown scry response")
	}
	_, input, _, err := decodePrompt(raw)
	if err != nil || input.Type != "scry" {
		return nil, errors.New("invalid scry prompt")
	}
	_, destinations, err := normalizeScry(input)
	if err != nil || len(piles) != len(destinations) {
		return nil, errors.New("invalid scry pile count")
	}

	zoneCardIDs := make([][]string, len(piles))
	seen := make(map[int]struct{}, len(input.Cards))
	for pileIndex, pile := range piles {
		if pile.Destination != destinations[pileIndex] {
			return nil, errors.New("scry destination no longer matches the prompt")
		}
		zoneCardIDs[pileIndex] = make([]string, 0, len(pile.CardIDs))
		for _, responseCardID := range pile.CardIDs {
			if !strings.HasPrefix(responseCardID, "scry:") {
				return nil, errors.New("invalid scry response id")
			}
			index, parseErr := strconv.Atoi(strings.TrimPrefix(responseCardID, "scry:"))
			if parseErr != nil || index < 0 || index >= len(input.Cards) {
				return nil, errors.New("scry response is no longer available")
			}
			if _, duplicate := seen[index]; duplicate {
				return nil, errors.New("scry response contains a duplicate card")
			}
			seen[index] = struct{}{}
			zoneCardIDs[pileIndex] = append(zoneCardIDs[pileIndex], input.Cards[index].ID)
		}
	}
	if len(seen) != len(input.Cards) {
		return nil, errors.New("scry response does not place every card")
	}
	return map[string]any{"type": "scryDecision", "zoneCardIds": zoneCardIDs}, nil
}
