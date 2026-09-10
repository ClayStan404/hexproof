// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import (
	"crypto/sha256"
	"fmt"
	"strings"

	"hexproof/server/internal/protocol"
)

const prismaticPiperName = "The Prismatic Piper"

// Fallback candidates are private construction aids, not drafted pool cards.
// Derivation is stable across reconnects and never changes draft RNG or stock.
func (e *Event) fallbackCommanders(participantID string) []*CardInstance {
	if e.EventType != protocol.LimitedEventCommanderCube || e.Player(participantID) == nil ||
		(e.Stage != protocol.LimitedStageDeckBuilding && e.Stage != protocol.LimitedStageCompetition) {
		return nil
	}
	result := make([]*CardInstance, 0, protocol.MaxCommanders)
	for index := 0; index < protocol.MaxCommanders; index++ {
		identity := sha256.Sum256([]byte(fmt.Sprintf("%s\x00%s\x00%d", e.TournamentID, participantID, index)))
		result = append(result, &CardInstance{
			ID: fmt.Sprintf("piper-%x", identity[:16]), Name: prismaticPiperName,
			SetCode: "CMR", CollectorNumber: "1", TypeLine: "Legendary Creature — Shapeshifter",
			Rarity: "special", Finish: "nonfoil",
		})
	}
	return result
}

// Qualification and partner compatibility remain advisory. Physical ownership,
// commander-only fallback use, and each selected Piper's color are authoritative.
func (e *Event) selectedCommanders(participantID string, request protocol.LimitedSubmitDeck,
	selected map[string]bool, pool map[string]*CardInstance) ([]*CardInstance, map[string]string, error) {
	ids := request.CommanderInstanceIDs
	if e.EventType != protocol.LimitedEventCommanderCube {
		if len(ids) != 0 || len(request.CommanderColors) != 0 {
			return nil, nil, fail(ErrDeckInvalid, "this limited format does not use commanders")
		}
		return nil, nil, nil
	}
	if len(ids) < 1 || len(ids) > protocol.MaxCommanders {
		return nil, nil, fail(ErrDeckInvalid, "select one or two commander instances")
	}
	fallbacks := make(map[string]*CardInstance, protocol.MaxCommanders)
	for _, card := range e.fallbackCommanders(participantID) {
		fallbacks[card.ID] = card
	}
	seen := make(map[string]bool, len(ids))
	pipers := make(map[string]bool, len(ids))
	commanders := make([]*CardInstance, 0, len(ids))
	for _, id := range ids {
		card := pool[id]
		if card != nil && !selected[id] {
			return nil, nil, fail(ErrDeckInvalid, "commander is not a selected pool card")
		}
		if card == nil {
			card = fallbacks[id]
		}
		if card == nil || seen[id] {
			return nil, nil, fail(ErrDeckInvalid, "commander is unavailable or selected more than once")
		}
		seen[id] = true
		if strings.EqualFold(strings.TrimSpace(card.Name), prismaticPiperName) {
			pipers[id] = true
		}
		commanders = append(commanders, card)
	}
	colors := make(map[string]string, len(pipers))
	for _, choice := range request.CommanderColors {
		if !pipers[choice.InstanceID] || colors[choice.InstanceID] != "" ||
			!protocol.ValidCommanderColor(choice.Color) {
			return nil, nil, fail(ErrDeckInvalid, "invalid Piper commander color choice")
		}
		colors[choice.InstanceID] = choice.Color
	}
	if len(colors) != len(pipers) {
		return nil, nil, fail(ErrDeckInvalid, "choose one color for each Piper commander")
	}
	return commanders, colors, nil
}
