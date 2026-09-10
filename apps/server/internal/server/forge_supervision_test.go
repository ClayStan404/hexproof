// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
)

const supervisionHelperEnv = "HEXPROOF_FORGE_SUPERVISION_HELPER"

func TestForgeRuntimeExitAbortsItsGamesAndNewGamesRecover(t *testing.T) {
	handler, _ := newSupervisedForgeHandler(t)
	first, firstMembers := newSupervisedRoom(t, handler, "first", protocol.RulesModeForge)
	second, secondMembers := newSupervisedRoom(t, handler, "second", protocol.RulesModeForge)
	manual, manualMembers := newSupervisedRoom(t, handler, "manual", protocol.RulesModeManual)
	old, ok := handler.forgeGame(first.ID)
	if !ok {
		t.Fatal("first rules game was not tracked")
	}
	other, _ := handler.forgeGame(second.ID)
	if old.client != other.client {
		t.Fatal("test did not exercise two games sharing one process")
	}
	manualGame := manual.Game
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	// The helper exits itself while handling this private test directive.
	if err := old.client.SubmitAction(ctx, old.sessionID, json.RawMessage(`{"testExit":true}`)); err == nil {
		t.Fatal("unexpected process exit did not fail the active RPC")
	}
	for _, members := range [][]*Session{firstMembers, secondMembers} {
		for _, member := range members {
			assertForgeTermination(t, member)
		}
	}
	for _, r := range []*room.Room{first, second} {
		assertSupervisedPhase(t, handler, r, protocol.RoomPhaseWaiting)
		if _, exists := handler.forgeGame(r.ID); exists {
			t.Fatal("terminated rules game retained its engine session")
		}
	}
	assertSupervisedPhase(t, handler, manual, protocol.RoomPhaseStarted)
	if manual.Game != manualGame {
		t.Fatal("Forge exit changed manual game authority")
	}
	for _, member := range manualMembers {
		select {
		case message := <-member.Send:
			t.Fatalf("manual member received Forge failure: %s", message)
		default:
		}
	}
	startSupervisedRoom(t, handler, first, firstMembers)
	replacement, ok := handler.forgeGame(first.ID)
	if !ok || replacement.client == old.client || replacement.gameID == old.gameID {
		t.Fatal("new game did not receive a fresh runtime and game identity")
	}
	// A delayed notification from the old process must not terminate the new game.
	operation, err := handler.hub.lockRoomOperation(first.ID)
	if err != nil {
		t.Fatal(err)
	}
	handler.terminateForgeGame(first, old)
	operation.opMu.Unlock()
	assertSupervisedPhase(t, handler, first, protocol.RoomPhaseStarted)
	if _, ok := handler.forgeGame(first.ID); !ok {
		t.Fatal("old runtime notification removed the replacement game")
	}
}

func TestForgeProjectionFailureIsPrivateAndReturnsRoomsToWaiting(t *testing.T) {
	handler, _ := newSupervisedForgeHandler(t)
	first, firstMembers := newSupervisedRoom(t, handler, "first", protocol.RulesModeForge)
	_, secondMembers := newSupervisedRoom(t, handler, "second", protocol.RulesModeForge)
	operation, err := handler.hub.lockRoomOperation(first.ID)
	if err != nil {
		t.Fatal(err)
	}
	// This exercises the existing already-locked call site, not a second lock.
	handler.failClosedGameProjections(first, errors.New("private deck and engine exception"))
	operation.opMu.Unlock()
	for _, members := range [][]*Session{firstMembers, secondMembers} {
		for _, member := range members {
			assertForgeTermination(t, member)
		}
	}
}

