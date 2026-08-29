// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func TestTwoClientCreateJoin(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	guest := dial(t, srv)
	defer guest.close()

	host.hello("Alice")
	guest.hello("Bob")

	_, roomID := host.createRoom("Friday EDH", protocol.FormatEDH, 4, true, "")
	initial := host.recvType(protocol.TypeRoomSnapshot)
	if !initial.HasSeq() || initial.SeqValue() != 1 {
		t.Fatalf("initial snapshot seq = %d (present=%v), want 1", initial.SeqValue(), initial.HasSeq())
	}

	joinEnv, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{
		RoomID: roomID, AsSpectator: false,
	})
	joinEnv.ID = "join"
	guest.send(joinEnv)
	joined := guest.recvType(protocol.TypeRoomJoined)
	var rj protocol.RoomJoined
	if err := joined.DecodePayload(&rj); err != nil {
		t.Fatalf("decode joined: %v", err)
	}
	if rj.Role != "player" || rj.Seat == nil || *rj.Seat != 1 {
		t.Fatalf("joined = %+v, want role=player seat=1", rj)
	}

	// Host should receive a snapshot showing Bob in seat 1.
	snap := host.recvType(protocol.TypeRoomSnapshot)
	if !snap.HasSeq() || snap.SeqValue() != 2 {
		t.Fatalf("join snapshot seq = %d (present=%v), want 2", snap.SeqValue(), snap.HasSeq())
	}
	var snapPayload protocol.RoomSnapshot
	if err := snap.DecodePayload(&snapPayload); err != nil {
		t.Fatalf("decode snapshot: %v", err)
	}
	if !snapPayload.Seats[1].Occupied || snapPayload.Seats[1].DisplayName != "Bob" {
		t.Fatalf("host snapshot seats[1] = %+v, want Bob", snapPayload.Seats[1])
	}
}

func TestCreateDuelCommanderCanonicalizesSeatsAndKeepsBO3(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	host.hello("Alice")

	createdEnvelope, _ := host.createRoom(
		"Duel Commander", protocol.FormatDuel, 4, true, "")
	var created protocol.RoomCreated
	if err := createdEnvelope.DecodePayload(&created); err != nil {
		t.Fatalf("decode duel room.created: %v", err)
	}
	if created.Settings.Format != protocol.FormatDuel ||
		created.Settings.MaxSeats != 2 ||
		created.Settings.MatchMode != protocol.MatchBO3 {
		t.Fatalf("duel settings = %+v", created.Settings)
	}
	host.recvType(protocol.TypeRoomSnapshot)
}

func TestForgeRoomRequiresConfiguredRuntime(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	welcomeEnvelope := host.hello("Alice")
	var welcome protocol.SessionWelcome
	if err := welcomeEnvelope.DecodePayload(&welcome); err != nil {
		t.Fatalf("decode welcome: %v", err)
	}
	if welcome.ForgeRulesAvailable {
		t.Fatal("default test server unexpectedly advertised Forge rules")
	}

	request, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{
		Name: "Rules table", Format: protocol.FormatModern,
		DeckFormat: protocol.DeckFormatModern, MaxSeats: 2,
		AllowSpectators: true, MatchMode: protocol.MatchBO1,
		CardLoadMode: protocol.CardLoadPreload, RulesMode: protocol.RulesModeForge,
	})
	request.ID = "forge-create"
	host.send(request)
	response := host.recvType(protocol.TypeError)
	var payload protocol.ErrorPayload
	if err := response.DecodePayload(&payload); err != nil {
		t.Fatalf("decode error: %v", err)
	}
	if response.ID != request.ID || payload.Code != protocol.ErrRulesUnavailable {
		t.Fatalf("forge create response = id %q payload %+v", response.ID, payload)
	}
}

func TestHubRoomListExposesOnlyPublicJoinMetadata(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	browser := dial(t, srv)
	defer browser.close()
	host.hello("Alice")
	browser.hello("Browser")

	_, roomID := host.createRoom(
		"Private Table", protocol.FormatModern, 2, true, "secret-password")
	host.recvType(protocol.TypeRoomSnapshot)

	request, _ := protocol.NewEnvelope(protocol.TypeRoomList, map[string]any{})
	request.ID = "list"
	browser.send(request)
	listedEnvelope := browser.recvType(protocol.TypeRoomListed)
	var listed protocol.RoomListed
	if err := listedEnvelope.DecodePayload(&listed); err != nil {
		t.Fatalf("decode room list: %v", err)
	}
	if len(listed.Rooms) != 1 {
		t.Fatalf("room list = %+v", listed.Rooms)
	}
	entry := listed.Rooms[0]
	if entry.RoomID != roomID || entry.Name != "Private Table" ||
		entry.PlayerCount != 1 || entry.MaxSeats != 2 ||
		!entry.HasPassword || !entry.PlayerJoinable ||
		!entry.SpectatorJoinable {
		t.Fatalf("room list entry = %+v", entry)
	}
	raw := string(listedEnvelope.Payload)
	if strings.Contains(raw, "Alice") ||
		strings.Contains(raw, "secret-password") ||
		strings.Contains(raw, "connectionId") {
		t.Fatalf("room list leaked private membership data: %s", raw)
	}
}

