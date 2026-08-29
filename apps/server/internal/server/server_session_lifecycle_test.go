// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/buildinfo"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"

	"github.com/coder/websocket"
)

func TestHandshakeValidation(t *testing.T) {
	srv, _ := newTestServer(t)
	client := dial(t, srv)
	defer client.close()

	missingID, _ := protocol.NewEnvelope(protocol.TypeSessionHello, protocol.SessionHello{
		DisplayName: "Alice", Protocol: protocol.ProtocolVersion,
	})
	client.send(missingID)
	errEnv := client.recvType(protocol.TypeError)
	var ep protocol.ErrorPayload
	_ = errEnv.DecodePayload(&ep)
	if ep.Code != protocol.ErrInvalidMessage {
		t.Fatalf("missing hello id code = %q, want %q", ep.Code, protocol.ErrInvalidMessage)
	}

	wrongVersion, _ := protocol.NewEnvelope(protocol.TypeSessionHello, protocol.SessionHello{
		DisplayName: "Alice", Protocol: "hexproof.v999",
	})
	wrongVersion.ID = "wrong-version"
	client.send(wrongVersion)
	errEnv = client.recvType(protocol.TypeError)
	_ = errEnv.DecodePayload(&ep)
	if ep.Code != protocol.ErrInvalidMessage || errEnv.ID != wrongVersion.ID {
		t.Fatalf("wrong protocol response = type %q id %q code %q", errEnv.Type, errEnv.ID, ep.Code)
	}

	missingClientVersion, _ := protocol.NewEnvelope(protocol.TypeSessionHello,
		protocol.SessionHello{
			DisplayName: "Alice",
			Protocol:    protocol.ProtocolVersion,
		})
	missingClientVersion.ID = "missing-client-version"
	client.send(missingClientVersion)
	errEnv = client.recvType(protocol.TypeError)
	_ = errEnv.DecodePayload(&ep)
	if ep.Code != protocol.ErrClientVersionMismatch ||
		ep.RequiredVersion != buildinfo.Version ||
		ep.ClientVersion != "" ||
		!strings.Contains(ep.Message, "download and install Hexproof") ||
		errEnv.ID != missingClientVersion.ID {
		t.Fatalf("missing client version response = id %q payload %+v",
			errEnv.ID, ep)
	}

	wrongClientVersion, _ := protocol.NewEnvelope(protocol.TypeSessionHello,
		protocol.SessionHello{
			DisplayName:   "Alice",
			ClientVersion: "99.0.0",
			Protocol:      protocol.ProtocolVersion,
		})
	wrongClientVersion.ID = "wrong-client-version"
	client.send(wrongClientVersion)
	errEnv = client.recvType(protocol.TypeError)
	_ = errEnv.DecodePayload(&ep)
	if ep.Code != protocol.ErrClientVersionMismatch ||
		ep.RequiredVersion != buildinfo.Version ||
		ep.ClientVersion != "99.0.0" ||
		!strings.Contains(ep.Message, "download and install Hexproof") ||
		errEnv.ID != wrongClientVersion.ID {
		t.Fatalf("wrong client version response = id %q payload %+v",
			errEnv.ID, ep)
	}

	longName, _ := protocol.NewEnvelope(protocol.TypeSessionHello, protocol.SessionHello{
		DisplayName: strings.Repeat("名", protocol.MaxDisplayNameRunes+1),
		Protocol:    protocol.ProtocolVersion,
	})
	longName.ID = "long-name"
	client.send(longName)
	errEnv = client.recvType(protocol.TypeError)
	_ = errEnv.DecodePayload(&ep)
	if ep.Code != protocol.ErrInvalidMessage || errEnv.ID != longName.ID {
		t.Fatalf("long name response = type %q id %q code %q", errEnv.Type, errEnv.ID, ep.Code)
	}

	controlName, _ := protocol.NewEnvelope(protocol.TypeSessionHello, protocol.SessionHello{
		DisplayName: "Alice\a", Protocol: protocol.ProtocolVersion,
	})
	controlName.ID = "control-name"
	client.send(controlName)
	errEnv = client.recvType(protocol.TypeError)
	_ = errEnv.DecodePayload(&ep)
	if ep.Code != protocol.ErrInvalidMessage || errEnv.ID != controlName.ID {
		t.Fatalf("control name response = type %q id %q code %q",
			errEnv.Type, errEnv.ID, ep.Code)
	}

	client.hello("  Alice  ")
	secondHello, _ := protocol.NewEnvelope(protocol.TypeSessionHello, protocol.SessionHello{
		DisplayName: "Mallory", Protocol: protocol.ProtocolVersion,
	})
	secondHello.ID = "second-hello"
	client.send(secondHello)
	errEnv = client.recvType(protocol.TypeError)
	_ = errEnv.DecodePayload(&ep)
	if ep.Code != protocol.ErrInvalidMessage || errEnv.ID != secondHello.ID {
		t.Fatalf("second hello response = type %q id %q code %q", errEnv.Type, errEnv.ID, ep.Code)
	}

	invalidRoom, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{
		Name: "  ", Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatCustom,
		MatchMode:       protocol.MatchBO1,
		AllowSpectators: true,
	})
	invalidRoom.ID = "invalid-room"
	client.send(invalidRoom)
	errEnv = client.recvType(protocol.TypeError)
	_ = errEnv.DecodePayload(&ep)
	if ep.Code != protocol.ErrInvalidMessage || errEnv.ID != invalidRoom.ID {
		t.Fatalf("invalid room response = type %q id %q code %q", errEnv.Type, errEnv.ID, ep.Code)
	}

	controlRoom, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{
		Name: "Room\a", Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatCustom,
		MatchMode:       protocol.MatchBO1,
		AllowSpectators: true,
	})
	controlRoom.ID = "control-room"
	client.send(controlRoom)
	errEnv = client.recvType(protocol.TypeError)
	_ = errEnv.DecodePayload(&ep)
	if ep.Code != protocol.ErrInvalidMessage || errEnv.ID != controlRoom.ID {
		t.Fatalf("control room response = type %q id %q code %q",
			errEnv.Type, errEnv.ID, ep.Code)
	}

	_, _ = client.createRoom("Room", protocol.FormatModern, 2, true, "")
	snapshot := client.recvType(protocol.TypeRoomSnapshot)
	var state protocol.RoomSnapshot
	if err := snapshot.DecodePayload(&state); err != nil {
		t.Fatalf("decode snapshot: %v", err)
	}
	if state.Seats[0].DisplayName != "Alice" {
		t.Fatalf("host display name = %q, want original handshake name Alice", state.Seats[0].DisplayName)
	}
}

