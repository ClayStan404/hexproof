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
	"strings"
	"testing"
	"time"
)

const helperEnvironment = "HEXPROOF_FORGE_TEST_HELPER"

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
	if !errors.Is(err, ErrRuntime) || len(err.Error()) > 600 {
		t.Fatalf("Snapshot() error = %v", err)
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
		if mode == "hang" && request.Command == "getSnapshot" {
			time.Sleep(time.Hour)
		}
		if mode == "runtime-error" && request.Command == "getSnapshot" {
			_ = encoder.Encode(rpcResponse{Error: strings.Repeat("private engine detail", 80)})
			continue
		}
		response := rpcResponse{OK: true}
		switch request.Command {
		case "reset", "submitAction", "endGame", "abortGame":
			response.Result = ""
		case "startGame":
			var startRequest StartGameRequest
			if err := json.Unmarshal([]byte(request.Payload), &startRequest); err != nil {
				response = rpcResponse{Error: err.Error()}
			} else {
				response.Result = `{"sessionId":"forge-session-1","playerIndexes":[0,1]}`
			}
		case "getSnapshot":
			response.Result = fmt.Sprintf(`{"viewer":%d,"players":[]}`, *request.Viewer)
		case "getPrompt":
			response.Result = fmt.Sprintf(`{"promptId":7,"player":%d}`, *request.PlayerIndex)
		case "getGameOver":
			response.Result = "false"
		default:
			response = rpcResponse{Error: "unknown command"}
		}
		if err := encoder.Encode(response); err != nil {
			return
		}
	}
}