func TestRoomCreationPublishesSpectatorHandPolicy(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	browser := dial(t, srv)
	defer browser.close()
	host.hello("Alice")
	browser.hello("Browser")

	createdEnvelope, roomID := host.createRoom(
		"Commentated Table", protocol.FormatModern, 2, true, "", true)
	var created protocol.RoomCreated
	if err := createdEnvelope.DecodePayload(&created); err != nil {
		t.Fatalf("decode room.created: %v", err)
	}
	if !created.Settings.AllowSpectators || !created.Settings.SpectatorsSeeHands {
		t.Fatalf("created settings = %+v", created.Settings)
	}
	initialEnvelope := host.recvType(protocol.TypeRoomSnapshot)
	var initial protocol.RoomSnapshot
	if err := initialEnvelope.DecodePayload(&initial); err != nil {
		t.Fatalf("decode room.snapshot: %v", err)
	}
	if !initial.SpectatorsSeeHands {
		t.Fatalf("initial snapshot = %+v", initial)
	}

	request, _ := protocol.NewEnvelope(protocol.TypeRoomList, map[string]any{})
	request.ID = "list-hand-policy"
	browser.send(request)
	listedEnvelope := browser.recvType(protocol.TypeRoomListed)
	var listed protocol.RoomListed
	if err := listedEnvelope.DecodePayload(&listed); err != nil {
		t.Fatalf("decode room list: %v", err)
	}
	if len(listed.Rooms) != 1 || listed.Rooms[0].RoomID != roomID ||
		!listed.Rooms[0].SpectatorsSeeHands {
		t.Fatalf("room list = %+v", listed.Rooms)
	}
}

func TestReplayEndpointsReturnPublicLogOnly(t *testing.T) {
	config := DefaultConfig()
	config.RetentionDir = t.TempDir()
	srv, handler := newConfiguredTestServer(t, config)

	now := time.Now().UTC()
	retained, err := room.New(
		"ABCDEF", "Archived Table", protocol.FormatModern, protocol.MatchBO1,
		protocol.CardLoadPreload, 2, true, false, "Alice", "conn-secret", now)
	if err != nil {
		t.Fatalf("new retained room: %v", err)
	}
	retained.Game = &room.GameState{
		Number: 1,
		Seats: []room.PlayerGameState{{
			Seat: 0, DisplayName: "Alice",
			Hand: []protocol.GameCard{{
				ID: "secret-card", Name: "Demonic Tutor",
				SetCode: "STA", CollectorNumber: "27",
			}},
		}},
		Log: []protocol.GameLogEntry{{
			ID: 1, Kind: "draw", Seat: 0, Text: "Alice drew a card.",
		}},
	}
	if err := handler.retention.save(retained, now); err != nil {
		t.Fatalf("save retained replay: %v", err)
	}

	client := dial(t, srv)
	defer client.close()
	client.hello("Viewer")
	listRequest, _ := protocol.NewEnvelope(protocol.TypeReplayList, map[string]any{})
	listRequest.ID = "replays"
	client.send(listRequest)
	listedEnvelope := client.recvType(protocol.TypeReplayListed)
	var listed protocol.ReplayListed
	if err := listedEnvelope.DecodePayload(&listed); err != nil {
		t.Fatalf("decode replay list: %v", err)
	}
	if len(listed.Replays) != 1 {
		t.Fatalf("replay list = %+v", listed.Replays)
	}

	getRequest, _ := protocol.NewEnvelope(protocol.TypeReplayGet,
		protocol.ReplayGet{ReplayID: listed.Replays[0].ReplayID})
	getRequest.ID = "replay"
	client.send(getRequest)
	loadedEnvelope := client.recvType(protocol.TypeReplayLoaded)
	var loaded protocol.ReplayLoaded
	if err := loadedEnvelope.DecodePayload(&loaded); err != nil {
		t.Fatalf("decode replay: %v", err)
	}
	if len(loaded.Log) != 1 || loaded.Log[0].Kind != "draw" {
		t.Fatalf("loaded public log = %+v", loaded.Log)
	}
	raw := string(loadedEnvelope.Payload)
	if strings.Contains(raw, "secret-card") ||
		strings.Contains(raw, "Demonic Tutor") ||
		strings.Contains(raw, "conn-secret") ||
		strings.Contains(raw, "library") ||
		strings.Contains(raw, "hand") {
		t.Fatalf("replay endpoint leaked hidden state: %s", raw)
	}
}

func modernTestDeck(name string) protocol.DeckSelect {
	return protocol.DeckSelect{
		Name:       name,
		Format:     protocol.FormatModern,
		DeckFormat: protocol.DeckFormatCustom,
		Mainboard: []protocol.DeckCard{
			{Name: "Lightning Bolt", Count: 10, SetCode: "M11", CollectorNumber: "149"},
		},
		Sideboard: []protocol.DeckCard{},
	}
}

