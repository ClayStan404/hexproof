// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"fmt"
	"reflect"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
)

type constructedPeer struct {
	client      *wsClient
	room        protocol.RoomSnapshot
	game        protocol.GameSnapshot
	gameJSON    string
	load        protocol.MatchLoadRequired
	lastSeq     int64
	gameSeq     int64
	resumeToken string
}

func (p *constructedPeer) receive(t *testing.T, id string) protocol.Envelope {
	t.Helper()
	for count := 0; count < 128; count++ {
		env := p.client.recv()
		p.lastSeq = max(p.lastSeq, env.SeqValue())
		var target any
		switch env.Type {
		case protocol.TypeRoomSnapshot:
			if strings.Contains(string(env.Payload), "Private P") ||
				strings.Contains(string(env.Payload), "Private registration") {
				t.Fatal("room snapshot exposed registered deck or card identities")
			}
			p.room = protocol.RoomSnapshot{}
			target = &p.room
		case protocol.TypeGameSnapshot:
			// Reset before decoding: omitted private fields must not survive a
			// new projection, including the first snapshot after reconnecting.
			p.game = protocol.GameSnapshot{}
			p.gameJSON, p.gameSeq = string(env.Payload), env.SeqValue()
			target = &p.game
		case protocol.TypeMatchLoadRequired:
			p.load = protocol.MatchLoadRequired{}
			target = &p.load
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
			t.Fatalf("unexpected asynchronous error: %s", env.Payload)
		}
	}
	t.Fatalf("no response for %s", id)
	return protocol.Envelope{}
}

func constructedBarrier(t *testing.T, peers ...*constructedPeer) {
	t.Helper()
	for _, peer := range peers {
		sendTournamentCommand(t, peer.client, protocol.TypeSessionPing, "constructed-barrier", protocol.EmptyPayload{})
		if env := peer.receive(t, "constructed-barrier"); env.Type != protocol.TypeSessionPong {
			t.Fatalf("barrier returned %s: %s", env.Type, env.Payload)
		}
	}
}

func constructedCommand(t *testing.T, peers []*constructedPeer, actor *constructedPeer,
	kind string, payload any, want string) protocol.Envelope {
	t.Helper()
	sendTournamentCommand(t, actor.client, kind, "constructed-command", payload)
	ack := actor.receive(t, "constructed-command")
	if ack.Type != want {
		t.Fatalf("%s: got %s %s, want %s", kind, ack.Type, ack.Payload, want)
	}
	// The actor barrier ensures its mutation and fanout have finished before
	// other connections are drained. This avoids timing sleeps for snapshots.
	constructedBarrier(t, actor)
	constructedBarrier(t, peers...)
	return ack
}

type constructedFormatCase struct {
	deckFormat string
	tableMode  string
	seats      int
	life       int
	mainCount  int
	commanders int
}

func constructedFixtureDeck(tc constructedFormatCase, seat int) protocol.DeckSelect {
	deck := protocol.DeckSelect{Name: fmt.Sprintf("Private registration %d", seat),
		Format: tc.tableMode, DeckFormat: tc.deckFormat}
	// Synthetic unique printings exercise transport and operational validation.
	// Named-format card-pool legality belongs to the client's catalog tests.
	for i := 0; i < tc.mainCount-tc.commanders; i++ {
		deck.Mainboard = append(deck.Mainboard, protocol.DeckCard{
			Name: fmt.Sprintf("Private P%d card %d", seat, i), Count: 1,
			SetCode: "TST", CollectorNumber: fmt.Sprintf("%d-%d", seat, i), TypeLine: "Creature"})
	}
	if tc.commanders != 0 {
		deck.Commander = fmt.Sprintf("Public commander %d", seat)
		deck.Mainboard = append(deck.Mainboard, protocol.DeckCard{
			Name: deck.Commander, Count: 1, SetCode: "TST",
			CollectorNumber: fmt.Sprintf("%d-C", seat), TypeLine: "Legendary Creature"})
	} else {
		deck.Sideboard = []protocol.DeckCard{{Name: fmt.Sprintf("Private P%d sideboard", seat),
			Count: 1, SetCode: "TST", CollectorNumber: fmt.Sprintf("%d-S", seat)}}
	}
	return deck
}

