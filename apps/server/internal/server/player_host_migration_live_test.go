//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/buildinfo"
	"hexproof/server/internal/forgehost"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
)

func TestLivePlayerHostMigration(t *testing.T) {
	root, overlay := os.Getenv("HEXPROOF_REAL_FORGE_ROOT"), os.Getenv("HEXPROOF_TEST_FORGE_OVERLAY")
	if root == "" || overlay == "" {
		t.Fatal("native base and overlay are required")
	}
	engine := forge.JavaOverlayProcessConfig(os.Getenv("HEXPROOF_FORGE_JAVA"), filepath.Join(root, "forge-harness.jar"), filepath.Join(root, "forge-gui"), overlay)
	engine.Args = append([]string{"-Xmx768m", "-XX:+UseSerialGC", "-XX:ActiveProcessorCount=2", "-Djava.awt.headless=true"}, engine.Args...)
	for _, mode := range []string{"planned", "loss", "planned_bo3", "loss_reconnect", "restart_during_replay"} {
		t.Run(mode, func(t *testing.T) {
			config := DefaultConfig()
			config.AllowPlayerHosting, config.MessagesPerSecond = true, 10000
			config.ReconnectWindow = time.Minute
			srv, handler := newConfiguredTestServer(t, config)
			migrated := false
			hook := func(ctx context.Context, roomID string, players []*liveForgePeer, observer *liveForgePeer, decision int) {
				if decision != 50 {
					return
				}
				host, guest := players[0], players[1]
				guest.command(t, ctx, protocol.TypeForgeHostRequest, "volunteer", protocol.ForgeHostRequest{Action: "offer"})
				grantEnvelope := guest.until(t, ctx, protocol.TypeForgeHostGrant)
				var grant protocol.ForgeHostGrant
				if grantEnvelope.DecodePayload(&grant) != nil || !grant.Standby {
					t.Fatal("missing private standby grant")
				}
				workerCtx, stop := context.WithCancel(ctx)
				done := make(chan error, 1)
				startGate := make(chan struct{})
				if mode != "loss_reconnect" && mode != "restart_during_replay" {
					close(startGate)
				}
				go func() {
					done <- forgehost.Run(workerCtx, forgehost.WorkerConfig{
						ServerURL: "ws" + strings.TrimPrefix(srv.URL, "http"), RoomID: roomID, Token: grant.Token, GraceSeconds: grant.GraceSeconds,
					}, func(ctx context.Context) (forge.Runtime, error) {
						select {
						case <-startGate:
						case <-ctx.Done():
							return nil, ctx.Err()
						}
						return forge.Start(ctx, engine)
					}, nil)
				}()
				t.Cleanup(func() {
					stop()
					select {
					case <-done:
					case <-time.After(5 * time.Second):
						t.Error("backup helper leaked")
					}
				})
				for {
					e := guest.until(t, ctx, protocol.TypeForgeHostStatus)
					var status protocol.ForgeHostStatus
					_ = e.DecodePayload(&status)
					if status.BackupConnected {
						break
					}
				}
				guest.command(t, ctx, protocol.TypeForgeHostRequest, "unapproved", protocol.ForgeHostRequest{Action: "migrate"})
				guest.until(t, ctx, protocol.TypeError)
				host.command(t, ctx, protocol.TypeForgeHostRequest, "approve", protocol.ForgeHostRequest{Action: "approve"})
				for {
					e := host.until(t, ctx, protocol.TypeForgeHostStatus)
					var status protocol.ForgeHostStatus
					_ = e.DecodePayload(&status)
					if status.BackupApproved && status.MigrationAvailable {
						break
					}
				}
				actor := liveForgeActor(t, players)
				stale := liveForgeAnswer(t, actor, make(map[string]int))
				before := make([][]byte, 3)
				for i, peer := range append(append([]*liveForgePeer{}, players...), observer) {
					before[i], _ = json.Marshal(peer.snapshot)
				}
				started := time.Now()
				if strings.HasPrefix(mode, "loss") {
					game, _ := handler.forgeGame(roomID)
					game.client.Invalidate() // Revoke the real owned JVM, not a fake process.
				} else {
					host.command(t, ctx, protocol.TypeForgeHostRequest, "transfer", protocol.ForgeHostRequest{Action: "migrate"})
				}
				if mode == "loss_reconnect" || mode == "restart_during_replay" {
					for {
						e := host.until(t, ctx, protocol.TypeForgeHostStatus)
						var status protocol.ForgeHostStatus
						_ = e.DecodePayload(&status)
						if status.Migrating {
							break
						}
					}
				}
				if mode == "restart_during_replay" {
					host.command(t, ctx, protocol.TypeGameRestart, "restart-replay", protocol.GameRestart{})
					host.until(t, ctx, protocol.TypeGameRestarted)
					for _, peer := range players {
						peer.until(t, ctx, protocol.TypeRulesPrompt)
					}
					observer.until(t, ctx, protocol.TypeRulesSnapshot)
					close(startGate)
					status := handler.playerHostingStatus(roomID)
					if status.Migrating || status.HostSeat != 0 || !status.Connected {
						t.Fatal("restart retained stale transfer or replaced original host")
					}
					migrated = true
					return
				}
				if mode == "loss_reconnect" {
					token := guest.welcome.ResumeToken
					_ = guest.client.conn.CloseNow()
					deadline := time.After(5 * time.Second)
					for {
						handler.resumeMu.Lock()
						_, held := handler.resumeHolds[token]
						handler.resumeMu.Unlock()
						if held {
							break
						}
						select {
						case <-deadline:
							t.Fatal("backup player not held for reconnect")
						case <-time.After(time.Millisecond):
						}
					}
					guest.client = dialLiveForge(t, srv)
					guest.command(t, ctx, protocol.TypeSessionHello, "resume-during-replay", protocol.SessionHello{
						DisplayName: guest.name, ClientVersion: buildinfo.Version, Protocol: protocol.ProtocolVersion, ResumeToken: token,
					})
					welcome := guest.until(t, ctx, protocol.TypeSessionWelcome)
					if welcome.DecodePayload(&guest.welcome) != nil || !guest.welcome.Resumed {
						t.Fatal("could not resume paused game")
					}
					for _, peer := range players {
						peer.until(t, ctx, protocol.TypeRulesPrompt)
						if peer.prompt.Pending {
							t.Fatal("paused migration offered active choices")
						}
					}
					observer.until(t, ctx, protocol.TypeRulesSnapshot)
					close(startGate)
				}
				for _, peer := range players {
					peer.until(t, ctx, protocol.TypeRulesPrompt)
				}
				observer.until(t, ctx, protocol.TypeRulesSnapshot)
				for i, peer := range append(append([]*liveForgePeer{}, players...), observer) {
					after, _ := json.Marshal(peer.snapshot)
					if string(before[i]) != string(after) {
						t.Fatalf("seat %d changed state during verified handover", i)
					}
				}
				status := handler.playerHostingStatus(roomID)
				if status.HostSeat != 1 || status.Migrating || !status.Connected {
					t.Fatal("new host did not become authoritative")
				}
				actor.command(t, ctx, protocol.TypeRulesRespond, "old-host-prompt", stale)
				actor.until(t, ctx, protocol.TypeError)
				migrated = true
				t.Logf("%s handover restored 50 real decisions in %s", mode, time.Since(started))
			}
			matchMode := protocol.MatchBO1
			if mode == "planned_bo3" {
				matchMode = protocol.MatchBO3
			}
			runLiveForgeWebSocketStudy(t, srv, handler, matchMode, hook, engine)
			if !migrated {
				t.Fatal("match ended before migration scenario")
			}
		})
	}
}
