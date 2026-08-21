// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

type privateZoneConsentSetup struct {
	handler   *Handler
	room      *room.Room
	host      *Session
	guest     *Session
	spectator *Session
}

func newPrivateZoneConsentSetup(t *testing.T) privateZoneConsentSetup {
	t.Helper()
	h := NewHandler()
	host := &Session{
		ConnectionID: "host-conn",
		DisplayName:  "Alice",
		RemoteIP:     "127.0.0.1",
		Send:         make(chan []byte, 32),
	}
	guest := &Session{
		ConnectionID: "guest-conn",
		DisplayName:  "Bob",
		RemoteIP:     "127.0.0.2",
		Send:         make(chan []byte, 32),
	}
	spectator := &Session{
		ConnectionID: "spectator-conn",
		DisplayName:  "Watcher",
		RemoteIP:     "127.0.0.3",
		Send:         make(chan []byte, 32),
	}
	h.registerSession(host)
	h.registerSession(guest)
	h.registerSession(spectator)
	t.Cleanup(func() {
		h.unregisterSession(host)
		h.unregisterSession(guest)
		h.unregisterSession(spectator)
	})

	r, _, _, operation, err := h.hub.CreateRoom(
		"Consent room", protocol.FormatModern, protocol.MatchBO1,
		protocol.CardLoadPreload, 2, true, "", host)
	if err != nil {
		t.Fatalf("CreateRoom: %v", err)
	}
	operation.opMu.Unlock()
	joinPrivateZoneMember(t, h, r, guest, false)
	joinPrivateZoneMember(t, h, r, spectator, true)

	r.Phase = protocol.RoomPhaseStarted
	r.Score = []int{0, 0}
	r.Game = &room.GameState{
		Number:       1,
		StartingSeat: 0,
		ActiveSeat:   0,
		CurrentPhase: protocol.GamePhaseFirstMain,
		Seats: []room.PlayerGameState{
			{
				Seat: 0, DisplayName: "Alice", Life: 20,
				Library: []protocol.GameCard{{
					ID: "s0-c8", Name: "Mountain", SetCode: "M21",
					CollectorNumber: "269", OwnerSeat: 0,
				}},
				Hand: []protocol.GameCard{}, Battlefield: []protocol.GameCard{},
				Graveyard: []protocol.GameCard{}, Exile: []protocol.GameCard{},
			},
			{
				Seat: 1, DisplayName: "Bob", Life: 20,
				Library: []protocol.GameCard{{
					ID: "s1-c8", Name: "Island", SetCode: "M21",
					CollectorNumber: "265", OwnerSeat: 1,
				}},
				Hand: []protocol.GameCard{}, Battlefield: []protocol.GameCard{},
				Graveyard: []protocol.GameCard{}, Exile: []protocol.GameCard{},
			},
		},
		Stack:       []protocol.GameSharedCard{},
		Revealed:    []protocol.GameSharedCard{},
		Arrows:      []protocol.GameArrow{},
		Attachments: []protocol.GameAttachment{},
		Log:         []protocol.GameLogEntry{},
		NextLogID:   1,
	}
	return privateZoneConsentSetup{
		handler: h, room: r, host: host, guest: guest, spectator: spectator,
	}
}

func joinPrivateZoneMember(t *testing.T, h *Handler, r *room.Room,
	sess *Session, spectator bool) {
	t.Helper()
	operation, err := h.hub.beginJoin(r.ID, "")
	if err != nil {
		t.Fatalf("beginJoin: %v", err)
	}
	_, _, err = h.hub.joinRoom(operation, sess, spectator)
	operation.opMu.Unlock()
	if err != nil {
		t.Fatalf("joinRoom: %v", err)
	}
}

func loadPrivateZoneFixture(t *testing.T, name string) protocol.Envelope {
	t.Helper()
	path := filepath.Join("../../../../testdata/protocol/v1", name)
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", name, err)
	}
	envelope, err := protocol.ParseEnvelope(data)
	if err != nil {
		t.Fatalf("parse %s: %v", name, err)
	}
	return envelope
}