func assertConstructedProjections(t *testing.T, peers []*constructedPeer, seats int) {
	t.Helper()
	var public protocol.GameSnapshot
	for viewer, peer := range peers {
		if len(peer.game.Seats) != seats {
			t.Fatalf("viewer %d has %d game seats, want %d", viewer, len(peer.game.Seats), seats)
		}
		var projection protocol.GameSnapshot
		if err := json.Unmarshal([]byte(peer.gameJSON), &projection); err != nil {
			t.Fatal(err)
		}
		var raw map[string]json.RawMessage
		if err := json.Unmarshal([]byte(peer.gameJSON), &raw); err != nil {
			t.Fatal(err)
		}
		var rawSeats []map[string]json.RawMessage
		if err := json.Unmarshal(raw["seats"], &rawSeats); err != nil {
			t.Fatal(err)
		}
		for owner := range projection.Seats {
			seat := &projection.Seats[owner]
			if _, exists := rawSeats[owner]["library"]; exists {
				t.Fatalf("viewer %d received a library identity array", viewer)
			}
			if viewer == owner {
				if len(seat.Hand) != seat.HandCount || len(seat.Sideboard) != seat.SideboardCount {
					t.Fatalf("owner %d lost private hand or sideboard identities", owner)
				}
			} else if len(seat.Hand) != 0 || len(seat.Sideboard) != 0 ||
				strings.Contains(peer.gameJSON, fmt.Sprintf("Private P%d ", owner)) {
				t.Fatalf("viewer %d received owner %d's private identities", viewer, owner)
			}
			seat.Hand, seat.Sideboard = nil, nil
			for i := range seat.Battlefield {
				card := &seat.Battlefield[i]
				if card.FaceDown {
					if viewer != owner && (card.Name != "" || card.SetCode != "" ||
						card.CollectorNumber != "" || card.TypeLine != "" || card.FaceName != "") {
						t.Fatalf("viewer %d received face-down identity from seat %d", viewer, owner)
					}
					card.Name, card.SetCode, card.CollectorNumber, card.TypeLine, card.FaceName = "", "", "", "", ""
				}
			}
		}
		if viewer == 0 {
			public = projection
		} else if !reflect.DeepEqual(public, projection) {
			t.Fatalf("viewer %d disagrees with the host's public state", viewer)
		}
	}
}

