// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/accounts"
	"hexproof/server/internal/buildinfo"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/tournament"
)

func accountCommand(t *testing.T, client *wsClient, q protocol.AccountCommand) protocol.AccountState {
	t.Helper()
	env, _ := protocol.NewEnvelope(protocol.TypeAccountCommand, q)
	env.ID = "account-" + q.Operation
	client.send(env)
	response := client.recvType(protocol.TypeAccountState, protocol.TypeError)
	if response.Type == protocol.TypeError {
		t.Fatalf("account %s failed: %s", q.Operation, response.Payload)
	}
	var state protocol.AccountState
	if err := response.DecodePayload(&state); err != nil {
		t.Fatal(err)
	}
	return state
}

func TestAccountLoginCodeRecoversSeatWithoutLocalCredential(t *testing.T) {
	cfg := DefaultConfig()
	cfg.AccountDir, cfg.AccountRealm = t.TempDir(), "official-test"
	srv, handler := newConfiguredTestServer(t, cfg)
	first := dial(t, srv)
	defer first.close()
	var originalWelcome protocol.SessionWelcome
	first.hello("Player").DecodePayload(&originalWelcome)
	identity := accountCommand(t, first, protocol.AccountCommand{Operation: "create", Name: "Alice", DeviceName: "First"})
	_, id := first.createRoom("Account table", protocol.FormatModern, 2, true, "")
	first.recvType(protocol.TypeRoomSnapshot)
	handler.sessionsMu.RLock()
	old := handler.sessions[originalWelcome.ConnectionID]
	handler.sessionsMu.RUnlock()

	second := dial(t, srv)
	defer second.close()
	var secondWelcome protocol.SessionWelcome
	second.hello("Unrelated name").DecodePayload(&secondWelcome)
	logged := accountCommand(t, second, protocol.AccountCommand{Operation: "login", LoginCode: identity.LoginCode, DeviceName: "Replacement"})
	if logged.AccountID != identity.AccountID || logged.DisplayName != "Alice" || len(logged.Resources) != 1 || logged.Resources[0].ID != id {
		t.Fatal("login code did not recover original identity and room")
	}
	stranger := dial(t, srv)
	defer stranger.close()
	if stranger.resume("Alice", originalWelcome.ResumeToken, 0).Resumed {
		t.Fatal("old local bearer token bypassed account ownership")
	}
	accountCommand(t, second, protocol.AccountCommand{Operation: "resume", ResourceID: id})
	entry := handler.hub.roomEntryFor(id)
	entry.mu.Lock()
	if entry.room.Seats[0].ConnectionID != secondWelcome.ConnectionID || entry.room.Seats[0].AccountID != identity.AccountID || !entry.room.Seats[0].Host {
		t.Fatal("seat/host ownership lost on takeover")
	}
	entry.mu.Unlock()
	// A buffered old command cannot mutate the seat after account handover.
	leave, _ := protocol.NewEnvelope(protocol.TypeRoomLeave, struct{}{})
	if err := handler.dispatch(context.Background(), nil, old, leave); err != nil {
		t.Fatal(err)
	}
	entry.mu.Lock()
	if !entry.room.Seats[0].Occupied || entry.room.Seats[0].ConnectionID != secondWelcome.ConnectionID {
		t.Fatal("stale account connection changed the new seat")
	}
	entry.mu.Unlock()

	// A cached device session also resumes across launches without a room token.
	third := dial(t, srv)
	defer third.close()
	hello, _ := protocol.NewEnvelope(protocol.TypeSessionHello, protocol.SessionHello{
		DisplayName: "Untrusted name", ClientVersion: buildinfo.Version, AccountSession: logged.SessionToken})
	hello.ID = "account-hello"
	third.send(hello)
	var restored protocol.SessionWelcome
	third.recvType(protocol.TypeSessionWelcome).DecodePayload(&restored)
	if !restored.Resumed || restored.RoomID != id || restored.AccountID != identity.AccountID {
		t.Fatal("account hello failed to restore seat")
	}
}