func receivePrivateZoneEnvelope(t *testing.T, sess *Session) protocol.Envelope {
	t.Helper()
	select {
	case data := <-sess.Send:
		envelope, err := protocol.ParseEnvelope(data)
		if err != nil {
			t.Fatalf("ParseEnvelope: %v", err)
		}
		return envelope
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for private-zone envelope")
		return protocol.Envelope{}
	}
}

func assertNoPrivateZoneEnvelope(t *testing.T, sess *Session) {
	t.Helper()
	select {
	case data := <-sess.Send:
		envelope, err := protocol.ParseEnvelope(data)
		if err != nil {
			t.Fatalf("ParseEnvelope: %v", err)
		}
		t.Fatalf("unexpected envelope: type=%q id=%q", envelope.Type, envelope.ID)
	default:
	}
}

func assertPrivateZoneFixture(t *testing.T, name, roomID string,
	got protocol.Envelope) {
	t.Helper()
	want := loadPrivateZoneFixture(t, name)
	var gotValue, wantValue map[string]any
	gotData, err := got.Marshal()
	if err != nil {
		t.Fatalf("marshal actual %s: %v", name, err)
	}
	wantData, err := want.Marshal()
	if err != nil {
		t.Fatalf("marshal fixture %s: %v", name, err)
	}
	if err := json.Unmarshal(gotData, &gotValue); err != nil {
		t.Fatalf("decode actual %s: %v", name, err)
	}
	if err := json.Unmarshal(wantData, &wantValue); err != nil {
		t.Fatalf("decode fixture %s: %v", name, err)
	}
	if payload, ok := wantValue["payload"].(map[string]any); ok {
		if _, hasRoomID := payload["roomId"]; hasRoomID {
			payload["roomId"] = roomID
		}
	}
	if !reflect.DeepEqual(gotValue, wantValue) {
		t.Fatalf("%s drifted:\nwant: %s\n got: %s", name, wantData, gotData)
	}
}

func assertPrivateZoneError(t *testing.T, envelope protocol.Envelope,
	requestID, code, message string) {
	t.Helper()
	if envelope.Type != protocol.TypeError || envelope.ID != requestID {
		t.Fatalf("error envelope = type=%q id=%q", envelope.Type, envelope.ID)
	}
	var payload protocol.ErrorPayload
	if err := envelope.DecodePayload(&payload); err != nil {
		t.Fatalf("decode error payload: %v", err)
	}
	if payload.Code != code || payload.Message != message {
		t.Fatalf("error payload = %#v, want code=%q message=%q",
			payload, code, message)
	}
}