func TestTwoClientDeckSelectionAndReadyRemainPrivate(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	guest := dial(t, srv)
	defer guest.close()

	host.hello("Alice")
	guest.hello("Bob")
	_, roomID := host.createRoom("Modern", protocol.FormatModern, 2, true, "")
	host.recvType(protocol.TypeRoomSnapshot)

	join, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: roomID})
	join.ID = "join"
	guest.send(join)
	guest.recvType(protocol.TypeRoomJoined)
	host.recvType(protocol.TypeRoomSnapshot)
	guest.recvType(protocol.TypeRoomSnapshot)

	selectHost, _ := protocol.NewEnvelope(protocol.TypeDeckSelect, modernTestDeck("Burn"))
	selectHost.ID = "deck-host"
	host.send(selectHost)
	selected := host.recvType(protocol.TypeDeckSelected)
	if selected.ID != selectHost.ID {
		t.Fatalf("deck.selected id = %q, want %q", selected.ID, selectHost.ID)
	}
	host.recvType(protocol.TypeRoomSnapshot)
	guestView := guest.recvType(protocol.TypeRoomSnapshot)
	if strings.Contains(string(guestView.Payload), "Lightning Bolt") || strings.Contains(string(guestView.Payload), "Burn") {
		t.Fatalf("opponent snapshot leaked deck identities: %s", guestView.Payload)
	}
	var snapshot protocol.RoomSnapshot
	if err := guestView.DecodePayload(&snapshot); err != nil {
		t.Fatalf("decode snapshot: %v", err)
	}
	if !snapshot.Seats[0].DeckSelected || snapshot.Seats[0].Ready {
		t.Fatalf("host public state = %+v", snapshot.Seats[0])
	}

	selectGuest, _ := protocol.NewEnvelope(protocol.TypeDeckSelect, modernTestDeck("Prowess"))
	selectGuest.ID = "deck-guest"
	guest.send(selectGuest)
	guest.recvType(protocol.TypeDeckSelected)
	guest.recvType(protocol.TypeRoomSnapshot)
	host.recvType(protocol.TypeRoomSnapshot)

	readyHost, _ := protocol.NewEnvelope(protocol.TypePlayerReady, protocol.PlayerReady{Ready: true})
	readyHost.ID = "ready-host"
	host.send(readyHost)
	host.recvType(protocol.TypePlayerReadyChanged)
	host.recvType(protocol.TypeRoomSnapshot)
	guest.recvType(protocol.TypeRoomSnapshot)

	readyGuest, _ := protocol.NewEnvelope(protocol.TypePlayerReady, protocol.PlayerReady{Ready: true})
	readyGuest.ID = "ready-guest"
	guest.send(readyGuest)
	guest.recvType(protocol.TypePlayerReadyChanged)
	guest.recvType(protocol.TypeRoomSnapshot)
	final := host.recvType(protocol.TypeRoomSnapshot)
	if err := final.DecodePayload(&snapshot); err != nil {
		t.Fatalf("decode final snapshot: %v", err)
	}
	if !snapshot.Seats[0].Ready || !snapshot.Seats[1].Ready {
		t.Fatalf("final ready state = %+v", snapshot.Seats)
	}

	hostLoad := host.recvType(protocol.TypeMatchLoadRequired)
	guestLoad := guest.recvType(protocol.TypeMatchLoadRequired)
	var hostRequired, guestRequired protocol.MatchLoadRequired
	if err := hostLoad.DecodePayload(&hostRequired); err != nil {
		t.Fatalf("decode host load: %v", err)
	}
	if err := guestLoad.DecodePayload(&guestRequired); err != nil {
		t.Fatalf("decode guest load: %v", err)
	}
	if hostRequired.LoadID == 0 || hostRequired.LoadID != guestRequired.LoadID || len(hostRequired.CardKeys) != 1 {
		t.Fatalf("load payloads host=%+v guest=%+v", hostRequired, guestRequired)
	}

	hostComplete, _ := protocol.NewEnvelope(protocol.TypeClientLoadComplete,
		protocol.ClientLoadComplete{LoadID: hostRequired.LoadID})
	hostComplete.ID = "load-host"
	host.send(hostComplete)
	host.recvType(protocol.TypeClientLoadCompleted)
	host.recvType(protocol.TypeRoomSnapshot)
	guest.recvType(protocol.TypeRoomSnapshot)

	guestComplete, _ := protocol.NewEnvelope(protocol.TypeClientLoadComplete,
		protocol.ClientLoadComplete{LoadID: guestRequired.LoadID})
	guestComplete.ID = "load-guest"
	guest.send(guestComplete)
	completed := guest.recvType(protocol.TypeClientLoadCompleted)
	if completed.ID != guestComplete.ID {
		t.Fatalf("client.load_completed id = %q, want %q", completed.ID, guestComplete.ID)
	}
	guest.recvType(protocol.TypeMatchStarted)
	startedEvent := host.recvType(protocol.TypeMatchStarted)
	var startedPayload protocol.MatchStarted
	if err := startedEvent.DecodePayload(&startedPayload); err != nil {
		t.Fatalf("decode started: %v", err)
	}
	if startedPayload.LoadID != hostRequired.LoadID {
		t.Fatalf("match.started = %+v", startedPayload)
	}

	hostGameEvent := host.recvType(protocol.TypeGameSnapshot)
	guestGameEvent := guest.recvType(protocol.TypeGameSnapshot)
	var hostGame, guestGame protocol.GameSnapshot
	if err := hostGameEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host game: %v", err)
	}
	if err := guestGameEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest game: %v", err)
	}
	if hostGameEvent.SeqValue() != guestGameEvent.SeqValue() || len(hostGame.Log) < 3 {
		t.Fatalf("initial game projections host=%+v guest=%+v", hostGameEvent, guestGameEvent)
	}
	if len(hostGame.Seats[0].Hand) != 7 || len(hostGame.Seats[1].Hand) != 0 ||
		len(guestGame.Seats[0].Hand) != 0 || len(guestGame.Seats[1].Hand) != 7 {
		t.Fatalf("private opening hands host=%+v guest=%+v", hostGame.Seats, guestGame.Seats)
	}
	if hostGame.ActiveSeat != hostGame.StartingSeat ||
		hostGame.CurrentPhase != protocol.GamePhaseUntap ||
		guestGame.ActiveSeat != hostGame.ActiveSeat ||
		guestGame.CurrentPhase != hostGame.CurrentPhase {
		t.Fatalf("initial turn state host=%+v guest=%+v", hostGame, guestGame)
	}
	if hostGame.Seats[0].LibraryCount != 3 || guestGame.Seats[0].HandCount != 7 {
		t.Fatalf("opening counts host=%+v guest=%+v", hostGame.Seats, guestGame.Seats)
	}

	setLife, _ := protocol.NewEnvelope(protocol.TypeGameSetCounter,
		protocol.GameSetCounter{
			Counter: protocol.PlayerCounterLife,
			Value:   testIntPointer(17),
		})
	setLife.ID = "set-life"
	host.send(setLife)
	counterSet := host.recvType(protocol.TypeGameCounterSet)
	if counterSet.ID != setLife.ID {
		t.Fatalf("game.counter_set id = %q, want %q", counterSet.ID, setLife.ID)
	}
	lifeHostEvent := host.recvType(protocol.TypeGameSnapshot)
	lifeGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := lifeHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host life projection: %v", err)
	}
	if err := lifeGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest life projection: %v", err)
	}
	if hostGame.Seats[0].Life != 17 || guestGame.Seats[0].Life != 17 ||
		hostGame.Log[len(hostGame.Log)-1].Kind != "counter" ||
		hostGame.Log[len(hostGame.Log)-1].Text != guestGame.Log[len(guestGame.Log)-1].Text {
		t.Fatalf("life projections host=%+v guest=%+v logs=%+v/%+v",
			hostGame.Seats, guestGame.Seats, hostGame.Log, guestGame.Log)
	}

	adjustCounter, _ := protocol.NewEnvelope(protocol.TypeGameSetCounter,
		protocol.GameSetCounter{
			Counter: "counter-1",
			Delta:   testIntPointer(1),
		})
	adjustCounter.ID = "adjust-counter"
	host.send(adjustCounter)
	if counterSet := host.recvType(protocol.TypeGameCounterSet); counterSet.ID != adjustCounter.ID {
		t.Fatalf("adjust game.counter_set id = %q, want %q",
			counterSet.ID, adjustCounter.ID)
	}
	counterHostEvent := host.recvType(protocol.TypeGameSnapshot)
	counterGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := counterHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host counter projection: %v", err)
	}
	if err := counterGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest counter projection: %v", err)
	}
	if hostGame.Seats[0].Counters[0].Value != 1 ||
		guestGame.Seats[0].Counters[0].Value != 1 {
		t.Fatalf("counter projections host=%+v guest=%+v",
			hostGame.Seats[0].Counters, guestGame.Seats[0].Counters)
	}

	renameCounter, _ := protocol.NewEnvelope(protocol.TypeGameSetCounter,
		protocol.GameSetCounter{
			Counter: "counter-1",
			Label:   testStringPointer("Energy"),
		})
	renameCounter.ID = "rename-counter"
	host.send(renameCounter)
	if counterSet := host.recvType(protocol.TypeGameCounterSet); counterSet.ID != renameCounter.ID {
		t.Fatalf("rename game.counter_set id = %q, want %q",
			counterSet.ID, renameCounter.ID)
	}
	counterHostEvent = host.recvType(protocol.TypeGameSnapshot)
	counterGuestEvent = guest.recvType(protocol.TypeGameSnapshot)
	if err := counterHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host renamed counter projection: %v", err)
	}
	if err := counterGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest renamed counter projection: %v", err)
	}
	if hostGame.Seats[0].Counters[0].Label != "Energy" ||
		guestGame.Seats[0].Counters[0].Label != "Energy" ||
		hostGame.Log[len(hostGame.Log)-1].Text !=
			"Alice renamed counter counter-1 to Energy." {
		t.Fatalf("renamed counter projections host=%+v guest=%+v logs=%+v",
			hostGame.Seats[0].Counters, guestGame.Seats[0].Counters, hostGame.Log)
	}

	setCounterCount, _ := protocol.NewEnvelope(protocol.TypeGameSetCounterCount,
		protocol.GameSetCounterCount{Count: 3})
	setCounterCount.ID = "set-counter-count"
	host.send(setCounterCount)
	if countSet := host.recvType(protocol.TypeGameCounterCountSet); countSet.ID != setCounterCount.ID {
		t.Fatalf("game.counter_count_set id = %q, want %q",
			countSet.ID, setCounterCount.ID)
	}
	counterHostEvent = host.recvType(protocol.TypeGameSnapshot)
	counterGuestEvent = guest.recvType(protocol.TypeGameSnapshot)
	if err := counterHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host counter-count projection: %v", err)
	}
	if err := counterGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest counter-count projection: %v", err)
	}
	if hostGame.Seats[0].CounterCount != 3 ||
		guestGame.Seats[0].CounterCount != 3 ||
		hostGame.Seats[1].CounterCount != 0 ||
		guestGame.Seats[1].CounterCount != 0 {
		t.Fatalf("counter-count projections host=%+v guest=%+v",
			hostGame.Seats, guestGame.Seats)
	}

	draw, _ := protocol.NewEnvelope(protocol.TypeGameDraw, protocol.GameDraw{})
	draw.ID = "draw-host"
	host.send(draw)
	drawn := host.recvType(protocol.TypeGameDrawn)
	if drawn.ID != draw.ID {
		t.Fatalf("game.drawn id = %q, want %q", drawn.ID, draw.ID)
	}
	drawnHostEvent := host.recvType(protocol.TypeGameSnapshot)
	drawnGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := drawnHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host draw projection: %v", err)
	}
	if err := drawnGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest draw projection: %v", err)
	}
	if len(hostGame.Seats[0].Hand) != 8 || hostGame.Seats[0].LibraryCount != 2 ||
		len(guestGame.Seats[0].Hand) != 0 || guestGame.Seats[0].HandCount != 8 {
		t.Fatalf("draw projections host=%+v guest=%+v", hostGame.Seats, guestGame.Seats)
	}

	mulligan, _ := protocol.NewEnvelope(protocol.TypeGameMulligan, protocol.GameMulligan{})
	mulligan.ID = "mulligan-host"
	host.send(mulligan)
	mulliganed := host.recvType(protocol.TypeGameMulliganed)
	if mulliganed.ID != mulligan.ID {
		t.Fatalf("game.mulliganed id = %q, want %q", mulliganed.ID, mulligan.ID)
	}
	var mulliganReply protocol.GameMulliganed
	if err := mulliganed.DecodePayload(&mulliganReply); err != nil {
		t.Fatalf("decode game.mulliganed: %v", err)
	}
	if mulliganReply.HandSize != 7 || mulliganReply.MulliganCount != 1 {
		t.Fatalf("game.mulliganed payload = %+v", mulliganReply)
	}
	mulliganHostEvent := host.recvType(protocol.TypeGameSnapshot)
	mulliganGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := mulliganHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host mulligan projection: %v", err)
	}
	if err := mulliganGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest mulligan projection: %v", err)
	}
	if len(hostGame.Seats[0].Hand) != 7 || hostGame.Seats[0].LibraryCount != 3 ||
		len(guestGame.Seats[0].Hand) != 0 ||
		hostGame.Seats[0].MulliganCount != 1 ||
		guestGame.Seats[0].MulliganCount != 1 ||
		hostGame.Log[len(hostGame.Log)-1].Kind != "mulligan" {
		t.Fatalf("mulligan projections host=%+v guest=%+v log=%+v",
			hostGame.Seats, guestGame.Seats, hostGame.Log)
	}

	cardID := hostGame.Seats[0].Hand[0].ID
	move, _ := protocol.NewEnvelope(protocol.TypeGameMoveCard, protocol.GameMoveCard{
		CardID: cardID, FromZone: protocol.ZoneHand, ToZone: protocol.ZoneBattlefield,
		Position: &protocol.CardPosition{X: 0.35, Y: 0.65},
	})
	move.ID = "move-host"
	host.send(move)
	moved := host.recvType(protocol.TypeGameCardMoved)
	if moved.ID != move.ID {
		t.Fatalf("game.card_moved id = %q, want %q", moved.ID, move.ID)
	}
	movedHostEvent := host.recvType(protocol.TypeGameSnapshot)
	movedGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := movedHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host move projection: %v", err)
	}
	if err := movedGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest move projection: %v", err)
	}
	if len(hostGame.Seats[0].Hand) != 6 || len(hostGame.Seats[0].Battlefield) != 1 ||
		hostGame.Seats[0].Battlefield[0].ID != cardID ||
		hostGame.Seats[0].Battlefield[0].Position == nil ||
		len(guestGame.Seats[0].Hand) != 0 || guestGame.Seats[0].HandCount != 6 ||
		len(guestGame.Seats[0].Battlefield) != 1 ||
		guestGame.Seats[0].Battlefield[0].Name != "Lightning Bolt" {
		t.Fatalf("move projections host=%+v guest=%+v", hostGame.Seats, guestGame.Seats)
	}

	setTapped, _ := protocol.NewEnvelope(protocol.TypeGameSetTapped,
		protocol.GameSetTapped{CardID: cardID, Tapped: true})
	setTapped.ID = "tap-host"
	host.send(setTapped)
	tappedAck := host.recvType(protocol.TypeGameTappedSet)
	if tappedAck.ID != setTapped.ID {
		t.Fatalf("game.tapped_set id = %q, want %q", tappedAck.ID, setTapped.ID)
	}
	tappedHostEvent := host.recvType(protocol.TypeGameSnapshot)
	tappedGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := tappedHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host tapped projection: %v", err)
	}
	if err := tappedGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest tapped projection: %v", err)
	}
	if !hostGame.Seats[0].Battlefield[0].Tapped ||
		!guestGame.Seats[0].Battlefield[0].Tapped {
		t.Fatalf("tapped projections host=%+v guest=%+v",
			hostGame.Seats[0].Battlefield, guestGame.Seats[0].Battlefield)
	}

	toStack, _ := protocol.NewEnvelope(protocol.TypeGameMoveCard, protocol.GameMoveCard{
		CardID: cardID, FromZone: protocol.ZoneBattlefield, ToZone: protocol.ZoneStack,
	})
	toStack.ID = "move-stack"
	host.send(toStack)
	host.recvType(protocol.TypeGameCardMoved)
	stackHostEvent := host.recvType(protocol.TypeGameSnapshot)
	stackGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := stackHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host stack projection: %v", err)
	}
	if err := stackGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest stack projection: %v", err)
	}
	if len(hostGame.Stack) != 1 || hostGame.Stack[0].OwnerSeat != 0 ||
		hostGame.Stack[0].Name != "Lightning Bolt" ||
		len(guestGame.Stack) != 1 || guestGame.Stack[0].Name != "Lightning Bolt" {
		t.Fatalf("stack projections host=%+v guest=%+v", hostGame.Stack, guestGame.Stack)
	}

	opponentResolve, _ := protocol.NewEnvelope(protocol.TypeGameMoveCard, protocol.GameMoveCard{
		CardID: cardID, FromZone: protocol.ZoneStack, ToZone: protocol.ZoneGraveyard,
	})
	opponentResolve.ID = "opponent-resolve"
	guest.send(opponentResolve)
	stackErrorEnv := guest.recvType(protocol.TypeError)
	var stackError protocol.ErrorPayload
	if err := stackErrorEnv.DecodePayload(&stackError); err != nil {
		t.Fatalf("decode stack ownership error: %v", err)
	}
	if stackError.Code != protocol.ErrCardNotFound {
		t.Fatalf("opponent stack code = %q, want %q",
			stackError.Code, protocol.ErrCardNotFound)
	}

	reveal, _ := protocol.NewEnvelope(protocol.TypeGameReveal, protocol.GameReveal{
		Zone: protocol.ZoneHand,
	})
	reveal.ID = "reveal-hand"
	host.send(reveal)
	revealed := host.recvType(protocol.TypeGameRevealed)
	if revealed.ID != reveal.ID {
		t.Fatalf("game.revealed id = %q, want %q", revealed.ID, reveal.ID)
	}
	revealHostEvent := host.recvType(protocol.TypeGameSnapshot)
	revealGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	hostGame = protocol.GameSnapshot{}
	guestGame = protocol.GameSnapshot{}
	if err := revealHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host reveal projection: %v", err)
	}
	if err := revealGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest reveal projection: %v", err)
	}
	if len(hostGame.Seats[0].Hand) != 0 || hostGame.Seats[0].HandCount != 0 ||
		len(hostGame.Revealed) != 6 || len(guestGame.Revealed) != 6 ||
		guestGame.Revealed[0].OwnerSeat != 0 ||
		guestGame.Revealed[0].Name == "" {
		t.Fatalf("reveal projections host=%+v guest=%+v",
			hostGame.Revealed, guestGame.Revealed)
	}

	active := host
	inactive := guest
	activeSeat := hostGame.ActiveSeat
	if activeSeat == 1 {
		active = guest
		inactive = host
	}
	setPhase, _ := protocol.NewEnvelope(protocol.TypeGameSetPhase, protocol.GameSetPhase{
		Phase: protocol.GamePhaseCombatDamage,
	})
	setPhase.ID = "set-phase"
	active.send(setPhase)
	phaseSet := active.recvType(protocol.TypeGamePhaseSet)
	if phaseSet.ID != setPhase.ID {
		t.Fatalf("game.phase_set id = %q, want %q", phaseSet.ID, setPhase.ID)
	}
	phaseHostEvent := host.recvType(protocol.TypeGameSnapshot)
	phaseGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := phaseHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host phase projection: %v", err)
	}
	if err := phaseGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest phase projection: %v", err)
	}
	if hostGame.ActiveSeat != activeSeat ||
		hostGame.CurrentPhase != protocol.GamePhaseCombatDamage ||
		guestGame.ActiveSeat != hostGame.ActiveSeat ||
		guestGame.CurrentPhase != hostGame.CurrentPhase {
		t.Fatalf("phase projections host=%+v guest=%+v", hostGame, guestGame)
	}

	invalidPhase, _ := protocol.NewEnvelope(protocol.TypeGameSetPhase, protocol.GameSetPhase{
		Phase: protocol.GamePhaseEnd,
	})
	invalidPhase.ID = "inactive-phase"
	inactive.send(invalidPhase)
	errEnv := inactive.recvType(protocol.TypeError)
	var phaseError protocol.ErrorPayload
	if err := errEnv.DecodePayload(&phaseError); err != nil {
		t.Fatalf("decode inactive phase error: %v", err)
	}
	if phaseError.Code != protocol.ErrNotActivePlayer {
		t.Fatalf("inactive phase code = %q, want %q",
			phaseError.Code, protocol.ErrNotActivePlayer)
	}

	nextTurn, _ := protocol.NewEnvelope(protocol.TypeGameNextTurn, protocol.GameNextTurn{})
	nextTurn.ID = "next-turn"
	active.send(nextTurn)
	advanced := active.recvType(protocol.TypeGameTurnAdvanced)
	if advanced.ID != nextTurn.ID {
		t.Fatalf("game.turn_advanced id = %q, want %q", advanced.ID, nextTurn.ID)
	}
	turnHostEvent := host.recvType(protocol.TypeGameSnapshot)
	turnGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := turnHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host turn projection: %v", err)
	}
	if err := turnGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest turn projection: %v", err)
	}
	if hostGame.ActiveSeat != (activeSeat+1)%2 ||
		hostGame.CurrentPhase != protocol.GamePhaseUntap ||
		guestGame.ActiveSeat != hostGame.ActiveSeat ||
		guestGame.CurrentPhase != hostGame.CurrentPhase {
		t.Fatalf("turn projections host=%+v guest=%+v", hostGame, guestGame)
	}

	guestSeat := 1
	dumpGuestTop, _ := protocol.NewEnvelope(protocol.TypeGameDumpZone,
		protocol.GameDumpZone{
			Zone: protocol.ZoneLibrary, Seat: &guestSeat, TopCount: 1,
		})
	dumpGuestTop.ID = "dump-guest-top"
	host.send(dumpGuestTop)
	pending := host.recvType(protocol.TypeGameZoneDumpPending)
	var pendingDump protocol.GameZoneDumpPending
	if err := pending.DecodePayload(&pendingDump); err != nil {
		t.Fatalf("decode pending guest dump: %v", err)
	}
	requested := guest.recvType(protocol.TypeGameZoneDumpRequested)
	var requestedDump protocol.GameZoneDumpRequested
	if err := requested.DecodePayload(&requestedDump); err != nil {
		t.Fatalf("decode requested guest dump: %v", err)
	}
	if pending.ID != dumpGuestTop.ID ||
		pendingDump.ApprovalID == "" ||
		requestedDump.ApprovalID != pendingDump.ApprovalID ||
		requestedDump.TopCount != 1 {
		t.Fatalf("remote dump approval pending=%+v requested=%+v",
			pendingDump, requestedDump)
	}
	approveTop, _ := protocol.NewEnvelope(protocol.TypeGameRespondZoneDump,
		protocol.GameRespondZoneDump{
			ApprovalID: pendingDump.ApprovalID, Approved: true,
		})
	approveTop.ID = "approve-guest-top"
	guest.send(approveTop)
	responded := guest.recvType(protocol.TypeGameZoneDumpResponded)
	if responded.ID != approveTop.ID {
		t.Fatalf("zone_dump_responded id = %q, want %q",
			responded.ID, approveTop.ID)
	}
	dumpedTopEnvelope := host.recvType(protocol.TypeGameZoneDumped)
	var dumpedTop protocol.GameZoneDumped
	if err := dumpedTopEnvelope.DecodePayload(&dumpedTop); err != nil {
		t.Fatalf("decode approved top dump: %v", err)
	}
	if dumpedTopEnvelope.ID != dumpGuestTop.ID ||
		len(dumpedTop.Cards) != 1 ||
		dumpedTop.ApprovalID != pendingDump.ApprovalID {
		t.Fatalf("approved top dump = env %+v payload %+v",
			dumpedTopEnvelope, dumpedTop)
	}
	topDumpHostSnapshot := host.recvType(protocol.TypeGameSnapshot)
	topDumpGuestSnapshot := guest.recvType(protocol.TypeGameSnapshot)
	if err := topDumpHostSnapshot.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host top-dump projection: %v", err)
	}
	if err := topDumpGuestSnapshot.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest top-dump projection: %v", err)
	}

	guestHandIDs := make(map[string]bool, len(guestGame.Seats[guestSeat].Hand))
	for _, card := range guestGame.Seats[guestSeat].Hand {
		guestHandIDs[card.ID] = true
	}
	outsideApprovedPrefix := ""
	for instance := 1; instance <= 10; instance++ {
		cardID := fmt.Sprintf("s1-c%d", instance)
		if cardID != dumpedTop.Cards[0].ID && !guestHandIDs[cardID] {
			outsideApprovedPrefix = cardID
			break
		}
	}
	if outsideApprovedPrefix == "" {
		t.Fatal("could not identify a guest library card outside approved prefix")
	}
	escalatedSearch, _ := protocol.NewEnvelope(protocol.TypeGameSearchLibrary,
		protocol.GameSearchLibrary{
			CardID:     outsideApprovedPrefix,
			SourceSeat: &guestSeat,
			ApprovalID: dumpedTop.ApprovalID,
			ToZone:     protocol.LibraryDestinationHand,
		})
	escalatedSearch.ID = "reuse-top-approval"
	host.send(escalatedSearch)
	escalationError := host.recvType(protocol.TypeError)
	var escalationPayload protocol.ErrorPayload
	if err := escalationError.DecodePayload(&escalationPayload); err != nil {
		t.Fatalf("decode top approval escalation error: %v", err)
	}
	if escalationPayload.Code != protocol.ErrApprovalExpired {
		t.Fatalf("top approval escalation code = %q, want %q",
			escalationPayload.Code, protocol.ErrApprovalExpired)
	}

	dumpLibrary, _ := protocol.NewEnvelope(protocol.TypeGameDumpZone,
		protocol.GameDumpZone{Zone: "library"})
	dumpLibrary.ID = "dump-library"
	host.send(dumpLibrary)
	dumpedEnv := host.recvType(protocol.TypeGameZoneDumped)
	if dumpedEnv.ID != dumpLibrary.ID {
		t.Fatalf("game.zone_dumped id = %q, want %q", dumpedEnv.ID, dumpLibrary.ID)
	}
	var dumped protocol.GameZoneDumped
	if err := dumpedEnv.DecodePayload(&dumped); err != nil {
		t.Fatalf("decode private library dump: %v", err)
	}
	if dumped.Zone != "library" || len(dumped.Cards) == 0 {
		t.Fatalf("private library dump = %+v", dumped)
	}
	dumpHostEvent := host.recvType(protocol.TypeGameSnapshot)
	dumpGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := dumpHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host library-search projection: %v", err)
	}
	if err := dumpGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest library-search projection: %v", err)
	}
	if len(hostGame.Log) == 0 ||
		hostGame.Log[len(hostGame.Log)-1].Text != "Alice is searching their library." ||
		len(guestGame.Log) == 0 ||
		guestGame.Log[len(guestGame.Log)-1].Text != "Alice is searching their library." {
		t.Fatalf("library-search logs host=%+v guest=%+v", hostGame.Log, guestGame.Log)
	}
	searchedCard := dumped.Cards[0]
	searchLibrary, _ := protocol.NewEnvelope(protocol.TypeGameSearchLibrary,
		protocol.GameSearchLibrary{
			CardID: searchedCard.ID, ToZone: protocol.LibraryDestinationHand,
			Reveal: false,
		})
	searchLibrary.ID = "search-library"
	host.send(searchLibrary)
	searchedEnv := host.recvType(protocol.TypeGameLibrarySearched)
	if searchedEnv.ID != searchLibrary.ID {
		t.Fatalf("game.library_searched id = %q, want %q",
			searchedEnv.ID, searchLibrary.ID)
	}
	searchHostEvent := host.recvType(protocol.TypeGameSnapshot)
	// The private game.zone_dumped response must never have been queued for
	// the opponent; its next event is the role-specific public snapshot.
	searchGuestEvent := guest.recv()
	if searchGuestEvent.Type != protocol.TypeGameSnapshot {
		t.Fatalf("opponent received private dump/event: %+v", searchGuestEvent)
	}
	if err := searchHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host search projection: %v", err)
	}
	if err := searchGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest search projection: %v", err)
	}
	hostLog := hostGame.Log[len(hostGame.Log)-1]
	guestLog := guestGame.Log[len(guestGame.Log)-1]
	if hostLog.Kind != "library_search" || guestLog.Text != hostLog.Text ||
		strings.Contains(hostLog.Text, searchedCard.Name) ||
		len(guestGame.Seats[0].Hand) != 0 ||
		guestGame.Seats[0].HandCount != hostGame.Seats[0].HandCount {
		t.Fatalf("hidden search projections host=%+v guest=%+v",
			hostGame, guestGame)
	}

	say, _ := protocol.NewEnvelope(protocol.TypeGameSay,
		protocol.GameSay{Message: "Good luck!"})
	say.ID = "say-host"
	host.send(say)
	said := host.recvType(protocol.TypeGameSaid)
	if said.ID != say.ID {
		t.Fatalf("game.said id = %q, want %q", said.ID, say.ID)
	}
	var saidPayload protocol.GameSaid
	if err := said.DecodePayload(&saidPayload); err != nil {
		t.Fatalf("decode game.said: %v", err)
	}
	sayHostEvent := host.recvType(protocol.TypeGameSnapshot)
	sayGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := sayHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host chat projection: %v", err)
	}
	if err := sayGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest chat projection: %v", err)
	}
	if saidPayload.LogID <= 0 ||
		hostGame.Log[len(hostGame.Log)-1].Kind != "chat" ||
		hostGame.Log[len(hostGame.Log)-1].Text != "Alice: Good luck!" ||
		guestGame.Log[len(guestGame.Log)-1].Text !=
			hostGame.Log[len(hostGame.Log)-1].Text {
		t.Fatalf("chat projections host=%+v guest=%+v",
			hostGame.Log, guestGame.Log)
	}

	concede, _ := protocol.NewEnvelope(protocol.TypeGameConcede,
		protocol.GameConcede{})
	concede.ID = "concede-host"
	host.send(concede)
	conceded := host.recvType(protocol.TypeGameConceded)
	if conceded.ID != concede.ID {
		t.Fatalf("game.conceded id = %q, want %q", conceded.ID, concede.ID)
	}
	var concededPayload protocol.GameConceded
	if err := conceded.DecodePayload(&concededPayload); err != nil {
		t.Fatalf("decode concede reply: %v", err)
	}
	if concededPayload.ConcededSeat != 0 || concededPayload.WinnerSeat != 1 ||
		concededPayload.MatchFinished || len(concededPayload.Score) != 2 ||
		concededPayload.Score[1] != 1 {
		t.Fatalf("concede reply = %+v", concededPayload)
	}
	concedeHostEvent := host.recvType(protocol.TypeGameSnapshot)
	concedeGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := concedeHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host concede projection: %v", err)
	}
	if err := concedeGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest concede projection: %v", err)
	}
	if hostGame.Result == nil || guestGame.Result == nil ||
		hostGame.Result.WinnerSeat != 1 ||
		guestGame.Result.ConcededSeat != 0 ||
		hostGame.ActiveSeat != -1 || guestGame.ActiveSeat != -1 ||
		hostGame.Score[1] != 1 || guestGame.Score[1] != 1 ||
		hostGame.Log[len(hostGame.Log)-1].Kind != "concede" ||
		guestGame.Log[len(guestGame.Log)-1].Text !=
			hostGame.Log[len(hostGame.Log)-1].Text {
		t.Fatalf("concede projections host=%+v guest=%+v", hostGame, guestGame)
	}

	postGameSay, _ := protocol.NewEnvelope(protocol.TypeGameSay,
		protocol.GameSay{Message: "Thanks for the game."})
	postGameSay.ID = "say-after-finish"
	guest.send(postGameSay)
	if said := guest.recvType(protocol.TypeGameSaid); said.ID != postGameSay.ID {
		t.Fatalf("post-game game.said id = %q, want %q",
			said.ID, postGameSay.ID)
	}
	postChatHostEvent := host.recvType(protocol.TypeGameSnapshot)
	postChatGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := postChatHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host post-game chat projection: %v", err)
	}
	if err := postChatGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest post-game chat projection: %v", err)
	}
	if hostGame.Result == nil || guestGame.Result == nil ||
		hostGame.Log[len(hostGame.Log)-1].Text !=
			"Bob: Thanks for the game." ||
		guestGame.Log[len(guestGame.Log)-1].Text !=
			hostGame.Log[len(hostGame.Log)-1].Text {
		t.Fatalf("post-game chat projections host=%+v guest=%+v",
			hostGame, guestGame)
	}

	drawAfterFinish, _ := protocol.NewEnvelope(protocol.TypeGameDraw,
		protocol.GameDraw{})
	drawAfterFinish.ID = "draw-after-finish"
	guest.send(drawAfterFinish)
	finishedError := guest.recvType(protocol.TypeError)
	var finishedPayload protocol.ErrorPayload
	if err := finishedError.DecodePayload(&finishedPayload); err != nil {
		t.Fatalf("decode finished error: %v", err)
	}
	if finishedError.ID != drawAfterFinish.ID ||
		finishedPayload.Code != protocol.ErrGameFinished {
		t.Fatalf("finished error = env %+v payload %+v",
			finishedError, finishedPayload)
	}
}