func TestForgeIdleExitNotifiesPlayersAndSpectatorWithoutAnotherRPC(t *testing.T) {
	handler, dir := newSupervisedForgeHandler(t)
	r, members := newSupervisedRoom(t, handler, "idle", protocol.RulesModeForge)
	spectator := &Session{ConnectionID: "spectator", DisplayName: "Observer", Send: make(chan []byte, 8)}
	join, err := handler.hub.beginJoin(r.ID, "")
	if err != nil {
		t.Fatal(err)
	}
	_, _, err = handler.hub.joinRoom(join, spectator, true)
	join.opMu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	spectator.setRoom(r)
	handler.sessionsMu.Lock()
	handler.sessions[spectator.ConnectionID] = spectator
	handler.sessionsMu.Unlock()
	// This PID is recorded by this test's most recently started private child.
	data, err := os.ReadFile(filepath.Join(dir, "pid"))
	if err != nil {
		t.Fatal(err)
	}
	pid, err := strconv.Atoi(string(data))
	if err != nil {
		t.Fatal(err)
	}
	child, err := os.FindProcess(pid)
	if err != nil {
		t.Fatal(err)
	}
	if err := child.Kill(); err != nil {
		t.Fatal(err)
	}
	for _, member := range append(members, spectator) {
		assertForgeTermination(t, member)
	}
	assertSupervisedPhase(t, handler, r, protocol.RoomPhaseWaiting)
}

func TestForgeRuntimeStartupIsSingleFlightAndFailedStartsAreThrottled(t *testing.T) {
	handler, dir := newSupervisedForgeHandler(t)
	const count = 12
	clients := make(chan *forge.Client, count)
	var callers sync.WaitGroup
	for range count {
		callers.Add(1)
		go func() {
			defer callers.Done()
			ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
			defer cancel()
			client, err := handler.forgeClientForUse(ctx)
			if err != nil {
				t.Errorf("get shared runtime: %v", err)
			}
			clients <- client
		}()
	}
	callers.Wait()
	close(clients)
	var shared *forge.Client
	for client := range clients {
		if shared == nil {
			shared = client
		}
		if client == nil || client != shared {
			t.Fatal("concurrent startups did not share one runtime")
		}
	}
	if starts := supervisionStartCount(t, dir); starts != 2 {
		t.Fatalf("startup count = %d, want startup probe plus one shared runtime", starts)
	}
	shared.Invalidate()
	<-shared.Done()
	if err := os.WriteFile(filepath.Join(dir, "fail"), []byte("fail probe"), 0600); err != nil {
		t.Fatal(err)
	}
	for range count {
		if _, err := handler.forgeClientForUse(context.Background()); err == nil {
			t.Fatal("failed startup was accepted")
		}
	}
	if starts := supervisionStartCount(t, dir); starts != 3 {
		t.Fatalf("failed startups were not throttled: %d processes", starts)
	}
	if handler.forgeRulesAvailable() {
		t.Fatal("failed runtime advertised availability during retry cooldown")
	}
	if err := os.Remove(filepath.Join(dir, "fail")); err != nil {
		t.Fatal(err)
	}
	handler.forgeMu.Lock()
	handler.forgeRetryAfter = time.Now().Add(-time.Second)
	handler.forgeMu.Unlock()
	client, err := handler.forgeClientForUse(context.Background())
	if err != nil || client == nil || !client.Healthy() || client == shared {
		t.Fatalf("runtime recovery after cooldown: client = %p, error = %v", client, err)
	}
	if starts := supervisionStartCount(t, dir); starts != 4 {
		t.Fatalf("recovery startup count = %d, want 4", starts)
	}
}

func TestForgeCloseCancelsInFlightStartupAndPreventsRestart(t *testing.T) {
	handler, dir := newSupervisedForgeHandler(t)
	if err := os.WriteFile(filepath.Join(dir, "hang"), []byte("hang probe"), 0600); err != nil {
		t.Fatal(err)
	}
	result := make(chan error, 1)
	go func() {
		_, err := handler.forgeClientForUse(context.Background())
		result <- err
	}()
	deadline := time.Now().Add(2 * time.Second)
	for supervisionStartCount(t, dir) != 2 {
		if time.Now().After(deadline) {
			t.Fatal("startup process did not begin")
		}
		time.Sleep(5 * time.Millisecond)
	}
	closed := make(chan error, 1)
	go func() { closed <- handler.Close() }()
	select {
	case err := <-closed:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("Close did not cancel the hanging startup")
	}
	if err := <-result; err == nil {
		t.Fatal("startup returned a client after Handler.Close")
	}
	if _, err := handler.forgeClientForUse(context.Background()); err == nil {
		t.Fatal("closed handler restarted Forge")
	}
	if handler.forgeRulesAvailable() {
		t.Fatal("closed handler advertises Forge availability")
	}
}