func TestRequiredRequestIDs(t *testing.T) {
	required := []string{
		protocol.TypeSessionHello,
		protocol.TypeRoomCreate,
		protocol.TypeRoomJoin,
		protocol.TypeRoomKick,
		protocol.TypeRoomDisband,
		protocol.TypeDeckSelect,
		protocol.TypePlayerReady,
		protocol.TypeClientLoadComplete,
		protocol.TypeGameDraw,
		protocol.TypeGameShuffleLibrary,
		protocol.TypeGameMulligan,
		protocol.TypeGameDiscardHand,
		protocol.TypeGameMoveCard,
		protocol.TypeGameMoveCards,
		protocol.TypeGameMoveLibraryCards,
		protocol.TypeGameSetCardFace,
		protocol.TypeGameSetCardCounter,
		protocol.TypeGameSetPhase,
		protocol.TypeGameSetResponseStatus,
		protocol.TypeGameSetCounter,
		protocol.TypeGameSetCounterCount,
		protocol.TypeGameConcede,
		protocol.TypeGameReturnToRoom,
		protocol.TypeGameSay,
		protocol.TypeGameNextTurn,
		protocol.TypeGameReveal,
		protocol.TypeGameRecallRevealed,
		protocol.TypeGameDumpZone,
		protocol.TypeGameRespondZoneDump,
		protocol.TypeGameSearchLibrary,
		protocol.TypeGameReorderLibrary,
	}
	for _, messageType := range required {
		if !requiresRequestID(messageType) {
			t.Errorf("requiresRequestID(%q) = false, want true", messageType)
		}
	}
	for _, optional := range []string{protocol.TypeSessionPing, protocol.TypeRoomLeave} {
		if requiresRequestID(optional) {
			t.Errorf("requiresRequestID(%q) = true, want false", optional)
		}
	}
}

func TestShouldLogSessionEnd(t *testing.T) {
	for _, err := range []error{
		nil,
		context.Canceled,
		websocket.CloseError{Code: websocket.StatusNormalClosure},
		websocket.CloseError{Code: websocket.StatusGoingAway},
	} {
		if shouldLogSessionEnd(err) {
			t.Errorf("shouldLogSessionEnd(%v) = true, want false", err)
		}
	}
	if !shouldLogSessionEnd(errors.New("network failure")) {
		t.Error("unexpected network failure should be logged")
	}
}

// TestWrongPasswordRejected: password-protected room rejects empty password.
func TestWrongPasswordRejected(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	guest := dial(t, srv)
	defer guest.close()

	host.hello("Alice")
	guest.hello("Bob")

	_, roomID := host.createRoom("Private", protocol.FormatModern, 2, true, "secret")

	joinEnv, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{
		RoomID: roomID, AsSpectator: false, // no password
	})
	joinEnv.ID = "j"
	guest.send(joinEnv)
	err := guest.recvType(protocol.TypeError)
	var ep protocol.ErrorPayload
	if err2 := err.DecodePayload(&ep); err2 != nil {
		t.Fatalf("decode error: %v", err2)
	}
	if ep.Code != protocol.ErrWrongPassword {
		t.Fatalf("code = %q, want %q", ep.Code, protocol.ErrWrongPassword)
	}
}

