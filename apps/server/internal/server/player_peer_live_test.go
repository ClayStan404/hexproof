//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"hexproof/server/internal/forgehost"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
)

// This exercises the native executor, private commit, redaction, journal and
// fallback over real authenticated hub sockets. Peerlink separately exercises
// ICE/DTLS/SCTP; the native GUI joins both paths with the shipped helper.
func TestLivePlayerPeerDecisionsAndFallback(t *testing.T) {
	root, overlay := os.Getenv("HEXPROOF_REAL_FORGE_ROOT"), os.Getenv("HEXPROOF_TEST_FORGE_OVERLAY")
	if root == "" || overlay == "" {
		t.Fatal("native base and overlay are required")
	}
	engine := forge.JavaOverlayProcessConfig(os.Getenv("HEXPROOF_FORGE_JAVA"), filepath.Join(root, "forge-harness.jar"), filepath.Join(root, "forge-gui"), overlay)
	engine.Args = append([]string{"-Xmx768m", "-XX:+UseSerialGC", "-XX:ActiveProcessorCount=2", "-Djava.awt.headless=true"}, engine.Args...)
	config := DefaultConfig()
	config.AllowPlayerHosting = true
	config.MessagesPerSecond = 10000
	config.ReconnectWindow = time.Minute
	srv, handler := newConfiguredTestServer(t, config)
	actions := make(chan forgehost.PeerAction, 1)
	replies := make(chan forgehost.PeerReply, 8)
	var binding string
	completed, fallbacks := 0, 0
	hook := func(ctx context.Context, roomID string, players []*liveForgePeer, observer *liveForgePeer, decision int) {
		if decision == 20 {
			observer.command(t, ctx, protocol.TypeForgePeerRequest, "spectator-peer", protocol.ForgePeerRequest{Enabled: true})
			observer.until(t, ctx, protocol.TypeError)
			for _, player := range players {
				player.command(t, ctx, protocol.TypeForgePeerRequest, "enable-peer", protocol.ForgePeerRequest{Enabled: true})
			}
			for _, player := range players {
				var grant protocol.ForgePeerGrant
				env := player.until(t, ctx, protocol.TypeForgePeerGrant)
				if env.DecodePayload(&grant) != nil || grant.BindingID == "" || grant.HostSeat != 0 {
					t.Fatal("missing room-bound peer grant")
				}
				if binding != "" && binding != grant.BindingID {
					t.Fatal("peers have different binding")
				}
				binding = grant.BindingID
			}
		}
		if binding == "" || completed >= 12 || !players[1].prompt.Pending || players[1].snapshot.GameOver {
			return
		}
		guest := players[1]
		request := liveForgeAnswer(t, guest, make(map[string]int))
		request.PeerBinding = binding
		op := fmt.Sprintf("peer-decision-%d", completed)
		action := forgehost.PeerAction{BindingID: binding, OperationID: op, Request: request}
		game, _ := handler.forgeGame(roomID)
		runtime := game.client.(*forgehost.Runtime)
		checkpoint, err := runtime.Checkpoint()
		if err != nil {
			t.Fatal(err)
		}
		var reply forgehost.PeerReply
		for attempts := 0; attempts < 30; attempts++ {
			actions <- action
			select {
			case reply = <-replies:
			case <-time.After(5 * time.Second):
				t.Fatal("peer confirmation timed out")
			}
			if reply.Error == "" {
				break
			}
			time.Sleep(10 * time.Millisecond)
		}
		if reply.Error != "" || len(reply.Envelopes) != 3 {
			t.Fatal("peer decision rejected", reply.Error)
		}
		after, err := runtime.Checkpoint()
		if err != nil || len(after.Actions) != len(checkpoint.Actions)+1 {
			t.Fatal("direct mutation was not journaled exactly once", err)
		}
		if completed%2 == 0 {
			// Drop the direct reply, then retry the identical operation over WS.
			guest.command(t, ctx, protocol.TypeRulesRespond, op, request)
			guest.until(t, ctx, protocol.TypeRulesResponded)
			fallbacks++
		} else {
			for _, env := range reply.Envelopes {
				guest.accept(t, env, env.Type)
			}
		}
		players[0].until(t, ctx, protocol.TypeRulesPrompt)
		observer.until(t, ctx, protocol.TypeRulesSnapshot)
		// Lost confirmations can cause the helper to resend a commit. Neither
		// transport is allowed to submit the action to the JVM twice.
		actions <- action
		select {
		case again := <-replies:
			if again.Error != "" {
				t.Fatal("duplicate confirmation failed")
			}
		case <-time.After(5 * time.Second):
			t.Fatal("duplicate confirmation timed out")
		}
		repeated, err := runtime.Checkpoint()
		if err != nil || len(repeated.Actions) != len(after.Actions) {
			t.Fatal("duplicate mutated native game")
		}
		completed++
	}
	runLiveForgePeerStudy(t, srv, handler, protocol.MatchBO1, hook, forgehost.WorkerPeer{Actions: actions, Reply: func(reply forgehost.PeerReply) { replies <- reply }}, engine)
	if completed < 8 || fallbacks < 4 {
		t.Fatalf("insufficient direct/fallback decisions: %d/%d", completed, fallbacks)
	}
	t.Logf("native direct decisions=%d dropped-reply fallbacks=%d", completed, fallbacks)
}
