// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
)

func TestForgeCapacityBoundsConcurrentStartsAndReleasesReapedChildren(t *testing.T) {
	const capacity, attempts = 2, 12
	handler, dir := newSupervisedForgeHandler(t, capacity)
	var callers sync.WaitGroup
	clients := make(chan *forge.Client, attempts)
	for range attempts {
		callers.Add(1)
		go func() {
			defer callers.Done()
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			client, err := handler.startForgeRuntime(ctx, "")
			if err != nil && !errors.Is(err, errForgeCapacity) {
				t.Errorf("unexpected startup error: %v", err)
			}
			if err == nil {
				clients <- client
			}
		}()
	}
	callers.Wait()
	close(clients)
	if len(clients) != capacity || supervisionStartCount(t, dir) != capacity+1 {
		t.Fatalf("capacity %d accepted %d games and spawned %d processes including probe",
			capacity, len(clients), supervisionStartCount(t, dir))
	}
	if !handler.forgeRulesAvailable() {
		t.Fatal("capacity exhaustion disabled the Forge capability")
	}
	for client := range clients {
		if err := client.Close(); err != nil {
			t.Fatal(err)
		}
		// No sleep: Done, not watcher scheduling, releases the old slot.
		if _, err := handler.startForgeRuntime(context.Background(), ""); err != nil {
			t.Fatalf("reaped child still consumes capacity: %v", err)
		}
	}
	if supervisionStartCount(t, dir) != 2*capacity+1 {
		t.Fatal("a freed slot did not start an independent replacement process")
	}
}

func TestForgeCapacityCountsStartupAndRecoversAfterCancellation(t *testing.T) {
	handler, dir := newSupervisedForgeHandler(t)
	if err := os.WriteFile(filepath.Join(dir, "hang"), nil, 0600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	result := make(chan error, 1)
	go func() {
		_, err := handler.startForgeRuntime(ctx, "")
		result <- err
	}()
	waitForgeCapacityCondition(t, func() bool { return supervisionStartCount(t, dir) == 2 })
	bounded, stop := context.WithTimeout(context.Background(), time.Second)
	defer stop()
	if _, err := handler.startForgeRuntime(bounded, ""); !errors.Is(err, errForgeCapacity) {
		t.Fatalf("in-flight startup did not reserve capacity: %v", err)
	}
	if supervisionStartCount(t, dir) != 2 {
		t.Fatal("capacity rejection forked another process")
	}
	cancel()
	select {
	case err := <-result:
		if err == nil {
			t.Fatal("canceled startup returned a live runtime")
		}
	case <-time.After(3 * time.Second):
		t.Fatal("canceled startup did not reap its child")
	}
	if err := os.Remove(filepath.Join(dir, "hang")); err != nil {
		t.Fatal(err)
	}
	handler.forgeMu.Lock()
	handler.forgeRetryAfter = time.Time{}
	handler.forgeMu.Unlock()
	if _, err := handler.startForgeRuntime(context.Background(), ""); err != nil {
		t.Fatalf("failed startup leaked its slot: %v", err)
	}
}

func TestForgeCapacityCountsClosingChildrenUntilExit(t *testing.T) {
	handler, dir := newSupervisedForgeHandler(t)
	client, err := handler.startForgeRuntime(context.Background(), "")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "hang-quit"), nil, 0600); err != nil {
		t.Fatal(err)
	}
	closed := make(chan error, 1)
	go func() { closed <- client.Close() }()
	waitForgeCapacityCondition(t, func() bool {
		_, err := os.Stat(filepath.Join(dir, "quitting"))
		return err == nil
	})
	if _, err := handler.startForgeRuntime(context.Background(), ""); !errors.Is(err, errForgeCapacity) {
		t.Fatalf("closing child released capacity before exiting: %v", err)
	}
	select {
	case <-closed:
	case <-time.After(4 * time.Second):
		t.Fatal("stuck quit was not forcibly reaped")
	}
	if err := os.Remove(filepath.Join(dir, "hang-quit")); err != nil {
		t.Fatal(err)
	}
	if _, err := handler.startForgeRuntime(context.Background(), ""); err != nil {
		t.Fatalf("reaped closing process leaked capacity: %v", err)
	}
}