// This is real loopback WebSocket acceptance, not native input automation or
// card-art downloading. Clients explicitly complete each preload generation.
// Every mutation, including setup and resumption, traverses the public wire.
func TestManualConstructedFormatsOverWebSocket(t *testing.T) {
	// Expected mappings are specified independently of the production mapping
	// helper so an incorrect helper cannot silently redefine the test oracle.
	cases := []constructedFormatCase{
		{"custom", "modern", 2, 20, 60, 0},
		{"standard", "modern", 2, 20, 60, 0},
		{"pioneer", "modern", 2, 20, 60, 0},
		{"modern", "modern", 2, 20, 60, 0},
		{"legacy", "modern", 2, 20, 60, 0},
		{"vintage", "modern", 2, 20, 60, 0},
		{"pauper", "modern", 2, 20, 60, 0},
		{"duel", "duel", 2, 20, 100, 1},
		{"commander", "edh", 4, 40, 100, 1},
	}
	for _, tc := range cases {
		t.Run(tc.deckFormat, func(t *testing.T) {
			config := DefaultConfig()
			config.MessagesPerSecond = 10000 // Deterministic per-viewer snapshot barriers.
			config.ReconnectWindow = 5 * time.Second
			srv, handler := newConfiguredTestServer(t, config)
			peers := make([]*constructedPeer, tc.seats+1)
			for i := range peers {
				client := dial(t, srv)
				defer client.close()
				var welcome protocol.SessionWelcome
				if err := client.hello(fmt.Sprintf("Player %d", i)).DecodePayload(&welcome); err != nil {
					t.Fatal(err)
				}
				peers[i] = &constructedPeer{client: client, resumeToken: welcome.ResumeToken}
			}
			host, players, spectator := peers[0], peers[:tc.seats], peers[tc.seats]
			command := func(actor *constructedPeer, kind string, payload any, want string) protocol.Envelope {
				return constructedCommand(t, peers, actor, kind, payload, want)
			}
			reject := func(actor *constructedPeer, kind string, payload any, code string) {
				t.Helper()
				previous := host.gameJSON
				previousSeq := host.gameSeq
				ack := command(actor, kind, payload, protocol.TypeError)
				var failure protocol.ErrorPayload
				if err := ack.DecodePayload(&failure); err != nil {
					t.Fatal(err)
				}
				if failure.Code != code || host.gameJSON != previous || host.gameSeq != previousSeq {
					t.Fatalf("%s: error %q, want %q, or rejected action changed state", kind, failure.Code, code)
				}
			}
			created := command(host, protocol.TypeRoomCreate, protocol.RoomCreate{
				Name: "Constructed verification", Format: tc.tableMode, DeckFormat: tc.deckFormat,
				MaxSeats: 8, AllowSpectators: true, MatchMode: protocol.MatchBO1,
				CardLoadMode: protocol.CardLoadPreload, RulesMode: protocol.RulesModeManual,
			}, protocol.TypeRoomCreated)
			var roomCreated protocol.RoomCreated
			if err := created.DecodePayload(&roomCreated); err != nil {
				t.Fatal(err)
			}
			roomID := roomCreated.RoomID
			if roomCreated.Settings.MaxSeats != tc.seats || host.room.MaxSeats != tc.seats ||
				host.room.Format != tc.tableMode || host.room.DeckFormat != tc.deckFormat ||
				host.room.RulesMode != protocol.RulesModeManual || host.room.HostSeat != 0 {
				t.Fatalf("incorrect constructed room configuration: %+v", host.room)
			}
			for _, player := range players[1:] {
				command(player, protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: roomID}, protocol.TypeRoomJoined)
			}
			reject(spectator, protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: roomID}, protocol.ErrRoomFull)
			command(spectator, protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: roomID, AsSpectator: true}, protocol.TypeRoomJoined)
			for seat, player := range players {
				deck := constructedFixtureDeck(tc, seat)
				wrong := deck
				wrong.DeckFormat = "commander"
				if tc.deckFormat == "commander" {
					wrong.DeckFormat = "modern"
				}
				reject(player, protocol.TypeDeckSelect, wrong, protocol.ErrInvalidDeck)
				if host.room.Seats[seat].DeckSelected {
					t.Fatal("rejected registration marked the seat selected")
				}
				command(player, protocol.TypeDeckSelect, deck, protocol.TypeDeckSelected)
			}
			for _, player := range players {
				command(player, protocol.TypePlayerReady, protocol.PlayerReady{Ready: true}, protocol.TypePlayerReadyChanged)
			}
			oldLoad := host.load.LoadID
			if oldLoad <= 0 || host.room.Phase != protocol.RoomPhaseLoading || host.game.RoomID != "" {
				t.Fatal("ready players did not enter a fresh preload generation")
			}
			command(host, protocol.TypePlayerReady, protocol.PlayerReady{Ready: false}, protocol.TypePlayerReadyChanged)
			if host.room.Phase != protocol.RoomPhaseWaiting {
				t.Fatal("cancel ready did not leave preload")
			}
			command(host, protocol.TypePlayerReady, protocol.PlayerReady{Ready: true}, protocol.TypePlayerReadyChanged)
			if host.load.LoadID <= oldLoad {
				t.Fatal("restarting preload reused a generation")
			}
			reject(host, protocol.TypeClientLoadComplete, protocol.ClientLoadComplete{LoadID: oldLoad}, protocol.ErrStaleLoad)
			if host.room.Seats[0].Loaded {
				t.Fatal("stale completion marked the host loaded")
			}
			for seat, player := range players {
				if player.load.LoadID != host.load.LoadID {
					t.Fatal("players disagree on the preload generation")
				}
				command(player, protocol.TypeClientLoadComplete, protocol.ClientLoadComplete{LoadID: player.load.LoadID}, protocol.TypeClientLoadCompleted)
				if seat < tc.seats-1 && host.room.Phase != protocol.RoomPhaseLoading {
					t.Fatal("match started before the final player's completion")
				}
			}
			if host.room.Phase != protocol.RoomPhaseStarted {
				t.Fatal("spectator incorrectly gated game start")
			}
			assertConstructedProjections(t, peers, tc.seats)
			for seat, player := range players {
				state := player.game.Seats[seat]
				if state.Life != tc.life || state.HandCount != 7 ||
					state.LibraryCount != tc.mainCount-7-tc.commanders || len(state.CommandZone) != tc.commanders {
					t.Fatalf("seat %d has incorrect opening state: %+v", seat, state)
				}
				if tc.commanders != 0 && (state.CommandZone[0].Name != fmt.Sprintf("Public commander %d", seat) ||
					state.CommandZone[0].CollectorNumber != fmt.Sprintf("%d-C", seat)) {
					t.Fatal("commander designation lost its exact printing")
				}
			}

			life := tc.life - 3
			reject(spectator, protocol.TypeGameSetCounter, protocol.GameSetCounter{Counter: "life", Value: &life}, protocol.ErrNotPlayer)
			inactive := (host.game.ActiveSeat + 1) % tc.seats
			reject(players[inactive], protocol.TypeGameSetPhase, protocol.GameSetPhase{Phase: protocol.GamePhaseFirstMain}, protocol.ErrNotActivePlayer)
			card := host.game.Seats[0].Hand[0]
			moved := command(host, protocol.TypeGameMoveCard, protocol.GameMoveCard{CardID: card.ID,
				FromZone: protocol.ZoneHand, ToZone: protocol.ZoneBattlefield, FaceDown: true,
				Position: &protocol.CardPosition{X: 0.25, Y: 0.5}}, protocol.TypeGameCardMoved)
			if strings.Contains(string(moved.Payload), card.Name) {
				t.Fatal("move acknowledgment exposed a private card identity")
			}
			command(host, protocol.TypeGameSetTapped, protocol.GameSetTapped{CardID: card.ID, Tapped: true}, protocol.TypeGameTappedSet)
			command(host, protocol.TypeGameSetCounter, protocol.GameSetCounter{Counter: "life", Value: &life}, protocol.TypeGameCounterSet)
			command(players[host.game.ActiveSeat], protocol.TypeGameSetPhase,
				protocol.GameSetPhase{Phase: protocol.GamePhaseFirstMain}, protocol.TypeGamePhaseSet)
			previousActive := host.game.ActiveSeat
			command(players[previousActive], protocol.TypeGameNextTurn, protocol.EmptyPayload{}, protocol.TypeGameTurnAdvanced)
			state := host.game.Seats[0]
			if host.game.ActiveSeat == previousActive || host.game.CurrentPhase != protocol.GamePhaseUntap ||
				state.Life != life || state.HandCount != 6 || len(state.Battlefield) != 1 ||
				state.Battlefield[0].Position == nil || !state.Battlefield[0].Tapped ||
				state.Battlefield[0].Name != card.Name || *state.Battlefield[0].Position != (protocol.CardPosition{X: 0.25, Y: 0.5}) {
				t.Fatal("manual turn advancement lost table state or automatically drew/untapped")
			}
			for seat := 1; seat < tc.seats; seat++ {
				if host.game.Seats[seat].HandCount != 7 {
					t.Fatal("manual turn advancement automatically drew for another seat")
				}
			}
			if tc.commanders != 0 {
				commander := host.game.Seats[0].CommandZone[0]
				command(host, protocol.TypeGameCastCommander, protocol.GameCastCommander{CommanderID: commander.ID}, protocol.TypeGameCommanderCast)
				if len(host.game.Stack) != 1 || host.game.Stack[0].ID != commander.ID || host.game.Seats[0].CommanderTaxes[commander.ID] != 1 {
					t.Fatal("explicit commander cast did not move to the stack and increment its cast count")
				}
				command(host, protocol.TypeGameMoveCard, protocol.GameMoveCard{CardID: commander.ID,
					FromZone: protocol.ZoneStack, ToZone: protocol.ZoneCommand}, protocol.TypeGameCardMoved)
				command(host, protocol.TypeGameMoveCard, protocol.GameMoveCard{CardID: commander.ID,
					FromZone: protocol.ZoneCommand, ToZone: protocol.ZoneStack}, protocol.TypeGameCardMoved)
				if host.game.Seats[0].CommanderTaxes[commander.ID] != 1 {
					t.Fatal("ordinary commander movement incorrectly implied another cast")
				}
			}
			assertConstructedProjections(t, peers, tc.seats)

			beforeResume := host.gameJSON
			oldToken := host.resumeToken
			_ = host.client.conn.CloseNow()
			// Observe only the transport disconnect barrier; never seed or alter
			// room state. The resume handshake itself still uses the public wire.
			deadline := time.Now().Add(3 * time.Second)
			for {
				handler.resumeMu.Lock()
				_, held := handler.resumeHolds[oldToken]
				handler.resumeMu.Unlock()
				if held {
					break
				}
				if time.Now().After(deadline) {
					t.Fatal("disconnected host never became resumable")
				}
				time.Sleep(time.Millisecond)
			}
			host.client = dial(t, srv)
			defer host.client.close()
			welcome := host.client.resume("Player 0", oldToken, host.lastSeq)
			if !welcome.Resumed || welcome.RoomID != roomID || welcome.Seat == nil || *welcome.Seat != 0 ||
				!welcome.Host || welcome.Role != protocol.RolePlayer || welcome.ResumeToken == "" || welcome.ResumeToken == oldToken {
				t.Fatalf("host resumption changed membership or did not rotate the token: %+v", welcome)
			}
			host.game, host.gameJSON = protocol.GameSnapshot{}, ""
			constructedBarrier(t, peers...)
			if host.gameJSON != beforeResume {
				t.Fatal("resumed host did not recover the exact private and public game state")
			}
			assertConstructedProjections(t, peers, tc.seats)

			for seat := 1; seat < tc.seats; seat++ {
				command(players[seat], protocol.TypeGameConcede, protocol.EmptyPayload{}, protocol.TypeGameConceded)
				if seat < tc.seats-1 {
					if host.game.Result != nil || !host.game.Seats[seat].Eliminated || host.game.ActiveSeat == seat {
						t.Fatal("partial Commander concession ended the table or left an eliminated seat active")
					}
					reject(players[seat], protocol.TypeGameSetCounter, protocol.GameSetCounter{Counter: "life", Value: &life}, protocol.ErrPlayerEliminated)
				}
			}
			if host.game.Result == nil || !host.game.Result.MatchFinished || host.game.Result.WinnerSeat != 0 ||
				len(host.game.Score) != tc.seats || host.game.Score[0] != 1 {
				t.Fatal("last remaining player did not win the best-of-one match")
			}
			assertConstructedProjections(t, peers, tc.seats)
			command(host, protocol.TypeGameReturnToRoom, protocol.EmptyPayload{}, protocol.TypeGameReturnedToRoom)
			for _, peer := range peers {
				if peer.room.Phase != protocol.RoomPhaseWaiting {
					t.Fatal("return to room did not reach all members")
				}
				for _, seat := range peer.room.Seats {
					if !seat.DeckSelected || seat.Ready || seat.Loaded {
						t.Fatal("return to room lost registration or retained readiness")
					}
				}
			}
			reject(host, protocol.TypeGameNextTurn, protocol.EmptyPayload{}, protocol.ErrGameNotStarted)
		})
	}
}
