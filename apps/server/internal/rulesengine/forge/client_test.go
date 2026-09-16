// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

const helperEnvironment = "HEXPROOF_FORGE_TEST_HELPER"

func TestClientOwnsAndReapsIsolatedProfiles(t *testing.T) {
	root := t.TempDir()
	t.Setenv("TMPDIR", root)
	config := ProcessConfig{Command: os.Args[0],
		Args: []string{"-test.run=TestForgeRuntimeHelperProcess"},
		Env:  []string{helperEnvironment + "=profile"}, IsolatedProfile: true}
	first, err := Start(context.Background(), config)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = first.Close() })
	second, err := Start(context.Background(), config)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = second.Close() })
	if first.profileDir == "" || first.profileDir == second.profileDir {
		t.Fatal("processes shared a mutable profile")
	}
	for _, client := range []*Client{first, second} {
		if _, err := os.Stat(filepath.Join(client.profileDir, "nested", "owned")); err != nil {
			t.Fatalf("child did not use its assigned profile: %v", err)
		}
	}
	first.Invalidate()
	<-first.Done()
	if _, err := os.Stat(first.profileDir); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("killed child retained its profile: %v", err)
	}
	if _, err := os.Stat(second.profileDir); err != nil {
		t.Fatalf("first child's cleanup changed another profile: %v", err)
	}
	if err := second.Close(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(second.profileDir); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("normally closed child retained its profile: %v", err)
	}
	config.Env = []string{helperEnvironment + "=profile-probe-failure"}
	if _, err := Start(context.Background(), config); err == nil {
		t.Fatal("failed probe was accepted")
	}
	entries, err := os.ReadDir(root)
	if err != nil || len(entries) != 0 {
		t.Fatalf("failed start leaked a profile: %v / %v", entries, err)
	}
}

func TestClientInteractiveLifecycle(t *testing.T) {
	client := newHelperClient(t, "normal")
	defer func() {
		if err := client.Close(); err != nil {
			t.Errorf("Close() error = %v", err)
		}
	}()

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	handle, err := client.StartGame(ctx, validStartRequest())
	if err != nil {
		t.Fatalf("StartGame() error = %v", err)
	}
	if handle.SessionID != "forge-session-1" || len(handle.PlayerIndexes) != 2 {
		t.Fatalf("StartGame() handle = %+v", handle)
	}

	snapshot, err := client.Snapshot(ctx, handle.SessionID, 1)
	if err != nil {
		t.Fatalf("Snapshot() error = %v", err)
	}
	if !strings.Contains(string(snapshot), `"viewer":1`) {
		t.Fatalf("Snapshot() = %s", snapshot)
	}
	prompt, err := client.Prompt(ctx, handle.SessionID, 1)
	if err != nil {
		t.Fatalf("Prompt() error = %v", err)
	}
	if !strings.Contains(string(prompt), `"promptId":7`) {
		t.Fatalf("Prompt() = %s", prompt)
	}
	if err := client.SubmitAction(ctx, handle.SessionID,
		json.RawMessage(`{"type":"chooseAction","output":{"type":"pass"}}`)); err != nil {
		t.Fatalf("SubmitAction() error = %v", err)
	}
	gameOver, err := client.GameOver(ctx, handle.SessionID)
	if err != nil || gameOver {
		t.Fatalf("GameOver() = %v, %v", gameOver, err)
	}
	if err := client.EndGame(ctx, handle.SessionID); err != nil {
		t.Fatalf("EndGame() error = %v", err)
	}
}

func TestClientConcedeUsesCanonicalDirective(t *testing.T) {
	client := newHelperClient(t, "concede")
	defer client.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := client.Concede(ctx, "forge-session-1", 1); err != nil {
		t.Fatalf("Concede() error = %v", err)
	}
	if err := client.Concede(ctx, "forge-session-1", -1); err == nil {
		t.Fatal("Concede() accepted an invalid player index")
	}
}

func TestDecodeOptionalJSONAcceptsEmptyAndNull(t *testing.T) {
	for _, value := range []string{"", "  ", "null", "\nnull\t"} {
		decoded, err := decodeOptionalJSON(value, nil)
		if err != nil || decoded != nil {
			t.Fatalf("decodeOptionalJSON(%q) = %s, %v", value, decoded, err)
		}
	}
}

