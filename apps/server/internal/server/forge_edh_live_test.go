//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"fmt"
	"testing"
	"time"

	"hexproof/server/internal/buildinfo"
	"hexproof/server/internal/protocol"
)

// Exercise public admission, participant-only engine seats, private views,
// multiplayer priority and non-terminal elimination with the packaged engine.
func TestLiveForgeEDHSeats(t *testing.T) {
	for _, count := range []int{2, 3, 4} {
		t.Run(fmt.Sprintf("players-%d", count), func(t *testing.T) {
			srv, _ := newLiveForgeWebSocketServer(t)
			ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
			defer cancel()
			players := make([]*liveForgePeer, count)
			for seat := range players {
				peer := &liveForgePeer{client: dialLiveForge(t, srv), seat: seat, name: fmt.Sprintf("Commander %d", seat)}
				players[seat] = peer
				defer peer.client.conn.CloseNow()
				peer.command(t, ctx, protocol.TypeSessionHello, "hello", protocol.SessionHello{
					DisplayName: peer.name, ClientVersion: buildinfo.Version, Protocol: protocol.ProtocolVersion,
				})
				peer.until(t, ctx, protocol.TypeSessionWelcome)
			}
			host := players[0]
			host.command(t, ctx, protocol.TypeRoomCreate, "create", protocol.RoomCreate{
				Name: "Commander pod", Format: protocol.FormatEDH, DeckFormat: protocol.DeckFormatCommander,
				RulesMode: protocol.RulesModeForge, MaxSeats: 4, MatchMode: protocol.MatchBO1,
				AllowSpectators: true, CardLoadMode: protocol.CardLoadBackground,
			})
			var created protocol.RoomCreated
			if err := host.until(t, ctx, protocol.TypeRoomCreated).DecodePayload(&created); err != nil {
				t.Fatal(err)
			}
			for _, peer := range players[1:] {
				peer.command(t, ctx, protocol.TypeRoomJoin, "join", protocol.RoomJoin{RoomID: created.RoomID})
				peer.until(t, ctx, protocol.TypeRoomJoined)
			}
			deck := protocol.DeckSelect{Name: "Commander fixture", Format: protocol.FormatEDH,
				DeckFormat: protocol.DeckFormatCommander, Commanders: []string{"Isamaru, Hound of Konda"},
				Mainboard: []protocol.DeckCard{{Name: "Plains", Count: 99, SetCode: "C15", CollectorNumber: "323"}, {Name: "Isamaru, Hound of Konda", Count: 1, SetCode: "CHK", CollectorNumber: "19"}},
				Sideboard: []protocol.DeckCard{},
			}
			for _, peer := range players {
				peer.command(t, ctx, protocol.TypeDeckSelect, "deck", deck)
				peer.until(t, ctx, protocol.TypeDeckSelected)
				peer.command(t, ctx, protocol.TypePlayerReady, "ready", protocol.PlayerReady{Ready: true})
				peer.until(t, ctx, protocol.TypePlayerReadyChanged)
			}
			for _, peer := range players {
				peer.until(t, ctx, protocol.TypeRulesPrompt)
			}
			if len(host.snapshot.Players) != count {
				t.Fatalf("engine seats = %d, want %d", len(host.snapshot.Players), count)
			}
			for _, player := range host.snapshot.Players {
				if player.Life != 40 || len(player.Commanders) != 1 {
					t.Fatalf("Commander initialization: %+v", player)
				}
			}
			observer := &liveForgePeer{client: dialLiveForge(t, srv), seat: -1, name: "Observer"}
			defer observer.client.conn.CloseNow()
			observer.command(t, ctx, protocol.TypeSessionHello, "hello", protocol.SessionHello{
				DisplayName: observer.name, ClientVersion: buildinfo.Version, Protocol: protocol.ProtocolVersion,
			})
			observer.until(t, ctx, protocol.TypeSessionWelcome)
			observer.command(t, ctx, protocol.TypeRoomJoin, "watch", protocol.RoomJoin{RoomID: created.RoomID, AsSpectator: true})
			observer.until(t, ctx, protocol.TypeRulesSnapshot)
			visited := make(map[int]bool)
			stats := make(map[string]int)
			for decision := 0; decision < 250 && len(visited) < count; decision++ {
				actor := liveForgeActor(t, players)
				if actor.prompt.Kind == "chooseAction" {
					visited[actor.seat] = true
				}
				answer := liveForgeAnswer(t, actor, stats)
				actor.command(t, ctx, protocol.TypeRulesRespond, fmt.Sprintf("decision-%d", decision), answer)
				actor.until(t, ctx, protocol.TypeRulesResponded)
				for _, peer := range players {
					peer.until(t, ctx, protocol.TypeRulesPrompt)
				}
				observer.until(t, ctx, protocol.TypeRulesSnapshot)
			}
			if len(visited) != count {
				t.Fatalf("priority did not reach every seat: %v", visited)
			}
			for seat := count - 1; seat > 0; seat-- {
				players[seat].command(t, ctx, protocol.TypeGameConcede, "concede", protocol.GameConcede{})
				players[seat].until(t, ctx, protocol.TypeGameConceded)
				for _, peer := range players {
					peer.until(t, ctx, protocol.TypeRulesPrompt)
				}
				observer.until(t, ctx, protocol.TypeRulesSnapshot)
				if host.snapshot.GameOver != (seat == 1) {
					t.Fatalf("terminal state after seat %d conceded: %v", seat, host.snapshot.GameOver)
				}
				if seat > 1 {
					if len(host.snapshot.Players) != count {
						t.Fatal("elimination changed public seat identities")
					}
					actor := liveForgeActor(t, players)
					if actor.seat >= seat {
						t.Fatalf("eliminated seat owns priority: %d", actor.seat)
					}
					actor.command(t, ctx, protocol.TypeRulesRespond, "continue", liveForgeAnswer(t, actor, stats))
					actor.until(t, ctx, protocol.TypeRulesResponded)
					for _, peer := range players {
						peer.until(t, ctx, protocol.TypeRulesPrompt)
					}
					observer.until(t, ctx, protocol.TypeRulesSnapshot)
				}
			}
			t.Logf("%d-player Commander: 40 life, commanders, private hands, all-seat priority, spectator and elimination passed", count)
		})
	}
}
