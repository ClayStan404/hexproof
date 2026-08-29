// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"testing"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
)

const forgeLifecycleHelperEnvironment = "HEXPROOF_FORGE_LIFECYCLE_HELPER"

func TestForgeStartRequestPreservesPrintingsAndCommanderVariant(t *testing.T) {
	r := &room.Room{ID: "ABCDEF", LoadID: 3, Format: protocol.FormatEDH}
	deck := protocol.DeckSelect{
		Commander: "Atraxa, Praetors' Voice",
		Commanders: []string{
			"Atraxa, Praetors' Voice", " atraxa, praetors' voice ",
		},
		Mainboard: []protocol.DeckCard{{
			Name: "Atraxa, Praetors' Voice", Count: 2,
			SetCode: "C16", CollectorNumber: "28",
		}},
	}
	request, seats, err := forgeStartRequest(r, []room.RulesStartPlayer{
		{Seat: 2, DisplayName: "Alice", Deck: deck},
		{Seat: 3, DisplayName: "Bob", Deck: deck},
	})
	if err != nil {
		t.Fatalf("forgeStartRequest: %v", err)
	}
	if request.GameID != "ABCDEF-3" || request.Variant != "Commander" ||
		request.StartingLife != 40 || len(request.Players) != 2 ||
		len(request.Players[0].Deck) != 2 || request.Players[0].Deck[0].SetCode != "C16" ||
		request.Players[0].Deck[0].CollectorNumber != "28" ||
		len(request.Players[0].CommanderNames) != 1 ||
		len(seats) != 2 || seats[0] != 2 || seats[1] != 3 {
		t.Fatalf("Forge request = %+v seats=%v", request, seats)
	}
}

func TestForgeRoomLifecycleProjectsViewerPrivateState(t *testing.T) {
	if os.Getenv(forgeLifecycleHelperEnvironment) == "1" {
		runForgeLifecycleHelper(t)
		return
	}
	config := DefaultConfig()
	config.ForgeRuntime = &forge.ProcessConfig{
		Command: os.Args[0],
		Args:    []string{"-test.run=TestForgeRoomLifecycleProjectsViewerPrivateState"},
		Env:     []string{forgeLifecycleHelperEnvironment + "=1"},
	}
	handler, err := NewHandlerWithConfig(config)
	if err != nil {
		t.Fatalf("NewHandlerWithConfig: %v", err)
	}
	t.Cleanup(func() {
		if err := handler.Close(); err != nil {
			t.Errorf("Handler.Close: %v", err)
		}
	})

	host := &Session{ConnectionID: "host-conn", DisplayName: "Alice"}
	r, _, _, createdEntry, err := handler.hub.CreateRoomWithRulesMode(
		"Rules table", protocol.FormatModern, protocol.DeckFormatCustom,
		protocol.MatchBO1, protocol.CardLoadBackground, protocol.RulesModeForge,
		2, true, false, "", host)
	if err != nil {
		t.Fatalf("CreateRoomWithRulesMode: %v", err)
	}
	createdEntry.opMu.Unlock()

	guest := &Session{ConnectionID: "guest-conn", DisplayName: "Bob"}
	joinEntry, err := handler.hub.beginJoin(r.ID, "")
	if err != nil {
		t.Fatalf("beginJoin: %v", err)
	}
	if _, _, err := handler.hub.joinRoom(joinEntry, guest, false); err != nil {
		joinEntry.opMu.Unlock()
		t.Fatalf("joinRoom: %v", err)
	}
	joinEntry.opMu.Unlock()

	operation, err := handler.hub.lockRoomOperation(r.ID)
	if err != nil {
		t.Fatalf("lockRoomOperation: %v", err)
	}
	deck := protocol.DeckSelect{
		Name: "Rules deck", Format: protocol.FormatModern,
		DeckFormat: protocol.DeckFormatCustom,
		Mainboard: []protocol.DeckCard{{
			Name: "Forest", Count: protocol.MinMainboardCards,
			SetCode: "M21", CollectorNumber: "272",
		}},
		Sideboard: []protocol.DeckCard{},
	}
	for _, connectionID := range []string{host.ConnectionID, guest.ConnectionID} {
		if _, err := handler.hub.SelectDeck(connectionID, deck, r); err != nil {
			t.Fatalf("SelectDeck(%s): %v", connectionID, err)
		}
	}
	if _, err := handler.hub.SetReady(host.ConnectionID, true, r); err != nil {
		t.Fatalf("SetReady(host): %v", err)
	}
	started, err := handler.hub.SetReady(guest.ConnectionID, true, r)
	if err != nil || !started.StartRulesGame {
		t.Fatalf("SetReady(guest) = %+v, %v", started, err)
	}
	state, err := handler.startForgeGame(r)
	if err != nil {
		operation.opMu.Unlock()
		t.Fatalf("startForgeGame: %v", err)
	}
	assertRulesProjectionVisibility(t, state.projections[host.ConnectionID], 0, true, false)
	assertRulesProjectionVisibility(t, state.projections[guest.ConnectionID], 1, false, true)
	assertRulesPromptOwner(t, state.prompts, host.ConnectionID, guest.ConnectionID)
	operation.opMu.Unlock()

	spectator := &Session{ConnectionID: "spectator-conn", DisplayName: "Observer"}
	joinSpectator, err := handler.hub.beginJoin(r.ID, "")
	if err != nil {
		t.Fatalf("beginJoin(spectator): %v", err)
	}
	joinResult, _, err := handler.hub.joinRoom(joinSpectator, spectator, true)
	joinSpectator.opMu.Unlock()
	if err != nil || !joinResult.ProjectGame {
		t.Fatalf("joinRoom(spectator) = %+v, %v", joinResult, err)
	}
	spectatorProjections, err := handler.rulesProjections(r)
	if err != nil {
		t.Fatalf("rulesProjections(spectator): %v", err)
	}
	assertRulesProjectionVisibility(t,
		spectatorProjections[spectator.ConnectionID], -1, false, false)
}