func TestOfficialHubsShareAccountsAndDeviceRevocation(t *testing.T) {
	store, err := accounts.Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	key := strings.Repeat("k", 48)
	api, err := accounts.HTTPHandler(store, key, "official-test")
	if err != nil {
		t.Fatal(err)
	}
	authority := httptest.NewServer(api)
	defer authority.Close()
	cfg := DefaultConfig()
	cfg.AccountAuthority, cfg.AccountServiceKey, cfg.AccountRealm = authority.URL, key, "official-test"
	one, _ := newConfiguredTestServer(t, cfg)
	two, _ := newConfiguredTestServer(t, cfg)
	a := dial(t, one)
	defer a.close()
	a.hello("Alice")
	created := accountCommand(t, a, protocol.AccountCommand{Operation: "create", Name: "Alice", DeviceName: "Node one"})
	b := dial(t, two)
	defer b.close()
	b.hello("Bob")
	logged := accountCommand(t, b, protocol.AccountCommand{Operation: "login", LoginCode: created.LoginCode, DeviceName: "Node two"})
	if logged.AccountID != created.AccountID || len(logged.Devices) != 2 {
		t.Fatal("official nodes did not share identity/devices")
	}
	accountCommand(t, a, protocol.AccountCommand{Operation: "revoke", SessionID: logged.SessionID})
	request, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{Name: "Forbidden", Format: protocol.FormatModern, MatchMode: protocol.MatchBO1})
	request.ID = "revoked-create"
	b.send(request)
	errEnv := b.recvType(protocol.TypeError)
	var payload protocol.ErrorPayload
	errEnv.DecodePayload(&payload)
	if payload.Code != protocol.ErrAccountInvalid {
		t.Fatalf("revoked device mutation: %s", payload.Code)
	}
}

func TestAccountRecoveryConflictDoesNotConsumeBackup(t *testing.T) {
	for _, resource := range []string{"room", "event"} {
		t.Run(resource, func(t *testing.T) {
			cfg := DefaultConfig()
			cfg.AccountDir, cfg.AccountRealm = t.TempDir(), "official-test"
			srv, h := newConfiguredTestServer(t, cfg)
			created, err := h.accountRequest(context.Background(), accounts.Request{Operation: "create", Name: "Owner", DeviceName: "Original"})
			if err != nil {
				t.Fatal(err)
			}
			guest := dial(t, srv)
			defer guest.close()
			guest.hello("Guest")
			if resource == "room" {
				guest.createRoom("Guest table", protocol.FormatModern, 2, true, "")
			} else {
				guest.send(cubeCommandEnvelope(t, protocol.TypeTournamentCreate, cubeRoomRequest(2)))
				guest.recvType(protocol.TypeTournamentCreated)
			}
			request, _ := protocol.NewEnvelope(protocol.TypeAccountCommand, protocol.AccountCommand{
				Operation: "recover", RecoveryCode: created.RecoveryCode, DeviceName: "New"})
			request.ID = "conflicting-recovery"
			guest.send(request)
			var failure protocol.ErrorPayload
			guest.recvType(protocol.TypeError).DecodePayload(&failure)
			if failure.Code != protocol.ErrAccountConflict {
				t.Fatalf("unexpected recovery failure: %s", failure.Code)
			}
			if _, err := h.accountRequest(context.Background(), accounts.Request{Operation: "check", SessionToken: created.SessionToken}); err != nil {
				t.Fatal("rejected recovery revoked the old device")
			}
			fresh := dial(t, srv)
			defer fresh.close()
			fresh.hello("New device")
			recovered := accountCommand(t, fresh, protocol.AccountCommand{
				Operation: "recover", RecoveryCode: created.RecoveryCode, DeviceName: "New"})
			if recovered.AccountID != created.Profile.ID || recovered.LoginCode == "" || recovered.RecoveryCode == "" {
				t.Fatal("rejected recovery consumed the backup")
			}
		})
	}
}

