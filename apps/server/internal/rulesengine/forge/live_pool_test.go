//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

// This crosses the production pool, multiplexed transport and actual native
// engine. Games use deliberately synthetic card-script decks; tournament decks
// and visible controls are qualified separately by the native GUI runner.
func TestLiveSharedForgePool(t *testing.T) {
	root, err := filepath.Abs(os.Getenv("HEXPROOF_REAL_FORGE_ROOT"))
	if err != nil || os.Getenv("HEXPROOF_REAL_FORGE_ROOT") == "" {
		t.Fatal("HEXPROOF_REAL_FORGE_ROOT must name the pinned adapter 3 runtime")
	}
	config := JavaProcessConfig(os.Getenv("HEXPROOF_FORGE_JAVA"),
		filepath.Join(root, "forge-harness.jar"), filepath.Join(root, "forge-gui"))
	config.Args = append([]string{"-Xms32m", "-Xmx768m", "-XX:+UseSerialGC", "-XX:ActiveProcessorCount=2", "-XX:+ExitOnOutOfMemoryError"}, config.Args...)
	pool, err := NewPool(config, 3)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = pool.Close() })
	var previous *sharedWorker
	for wave := range 3 {
		clients := make([]*Client, 3)
		ids := make([]string, 3)
		for index := range 3 {
			client, err := pool.Acquire(context.Background())
			if err != nil {
				t.Fatal(err)
			}
			clients[index] = client
			t.Cleanup(func() { _ = client.Close() })
			if index == 0 && wave == 0 {
				previous = client.shared.worker
			}
			if client.shared.worker != previous {
				t.Fatal("healthy shared worker was not reused across games/waves")
			}
			ids[index] = fmt.Sprintf("shared-%d-%d", wave, index)
			land, spell := "Forest", "Grizzly Bears"
			if index == 1 {
				land, spell = "Mountain", "Lightning Bolt"
			}
			request := liveStartRequest(ids[index], 2, "Constructed", 20, liveDeck(land, spell, 24, 36))
			request.Seed += int64(wave*3 + index)
			if _, err := client.StartGame(context.Background(), request); err != nil {
				t.Fatal(err)
			}
		}
		before, err := clients[1].Snapshot(context.Background(), ids[1], -1)
		if err != nil {
			t.Fatal(err)
		}
		if wave == 1 {
			clients[0].Invalidate()
			<-clients[0].Done()
			after, err := clients[1].Snapshot(context.Background(), ids[1], -1)
			if err != nil || string(before) != string(after) {
				t.Fatalf("aborting a pending game changed its neighbor: %v", err)
			}
			clients[0], err = pool.Acquire(context.Background())
			if err != nil {
				t.Fatal(err)
			}
			ids[0] += "-replacement"
			request := liveStartRequest(ids[0], 2, "Constructed", 20, liveDeck("Forest", "Grizzly Bears", 24, 36))
			if _, err := clients[0].StartGame(context.Background(), request); err != nil {
				t.Fatal(err)
			}
		}
		t.Run(fmt.Sprintf("wave-%d", wave), func(t *testing.T) {
			for index, client := range clients {
				t.Run(fmt.Sprintf("game-%d", index), func(t *testing.T) {
					t.Parallel()
					defer client.Close()
					stats := livePlay(t, client, ids[index], 2, 0)
					if stats["land"] == 0 || stats["cast"] == 0 || stats["payManaCost"] == 0 {
						t.Fatalf("shared game bypassed native choices: %v", stats)
					}
				})
			}
		})
	}
}