func TestOpponentLibraryConsentFlowMatchesGoldenFixtures(t *testing.T) {
	setup := newPrivateZoneConsentSetup(t)
	dumpRequest := loadPrivateZoneFixture(t, "game-dump-zone-opponent.json")
	if err := setup.handler.handleGameDumpZone(setup.host, dumpRequest); err != nil {
		t.Fatalf("handleGameDumpZone: %v", err)
	}
	pending := receivePrivateZoneEnvelope(t, setup.host)
	requested := receivePrivateZoneEnvelope(t, setup.guest)
	assertPrivateZoneFixture(t, "game-zone-dump-pending.json", setup.room.ID, pending)
	assertPrivateZoneFixture(t, "game-zone-dump-requested.json", setup.room.ID, requested)
	assertNoPrivateZoneEnvelope(t, setup.spectator)

	response := loadPrivateZoneFixture(t, "game-respond-zone-dump.json")
	if err := setup.handler.handleGameRespondZoneDump(setup.guest, response); err != nil {
		t.Fatalf("handleGameRespondZoneDump: %v", err)
	}
	responded := receivePrivateZoneEnvelope(t, setup.guest)
	dumped := receivePrivateZoneEnvelope(t, setup.host)
	assertPrivateZoneFixture(t, "game-zone-dump-responded.json", setup.room.ID, responded)
	assertPrivateZoneFixture(t, "game-zone-dumped-opponent.json", setup.room.ID, dumped)

	for name, sess := range map[string]*Session{
		"requester": setup.host,
		"target":    setup.guest,
		"spectator": setup.spectator,
	} {
		snapshot := receivePrivateZoneEnvelope(t, sess)
		if snapshot.Type != protocol.TypeGameSnapshot {
			t.Fatalf("%s received private response instead of snapshot: %+v", name, snapshot)
		}
	}

	searchRequest := loadPrivateZoneFixture(t, "game-search-library-opponent.json")
	if err := setup.handler.handleGameSearchLibrary(setup.host, searchRequest); err != nil {
		t.Fatalf("handleGameSearchLibrary: %v", err)
	}
	searched := receivePrivateZoneEnvelope(t, setup.host)
	assertPrivateZoneFixture(t, "game-library-searched-opponent.json", setup.room.ID, searched)

	hostSnapshot := receivePrivateZoneEnvelope(t, setup.host)
	guestSnapshot := receivePrivateZoneEnvelope(t, setup.guest)
	spectatorSnapshot := receivePrivateZoneEnvelope(t, setup.spectator)
	for name, envelope := range map[string]protocol.Envelope{
		"requester": hostSnapshot,
		"target":    guestSnapshot,
		"spectator": spectatorSnapshot,
	} {
		if envelope.Type != protocol.TypeGameSnapshot {
			t.Fatalf("%s received %q after private search", name, envelope.Type)
		}
	}
	var hostGame, guestGame, spectatorGame protocol.GameSnapshot
	if err := hostSnapshot.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode requester snapshot: %v", err)
	}
	if err := guestSnapshot.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode target snapshot: %v", err)
	}
	if err := spectatorSnapshot.DecodePayload(&spectatorGame); err != nil {
		t.Fatalf("decode spectator snapshot: %v", err)
	}
	if len(hostGame.Seats[0].Hand) != 1 ||
		hostGame.Seats[0].Hand[0].Name != "Island" ||
		guestGame.Seats[0].HandCount != 1 || len(guestGame.Seats[0].Hand) != 0 ||
		spectatorGame.Seats[0].HandCount != 1 || len(spectatorGame.Seats[0].Hand) != 0 {
		t.Fatalf("private searched card projections requester=%+v target=%+v spectator=%+v",
			hostGame.Seats[0], guestGame.Seats[0], spectatorGame.Seats[0])
	}
	for name, snapshot := range map[string]protocol.GameSnapshot{
		"target": guestGame, "spectator": spectatorGame,
	} {
		encoded, err := json.Marshal(snapshot)
		if err != nil {
			t.Fatalf("marshal %s snapshot: %v", name, err)
		}
		if strings.Contains(string(encoded), "Island") {
			t.Fatalf("%s learned the privately selected card: %s", name, encoded)
		}
	}

	reused := searchRequest
	reused.ID = "search-opponent-reused"
	if err := setup.handler.handleGameSearchLibrary(setup.host, reused); err != nil {
		t.Fatalf("reuse search handler: %v", err)
	}
	assertPrivateZoneError(t, receivePrivateZoneEnvelope(t, setup.host),
		reused.ID, protocol.ErrApprovalExpired, "library access approval expired")
	assertNoPrivateZoneEnvelope(t, setup.guest)
	assertNoPrivateZoneEnvelope(t, setup.spectator)
}