func newSupervisedForgeHandler(t *testing.T) (*Handler, string) {
	t.Helper()
	dir := t.TempDir()
	config := DefaultConfig()
	config.ForgeRuntime = &forge.ProcessConfig{
		Command: os.Args[0], Args: []string{"-test.run=^TestForgeSupervisionHelper$"},
		Env: []string{supervisionHelperEnv + "=" + dir}, StartTimeout: 5 * time.Second,
	}
	handler, err := NewHandlerWithConfig(config)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = handler.Close() })
	return handler, dir
}

func newSupervisedRoom(t *testing.T, handler *Handler, name, mode string, mainCount ...int) (*room.Room, []*Session) {
	t.Helper()
	members := []*Session{
		{ConnectionID: name + "-host", DisplayName: "Alice", Send: make(chan []byte, 32)},
		{ConnectionID: name + "-guest", DisplayName: "Bob", Send: make(chan []byte, 32)},
	}
	r, _, _, entry, err := handler.hub.CreateRoomWithRulesMode(name, protocol.FormatModern,
		protocol.DeckFormatCustom, protocol.MatchBO1, protocol.CardLoadBackground,
		mode, 2, true, false, "", members[0])
	if err != nil {
		t.Fatal(err)
	}
	entry.opMu.Unlock()
	join, err := handler.hub.beginJoin(r.ID, "")
	if err != nil {
		t.Fatal(err)
	}
	_, _, err = handler.hub.joinRoom(join, members[1], false)
	join.opMu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	for _, member := range members {
		member.setRoom(r)
		handler.sessionsMu.Lock()
		handler.sessions[member.ConnectionID] = member
		handler.sessionsMu.Unlock()
		deck := protocol.DeckSelect{Name: "Fixture deck", Format: protocol.FormatModern,
			DeckFormat: protocol.DeckFormatCustom, Mainboard: []protocol.DeckCard{
				{Name: "Forest", Count: protocol.MinMainboardCards, SetCode: "M21", CollectorNumber: "272"},
			}}
		if len(mainCount) > 0 {
			deck.Mainboard[0].Count = mainCount[0]
		}
		if _, err := handler.hub.SelectDeck(member.ConnectionID, deck, r); err != nil {
			t.Fatal(err)
		}
	}
	startSupervisedRoom(t, handler, r, members)
	return r, members
}

func startSupervisedRoom(t *testing.T, handler *Handler, r *room.Room, members []*Session) {
	t.Helper()
	operation, err := handler.hub.lockRoomOperation(r.ID)
	if err != nil {
		t.Fatal(err)
	}
	defer operation.opMu.Unlock()
	for _, member := range members {
		result, err := handler.hub.SetReady(member.ConnectionID, true, r)
		if err != nil {
			t.Fatal(err)
		}
		if result.StartRulesGame {
			if _, err := handler.startForgeGame(r); err != nil {
				t.Fatal(err)
			}
		}
	}
}

func assertSupervisedPhase(t *testing.T, handler *Handler, r *room.Room, expected string) {
	t.Helper()
	entry := handler.hub.roomEntryFor(r.ID)
	entry.mu.Lock()
	defer entry.mu.Unlock()
	if r.Phase != expected {
		t.Fatalf("room phase = %s, want %s", r.Phase, expected)
	}
}

