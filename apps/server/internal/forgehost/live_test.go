//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forgehost

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"hexproof/server/internal/rulesengine/forge"
)

func TestLivePlayerHostReconnectCrashAndRevoke(t *testing.T) {
	root := os.Getenv("HEXPROOF_REAL_FORGE_ROOT")
	if root == "" {
		t.Fatal("HEXPROOF_REAL_FORGE_ROOT is required")
	}
	root, err := filepath.Abs(root)
	if err != nil {
		t.Fatal(err)
	}
	config := forge.JavaProcessConfig(os.Getenv("HEXPROOF_FORGE_JAVA"), filepath.Join(root, "forge-harness.jar"), filepath.Join(root, "forge-gui"))
	if overlay := os.Getenv("HEXPROOF_TEST_FORGE_OVERLAY"); overlay != "" {
		config = forge.JavaOverlayProcessConfig(os.Getenv("HEXPROOF_FORGE_JAVA"), filepath.Join(root, "forge-harness.jar"), filepath.Join(root, "forge-gui"), overlay)
	}
	config.Args = append([]string{"-Xmx768m", "-XX:+UseSerialGC", "-XX:ActiveProcessorCount=2", "-Djava.awt.headless=true"}, config.Args...)
	started := make(chan *forge.Client, 1)
	link, ctx := newRelayFixtureWithTimeout(t, func(ctx context.Context) (forge.Runtime, error) {
		client, err := forge.Start(ctx, config)
		if err == nil {
			started <- client
		}
		return client, err
	}, 90*time.Second)
	deck := make([]forge.CardIdentity, 60)
	for i := range deck {
		deck[i].Name = "Mountain"
	}
	var previous *forge.Client
	for round := range 3 {
		engine, err := link.NewRuntime()
		if err != nil {
			t.Fatal(err)
		}
		handle, err := engine.StartGame(ctx, forge.StartGameRequest{
			GameID: fmt.Sprintf("live-relay-%d", round), Variant: "Constructed", StartingLife: 20, Seed: 42,
			Players: []forge.PlayerConfig{{Name: "Host", Deck: deck}, {Name: "Opponent", Deck: deck}},
		})
		if err != nil {
			t.Fatal(err)
		}
		client := <-started
		if client == previous {
			t.Fatal("next game reused the previous JVM")
		}
		previous = client
		switch round {
		case 0:
			prompt, err := engine.Prompt(ctx, handle.SessionID, 0)
			if err != nil || len(prompt) == 0 {
				t.Fatalf("initial prompt: %s, %v", prompt, err)
			}
			link.mu.Lock()
			conn, epoch := link.conn, link.epoch
			link.mu.Unlock()
			_ = conn.CloseNow()
			waitUntil(t, func() bool {
				link.mu.Lock()
				defer link.mu.Unlock()
				return link.conn != nil && link.epoch > epoch
			})
			resumed, err := client.Prompt(ctx, handle.SessionID, 0)
			if err != nil || !bytes.Equal(prompt, resumed) || !engine.Healthy() {
				t.Fatalf("reconnect did not preserve the real engine decision: %v", err)
			}
			if err := engine.Concede(ctx, handle.SessionID, 0); err != nil {
				t.Fatal(err)
			}
			if over, err := engine.GameOver(ctx, handle.SessionID); err != nil || !over {
				t.Fatalf("resumed game did not finish: %v", err)
			}
			if err := engine.EndGame(ctx, handle.SessionID); err != nil {
				t.Fatal(err)
			}
		case 1:
			client.Invalidate() // Kill the owned JVM while it is waiting for input.
			waitUntil(t, func() bool { return !engine.Healthy() })
			if _, err := engine.GameOver(ctx, handle.SessionID); err == nil {
				t.Fatal("crashed engine invented a terminal result")
			}
		case 2:
			link.Close() // Explicit room revocation must cancel, not wait for grace.
		}
		select {
		case <-client.Done():
		case <-time.After(2 * time.Second):
			t.Fatal("owned JVM was not reaped after completion, crash or revocation")
		}
	}
}
