// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestGameViewDecodesVisibleAndHiddenCards(t *testing.T) {
	raw := []byte(`{
        "gameId":"game-1","turn":2,"step":"main1",
        "activePlayerId":"player-0","priorityPlayerId":"player-1",
        "players":[
          {"id":"player-0","name":"Alice","status":"playing","life":20,"counters":{},"manaPool":{"U":1}},
          {"id":"player-1","name":"Bob","status":"playing","life":19,"counters":{"poison":1},"manaPool":{}}
        ],
        "zones":[
          {"zone":"hand","ownerId":"player-0","count":1,"cards":[
            {"visibility":"visible","id":"card-1","identity":{"name":"Opt","setCode":"XLN","cardNumber":"65","isToken":false},"ownerId":"player-0","controllerId":"player-0"}
          ]},
          {"zone":"hand","ownerId":"player-1","count":2,"cards":[]},
          {"zone":"exile","ownerId":"player-1","count":1,"cards":[
            {"visibility":"hidden","id":"card-2"}
          ]}
        ],
        "stack":[],"gameOver":false
      }`)
	var view GameView
	if err := json.Unmarshal(raw, &view); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	if err := view.validate(); err != nil {
		t.Fatalf("validate: %v", err)
	}
	if view.Zones[0].Cards[0].Identity == nil ||
		view.Zones[0].Cards[0].Identity.CardNumber != "65" ||
		view.Zones[2].Cards[0].Identity != nil {
		t.Fatalf("decoded cards = %+v", view.Zones)
	}
}

func TestGameViewRejectsUnknownAuthorizationReferences(t *testing.T) {
	view := GameView{
		GameID: "game-1", ActivePlayerID: "player-0",
		PriorityPlayerID: "player-7",
		Players: []PlayerView{
			{ID: "player-0", Name: "Alice", Status: "playing"},
			{ID: "player-1", Name: "Bob", Status: "playing"},
		},
	}
	if err := view.validate(); err == nil || !strings.Contains(err.Error(), "priority player") {
		t.Fatalf("validate error = %v", err)
	}
}

func TestGameViewRejectsUnknownPlayerStatus(t *testing.T) {
	view := GameView{
		GameID: "game-1", ActivePlayerID: "player-0", PriorityPlayerID: "player-0",
		Players: []PlayerView{
			{ID: "player-0", Status: "playing"},
			{ID: "player-1", Status: "waiting"},
		},
	}
	if err := view.validate(); err == nil || !strings.Contains(err.Error(), "invalid status") {
		t.Fatalf("validate error = %v", err)
	}
}

func TestPlayerIndexFromID(t *testing.T) {
	if index, err := PlayerIndexFromID("player-3"); err != nil || index != 3 {
		t.Fatalf("PlayerIndexFromID(player-3) = %d, %v", index, err)
	}
	for _, invalid := range []string{"", "3", "player--1", "player-8"} {
		if _, err := PlayerIndexFromID(invalid); err == nil {
			t.Fatalf("PlayerIndexFromID(%q) succeeded", invalid)
		}
	}
}
