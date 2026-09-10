// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"fmt"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/tournament"
)

func cubeRoomRequest(seats int) protocol.TournamentCreate {
	return protocol.TournamentCreate{
		Name: "Room Cube", Format: "Cube", EventType: protocol.LimitedEventCubeDraft,
		Coordinator: protocol.LimitedCoordinatorCasual, MatchMode: protocol.MatchBO1,
		MaxPlayers: seats,
		Product: &protocol.LimitedProductDefinition{ID: "room-cube", Name: "Room Cube", ProductType: "cube",
			Sheets: []protocol.LimitedSheetDefinition{{Name: "pool", Cards: []protocol.LimitedCardDefinition{
				{Name: "Test Creature", SetCode: "TST", CollectorNumber: "1", TypeLine: "Creature", Weight: seats * 45},
			}}}},
	}
}

func cubeCommandEnvelope(t *testing.T, kind string, payload any) protocol.Envelope {
	t.Helper()
	env, err := protocol.NewEnvelope(kind, payload)
	if err != nil {
		t.Fatal(err)
	}
	env.ID = "cube-test"
	return env
}

func cubeReply(t *testing.T, sess *Session) protocol.Envelope {
	t.Helper()
	for _, env := range drainProjection(t, sess) {
		if env.ID == "cube-test" {
			return env
		}
	}
	t.Fatal("Cube command has no reply")
	return protocol.Envelope{}
}

func cubeTestSession(h *Handler, index int) *Session {
	sess := &Session{ConnectionID: fmt.Sprintf("cube-conn-%d", index), DisplayName: fmt.Sprintf("Cube player %d", index),
		RemoteIP: fmt.Sprintf("192.0.2.%d", index+1), Send: make(chan []byte, 512)}
	h.registerSession(sess)
	return sess
}

func createCubeRoomHarness(t *testing.T, seats int) (*Handler, *tournamentEntry, []*Session, string) {
	t.Helper()
	h := NewHandler()
	host := cubeTestSession(h, 0)
	if err := h.handleTournamentCreate(host, cubeCommandEnvelope(t, protocol.TypeTournamentCreate, cubeRoomRequest(seats))); err != nil {
		t.Fatal(err)
	}
	created := cubeReply(t, host)
	var payload protocol.TournamentCreated
	if err := created.DecodePayload(&payload); err != nil {
		t.Fatal(err)
	}
	if len(payload.TournamentID) != 6 || host.Tournament().ParticipantID == "" {
		t.Fatalf("Cube creation did not provide room identity and host seat: %s", created.Payload)
	}
	entry := h.tournaments.entry(payload.TournamentID)
	return h, entry, []*Session{host}, payload.OrganizerToken
}

func joinCubeRoomHarness(t *testing.T, h *Handler, entry *tournamentEntry, index int) (*Session, string) {
	t.Helper()
	sess := cubeTestSession(h, index)
	if err := h.handleRoomJoin(sess, cubeCommandEnvelope(t, protocol.TypeRoomJoin,
		protocol.RoomJoin{RoomID: entry.event.ID})); err != nil {
		t.Fatal(err)
	}
	token := ""
	for _, env := range drainProjection(t, sess) {
		if env.Type == protocol.TypeError {
			t.Fatalf("join Cube: %s", env.Payload)
		}
		if env.Type == protocol.TypeTournamentRegistered {
			var registered protocol.TournamentRegistered
			_ = env.DecodePayload(&registered)
			token = registered.ParticipantToken
		}
	}
	if token == "" || sess.Tournament().ParticipantID == "" {
		t.Fatal("Cube room join did not seat and issue credential")
	}
	return sess, token
}