func TestClientRejectsInvalidStartBeforeRPC(t *testing.T) {
	client := newHelperClient(t, "normal")
	defer client.Close()
	request := validStartRequest()
	request.Players[0].Deck[0].Name = ""
	if _, err := client.StartGame(context.Background(), request); err == nil ||
		!strings.Contains(err.Error(), "card 0 name") {
		t.Fatalf("StartGame() error = %v", err)
	}
}

func TestClientReturnsBoundedRuntimeError(t *testing.T) {
	client := newHelperClient(t, "runtime-error")
	defer client.Close()
	_, err := client.Snapshot(context.Background(), "forge-session-1", 0)
	if !errors.Is(err, ErrRuntime) || len(err.Error()) > 600 ||
		strings.Contains(err.Error(), "private engine detail") || client.Healthy() {
		t.Fatalf("Snapshot() error = %v", err)
	}
}

func TestClientRejectedActionPreservesHealthyRuntime(t *testing.T) {
	client := newHelperClient(t, "action-rejected")
	defer client.Close()
	err := client.SubmitAction(context.Background(), "forge-session-1", json.RawMessage(`{}`))
	if !errors.Is(err, ErrRuntime) || strings.Contains(err.Error(), "private engine detail") || !client.Healthy() {
		t.Fatalf("SubmitAction() error = %v, healthy = %v", err, client.Healthy())
	}
	if _, err := client.Snapshot(context.Background(), "forge-session-1", 0); err != nil {
		t.Fatalf("Snapshot() after a rejected action: %v", err)
	}
}

func TestClientInvalidResponsesInvalidateTheRuntime(t *testing.T) {
	for _, mode := range []string{"malformed", "oversized", "invalid-snapshot", "exit"} {
		t.Run(mode, func(t *testing.T) {
			client := newHelperClient(t, mode)
			defer client.Close()
			ctx, cancel := context.WithTimeout(context.Background(), time.Second)
			defer cancel()
			if _, err := client.Snapshot(ctx, "forge-session-1", 0); err == nil {
				t.Fatal("invalid runtime response was accepted")
			}
			select {
			case <-client.Done():
			case <-time.After(2 * time.Second):
				t.Fatal("failed runtime was not reaped")
			}
			if client.Healthy() {
				t.Fatal("failed runtime still reports healthy")
			}
			if _, err := client.StartGame(ctx, validStartRequest()); err == nil {
				t.Fatal("dead runtime accepted a new game")
			}
		})
	}
}

func TestClientConcurrentCloseAndInvalidation(t *testing.T) {
	client := newHelperClient(t, "normal")
	var callers sync.WaitGroup
	for range 20 {
		callers.Add(1)
		go func() {
			defer callers.Done()
			client.Invalidate()
			_ = client.Close()
			_ = client.Healthy()
		}()
	}
	callers.Wait()
	select {
	case <-client.Done():
	default:
		t.Fatal("Close returned before child exit")
	}
}

func TestClientInvalidResultSchemasInvalidateTheRuntime(t *testing.T) {
	for _, mode := range []string{"invalid-handle", "invalid-prompt", "invalid-game-over", "invalid-view"} {
		t.Run(mode, func(t *testing.T) {
			client := newHelperClient(t, mode)
			defer client.Close()
			ctx, cancel := context.WithTimeout(context.Background(), time.Second)
			defer cancel()
			var err error
			switch mode {
			case "invalid-handle":
				_, err = client.StartGame(ctx, validStartRequest())
			case "invalid-prompt":
				_, err = client.Prompt(ctx, "forge-session-1", 0)
			case "invalid-game-over":
				_, err = client.GameOver(ctx, "forge-session-1")
			case "invalid-view":
				_, err = client.SnapshotView(ctx, "forge-session-1", 0)
			}
			if !errors.Is(err, ErrRuntime) || client.Healthy() {
				t.Fatalf("bad result left runtime healthy: %v", err)
			}
		})
	}
}

func TestClientTimeoutTerminatesRuntime(t *testing.T) {
	client := newHelperClient(t, "hang")
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	_, err := client.Snapshot(ctx, "forge-session-1", 0)
	if err == nil || !strings.Contains(err.Error(), "deadline exceeded") {
		t.Fatalf("Snapshot() error = %v", err)
	}
	select {
	case <-client.done:
	case <-time.After(2 * time.Second):
		t.Fatal("timed-out Forge runtime was not terminated")
	}
	_ = client.Close()
}