func TestPasswordCheckRunsOutsideRoomOperationLock(t *testing.T) {
	hub := NewHub()
	r, err := room.New(
		"ABCDEF", "Private", protocol.FormatModern, protocol.MatchBO1,
		protocol.CardLoadPreload, 2, true, true,
		"Alice", "host-conn", time.Now().UTC())
	if err != nil {
		t.Fatalf("new room: %v", err)
	}
	entry := &roomEntry{room: r, passwordHash: []byte("test-hash")}
	hub.rooms[r.ID] = entry

	checkStarted := make(chan struct{})
	releaseCheck := make(chan struct{})
	hub.passwordCheck = func(hash []byte, password string) bool {
		close(checkStarted)
		<-releaseCheck
		return string(hash) == "test-hash" && password == "secret"
	}
	type beginJoinResult struct {
		entry *roomEntry
		err   error
	}
	result := make(chan beginJoinResult, 1)
	go func() {
		joinedEntry, joinErr := hub.beginJoin(r.ID, "secret")
		result <- beginJoinResult{entry: joinedEntry, err: joinErr}
	}()

	<-checkStarted
	if !entry.opMu.TryLock() {
		t.Fatal("room operation lock held during password comparison")
	}
	entry.opMu.Unlock()
	close(releaseCheck)

	joined := <-result
	if joined.err != nil || joined.entry != entry {
		t.Fatalf("begin join = entry %p err %v, want %p", joined.entry, joined.err, entry)
	}
	joined.entry.opMu.Unlock()
}

// TestSpectatorCap: 8 spectators allowed, 9th rejected.
func TestSpectatorCap(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	host.hello("Alice")
	_, roomID := host.createRoom("Spec EDH", protocol.FormatEDH, 4, true, "")

	for i := 0; i < protocol.MaxSpectators; i++ {
		sp := dial(t, srv)
		sp.hello("Spec")
		joinEnv, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{
			RoomID: roomID, AsSpectator: true,
		})
		joinEnv.ID = "j"
		sp.send(joinEnv)
		sp.recvType(protocol.TypeRoomJoined)
		// drain host snapshot fanout so its buffer doesn't block
		host.recvType(protocol.TypeRoomSnapshot)
	}

	// 9th spectator should be rejected.
	ninth := dial(t, srv)
	defer ninth.close()
	ninth.hello("Spec9")
	joinEnv, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{
		RoomID: roomID, AsSpectator: true,
	})
	joinEnv.ID = "j"
	ninth.send(joinEnv)
	err := ninth.recvType(protocol.TypeError)
	var ep protocol.ErrorPayload
	_ = err.DecodePayload(&ep)
	if ep.Code != protocol.ErrSpectatorLimit {
		t.Fatalf("9th spectator code = %q, want %q", ep.Code, protocol.ErrSpectatorLimit)
	}
}

// TestSeatsFull: Modern room (2 seats) rejects a 3rd player.
func TestSeatsFull(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	g1 := dial(t, srv)
	defer g1.close()
	g2 := dial(t, srv)
	defer g2.close()

	host.hello("Alice")
	g1.hello("Bob")
	g2.hello("Carol")

	_, roomID := host.createRoom("Modern", protocol.FormatModern, 2, true, "")
	joinRoom(t, g1, roomID, false)
	host.recvType(protocol.TypeRoomSnapshot) // drain fanout

	joinEnv, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{
		RoomID: roomID, AsSpectator: false,
	})
	joinEnv.ID = "j"
	g2.send(joinEnv)
	err := g2.recvType(protocol.TypeError)
	var ep protocol.ErrorPayload
	_ = err.DecodePayload(&ep)
	if ep.Code != protocol.ErrRoomFull {
		t.Fatalf("3rd player code = %q, want %q", ep.Code, protocol.ErrRoomFull)
	}
}

