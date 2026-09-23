//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"fmt"
	"github.com/coder/websocket"
	"hexproof/server/internal/buildinfo"
	"hexproof/server/internal/forgehost"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

// The worker is deterministic here: real Forge still generates every legal
// decision and validates its answer across the production capability socket.
func TestLiveModelAIPractice(t *testing.T) {
	root := os.Getenv("HEXPROOF_REAL_FORGE_ROOT")
	if root == "" {
		t.Fatal("HEXPROOF_REAL_FORGE_ROOT is required")
	}
	engine := forge.JavaProcessConfig(os.Getenv("HEXPROOF_FORGE_JAVA"), filepath.Join(root, "forge-harness.jar"), filepath.Join(root, "forge-gui"))
	engine.Args = append([]string{"-Xmx768m", "-XX:+UseSerialGC", "-XX:ActiveProcessorCount=2", "-Djava.awt.headless=true"}, engine.Args...)
	for _, hosting := range []string{protocol.HostingModeServer, protocol.HostingModePlayer} {
		t.Run(hosting, func(t *testing.T) {
			cfg := DefaultConfig()
			cfg.MessagesPerSecond = 10000
			if hosting == protocol.HostingModePlayer {
				cfg.AllowPlayerHosting = true
			} else {
				cfg.ForgeRuntime = &engine
			}
			srv, h := newConfiguredTestServer(t, cfg)
			defer h.Close()
			ctx, cancel := context.WithTimeout(t.Context(), 3*time.Minute)
			defer cancel()
			human := &liveForgePeer{client: dialLiveForge(t, srv), seat: 0, name: "Synthetic Human"}
			defer human.client.conn.CloseNow()
			human.command(t, ctx, protocol.TypeSessionHello, "hello", protocol.SessionHello{DisplayName: human.name, ClientVersion: buildinfo.Version})
			welcome := human.until(t, ctx, protocol.TypeSessionWelcome)
			welcome.DecodePayload(&human.welcome)
			if !human.welcome.AIModelsAvailable {
				t.Fatal("models not advertised")
			}
			human.command(t, ctx, protocol.TypeRoomCreate, "create", protocol.RoomCreate{Name: "Model practice", Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatCustom, MatchMode: protocol.MatchBO1, RulesMode: protocol.RulesModeForge, HostingMode: hosting, AISource: protocol.AISourceLocal, AllowSpectators: true, CardLoadMode: protocol.CardLoadBackground})
			created := human.until(t, ctx, protocol.TypeRoomCreated)
			var info protocol.RoomCreated
			created.DecodePayload(&info)
			grantEvent := human.until(t, ctx, protocol.TypeRoomAIWorker)
			var grant protocol.RoomAIWorker
			grantEvent.DecodePayload(&grant)
			if hosting == protocol.HostingModePlayer {
				event := human.until(t, ctx, protocol.TypeForgeHostGrant)
				var hostGrant protocol.ForgeHostGrant
				event.DecodePayload(&hostGrant)
				workerCtx, stop := context.WithCancel(ctx)
				done := make(chan error, 1)
				go func() {
					done <- forgehost.Run(workerCtx, forgehost.WorkerConfig{ServerURL: "ws" + strings.TrimPrefix(srv.URL, "http"), RoomID: info.RoomID, Token: hostGrant.Token, GraceSeconds: hostGrant.GraceSeconds}, func(ctx context.Context) (forge.Runtime, error) { return forge.Start(ctx, engine) }, nil)
				}()
				defer func() {
					stop()
					select {
					case <-done:
					case <-time.After(5 * time.Second):
						t.Error("host worker leaked")
					}
				}()
				for {
					event := human.until(t, ctx, protocol.TypeForgeHostStatus)
					var status protocol.ForgeHostStatus
					event.DecodePayload(&status)
					if status.Connected {
						break
					}
				}
			}
			model, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(srv.URL, "http")+"?ai=1", nil)
			if err != nil {
				t.Fatal(err)
			}
			defer model.CloseNow()
			attach, _ := protocol.NewEnvelope(protocol.TypeAIAttach, protocol.AIAttach{RoomID: info.RoomID, Token: grant.Token})
			raw, _ := attach.Marshal()
			if err = model.Write(ctx, websocket.MessageText, raw); err != nil {
				t.Fatal(err)
			}
			_, raw, err = model.Read(ctx)
			if err != nil {
				t.Fatal(err)
			}
			event, _ := protocol.ParseEnvelope(raw)
			if event.Type != protocol.TypeAIAttached {
				t.Fatal("model attach failed")
			}
			var modelDecisions atomic.Int64
			modelCtx, stopModel := context.WithCancel(ctx)
			modelDone := make(chan error, 1)
			go func() {
				stats := map[string]int{}
				for {
					_, data, err := model.Read(modelCtx)
					if err != nil {
						modelDone <- err
						return
					}
					env, err := protocol.ParseEnvelope(data)
					if err != nil {
						modelDone <- err
						return
					}
					if env.Type == protocol.TypeAICancel {
						continue
					}
					if env.Type != protocol.TypeAIDecision {
						modelDone <- fmt.Errorf("unexpected model event %s", env.Type)
						return
					}
					var decision protocol.AIDecision
					if err = env.DecodePayload(&decision); err != nil {
						modelDone <- err
						return
					}
					peer := &liveForgePeer{seat: 1, name: "Model AI", snapshot: decision.Snapshot, prompt: decision.Prompt}
					snapshotEvent, _ := protocol.NewEnvelope(protocol.TypeRulesSnapshot, decision.Snapshot)
					peer.accept(t, snapshotEvent, protocol.TypeRulesSnapshot)
					answer := liveForgeAnswer(t, peer, stats)
					response, _ := protocol.NewEnvelope(protocol.TypeAIAnswer, protocol.AIAnswer{RequestID: decision.RequestID, Response: answer})
					raw, _ := response.Marshal()
					if err = model.Write(modelCtx, websocket.MessageText, raw); err != nil {
						modelDone <- err
						return
					}
					modelDecisions.Add(1)
				}
			}()
			defer func() {
				stopModel()
				model.CloseNow()
				select {
				case <-modelDone:
				case <-time.After(5 * time.Second):
					t.Error("model worker leaked")
				}
			}()
			deck := protocol.DeckSelect{Name: "Synthetic Burn", Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatCustom, Mainboard: []protocol.DeckCard{{Name: "Mountain", Count: 24, SetCode: "M11", CollectorNumber: "242"}, {Name: "Lightning Bolt", Count: 36, SetCode: "M11", CollectorNumber: "149"}}, Sideboard: []protocol.DeckCard{}}
			human.command(t, ctx, protocol.TypeRoomAIConfigure, "ai-deck", protocol.RoomAIConfigure{Deck: &deck})
			for {
				if human.until(t, ctx, protocol.TypeRoomSnapshot).ID == "ai-deck" {
					break
				}
			}
			human.command(t, ctx, protocol.TypeDeckSelect, "deck", deck)
			human.until(t, ctx, protocol.TypeDeckSelected)
			human.command(t, ctx, protocol.TypePlayerReady, "ready", protocol.PlayerReady{Ready: true})
			human.until(t, ctx, protocol.TypeRulesPrompt)
			stats := map[string]int{}
			for decisions := 0; decisions < 1500 && !human.snapshot.GameOver; decisions++ {
				if !human.prompt.Pending {
					human.until(t, ctx, protocol.TypeRulesPrompt)
					continue
				}
				human.command(t, ctx, protocol.TypeRulesRespond, fmt.Sprintf("human-%d", decisions), liveForgeAnswer(t, human, stats))
				human.until(t, ctx, protocol.TypeRulesResponded)
				human.until(t, ctx, protocol.TypeRulesPrompt)
			}
			if !human.snapshot.GameOver || modelDecisions.Load() < 5 {
				t.Fatalf("model game incomplete: model=%d", modelDecisions.Load())
			}
			t.Logf("natural terminal turn=%d model decisions=%d", human.snapshot.Turn, modelDecisions.Load())
			human.command(t, ctx, protocol.TypeGameReturnToRoom, "return", protocol.EmptyPayload{})
			human.until(t, ctx, protocol.TypeGameReturnedToRoom)
			human.until(t, ctx, protocol.TypeRoomSnapshot)
			if !human.room.Seats[1].Ready {
				t.Fatal("model lost rematch readiness")
			}
			human.command(t, ctx, protocol.TypeRoomLeave, "leave", protocol.EmptyPayload{})
			human.until(t, ctx, protocol.TypeRoomDisbanded)
		})
	}
}