func TestOpponentTopLibraryViewResolvesWithOneUseApproval(t *testing.T) {
	setup := newPrivateZoneConsentSetup(t)
	setup.room.Game.Seats[1].Library = []protocol.GameCard{
		{ID: "s1-top1", Name: "Remote One", OwnerSeat: 1},
		{ID: "s1-top2", Name: "Remote Two", OwnerSeat: 1},
		{ID: "s1-top3", Name: "Remote Three", OwnerSeat: 1},
		{ID: "s1-top4", Name: "Remote Four", OwnerSeat: 1},
	}
	sourceSeat := 1
	dump, err := protocol.NewEnvelope(protocol.TypeGameDumpZone,
		protocol.GameDumpZone{
			Zone: protocol.ZoneLibrary, Seat: &sourceSeat, TopCount: 3,
		})
	if err != nil {
		t.Fatalf("build remote top dump: %v", err)
	}
	dump.ID = "dump-remote-top"
	if err := setup.handler.handleGameDumpZone(setup.host, dump); err != nil {
		t.Fatalf("request remote top dump: %v", err)
	}
	_ = receivePrivateZoneEnvelope(t, setup.host)
	requested := receivePrivateZoneEnvelope(t, setup.guest)
	var requestedPayload protocol.GameZoneDumpRequested
	if err := requested.DecodePayload(&requestedPayload); err != nil {
		t.Fatalf("decode remote top request: %v", err)
	}
	response, err := protocol.NewEnvelope(protocol.TypeGameRespondZoneDump,
		protocol.GameRespondZoneDump{
			ApprovalID: requestedPayload.ApprovalID, Approved: true,
		})
	if err != nil {
		t.Fatalf("build remote top approval: %v", err)
	}
	response.ID = "approve-remote-top"
	if err := setup.handler.handleGameRespondZoneDump(setup.guest, response); err != nil {
		t.Fatalf("approve remote top dump: %v", err)
	}
	_ = receivePrivateZoneEnvelope(t, setup.guest)
	dumped := receivePrivateZoneEnvelope(t, setup.host)
	var dumpedPayload protocol.GameZoneDumped
	if err := dumped.DecodePayload(&dumpedPayload); err != nil {
		t.Fatalf("decode remote top dump: %v", err)
	}
	if dumpedPayload.ApprovalID != requestedPayload.ApprovalID ||
		len(dumpedPayload.Cards) != 3 {
		t.Fatalf("remote top dump = %+v", dumpedPayload)
	}
	for _, sess := range []*Session{setup.host, setup.guest, setup.spectator} {
		if snapshot := receivePrivateZoneEnvelope(t, sess); snapshot.Type != protocol.TypeGameSnapshot {
			t.Fatalf("dump projection type = %q", snapshot.Type)
		}
	}

	resolve, err := protocol.NewEnvelope(protocol.TypeGameResolveLibraryView,
		protocol.GameResolveLibraryView{
			SelectedCardIDs:    []string{"s1-top1", "s1-top2"},
			RemainderCardIDs:   []string{"s1-top3"},
			ToZone:             protocol.LibraryDestinationBattlefield,
			Position:           &protocol.CardPosition{X: 0.5, Y: 0.5},
			FaceDown:           true,
			SourceSeat:         &sourceSeat,
			ApprovalID:         dumpedPayload.ApprovalID,
			RemainderPlacement: protocol.LibraryPlacementBottom,
		})
	if err != nil {
		t.Fatalf("build remote top resolve: %v", err)
	}
	resolve.ID = "resolve-remote-top"
	if err := setup.handler.handleGameResolveLibraryView(setup.host, resolve); err != nil {
		t.Fatalf("resolve remote top dump: %v", err)
	}
	resolved := receivePrivateZoneEnvelope(t, setup.host)
	if resolved.Type != protocol.TypeGameLibraryViewResolved ||
		resolved.ID != resolve.ID {
		t.Fatalf("remote top resolve acknowledgement = %+v", resolved)
	}
	hostSnapshot := receivePrivateZoneEnvelope(t, setup.host)
	guestSnapshot := receivePrivateZoneEnvelope(t, setup.guest)
	spectatorSnapshot := receivePrivateZoneEnvelope(t, setup.spectator)
	var hostGame protocol.GameSnapshot
	if err := hostSnapshot.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode requester projection: %v", err)
	}
	if len(hostGame.Seats[0].Battlefield) != 2 ||
		hostGame.Seats[0].Battlefield[0].Name != "Remote One" ||
		hostGame.Seats[0].Battlefield[1].Name != "Remote Two" ||
		!hostGame.Seats[0].Battlefield[0].FaceDown ||
		!hostGame.Seats[0].Battlefield[1].FaceDown {
		t.Fatalf("requester battlefield projection = %+v", hostGame.Seats[0])
	}
	for name, snapshot := range map[string]protocol.Envelope{
		"target": guestSnapshot, "spectator": spectatorSnapshot,
	} {
		encoded, err := snapshot.Marshal()
		if err != nil {
			t.Fatalf("marshal %s projection: %v", name, err)
		}
		for _, secret := range []string{"Remote One", "Remote Two", "Remote Three"} {
			if strings.Contains(string(encoded), secret) {
				t.Fatalf("%s learned remote top identity %q: %s",
					name, secret, encoded)
			}
		}
		var projected protocol.GameSnapshot
		if err := snapshot.DecodePayload(&projected); err != nil {
			t.Fatalf("decode %s projection: %v", name, err)
		}
		if len(projected.Seats[0].Battlefield) != 2 ||
			!projected.Seats[0].Battlefield[0].FaceDown ||
			!projected.Seats[0].Battlefield[1].FaceDown ||
			projected.Seats[0].Battlefield[0].Name != "" ||
			projected.Seats[0].Battlefield[1].Name != "" {
			t.Fatalf("%s face-down projection = %+v",
				name, projected.Seats[0].Battlefield)
		}
	}
	library := setup.room.Game.Seats[1].Library
	if len(library) != 2 || library[0].ID != "s1-top4" ||
		library[1].ID != "s1-top3" {
		t.Fatalf("resolved source library = %+v", library)
	}
	log := setup.room.Game.Log[len(setup.room.Game.Log)-1]
	if log.Kind != "library_view" ||
		!strings.Contains(log.Text,
			"put 2 card(s) face down onto battlefield") ||
		strings.Contains(log.Text, "Remote One") ||
		strings.Contains(log.Text, "Remote Two") {
		t.Fatalf("remote face-down resolve log = %+v", log)
	}

	reused := resolve
	reused.ID = "resolve-remote-top-reused"
	if err := setup.handler.handleGameResolveLibraryView(setup.host, reused); err != nil {
		t.Fatalf("reuse remote top resolve handler: %v", err)
	}
	assertPrivateZoneError(t, receivePrivateZoneEnvelope(t, setup.host),
		reused.ID, protocol.ErrApprovalExpired,
		"library access approval expired")
}

