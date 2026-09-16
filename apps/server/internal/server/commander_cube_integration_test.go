// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"fmt"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
)

// All mutations below use real WebSockets, including the complete 3x20 draft.
// Repeated card names with distinct printings exercise physical commander
// selection rather than merely finding the first card with the same name.
func TestCommanderCubeFourPlayerLifecycleOverWebSocket(t *testing.T) {
	config := DefaultConfig()
	config.MessagesPerSecond = 10000
	srv, handler := newConfiguredTestServer(t, config)
	peers := make([]*casualCubePeer, 5)
	for index := range peers {
		client := dial(t, srv)
		defer client.close()
		welcomeEnvelope := client.hello(fmt.Sprintf("Commander player %d", index))
		var welcome protocol.SessionWelcome
		if err := welcomeEnvelope.DecodePayload(&welcome); err != nil {
			t.Fatal(err)
		}
		peers[index] = &casualCubePeer{client: client, resumeToken: welcome.ResumeToken}
	}
	players, host, viewer := peers[:4], peers[0], peers[4]
	command := func(actor *casualCubePeer, kind string, payload any, want string) protocol.Envelope {
		t.Helper()
		env := casualCubeCommand(t, peers, actor, kind, payload, want)
		if len(viewer.pool.CommanderInstanceIDs) != 0 || len(viewer.pool.MainboardInstanceIDs) != 0 || viewer.pool.DeckSubmitted {
			t.Fatal("public viewer received private Commander deck construction")
		}
		for _, participant := range viewer.event.Participants {
			if participant.Deck != nil {
				t.Fatal("running Commander room published a private deck")
			}
		}
		return env
	}
	cards := make([]protocol.LimitedCardDefinition, 240)
	for index := range cards {
		cards[index] = protocol.LimitedCardDefinition{
			Name: fmt.Sprintf("Commander draft legend %d", index%10), SetCode: "TST",
			CollectorNumber: fmt.Sprint(index + 1), TypeLine: "Legendary Creature — Human Wizard",
			Rarity: "rare", Finish: "nonfoil", Weight: 1,
		}
	}
	command(host, protocol.TypeTournamentCreate, protocol.TournamentCreate{
		Name: "Commander Cube integration", Format: "Commander", EventType: protocol.LimitedEventCommanderCube,
		Coordinator: protocol.LimitedCoordinatorCasual, MatchMode: protocol.MatchBO1, MaxPlayers: 4,
		DraftSettings: &protocol.LimitedDraftSettings{PacksPerPlayer: 3, PacksPerBatch: 1},
		Product: &protocol.LimitedProductDefinition{ID: "commander-cube", Name: "Commander Cube", ProductType: "cube",
			Sheets: []protocol.LimitedSheetDefinition{{Name: "pool", Cards: cards}}},
	}, protocol.TypeTournamentCreated)
	podID := host.event.TournamentID
	if len(podID) != 6 || host.event.ParticipantID == "" || host.event.EventType != protocol.LimitedEventCommanderCube {
		t.Fatalf("Commander creator did not receive the correct room and seat: %+v", host.event)
	}
	listedEnvelope := command(viewer, protocol.TypeRoomList, protocol.EmptyPayload{}, protocol.TypeRoomListed)
	var listed protocol.RoomListed
	if err := listedEnvelope.DecodePayload(&listed); err != nil {
		t.Fatal(err)
	}
	if len(listed.Rooms) != 1 || listed.Rooms[0].RoomID != podID || !listed.Rooms[0].PlayerJoinable {
		t.Fatal("Commander Cube is not discoverable as a joinable room")
	}
	for _, player := range players[1:] {
		command(player, protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: podID}, protocol.TypeTournamentEntered)
	}
	command(viewer, protocol.TypeRoomJoin,
		protocol.RoomJoin{RoomID: podID, AsSpectator: true, Credential: players[1].credential}, protocol.TypeTournamentEntered)
	if viewer.event.Role != "viewer" || viewer.event.ParticipantID != "" || len(viewer.event.Participants) != 4 {
		t.Fatal("spectator acquired a Commander draft seat or credential authority")
	}
	for _, player := range players[:3] {
		command(player, protocol.TypeTournamentCheckIn, protocol.TournamentCheckIn{CheckedIn: true}, protocol.TypeTournamentCheckInSet)
	}
	command(host, protocol.TypeTournamentStart, protocol.EmptyPayload{}, protocol.TypeError)
	command(players[3], protocol.TypeTournamentCheckIn, protocol.TournamentCheckIn{CheckedIn: true}, protocol.TypeTournamentCheckInSet)
	command(host, protocol.TypeTournamentStart, protocol.EmptyPayload{}, protocol.TypeTournamentStarted)
	if len(host.pool.CurrentPack) != 20 || host.pool.PicksRequired != 2 || host.pool.MinimumDeckCards != 60 {
		t.Fatalf("incorrect Commander draft profile: %+v", host.pool)
	}
	command(host, protocol.TypeLimitedPick,
		protocol.LimitedPick{InstanceIDs: []string{host.pool.CurrentPack[0].InstanceID}}, protocol.TypeError)
	if len(host.pool.Pool) != 0 || len(host.pool.CurrentPack) != 20 {
		t.Fatal("invalid one-card pick mutated the Commander pack")
	}
	for iteration := 0; host.event.Stage == protocol.LimitedStageDraft && iteration < 100; iteration++ {
		progress := false
		for _, player := range players {
			if len(player.pool.CurrentPack) < 2 {
				continue
			}
			progress = true
			command(player, protocol.TypeLimitedPick, protocol.LimitedPick{InstanceIDs: []string{
				player.pool.CurrentPack[0].InstanceID, player.pool.CurrentPack[1].InstanceID,
			}}, protocol.TypeLimitedPicked)
		}
		if !progress && host.event.Stage == protocol.LimitedStageDraft {
			t.Fatal("four-player Commander draft stalled")
		}
	}
	seen := make(map[string]bool)
	commanders := make([]protocol.LimitedCardView, len(players))
	participantIDs := make([]string, len(players))
	for index, player := range players {
		if player.pool.Stage != protocol.LimitedStageDeckBuilding || len(player.pool.Pool) != 60 {
			t.Fatalf("Commander draft did not deliver 60 physical cards: %+v", player.pool)
		}
		for _, card := range player.pool.Pool {
			if seen[card.InstanceID] {
				t.Fatal("Commander draft dealt a physical card twice")
			}
			seen[card.InstanceID] = true
		}
		ids := make([]string, 35)
		names := make(map[string]bool)
		for position := range ids {
			card := player.pool.Pool[position]
			ids[position] = card.InstanceID
			if names[card.Name] && commanders[index].InstanceID == "" {
				commanders[index] = card
			}
			names[card.Name] = true
		}
		if commanders[index].InstanceID == "" {
			t.Fatal("fixture did not provide a second printing of a selected card name")
		}
		request := protocol.LimitedSubmitDeck{Name: "Commander pool deck", MainboardInstanceIDs: ids,
			CommanderInstanceIDs: []string{commanders[index].InstanceID},
			BasicLands:           []protocol.LimitedBasicLand{{Name: "Forest", Count: 24}},
		}
		command(player, protocol.TypeLimitedSubmitDeck, request, protocol.TypeError)
		if player.pool.DeckSubmitted {
			t.Fatal("59-card Commander draft submission was accepted")
		}
		request.BasicLands[0].Count = 25
		if index == 0 {
			foreign := request
			foreign.CommanderInstanceIDs = []string{players[1].pool.Pool[0].InstanceID}
			command(player, protocol.TypeLimitedSubmitDeck, foreign, protocol.TypeError)
		}
		command(player, protocol.TypeLimitedSubmitDeck, request, protocol.TypeLimitedDeckSubmitted)
		participantIDs[index] = player.event.ParticipantID
	}
	if host.event.Stage != protocol.LimitedStageCompetition || host.event.PlannedRounds != 0 {
		t.Fatal("submitted Commander decks did not enter free play")
	}

	invite := func() string {
		t.Helper()
		command(host, protocol.TypeLimitedCreateCasualMatch,
			protocol.LimitedCreateCasualMatch{Action: "invite", PlayerIDs: participantIDs}, protocol.TypeLimitedCasualMatchCreated)
		if len(host.event.Pairings) != 1 || len(host.event.Pairings[0].PlayerIDs) != 4 {
			t.Fatal("four-player invitation did not reserve all selected participants")
		}
		pairID := host.event.Pairings[0].PairingID
		command(viewer, protocol.TypeLimitedCreateCasualMatch,
			protocol.LimitedCreateCasualMatch{Action: "accept", PairingID: pairID}, protocol.TypeError)
		for _, player := range players[1:] {
			command(host, protocol.TypeTournamentOpenMatch, protocol.TournamentPairingCommand{PairingID: pairID}, protocol.TypeError)
			command(player, protocol.TypeLimitedCreateCasualMatch,
				protocol.LimitedCreateCasualMatch{Action: "accept", PairingID: pairID}, protocol.TypeLimitedCasualMatchCreated)
		}
		return pairID
	}
	if len(host.event.Pairings) != 1 || host.event.Pairings[0].Status != "open" ||
		len(host.event.Pairings[0].AcceptedPlayerIDs) != 4 || viewer.event.Pairings[0].AutoEnter {
		t.Fatal("all submitted Commander decks did not create one accepted initial table")
	}
	pairID := host.event.Pairings[0].PairingID
	for _, player := range players {
		if !player.event.Pairings[0].AutoEnter || !player.pool.AllDecksSubmitted || !player.pool.DeckSubmitted {
			t.Fatal("initial table owner did not receive complete construction state and entry request")
		}
	}
	command(viewer, protocol.TypeTournamentOpenMatch,
		protocol.TournamentPairingCommand{PairingID: pairID}, protocol.TypeError)
	for _, player := range players[:3] {
		command(player, protocol.TypeTournamentOpenMatch, protocol.TournamentPairingCommand{PairingID: pairID}, protocol.TypeTournamentMatchOpened)
		if player.event.Pairings[0].AutoEnter {
			t.Fatal("successful room entry retained the owner's automatic-entry request")
		}
		command(player, protocol.TypePlayerReady, protocol.PlayerReady{Ready: true}, protocol.TypeError)
	}
	if host.room.Phase != protocol.RoomPhaseWaiting || len(host.game.Seats) != 0 {
		t.Fatal("Commander table started with only three of its four invited players")
	}
	command(players[3], protocol.TypeTournamentOpenMatch, protocol.TournamentPairingCommand{PairingID: pairID}, protocol.TypeTournamentMatchOpened)
	for _, player := range players[:3] {
		command(player, protocol.TypePlayerReady, protocol.PlayerReady{Ready: true}, protocol.TypePlayerReadyChanged)
	}
	if host.room.Phase != protocol.RoomPhaseWaiting {
		t.Fatal("Commander table started before the fourth player readied")
	}
	command(players[3], protocol.TypePlayerReady, protocol.PlayerReady{Ready: true}, protocol.TypePlayerReadyChanged)
	roomID := host.room.RoomID
	for index, player := range players {
		assertCommanderTableProjection(t, player, index, commanders)
	}
	command(viewer, protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: roomID, AsSpectator: true}, protocol.TypeRoomJoined)
	assertCommanderTableProjection(t, viewer, -1, commanders)

	// A real transport reconnect must retain the exact table and pool without
	// requiring the player to draft or submit a deck again.
	players[2].client.close()
	until := time.Now().Add(3 * time.Second)
	for {
		handler.resumeMu.Lock()
		_, held := handler.resumeHolds[players[2].resumeToken]
		handler.resumeMu.Unlock()
		if held {
			break
		}
		if time.Now().After(until) {
			t.Fatal("Commander player disconnect did not retain its seat")
		}
		time.Sleep(time.Millisecond)
	}
	resumed := dial(t, srv)
	defer resumed.close()
	welcome := resumed.resume("Commander player 2", players[2].resumeToken, 0)
	if !welcome.Resumed || welcome.RoomID != roomID || welcome.Seat == nil || *welcome.Seat != 2 {
		t.Fatalf("Commander transport resume failed: %+v", welcome)
	}
	players[2].client = resumed
	command(players[2], protocol.TypeTournamentEnter,
		protocol.TournamentEnter{TournamentID: podID, Credential: players[2].credential}, protocol.TypeTournamentEntered)
	if len(players[2].pool.Pool) != 60 || len(players[2].pool.CommanderInstanceIDs) != 1 ||
		players[2].pool.CommanderInstanceIDs[0] != commanders[2].InstanceID {
		t.Fatal("Commander reentry lost the player's private deck or selected commander")
	}
	if players[2].event.Pairings[0].AutoEnter {
		t.Fatal("transport recovery recreated the automatic-entry request")
	}
	assertCommanderTableProjection(t, players[2], 2, commanders)
	commanderID := host.game.Seats[0].CommandZone[0].ID
	command(host, protocol.TypeGameAdjustCommanderTax,
		protocol.GameAdjustCommanderTax{CommanderID: commanderID, Delta: 1}, protocol.TypeGameCommanderTaxAdjusted)
	command(host, protocol.TypeGameSetCommanderDamage,
		protocol.GameSetCommanderDamage{CommanderID: commanderID, TargetSeat: 1, Value: testIntPointer(2)}, protocol.TypeGameCommanderDamageSet)
	if viewer.game.Seats[0].CommanderTaxes[commanderID] != 1 || len(viewer.game.CommanderDamage) != 1 ||
		viewer.game.CommanderDamage[0].Value != 2 || viewer.game.Seats[1].Life != 40 {
		t.Fatal("Commander Cube did not support public per-commander tax and damage controls")
	}

	command(host, protocol.TypeRoomLeave, protocol.EmptyPayload{}, protocol.TypeRoomLeft)
	if handler.hub.FindRoom(roomID) == nil || len(host.event.Pairings) != 1 ||
		players[1].game.Result != nil || !players[1].game.Seats[0].Eliminated {
		t.Fatal("active Commander table host departure destroyed or reset the remaining game")
	}
	if players[1].room.HostSeat != 1 || players[1].room.Seats[0].Occupied {
		t.Fatal("departed host did not release their seat and transfer table ownership")
	}
	command(host, protocol.TypeTournamentOpenMatch, protocol.TournamentPairingCommand{PairingID: pairID}, protocol.TypeTournamentMatchOpened)
	if !host.game.Seats[0].Eliminated || host.room.Seats[0].Occupied {
		t.Fatal("returning departed host resurrected their eliminated seat")
	}
	for _, seat := range host.game.Seats {
		if len(seat.Hand) != 0 || len(seat.Sideboard) != 0 {
			t.Fatal("returning departed player received private cards while spectating")
		}
	}
	command(host, protocol.TypePlayerReady, protocol.PlayerReady{Ready: true}, protocol.TypeError)
	command(players[1], protocol.TypeGameConcede, protocol.GameConcede{}, protocol.TypeGameConceded)
	command(players[2], protocol.TypeGameConcede, protocol.GameConcede{}, protocol.TypeGameConceded)
	if players[3].game.Result == nil || players[3].game.Result.WinnerSeat != 3 || !players[3].game.Result.MatchFinished {
		t.Fatal("Commander table did not finish with the last remaining player")
	}
	command(players[3], protocol.TypeRoomLeave, protocol.EmptyPayload{}, protocol.TypeRoomLeft)
	if handler.hub.FindRoom(roomID) != nil || len(host.event.Pairings) != 0 {
		t.Fatal("finished Commander table remained reserved after return")
	}
	command(host, protocol.TypeLimitedCreateCasualMatch,
		protocol.LimitedCreateCasualMatch{Action: "invite", PlayerIDs: participantIDs}, protocol.TypeLimitedCasualMatchCreated)
	declinedPairID := host.event.Pairings[0].PairingID
	command(players[3], protocol.TypeLimitedCreateCasualMatch,
		protocol.LimitedCreateCasualMatch{Action: "cancel", PairingID: declinedPairID}, protocol.TypeLimitedCasualMatchCreated)
	if len(host.event.Pairings) != 0 {
		t.Fatal("declining a later invitation did not release all four players")
	}
	nextPairID := invite()
	if nextPairID == pairID {
		t.Fatal("next Commander game reused a retired pairing")
	}
	for _, player := range players {
		command(player, protocol.TypeTournamentOpenMatch, protocol.TournamentPairingCommand{PairingID: nextPairID}, protocol.TypeTournamentMatchOpened)
	}
	for _, player := range players {
		command(player, protocol.TypePlayerReady, protocol.PlayerReady{Ready: true}, protocol.TypePlayerReadyChanged)
	}
	if host.room.RoomID == roomID || host.room.Phase != protocol.RoomPhaseStarted {
		t.Fatal("the same four players could not start a fresh Commander game")
	}
	for index, player := range players {
		assertCommanderTableProjection(t, player, index, commanders)
	}
}