// TestHostKick: host kicks seat 1; guest receives room.kicked, is unbound
// (further commands fail with not_in_room), and host sees the seat freed.
func TestHostKick(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	guest := dial(t, srv)
	defer guest.close()

	host.hello("Alice")
	guest.hello("Bob")

	_, roomID := host.createRoom("EDH", protocol.FormatEDH, 4, true, "")
	joinRoom(t, guest, roomID, false)
	host.recvType(protocol.TypeRoomSnapshot) // drain join fanout

	seat := 1
	kickEnv, _ := protocol.NewEnvelope(protocol.TypeRoomKick, protocol.RoomKick{Seat: &seat})
	kickEnv.ID = "k"
	host.send(kickEnv)

	// Host: reply room.kicked (echo id) + snapshot with seat 1 free.
	hostReply := host.recvType(protocol.TypeRoomKicked)
	if hostReply.ID != "k" {
		t.Fatalf("host kicked reply id = %q, want k (echo)", hostReply.ID)
	}
	snap := host.recvType(protocol.TypeRoomSnapshot)
	var sp protocol.RoomSnapshot
	_ = snap.DecodePayload(&sp)
	if sp.Seats[1].Occupied {
		t.Fatalf("seat 1 should be free after kick: %+v", sp.Seats[1])
	}

	// Guest: server-push room.kicked (no echo id).
	guestKicked := guest.recvType(protocol.TypeRoomKicked)
	if guestKicked.ID != "" {
		t.Fatalf("guest kicked push should have no echoed id, got %q", guestKicked.ID)
	}

	// Guest is now unbound: a subsequent room.leave must fail with not_in_room.
	leaveEnv, _ := protocol.NewEnvelope(protocol.TypeRoomLeave, nil)
	leaveEnv.ID = "leave-after-kick"
	guest.send(leaveEnv)
	err := guest.recvType(protocol.TypeError)
	var ep protocol.ErrorPayload
	_ = err.DecodePayload(&ep)
	if ep.Code != protocol.ErrNotInRoom {
		t.Fatalf("kicked guest leave code = %q, want %q", ep.Code, protocol.ErrNotInRoom)
	}
}

// TestKickSpectatorByIndex: host kicks spectator by index.
func TestKickSpectatorByIndex(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	spec := dial(t, srv)
	defer spec.close()

	host.hello("Alice")
	spec.hello("Spec")
	_, roomID := host.createRoom("EDH", protocol.FormatEDH, 4, true, "")
	joinRoom(t, spec, roomID, true)
	host.recvType(protocol.TypeRoomSnapshot) // drain

	idx := 0
	kickEnv, _ := protocol.NewEnvelope(protocol.TypeRoomKick, protocol.RoomKick{SpectatorIndex: &idx})
	kickEnv.ID = "k"
	host.send(kickEnv)
	host.recvType(protocol.TypeRoomKicked)

	// Spectator receives a server-push room.kicked.
	spec.recvType(protocol.TypeRoomKicked)

	// Snapshot shows no spectators.
	snap := host.recvType(protocol.TypeRoomSnapshot)
	var sp protocol.RoomSnapshot
	_ = snap.DecodePayload(&sp)
	if len(sp.Spectators) != 0 {
		t.Fatalf("spectators after kick = %d, want 0", len(sp.Spectators))
	}
}

// TestKickHostRejected: host cannot kick their own seat.
func TestKickHostRejected(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	host.hello("Alice")
	_, _ = host.createRoom("EDH", protocol.FormatEDH, 4, true, "")
	host.recvType(protocol.TypeRoomSnapshot) // drain

	seat := 0
	kickEnv, _ := protocol.NewEnvelope(protocol.TypeRoomKick, protocol.RoomKick{Seat: &seat})
	kickEnv.ID = "k"
	host.send(kickEnv)
	err := host.recvType(protocol.TypeError)
	var ep protocol.ErrorPayload
	_ = err.DecodePayload(&ep)
	if ep.Code != protocol.ErrCannotKickHost {
		t.Fatalf("kick host code = %q, want %q", ep.Code, protocol.ErrCannotKickHost)
	}
}

// TestCreateWhileInRoom: a host already in a room cannot create another.
func TestCreateWhileInRoom(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	host.hello("Alice")
	_, _ = host.createRoom("First", protocol.FormatEDH, 4, true, "")
	host.recvType(protocol.TypeRoomSnapshot) // drain

	// Attempt a second create while still in the first room.
	createEnv, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{
		Name: "Second", Format: protocol.FormatEDH, DeckFormat: protocol.DeckFormatCommander,
		AllowSpectators: true, MatchMode: protocol.MatchBO3,
	})
	createEnv.ID = "c2"
	host.send(createEnv)
	err := host.recvType(protocol.TypeError)
	var ep protocol.ErrorPayload
	_ = err.DecodePayload(&ep)
	if ep.Code != protocol.ErrAlreadyInRoom {
		t.Fatalf("second create code = %q, want %q", ep.Code, protocol.ErrAlreadyInRoom)
	}
}