func TestCubeRoomsDiscoverJoinReadyAndReenter(t *testing.T) {
	h, entry, sessions, hostToken := createCubeRoomHarness(t, 3)
	host := sessions[0]
	guest, guestToken := joinCubeRoomHarness(t, h, entry, 1)
	id := entry.event.ID
	rooms := h.listRooms(guest)
	if len(rooms) != 1 || rooms[0].RoomKind != "cube" || rooms[0].DeckFormat != "cube" ||
		rooms[0].PlayerCount != 2 || rooms[0].MaxSeats != 3 || !rooms[0].PlayerJoinable || !rooms[0].SpectatorJoinable {
		t.Fatalf("bad public Cube room projection: %+v", rooms)
	}
	if len(h.tournaments.list()) != 0 {
		t.Fatal("Cube room leaked into the tournament browser")
	}
	outsider := cubeTestSession(h, 2)
	_ = h.handleRoomJoin(outsider, cubeCommandEnvelope(t, protocol.TypeRoomJoin,
		protocol.RoomJoin{RoomID: id, AsSpectator: true, Credential: guestToken}))
	if reply := cubeReply(t, outsider); reply.Type != protocol.TypeTournamentEntered ||
		outsider.Tournament().ParticipantID != "" || outsider.Tournament().Role != tournament.RoleViewer ||
		len(entry.event.Participants) != 2 || entry.event.Participant(guest.Tournament().ParticipantID).ConnectionID != guest.ConnectionID {
		t.Fatal("explicit spectator entry consumed a Cube seat or bound the supplied credential")
	}
	_ = h.handleTournamentLeave(outsider, cubeCommandEnvelope(t, protocol.TypeTournamentLeave, protocol.EmptyPayload{}))
	if cubeReply(t, outsider).Type != protocol.TypeTournamentLeft {
		t.Fatal("registration-stage viewer could not leave without unregistering")
	}
	_ = h.handleTournamentCheckIn(host, cubeCommandEnvelope(t, protocol.TypeTournamentCheckIn, protocol.TournamentCheckIn{CheckedIn: true}))
	_ = cubeReply(t, host)
	_ = h.handleTournamentStart(host, cubeCommandEnvelope(t, protocol.TypeTournamentStart, protocol.EmptyPayload{}))
	if reply := cubeReply(t, host); reply.Type != protocol.TypeError || entry.event.Limited != nil {
		t.Fatal("host started with an unready occupied seat")
	}
	_ = h.handleTournamentCheckIn(host, cubeCommandEnvelope(t, protocol.TypeTournamentCheckIn,
		protocol.TournamentCheckIn{ParticipantID: guest.Tournament().ParticipantID, CheckedIn: true}))
	if reply := cubeReply(t, host); reply.Type != protocol.TypeError {
		t.Fatal("host readied another player")
	}
	_ = h.handleTournamentCheckIn(guest, cubeCommandEnvelope(t, protocol.TypeTournamentCheckIn, protocol.TournamentCheckIn{CheckedIn: true}))
	_ = cubeReply(t, guest)
	entry.event.Disconnect(guest.ConnectionID, time.Now())
	_ = h.handleTournamentStart(host, cubeCommandEnvelope(t, protocol.TypeTournamentStart, protocol.EmptyPayload{}))
	if reply := cubeReply(t, host); reply.Type != protocol.TypeError {
		t.Fatal("host omitted disconnected seat from the draft")
	}
	_ = h.handleRoomJoin(outsider, cubeCommandEnvelope(t, protocol.TypeRoomJoin,
		protocol.RoomJoin{RoomID: id, Credential: guestToken}))
	if reply := cubeReply(t, outsider); reply.Type != protocol.TypeTournamentEntered {
		t.Fatalf("credential recovery failed: %s", reply.Payload)
	}
	_ = h.handleTournamentCheckIn(guest, cubeCommandEnvelope(t, protocol.TypeTournamentCheckIn, protocol.TournamentCheckIn{CheckedIn: true}))
	if reply := cubeReply(t, guest); reply.Type != protocol.TypeError {
		t.Fatal("transferred credential retained readiness authority on old connection")
	}
	_ = h.handleTournamentCheckIn(outsider, cubeCommandEnvelope(t, protocol.TypeTournamentCheckIn, protocol.TournamentCheckIn{CheckedIn: true}))
	_ = cubeReply(t, outsider)
	_ = h.handleTournamentStart(host, cubeCommandEnvelope(t, protocol.TypeTournamentStart, protocol.EmptyPayload{}))
	if reply := cubeReply(t, host); reply.Type != protocol.TypeTournamentStarted || entry.event.Stage != protocol.LimitedStageDraft {
		t.Fatalf("all-ready room failed to start: %s", reply.Payload)
	}
	poolBefore := entry.event.LimitedSnapshot(outsider.Tournament().ParticipantID)
	_ = h.handleTournamentLeave(outsider, cubeCommandEnvelope(t, protocol.TypeTournamentLeave, protocol.EmptyPayload{}))
	_ = cubeReply(t, outsider)
	if len(entry.event.Participants) != 2 {
		t.Fatal("draft departure destroyed a participant's pool")
	}
	_ = h.handleRoomJoin(outsider, cubeCommandEnvelope(t, protocol.TypeRoomJoin,
		protocol.RoomJoin{RoomID: id, Credential: guestToken}))
	if reply := cubeReply(t, outsider); reply.Type != protocol.TypeTournamentEntered {
		t.Fatalf("draft reentry: %s", reply.Payload)
	}
	poolAfter := entry.event.LimitedSnapshot(outsider.Tournament().ParticipantID)
	if len(poolBefore.CurrentPack) != len(poolAfter.CurrentPack) || poolBefore.CurrentPack[0].InstanceID != poolAfter.CurrentPack[0].InstanceID {
		t.Fatal("draft reentry did not restore the same private pack")
	}
	if !h.listRooms(outsider)[0].PlayerJoinable || h.listRooms(guest)[0].PlayerJoinable {
		t.Fatal("running Cube joinability did not respect current seat binding")
	}
	entry.event.Disconnect(host.ConnectionID, time.Now())
	if entry.event.IsTerminal() {
		t.Fatal("host disconnect closed the room")
	}
	newHost := cubeTestSession(h, 3)
	_ = h.handleRoomJoin(newHost, cubeCommandEnvelope(t, protocol.TypeRoomJoin,
		protocol.RoomJoin{RoomID: id, Credential: hostToken}))
	if reply := cubeReply(t, newHost); reply.Type != protocol.TypeTournamentEntered || newHost.Tournament().Role != tournament.RoleOrganizer {
		t.Fatal("host credential did not recover the host seat")
	}
	_ = h.handleTournamentLeave(newHost, cubeCommandEnvelope(t, protocol.TypeTournamentLeave, protocol.EmptyPayload{}))
	if reply := cubeReply(t, newHost); reply.Type != protocol.TypeTournamentLeft || !entry.event.IsTerminal() || len(h.listRooms(outsider)) != 0 {
		t.Fatal("host explicit leave did not close and unlist the Cube room")
	}
	_ = h.handleRoomJoin(guest, cubeCommandEnvelope(t, protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: id, Credential: guestToken}))
	if reply := cubeReply(t, guest); reply.Type != protocol.TypeError {
		t.Fatal("closed Cube room accepted reentry")
	}
}