func assertCommanderTableProjection(t *testing.T, player *casualCubePeer, ownSeat int, commanders []protocol.LimitedCardView) {
	t.Helper()
	if player.room.Format != protocol.FormatEDH || player.room.DeckFormat != protocol.DeckFormatCommanderLimited ||
		player.room.MatchMode != protocol.MatchBO1 || len(player.game.Seats) != 4 || player.game.Result != nil {
		t.Fatalf("incorrect Commander table mode: %+v / %+v", player.room, player.game)
	}
	for index, seat := range player.game.Seats {
		if seat.Life != 40 || seat.Eliminated || len(seat.CommandZone) != 1 || seat.LibraryCount != 52 || seat.HandCount != 7 {
			t.Fatalf("incorrect Commander initial state for seat %d: %+v", index, seat)
		}
		actual, expected := seat.CommandZone[0], commanders[index]
		if !actual.Commander || actual.Name != expected.Name || actual.SetCode != expected.SetCode ||
			actual.CollectorNumber != expected.CollectorNumber || actual.OwnerSeat != index {
			t.Fatalf("commander printing changed: got %+v, want %+v", actual, expected)
		}
		if index == ownSeat {
			if len(seat.Hand) != 7 || len(seat.Sideboard) != 25 {
				t.Fatalf("owner did not receive their hand and remaining draft pool: %+v", seat)
			}
		} else if len(seat.Hand) != 0 || len(seat.Sideboard) != 0 {
			t.Fatal("Commander projection exposed another player's hand or unused draft pool")
		}
	}
}