// TestHostLeaveDisbands: host leaving disbands the room; host receives
// room.disbanded (reply, echo id), guest receives room.disbanded (broadcast).
func TestHostLeaveDisbands(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	guest := dial(t, srv)
	defer guest.close()

	host.hello("Alice")
	guest.hello("Bob")

	_, roomID := host.createRoom("EDH", protocol.FormatEDH, 4, true, "")
	joinRoom(t, guest, roomID, false)
	host.recvType(protocol.TypeRoomSnapshot) // drain

	leaveEnv, _ := protocol.NewEnvelope(protocol.TypeRoomLeave, nil)
	leaveEnv.ID = "l"
	host.send(leaveEnv)

	// Host gets room.disbanded reply with echoed id.
	hostDisbanded := host.recvType(protocol.TypeRoomDisbanded)
	if hostDisbanded.ID != "l" {
		t.Fatalf("host disbanded reply id = %q, want l (echo)", hostDisbanded.ID)
	}

	// Guest gets room.disbanded broadcast (no echoed id).
	guestDisbanded := guest.recvType(protocol.TypeRoomDisbanded)
	if guestDisbanded.ID != "" {
		t.Fatalf("guest disbanded broadcast should have no echoed id, got %q", guestDisbanded.ID)
	}
	assertCanCreateRoom(t, guest, roomID)
}

func TestExplicitDisbandUnbindsGuest(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	guest := dial(t, srv)
	defer guest.close()

	host.hello("Alice")
	guest.hello("Bob")
	_, roomID := host.createRoom("EDH", protocol.FormatEDH, 4, true, "")
	host.recvType(protocol.TypeRoomSnapshot)
	joinRoom(t, guest, roomID, false)
	host.recvType(protocol.TypeRoomSnapshot)

	disband, _ := protocol.NewEnvelope(protocol.TypeRoomDisband, nil)
	disband.ID = "d"
	host.send(disband)
	if reply := host.recvType(protocol.TypeRoomDisbanded); reply.ID != disband.ID {
		t.Fatalf("host disband reply id = %q, want %q", reply.ID, disband.ID)
	}
	if push := guest.recvType(protocol.TypeRoomDisbanded); push.ID != "" {
		t.Fatalf("guest disband push id = %q, want empty", push.ID)
	}
	assertCanCreateRoom(t, guest, roomID)
}