func TestAccountAttachConflictPreservesExistingDevice(t *testing.T) {
	cfg := DefaultConfig()
	cfg.AccountDir, cfg.AccountRealm = t.TempDir(), "official-test"
	srv, h := newConfiguredTestServer(t, cfg)
	owner := dial(t, srv)
	defer owner.close()
	owner.hello("Owner")
	created := accountCommand(t, owner, protocol.AccountCommand{Operation: "create", Name: "Owner", DeviceName: "Original"})
	owner.createRoom("Account table", protocol.FormatModern, 2, true, "")
	guest := dial(t, srv)
	defer guest.close()
	guest.hello("Guest")
	guest.createRoom("Guest table", protocol.FormatModern, 2, true, "")
	request, _ := protocol.NewEnvelope(protocol.TypeAccountCommand, protocol.AccountCommand{
		Operation: "attach", Credential: created.SessionToken})
	request.ID = "conflicting-attach"
	guest.send(request)
	var failure protocol.ErrorPayload
	guest.recvType(protocol.TypeError).DecodePayload(&failure)
	if failure.Code != protocol.ErrAccountConflict {
		t.Fatalf("unexpected attach failure: %s", failure.Code)
	}
	if _, err := h.accountRequest(context.Background(), accounts.Request{Operation: "check", SessionToken: created.SessionToken}); err != nil {
		t.Fatal("rejected attachment revoked a preexisting device")
	}
	accountCommand(t, owner, protocol.AccountCommand{Operation: "status"})
}

func TestAccountReplayOwnershipPersistsAndRequiresMatchingAccount(t *testing.T) {
	h, r, game, players := recordingFixture(t)
	h.collectForgeReplay(r, game)
	record := h.forgeReplays.active[r]
	accountID := strings.Repeat("a", 32)
	if h.claimAccountReplay(accountID, record.Grant.ReplayID, record.Tokens[0]) {
		t.Fatal("unfinished replay claimed")
	}
	r.Game = &room.GameState{Result: &protocol.GameResult{MatchFinished: true}}
	h.publishForgeReplay(r)
	for _, p := range players {
		drainProjection(t, p)
	}
	if !h.claimAccountReplay(accountID, record.Grant.ReplayID, record.Tokens[0]) {
		t.Fatal("valid replay capability not adopted")
	}
	if h.claimAccountReplay(strings.Repeat("b", 32), record.Grant.ReplayID, record.Tokens[0]) {
		t.Fatal("another account stole a claimed replay")
	}
	if recordingRead(t, h, players[0], record.Grant.ReplayID, record.Tokens[0]).Type != protocol.TypeError {
		t.Fatal("anonymous legacy capability bypassed ownership")
	}
	players[0].setAccount(accountBinding{ID: accountID})
	if recordingRead(t, h, players[0], record.Grant.ReplayID, record.Tokens[0]).Type != protocol.TypeForgeReplayPage {
		t.Fatal("matching account lost replay")
	}
	grants, more := h.accountReplays(accountID, 0)
	if len(grants) != 1 || more || grants[0].Token != record.Tokens[0] {
		t.Fatal("account replay index incomplete")
	}
	if grants, _ := h.accountReplays(strings.Repeat("b", 32), 0); len(grants) != 0 {
		t.Fatal("replay index exposed another player's archive")
	}
	reloaded := retentionHandler(t, h.config)
	if grants, _ := reloaded.accountReplays(accountID, 0); len(grants) != 1 {
		t.Fatal("replay account association lost on restart")
	}
	if recordingRead(t, reloaded, players[2], record.Grant.ReplayID, record.Tokens[0]).Type != protocol.TypeError {
		t.Fatal("restart reverted archive to bearer-only access")
	}
	if recordingRead(t, reloaded, players[0], record.Grant.ReplayID, record.Tokens[0]).Type != protocol.TypeForgeReplayPage {
		t.Fatal("restart lost owner access")
	}
}

