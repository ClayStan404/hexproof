// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import (
	"sort"
	"strings"

	"hexproof/server/internal/protocol"
)

var basicLandNames = map[string]string{
	"plains": "Plains", "island": "Island", "swamp": "Swamp",
	"mountain": "Mountain", "forest": "Forest",
}

type cardKey struct {
	name         string
	set          string
	collector    string
	typeLine     string
	virtualBasic bool
}

func appendDeckCard(cards map[cardKey]int, card *CardInstance) {
	key := cardKey{name: card.Name, set: card.SetCode, collector: card.CollectorNumber, typeLine: card.TypeLine}
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
		if keys[left].collector != keys[right].collector {
			return keys[left].collector < keys[right].collector
		}
		if keys[left].virtualBasic != keys[right].virtualBasic {
			return !keys[left].virtualBasic
		}
		return keys[left].typeLine < keys[right].typeLine
	})
	result := make([]protocol.DeckCard, 0, len(keys))
	for _, key := range keys {
		result = append(result, protocol.DeckCard{
			Name: key.name, Count: cards[key], SetCode: key.set,
			CollectorNumber: key.collector, TypeLine: key.typeLine, VirtualBasic: key.virtualBasic,
		})
	}
	return result
}

func (e *Event) SubmitDeck(participantID string, request protocol.LimitedSubmitDeck) (*protocol.DeckSelect, error) {
	if e.Stage != protocol.LimitedStageDeckBuilding {
		return nil, fail(ErrDeckInvalid, "limited deck building is not active")
	}
	return e.submitDeck(participantID, request)
}

// UpdateCasualDeck validates the same immutable pool after construction. The
// coordinator must authorize that the player has no reserved or active table.
func (e *Event) UpdateCasualDeck(participantID string, request protocol.LimitedSubmitDeck) (*protocol.DeckSelect, error) {
	if e.Stage != protocol.LimitedStageCompetition {
		return nil, fail(ErrDeckInvalid, "limited free play is not active")
	}
	return e.submitDeck(participantID, request)
}

func (e *Event) submitDeck(participantID string, request protocol.LimitedSubmitDeck) (*protocol.DeckSelect, error) {
	player := e.Player(participantID)
	if player == nil {
		return nil, fail(ErrForbidden, "participant does not own a limited pool")
	}
	request.Name = strings.TrimSpace(request.Name)
	if !validText(request.Name, protocol.MaxDeckNameRunes) {
		return nil, fail(ErrDeckInvalid, "invalid limited deck name")
	}
	pool := make(map[string]*CardInstance, len(player.Pool))
	for _, card := range player.Pool {
		pool[card.ID] = card
	}
	optional := make(map[string]*CardInstance)
	for _, card := range e.optionalCards(participantID) {
		optional[card.ID] = card
	}
	optionalCount := 0
	selected := make(map[string]bool, len(request.MainboardInstanceIDs))
	mainboard := make(map[cardKey]int)
	for _, instanceID := range request.MainboardInstanceIDs {
		card := pool[instanceID]
		if card == nil {
			card = optional[instanceID]
			optionalCount++
		}
		if card == nil || selected[instanceID] {
			return nil, fail(ErrDeckInvalid, "main deck contains an unavailable pool card")
		}
		selected[instanceID] = true
		appendDeckCard(mainboard, card)
	}
	commanders, commanderColors, err := e.selectedCommanders(player.ID, request, selected, pool)
	if err != nil {
		return nil, err
	}
	mainboardCount := len(request.MainboardInstanceIDs)
	totalCount := len(player.Pool) + optionalCount
	for _, commander := range commanders {
		if pool[commander.ID] == nil {
			appendDeckCard(mainboard, commander)
			mainboardCount++
			totalCount++
		}
	}
	for _, basic := range request.BasicLands {
		name := basicLandNames[strings.ToLower(strings.TrimSpace(basic.Name))]
		if name == "" || basic.Count < 1 || basic.Count > protocol.MaxDeckCards ||
			totalCount > protocol.MaxDeckCards-basic.Count {
			return nil, fail(ErrDeckInvalid, "invalid basic land addition")
		}
		key := cardKey{
			name: name, set: strings.ToUpper(strings.TrimSpace(basic.SetCode)),
			collector: strings.TrimSpace(basic.CollectorNumber), typeLine: "Basic Land", virtualBasic: true,
		}
		if (key.set == "") != (key.collector == "") ||
			!validOptionalText(key.set, protocol.MaxSetCodeRunes) ||
			!validOptionalText(key.collector, protocol.MaxCollectorNumberRunes) {
			return nil, fail(ErrDeckInvalid, "invalid basic land printing")
		}
		mainboardCount += basic.Count
		totalCount += basic.Count
		mainboard[key] += basic.Count
	}
	if mainboardCount < e.MinimumDeckCards() ||
		mainboardCount > protocol.MaxDeckCards {
		return nil, fail(ErrDeckInvalid, "limited main deck must contain at least "+itoa(e.MinimumDeckCards())+" cards")
	}
	sideboard := make(map[cardKey]int)
	for _, card := range player.Pool {
		if !selected[card.ID] {
			appendDeckCard(sideboard, card)
		}
	}
	// Pairing rooms apply the same transport bounds to the complete partition.
	// Reject an unusable deck before acknowledging or replacing construction.
	if totalCount > protocol.MaxDeckCards || len(mainboard)+len(sideboard) > protocol.MaxDeckEntries {
		return nil, fail(ErrDeckInvalid, "limited deck exceeds the table's card or entry limit")
	}
	deck := protocol.DeckSelect{
		Name: request.Name, Format: protocol.FormatModern,
		DeckFormat: protocol.DeckFormatLimited,
		Mainboard:  deckCards(mainboard), Sideboard: deckCards(sideboard),
	}
	if e.EventType == protocol.LimitedEventCommanderCube {
		deck.Format = protocol.FormatEDH
		deck.DeckFormat = protocol.DeckFormatCommanderLimited
		for _, card := range commanders {
			deck.Commanders = append(deck.Commanders, card.Name)
			deck.CommanderPrintings = append(deck.CommanderPrintings, protocol.DeckCard{
				Name: card.Name, Count: 1, SetCode: card.SetCode,
				CollectorNumber: card.CollectorNumber, TypeLine: card.TypeLine,
			})
			deck.CommanderColors = append(deck.CommanderColors, commanderColors[card.ID])
		}
		deck.Commander = deck.Commanders[0]
	}
	player.Deck = &deck
	player.MainboardInstanceIDs = append([]string(nil), request.MainboardInstanceIDs...)
	player.CommanderInstanceIDs = append([]string(nil), request.CommanderInstanceIDs...)
	player.CommanderColors = append([]protocol.LimitedCommanderColor(nil), request.CommanderColors...)
	player.BasicLands = append([]protocol.LimitedBasicLand(nil), request.BasicLands...)
	return &deck, nil
}