func TestReconnectRestoresHostSeatAndPrivateProjection(t *testing.T) {
	config := DefaultConfig()
	config.ReconnectWindow = 500 * time.Millisecond
	srv, handler := newConfiguredTestServer(t, config)
	host := dial(t, srv)
	guest := dial(t, srv)
	defer guest.close()

	hostWelcomeEnvelope := host.hello("Alice")
	var hostWelcome protocol.SessionWelcome
	if err := hostWelcomeEnvelope.DecodePayload(&hostWelcome); err != nil {
		t.Fatalf("decode host welcome: %v", err)
	}
	if hostWelcome.ResumeToken == "" {
		t.Fatal("initial welcome omitted resume token")
	}
	guest.hello("Bob")
	_, roomID := host.createRoom("Modern", protocol.FormatModern, 2, true, "")
	host.recvType(protocol.TypeRoomSnapshot)
	joinRoom(t, guest, roomID, false)
	host.recvType(protocol.TypeRoomSnapshot)
	guest.recvType(protocol.TypeRoomSnapshot)

	r := handler.hub.FindRoom(roomID)
	operation, err := handler.hub.lockRoomOperation(roomID)
	if err != nil {
		t.Fatalf("lock room: %v", err)
	}
	operation.mu.Lock()
	r.Phase = protocol.RoomPhaseStarted
	r.Score = []int{0, 0}
	r.Game = &room.GameState{
		Number:       1,
		StartingSeat: 0,
		ActiveSeat:   0,
		CurrentPhase: protocol.GamePhaseUntap,
		Seats: []room.PlayerGameState{
			{
				Seat: 0, DisplayName: "Alice", Life: 20,
				Hand: []protocol.GameCard{{
					ID: "alice-secret", Name: "Lightning Bolt",
					SetCode: "M11", CollectorNumber: "149",
				}},
				Library: []protocol.GameCard{{
					ID: "alice-library", Name: "Mountain",
					SetCode: "M11", CollectorNumber: "242",
				}},
			},
			{
				Seat: 1, DisplayName: "Bob", Life: 20,
				Hand: []protocol.GameCard{{
					ID: "bob-secret", Name: "Counterspell",
					SetCode: "MH2", CollectorNumber: "267",
				}},
			},
		},
		Stack:       []protocol.GameSharedCard{},
		Revealed:    []protocol.GameSharedCard{},
		Log:         []protocol.GameLogEntry{},
		NextLogID:   1,
		NextTokenID: 1,
	}
	operation.mu.Unlock()
	operation.opMu.Unlock()

	host.close()
	time.Sleep(30 * time.Millisecond)

	resumedHost := dial(t, srv)
	defer resumedHost.close()
	resumedWelcome := resumedHost.resume("Alice", hostWelcome.ResumeToken, 2)
	if !resumedWelcome.Resumed || resumedWelcome.RoomID != roomID ||
		resumedWelcome.Role != protocol.RolePlayer ||
		resumedWelcome.Seat == nil || *resumedWelcome.Seat != 0 ||
		!resumedWelcome.Host {
		t.Fatalf("resumed welcome = %+v", resumedWelcome)
	}
	if resumedWelcome.ResumeToken == "" ||
		resumedWelcome.ResumeToken == hostWelcome.ResumeToken {
		t.Fatalf("resumed token was not rotated: initial=%q resumed=%q",
			hostWelcome.ResumeToken, resumedWelcome.ResumeToken)
	}
	resumedHost.recvType(protocol.TypeRoomSnapshot)
	gameEnvelope := resumedHost.recvType(protocol.TypeGameSnapshot)
	var game protocol.GameSnapshot
	if err := gameEnvelope.DecodePayload(&game); err != nil {
		t.Fatalf("decode resumed game: %v", err)
	}
	if len(game.Seats[0].Hand) != 1 ||
		game.Seats[0].Hand[0].ID != "alice-secret" ||
		len(game.Seats[1].Hand) != 0 {
		t.Fatalf("resumed private projection = %+v", game.Seats)
	}

	spectator := dial(t, srv)
	spectatorWelcomeEnvelope := spectator.hello("Observer")
	var spectatorWelcome protocol.SessionWelcome
	if err := spectatorWelcomeEnvelope.DecodePayload(&spectatorWelcome); err != nil {
		t.Fatalf("decode spectator welcome: %v", err)
	}
	joinRoom(t, spectator, roomID, true)
	spectator.recvType(protocol.TypeRoomSnapshot)
	spectator.recvType(protocol.TypeGameSnapshot)
	spectator.close()
	time.Sleep(30 * time.Millisecond)

	resumedSpectator := dial(t, srv)
	defer resumedSpectator.close()
	resumedObserverWelcome := resumedSpectator.resume(
		"Observer", spectatorWelcome.ResumeToken, 0)
	if !resumedObserverWelcome.Resumed ||
		resumedObserverWelcome.Role != protocol.RoleSpectator ||
		resumedObserverWelcome.Seat != nil {
		t.Fatalf("resumed spectator welcome = %+v", resumedObserverWelcome)
	}
	if resumedObserverWelcome.ResumeToken == "" ||
		resumedObserverWelcome.ResumeToken == spectatorWelcome.ResumeToken {
		t.Fatalf("spectator token was not rotated: initial=%q resumed=%q",
			spectatorWelcome.ResumeToken, resumedObserverWelcome.ResumeToken)
	}
	resumedSpectator.recvType(protocol.TypeRoomSnapshot)
	spectatorGameEnvelope := resumedSpectator.recvType(protocol.TypeGameSnapshot)
	var spectatorGame protocol.GameSnapshot
	if err := spectatorGameEnvelope.DecodePayload(&spectatorGame); err != nil {
		t.Fatalf("decode resumed spectator game: %v", err)
	}
	if len(spectatorGame.Seats[0].Hand) != 0 ||
		len(spectatorGame.Seats[1].Hand) != 0 ||
		spectatorGame.Seats[0].HandCount != 1 ||
		spectatorGame.Seats[1].HandCount != 1 {
		t.Fatalf("spectator reconnect leaked hidden hands: %+v", spectatorGame.Seats)
	}
}

func TestReconnectExpiryTransfersHostWithoutDisbandingRoom(t *testing.T) {
	config := DefaultConfig()
	config.ReconnectWindow = 60 * time.Millisecond
	srv, _ := newConfiguredTestServer(t, config)
	host := dial(t, srv)
	guest := dial(t, srv)
	defer guest.close()

	host.hello("Alice")
	guest.hello("Bob")
	_, roomID := host.createRoom("Modern", protocol.FormatModern, 2, true, "")
	host.recvType(protocol.TypeRoomSnapshot)
	joinRoom(t, guest, roomID, false)
	host.recvType(protocol.TypeRoomSnapshot)
	guest.recvType(protocol.TypeRoomSnapshot)

	host.close()
	expiredSnapshot := guest.recvType(protocol.TypeRoomSnapshot)
	var expired protocol.RoomSnapshot
	if err := expiredSnapshot.DecodePayload(&expired); err != nil {
		t.Fatalf("decode expiry snapshot: %v", err)
	}
	if expired.Seats[0].Occupied || expired.HostSeat != 1 ||
		!expired.Seats[1].Host {
		t.Fatalf("expired host seat = %+v hostSeat=%d", expired.Seats[0], expired.HostSeat)
	}

	replacement := dial(t, srv)
	defer replacement.close()
	replacement.hello("Carol")
	joinRoom(t, replacement, roomID, false)
	replacementSnapshot := replacement.recvType(protocol.TypeRoomSnapshot)
	var joined protocol.RoomSnapshot
	if err := replacementSnapshot.DecodePayload(&joined); err != nil {
		t.Fatalf("decode replacement snapshot: %v", err)
	}
	if !joined.Seats[0].Occupied || joined.Seats[0].DisplayName != "Carol" ||
		joined.Seats[0].Host || !joined.Seats[1].Host {
		t.Fatalf("replacement seat = %+v", joined.Seats[0])
	}
}

