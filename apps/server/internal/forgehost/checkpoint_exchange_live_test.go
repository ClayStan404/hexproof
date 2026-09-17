//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forgehost

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"hexproof/server/internal/rulesengine/forge"
)

// These opt-in artifacts contain only the synthetic test game's full state.
// Never export a real player's checkpoint or publication for diagnostics.
type checkpointExchangeArtifact struct {
	Checkpoint   Checkpoint     `json:"checkpoint"`
	Publications []*Publication `json:"publications"`
}

func writeCheckpointFixture(t *testing.T, path string, value any) {
	t.Helper()
	if !filepath.IsAbs(path) {
		t.Fatal("checkpoint fixture path must be absolute")
	}
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	if _, err := file.Write(data); err != nil {
		t.Fatal(err)
	}
}

func TestLiveCheckpointImport(t *testing.T) {
	input := os.Getenv("HEXPROOF_CHECKPOINT_IMPORT")
	if input == "" {
		t.Skip("requires an exported synthetic checkpoint from another platform")
	}
	data, err := os.ReadFile(input)
	if err != nil {
		t.Fatal(err)
	}
	var fixture checkpointExchangeArtifact
	if json.Unmarshal(data, &fixture) != nil || fixture.Checkpoint.validate() != nil ||
		len(fixture.Publications) != len(fixture.Checkpoint.Actions)+1 {
		t.Fatal("invalid checkpoint exchange fixture")
	}
	root, overlay := os.Getenv("HEXPROOF_REAL_FORGE_ROOT"), os.Getenv("HEXPROOF_TEST_FORGE_OVERLAY")
	if root == "" || overlay == "" {
		t.Fatal("HEXPROOF_REAL_FORGE_ROOT and HEXPROOF_TEST_FORGE_OVERLAY are required")
	}
	config := forge.JavaOverlayProcessConfig(os.Getenv("HEXPROOF_FORGE_JAVA"), filepath.Join(root, "forge-harness.jar"), filepath.Join(root, "forge-gui"), overlay)
	config.Args = append([]string{"-Xmx768m", "-XX:+UseSerialGC", "-XX:ActiveProcessorCount=2", "-Djava.awt.headless=true"}, config.Args...)
	start := func(ctx context.Context) (forge.Runtime, error) { return forge.Start(ctx, config) }
	ctx, cancel := context.WithTimeout(t.Context(), 4*time.Minute)
	defer cancel()
	executor := NewExecutor("ROOM", start, nil)
	defer executor.Cancel("")
	engineID := NewID()
	for step, expected := range fixture.Publications {
		request := Request{RoomID: "ROOM", EngineID: engineID, ID: uint64(step + 1), Command: "start", Start: &fixture.Checkpoint.Start}
		if step > 0 {
			request.Command, request.Start, request.Action = "action", nil, fixture.Checkpoint.Actions[step-1].Action
		}
		response := executor.Execute(ctx, request)
		want, wantErr := publicationDigest(expected)
		got, gotErr := publicationDigest(response.Publication)
		if response.Error != "" || wantErr != nil || gotErr != nil || got != want {
			if output := os.Getenv("HEXPROOF_CHECKPOINT_MISMATCH"); output != "" {
				writeCheckpointFixture(t, output, map[string]any{"step": step, "error": response.Error, "expected": expected, "actual": response.Publication})
			}
			t.Fatalf("cross-platform publication differs at synthetic decision %d (engine error %q)", step, response.Error)
		}
	}
	executor.Cancel("")
	successor := NewExecutor("ROOM", start, nil)
	defer successor.Cancel("")
	response := successor.Execute(ctx, Request{RoomID: "ROOM", EngineID: NewID(), ID: 1, Command: "restore", Checkpoint: &fixture.Checkpoint})
	if response.Error != "" {
		t.Fatalf("cross-platform production replay: %s", response.Error)
	}
	t.Logf("verified %d cross-platform decisions and production checkpoint restore", len(fixture.Checkpoint.Actions))
}
