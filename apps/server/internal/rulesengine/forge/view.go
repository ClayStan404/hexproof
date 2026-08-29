// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
)

// GameView is the backend-private subset of Forge's viewer-specific snapshot
// that Hexproof currently projects. Unknown upstream fields are deliberately
// ignored so harness additions do not change the public wire contract.
type GameView struct {
	GameID           string            `json:"gameId"`
	Turn             int               `json:"turn"`
	Step             string            `json:"step"`
	ActivePlayerID   string            `json:"activePlayerId"`
	PriorityPlayerID string            `json:"priorityPlayerId"`
	Players          []PlayerView      `json:"players"`
	Zones            []ZoneView        `json:"zones"`
	Stack            []StackObjectView `json:"stack"`
	GameOver         bool              `json:"gameOver"`
	WinnerID         string            `json:"winnerId,omitempty"`
}

type PlayerView struct {
	ID       string         `json:"id"`
	Name     string         `json:"name"`
	Status   string         `json:"status"`
	Life     int            `json:"life"`
	Counters map[string]int `json:"counters"`
	ManaPool map[string]int `json:"manaPool"`
}

type ZoneView struct {
	Zone    string     `json:"zone"`
	OwnerID string     `json:"ownerId"`
	Cards   []CardView `json:"cards"`
	Count   int        `json:"count"`
}

type CardIdentityView struct {
	Name       string `json:"name"`
	SetCode    string `json:"setCode"`
	CardNumber string `json:"cardNumber"`
	Token      bool   `json:"isToken"`
}

type CardView struct {
	Visibility   string            `json:"visibility"`
	ID           string            `json:"id"`
	Identity     *CardIdentityView `json:"identity,omitempty"`
	OwnerID      string            `json:"ownerId,omitempty"`
	ControllerID string            `json:"controllerId,omitempty"`
	Tapped       bool              `json:"tapped,omitempty"`
	FaceDown     bool              `json:"isFaceDown,omitempty"`
	Attacking    bool              `json:"isAttacking,omitempty"`
	Power        string            `json:"power,omitempty"`
	Toughness    string            `json:"toughness,omitempty"`
	Counters     map[string]int    `json:"counters,omitempty"`
	Damage       int               `json:"damage,omitempty"`
	AttachedTo   string            `json:"attachedTo,omitempty"`
}

type StackObjectView struct {
	ID           string           `json:"id"`
	SourceID     string           `json:"sourceId"`
	ControllerID string           `json:"controllerId"`
	OwnerID      string           `json:"ownerId"`
	Identity     CardIdentityView `json:"identity"`
	Text         string           `json:"text"`
}

// SnapshotView decodes a raw harness projection before it reaches the room or
// WebSocket layers. It validates the player references used for authorization
// and seat mapping while tolerating unrelated fields added by Forge.
func (client *Client) SnapshotView(ctx context.Context, sessionID string,
	viewer int) (GameView, error) {
	raw, err := client.Snapshot(ctx, sessionID, viewer)
	if err != nil {
		return GameView{}, err
	}
	var view GameView
	if err := json.Unmarshal(raw, &view); err != nil {
		return GameView{}, fmt.Errorf("%w: decode snapshot view: %v", ErrRuntime, err)
	}
	if err := view.validate(); err != nil {
		return GameView{}, fmt.Errorf("%w: invalid snapshot view: %v", ErrRuntime, err)
	}
	return view, nil
}

func (view GameView) validate() error {
	if strings.TrimSpace(view.GameID) == "" {
		return fmt.Errorf("game id is required")
	}
	if len(view.Players) < 2 || len(view.Players) > maxPlayers {
		return fmt.Errorf("player count must be between 2 and %d", maxPlayers)
	}
	playerIDs := make(map[string]struct{}, len(view.Players))
	for index, player := range view.Players {
		if _, err := PlayerIndexFromID(player.ID); err != nil {
			return fmt.Errorf("player %d: %v", index, err)
		}
		if _, duplicate := playerIDs[player.ID]; duplicate {
			return fmt.Errorf("duplicate player id %q", player.ID)
		}
		playerIDs[player.ID] = struct{}{}
	}
	for label, playerID := range map[string]string{
		"active player": view.ActivePlayerID, "priority player": view.PriorityPlayerID,
	} {
		if _, ok := playerIDs[playerID]; !ok {
			return fmt.Errorf("%s id %q is unknown", label, playerID)
		}
	}
	if view.WinnerID != "" {
		if _, ok := playerIDs[view.WinnerID]; !ok {
			return fmt.Errorf("winner id %q is unknown", view.WinnerID)
		}
	}
	for index, zone := range view.Zones {
		if strings.TrimSpace(zone.Zone) == "" {
			return fmt.Errorf("zone %d has no name", index)
		}
		if _, ok := playerIDs[zone.OwnerID]; !ok {
			return fmt.Errorf("zone %d owner id %q is unknown", index, zone.OwnerID)
		}
		if zone.Count < 0 || zone.Count < len(zone.Cards) {
			return fmt.Errorf("zone %d has invalid card count", index)
		}
	}
	return nil
}

// PlayerIndexFromID decodes the stable player-N identifiers emitted by the
// pinned harness. The coordinator uses it only to map engine players back to
// authenticated Hexproof seats.
func PlayerIndexFromID(playerID string) (int, error) {
	const prefix = "player-"
	if !strings.HasPrefix(playerID, prefix) {
		return 0, fmt.Errorf("invalid player id %q", playerID)
	}
	index, err := strconv.Atoi(strings.TrimPrefix(playerID, prefix))
	if err != nil || index < 0 || index >= maxPlayers {
		return 0, fmt.Errorf("invalid player id %q", playerID)
	}
	return index, nil
}