func TestReconnectExpiryForfeitsStartedModernMatch(t *testing.T) {
	config := DefaultConfig()
	config.ReconnectWindow = 60 * time.Millisecond
	srv, handler := newConfiguredTestServer(t, config)
	host := dial(t, srv)
	defer host.close()
	guest := dial(t, srv)

	host.hello("Alice")
	guest.hello("Bob")
	_, roomID := host.createRoom("Modern", protocol.FormatModern, 2, true, "")
	host.recvType(protocol.TypeRoomSnapshot)
	joinRoom(t, guest, roomID, false)
	host.recvType(protocol.TypeRoomSnapshot)
	guest.recvType(protocol.TypeRoomSnapshot)

	r := handler.hub.FindRoom(roomID)
	operation, err := handler.hub.lockRoomOperation(roomID)
	if err != nil {
		t.Fatalf("lock room: %v", err)
	}
	operation.mu.Lock()
	r.Phase = protocol.RoomPhaseStarted
	r.Score = []int{0, 0}
	r.Game = &room.GameState{
		Number:       1,
		StartingSeat: 1,
		ActiveSeat:   1,
		CurrentPhase: protocol.GamePhaseEnd,
		Seats: []room.PlayerGameState{
			{Seat: 0, DisplayName: "Alice", Life: 20},
			{Seat: 1, DisplayName: "Bob", Life: 20},
		},
		Log:       []protocol.GameLogEntry{},
		NextLogID: 1,
	}
	operation.mu.Unlock()
	operation.opMu.Unlock()

	guest.close()
	host.recvType(protocol.TypeRoomSnapshot)
	gameEnvelope := host.recvType(protocol.TypeGameSnapshot)
	var game protocol.GameSnapshot
	if err := gameEnvelope.DecodePayload(&game); err != nil {
		t.Fatalf("decode departure game: %v", err)
	}
	if game.Result == nil ||
		game.Result.Reason != protocol.GameResultDeparture ||
		game.Result.WinnerSeat != 0 ||
		game.Result.ConcededSeat != 1 ||
		!game.Result.MatchFinished ||
		game.ActiveSeat != -1 ||
		len(game.Score) != 2 || game.Score[0] != 2 ||
		len(game.Log) != 1 || game.Log[0].Kind != "departure" {
		t.Fatalf("departure projection = %+v", game)
	}
}

func TestConcurrentJoinAndDisbandLeavesSessionReusable(t *testing.T) {
	for i := 0; i < 25; i++ {
		srv, _ := newTestServer(t)
		host := dial(t, srv)
		guest := dial(t, srv)
		host.hello("Alice")
		guest.hello("Bob")
		_, roomID := host.createRoom("EDH", protocol.FormatEDH, 4, true, "")
		host.recvType(protocol.TypeRoomSnapshot)

		join, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: roomID})
		join.ID = "concurrent-join"
		disband, _ := protocol.NewEnvelope(protocol.TypeRoomDisband, nil)
		disband.ID = "concurrent-disband"
		guest.send(join)
		host.send(disband)
		host.recvType(protocol.TypeRoomDisbanded)

		assertCanCreateRoom(t, guest, roomID)
		host.close()
		guest.close()
		srv.Close()
	}
}

// joinRoom is a helper that joins a client to a room and drains the joined reply.
func joinRoom(t *testing.T, c *wsClient, roomID string, asSpec bool) {
	t.Helper()
	joinEnv, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{
		RoomID: roomID, AsSpectator: asSpec,
	})
	joinEnv.ID = "j"
	c.send(joinEnv)
	c.recvType(protocol.TypeRoomJoined)
}