func assertRulesProjectionVisibility(t *testing.T, envelope protocol.Envelope,
	wantViewerSeat int, aliceVisible, bobVisible bool) {
	t.Helper()
	if envelope.Type != protocol.TypeRulesSnapshot || !envelope.HasSeq() {
		t.Fatalf("rules envelope = %+v", envelope)
	}
	var snapshot protocol.RulesGameSnapshot
	if err := envelope.DecodePayload(&snapshot); err != nil {
		t.Fatalf("DecodePayload: %v", err)
	}
	visibility := map[int]bool{}
	for _, zone := range snapshot.Zones {
		if zone.Zone != "hand" {
			continue
		}
		visibility[zone.OwnerSeat] = len(zone.Cards) == 1 &&
			zone.Cards[0].Visible && zone.Cards[0].Identity != nil
	}
	if visibility[0] != aliceVisible || visibility[1] != bobVisible {
		t.Fatalf("viewer %d hand visibility = %+v", wantViewerSeat, visibility)
	}
}

func assertRulesPromptOwner(t *testing.T, prompts map[string]protocol.Envelope,
	hostConnectionID, guestConnectionID string) {
	t.Helper()
	var hostPrompt protocol.RulesPrompt
	if err := prompts[hostConnectionID].DecodePayload(&hostPrompt); err != nil {
		t.Fatalf("DecodePayload(host prompt): %v", err)
	}
	if !hostPrompt.Pending || hostPrompt.PromptID != 1 ||
		hostPrompt.Kind != "mulligan" || !hostPrompt.Supported {
		t.Fatalf("host prompt = %+v", hostPrompt)
	}
	var guestPrompt protocol.RulesPrompt
	if err := prompts[guestConnectionID].DecodePayload(&guestPrompt); err != nil {
		t.Fatalf("DecodePayload(guest prompt): %v", err)
	}
	if guestPrompt.Pending || guestPrompt.PromptID != 0 || len(guestPrompt.Options) != 0 {
		t.Fatalf("guest prompt = %+v", guestPrompt)
	}
}