func TestCubeRegistrationLeaveFreesSeatAndConcurrentInvitationsReserveOnce(t *testing.T) {
	h, entry, sessions, _ := createCubeRoomHarness(t, 3)
	first, _ := joinCubeRoomHarness(t, h, entry, 1)
	_ = h.handleTournamentLeave(first, cubeCommandEnvelope(t, protocol.TypeTournamentLeave, protocol.EmptyPayload{}))
	_ = cubeReply(t, first)
	if len(entry.event.Participants) != 1 {
		t.Fatal("leaving before draft did not free the seat")
	}
	a, _ := joinCubeRoomHarness(t, h, entry, 2)
	b, _ := joinCubeRoomHarness(t, h, entry, 3)
	sessions = append(sessions, a, b)
	entry.event.Status, entry.event.Stage = tournament.StatusRunning, protocol.LimitedStageCompetition
	for _, participant := range entry.event.Participants {
		participant.Competing = true
		participant.Deck = &protocol.DeckSelect{Name: "Submitted deck"}
	}
	for _, sess := range sessions {
		drainProjection(t, sess)
	}
	var workers sync.WaitGroup
	for _, challenger := range sessions[:2] {
		workers.Add(1)
		go func(sess *Session) {
			defer workers.Done()
			env, _ := protocol.NewEnvelope(protocol.TypeLimitedCreateCasualMatch, protocol.LimitedCreateCasualMatch{
				PlayerAID: sess.Tournament().ParticipantID, PlayerBID: b.Tournament().ParticipantID,
			})
			env.ID = "cube-test"
			_ = h.handleLimitedCreateCasualMatch(sess, env)
		}(challenger)
	}
	workers.Wait()
	accepted := 0
	for _, sess := range sessions[:2] {
		if cubeReply(t, sess).Type == protocol.TypeLimitedCasualMatchCreated {
			accepted++
		}
	}
	if accepted != 1 || len(entry.event.CasualPairings) != 1 || !entry.event.CasualPairings[0].Invited {
		t.Fatal("concurrent challenges reserved the same opponent more than once")
	}
	pair := entry.event.CasualPairings[0]
	_ = h.handleLimitedCreateCasualMatch(b, cubeCommandEnvelope(t, protocol.TypeLimitedCreateCasualMatch,
		protocol.LimitedCreateCasualMatch{PlayerAID: pair.PlayerAID, PlayerBID: pair.PlayerBID, Action: "cancel"}))
	if cubeReply(t, b).Type != protocol.TypeLimitedCasualMatchCreated || len(entry.event.CasualPairings) != 0 {
		t.Fatal("invite recipient could not decline and release both players")
	}
}

