// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"errors"
	"fmt"
	"strings"
)

const (
	maxPlayers        = 8
	maxCardsPerPlayer = 1000
)

var (
	ErrClosed           = errors.New("forge runtime is closed")
	ErrRuntime          = errors.New("forge runtime error")
	ErrResponseTooLarge = errors.New("forge runtime response exceeds the configured limit")
)

// CardIdentity identifies one physical card printing passed to Forge.
type CardIdentity struct {
	Name            string `json:"name"`
	SetCode         string `json:"setCode,omitempty"`
	CollectorNumber string `json:"collectorNumber,omitempty"`
	Foil            bool   `json:"foil,omitempty"`
}

// PlayerConfig is one Forge seat. Deck contains one entry per physical card;
// callers expand Hexproof deck quantities before crossing this boundary.
type PlayerConfig struct {
	Name           string         `json:"name"`
	Deck           []CardIdentity `json:"deck"`
	CommanderNames []string       `json:"commanderNames,omitempty"`
	AI             bool           `json:"ai,omitempty"`
}

// StartGameRequest is the typed payload accepted by the upstream headless
// Forge harness.
type StartGameRequest struct {
	GameID       string         `json:"gameId"`
	Variant      string         `json:"variant"`
	StartingLife int            `json:"startingLife"`
	Seed         int64          `json:"seed"`
	Players      []PlayerConfig `json:"players"`
}

func (request StartGameRequest) validate() error {
	if strings.TrimSpace(request.GameID) == "" {
		return errors.New("game id is required")
	}
	if len(request.Players) < 2 || len(request.Players) > maxPlayers {
		return fmt.Errorf("player count must be between 2 and %d", maxPlayers)
	}
	if request.StartingLife <= 0 || request.StartingLife > 1000 {
		return errors.New("starting life must be between 1 and 1000")
	}
	for playerIndex, player := range request.Players {
		if strings.TrimSpace(player.Name) == "" {
			return fmt.Errorf("player %d name is required", playerIndex)
		}
		if len(player.Deck) == 0 || len(player.Deck) > maxCardsPerPlayer {
			return fmt.Errorf("player %d deck must contain between 1 and %d cards",
				playerIndex, maxCardsPerPlayer)
		}
		for cardIndex, card := range player.Deck {
			if strings.TrimSpace(card.Name) == "" {
				return fmt.Errorf("player %d card %d name is required", playerIndex, cardIndex)
			}
		}
	}
	return nil
}

// SessionHandle is returned after Forge accepts a new game.
type SessionHandle struct {
	SessionID     string `json:"sessionId"`
	PlayerIndexes []int  `json:"playerIndexes"`
}