func TestForgeCapacityRejectsStartWithoutAffectingOtherGames(t *testing.T) {
	for _, loadMode := range []string{protocol.CardLoadBackground, protocol.CardLoadPreload} {
		t.Run(loadMode, func(t *testing.T) {
			handler, dir := newSupervisedForgeHandler(t)
			active, activeMembers := newSupervisedRoom(t, handler, "active", protocol.RulesModeForge)
			game, _ := handler.forgeGame(active.ID)
			manual, manualMembers := newSupervisedRoom(t, handler, "manual", protocol.RulesModeManual)
			waiting, members := newWaitingSupervisedRoom(t, handler, "waiting", protocol.RulesModeForge)
			waiting.CardLoadMode = loadMode
			ready, _ := protocol.NewEnvelope(protocol.TypePlayerReady, protocol.PlayerReady{Ready: true})
			for _, member := range members {
				if err := handler.handlePlayerReady(member, ready); err != nil {
					t.Fatal(err)
				}
			}
			if loadMode == protocol.CardLoadPreload {
				loaded, _ := protocol.NewEnvelope(protocol.TypeClientLoadComplete,
					protocol.ClientLoadComplete{LoadID: waiting.LoadID})
				for _, member := range members {
					if err := handler.handleClientLoadComplete(member, loaded); err != nil {
						t.Fatal(err)
					}
				}
			}
			assertSupervisedPhase(t, handler, waiting, protocol.RoomPhaseWaiting)
			for _, seat := range waiting.Seats {
				if seat.Deck == nil || seat.Ready {
					t.Fatal("capacity rejection lost a deck or retained readiness")
				}
			}
			found := false
			for _, member := range members {
				for len(member.Send) > 0 {
					var event protocol.Envelope
					if err := json.Unmarshal(<-member.Send, &event); err != nil {
						t.Fatal(err)
					}
					if event.Type == protocol.TypeError {
						var failure protocol.ErrorPayload
						if event.DecodePayload(&failure) != nil || failure.Code != protocol.ErrServerLimit ||
							!strings.Contains(failure.Message, "Forge game capacity is full") {
							t.Fatalf("unexpected capacity failure: %+v", failure)
						}
						found = true
					}
				}
			}
			if !found || supervisionStartCount(t, dir) != 2 || !game.client.Healthy() {
				t.Fatal("overflow was not rejected before launch while preserving the active game")
			}
			assertSupervisedPhase(t, handler, active, protocol.RoomPhaseStarted)
			assertSupervisedPhase(t, handler, manual, protocol.RoomPhaseStarted)
			assertNoForgeFailure(t, activeMembers)
			assertNoForgeFailure(t, manualMembers)
			handler.abortForgeGame(active.ID)
			waiting.CardLoadMode = protocol.CardLoadBackground
			startSupervisedRoom(t, handler, waiting, members)
			assertSupervisedPhase(t, handler, waiting, protocol.RoomPhaseStarted)
		})
	}
}

func TestForgeCapacityPreservesBO3AndRestartReservations(t *testing.T) {
	handler, _ := newSupervisedForgeHandler(t)
	r, members := newSupervisedRoom(t, handler, "bo3-capacity", protocol.RulesModeForge)
	r.MatchMode = protocol.MatchBO3
	game, _ := handler.forgeGame(r.ID)
	result, err := handler.hub.CompleteRulesGame(r, 1)
	if err != nil || result.SideboardDeadline.IsZero() {
		t.Fatalf("game did not enter BO3 sideboarding: %v", err)
	}
	handler.finishForgeGame(r.ID, game, true)
	if _, err := handler.startForgeRuntime(context.Background(), "other-room"); !errors.Is(err, errForgeCapacity) {
		t.Fatalf("another room took a sideboarding match's slot: %v", err)
	}
	ready, _ := protocol.NewEnvelope(protocol.TypeSideboardReady, protocol.SideboardReady{Ready: true})
	for _, member := range members {
		if err := handler.handleSideboardReady(member, ready); err != nil {
			t.Fatal(err)
		}
	}
	next, exists := handler.forgeGame(r.ID)
	if !exists || next.client == game.client || r.Score[1] != 1 {
		t.Fatal("reserved next game lost its runtime or score")
	}
	// A restart keeps the slot while the old process exits, then consumes it
	// for a fresh game. No other room can use the cleanup/startup gap.
	handler.closeForgeGame(r.ID, true)
	if _, err := handler.startForgeRuntime(context.Background(), "other-room"); !errors.Is(err, errForgeCapacity) {
		t.Fatalf("another room took a restarting game's slot: %v", err)
	}
	if _, err := handler.startForgeGame(r); err != nil {
		t.Fatalf("reserved restart failed: %v", err)
	}
	last, _ := handler.forgeGame(r.ID)
	result, err = handler.hub.CompleteRulesGame(r, 1)
	if err != nil || !result.SideboardDeadline.IsZero() {
		t.Fatalf("BO3 did not finish: %v", err)
	}
	handler.finishForgeGame(r.ID, last, false)
	if _, err := handler.startForgeRuntime(context.Background(), "other-room"); err != nil {
		t.Fatalf("finished BO3 match leaked capacity: %v", err)
	}
}

func TestForgeCapacityReleasesAbandonedSideboard(t *testing.T) {
	handler, _ := newSupervisedForgeHandler(t)
	r, _ := newSupervisedRoom(t, handler, "abandoned", protocol.RulesModeForge)
	game, _ := handler.forgeGame(r.ID)
	handler.finishForgeGame(r.ID, game, true)
	handler.abortForgeGame(r.ID)
	if _, err := handler.startForgeRuntime(context.Background(), "other-room"); err != nil {
		t.Fatalf("abandoned between-game reservation leaked capacity: %v", err)
	}
}

func TestForgeCapacityReleasesFailedReservedTransition(t *testing.T) {
	handler, dir := newSupervisedForgeHandler(t)
	r, _ := newSupervisedRoom(t, handler, "failed-next-game", protocol.RulesModeForge)
	game, _ := handler.forgeGame(r.ID)
	handler.finishForgeGame(r.ID, game, true)
	if err := os.WriteFile(filepath.Join(dir, "fail-game"), nil, 0600); err != nil {
		t.Fatal(err)
	}
	if _, ok := handler.prepareForgeTransition(r, nil, ""); ok {
		t.Fatal("unsupported next game was accepted")
	}
	assertSupervisedPhase(t, handler, r, protocol.RoomPhaseWaiting)
	if err := os.Remove(filepath.Join(dir, "fail-game")); err != nil {
		t.Fatal(err)
	}
	if _, err := handler.startForgeRuntime(context.Background(), "other-room"); err != nil {
		t.Fatalf("failed reserved next game leaked capacity: %v", err)
	}
}

func waitForgeCapacityCondition(t *testing.T, condition func() bool) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for !condition() {
		if time.Now().After(deadline) {
			t.Fatal("Forge helper did not reach the expected process state")
		}
		time.Sleep(5 * time.Millisecond)
	}
}