func newHelperClient(t *testing.T, mode string) *Client {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	client, err := Start(ctx, ProcessConfig{
		Command:      os.Args[0],
		Args:         []string{"-test.run=TestForgeRuntimeHelperProcess"},
		Env:          []string{helperEnvironment + "=" + mode},
		StartTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("Start() error = %v", err)
	}
	return client
}

func validStartRequest() StartGameRequest {
	return StartGameRequest{
		GameID:       "game-1",
		Variant:      "Constructed",
		StartingLife: 20,
		Seed:         42,
		Players: []PlayerConfig{
			{Name: "Alice", Deck: []CardIdentity{{Name: "Forest", SetCode: "EOE", CollectorNumber: "266"}}},
			{Name: "Bob", Deck: []CardIdentity{{Name: "Mountain", SetCode: "EOE", CollectorNumber: "274"}}},
		},
	}
}

// TestForgeRuntimeHelperProcess implements the upstream JSONL envelope in a
// child test process. It intentionally does not exercise room or WebSocket code.
func TestForgeRuntimeHelperProcess(t *testing.T) {
	mode := os.Getenv(helperEnvironment)
	if mode == "" {
		return
	}
	scanner := bufio.NewScanner(os.Stdin)
	encoder := json.NewEncoder(os.Stdout)
	for scanner.Scan() {
		var request rpcRequest
		if err := json.Unmarshal(scanner.Bytes(), &request); err != nil {
			_ = encoder.Encode(rpcResponse{Error: err.Error()})
			continue
		}
		if request.Command == "quit" {
			return
		}
		if strings.HasPrefix(mode, "profile") && request.Command == "reset" {
			profile := os.Getenv("HEXPROOF_FORGE_PROFILE")
			if profile == "" {
				t.Fatal("isolated profile was not assigned")
			}
			if err := os.MkdirAll(filepath.Join(profile, "nested"), 0700); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(profile, "nested", "owned"), []byte("private preferences"), 0600); err != nil {
				t.Fatal(err)
			}
			if mode == "profile-probe-failure" {
				_ = encoder.Encode(rpcResponse{Error: "probe failure"})
				continue
			}
		}
		if mode == "hang" && request.Command == "getSnapshot" {
			time.Sleep(time.Hour)
		}
		if mode == "runtime-error" && request.Command == "getSnapshot" {
			_ = encoder.Encode(rpcResponse{Error: strings.Repeat("private engine detail", 80)})
			continue
		}
		if request.Command == "getSnapshot" {
			switch mode {
			case "malformed":
				_, _ = fmt.Fprintln(os.Stdout, "private invalid JSON")
				continue
			case "oversized":
				_, _ = fmt.Fprintln(os.Stdout, strings.Repeat("x", defaultMaxResponseBytes+1))
				continue
			case "invalid-snapshot":
				_ = encoder.Encode(rpcResponse{OK: true, Result: "not JSON"})
				continue
			case "exit":
				os.Exit(23)
			}
		}
		response := rpcResponse{OK: true}
		switch request.Command {
		case "reset", "endGame", "abortGame":
			response.Result = ""
		case "submitAction":
			if mode == "action-rejected" {
				response = rpcResponse{Error: "private engine detail"}
			} else if mode == "concede" && request.Payload !=
				`{"type":"directive","directive":{"type":"concede"},"player":1}` {
				response = rpcResponse{Error: "invalid concede directive"}
			} else {
				response.Result = ""
			}
		case "startGame":
			var startRequest StartGameRequest
			if err := json.Unmarshal([]byte(request.Payload), &startRequest); err != nil {
				response = rpcResponse{Error: err.Error()}
			} else {
				response.Result = `{"sessionId":"forge-session-1","playerIndexes":[0,1]}`
			}
			if mode == "invalid-handle" {
				response.Result = `{"sessionId":"forge-session-1","playerIndexes":[0,0]}`
			}
		case "getSnapshot":
			response.Result = fmt.Sprintf(`{"viewer":%d,"players":[]}`, *request.Viewer)
		case "getPrompt":
			response.Result = fmt.Sprintf(`{"promptId":7,"player":%d}`, *request.PlayerIndex)
			if mode == "invalid-prompt" {
				response.Result = "not JSON"
			}
		case "getGameOver":
			response.Result = "false"
			if mode == "invalid-game-over" {
				response.Result = "not a boolean"
			}
		default:
			response = rpcResponse{Error: "unknown command"}
		}
		if err := encoder.Encode(response); err != nil {
			return
		}
	}
}
