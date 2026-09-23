//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"fmt"
	"hexproof/server/internal/buildinfo"
	"hexproof/server/internal/forgehost"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Complete natural games through the public WebSocket protocol, including a
// spectator, human reconnect, rematch and both supported engine placements.
func TestLiveForgeAIPractice(t *testing.T) {
	root := os.Getenv("HEXPROOF_REAL_FORGE_ROOT")
	if root == "" {
		t.Fatal("HEXPROOF_REAL_FORGE_ROOT is required")
	}
	engine := forge.JavaProcessConfig(os.Getenv("HEXPROOF_FORGE_JAVA"), filepath.Join(root, "forge-harness.jar"), filepath.Join(root, "forge-gui"))
	engine.Args = append([]string{"-Xmx768m", "-XX:+UseSerialGC", "-XX:ActiveProcessorCount=2", "-Djava.awt.headless=true"}, engine.Args...)
	for _, test := range []struct {
		name, difficulty, hosting string
		shared                    int
		advisory                  bool
	}{
		{"easy", "easy", "server", 1, false},
		{"normal_shared_setting", "normal", "server", 2, false},
		{"hard", "hard", "server", 1, false},
		{"player_hosted", "normal", "player", 1, false},
		{"deck_advisory", "normal", "server", 1, true},
	} {
		t.Run(test.name, func(t *testing.T) {
			config := DefaultConfig()
			config.MessagesPerSecond = 10000
			config.ReconnectWindow = time.Minute
			if test.hosting == "player" {
				config.AllowPlayerHosting = true
			} else {
				config.ForgeRuntime = &engine
				config.ForgeGamesPerJVM = test.shared
			}
			srv, handler := newConfiguredTestServer(t, config)
			defer handler.Close()
			ctx, cancel := context.WithTimeout(t.Context(), 3*time.Minute)
			defer cancel()
			human := &liveForgePeer{client: dialLiveForge(t, srv), seat: 0, name: "Synthetic Human"}
			defer func() { _ = human.client.conn.CloseNow() }()
			human.command(t, ctx, protocol.TypeSessionHello, "hello", protocol.SessionHello{DisplayName: human.name, ClientVersion: buildinfo.Version})
			welcome := human.until(t, ctx, protocol.TypeSessionWelcome)
			_ = welcome.DecodePayload(&human.welcome)
			if test.hosting == "server" && !human.welcome.ForgeAIAvailable {
				t.Fatal("capable native runtime not advertised")
			}
			human.command(t, ctx, protocol.TypeRoomCreate, "create", protocol.RoomCreate{Name: "AI practice", Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatCustom, MatchMode: protocol.MatchBO1, RulesMode: protocol.RulesModeForge, HostingMode: test.hosting, AIDifficulty: test.difficulty, AllowSpectators: true, CardLoadMode: protocol.CardLoadBackground})
			created := human.until(t, ctx, protocol.TypeRoomCreated)
			var roomCreated protocol.RoomCreated
			_ = created.DecodePayload(&roomCreated)
			roomID := roomCreated.RoomID
			if test.hosting == "player" {
				grantEnvelope := human.until(t, ctx, protocol.TypeForgeHostGrant)
				var grant protocol.ForgeHostGrant
				_ = grantEnvelope.DecodePayload(&grant)
				workerCtx, stopWorker := context.WithCancel(ctx)
				completed := make(chan error, 1)
				go func() {
					completed <- forgehost.Run(workerCtx, forgehost.WorkerConfig{ServerURL: "ws" + strings.TrimPrefix(srv.URL, "http"), RoomID: roomID, Token: grant.Token, GraceSeconds: grant.GraceSeconds}, func(ctx context.Context) (forge.Runtime, error) { return forge.Start(ctx, engine) }, nil, forgehost.WorkerPeer{})
				}()
				defer func() {
					stopWorker()
					select {
					case <-completed:
					case <-time.After(5 * time.Second):
						t.Error("AI helper leaked")
					}
				}()
				for {
					envelope := human.until(t, ctx, protocol.TypeForgeHostStatus)
					var status protocol.ForgeHostStatus
					_ = envelope.DecodePayload(&status)
					if status.Connected {
						break
					}
				}
			}
			deck := protocol.DeckSelect{Name: "Synthetic Burn", Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatCustom, Mainboard: []protocol.DeckCard{{Name: "Mountain", Count: 24, SetCode: "M11", CollectorNumber: "242"}, {Name: "Lightning Bolt", Count: 36, SetCode: "M11", CollectorNumber: "149"}}, Sideboard: []protocol.DeckCard{}}
			aiDeck := deck
			if test.advisory {
				// Both exact pinned card scripts have AI:RemoveDeck:All. Keep
				// them in the sideboard so the synthetic game's play stays simple.
				aiDeck.Sideboard = []protocol.DeckCard{
					{Name: "Prismatic Ending", Count: 1, SetCode: "MH2", CollectorNumber: "25"},
					{Name: "Wrath of the Skies", Count: 1, SetCode: "MH3", CollectorNumber: "49"},
				}
			}
			human.command(t, ctx, protocol.TypeRoomAIConfigure, "ai-deck", protocol.RoomAIConfigure{Difficulty: test.difficulty, Deck: &aiDeck})
			for {
				if human.until(t, ctx, protocol.TypeRoomSnapshot).ID == "ai-deck" {
					break
				}
			}
			human.command(t, ctx, protocol.TypeDeckSelect, "deck", deck)
			human.until(t, ctx, protocol.TypeDeckSelected)
			human.command(t, ctx, protocol.TypePlayerReady, "ready", protocol.PlayerReady{Ready: true})
			human.until(t, ctx, protocol.TypeRulesPrompt)
			if game, ok := handler.forgeGame(roomID); !ok || !game.nativeAI {
				t.Fatal("native controller not recorded")
			}
			observer := &liveForgePeer{client: dialLiveForge(t, srv), seat: -1, name: "Observer"}
			defer observer.client.conn.CloseNow()
			observer.command(t, ctx, protocol.TypeSessionHello, "hello", protocol.SessionHello{DisplayName: observer.name, ClientVersion: buildinfo.Version})
			observer.until(t, ctx, protocol.TypeSessionWelcome)
			observer.command(t, ctx, protocol.TypeRoomJoin, "watch", protocol.RoomJoin{RoomID: roomID, AsSpectator: true, AcceptPlayerHost: test.hosting == "player"})
			observer.until(t, ctx, protocol.TypeRulesSnapshot)
			stats := map[string]int{}
			advisorySeen := false
			for decisions := 0; decisions < 1000 && !human.snapshot.GameOver; decisions++ {
				if !human.prompt.Pending {
					t.Fatal("native AI left no actionable human decision")
				}
				if test.advisory && human.prompt.Kind == "acknowledge" && human.prompt.Title == "AI deck advisory" {
					if !human.prompt.Supported || len(human.prompt.Options) != 1 || len(human.prompt.Choices) != 0 ||
						human.prompt.Options[0].ResponseID != "$ack" || human.prompt.Options[0].Kind != "acknowledge" ||
						human.prompt.Options[0].Label != "Continue" ||
						!strings.Contains(human.prompt.Detail, "Prismatic Ending") ||
						!strings.Contains(human.prompt.Detail, "Wrath of the Skies") ||
						!strings.Contains(human.prompt.Detail, "You can continue this game.") {
						t.Fatalf("AI deck advisory lacks one actionable acknowledgement: %+v", human.prompt)
					}
					advisorySeen = true
				}
				if decisions == 5 {
					token, promptID := human.welcome.ResumeToken, human.prompt.PromptID
					_ = human.client.conn.CloseNow()
					deadline := time.Now().Add(5 * time.Second)
					for {
						handler.resumeMu.Lock()
						_, held := handler.resumeHolds[token]
						handler.resumeMu.Unlock()
						if held {
							break
						}
						if time.Now().After(deadline) {
							t.Fatal("human disconnect was not held")
						}
						time.Sleep(5 * time.Millisecond)
					}
					human.client = dialLiveForge(t, srv)
					human.command(t, ctx, protocol.TypeSessionHello, "resume", protocol.SessionHello{DisplayName: human.name, ClientVersion: buildinfo.Version, ResumeToken: token})
					welcome := human.until(t, ctx, protocol.TypeSessionWelcome)
					_ = welcome.DecodePayload(&human.welcome)
					human.until(t, ctx, protocol.TypeRulesPrompt)
					observer.until(t, ctx, protocol.TypeRulesSnapshot)
					if !human.welcome.Resumed || human.prompt.PromptID != promptID {
						t.Fatal("AI practice did not reconnect to existing decision")
					}
				}
				answer := liveForgeAnswer(t, human, stats)
				human.command(t, ctx, protocol.TypeRulesRespond, fmt.Sprintf("decision-%d", decisions), answer)
				human.until(t, ctx, protocol.TypeRulesResponded)
				human.until(t, ctx, protocol.TypeRulesPrompt)
				observer.until(t, ctx, protocol.TypeRulesSnapshot)
			}
			if !human.snapshot.GameOver || human.snapshot.WinnerSeat == nil {
				t.Fatal("AI game did not finish naturally")
			}
			if test.advisory && !advisorySeen {
				t.Fatal("unsupported AI cards did not produce a deck advisory")
			}
			t.Logf("natural terminal winner=%d turn=%d stats=%v", *human.snapshot.WinnerSeat, human.snapshot.Turn, stats)
			human.command(t, ctx, protocol.TypeGameReturnToRoom, "return", protocol.EmptyPayload{})
			human.until(t, ctx, protocol.TypeGameReturnedToRoom)
			human.until(t, ctx, protocol.TypeRoomSnapshot)
			if !human.room.Seats[1].Ready || !human.room.Seats[1].DeckSelected || human.room.Seats[0].Ready {
				t.Fatal("AI rematch readiness lost")
			}
			human.command(t, ctx, protocol.TypePlayerReady, "rematch", protocol.PlayerReady{Ready: true})
			human.until(t, ctx, protocol.TypeRulesPrompt)
			human.command(t, ctx, protocol.TypeGameConcede, "concede", protocol.EmptyPayload{})
			human.until(t, ctx, protocol.TypeGameConceded)
			human.command(t, ctx, protocol.TypeRoomLeave, "leave", protocol.EmptyPayload{})
			human.until(t, ctx, protocol.TypeRoomDisbanded)
			observer.until(t, ctx, protocol.TypeRoomDisbanded)
			if handler.hub.FindRoom(roomID) != nil {
				t.Fatal("AI room survived final human leave")
			}
		})
	}
}