func TestCubeRoomCodesShareRoomCapacityAndCannotCollide(t *testing.T) {
	hub := NewHubWithLimit(1)
	if err := hub.reserveCubeRoomID("ABCDEF"); err != nil {
		t.Fatal(err)
	}
	if err := hub.reserveCubeRoomID("ABCDEF"); err == nil {
		t.Fatal("duplicate Cube code accepted")
	}
	if err := hub.reserveCubeRoomID("BCDEFG"); err == nil {
		t.Fatal("Cube rooms bypassed room capacity")
	}
	host := testTournamentSession("capacity-host", "192.0.2.90")
	if _, _, _, _, err := hub.CreateRoom("Table", "modern", "bo1", "background", 2, false, false, "", host); err == nil {
		t.Fatal("normal table ignored reserved Cube room capacity")
	}
	hub.releaseCubeRoomID("ABCDEF")
	r, _, _, operation, err := hub.CreateRoom("Table", "modern", "bo1", "background", 2, false, false, "", host)
	if err != nil {
		t.Fatal(err)
	}
	operation.opMu.Unlock()
	if err := hub.reserveCubeRoomID(r.ID); err == nil {
		t.Fatal("Cube code collided with ordinary room")
	}
}

func TestCubeMembershipRequiresExplicitLeaveBeforeCrossRoomNavigation(t *testing.T) {
	h, entry, sessions, hostToken := createCubeRoomHarness(t, 2)
	host := sessions[0]
	guest, guestToken := joinCubeRoomHarness(t, h, entry, 1)
	outOfPod := cubeTestSession(h, 20)
	otherRoom, _, _, operation, err := h.hub.CreateRoom("Another table", "modern", "bo1", "background", 2, true, false, "", outOfPod)
	if err != nil {
		t.Fatal(err)
	}
	operation.opMu.Unlock()
	otherCubeHost := cubeTestSession(h, 21)
	_ = h.handleTournamentCreate(otherCubeHost,
		cubeCommandEnvelope(t, protocol.TypeTournamentCreate, cubeRoomRequest(2)))
	_ = cubeReply(t, otherCubeHost)
	otherCubeID := otherCubeHost.Tournament().TournamentID
	swissOrganizer := cubeTestSession(h, 22)
	swissRequest := protocol.TournamentCreate{Name: "Swiss event", Format: "modern", MatchMode: "bo1", MaxPlayers: 8}
	_ = h.handleTournamentCreate(swissOrganizer,
		cubeCommandEnvelope(t, protocol.TypeTournamentCreate, swissRequest))
	_ = cubeReply(t, swissOrganizer)
	swissID := swissOrganizer.Tournament().TournamentID
	roomRequest := protocol.RoomCreate{Name: "New table", Format: "modern", MatchMode: "bo1"}
	tests := []struct {
		name    string
		kind    string
		payload any
		handle  func(*Session, protocol.Envelope) error
	}{
		{"create ordinary table", protocol.TypeRoomCreate, roomRequest, h.handleRoomCreate},
		{"create tournament", protocol.TypeTournamentCreate, swissRequest, h.handleTournamentCreate},
		{"create Cube", protocol.TypeTournamentCreate, cubeRoomRequest(2), h.handleTournamentCreate},
		{"join ordinary table", protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: otherRoom.ID}, h.handleRoomJoin},
		{"watch unrelated table", protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: otherRoom.ID, AsSpectator: true}, h.handleRoomJoin},
		{"join another Cube", protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: otherCubeID}, h.handleRoomJoin},
		{"enter another Cube", protocol.TypeTournamentEnter, protocol.TournamentEnter{TournamentID: otherCubeID}, h.handleTournamentEnter},
		{"enter tournament", protocol.TypeTournamentEnter, protocol.TournamentEnter{TournamentID: swissID}, h.handleTournamentEnter},
	}
	for _, stage := range []string{"registration", "draft"} {
		for index, sess := range []*Session{host, guest} {
			if stage == "registration" {
				_ = h.handleTournamentCheckIn(sess, cubeCommandEnvelope(t, protocol.TypeTournamentCheckIn,
					protocol.TournamentCheckIn{CheckedIn: true}))
				_ = cubeReply(t, sess)
			}
			for _, test := range tests {
				t.Run(fmt.Sprintf("%s/player-%d/%s", stage, index, test.name), func(t *testing.T) {
					before := sess.Tournament()
					count := len(h.tournaments.snapshot())
					_ = test.handle(sess, cubeCommandEnvelope(t, test.kind, test.payload))
					reply := cubeReply(t, sess)
					var failure protocol.ErrorPayload
					_ = reply.DecodePayload(&failure)
					if reply.Type != protocol.TypeError || failure.Code != protocol.ErrAlreadyInRoom {
						t.Fatalf("navigation bypassed Cube leave: %s %s", reply.Type, reply.Payload)
					}
					if sess.Tournament() != before || sess.Room() != nil || len(h.tournaments.snapshot()) != count ||
						len(entry.event.Participants) != 2 || !entry.event.Participant(before.ParticipantID).CheckedIn {
						t.Fatal("rejected navigation changed membership, readiness, or created another event")
					}
				})
			}
			credential := guestToken
			if sess == host {
				credential = hostToken
			}
			_ = h.handleRoomJoin(sess, cubeCommandEnvelope(t, protocol.TypeRoomJoin,
				protocol.RoomJoin{RoomID: entry.event.ID, Credential: credential}))
			if cubeReply(t, sess).Type != protocol.TypeTournamentEntered {
				t.Fatal("same-pod credential entry was blocked by navigation guard")
			}
		}
		if stage == "registration" {
			_ = h.handleTournamentStart(host, cubeCommandEnvelope(t, protocol.TypeTournamentStart, protocol.EmptyPayload{}))
			if cubeReply(t, host).Type != protocol.TypeTournamentStarted {
				t.Fatal("ready pod could not start after rejected cross-room navigation")
			}
		}
	}
	_ = h.handleTournamentLeave(guest, cubeCommandEnvelope(t, protocol.TypeTournamentLeave, protocol.EmptyPayload{}))
	if cubeReply(t, guest).Type != protocol.TypeTournamentLeft {
		t.Fatal("guest could not explicitly leave")
	}
	_ = h.handleRoomJoin(guest, cubeCommandEnvelope(t, protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: otherRoom.ID}))
	if cubeReply(t, guest).Type != protocol.TypeRoomJoined {
		t.Fatal("guest could not join another table after leaving the Cube pod")
	}
	_ = h.handleRoomLeave(guest, cubeCommandEnvelope(t, protocol.TypeRoomLeave, protocol.EmptyPayload{}))
	_ = cubeReply(t, guest)
	_ = h.handleTournamentLeave(host, cubeCommandEnvelope(t, protocol.TypeTournamentLeave, protocol.EmptyPayload{}))
	_ = cubeReply(t, host)
	_ = h.handleRoomCreate(host, cubeCommandEnvelope(t, protocol.TypeRoomCreate, roomRequest))
	if cubeReply(t, host).Type != protocol.TypeRoomCreated || !entry.event.IsTerminal() {
		t.Fatal("host could not create a table after explicitly closing the Cube pod")
	}
	// A Swiss event is still a background coordinator; its established ability
	// to create ordinary tables does not inherit Cube's room exclusivity.
	_ = h.handleRoomCreate(swissOrganizer, cubeCommandEnvelope(t, protocol.TypeRoomCreate, roomRequest))
	if cubeReply(t, swissOrganizer).Type != protocol.TypeRoomCreated || swissOrganizer.Tournament().TournamentID != swissID {
		t.Fatal("Cube navigation guard changed Swiss organization semantics")
	}
}