func TestOpponentLibraryConsentDenialAndPendingArePrivate(t *testing.T) {
	t.Run("duplicate pending request", func(t *testing.T) {
		setup := newPrivateZoneConsentSetup(t)
		request := loadPrivateZoneFixture(t, "game-dump-zone-opponent.json")
		if err := setup.handler.handleGameDumpZone(setup.host, request); err != nil {
			t.Fatalf("first dump request: %v", err)
		}
		_ = receivePrivateZoneEnvelope(t, setup.host)
		_ = receivePrivateZoneEnvelope(t, setup.guest)

		duplicate := request
		duplicate.ID = "dump-opponent-duplicate"
		if err := setup.handler.handleGameDumpZone(setup.host, duplicate); err != nil {
			t.Fatalf("duplicate dump request: %v", err)
		}
		assertPrivateZoneError(t, receivePrivateZoneEnvelope(t, setup.host),
			duplicate.ID, protocol.ErrApprovalPending,
			"target player already has a library access request")
		assertNoPrivateZoneEnvelope(t, setup.guest)
		assertNoPrivateZoneEnvelope(t, setup.spectator)
	})

	t.Run("denied request", func(t *testing.T) {
		setup := newPrivateZoneConsentSetup(t)
		request := loadPrivateZoneFixture(t, "game-dump-zone-opponent.json")
		if err := setup.handler.handleGameDumpZone(setup.host, request); err != nil {
			t.Fatalf("dump request: %v", err)
		}
		_ = receivePrivateZoneEnvelope(t, setup.host)
		requested := receivePrivateZoneEnvelope(t, setup.guest)
		var requestedPayload protocol.GameZoneDumpRequested
		if err := requested.DecodePayload(&requestedPayload); err != nil {
			t.Fatalf("decode requested payload: %v", err)
		}

		response, err := protocol.NewEnvelope(protocol.TypeGameRespondZoneDump,
			protocol.GameRespondZoneDump{
				ApprovalID: requestedPayload.ApprovalID,
				Approved:   false,
			})
		if err != nil {
			t.Fatalf("build denial response: %v", err)
		}
		response.ID = "deny-zone-dump"
		if err := setup.handler.handleGameRespondZoneDump(setup.guest, response); err != nil {
			t.Fatalf("deny dump request: %v", err)
		}
		responded := receivePrivateZoneEnvelope(t, setup.guest)
		if responded.Type != protocol.TypeGameZoneDumpResponded ||
			responded.ID != response.ID {
			t.Fatalf("denial acknowledgement = %+v", responded)
		}
		var respondedPayload protocol.GameZoneDumpResponded
		if err := responded.DecodePayload(&respondedPayload); err != nil {
			t.Fatalf("decode denial acknowledgement: %v", err)
		}
		if respondedPayload.Approved ||
			respondedPayload.ApprovalID != requestedPayload.ApprovalID {
			t.Fatalf("denial acknowledgement payload = %+v", respondedPayload)
		}
		assertPrivateZoneError(t, receivePrivateZoneEnvelope(t, setup.host),
			request.ID, protocol.ErrPermissionDenied, "library access was denied")
		assertNoPrivateZoneEnvelope(t, setup.spectator)

		retry := response
		retry.ID = "deny-zone-dump-reused"
		if err := setup.handler.handleGameRespondZoneDump(setup.guest, retry); err != nil {
			t.Fatalf("reuse denial response: %v", err)
		}
		assertPrivateZoneError(t, receivePrivateZoneEnvelope(t, setup.guest),
			retry.ID, protocol.ErrApprovalExpired, "library access request expired")
		assertNoPrivateZoneEnvelope(t, setup.host)
		assertNoPrivateZoneEnvelope(t, setup.spectator)
	})
}

