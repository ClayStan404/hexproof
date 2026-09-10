// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import "hexproof/server/internal/protocol"

const (
	commanderCubeCardsPerPack = 20
	commanderMinimumDeckCards = 60
)

func isCubeEvent(eventType string) bool {
	return eventType == protocol.LimitedEventCubeDraft ||
		eventType == protocol.LimitedEventCommanderCube
}

func cubeCardsPerPack(eventType string) int {
	if eventType == protocol.LimitedEventCommanderCube {
		return commanderCubeCardsPerPack
	}
	return cubeDraftCardsPerPack
}

func CubeDraftCardsRequiredForEvent(eventType string, players int) int {
	return players * draftPacksPerPlayer * cubeCardsPerPack(eventType)
}

func (e *Event) PicksPerSelection() int {
	if e.EventType == protocol.LimitedEventCommanderCube {
		return 2
	}
	return 1
}

func (e *Event) MinimumDeckCards() int {
	if e.EventType == protocol.LimitedEventCommanderCube {
		return commanderMinimumDeckCards
	}
	return protocol.MinLimitedMainboardCards
}