func TestCubeViewerReconnectCannotImplicitlyRegisterOrReceiveAPool(t *testing.T) {
	h, entry, _, _ := createCubeRoomHarness(t, 2)
	watcher := cubeTestSession(h, 40)
	_ = h.handleRoomJoin(watcher, cubeCommandEnvelope(t, protocol.TypeRoomJoin,
		protocol.RoomJoin{RoomID: entry.event.ID, AsSpectator: true}))
	if cubeReply(t, watcher).Type != protocol.TypeTournamentEntered {
		t.Fatal("initial public Cube view failed")
	}
	_ = h.handleTournamentRegister(watcher, cubeCommandEnvelope(t, protocol.TypeTournamentRegister,
		protocol.TournamentRegister{TournamentID: entry.event.ID}))
	if cubeReply(t, watcher).Type != protocol.TypeError || len(entry.event.Participants) != 1 {
		t.Fatal("tournament.register bypassed explicit Cube room joining")
	}
	h.unregisterSession(watcher)
	reconnected := cubeTestSession(h, 41)
	_ = h.handleTournamentEnter(reconnected, cubeCommandEnvelope(t, protocol.TypeTournamentEnter,
		protocol.TournamentEnter{TournamentID: entry.event.ID}))
	for _, envelope := range drainProjection(t, reconnected) {
		if envelope.Type == protocol.TypeError || envelope.Type == protocol.TypeTournamentRegistered {
			t.Fatalf("viewer resume errored or registered a seat: %s", envelope.Payload)
		}
		if envelope.Type == protocol.TypeLimitedSnapshot {
			var snapshot protocol.LimitedSnapshot
			_ = envelope.DecodePayload(&snapshot)
			if len(snapshot.Pool) != 0 || len(snapshot.CurrentPack) != 0 {
				t.Fatal("viewer reconnect revealed a private Cube pool")
			}
		}
	}
	if reconnected.Tournament().Role != tournament.RoleViewer ||
		reconnected.Tournament().ParticipantID != "" || len(entry.event.Participants) != 1 {
		t.Fatal("public-view reconnect implicitly consumed a draft seat")
	}
	// Taking a seat is a separate, explicit room command, even for a viewer.
	_ = h.handleRoomJoin(reconnected, cubeCommandEnvelope(t, protocol.TypeRoomJoin,
		protocol.RoomJoin{RoomID: entry.event.ID}))
	if cubeReply(t, reconnected).Type != protocol.TypeTournamentEntered ||
		reconnected.Tournament().ParticipantID == "" || len(entry.event.Participants) != 2 {
		t.Fatal("explicit room.join did not allow a viewer to become a player")
	}
	for index := 0; index < protocol.MaxSpectators; index++ {
		viewer := cubeTestSession(h, 50+index)
		_ = h.handleRoomJoin(viewer, cubeCommandEnvelope(t, protocol.TypeRoomJoin,
			protocol.RoomJoin{RoomID: entry.event.ID, AsSpectator: true}))
		if cubeReply(t, viewer).Type != protocol.TypeTournamentEntered {
			t.Fatal("Cube spectator capacity rejected an available seat")
		}
	}
	rooms := h.listRooms(reconnected)
	if rooms[0].SpectatorCount != protocol.MaxSpectators || rooms[0].SpectatorJoinable {
		t.Fatal("Cube public discovery did not reflect the spectator limit")
	}
	extra := cubeTestSession(h, 90)
	_ = h.handleTournamentEnter(extra, cubeCommandEnvelope(t, protocol.TypeTournamentEnter,
		protocol.TournamentEnter{TournamentID: entry.event.ID}))
	var failure protocol.ErrorPayload
	reply := cubeReply(t, extra)
	_ = reply.DecodePayload(&failure)
	if reply.Type != protocol.TypeError || failure.Code != protocol.ErrSpectatorLimit || extra.Tournament().TournamentID != "" {
		t.Fatal("public coordinator entry bypassed the Cube spectator limit")
	}
}