func TestAccountCubeDraftRecoveryPreservesPrivateSeat(t *testing.T) {
	cfg := DefaultConfig()
	cfg.AccountDir, cfg.AccountRealm = t.TempDir(), "official-test"
	srv, h := newConfiguredTestServer(t, cfg)
	host := dial(t, srv)
	defer host.close()
	host.hello("Host")
	identity := accountCommand(t, host, protocol.AccountCommand{Operation: "create", Name: "Host", DeviceName: "First"})
	host.send(cubeCommandEnvelope(t, protocol.TypeTournamentCreate, cubeRoomRequest(2)))
	var created protocol.TournamentCreated
	host.recvType(protocol.TypeTournamentCreated).DecodePayload(&created)
	host.recvType(protocol.TypeTournamentSnapshot)
	guest := dial(t, srv)
	defer guest.close()
	guest.hello("Guest")
	guest.send(cubeCommandEnvelope(t, protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: created.TournamentID}))
	guest.recvType(protocol.TypeTournamentRegistered)
	for _, client := range []*wsClient{host, guest} {
		client.send(cubeCommandEnvelope(t, protocol.TypeTournamentCheckIn, protocol.TournamentCheckIn{CheckedIn: true}))
		if reply := client.recvType(protocol.TypeTournamentCheckInSet, protocol.TypeError); reply.Type == protocol.TypeError {
			t.Fatal(string(reply.Payload))
		}
	}
	host.send(cubeCommandEnvelope(t, protocol.TypeTournamentStart, struct{}{}))
	if reply := host.recvType(protocol.TypeTournamentStarted, protocol.TypeError); reply.Type == protocol.TypeError {
		t.Fatal(string(reply.Payload))
	}
	var before protocol.LimitedSnapshot
	for before.Stage != protocol.LimitedStageDraft {
		host.recvType(protocol.TypeLimitedSnapshot).DecodePayload(&before)
	}
	entry := h.tournaments.entry(created.TournamentID)
	entry.mu.Lock()
	participantID := entry.event.OrganizerParticipantID
	entry.mu.Unlock()
	replacement := dial(t, srv)
	defer replacement.close()
	replacement.hello("Replacement")
	logged := accountCommand(t, replacement, protocol.AccountCommand{Operation: "login", LoginCode: identity.LoginCode, DeviceName: "Second"})
	if len(logged.Resources) != 1 || logged.Resources[0].Kind != "cube" {
		t.Fatal("Cube missing from account resources")
	}
	// Explicit spectator entry must not reveal even this account's own pack.
	replacement.send(cubeCommandEnvelope(t, protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: created.TournamentID, AsSpectator: true, UseAccount: true}))
	replacement.recvType(protocol.TypeTournamentEntered)
	var viewed protocol.LimitedSnapshot
	replacement.recvType(protocol.TypeLimitedSnapshot).DecodePayload(&viewed)
	if len(viewed.CurrentPack) != 0 || len(viewed.Pool) != 0 {
		t.Fatal("account login granted spectator private cards")
	}
	replacement.send(cubeCommandEnvelope(t, protocol.TypeTournamentEnter, protocol.TournamentEnter{TournamentID: created.TournamentID, UseAccount: true}))
	var entered protocol.TournamentEntered
	replacement.recvType(protocol.TypeTournamentEntered).DecodePayload(&entered)
	var restored protocol.LimitedSnapshot
	replacement.recvType(protocol.TypeLimitedSnapshot).DecodePayload(&restored)
	if entered.ParticipantID != participantID || entered.Role != "organizer" || !reflect.DeepEqual(before.CurrentPack, restored.CurrentPack) || !reflect.DeepEqual(before.Pool, restored.Pool) {
		t.Fatal("account recovery changed draft seat, pack, or picked pool")
	}
	// The legacy organizer token cannot bypass account ownership.
	intruder := dial(t, srv)
	defer intruder.close()
	intruder.hello("Host")
	intruder.send(cubeCommandEnvelope(t, protocol.TypeTournamentEnter, protocol.TournamentEnter{TournamentID: created.TournamentID, Credential: created.OrganizerToken}))
	if intruder.recvType(protocol.TypeTournamentEntered, protocol.TypeError).Type != protocol.TypeError {
		t.Fatal("legacy credential bypassed account")
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()
	if len(entry.event.Participants) != 2 {
		t.Fatal("recovery allocated a new participant")
	}
}

func TestAccountClaimRevokesExistingGuestEventAuthority(t *testing.T) {
	h, entry, sessions, hostToken := createCubeRoomHarness(t, 2)
	defer h.Close()
	host := sessions[0]
	entry.mu.Lock()
	if !entry.event.ClaimCredentialAccount(tournament.CredentialHash(hostToken), "new-owner") {
		t.Fatal("claim failed")
	}
	actor := tournamentActor(host)
	if entry.event.SetCheckedIn(actor, true) == nil {
		t.Fatal("claimed guest retained mutation authority")
	}
	host.tournamentMu.RLock()
	_, allowed := tournamentProjectionIdentity(entry.event, host, host.tournament)
	host.tournamentMu.RUnlock()
	entry.mu.Unlock()
	if allowed {
		t.Fatal("claimed guest retained private projection authority")
	}
}

