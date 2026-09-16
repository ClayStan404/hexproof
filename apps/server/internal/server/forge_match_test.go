// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
)

func TestForgePromptIDsDoNotRepeatAcrossGamesOrRuntimeReplacement(t *testing.T) {
	handler := &Handler{}
	old := forgeRoomGame{gameID: "old", promptState: &forgePromptState{}}
	oldID, err := handler.publicForgePromptID(old, 1)
	if err != nil {
		t.Fatal(err)
	}
	again, err := handler.publicForgePromptID(old, 1)
	if err != nil || again != oldID {
		t.Fatal("same pending prompt changed public identity during re-projection")
	}
	for _, label := range []string{"next-game", "restart", "replacement-process"} {
		next := forgeRoomGame{gameID: label, promptState: &forgePromptState{}}
		id, err := handler.publicForgePromptID(next, 1)
		if err != nil || id <= oldID || next.promptState.matches(oldID, 1) || !next.promptState.matches(id, 1) {
			t.Fatalf("reused an old decision after %s: old=%d new=%d err=%v", label, oldID, id, err)
		}
		oldID = id
	}
	var callers sync.WaitGroup
	ids := make(chan int64, 20)
	for range 20 {
		callers.Add(1)
		go func() {
			defer callers.Done()
			id, err := handler.publicForgePromptID(forgeRoomGame{promptState: &forgePromptState{}}, 1)
			if err != nil {
				t.Error(err)
			}
			ids <- id
		}()
	}
	callers.Wait()
	close(ids)
	seen := make(map[int64]bool)
	for id := range ids {
		if seen[id] || id <= oldID {
			t.Fatal("simultaneous rooms reused a public decision id")
		}
		seen[id] = true
	}
	handler.forgePromptSequence.Store(1<<53 - 1)
	if _, err := handler.publicForgePromptID(forgeRoomGame{promptState: &forgePromptState{}}, 1); err == nil {
		t.Fatal("unsafe JSON integer was published as a prompt id")
	}
}

func TestForgeBO3ReadyAndTimeoutUseFreshEngineNotManualState(t *testing.T) {
	handler, dir := newSupervisedForgeHandler(t)
	r, members := newSupervisedRoom(t, handler, "bo3", protocol.RulesModeForge, protocol.MinMainboardCards+1)
	old, _ := handler.forgeGame(r.ID)
	operation, err := handler.hub.lockRoomOperation(r.ID)
	if err != nil {
		t.Fatal(err)
	}
	r.MatchMode = protocol.MatchBO3
	_, err = handler.hub.CompleteRulesGame(r, 1)
	if err != nil {
		t.Fatal(err)
	}
	handler.finishForgeGame(r.ID, old, true)
	operation.opMu.Unlock()
	move, _ := protocol.NewEnvelope(protocol.TypeSideboardMove, protocol.SideboardMove{
		FromZone: protocol.SideboardZoneMain, ToZone: protocol.SideboardZoneSide,
		Name: "Forest", SetCode: "M21", CollectorNumber: "272",
	})
	if err := handler.handleSideboardMove(members[0], move); err != nil {
		t.Fatal(err)
	}
	ready, _ := protocol.NewEnvelope(protocol.TypeSideboardReady, protocol.SideboardReady{Ready: true})
	for _, member := range members {
		if err := handler.handleSideboardReady(member, ready); err != nil {
			t.Fatal(err)
		}
	}
	current, exists := handler.forgeGame(r.ID)
	if !exists || current.gameID == old.gameID || r.Game != nil || r.Score[1] != 1 {
		t.Fatal("BO3 ready did not start an independent Forge game")
	}
	assertFakeMatchStart(t, dir, current.gameID, 0, protocol.MinMainboardCards)
	// A stale public id cannot answer the new session's identically numbered
	// engine prompt. Rejection must happen before the helper receives anything.
	oldPublic, _ := handler.publicForgePromptID(old, 1)
	answer, _ := protocol.NewEnvelope(protocol.TypeRulesRespond,
		protocol.RulesRespond{PromptID: oldPublic, ResponseID: "$keep"})
	answer.ID = "stale-before-sideboard"
	drainForgeTestMessages(t, members)
	if err := handler.handleRulesRespond(members[0], answer); err != nil {
		t.Fatal(err)
	}
	response := receiveForgeSessionEnvelopes(t, members[0], 1)[0]
	var failure protocol.ErrorPayload
	if err := response.DecodePayload(&failure); err != nil || response.Type != protocol.TypeError ||
		failure.Code != protocol.ErrRulesActionRejected || response.ID != answer.ID {
		t.Fatalf("stale answer was not rejected: %+v", response)
	}
	operation, err = handler.hub.lockRoomOperation(r.ID)
	if err != nil {
		t.Fatal(err)
	}
	_, err = handler.hub.CompleteRulesGame(r, 0)
	if err != nil {
		t.Fatal(err)
	}
	handler.finishForgeGame(r.ID, current, true)
	_, err = handler.hub.MoveSideboard(members[0].ConnectionID, protocol.SideboardMove{
		FromZone: protocol.SideboardZoneSide, ToZone: protocol.SideboardZoneMain,
		Name: "Forest", SetCode: "M21", CollectorNumber: "272",
	}, r)
	if err != nil {
		t.Fatal(err)
	}
	_, err = handler.hub.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		locked.Game.Sideboard.Deadline = time.Now().Add(-time.Second)
		return room.Result{}, nil
	})
	if err != nil {
		t.Fatal(err)
	}
	operation.opMu.Unlock()
	timer := time.NewTimer(time.Hour)
	defer timer.Stop()
	handler.sideboardTimerMu.Lock()
	handler.sideboardTimers[r.ID] = timer
	handler.sideboardTimerMu.Unlock()
	handler.expireSideboard(r, timer)
	third, exists := handler.forgeGame(r.ID)
	if !exists || third.gameID == current.gameID || r.Game != nil || r.Score[0] != 1 || r.Score[1] != 1 {
		t.Fatal("timeout did not start game three with retained match score")
	}
	assertFakeMatchStart(t, dir, third.gameID, 1, protocol.MinMainboardCards)
}

