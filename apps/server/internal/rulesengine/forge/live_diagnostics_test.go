//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	"hexproof/server/internal/forgediag"
)

// These opt-in tests kill only the JVM they start, after real Commander games
// reach a player prompt. They exercise packaged native diagnostics and process
// reaping without manufacturing a supervisor failure through Invalidate.
func TestLiveForgeCrashDiagnosticsExternalKill(t *testing.T) {
	for _, shared := range []bool{false, true} {
		for _, participants := range []int{3, 4} {
			t.Run(fmt.Sprintf("shared-%t/commander-%d", shared, participants), func(t *testing.T) {
				client, pool := liveDiagnosticAcquire(t, liveDiagnosticConfig(t), shared)
				game := liveDiagnosticStart(t, client, "crash-primary", participants, "Isamaru, Hound of Konda", "Plains")
				liveDiagnosticWait(t, client, game)
				before := liveDiagnosticNoFailure(t, client, game)

				var neighbor *Client
				var neighborGame SessionHandle
				var neighborBefore forgediag.FailureInfo
				if pool != nil {
					ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
					defer cancel()
					var err error
					neighbor, err = pool.Acquire(ctx)
					if err != nil {
						t.Fatal(err)
					}
					t.Cleanup(func() { _ = neighbor.Close() })
					if neighbor.shared.worker != client.shared.worker {
						t.Fatal("neighbor must share the killed JVM")
					}
					neighborGame = liveDiagnosticStart(t, neighbor, "crash-neighbor", 7-participants, "Krenko, Mob Boss", "Mountain")
					liveDiagnosticWait(t, neighbor, neighborGame)
					neighborBefore = liveDiagnosticNoFailure(t, neighbor, neighborGame)
					if before.ProducerID == neighborBefore.ProducerID || game.DiagnosticProducerID == neighborGame.DiagnosticProducerID {
						t.Fatal("shared games must have distinct supervisor and native producers")
					}
					liveDiagnosticNoFailure(t, client, game)
				}

				command := client.command
				if shared {
					command = client.shared.worker.command
				}
				if err := command.Process.Kill(); err != nil {
					t.Fatal(err)
				}
				liveDiagnosticCollectExit(t, client, game, before.ProducerID)
				if neighbor != nil {
					liveDiagnosticCollectExit(t, neighbor, neighborGame, neighborBefore.ProducerID)
				}
			})
		}
	}
}

func TestLiveForgeCrashDiagnosticsCleanAbort(t *testing.T) {
	for _, shared := range []bool{false, true} {
		t.Run(fmt.Sprintf("shared-%t", shared), func(t *testing.T) {
			client, _ := liveDiagnosticAcquire(t, liveDiagnosticConfig(t), shared)
			game := liveDiagnosticStart(t, client, "normal-abort", 3, "Isamaru, Hound of Konda", "Plains")
			liveDiagnosticWait(t, client, game)
			ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
			defer cancel()
			if err := client.AbortGame(ctx, game.SessionID); err != nil {
				t.Fatal(err)
			}
			liveDiagnosticNoFailure(t, client, game)
		})
	}
}

func liveDiagnosticConfig(t *testing.T) ProcessConfig {
	t.Helper()
	root := os.Getenv("HEXPROOF_REAL_FORGE_ROOT")
	if root == "" {
		t.Fatal("HEXPROOF_REAL_FORGE_ROOT must name an extracted pinned runtime")
	}
	root, err := filepath.Abs(root)
	if err != nil {
		t.Fatal(err)
	}
	config := JavaProcessConfig(os.Getenv("HEXPROOF_FORGE_JAVA"),
		filepath.Join(root, "forge-harness.jar"), filepath.Join(root, "forge-gui"))
	if overlay := os.Getenv("HEXPROOF_REAL_FORGE_OVERLAY"); overlay != "" {
		overlay, err = filepath.Abs(overlay)
		if err != nil {
			t.Fatal(err)
		}
		config = JavaOverlayProcessConfig(os.Getenv("HEXPROOF_FORGE_JAVA"),
			filepath.Join(root, "forge-harness.jar"), filepath.Join(root, "forge-gui"), overlay)
	}
	config.Dir = t.TempDir()
	config.Args = append([]string{"-Xms32m", "-Xmx1024m", "-XX:+UseSerialGC", "-XX:ActiveProcessorCount=2",
		"-Djava.awt.headless=true", "-Duser.home=" + config.Dir}, config.Args...)
	return config
}

func liveDiagnosticAcquire(t *testing.T, config ProcessConfig, shared bool) (*Client, *Pool) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	var client *Client
	var pool *Pool
	var err error
	if shared {
		pool, err = NewPool(config, 2)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = pool.Close() })
		client, err = pool.Acquire(ctx)
	} else {
		client, err = Start(ctx, config)
	}
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = client.Close() })
	return client, pool
}

