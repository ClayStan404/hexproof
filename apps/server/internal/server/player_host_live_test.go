//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
)

func TestLivePlayerHostedForgeMatches(t *testing.T) {
	root := os.Getenv("HEXPROOF_REAL_FORGE_ROOT")
	if root == "" {
		t.Fatal("HEXPROOF_REAL_FORGE_ROOT is required")
	}
	root, err := filepath.Abs(root)
	if err != nil {
		t.Fatal(err)
	}
	engine := forge.JavaProcessConfig(os.Getenv("HEXPROOF_FORGE_JAVA"), filepath.Join(root, "forge-harness.jar"), filepath.Join(root, "forge-gui"))
	if overlay := os.Getenv("HEXPROOF_TEST_FORGE_OVERLAY"); overlay != "" {
		engine = forge.JavaOverlayProcessConfig(os.Getenv("HEXPROOF_FORGE_JAVA"), filepath.Join(root, "forge-harness.jar"), filepath.Join(root, "forge-gui"), overlay)
	}
	engine.Args = append([]string{"-Xmx768m", "-XX:+UseSerialGC", "-XX:ActiveProcessorCount=2", "-Djava.awt.headless=true"}, engine.Args...)
	for _, mode := range []string{protocol.MatchBO1, protocol.MatchBO3} {
		t.Run(mode, func(t *testing.T) {
			config := DefaultConfig()
			config.AllowPlayerHosting = true
			config.MessagesPerSecond = 10000
			config.ReconnectWindow = time.Minute
			srv, handler := newConfiguredTestServer(t, config)
			if handler.forgeRulesAvailable() {
				t.Fatal("relay server unexpectedly owns a local Forge runtime")
			}
			runLiveForgeWebSocketRoom(t, srv, handler, mode, engine)
		})
	}
}
