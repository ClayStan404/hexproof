// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func TestSideboardCompletedStopsAndRemovesExpirationTimer(t *testing.T) {
	handler, r, host, guest := newHandlerSideboardRoom(t)
	handler.scheduleSideboardExpiration(r, time.Now().Add(time.Hour))

	handler.sideboardTimerMu.Lock()
	timer := handler.sideboardTimers[r.ID]
	handler.sideboardTimerMu.Unlock()
	if timer == nil {
		t.Fatal("sideboard expiration timer was not scheduled")
	}
	t.Cleanup(func() { timer.Stop() })

	handleSideboardReadyForTest(t, handler, host, "ready-host")
	handleSideboardReadyForTest(t, handler, guest, "ready-guest")

	handler.sideboardTimerMu.Lock()
	_, retained := handler.sideboardTimers[r.ID]
	handler.sideboardTimerMu.Unlock()
	if retained {
		t.Fatal("completed sideboard retained its expiration timer")
	}
	if timer.Stop() {
		t.Fatal("completed sideboard timer remained active")
	}
	if r.Game == nil || r.Game.Number != 2 || r.Game.Sideboard != nil {
		t.Fatalf("completed sideboard state = %+v, want game 2 without sideboarding", r.Game)
	}
}

func TestStartedSideboardExpirationCannotAdvanceLaterSideboard(t *testing.T) {
	handler, r, host, guest := newHandlerSideboardRoom(t)
	timer := time.NewTimer(time.Hour)
	handler.sideboardTimerMu.Lock()
	handler.sideboardTimers[r.ID] = timer
	handler.sideboardTimerMu.Unlock()
	t.Cleanup(func() { timer.Stop() })

	operation, err := handler.hub.lockRoomOperation(r.ID)
	if err != nil {
		t.Fatalf("lockRoomOperation: %v", err)
	}
	released := false
	defer func() {
		if !released {
			operation.opMu.Unlock()
		}
	}()

	started := make(chan struct{})
	done := make(chan struct{})
	go func() {
		close(started)
		handler.expireSideboard(r, timer)
		close(done)
	}()
	<-started
	select {
	case <-done:
		t.Fatal("sideboard expiration did not block on the room operation")
	default:
	}

	if _, err := handler.hub.SetSideboardReady(host.ConnectionID, true, r); err != nil {
		t.Fatalf("SetSideboardReady(host): %v", err)
	}
	completed, err := handler.hub.SetSideboardReady(guest.ConnectionID, true, r)
	if err != nil {
		t.Fatalf("SetSideboardReady(guest): %v", err)
	}
	if len(completed.Broadcast) != 1 ||
		completed.Broadcast[0].Type != protocol.TypeSideboardCompleted {
		t.Fatalf("completed sideboard broadcast = %+v", completed.Broadcast)
	}
	handler.cancelSideboardExpiration(r.ID)

	if _, err := handler.hub.Concede(guest.ConnectionID, r); err != nil {
		t.Fatalf("Concede(game 2): %v", err)
	}
	operation.mu.Lock()
	r.Game.Sideboard.Deadline = time.Now().Add(-time.Second)
	operation.mu.Unlock()

	released = true
	operation.opMu.Unlock()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("sideboard expiration did not exit after cancellation")
	}
	if r.Game == nil || r.Game.Number != 2 || r.Game.Sideboard == nil {
		t.Fatalf("stale expiration advanced later sideboard: game=%+v", r.Game)
	}
	if len(host.Send) != 0 || len(guest.Send) != 0 {
		t.Fatalf("stale expiration sent messages: host=%d guest=%d",
			len(host.Send), len(guest.Send))
	}
}

func TestCancelSideboardExpirationIsIdempotent(t *testing.T) {
	handler := NewHandler()
	timer := time.NewTimer(time.Hour)
	handler.sideboardTimerMu.Lock()
	handler.sideboardTimers["ROOM"] = timer
	handler.sideboardTimerMu.Unlock()

	handler.cancelSideboardExpiration("ROOM")
	handler.cancelSideboardExpiration("ROOM")

	if timer.Stop() {
		t.Fatal("cancelled timer remained active")
	}
}

func newHandlerSideboardRoom(t *testing.T) (*Handler, *room.Room, *Session, *Session) {
	t.Helper()
	handler := NewHandler()
	host := newManualJoinTestSession("sideboard-host", "Alice")
	guest := newManualJoinTestSession("sideboard-guest", "Bob")
	handler.registerSession(host)
	handler.registerSession(guest)
	t.Cleanup(func() {
		handler.unregisterSession(host)
		handler.unregisterSession(guest)
	})

	r, _, _, operation, err := handler.hub.CreateRoom(
		"BO3 table", protocol.FormatModern, protocol.MatchBO3,
		protocol.CardLoadBackground, 2, true, false, "", host)
	if err != nil {
		t.Fatalf("CreateRoom: %v", err)
	}
	operation.opMu.Unlock()

	joinOperation, err := handler.hub.beginJoin(r.ID, "")
	if err != nil {
		t.Fatalf("beginJoin: %v", err)
	}
	if _, _, err := handler.hub.joinRoom(joinOperation, guest, false); err != nil {
		joinOperation.opMu.Unlock()
		t.Fatalf("joinRoom: %v", err)
	}
	joinOperation.opMu.Unlock()

	for _, session := range []*Session{host, guest} {
		deck := protocol.DeckSelect{
			Name:       session.DisplayName + " deck",
			Format:     protocol.FormatModern,
			DeckFormat: protocol.DeckFormatCustom,
			Mainboard: []protocol.DeckCard{{
				Name: "Lightning Bolt", Count: 10,
				SetCode: "M11", CollectorNumber: "149",
			}},
		}
		if _, err := handler.hub.SelectDeck(session.ConnectionID, deck, r); err != nil {
			t.Fatalf("SelectDeck(%s): %v", session.ConnectionID, err)
		}
		if _, err := handler.hub.SetReady(session.ConnectionID, true, r); err != nil {
			t.Fatalf("SetReady(%s): %v", session.ConnectionID, err)
		}
	}
	if r.Game == nil || r.Game.Number != 1 {
		t.Fatalf("started game = %+v, want game 1", r.Game)
	}
	conceded, err := handler.hub.Concede(host.ConnectionID, r)
	if err != nil {
		t.Fatalf("Concede: %v", err)
	}
	if conceded.SideboardDeadline.IsZero() || r.Game.Sideboard == nil {
		t.Fatalf("concede result = %+v game=%+v, want sideboard deadline", conceded, r.Game)
	}
	return handler, r, host, guest
}

func handleSideboardReadyForTest(t *testing.T, handler *Handler, session *Session, id string) {
	t.Helper()
	request, err := protocol.NewEnvelope(
		protocol.TypeSideboardReady, protocol.SideboardReady{Ready: true})
	if err != nil {
		t.Fatalf("NewEnvelope(sideboard.ready): %v", err)
	}
	request.ID = id
	if err := handler.handleSideboardReady(session, request); err != nil {
		t.Fatalf("handleSideboardReady(%s): %v", session.ConnectionID, err)
	}
}