func TestClosingCubeImmediatelyReleasesRegistryCapacityAndAllBindings(t *testing.T) {
	config := DefaultConfig()
	config.MaxTournaments, config.MaxRooms = 1, 1
	config.TournamentCreatesPerMinute = 100
	h, err := NewHandlerWithConfig(config)
	if err != nil {
		t.Fatal(err)
	}
	host := cubeTestSession(h, 0)
	for iteration := 0; iteration < 3; iteration++ {
		_ = h.handleTournamentCreate(host, cubeCommandEnvelope(t, protocol.TypeTournamentCreate, cubeRoomRequest(2)))
		if reply := cubeReply(t, host); reply.Type != protocol.TypeTournamentCreated {
			t.Fatalf("closed Cube consumed registry/room capacity on iteration %d: %s", iteration, reply.Payload)
		}
		id := host.Tournament().TournamentID
		entry := h.tournaments.entry(id)
		guest, _ := joinCubeRoomHarness(t, h, entry, 100+iteration)
		_ = h.handleTournamentLeave(host, cubeCommandEnvelope(t, protocol.TypeTournamentLeave, protocol.EmptyPayload{}))
		if cubeReply(t, host).Type != protocol.TypeTournamentLeft || h.tournaments.entry(id) != nil ||
			host.Tournament().TournamentID != "" || guest.Tournament().TournamentID != "" {
			t.Fatal("host closure retained a Cube registry entry or session binding")
		}
		cancelled, left := false, false
		for _, envelope := range drainProjection(t, guest) {
			switch envelope.Type {
			case protocol.TypeTournamentSnapshot:
				var snapshot protocol.TournamentSnapshot
				_ = envelope.DecodePayload(&snapshot)
				cancelled = snapshot.Status == tournament.StatusCancelled
			case protocol.TypeTournamentLeft:
				if !cancelled {
					t.Fatal("Cube guest received terminal leave before its cancelled state")
				}
				left = true
			}
		}
		if !cancelled || !left || len(h.hub.reservedRoomIDs) != 0 {
			t.Fatal("Cube closure did not notify guests and release the room code immediately")
		}
	}
}