func TestAccountTableRecoveryRestoresSubmittedCubeDeck(t *testing.T) {
	h, event, sessions, _ := submittedInitialCubeRoom(t, protocol.LimitedEventCubeDraft)
	defer h.Close()
	host := sessions[0]
	host.setAccount(accountBinding{ID: "table-owner"})
	host.ResumeToken = "old-local-token"
	h.bindAccountResources(host)
	participantID := host.Tournament().ParticipantID
	before := event.event.LimitedSnapshot(participantID)
	pairID := event.event.CasualPairings[0].ID
	_ = h.handleTournamentOpenMatch(host, cubeCommandEnvelope(t, protocol.TypeTournamentOpenMatch, protocol.TournamentPairingCommand{PairingID: pairID}))
	if reply := cubeReply(t, host); reply.Type != protocol.TypeTournamentMatchOpened {
		t.Fatal(string(reply.Payload))
	}
	h.bindAccountResources(host)
	r := host.Room()
	h.holdForReconnect(host, r)
	replacement := cubeTestSession(h, 8)
	replacement.setAccount(accountBinding{ID: "table-owner"})
	replacement.ResumeToken = "fresh-local-token"
	if !h.resumeAccountRoom(replacement, r.ID) {
		t.Fatal("account room resume failed")
	}
	if replacement.Tournament().ParticipantID != participantID {
		t.Fatal("new device lost linked event identity")
	}
	var snapshot protocol.LimitedSnapshot
	for _, env := range drainProjection(t, replacement) {
		if env.Type == protocol.TypeError {
			t.Fatal(string(env.Payload))
		}
		if env.Type == protocol.TypeLimitedSnapshot {
			env.DecodePayload(&snapshot)
		}
	}
	if !snapshot.DeckSubmitted || !reflect.DeepEqual(before.Pool, snapshot.Pool) || !reflect.DeepEqual(before.MainboardInstanceIDs, snapshot.MainboardInstanceIDs) {
		t.Fatal("submitted deck or original picked pool lost during table recovery")
	}
	// Explicit departure consumes the account room right, just like a guest seat.
	_ = h.handleRoomLeave(replacement, cubeCommandEnvelope(t, protocol.TypeRoomLeave, struct{}{}))
	if h.accountResumeToken("table-owner", r.ID) != "" || h.resumeAccountRoom(replacement, r.ID) {
		t.Fatal("explicit departure was resurrected")
	}
}

func TestAccountLegacyTableResumeCannotClaimSecondParticipant(t *testing.T) {
	h, event, sessions, _ := submittedInitialCubeRoom(t, protocol.LimitedEventCubeDraft)
	defer h.Close()
	host := sessions[0]
	host.ResumeToken = "legacy-host-room-token"
	participantID := host.Tournament().ParticipantID
	pairID := event.event.CasualPairings[0].ID
	_ = h.handleTournamentOpenMatch(host, cubeCommandEnvelope(t, protocol.TypeTournamentOpenMatch, protocol.TournamentPairingCommand{PairingID: pairID}))
	if reply := cubeReply(t, host); reply.Type != protocol.TypeTournamentMatchOpened {
		t.Fatal(string(reply.Payload))
	}
	r := host.Room()
	h.holdForReconnect(host, r)
	if !event.event.ClaimConnectionAccount(sessions[1].ConnectionID, "other-player") {
		t.Fatal("could not bind other participant")
	}
	if _, ok := h.takeAccountResumeHold(host.ResumeToken, "other-player", time.Now().UTC()); ok {
		t.Fatal("a legacy room token acquired a second participant")
	}
	if role, _ := event.event.AccountRole("new-owner"); role != "" {
		t.Fatal("rejected adoption mutated the event")
	}
	hold, ok := h.takeAccountResumeHold(host.ResumeToken, "new-owner", time.Now().UTC())
	if !ok || hold.accountID != "new-owner" {
		t.Fatal("valid original guest seat could not be adopted")
	}
	role, adoptedID := event.event.AccountRole("new-owner")
	if role != tournament.RoleOrganizer || adoptedID != participantID {
		t.Fatal("table adoption changed the original role")
	}
	h.restoreResumeHold(hold, time.Now().UTC())
	replacement := cubeTestSession(h, 9)
	replacement.setAccount(accountBinding{ID: "new-owner"})
	replacement.ResumeToken = "new-device-room-token"
	if !h.resumeAccountRoom(replacement, r.ID) || replacement.Tournament().ParticipantID != participantID {
		t.Fatal("adopted table could not restore its event")
	}
}
