// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"fmt"
	"reflect"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestCommanderPiperFallbackOverWebSocket(t *testing.T) {
	config := DefaultConfig()
	config.MessagesPerSecond = 10000
	srv, _ := newConfiguredTestServer(t, config)
	peers := make([]*casualCubePeer, 3)
	for index := range peers {
		client := dial(t, srv)
		defer client.close()
		client.hello(fmt.Sprintf("Piper player %d", index))
		peers[index] = &casualCubePeer{client: client}
	}
	host, guest, viewer := peers[0], peers[1], peers[2]
	command := func(actor *casualCubePeer, kind string, payload any, want string) protocol.Envelope {
		t.Helper()
		env := casualCubeCommand(t, peers, actor, kind, payload, want)
		if len(viewer.pool.FallbackCommanders) != 0 || len(viewer.pool.CommanderColors) != 0 || len(viewer.pool.CommanderInstanceIDs) != 0 {
			t.Fatal("viewer received private fallback selections")
		}
		return env
	}
	cards := make([]protocol.LimitedCardDefinition, 120)
	for index := range cards {
		cards[index] = protocol.LimitedCardDefinition{
			Name: fmt.Sprintf("Cube creature %d", index), SetCode: "TST",
			CollectorNumber: fmt.Sprint(index + 1), TypeLine: "Creature — Test", Weight: 1,
		}
	}
	command(host, protocol.TypeTournamentCreate, protocol.TournamentCreate{
		Name: "Piper Commander Cube", Format: "Commander", EventType: protocol.LimitedEventCommanderCube,
		Coordinator: protocol.LimitedCoordinatorCasual, MatchMode: protocol.MatchBO1, MaxPlayers: 2,
		DraftSettings: &protocol.LimitedDraftSettings{PacksPerPlayer: 3, PacksPerBatch: 1},
		Product: &protocol.LimitedProductDefinition{ID: "piper-cube", Name: "No-legend Cube", ProductType: "cube",
			Sheets: []protocol.LimitedSheetDefinition{{Name: "pool", Cards: cards}}},
	}, protocol.TypeTournamentCreated)
	podID := host.event.TournamentID
	command(guest, protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: podID}, protocol.TypeTournamentEntered)
	command(viewer, protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: podID, AsSpectator: true}, protocol.TypeTournamentEntered)
	for _, player := range peers[:2] {
		command(player, protocol.TypeTournamentCheckIn, protocol.TournamentCheckIn{CheckedIn: true}, protocol.TypeTournamentCheckInSet)
	}
	command(host, protocol.TypeTournamentStart, protocol.EmptyPayload{}, protocol.TypeTournamentStarted)
	if len(host.pool.FallbackCommanders) != 0 || len(guest.pool.FallbackCommanders) != 0 {
		t.Fatal("fallbacks appeared before the draft finished")
	}
	for iteration := 0; host.event.Stage == protocol.LimitedStageDraft && iteration < 100; iteration++ {
		for _, player := range peers[:2] {
			if len(player.pool.CurrentPack) < 2 {
				continue
			}
			command(player, protocol.TypeLimitedPick, protocol.LimitedPick{InstanceIDs: []string{
				player.pool.CurrentPack[0].InstanceID, player.pool.CurrentPack[1].InstanceID}}, protocol.TypeLimitedPicked)
		}
	}
	if host.event.Stage != protocol.LimitedStageDeckBuilding || len(host.pool.Pool) != 60 || len(guest.pool.Pool) != 60 {
		t.Fatal("draft did not preserve the sixty-card physical pools")
	}
	for _, player := range peers[:2] {
		if len(player.pool.FallbackCommanders) != 2 {
			t.Fatal("owner did not receive two Piper candidates")
		}
		request := protocol.LimitedSubmitDeck{Name: "Piper Commander deck",
			BasicLands: []protocol.LimitedBasicLand{{Name: "Island", Count: 29}, {Name: "Forest", Count: 29}},
		}
		for index, candidate := range player.pool.FallbackCommanders {
			request.CommanderInstanceIDs = append(request.CommanderInstanceIDs, candidate.InstanceID)
			request.CommanderColors = append(request.CommanderColors, protocol.LimitedCommanderColor{
				InstanceID: candidate.InstanceID, Color: []string{"U", "G"}[index],
			})
		}
		if player == host {
			bad := request
			bad.CommanderInstanceIDs = []string{guest.pool.FallbackCommanders[0].InstanceID, request.CommanderInstanceIDs[1]}
			command(player, protocol.TypeLimitedSubmitDeck, bad, protocol.TypeError)
			if player.pool.DeckSubmitted {
				t.Fatal("foreign fallback submission changed deck registration")
			}
		}
		ack := command(player, protocol.TypeLimitedSubmitDeck, request, protocol.TypeLimitedDeckSubmitted)
		var submitted protocol.LimitedDeckSubmitted
		if err := ack.DecodePayload(&submitted); err != nil || submitted.MainboardCount != 60 || submitted.SideboardCount != 60 {
			t.Fatalf("fallback deck acknowledgment has wrong counts: %+v (%v)", submitted, err)
		}
		command(player, protocol.TypeTournamentEnter,
			protocol.TournamentEnter{TournamentID: podID, Credential: player.credential}, protocol.TypeTournamentEntered)
		if !reflect.DeepEqual(player.pool.CommanderColors, request.CommanderColors) ||
			!reflect.DeepEqual(player.pool.CommanderInstanceIDs, request.CommanderInstanceIDs) ||
			len(player.pool.MainboardInstanceIDs) != 0 || len(player.pool.Pool) != 60 {
			t.Fatal("authenticated reentry lost or duplicated fallback construction")
		}
	}
	if len(host.event.Pairings) != 1 || !host.event.Pairings[0].AutoEnter || !guest.event.Pairings[0].AutoEnter {
		t.Fatal("Piper decks did not receive their initial Commander table")
	}
	pairID := host.event.Pairings[0].PairingID
	for _, player := range peers[:2] {
		command(player, protocol.TypeTournamentOpenMatch, protocol.TournamentPairingCommand{PairingID: pairID}, protocol.TypeTournamentMatchOpened)
	}
	for _, player := range peers[:2] {
		command(player, protocol.TypePlayerReady, protocol.PlayerReady{Ready: true}, protocol.TypePlayerReadyChanged)
	}
	command(viewer, protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: host.room.RoomID, AsSpectator: true}, protocol.TypeRoomJoined)
	if len(viewer.game.Commanders) != 4 || len(viewer.game.Seats) != 2 {
		t.Fatal("Piper free-play table failed to start")
	}
	for _, seat := range viewer.game.Seats {
		if len(seat.CommandZone) != 2 || len(seat.CommanderTaxes) != 2 || seat.LibraryCount != 51 || seat.HandCount != 7 ||
			len(seat.Hand) != 0 || len(seat.Sideboard) != 0 {
			t.Fatal("Piper command zone or hidden pool projection is incorrect")
		}
		if seat.CommandZone[0].ID == seat.CommandZone[1].ID {
			t.Fatal("both Piper selections became the same physical card")
		}
	}
	for _, identity := range viewer.game.Commanders {
		if identity.Name != "The Prismatic Piper" || (identity.ChosenColor != "U" && identity.ChosenColor != "G") {
			t.Fatalf("public per-Piper identity lost color at room installation: %+v", identity)
		}
	}
}
