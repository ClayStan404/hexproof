// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import (
	"crypto/sha256"
	"fmt"

	"hexproof/server/internal/protocol"
)

// Each owner may add one outside copy of each staple during construction.
// These identities never consume draft stock or appear in an unused sideboard.
func (e *Event) optionalCards(participantID string) []*CardInstance {
	if e.EventType != protocol.LimitedEventCommanderCube || e.Player(participantID) == nil ||
		(e.Stage != protocol.LimitedStageDeckBuilding && e.Stage != protocol.LimitedStageCompetition) {
		return nil
	}
	cards := []*CardInstance{
		{Name: "Sol Ring", SetCode: "CMR", CollectorNumber: "472", TypeLine: "Artifact", Rarity: "uncommon", Finish: "nonfoil"},
		{Name: "Command Tower", SetCode: "CMR", CollectorNumber: "350", TypeLine: "Land", Rarity: "common", Finish: "nonfoil"},
		{Name: "Arcane Signet", SetCode: "CMR", CollectorNumber: "297", TypeLine: "Artifact", Rarity: "uncommon", Finish: "nonfoil"},
	}
	for _, card := range cards {
		identity := sha256.Sum256([]byte(e.TournamentID + "\x00" + participantID + "\x00optional\x00" + card.Name))
		card.ID = fmt.Sprintf("optional-%x", identity[:16])
	}
	return cards
}