func TestOwnLibraryViewAndReorderMatchGoldenFixtures(t *testing.T) {
	setup := newPrivateZoneConsentSetup(t)
	setup.room.Game.Seats[0].Library = []protocol.GameCard{
		{ID: "s0-c8", Name: "Island", SetCode: "M21", CollectorNumber: "265", OwnerSeat: 0},
		{ID: "s0-c9", Name: "Demonic Tutor", SetCode: "STA", CollectorNumber: "27", OwnerSeat: 0},
	}

	dumpRequest := loadPrivateZoneFixture(t, "game-dump-zone.json")
	if err := setup.handler.handleGameDumpZone(setup.host, dumpRequest); err != nil {
		t.Fatalf("handle own dump: %v", err)
	}
	dumped := receivePrivateZoneEnvelope(t, setup.host)
	assertPrivateZoneFixture(t, "game-zone-dumped.json", setup.room.ID, dumped)
	for name, sess := range map[string]*Session{
		"requester": setup.host, "opponent": setup.guest, "spectator": setup.spectator,
	} {
		snapshot := receivePrivateZoneEnvelope(t, sess)
		if snapshot.Type != protocol.TypeGameSnapshot {
			t.Fatalf("%s received %q after own library dump", name, snapshot.Type)
		}
		if name != "requester" {
			encoded, err := snapshot.Marshal()
			if err != nil {
				t.Fatalf("marshal %s snapshot: %v", name, err)
			}
			if strings.Contains(string(encoded), "Island") ||
				strings.Contains(string(encoded), "Demonic Tutor") {
				t.Fatalf("%s received private library identities: %s", name, encoded)
			}
		}
	}

	reorderRequest := loadPrivateZoneFixture(t, "game-reorder-library.json")
	if err := setup.handler.handleGameReorderLibrary(setup.host, reorderRequest); err != nil {
		t.Fatalf("handle reorder: %v", err)
	}
	reordered := receivePrivateZoneEnvelope(t, setup.host)
	assertPrivateZoneFixture(t, "game-library-reordered.json", setup.room.ID, reordered)
	if library := setup.room.Game.Seats[0].Library; len(library) != 2 || library[0].ID != "s0-c9" || library[1].ID != "s0-c8" {
		t.Fatalf("reordered library = %+v", library)
	}
	for name, sess := range map[string]*Session{
		"requester": setup.host, "opponent": setup.guest, "spectator": setup.spectator,
	} {
		snapshot := receivePrivateZoneEnvelope(t, sess)
		if snapshot.Type != protocol.TypeGameSnapshot {
			t.Fatalf("%s received %q after reorder", name, snapshot.Type)
		}
		if name != "requester" {
			encoded, err := snapshot.Marshal()
			if err != nil {
				t.Fatalf("marshal %s reorder snapshot: %v", name, err)
			}
			if strings.Contains(string(encoded), "Island") ||
				strings.Contains(string(encoded), "Demonic Tutor") {
				t.Fatalf("%s learned reordered identities: %s", name, encoded)
			}
		}
	}
}