func TestSpectatorSnapshotRedactsSelectedDeck(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	spectator := dial(t, srv)
	defer spectator.close()

	host.hello("Alice")
	spectator.hello("Observer")
	_, roomID := host.createRoom("Modern", protocol.FormatModern, 2, true, "")
	host.recvType(protocol.TypeRoomSnapshot)

	join, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{
		RoomID: roomID, AsSpectator: true,
	})
	join.ID = "watch"
	spectator.send(join)
	spectator.recvType(protocol.TypeRoomJoined)
	host.recvType(protocol.TypeRoomSnapshot)
	spectator.recvType(protocol.TypeRoomSnapshot)

	selectDeck, _ := protocol.NewEnvelope(protocol.TypeDeckSelect, modernTestDeck("Secret Burn"))
	selectDeck.ID = "secret-deck"
	host.send(selectDeck)
	host.recvType(protocol.TypeDeckSelected)
	host.recvType(protocol.TypeRoomSnapshot)
	view := spectator.recvType(protocol.TypeRoomSnapshot)
	for _, hidden := range []string{"Secret Burn", "Lightning Bolt", "M11", "149"} {
		if strings.Contains(string(view.Payload), hidden) {
			t.Fatalf("spectator snapshot leaked %q: %s", hidden, view.Payload)
		}
	}
	var snapshot protocol.RoomSnapshot
	if err := view.DecodePayload(&snapshot); err != nil {
		t.Fatalf("decode snapshot: %v", err)
	}
	if !snapshot.Seats[0].DeckSelected {
		t.Fatalf("spectator should see public deckSelected state: %+v", snapshot.Seats[0])
	}

	ready, _ := protocol.NewEnvelope(protocol.TypePlayerReady, protocol.PlayerReady{Ready: true})
	ready.ID = "spectator-ready"
	spectator.send(ready)
	errEnv := spectator.recvType(protocol.TypeError)
	var payload protocol.ErrorPayload
	if err := errEnv.DecodePayload(&payload); err != nil {
		t.Fatalf("decode error: %v", err)
	}
	if payload.Code != protocol.ErrNotPlayer {
		t.Fatalf("spectator ready code = %q, want %q", payload.Code, protocol.ErrNotPlayer)
	}
}
