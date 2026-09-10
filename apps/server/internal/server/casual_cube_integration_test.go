// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"fmt"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
)

type casualCubePeer struct {
	client      *wsClient
	event       protocol.TournamentSnapshot
	pool        protocol.LimitedSnapshot
	room        protocol.RoomSnapshot
	game        protocol.GameSnapshot
	credential  string
	resumeToken string
}

func (p *casualCubePeer) receive(t *testing.T, id string) protocol.Envelope {
	t.Helper()
	for count := 0; count < 128; count++ {
		env := p.client.recv()
		var target any
		switch env.Type {
		case protocol.TypeTournamentCreated:
			var created protocol.TournamentCreated
			if err := env.DecodePayload(&created); err != nil {
				t.Fatal(err)
			}
			p.credential = created.OrganizerToken
		case protocol.TypeTournamentRegistered:
			var registered protocol.TournamentRegistered
			if err := env.DecodePayload(&registered); err != nil {
				t.Fatal(err)
			}
			p.credential = registered.ParticipantToken
		case protocol.TypeTournamentSnapshot:
			p.event = protocol.TournamentSnapshot{}
			target = &p.event
		case protocol.TypeLimitedSnapshot:
			p.pool = protocol.LimitedSnapshot{}
			target = &p.pool
		case protocol.TypeRoomSnapshot:
			p.room = protocol.RoomSnapshot{}
			target = &p.room
		case protocol.TypeGameSnapshot:
			// Full snapshots omit redacted fields. Decoding into a previously
			// populated struct would retain old private slices after role changes.
			p.game = protocol.GameSnapshot{}
			target = &p.game
		}
		if target != nil {
			if err := env.DecodePayload(target); err != nil {
				t.Fatal(err)
			}
		}
		if env.ID == id {
			return env
		}
		if env.Type == protocol.TypeError {
			t.Fatalf("unexpected async error: %s", env.Payload)
		}
	}
	t.Fatalf("no response for %s", id)
	return protocol.Envelope{}
}

// A ping on the actor's connection is processed after its mutation/fanout.
// Subsequent per-viewer barriers collect all projections without sleeps.
func casualCubeCommand(t *testing.T, peers []*casualCubePeer, actor *casualCubePeer,
	kind string, payload any, want string) protocol.Envelope {
	t.Helper()
	sendTournamentCommand(t, actor.client, kind, "cube-command", payload)
	ack := actor.receive(t, "cube-command")
	if ack.Type != want {
		t.Fatalf("%s: got %s %s, want %s", kind, ack.Type, ack.Payload, want)
	}
	for _, peer := range append([]*casualCubePeer{actor}, peers...) {
		sendTournamentCommand(t, peer.client, protocol.TypeSessionPing, "cube-barrier", protocol.EmptyPayload{})
		peer.receive(t, "cube-barrier")
		if peer.event.ParticipantID == "" && (len(peer.pool.Pool) != 0 || len(peer.pool.CurrentPack) != 0) {
			t.Fatal("organizer/viewer received private Cube identities")
		}
	}
	return ack
}