func TestForgeBO3NextGameFailureReturnsWaitingWithoutFalseReadyAck(t *testing.T) {
	handler, dir := newSupervisedForgeHandler(t)
	r, members := newSupervisedRoom(t, handler, "failed-bo3", protocol.RulesModeForge)
	manual, manualMembers := newSupervisedRoom(t, handler, "unrelated", protocol.RulesModeManual)
	manualGame := manual.Game
	operation, err := handler.hub.lockRoomOperation(r.ID)
	if err != nil {
		t.Fatal(err)
	}
	r.MatchMode = protocol.MatchBO3
	if _, err := handler.hub.CompleteRulesGame(r, 1); err != nil {
		t.Fatal(err)
	}
	old, _ := handler.forgeGame(r.ID)
	handler.finishForgeGame(r.ID, old, true)
	operation.opMu.Unlock()
	if err := os.WriteFile(filepath.Join(dir, "fail-game"), []byte("synthetic failure"), 0600); err != nil {
		t.Fatal(err)
	}
	ready, _ := protocol.NewEnvelope(protocol.TypeSideboardReady, protocol.SideboardReady{Ready: true})
	ready.ID = "first-ready"
	if err := handler.handleSideboardReady(members[0], ready); err != nil {
		t.Fatal(err)
	}
	drainForgeTestMessages(t, members)
	ready.ID = "next-game-ready"
	if err := handler.handleSideboardReady(members[1], ready); err != nil {
		t.Fatal(err)
	}
	assertSupervisedPhase(t, handler, r, protocol.RoomPhaseWaiting)
	if r.Game != nil {
		t.Fatal("failed Forge transition created a manual game")
	}
	if _, exists := handler.forgeGame(r.ID); exists {
		t.Fatal("failed next game retained an engine handle")
	}
	for index, member := range members {
		events := receiveForgeSessionEnvelopes(t, member, 2)
		var failure protocol.ErrorPayload
		if events[0].Type != protocol.TypeRoomSnapshot || events[1].Type != protocol.TypeError ||
			events[1].DecodePayload(&failure) != nil || failure.Code != protocol.ErrRulesUnavailable ||
			strings.Contains(failure.Message, "private") {
			t.Fatal("failed transition did not publish a non-sensitive waiting-room failure")
		}
		if (index == 1 && events[1].ID != ready.ID) || (index == 0 && events[1].ID != "") {
			t.Fatal("transition failure did not correlate only the triggering command")
		}
		select {
		case raw := <-member.Send:
			t.Fatalf("failed transition published a success event: %s", raw)
		default:
		}
	}
	if manual.Game != manualGame || manual.Phase != protocol.RoomPhaseStarted {
		t.Fatal("Forge next-game failure changed an unrelated manual table")
	}
	for _, member := range manualMembers {
		select {
		case raw := <-member.Send:
			t.Fatalf("manual participant received Forge transition error: %s", raw)
		default:
		}
	}
}

func assertFakeMatchStart(t *testing.T, dir, id string, startingPlayer, mainCount int) {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(dir, "last-start.json"))
	if err != nil {
		t.Fatal(err)
	}
	var request forge.StartGameRequest
	if err := json.Unmarshal(data, &request); err != nil || request.GameID != id ||
		request.StartingPlayerIndex == nil || *request.StartingPlayerIndex != startingPlayer ||
		len(request.Players[0].Deck) != mainCount {
		t.Fatalf("wrong deck/first player sent to runtime: %+v %v", request, err)
	}
}

func drainForgeTestMessages(t *testing.T, members []*Session) {
	t.Helper()
	for _, member := range members {
		for {
			select {
			case raw := <-member.Send:
				envelope, err := protocol.ParseEnvelope(raw)
				if err != nil || envelope.Type == protocol.TypeError {
					t.Fatalf("unexpected setup event: %s %v", raw, err)
				}
			default:
				goto nextMember
			}
		}
	nextMember:
	}
}
