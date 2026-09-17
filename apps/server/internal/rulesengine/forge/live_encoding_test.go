//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestLiveNativeProtocolUTF8(t *testing.T) {
	root, overlay := os.Getenv("HEXPROOF_REAL_FORGE_ROOT"), os.Getenv("HEXPROOF_TEST_FORGE_OVERLAY")
	if root == "" || overlay == "" {
		t.Fatal("HEXPROOF_REAL_FORGE_ROOT and HEXPROOF_TEST_FORGE_OVERLAY are required")
	}
	for _, shared := range []bool{false, true} {
		name := "dedicated"
		if shared {
			name = "shared"
		}
		t.Run(name, func(t *testing.T) {
			config := JavaOverlayProcessConfig(os.Getenv("HEXPROOF_FORGE_JAVA"), filepath.Join(root, "forge-harness.jar"), filepath.Join(root, "forge-gui"), overlay)
			// Reproduce a non-UTF-8 Windows stdout code page on any test OS.
			config.Args = append([]string{"-Xmx768m", "-XX:+UseSerialGC", "-XX:ActiveProcessorCount=2", "-Djava.awt.headless=true", "-Dstdout.encoding=windows-1252"}, config.Args...)
			ctx, cancel := context.WithTimeout(t.Context(), time.Minute)
			defer cancel()
			var client *Client
			var err error
			if shared {
				pool, poolErr := NewPool(config, 2)
				if poolErr != nil {
					t.Fatal(poolErr)
				}
				defer pool.Close()
				client, err = pool.Acquire(ctx)
			} else {
				client, err = Start(ctx, config)
			}
			if err != nil {
				t.Fatal(err)
			}
			defer client.Close()
			request := liveStartRequest("utf8-"+name, 2, "Constructed", 20, liveDeck("Forest", "Grizzly Bears", 24, 36))
			request.Players[0].Name, request.Players[1].Name = "玩家 — 雪", "Opponent Ω"
			handle, err := client.StartGame(ctx, request)
			if err != nil {
				t.Fatal(err)
			}
			raw, err := client.Snapshot(ctx, handle.SessionID, 0)
			if err != nil {
				t.Fatal(err)
			}
			view, err := DecodeSnapshotView(raw)
			if err != nil || len(view.Players) != 2 {
				t.Fatalf("invalid native snapshot: %v", err)
			}
			for index, player := range view.Players {
				if player.Name != request.Players[index].Name {
					t.Fatalf("native JSONL changed UTF-8 name: got %q, want %q", player.Name, request.Players[index].Name)
				}
			}
		})
	}
}