func TestCasualCubeDraftToFreePlayOverWebSocket(t *testing.T) {
	for _, seats := range []int{2, 4} {
		t.Run(fmt.Sprintf("%d_players", seats), func(t *testing.T) {
			config := DefaultConfig()
			// Snapshot barriers intentionally generate far more traffic than a
			// human draft; transport throttling has separate regression tests.
			config.MessagesPerSecond = 10000
			srv, handler := newConfiguredTestServer(t, config)
			peers := make([]*casualCubePeer, seats+1)
			for i := range peers {
				client := dial(t, srv)
				defer client.close()
				welcomeEnvelope := client.hello(fmt.Sprintf("Cube player %d", i))
				var welcome protocol.SessionWelcome
				_ = welcomeEnvelope.DecodePayload(&welcome)
				peers[i] = &casualCubePeer{client: client, resumeToken: welcome.ResumeToken}
			}
			organizer, players, spectator := peers[0], peers[:seats], peers[seats]
			command := func(actor *casualCubePeer, kind string, payload any, want string) protocol.Envelope {
				return casualCubeCommand(t, peers, actor, kind, payload, want)
			}
			cards := make([]protocol.LimitedCardDefinition, seats*45)
			for i := range cards {
				cards[i] = protocol.LimitedCardDefinition{Name: fmt.Sprintf("Cube card %d", i),
					SetCode: "TST", CollectorNumber: fmt.Sprint(i + 1), TypeLine: "Creature", Weight: 1}
			}
			command(organizer, protocol.TypeTournamentCreate, protocol.TournamentCreate{
				Name: "Free Cube", Format: "Cube", EventType: protocol.LimitedEventCubeDraft,
				Coordinator: protocol.LimitedCoordinatorCasual, MatchMode: protocol.MatchBO1,
				RoundMinutes: 50, MaxPlayers: seats,
				Product: &protocol.LimitedProductDefinition{ID: "free-cube", Name: "Free Cube", ProductType: "cube",
					Sheets: []protocol.LimitedSheetDefinition{{Name: "pool", Cards: cards}}},
			}, protocol.TypeTournamentCreated)
			if len(organizer.event.TournamentID) != 6 || organizer.event.ParticipantID == "" {
				t.Fatal("Cube creator did not receive a room code and seat")
			}
			for _, player := range players[1:] {
				command(player, protocol.TypeRoomJoin,
					protocol.RoomJoin{RoomID: organizer.event.TournamentID}, protocol.TypeTournamentEntered)
				if player.credential == "" {
					t.Fatal("Cube join did not issue a reentry credential")
				}
			}
			for _, player := range players {
				command(player, protocol.TypeTournamentCheckIn,
					protocol.TournamentCheckIn{CheckedIn: true}, protocol.TypeTournamentCheckInSet)
			}
			command(spectator, protocol.TypeRoomJoin,
				protocol.RoomJoin{RoomID: organizer.event.TournamentID, AsSpectator: true, Credential: players[1].credential},
				protocol.TypeTournamentEntered)
			if spectator.event.ParticipantID != "" || spectator.event.Role != "viewer" ||
				len(spectator.event.Participants) != seats {
				t.Fatal("public Cube viewer bound a supplied participant credential or consumed a seat")
			}
			command(organizer, protocol.TypeTournamentStart, protocol.EmptyPayload{}, protocol.TypeTournamentStarted)
			for pick := 0; organizer.event.Stage == protocol.LimitedStageDraft && pick < 100; pick++ {
				picked := false
				for _, player := range players {
					if len(player.pool.CurrentPack) == 0 {
						continue
					}
					picked = true
					command(player, protocol.TypeLimitedPick,
						protocol.LimitedPick{InstanceID: player.pool.CurrentPack[0].InstanceID}, protocol.TypeLimitedPicked)
				}
				if !picked {
					t.Fatalf("draft stalled at pick %d", pick)
				}
			}
			seen := make(map[string]bool)
			for _, player := range players {
				if player.pool.Stage != protocol.LimitedStageDeckBuilding || len(player.pool.Pool) != 45 {
					t.Fatalf("unexpected post-draft state: %+v", player.pool)
				}
				for _, card := range player.pool.Pool {
					if seen[card.InstanceID] {
						t.Fatal("physical card dealt twice")
					}
					seen[card.InstanceID] = true
				}
				ids := make([]string, 23)
				for i := range ids {
					ids[i] = player.pool.Pool[i].InstanceID
				}
				command(player, protocol.TypeLimitedSubmitDeck, protocol.LimitedSubmitDeck{
					Name: "Draft deck", MainboardInstanceIDs: ids,
					BasicLands: []protocol.LimitedBasicLand{{Name: "Forest", Count: 17}},
				}, protocol.TypeLimitedDeckSubmitted)
			}
			if organizer.event.Stage != protocol.LimitedStageCompetition ||
				organizer.event.PlannedRounds != 0 || len(organizer.event.Standings) != 0 {
				t.Fatalf("free play scheduled Swiss competition: %+v", organizer.event)
			}
			pair := protocol.LimitedCreateCasualMatch{PlayerAID: players[0].event.ParticipantID,
				PlayerBID: players[1].event.ParticipantID}
			if seats == 2 {
				if len(organizer.event.Pairings) != 1 || !organizer.event.Pairings[0].AutoEnter ||
					organizer.event.Pairings[0].Status != "open" || !players[1].event.Pairings[0].AutoEnter ||
					spectator.event.Pairings[0].AutoEnter {
					t.Fatal("two-player initial table was not automatically assigned privately")
				}
			} else {
				if len(organizer.event.Pairings) != 0 {
					t.Fatal("larger normal Cube pod automatically chose opponents")
				}
				command(players[0], protocol.TypeLimitedCreateCasualMatch, pair, protocol.TypeLimitedCasualMatchCreated)
				command(players[0], protocol.TypeLimitedCreateCasualMatch, pair, protocol.TypeError)
				command(players[0], protocol.TypeTournamentOpenMatch,
					protocol.TournamentPairingCommand{PairingID: organizer.event.Pairings[0].PairingID}, protocol.TypeError)
				command(players[1], protocol.TypeLimitedCreateCasualMatch,
					protocol.LimitedCreateCasualMatch{PlayerAID: pair.PlayerBID, PlayerBID: pair.PlayerAID},
					protocol.TypeLimitedCasualMatchCreated)
			}
			pairID := organizer.event.Pairings[0].PairingID
			for _, player := range players[:2] {
				command(player, protocol.TypeTournamentOpenMatch,
					protocol.TournamentPairingCommand{PairingID: pairID}, protocol.TypeTournamentMatchOpened)
				// The real client restores its coordinator after the first table
				// snapshot, even when it already has a current Cube binding.
				command(player, protocol.TypeTournamentEnter,
					protocol.TournamentEnter{TournamentID: organizer.event.TournamentID, Credential: player.credential},
					protocol.TypeTournamentEntered)
				if player.event.Pairings[0].AutoEnter {
					t.Fatal("successful entry or reentry retained the automatic-entry request")
				}
			}
			if players[0].room.RoomID != players[1].room.RoomID || players[0].room.RoomID == "" {
				t.Fatal("paired players did not enter the same room")
			}
			for _, player := range players[:2] {
				command(player, protocol.TypePlayerReady, protocol.PlayerReady{Ready: true}, protocol.TypePlayerReadyChanged)
			}
			if len(players[0].game.Seats) != 2 || len(players[0].game.Seats[0].Hand) != 7 ||
				len(players[0].game.Seats[1].Hand) != 0 || len(players[1].game.Seats[1].Hand) != 7 {
				t.Fatalf("locked decks did not start a private game: %+v / %+v", players[0].game, players[1].game)
			}
			players[0].client.close()
			deadline := time.Now().Add(3 * time.Second)
			for {
				handler.resumeMu.Lock()
				_, held := handler.resumeHolds[players[0].resumeToken]
				handler.resumeMu.Unlock()
				if held {
					break
				}
				if time.Now().After(deadline) {
					t.Fatal("Cube table disconnect did not retain its seat")
				}
				time.Sleep(time.Millisecond)
			}
			resumed := dial(t, srv)
			defer resumed.close()
			welcome := resumed.resume("Cube player 0", players[0].resumeToken, 0)
			if !welcome.Resumed || welcome.RoomID != players[0].room.RoomID {
				t.Fatalf("Cube table transport resume failed: %+v", welcome)
			}
			players[0].client = resumed
			command(players[0], protocol.TypeTournamentEnter,
				protocol.TournamentEnter{TournamentID: organizer.event.TournamentID, Credential: players[0].credential},
				protocol.TypeTournamentEntered)
			if players[0].event.ParticipantID != pair.PlayerAID || len(players[0].pool.Pool) != 45 {
				t.Fatal("table resume did not restore the authenticated private Cube pool")
			}
			command(spectator, protocol.TypeRoomJoin,
				protocol.RoomJoin{RoomID: players[0].room.RoomID, AsSpectator: true}, protocol.TypeRoomJoined)
			command(spectator, protocol.TypeTournamentEnter,
				protocol.TournamentEnter{TournamentID: organizer.event.TournamentID},
				protocol.TypeTournamentEntered)
			if spectator.event.ParticipantID != "" || spectator.event.Role != "viewer" ||
				len(spectator.pool.Pool) != 0 || len(spectator.pool.CurrentPack) != 0 {
				t.Fatal("ordinary table spectator received private Cube authority")
			}
			if len(spectator.game.Seats) != 2 || len(spectator.game.Seats[0].Hand) != 0 ||
				len(spectator.game.Seats[1].Hand) != 0 {
				t.Fatal("casual table spectator received a player's private hand")
			}
			command(spectator, protocol.TypeRoomLeave, protocol.EmptyPayload{}, protocol.TypeRoomLeft)
			if len(organizer.event.Pairings) != 1 {
				t.Fatal("spectator departure closed the players' free-play table")
			}
			if seats > 2 {
				watcher := players[2]
				participantID := watcher.event.ParticipantID
				command(watcher, protocol.TypeRoomJoin,
					protocol.RoomJoin{RoomID: players[0].room.RoomID, AsSpectator: true}, protocol.TypeRoomJoined)
				command(watcher, protocol.TypeTournamentEnter,
					protocol.TournamentEnter{TournamentID: organizer.event.TournamentID, Credential: watcher.credential},
					protocol.TypeTournamentEntered)
				if watcher.event.ParticipantID != participantID || len(watcher.pool.Pool) != 45 ||
					len(watcher.game.Seats[0].Hand) != 0 || len(watcher.game.Seats[1].Hand) != 0 {
					t.Fatal("participant spectating lost their own Cube pool or saw opponents' hands")
				}
				command(watcher, protocol.TypeRoomLeave, protocol.EmptyPayload{}, protocol.TypeRoomLeft)
				if watcher.event.ParticipantID != participantID || len(organizer.event.Pairings) != 1 {
					t.Fatal("participant spectator could not return to their Cube seat")
				}
			}
			command(players[0], protocol.TypeGameConcede, protocol.GameConcede{}, protocol.TypeGameConceded)
			command(players[1], protocol.TypeRoomLeave, protocol.EmptyPayload{}, protocol.TypeRoomLeft)
			if len(organizer.event.Pairings) != 0 {
				t.Fatal("closed table still reserves players")
			}
			if seats > 2 {
				pair.PlayerBID = players[2].event.ParticipantID
			}
			command(players[0], protocol.TypeLimitedCreateCasualMatch, pair, protocol.TypeLimitedCasualMatchCreated)
			if len(organizer.event.Pairings) != 1 || organizer.event.Pairings[0].PairingID == pairID ||
				organizer.event.Pairings[0].PlayerBID != pair.PlayerBID {
				t.Fatal("could not arrange the next free-play match")
			}
			opponent := players[1]
			if seats > 2 {
				opponent = players[2]
			}
			command(opponent, protocol.TypeLimitedCreateCasualMatch,
				protocol.LimitedCreateCasualMatch{PlayerAID: pair.PlayerBID, PlayerBID: pair.PlayerAID},
				protocol.TypeLimitedCasualMatchCreated)
			command(players[0], protocol.TypeTournamentOpenMatch,
				protocol.TournamentPairingCommand{PairingID: organizer.event.Pairings[0].PairingID}, protocol.TypeTournamentMatchOpened)
			lastRoomID := players[0].room.RoomID
			command(organizer, protocol.TypeTournamentLeave, protocol.EmptyPayload{}, protocol.TypeTournamentLeft)
			if handler.hub.FindRoom(lastRoomID) != nil {
				t.Fatal("closing the Cube pod retained an active pairing room")
			}
		})
	}
}
