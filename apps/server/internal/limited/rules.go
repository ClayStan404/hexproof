// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import "hexproof/server/internal/protocol"

const (
	commanderCubeCardsPerPack = 20
	minCommanderCardsPerPack  = 10
	maxCommanderCardsPerPack  = 40
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
	settings, _ := ResolveDraftSettings(eventType, players, nil)
	return players * settings.PacksPerPlayer * settings.CardsPerPack
}

// ResolveDraftSettings also validates the creation-time capacity. Smaller
// groups can select more packs; five to eight seats open three packs separately.
func ResolveDraftSettings(eventType string, players int, requested *protocol.LimitedDraftSettings) (protocol.LimitedDraftSettings, error) {
	settings := protocol.LimitedDraftSettings{PacksPerPlayer: draftPacksPerPlayer, PacksPerBatch: 1,
		CardsPerPack: cubeCardsPerPack(eventType)}
	if eventType != protocol.LimitedEventCommanderCube {
		if requested != nil {
			return settings, fail(ErrInvalid, "custom draft settings require Commander Cube")
		}
		return settings, nil
	}
	if players <= 4 {
		settings.PacksPerPlayer, settings.PacksPerBatch = 6, 2
	}
	if requested != nil {
		settings = *requested
		// Older clients omit pack size and retain the original 20-card packs.
		if settings.CardsPerPack == 0 {
			settings.CardsPerPack = commanderCubeCardsPerPack
		}
	}
	if settings.CardsPerPack < minCommanderCardsPerPack || settings.CardsPerPack > maxCommanderCardsPerPack {
		return settings, fail(ErrInvalid, "choose 10 to 40 cards per Commander Cube pack")
	}
	switch settings.PacksPerPlayer {
	case 3, 4, 5, 6, 8:
	default:
		return settings, fail(ErrInvalid, "choose three, four, five, six, or eight packs per player")
	}
	if settings.PacksPerBatch != 1 && settings.PacksPerBatch != 2 {
		return settings, fail(ErrInvalid, "open one or two packs per batch")
	}
	if players > 4 && (settings.PacksPerPlayer != 3 || settings.PacksPerBatch != 1) {
		return settings, fail(ErrInvalid, "five to eight players use three packs, opened one at a time")
	}
	return settings, nil
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