func assertForgeTermination(t *testing.T, member *Session) {
	t.Helper()
	envelopes := receiveForgeSessionEnvelopes(t, member, 2)
	var failure protocol.ErrorPayload
	if envelopes[0].Type != protocol.TypeError || envelopes[0].DecodePayload(&failure) != nil ||
		failure.Code != protocol.ErrRulesUnavailable || envelopes[0].ID != "" ||
		!strings.Contains(failure.Message, "aborted") || strings.Contains(failure.Message, "private") {
		t.Fatalf("unexpected public termination: %+v", failure)
	}
	if envelopes[1].Type != protocol.TypeRoomSnapshot ||
		!strings.Contains(string(envelopes[1].Payload), `"phase":"waiting"`) {
		t.Fatal("rules failure did not publish a waiting-room snapshot")
	}
	member.closeMu.Lock()
	closed := member.closed
	member.closeMu.Unlock()
	if closed || member.Room() == nil {
		t.Fatal("rules termination disconnected the member instead of preserving the waiting room")
	}
}

func supervisionStartCount(t *testing.T, dir string) int {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(dir, "starts"))
	if err != nil {
		t.Fatal(err)
	}
	return strings.Count(string(data), "start\n")
}

func TestForgeSupervisionHelper(t *testing.T) {
	dir := os.Getenv(supervisionHelperEnv)
	if dir == "" {
		return
	}
	starts, err := os.OpenFile(filepath.Join(dir, "starts"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if err != nil {
		t.Fatal(err)
	}
	_, _ = starts.WriteString("start\n")
	_ = starts.Close()
	if err := os.WriteFile(filepath.Join(dir, "pid"), []byte(strconv.Itoa(os.Getpid())), 0600); err != nil {
		t.Fatal(err)
	}
	scanner := bufio.NewScanner(os.Stdin)
	encoder := json.NewEncoder(os.Stdout)
	games := make(map[string]string)
	for scanner.Scan() {
		var request struct {
			Command   string `json:"command"`
			SessionID string `json:"sessionId"`
			Payload   string `json:"payload"`
			Viewer    int    `json:"viewer"`
		}
		if err := json.Unmarshal(scanner.Bytes(), &request); err != nil {
			t.Fatal(err)
		}
		if request.Command == "quit" {
			return
		}
		result := ""
		switch request.Command {
		case "reset":
			if _, err := os.Stat(filepath.Join(dir, "hang")); err == nil {
				time.Sleep(time.Hour)
			}
			if _, err := os.Stat(filepath.Join(dir, "fail")); err == nil {
				_ = encoder.Encode(map[string]any{"ok": false, "error": "private runtime startup error"})
				continue
			}
		case "startGame":
			if _, err := os.Stat(filepath.Join(dir, "fail-game")); err == nil {
				_ = encoder.Encode(map[string]any{"ok": false, "error": "private next-game deck failure"})
				continue
			}
			var start forge.StartGameRequest
			if err := json.Unmarshal([]byte(request.Payload), &start); err != nil {
				t.Fatal(err)
			}
			games[start.GameID] = start.GameID
			if err := os.WriteFile(filepath.Join(dir, "last-start.json"), []byte(request.Payload), 0600); err != nil {
				t.Fatal(err)
			}
			result = fmt.Sprintf(`{"sessionId":%q,"playerIndexes":[0,1]}`, start.GameID)
		case "getSnapshot":
			data, _ := json.Marshal(forgeLifecycleSnapshot(games[request.SessionID], request.Viewer, -1))
			result = string(data)
		case "getPrompt":
			result = `{"promptId":1,"decidingPlayerId":"player-0","input":{"type":"mulligan","mulliganCount":0}}`
		case "getGameOver":
			result = "false"
		case "submitAction":
			if request.Payload == `{"testExit":true}` {
				os.Exit(23)
			}
		case "endGame", "abortGame":
			delete(games, request.SessionID)
		}
		if err := encoder.Encode(map[string]any{"ok": true, "result": result}); err != nil {
			return
		}
	}
}