func assertCanCreateRoom(t *testing.T, c *wsClient, previousRoomID string) {
	t.Helper()
	env, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{
		Name: "Next room", Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatCustom,
		AllowSpectators: true,
		MatchMode:       protocol.MatchBO1,
	})
	env.ID = "create-after-disband"
	c.send(env)
	var result protocol.Envelope
	for i := 0; i < 12; i++ {
		candidate := c.recv()
		if candidate.ID == env.ID && (candidate.Type == protocol.TypeRoomCreated || candidate.Type == protocol.TypeError) {
			result = candidate
			break
		}
	}
	if result.Type == "" {
		t.Fatal("no correlated create result after disband")
	}
	if result.Type == protocol.TypeError {
		var ep protocol.ErrorPayload
		_ = result.DecodePayload(&ep)
		t.Fatalf("create after disband failed: %s: %s", ep.Code, ep.Message)
	}
	var created protocol.RoomCreated
	if err := result.DecodePayload(&created); err != nil {
		t.Fatalf("decode created: %v", err)
	}
	if created.RoomID == "" || created.RoomID == previousRoomID {
		t.Fatalf("new room id = %q, previous = %q", created.RoomID, previousRoomID)
	}
	c.recvType(protocol.TypeRoomSnapshot)
}

func TestSessionHelloTimeoutClosesIdleConnection(t *testing.T) {
	config := DefaultConfig()
	config.HelloTimeout = 50 * time.Millisecond
	srv, _ := newConfiguredTestServer(t, config)
	client := dial(t, srv)
	defer client.close()
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	_, _, err := client.conn.Read(ctx)
	if err == nil {
		t.Fatal("idle connection remained open past session.hello timeout")
	}
	if status := websocket.CloseStatus(err); status != websocket.StatusPolicyViolation {
		t.Fatalf("hello timeout close status = %v, want %v (err=%v)",
			status, websocket.StatusPolicyViolation, err)
	}
}

func TestPasswordJoinRateLimitResetsAfterWindow(t *testing.T) {
	handler := NewHandler()
	handler.config.PasswordJoinsPerMinute = 2
	now := time.Date(2026, time.August, 5, 10, 0, 0, 0, time.UTC)
	if !handler.allowPasswordJoin("203.0.113.5", now) ||
		!handler.allowPasswordJoin("203.0.113.5", now.Add(time.Second)) {
		t.Fatal("allowed password joins were rejected")
	}
	if handler.allowPasswordJoin("203.0.113.5", now.Add(2*time.Second)) {
		t.Fatal("password join rate limit did not reject excess attempt")
	}
	if !handler.allowPasswordJoin("203.0.113.5", now.Add(time.Minute)) {
		t.Fatal("password join rate limit did not reset")
	}
}

func TestReplayRequestRateLimitIsPerIPAndResetsAfterWindow(t *testing.T) {
	handler := NewHandler()
	handler.config.ReplayRequestsPerMinute = 2
	now := time.Date(2026, time.August, 5, 10, 0, 0, 0, time.UTC)
	if !handler.allowReplayRequest("203.0.113.5", now) ||
		!handler.allowReplayRequest("203.0.113.5", now.Add(time.Second)) {
		t.Fatal("allowed replay requests were rejected")
	}
	if handler.allowReplayRequest("203.0.113.5", now.Add(2*time.Second)) {
		t.Fatal("replay request rate limit did not reject excess attempt")
	}
	if !handler.allowReplayRequest("198.51.100.8", now.Add(2*time.Second)) {
		t.Fatal("one client IP exhausted another client's replay allowance")
	}
	if !handler.allowReplayRequest("203.0.113.5", now.Add(time.Minute)) {
		t.Fatal("replay request rate limit did not reset")
	}
}

func TestPasswordCheckConcurrencyIsBounded(t *testing.T) {
	hub := NewHubWithLimits(4, 1)
	r, err := room.New(
		"ABCDEF", "Protected", protocol.FormatModern, protocol.MatchBO1,
		protocol.CardLoadPreload, 2, true, true, "Alice", "host", time.Now().UTC())
	if err != nil {
		t.Fatalf("new room: %v", err)
	}
	hub.rooms[r.ID] = &roomEntry{room: r, passwordHash: []byte("hash")}
	entered := make(chan struct{})
	release := make(chan struct{})
	hub.passwordCheck = func([]byte, string) bool {
		close(entered)
		<-release
		return true
	}
	result := make(chan error, 1)
	go func() {
		entry, err := hub.beginJoin(r.ID, "secret")
		if err == nil {
			entry.opMu.Unlock()
		}
		result <- err
	}()
	select {
	case <-entered:
	case <-time.After(time.Second):
		t.Fatal("first password check did not start")
	}
	if _, err := hub.beginJoin(r.ID, "secret"); err == nil {
		t.Fatal("second concurrent password check was accepted")
	} else if code, ok := ErrCode(err); !ok || code != protocol.ErrRateLimited {
		t.Fatalf("second password check err=%v code=%q", err, code)
	}
	close(release)
	if err := <-result; err != nil {
		t.Fatalf("first password check failed: %v", err)
	}
}