func liveDiagnosticStart(t *testing.T, client *Client, id string, participants int, commander, land string) SessionHandle {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	deck := append(liveDeck(land, land, 99, 0), CardIdentity{Name: commander})
	request := liveStartRequest(id, participants, "Commander", 40, deck)
	request.StartingPlayerIndex = new(int)
	for index := range request.Players {
		request.Players[index].CommanderNames = []string{commander}
	}
	game, err := client.StartGame(ctx, request)
	if err != nil {
		t.Fatal(err)
	}
	if game.DiagnosticProducerID == "" {
		t.Fatal("runtime did not return a native diagnostic producer")
	}
	view, err := client.SnapshotView(ctx, game.SessionID, -1)
	if err != nil || len(view.Players) != participants {
		t.Fatalf("Commander participant count: %+v %v", view, err)
	}
	for _, player := range view.Players {
		if player.Life != 40 || len(player.Commanders) != 1 || player.Commanders[0].Name != commander {
			t.Fatalf("Commander initialization: %+v", player)
		}
	}
	raw, err := client.Prompt(ctx, game.SessionID, 0)
	if err != nil {
		t.Fatal(err)
	}
	prompt, err := NormalizePrompt(raw)
	if err != nil || prompt.Kind != "mulligan" || prompt.PlayerIndex != 0 {
		t.Fatalf("expected a real waiting player prompt: %+v %v", prompt, err)
	}
	return game
}

func liveDiagnosticNoFailure(t *testing.T, client *Client, game SessionHandle) forgediag.FailureInfo {
	t.Helper()
	info := client.FailureInfo()
	if info.ProducerID == "" || info.Boundary != nil || info.Exit != nil {
		t.Fatalf("normal player wait/abort acquired a failure: %+v", info)
	}
	liveDiagnosticOwnContext(t, info.Native, game)
	return info
}

func liveDiagnosticOwnContext(t *testing.T, capsule *forgediag.Capsule, game SessionHandle) {
	t.Helper()
	if capsule == nil {
		return
	}
	if capsule.SessionID != game.SessionID || capsule.ProducerID != game.DiagnosticProducerID {
		t.Fatalf("native evidence belongs to another game: %+v, expected %+v", capsule, game)
	}
	if capsule.Kind != "context" || len(capsule.Causes) != 0 {
		t.Fatalf("external kill or normal wait must not invent an engine/resource failure: %+v", capsule)
	}
}

func liveDiagnosticWait(t *testing.T, client *Client, game SessionHandle) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	raw, err := client.Prompt(ctx, game.SessionID, 0)
	if err != nil {
		t.Fatal(err)
	}
	prompt, err := NormalizePrompt(raw)
	if err != nil {
		t.Fatal(err)
	}
	if client.shared != nil {
		raw, supported, err := client.AwaitPrompt(ctx, game.SessionID, prompt.PromptID)
		if err != nil || supported || len(raw) != 0 {
			t.Fatalf("shared wait must retain polling: supported=%t raw=%s err=%v", supported, raw, err)
		}
	} else {
		// Keep the RPC deadline separate from the native long-poll timeout so
		// this exercises a successful empty response, not cancellation races.
		result, err := client.call(ctx, rpcRequest{Command: "awaitPrompt", SessionID: game.SessionID,
			PreviousPromptID: prompt.PromptID, TimeoutMs: 40}, false, false)
		decoded, err := decodeOptionalJSON(result, err)
		if err != nil || len(decoded) != 0 {
			t.Fatalf("normal long-poll expiry: raw=%s err=%v", decoded, err)
		}
	}
	liveDiagnosticNoFailure(t, client, game)
}

func liveDiagnosticCollectExit(t *testing.T, client *Client, game SessionHandle, producer string) {
	t.Helper()
	select {
	case <-client.Done():
	case <-time.After(10 * time.Second):
		t.Fatal("owned JVM exited without closing its client")
	}
	deadline := time.Now().Add(5 * time.Second)
	info := client.FailureInfo()
	for !info.CollectionDone && time.Now().Before(deadline) {
		time.Sleep(5 * time.Millisecond)
		info = client.FailureInfo()
	}
	if !info.CollectionDone || info.ProducerID != producer || info.Exit == nil || info.Exit.Code == nil || *info.Exit.Code == 0 {
		t.Fatalf("incomplete or misattributed natural process exit: %+v", info)
	}
	if info.Exit.SupervisorKilled || runtime.GOOS != "windows" && info.Exit.Signal == "" {
		t.Fatalf("external process kill misclassified as supervisor termination: %+v", info.Exit)
	}
	if info.Boundary != nil && info.Boundary.Code != "process_exited" && info.Boundary.Code != "process_signalled" {
		t.Fatalf("natural exit acquired an unrelated boundary: %+v", info.Boundary)
	}
	liveDiagnosticOwnContext(t, info.Native, game)
	t.Logf("session=%s supervisorProducer=%s nativeProducer=%s nativeContext=%t exitCode=%d signal=%q drained=%t",
		game.SessionID, info.ProducerID, game.DiagnosticProducerID, info.Native != nil, *info.Exit.Code, info.Exit.Signal, info.CollectionDone)
}
