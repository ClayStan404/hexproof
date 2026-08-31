// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import (
	"sort"
	"strings"
	"unicode/utf8"

	"hexproof/server/internal/protocol"
)

var basicLandNames = map[string]string{
	"plains": "Plains", "island": "Island", "swamp": "Swamp",
	"mountain": "Mountain", "forest": "Forest",
}

type cardKey struct {
	name      string
	set       string
	collector string
	typeLine  string
}

func appendDeckCard(cards map[cardKey]int, card *CardInstance) {
	key := cardKey{card.Name, card.SetCode, card.CollectorNumber, card.TypeLine}
	cards[key]++
}

func deckCards(cards map[cardKey]int) []protocol.DeckCard {
	keys := make([]cardKey, 0, len(cards))
	for key := range cards {
		keys = append(keys, key)
	}
	sort.Slice(keys, func(left, right int) bool {
		if keys[left].name != keys[right].name {
			return keys[left].name < keys[right].name
		}
		if keys[left].set != keys[right].set {
			return keys[left].set < keys[right].set
		}
		return keys[left].collector < keys[right].collector
	})
	result := make([]protocol.DeckCard, 0, len(keys))
	for _, key := range keys {
		result = append(result, protocol.DeckCard{
			Name: key.name, Count: cards[key], SetCode: key.set,
			CollectorNumber: key.collector, TypeLine: key.typeLine,
		})
	}
	return result
}

func (e *Event) SubmitDeck(participantID string, request protocol.LimitedSubmitDeck) (*protocol.DeckSelect, error) {
	if e.Stage != protocol.LimitedStageDeckBuilding {
		return nil, fail(ErrDeckInvalid, "limited deck building is not active")
	}
	player := e.Player(participantID)
	if player == nil {
		return nil, fail(ErrForbidden, "participant does not own a limited pool")
	}
	request.Name = strings.TrimSpace(request.Name)
	if request.Name == "" || utf8.RuneCountInString(request.Name) > protocol.MaxDeckNameRunes {
		return nil, fail(ErrDeckInvalid, "invalid limited deck name")
	}
	pool := make(map[string]*CardInstance, len(player.Pool))
	for _, card := range player.Pool {
		pool[card.ID] = card
	}
	selected := make(map[string]bool, len(request.MainboardInstanceIDs))
	mainboard := make(map[cardKey]int)
	for _, instanceID := range request.MainboardInstanceIDs {
		card := pool[instanceID]
		if card == nil || selected[instanceID] {
			return nil, fail(ErrDeckInvalid, "main deck contains an unavailable pool card")
		}
		selected[instanceID] = true
		appendDeckCard(mainboard, card)
	}
	mainboardCount := len(request.MainboardInstanceIDs)
	for _, basic := range request.BasicLands {
		name := basicLandNames[strings.ToLower(strings.TrimSpace(basic.Name))]
		if name == "" || basic.Count < 1 || basic.Count > protocol.MaxDeckCards ||
			mainboardCount > protocol.MaxDeckCards-basic.Count {
			return nil, fail(ErrDeckInvalid, "invalid basic land addition")
		}
		mainboardCount += basic.Count
		key := cardKey{
			name: name, set: strings.ToUpper(strings.TrimSpace(basic.SetCode)),
			collector: strings.TrimSpace(basic.CollectorNumber), typeLine: "Basic Land",
		}
		mainboard[key] += basic.Count
	}
	if mainboardCount < protocol.MinLimitedMainboardCards ||
		mainboardCount > protocol.MaxDeckCards {
		return nil, fail(ErrDeckInvalid, "limited main deck must contain at least 40 cards")
	}
	sideboard := make(map[cardKey]int)
	for _, card := range player.Pool {
		if !selected[card.ID] {
			appendDeckCard(sideboard, card)
		}
	}
	deck := protocol.DeckSelect{
		Name: request.Name, Format: protocol.FormatModern,
		DeckFormat: protocol.DeckFormatLimited,
		Mainboard:  deckCards(mainboard), Sideboard: deckCards(sideboard),
	}
	player.Deck = &deck
	player.MainboardInstanceIDs = append([]string(nil), request.MainboardInstanceIDs...)
	player.BasicLands = append([]protocol.LimitedBasicLand(nil), request.BasicLands...)
	return &deck, nil
}