func TestClosingCubeCannotDetachAMemberWhoAlreadyEnteredAnotherPod(t *testing.T) {
	h, original, sessions, _ := createCubeRoomHarness(t, 2)
	host := sessions[0]
	guest, _ := joinCubeRoomHarness(t, h, original, 1)
	otherHost := cubeTestSession(h, 2)
	_ = h.handleTournamentCreate(otherHost, cubeCommandEnvelope(t, protocol.TypeTournamentCreate, cubeRoomRequest(2)))
	if cubeReply(t, otherHost).Type != protocol.TypeTournamentCreated {
		t.Fatal("second Cube creation failed")
	}
	destinationID := otherHost.Tournament().TournamentID
	for _, sess := range []*Session{host, guest, otherHost} {
		drainProjection(t, sess)
	}
	serializingLeft, resumeLeft, enteredDestination := make(chan struct{}), make(chan struct{}), make(chan struct{})
	var paused, entered atomic.Bool
	h.marshalEnvelope = func(env protocol.Envelope) ([]byte, error) {
		if env.Type == protocol.TypeTournamentLeft && paused.CompareAndSwap(false, true) {
			close(serializingLeft)
			<-resumeLeft
		}
		if env.Type == protocol.TypeTournamentEntered && entered.CompareAndSwap(false, true) {
			close(enteredDestination)
		}
		return env.Marshal()
	}
	closeDone, enterDone := make(chan error, 1), make(chan error, 1)
	leave := cubeCommandEnvelope(t, protocol.TypeTournamentLeave, protocol.EmptyPayload{})
	join := cubeCommandEnvelope(t, protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: destinationID})
	go func() { closeDone <- h.handleTournamentLeave(host, leave) }()
	select {
	case <-serializingLeft:
	case <-time.After(3 * time.Second):
		close(resumeLeft)
		t.Fatal("host closure did not reach the captured-membership serialization boundary")
	}
	go func() { enterDone <- h.handleRoomJoin(guest, join) }()
	select {
	case <-enteredDestination:
	case <-time.After(3 * time.Second):
		close(resumeLeft)
		t.Fatal("guest could not enter a new pod after the old pod was cancelled")
	}
	newBinding := guest.Tournament()
	close(resumeLeft)
	for _, done := range []chan error{closeDone, enterDone} {
		select {
		case err := <-done:
			if err != nil {
				t.Fatal(err)
			}
		case <-time.After(3 * time.Second):
			t.Fatal("concurrent Cube close and entry did not finish")
		}
	}
	if newBinding.TournamentID != destinationID || guest.Tournament() != newBinding {
		t.Fatal("old Cube closure detached or changed the newly entered pod binding")
	}
	destination := h.tournaments.entry(destinationID)
	if destination == nil || destination.event.Participant(newBinding.ParticipantID).ConnectionID != guest.ConnectionID {
		t.Fatal("old Cube closure disconnected the participant from their new pod")
	}
	for _, envelope := range drainProjection(t, guest) {
		if envelope.Type == protocol.TypeTournamentLeft {
			t.Fatal("a stale terminal leave was delivered after the guest switched pods")
		}
	}
	if h.tournaments.entry(original.event.ID) != nil {
		t.Fatal("race-safe terminal delivery failed to release the closed Cube")
	}
}
