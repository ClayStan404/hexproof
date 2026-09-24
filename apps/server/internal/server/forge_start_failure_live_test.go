//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
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

func TestLiveForgeStartFailurePrivateDetailsAndRecovery(t *testing.T) {
	root := os.Getenv("HEXPROOF_REAL_FORGE_ROOT")
	if root == "" {
		t.Fatal("HEXPROOF_REAL_FORGE_ROOT is required")
	}
	engine := forge.JavaProcessConfig(os.Getenv("HEXPROOF_FORGE_JAVA"), filepath.Join(root, "forge-harness.jar"), filepath.Join(root, "forge-gui"))
	engine.Args = append([]string{"-Xmx768m", "-XX:+UseSerialGC", "-XX:ActiveProcessorCount=2", "-Djava.awt.headless=true"}, engine.Args...)
	for _, placement := range []string{"dedicated", "shared", "player"} {
		t.Run(placement, func(t *testing.T) {
			config := DefaultConfig()
			config.MessagesPerSecond = 10000
			hosting := protocol.HostingModeServer
			if placement == "player" {
				config.AllowPlayerHosting = true
				hosting = protocol.HostingModePlayer
			} else {
				config.ForgeRuntime = &engine
				if placement == "shared" {
					config.ForgeGamesPerJVM = 2
				}
			}
			srv, handler := newConfiguredTestServer(t, config)
			defer handler.Close()
			ctx, cancel := context.WithTimeout(t.Context(), 90*time.Second)
			defer cancel()
			members := []*liveForgePeer{}
			for i, name := range []string{"Owner", "Opponent", "Observer"} {
				peer := &liveForgePeer{client: dialLiveForge(t, srv), seat: i, name: name}
				if i == 2 {
					peer.seat = -1
				}
				members = append(members, peer)
				defer peer.client.conn.CloseNow()
				peer.command(t, ctx, protocol.TypeSessionHello, "hello", protocol.SessionHello{DisplayName: name, ClientVersion: buildinfo.Version})
				peer.until(t, ctx, protocol.TypeSessionWelcome)
			}
			host, guest, observer := members[0], members[1], members[2]
			host.command(t, ctx, protocol.TypeRoomCreate, "create", protocol.RoomCreate{Name: "Private registration check", Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatCustom, MatchMode: protocol.MatchBO1, RulesMode: protocol.RulesModeForge, HostingMode: hosting, AllowSpectators: true, CardLoadMode: protocol.CardLoadBackground})
			var created protocol.RoomCreated
			_ = host.until(t, ctx, protocol.TypeRoomCreated).DecodePayload(&created)
			if placement == "player" {
				var grant protocol.ForgeHostGrant
				_ = host.until(t, ctx, protocol.TypeForgeHostGrant).DecodePayload(&grant)
				workerCtx, stop := context.WithCancel(ctx)
				done := make(chan error, 1)
				go func() {
					done <- forgehost.Run(workerCtx, forgehost.WorkerConfig{ServerURL: "ws" + strings.TrimPrefix(srv.URL, "http"), RoomID: created.RoomID, Token: grant.Token, GraceSeconds: grant.GraceSeconds}, func(ctx context.Context) (forge.Runtime, error) { return forge.Start(ctx, engine) }, nil, forgehost.WorkerPeer{})
				}()
				defer func() {
					stop()
					select {
					case <-done:
					case <-time.After(5 * time.Second):
						t.Error("test helper did not stop")
					}
				}()
				for {
					var status protocol.ForgeHostStatus
					_ = host.until(t, ctx, protocol.TypeForgeHostStatus).DecodePayload(&status)
					if status.Connected {
						break
					}
				}
			}
			for _, peer := range []*liveForgePeer{guest, observer} {
				peer.command(t, ctx, protocol.TypeRoomJoin, "join", protocol.RoomJoin{RoomID: created.RoomID, AsSpectator: peer.seat < 0, AcceptPlayerHost: placement == "player"})
				peer.until(t, ctx, protocol.TypeRoomJoined)
			}
			valid := protocol.DeckSelect{Name: "Registration verification", Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatCustom, Mainboard: []protocol.DeckCard{{Name: "Forest", Count: 60, SetCode: "M21", CollectorNumber: "272"}}, Sideboard: []protocol.DeckCard{}}
			invalid := valid
			invalid.Sideboard = []protocol.DeckCard{{Name: "Lightning Bolt", Count: 1, SetCode: "M11", CollectorNumber: "not-a-printing"}}
			for index, peer := range members[:2] {
				deck := valid
				if index == 0 {
					deck = invalid
				}
				peer.command(t, ctx, protocol.TypeDeckSelect, "deck", deck)
				peer.until(t, ctx, protocol.TypeDeckSelected)
			}
			host.command(t, ctx, protocol.TypePlayerReady, "first-ready", protocol.PlayerReady{Ready: true})
			host.until(t, ctx, protocol.TypePlayerReadyChanged)
			guest.command(t, ctx, protocol.TypePlayerReady, "last-ready", protocol.PlayerReady{Ready: true})
			for index, peer := range members {
				envelope := peer.until(t, ctx, protocol.TypeError)
				var failure protocol.ErrorPayload
				if envelope.DecodePayload(&failure) != nil || failure.RulesStartFailure == nil || failure.RulesStartFailure.Reason != "deck_rejected" || peer.room.Phase != protocol.RoomPhaseWaiting {
					t.Fatal("native start rejection did not return a categorized waiting-room failure")
				}
				if (index == 1 && envelope.ID != "last-ready") || (index != 1 && envelope.ID != "") {
					t.Fatal("native start rejection correlated to wrong member")
				}
				issues := failure.RulesStartFailure.Issues
				if index == 0 {
					if len(issues) != 1 || issues[0].CardName != "Lightning Bolt" || issues[0].CollectorNumber != "not-a-printing" || issues[0].Section != "sideboard" {
						t.Fatal("owner did not receive exact rejected registration")
					}
				} else if len(issues) != 0 || strings.Contains(string(envelope.Payload), "Lightning Bolt") || strings.Contains(string(envelope.Payload), "not-a-printing") {
					t.Fatal("private registration crossed owner boundary")
				}
			}
			// Missing native printings with verified Oracle-equivalent parents
			// must start in dedicated, shared and creator-managed sessions.
			corrected := valid
			corrected.Mainboard = []protocol.DeckCard{
				{Name: "Forest", Count: 56, SetCode: "M21", CollectorNumber: "272"},
				{Name: "Blood Crypt", Count: 1, SetCode: "RVR", CollectorNumber: "397z"},
				{Name: "Overgrown Tomb", Count: 1, SetCode: "RVR", CollectorNumber: "407z"},
				{Name: "Fyndhorn Elves", Count: 1, SetCode: "PTC", CollectorNumber: "bl244"},
				{Name: "Windswept Heath", Count: 1, SetCode: "WC04", CollectorNumber: "jn328"},
			}
			corrected.Sideboard = append([]protocol.DeckCard(nil), corrected.Mainboard[1:]...)
			host.command(t, ctx, protocol.TypeDeckSelect, "correct-deck", corrected)
			host.until(t, ctx, protocol.TypeDeckSelected)
			for _, peer := range members[:2] {
				peer.command(t, ctx, protocol.TypePlayerReady, "retry", protocol.PlayerReady{Ready: true})
			}
			for _, peer := range members[:2] {
				peer.until(t, ctx, protocol.TypeRulesPrompt)
			}
			host.command(t, ctx, protocol.TypeGameConcede, "concede", protocol.GameConcede{})
			host.until(t, ctx, protocol.TypeGameConceded)
			host.command(t, ctx, protocol.TypeRoomLeave, "leave", struct{}{})
			host.until(t, ctx, protocol.TypeRoomDisbanded)
			t.Log("exact rejected printing visible only to owner; opponent/observer notified; corrected game started and cleanup completed")
		})
	}
}