func runForgeLifecycleHelper(t *testing.T) {
	t.Helper()
	type helperRequest struct {
		Command     string `json:"command"`
		Payload     string `json:"payload"`
		SessionID   string `json:"sessionId"`
		PlayerIndex *int   `json:"playerIndex"`
		Viewer      *int   `json:"viewer"`
	}
	type helperResponse struct {
		OK     bool   `json:"ok"`
		Result string `json:"result"`
		Error  string `json:"error"`
	}
	scanner := bufio.NewScanner(os.Stdin)
	encoder := json.NewEncoder(os.Stdout)
	gameID := ""
	for scanner.Scan() {
		var request helperRequest
		if err := json.Unmarshal(scanner.Bytes(), &request); err != nil {
			_ = encoder.Encode(helperResponse{Error: "invalid request"})
			continue
		}
		if request.Command == "quit" {
			return
		}
		response := helperResponse{OK: true}
		switch request.Command {
		case "reset", "abortGame", "endGame":
			response.Result = ""
		case "startGame":
			var start forge.StartGameRequest
			if err := json.Unmarshal([]byte(request.Payload), &start); err != nil ||
				start.Variant != "Constructed" || start.StartingLife != 20 ||
				len(start.Players) != 2 || len(start.Players[0].Deck) != protocol.MinMainboardCards ||
				start.Players[0].Deck[0].SetCode != "M21" {
				response = helperResponse{Error: "invalid start payload"}
				break
			}
			gameID = start.GameID
			response.Result = `{"sessionId":"rules-session-1","playerIndexes":[0,1]}`
		case "getSnapshot":
			if request.SessionID != "rules-session-1" || request.Viewer == nil {
				response = helperResponse{Error: "invalid snapshot request"}
				break
			}
			snapshot := forgeLifecycleSnapshot(gameID, *request.Viewer)
			encoded, err := json.Marshal(snapshot)
			if err != nil {
				response = helperResponse{Error: "encode snapshot"}
			} else {
				response.Result = string(encoded)
			}
		case "getPrompt":
			if request.SessionID != "rules-session-1" || request.PlayerIndex == nil {
				response = helperResponse{Error: "invalid prompt request"}
				break
			}
			// The pinned harness currently exposes one session-global prompt and
			// ignores playerIndex. Hexproof must project it only to its owner.
			response.Result = `{"promptId":1,"decidingPlayerId":"player-0",` +
				`"input":{"type":"mulligan","mulliganCount":0}}`
		default:
			response = helperResponse{Error: fmt.Sprintf("unknown command %s", request.Command)}
		}
		if err := encoder.Encode(response); err != nil {
			return
		}
	}
}

func forgeLifecycleSnapshot(gameID string, viewer int) map[string]any {
	handZone := func(player int, name string) map[string]any {
		cards := []any{}
		if viewer == player {
			cards = append(cards, map[string]any{
				"visibility": "visible", "id": fmt.Sprintf("private-%d", player),
				"identity": map[string]any{
					"name": name, "setCode": "TST", "cardNumber": "1", "isToken": false,
				},
				"ownerId":      fmt.Sprintf("player-%d", player),
				"controllerId": fmt.Sprintf("player-%d", player),
			})
		}
		return map[string]any{
			"zone": "hand", "ownerId": fmt.Sprintf("player-%d", player),
			"cards": cards, "count": 1,
		}
	}
	return map[string]any{
		"gameId": gameID, "turn": 1, "step": "main1",
		"activePlayerId": "player-0", "priorityPlayerId": "player-0",
		"players": []any{
			map[string]any{"id": "player-0", "name": "Alice", "status": "playing", "life": 20, "counters": map[string]int{}, "manaPool": map[string]int{}},
			map[string]any{"id": "player-1", "name": "Bob", "status": "playing", "life": 20, "counters": map[string]int{}, "manaPool": map[string]int{}},
		},
		"zones": []any{handZone(0, "Private Alice"), handZone(1, "Private Bob")},
		"stack": []any{}, "gameOver": false,
	}
}
