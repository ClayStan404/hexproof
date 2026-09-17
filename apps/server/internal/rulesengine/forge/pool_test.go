// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

func testSharedPool(t *testing.T) *Pool {
	t.Helper()
	pool, err := NewPool(ProcessConfig{Command: os.Args[0],
		Args: []string{"-test.run=^TestSharedProcessHelper$", "--"},
		Env:  []string{"HEXPROOF_SHARED_HELPER=1"}, IsolatedProfile: true}, 2)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = pool.Close() })
	return pool
}

func poolGame(t *testing.T, pool *Pool, id string) *Client {
	t.Helper()
	client, err := pool.Acquire(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = client.Close() })
	request := validStartRequest()
	request.GameID = id
	if _, err := client.StartGame(context.Background(), request); err != nil {
		t.Fatal(err)
	}
	return client
}

func TestPoolMultiplexesAndFencesGameLeases(t *testing.T) {
	pool := testSharedPool(t)
	first := poolGame(t, pool, "slow")
	second := poolGame(t, pool, "fast")
	third := poolGame(t, pool, "other-worker")
	if first.shared.worker != second.shared.worker || first.shared.worker == third.shared.worker {
		t.Fatal("pool did not enforce two games per worker")
	}
	if _, err := first.Snapshot(context.Background(), "fast", 0); err == nil {
		t.Fatal("lease accepted another game's session ID")
	}
	slow := make(chan error, 1)
	go func() { _, err := first.Snapshot(context.Background(), "slow", 0); slow <- err }()
	deadline := time.Now().Add(time.Second)
	for {
		first.shared.worker.mu.Lock()
		pending := len(first.shared.worker.pending)
		first.shared.worker.mu.Unlock()
		if pending > 0 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("slow request did not start")
		}
		time.Sleep(time.Millisecond)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 150*time.Millisecond)
	defer cancel()
	if snapshot, err := second.Snapshot(ctx, "fast", 1); err != nil || !strings.Contains(string(snapshot), `"viewer":1`) {
		t.Fatalf("another game's slow call blocked the worker: %s / %v", snapshot, err)
	}
	if err := <-slow; err != nil {
		t.Fatal(err)
	}
	if err := first.Close(); err != nil {
		t.Fatal(err)
	}
	if !second.Healthy() {
		t.Fatal("closing one game killed its neighbor")
	}
	replacement := poolGame(t, pool, "replacement")
	if replacement.shared.worker != second.shared.worker {
		t.Fatal("cleanly released worker slot was not reused")
	}
	if err := replacement.AbortGame(context.Background(), "replacement"); err != nil {
		t.Fatal(err)
	}
	if _, err := replacement.Snapshot(context.Background(), "replacement", 0); err == nil {
		t.Fatal("ended lease accepted more work")
	}
}

func TestPoolGameFailureAndWorkerFailureScopes(t *testing.T) {
	pool := testSharedPool(t)
	first := poolGame(t, pool, "rejected")
	second := poolGame(t, pool, "survivor")
	if _, err := first.Snapshot(context.Background(), "rejected", 0); err == nil {
		t.Fatal("native rejection was ignored")
	}
	select {
	case <-first.Done():
	case <-time.After(3 * time.Second):
		t.Fatal("failed game was not cleaned up")
	}
	if _, err := second.Snapshot(context.Background(), "survivor", 0); err != nil {
		t.Fatalf("isolated game failure affected its neighbor: %v", err)
	}
	hung := poolGame(t, pool, "hang")
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	if _, err := hung.Snapshot(ctx, "hang", 0); err == nil {
		t.Fatal("hung call did not time out")
	}
	for _, client := range []*Client{hung, second} {
		select {
		case <-client.Done():
		case <-time.After(3 * time.Second):
			t.Fatal("uncertain worker retained a live lease")
		}
	}
	replacement := poolGame(t, pool, "fresh")
	if replacement.shared.worker == second.shared.worker {
		t.Fatal("failed worker was reused")
	}
}

func TestPoolIdleRetirementAndReap(t *testing.T) {
	root := t.TempDir()
	t.Setenv("TMPDIR", root)
	pool := testSharedPool(t)
	pool.idleTimeout = 10 * time.Millisecond
	first := poolGame(t, pool, "idle")
	if err := first.Close(); err != nil {
		t.Fatal(err)
	}
	select {
	case <-first.shared.worker.done:
	case <-time.After(3 * time.Second):
		t.Fatal("idle worker did not retire")
	}
	entries, err := os.ReadDir(root)
	if err != nil || len(entries) != 0 {
		t.Fatalf("worker left mutable profiles behind: %v / %v", entries, err)
	}
	pool.idleTimeout = time.Minute
	second := poolGame(t, pool, "retiring")
	pool.mu.Lock()
	second.shared.entry.games = sharedWorkerGames
	pool.mu.Unlock()
	third := poolGame(t, pool, "new-worker")
	if second.shared.worker == third.shared.worker {
		t.Fatal("retiring worker admitted another game")
	}
	if err := second.Close(); err != nil {
		t.Fatal(err)
	}
	select {
	case <-second.shared.worker.done:
	case <-time.After(3 * time.Second):
		t.Fatal("exhausted worker was not reaped")
	}
	if err := pool.Close(); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Acquire(context.Background()); err == nil {
		t.Fatal("closed pool admitted a lease")
	}
}

func TestPoolRejectsOldRuntime(t *testing.T) {
	pool, err := NewPool(ProcessConfig{Command: os.Args[0],
		Args: []string{"-test.run=^TestSharedProcessHelper$", "--"},
		Env:  []string{"HEXPROOF_SHARED_HELPER=old"}}, 2)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	if _, err := pool.Acquire(context.Background()); err == nil {
		t.Fatal("adapter without explicit shared capability was accepted")
	}
}

func TestSharedProcessHelper(t *testing.T) {
	mode := os.Getenv("HEXPROOF_SHARED_HELPER")
	if mode == "" {
		return
	}
	capacity := 0
	for i, arg := range os.Args {
		if arg == "--max-games" && i+1 < len(os.Args) {
			capacity, _ = strconv.Atoi(os.Args[i+1])
		}
	}
	var output sync.Mutex
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 4096), maxRequestBytes)
	for scanner.Scan() {
		var request sharedRequest
		if err := json.Unmarshal(scanner.Bytes(), &request); err != nil {
			os.Exit(2)
		}
		go func(request sharedRequest) {
			response := sharedResponse{RequestID: request.RequestID, rpcResponse: rpcResponse{OK: true, Result: `{}`}}
			switch request.Command {
			case "reset":
				if mode != "old" {
					response.Result = fmt.Sprintf(`{"sharedVersion":1,"capacity":%d}`, capacity)
				}
			case "startGame":
				var setup StartGameRequest
				_ = json.Unmarshal([]byte(request.Payload), &setup)
				handle, _ := json.Marshal(SessionHandle{SessionID: setup.GameID, PlayerIndexes: []int{0, 1}})
				response.Result = string(handle)
			case "getSnapshot":
				if request.SessionID == "slow" {
					time.Sleep(300 * time.Millisecond)
				}
				if request.SessionID == "hang" {
					select {}
				}
				if request.SessionID == "rejected" {
					response.OK = false
					response.Error = "private diagnostic must not escape"
				}
				response.Result = fmt.Sprintf(`{"viewer":%d,"pid":%d}`, *request.Viewer, os.Getpid())
			}
			encoded, _ := json.Marshal(response)
			output.Lock()
			fmt.Println(string(encoded))
			output.Unlock()
		}(request)
	}
	os.Exit(0)
}