func TestResolveOwnLibraryViewMatchesGoldenFixtureAndPrivacy(t *testing.T) {
	setup := newPrivateZoneConsentSetup(t)
	setup.room.Game.Seats[0].Library = []protocol.GameCard{
		{ID: "s0-c8", Name: "Island", SetCode: "M21", CollectorNumber: "265", OwnerSeat: 0},
		{ID: "s0-c10", Name: "Forest", SetCode: "M21", CollectorNumber: "274", OwnerSeat: 0},
		{ID: "s0-c9", Name: "Demonic Tutor", SetCode: "STA", CollectorNumber: "27", OwnerSeat: 0},
	}

	request := loadPrivateZoneFixture(t, "game-resolve-library-view.json")
	if err := setup.handler.handleGameResolveLibraryView(setup.host, request); err != nil {
		t.Fatalf("handle resolve library view: %v", err)
	}
	resolved := receivePrivateZoneEnvelope(t, setup.host)
	assertPrivateZoneFixture(t, "game-library-view-resolved.json", setup.room.ID, resolved)

	state := setup.room.Game.Seats[0]
	if len(state.Library) != 1 || state.Library[0].ID != "s0-c9" ||
		len(state.Battlefield) != 2 || !state.Battlefield[0].FaceDown ||
		!state.Battlefield[1].FaceDown || state.Battlefield[0].Position == nil ||
		state.Battlefield[1].Position == nil {
		t.Fatalf("resolved library state = %+v", state)
	}
	log := setup.room.Game.Log[len(setup.room.Game.Log)-1]
	if log.Kind != "library_view" ||
		!strings.Contains(log.Text,
			"put 2 card(s) face down onto battlefield") ||
		strings.Contains(log.Text, "Island") ||
		strings.Contains(log.Text, "Forest") {
		t.Fatalf("own face-down resolve log = %+v", log)
	}

	hostSnapshot := receivePrivateZoneEnvelope(t, setup.host)
	guestSnapshot := receivePrivateZoneEnvelope(t, setup.guest)
	spectatorSnapshot := receivePrivateZoneEnvelope(t, setup.spectator)
	for name, envelope := range map[string]protocol.Envelope{
		"requester": hostSnapshot, "opponent": guestSnapshot, "spectator": spectatorSnapshot,
	} {
		if envelope.Type != protocol.TypeGameSnapshot {
			t.Fatalf("%s received %q after resolve", name, envelope.Type)
		}
	}
	for name, envelope := range map[string]protocol.Envelope{
		"opponent": guestSnapshot, "spectator": spectatorSnapshot,
	} {
		encoded, err := envelope.Marshal()
		if err != nil {
			t.Fatalf("marshal %s resolve snapshot: %v", name, err)
		}
		for _, secret := range []string{"Island", "Forest", "Demonic Tutor"} {
			if strings.Contains(string(encoded), secret) {
				t.Fatalf("%s learned private library identity %q: %s", name, secret, encoded)
			}
		}
	}
}
