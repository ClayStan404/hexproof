// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"fmt"
	"reflect"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestCommanderDraftProfilesAndOptionalCardsOverWebSocket(t *testing.T) {
	for _, profile := range []struct{ seats, packs, batch, cards int }{
		{4, 6, 2, 20}, {4, 5, 2, 20}, {8, 3, 1, 20}, {4, 5, 2, 25}, {8, 3, 1, 40},
	} {
		t.Run(fmt.Sprintf("%d_players_%d_packs_%d_cards", profile.seats, profile.packs, profile.cards), func(t *testing.T) {
			config := DefaultConfig()
			config.MessagesPerSecond = 10000
			srv, _ := newConfiguredTestServer(t, config)
			peers := make([]*casualCubePeer, profile.seats+1)
			for index := range peers {
				client := dial(t, srv)
				// Match the native client's bound; large private pools exceed the
				// Go WebSocket library's default 32 KiB test-client limit.
				client.conn.SetReadLimit(8 << 20)
				defer client.close()
				client.hello(fmt.Sprintf("Profile player %d", index))
				peers[index] = &casualCubePeer{client: client}
			}
			players, host, viewer := peers[:profile.seats], peers[0], peers[profile.seats]
			command := func(actor *casualCubePeer, kind string, payload any, want string) protocol.Envelope {
				t.Helper()
				ack := casualCubeCommand(t, peers, actor, kind, payload, want)
				if len(viewer.pool.CurrentPacks) != 0 || len(viewer.pool.OptionalCards) != 0 || len(viewer.pool.MainboardInstanceIDs) != 0 {
					t.Fatal("observer received private packs or optional construction")
				}
				return ack
			}
			cards := make([]protocol.LimitedCardDefinition, 960)
			for i := range cards {
				cards[i] = protocol.LimitedCardDefinition{Name: fmt.Sprintf("Profile legend %d", i), SetCode: "TST",
					CollectorNumber: fmt.Sprint(i + 1), TypeLine: "Legendary Creature — Human", Weight: 1}
			}
			request := protocol.TournamentCreate{Name: "Commander profiles", Format: protocol.FormatEDH,
				EventType: protocol.LimitedEventCommanderCube, Coordinator: protocol.LimitedCoordinatorCasual,
				MatchMode: protocol.MatchBO1, MaxPlayers: profile.seats,
				Product: &protocol.LimitedProductDefinition{ID: "profiles", Name: "Large Cube", ProductType: "cube",
					Sheets: []protocol.LimitedSheetDefinition{{Name: "stock", Cards: cards}}}}
			if profile.packs == 5 || profile.cards != 20 {
				request.DraftSettings = &protocol.LimitedDraftSettings{PacksPerPlayer: profile.packs,
					PacksPerBatch: profile.batch, CardsPerPack: profile.cards}
			}
			command(host, protocol.TypeTournamentCreate, request, protocol.TypeTournamentCreated)
			if host.event.DraftSettings == nil || host.event.DraftSettings.PacksPerPlayer != profile.packs || host.event.DraftSettings.PacksPerBatch != profile.batch || host.event.DraftSettings.CardsPerPack != profile.cards {
				t.Fatal("creation did not publish the locked draft settings")
			}
			podID := host.event.TournamentID
			for _, player := range players[1:] {
				command(player, protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: podID}, protocol.TypeTournamentEntered)
			}
			command(viewer, protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: podID, AsSpectator: true}, protocol.TypeTournamentEntered)
			for _, player := range players {
				command(player, protocol.TypeTournamentCheckIn, protocol.TournamentCheckIn{CheckedIn: true}, protocol.TypeTournamentCheckInSet)
			}
			command(host, protocol.TypeTournamentStart, protocol.EmptyPayload{}, protocol.TypeTournamentStarted)
			if len(host.pool.CurrentPacks) != profile.batch || host.pool.PicksRequired != 2*profile.batch {
				t.Fatal("wrong opening batch")
			}
			for _, part := range host.pool.CurrentPacks {
				if len(part.Cards) != profile.cards {
					t.Fatal("opening pack ignored the configured card count")
				}
			}
			if profile.batch == 2 {
				part := host.pool.CurrentPacks[0]
				bad := []string{}
				for _, card := range part.Cards[:4] {
					bad = append(bad, card.InstanceID)
				}
				command(host, protocol.TypeLimitedPick, protocol.LimitedPick{InstanceIDs: bad}, protocol.TypeError)
				if len(host.pool.Pool) != 0 {
					t.Fatal("cross-pack quota violation changed picks")
				}
			}
			// Reenter over a new transport before choosing: both current packs and
			// their exact quotas must survive, including a companion pack.
			guest := players[1]
			before := guest.pool
			guest.client.close()
			guest.client = dial(t, srv)
			guest.client.conn.SetReadLimit(8 << 20)
			defer guest.client.close()
			guest.client.hello("Profile player 1")
			command(guest, protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: podID, Credential: guest.credential}, protocol.TypeTournamentEntered)
			if !reflect.DeepEqual(before.CurrentPacks, guest.pool.CurrentPacks) || !reflect.DeepEqual(before.Pool, guest.pool.Pool) || !reflect.DeepEqual(host.event.DraftSettings, guest.event.DraftSettings) {
				t.Fatal("reentry lost the private batch")
			}
			for step := 0; host.pool.Stage == protocol.LimitedStageDraft && step < 100; step++ {
				for _, player := range players {
					if player.pool.Stage != protocol.LimitedStageDraft || len(player.pool.CurrentPack) == 0 {
						continue
					}
					ids := []string{}
					for _, part := range player.pool.CurrentPacks {
						for _, card := range part.Cards[:part.PicksRequired] {
							ids = append(ids, card.InstanceID)
						}
					}
					command(player, protocol.TypeLimitedPick, protocol.LimitedPick{InstanceIDs: ids}, protocol.TypeLimitedPicked)
				}
			}
			seen := map[string]bool{}
			for index, player := range players {
				if player.pool.Stage != protocol.LimitedStageDeckBuilding || len(player.pool.Pool) != profile.packs*profile.cards || len(player.pool.OptionalCards) != 3 {
					t.Fatal("incorrect construction pool")
				}
				for _, card := range player.pool.Pool {
					if seen[card.InstanceID] {
						t.Fatal("draft duplicated physical stock")
					}
					seen[card.InstanceID] = true
				}
				deck := protocol.LimitedSubmitDeck{Name: "Selected staples", CommanderInstanceIDs: []string{player.pool.Pool[0].InstanceID},
					BasicLands: []protocol.LimitedBasicLand{{Name: "Island", Count: 25}}}
				for _, card := range player.pool.Pool[:35] {
					deck.MainboardInstanceIDs = append(deck.MainboardInstanceIDs, card.InstanceID)
				}
				if index == 0 {
					for _, card := range player.pool.OptionalCards {
						deck.MainboardInstanceIDs = append(deck.MainboardInstanceIDs, card.InstanceID)
					}
					deck.BasicLands[0].Count = 22
				}
				command(player, protocol.TypeLimitedSubmitDeck, deck, protocol.TypeLimitedDeckSubmitted)
				if !reflect.DeepEqual(player.pool.MainboardInstanceIDs, deck.MainboardInstanceIDs) {
					t.Fatal("submission lost selected staples")
				}
			}
			wantTables := (profile.seats + 3) / 4
			if len(host.event.Pairings) != wantTables {
				t.Fatal("initial table count is incorrect")
			}
			for _, player := range players {
				pairID := ""
				for _, pair := range player.event.Pairings {
					if pair.AutoEnter {
						if pairID != "" {
							t.Fatal("duplicate initial assignment")
						}
						pairID = pair.PairingID
					}
				}
				if pairID == "" {
					t.Fatal("missing automatic-entry assignment")
				}
				command(player, protocol.TypeTournamentOpenMatch, protocol.TournamentPairingCommand{PairingID: pairID}, protocol.TypeTournamentMatchOpened)
			}
			for _, player := range players {
				command(player, protocol.TypePlayerReady, protocol.PlayerReady{Ready: true}, protocol.TypePlayerReadyChanged)
			}
			rooms := map[string]int{}
			for _, player := range players {
				if len(player.game.Seats) != 4 {
					t.Fatal("Commander game does not contain its four assigned players")
				}
				rooms[player.room.RoomID]++
			}
			if len(rooms) != wantTables {
				t.Fatal("multiple groups entered the same table")
			}
			for _, count := range rooms {
				if count != 4 {
					t.Fatal("initial table lost a player")
				}
			}
		})
	}
}
