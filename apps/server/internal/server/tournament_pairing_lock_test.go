// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/tournament"
)

func addRunningPairingTournament(t *testing.T, handler *Handler, id string) *tournament.Tournament {
	t.Helper()
	event := addLiveTournament(t, handler, id, tournament.StatusRunning, time.Now().UTC())
	entry := handler.tournaments.entry(event.ID)
	if entry == nil {
		t.Fatal("tournament missing")
	}
	entry.mu.Lock()
	event.Rounds = []tournament.Round{{
		Number: 1,
		Pairings: []tournament.Pairing{{
			ID: "r1-m1", PlayerAID: "p-1", PlayerBID: "p-2",
		}},
	}}
	entry.mu.Unlock()
	return event
}

func pairingRoomID(event *tournament.Tournament) string {
	if event == nil || len(event.Rounds) == 0 || len(event.Rounds[0].Pairings) == 0 {
		return ""
	}
	return event.Rounds[0].Pairings[0].RoomID
}

func TestPairingRoomCleanupWaitsForTournamentOperationLock(t *testing.T) {
	handler, err := NewHandlerWithConfig(DefaultConfig())
	if err != nil {
		t.Fatalf("new handler: %v", err)
	}
	event := addRunningPairingTournament(t, handler, "LOCK-WAIT")
	host := testTournamentSession("host", "192.0.2.40")
	r, _, _, roomOperation, createErr := handler.hub.createTournamentRoom(
		"Pairing", protocol.FormatModern, protocol.DeckFormatModern, protocol.MatchBO3,
		protocol.CardLoadBackground, 2, event.ID, "r1-m1", "p-host", host)
	if createErr != nil {
		t.Fatalf("create pairing room: %v", createErr)
	}
	roomOperation.opMu.Unlock()

	entry := handler.tournaments.entry(event.ID)
	if entry == nil {
		t.Fatal("tournament missing")
	}
	entry.mu.Lock()
	event.Rounds[0].Pairings[0].RoomID = r.ID
	entry.mu.Unlock()

	entry.opMu.Lock()

	started := make(chan struct{})
	done := make(chan struct{})
	go func() {
		operation, lockErr := handler.hub.lockRoomOperation(r.ID)
		if lockErr != nil {
			t.Errorf("lock room: %v", lockErr)
			close(done)
			return
		}
		cleanup := handler.removeRoom(r)
		operation.opMu.Unlock()
		close(started)
		handler.commitPairingRoomCleanup(cleanup)
		close(done)
	}()

	select {
	case <-started:
	case <-time.After(2 * time.Second):
		t.Fatal("removeRoom blocked while the tournament operation lock was held")
	}

	select {
	case <-done:
		t.Fatal("pairing cleanup finished while tournament opMu was held")
	case <-time.After(100 * time.Millisecond):
	}

	entry.mu.Lock()
	if pairingRoomID(event) == "" {
		entry.mu.Unlock()
		t.Fatal("pairing RoomID was cleared without tournament opMu")
	}
	entry.mu.Unlock()

	entry.opMu.Unlock()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("pairing cleanup did not finish after tournament opMu was released")
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()
	if pairingRoomID(event) != "" {
		t.Fatalf("pairing RoomID = %q after cleanup", pairingRoomID(event))
	}
}

func TestPairingRoomCleanupDoesNotInvertLockOrder(t *testing.T) {
	handler, err := NewHandlerWithConfig(DefaultConfig())
	if err != nil {
		t.Fatalf("new handler: %v", err)
	}
	event := addRunningPairingTournament(t, handler, "LOCK-ORDER")
	host := testTournamentSession("host", "192.0.2.41")
	r, _, _, roomOperation, createErr := handler.hub.createTournamentRoom(
		"Pairing", protocol.FormatModern, protocol.DeckFormatModern, protocol.MatchBO3,
		protocol.CardLoadBackground, 2, event.ID, "r1-m1", "p-host", host)
	if createErr != nil {
		t.Fatalf("create pairing room: %v", createErr)
	}
	roomOperation.opMu.Unlock()

	entry := handler.tournaments.entry(event.ID)
	if entry == nil {
		t.Fatal("tournament missing")
	}
	entry.mu.Lock()
	event.Rounds[0].Pairings[0].RoomID = r.ID
	entry.mu.Unlock()

	roomHeld := make(chan struct{})
	tournamentReady := make(chan struct{})
	roomDone := make(chan struct{})
	tournamentDone := make(chan struct{})

	go func() {
		operation, lockErr := handler.hub.lockRoomOperation(r.ID)
		if lockErr != nil {
			t.Errorf("lock room: %v", lockErr)
			close(roomDone)
			return
		}
		close(roomHeld)
		<-tournamentReady
		cleanup := handler.removeRoom(r)
		operation.opMu.Unlock()
		handler.commitPairingRoomCleanup(cleanup)
		close(roomDone)
	}()

	select {
	case <-roomHeld:
	case <-time.After(2 * time.Second):
		t.Fatal("room worker did not acquire room opMu")
	}

	go func() {
		locked, lockErr := handler.tournaments.lockOperation(event.ID)
		if lockErr != nil {
			t.Errorf("lock tournament: %v", lockErr)
			close(tournamentDone)
			return
		}
		close(tournamentReady)
		operation, roomErr := handler.hub.lockRoomOperation(r.ID)
		if roomErr == nil {
			operation.opMu.Unlock()
		}
		locked.opMu.Unlock()
		close(tournamentDone)
	}()

	select {
	case <-tournamentDone:
	case <-time.After(2 * time.Second):
		t.Fatal("deadlock: tournament opMu then room opMu vs pairing-room cleanup")
	}
	select {
	case <-roomDone:
	case <-time.After(2 * time.Second):
		t.Fatal("pairing-room cleanup did not finish")
	}
}

func TestFailedPairingBindDoesNotClearUnboundRoomUnderTournamentLock(t *testing.T) {
	handler, err := NewHandlerWithConfig(DefaultConfig())
	if err != nil {
		t.Fatalf("new handler: %v", err)
	}
	event := addRunningPairingTournament(t, handler, "LOCK-DISCARD")
	host := testTournamentSession("host", "192.0.2.42")
	entry, err := handler.tournaments.lockOperation(event.ID)
	if err != nil {
		t.Fatalf("lock tournament: %v", err)
	}
	r, _, _, roomOperation, createErr := handler.hub.createTournamentRoom(
		"Pairing", protocol.FormatModern, protocol.DeckFormatModern, protocol.MatchBO3,
		protocol.CardLoadBackground, 2, event.ID, "r1-m1", "p-host", host)
	if createErr != nil {
		entry.opMu.Unlock()
		t.Fatalf("create pairing room: %v", createErr)
	}

	done := make(chan struct{})
	go func() {
		host.setRoom(nil)
		_ = handler.removeRoom(r)
		roomOperation.opMu.Unlock()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		entry.opMu.Unlock()
		t.Fatal("removeRoom deadlocked while tournament opMu was already held")
	}
	entry.opMu.Unlock()
	if handler.hub.FindRoom(r.ID) != nil {
		t.Fatal("unbound pairing room remained in the hub")
	}
}
