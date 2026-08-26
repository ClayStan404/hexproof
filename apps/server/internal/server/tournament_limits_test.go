// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/tournament"
)

func tournamentCreateEnvelope(t *testing.T, id, name string) protocol.Envelope {
	t.Helper()
	envelope, err := protocol.NewEnvelope(protocol.TypeTournamentCreate,
		protocol.TournamentCreate{
			Name: name, Format: protocol.FormatModern,
			MatchMode: protocol.MatchBO3, RoundMinutes: 50, MaxPlayers: 16,
		})
	if err != nil {
		t.Fatalf("new tournament.create: %v", err)
	}
	envelope.ID = id
	return envelope
}

func tournamentEnterEnvelope(t *testing.T, id, tournamentID, credential string) protocol.Envelope {
	t.Helper()
	envelope, err := protocol.NewEnvelope(protocol.TypeTournamentEnter,
		protocol.TournamentEnter{TournamentID: tournamentID, Credential: credential})
	if err != nil {
		t.Fatalf("new tournament.enter: %v", err)
	}
	envelope.ID = id
	return envelope
}

func testTournamentSession(connectionID, remoteIP string) *Session {
	return &Session{
		ConnectionID: connectionID,
		DisplayName:  connectionID,
		RemoteIP:     remoteIP,
		Send:         make(chan []byte, 8),
	}
}

func TestTournamentCreateHonorsRegistryLimit(t *testing.T) {
	config := DefaultConfig()
	config.MaxTournaments = 1
	config.TournamentCreatesPerMinute = 10
	handler, err := NewHandlerWithConfig(config)
	if err != nil {
		t.Fatalf("new handler: %v", err)
	}

	first := testTournamentSession("first", "192.0.2.1")
	if err := handler.handleTournamentCreate(
		first, tournamentCreateEnvelope(t, "first-create", "First")); err != nil {
		t.Fatalf("first create: %v", err)
	}
	select {
	case <-first.Send:
	default:
		t.Fatal("first tournament did not return tournament.created")
	}

	second := testTournamentSession("second", "192.0.2.2")
	if err := handler.handleTournamentCreate(
		second, tournamentCreateEnvelope(t, "second-create", "Second")); err != nil {
		t.Fatalf("second create: %v", err)
	}
	payload := readWireError(t, second)
	if payload.Code != protocol.ErrServerLimit {
		t.Fatalf("tournament limit code = %q", payload.Code)
	}
}

func TestTournamentCreateHasIndependentIPRateLimit(t *testing.T) {
	config := DefaultConfig()
	config.MaxTournaments = 10
	config.TournamentCreatesPerMinute = 1
	handler, err := NewHandlerWithConfig(config)
	if err != nil {
		t.Fatalf("new handler: %v", err)
	}

	first := testTournamentSession("first", "192.0.2.10")
	if err := handler.handleTournamentCreate(
		first, tournamentCreateEnvelope(t, "first-create", "First")); err != nil {
		t.Fatalf("first create: %v", err)
	}
	<-first.Send

	second := testTournamentSession("second", "192.0.2.10")
	if err := handler.handleTournamentCreate(
		second, tournamentCreateEnvelope(t, "second-create", "Second")); err != nil {
		t.Fatalf("second create: %v", err)
	}
	payload := readWireError(t, second)
	if payload.Code != protocol.ErrRateLimited {
		t.Fatalf("tournament rate code = %q", payload.Code)
	}

	otherIP := testTournamentSession("other", "192.0.2.11")
	if err := handler.handleTournamentCreate(
		otherIP, tournamentCreateEnvelope(t, "other-create", "Other")); err != nil {
		t.Fatalf("other IP create: %v", err)
	}
	select {
	case <-otherIP.Send:
	default:
		t.Fatal("one IP exhausted another IP's tournament allowance")
	}
}

func addClosedTournament(t *testing.T, handler *Handler, id string,
	closedAt time.Time) *tournament.Tournament {
	t.Helper()
	event, err := tournament.New(id, tournament.Config{
		Name: "Closed event", Format: protocol.FormatModern,
		MatchMode: protocol.MatchBO3, MaxPlayers: 16,
	}, "Judge", "organizer", tournament.CredentialHash("credential"), closedAt.Add(-time.Hour))
	if err != nil {
		t.Fatalf("new tournament: %v", err)
	}
	event.Status = tournament.StatusCancelled
	event.ClosedAt = closedAt
	if _, err := handler.tournaments.create(event); err != nil {
		t.Fatalf("register tournament: %v", err)
	}
	return event
}

func TestExpiredClosedTournamentEvictionWaitsForBoundSessions(t *testing.T) {
	config := DefaultConfig()
	config.MaxTournaments = 4
	config.TournamentClosedTTL = time.Hour
	handler, err := NewHandlerWithConfig(config)
	if err != nil {
		t.Fatalf("new handler: %v", err)
	}
	now := time.Now().UTC()
	event := addClosedTournament(t, handler, "CLOSED", now.Add(-2*time.Hour))

	viewer := testTournamentSession("viewer", "192.0.2.20")
	viewer.setTournament(tournamentBinding{
		TournamentID: event.ID, Role: tournament.RoleViewer,
	})
	handler.registerSession(viewer)
	handler.evictExpiredTournaments(now)
	if handler.tournaments.entry(event.ID) == nil {
		t.Fatal("closed tournament was evicted while a viewer remained bound")
	}

	handler.unregisterSession(viewer)
	if handler.tournaments.entry(event.ID) != nil {
		t.Fatal("expired closed tournament remained after its last viewer disconnected")
	}
}

func addLiveTournament(t *testing.T, handler *Handler, id, status string,
	createdAt time.Time) *tournament.Tournament {
	t.Helper()
	event, err := tournament.New(id, tournament.Config{
		Name: "Live event", Format: protocol.FormatModern,
		MatchMode: protocol.MatchBO3, MaxPlayers: 16,
	}, "Judge", "organizer", tournament.CredentialHash("credential"), createdAt)
	if err != nil {
		t.Fatalf("new tournament: %v", err)
	}
	event.OrganizerConnectionID = ""
	event.Status = status
	if _, err := handler.tournaments.create(event); err != nil {
		t.Fatalf("register tournament: %v", err)
	}
	return event
}

func TestOccupiedRunningTournamentIsNeverEvicted(t *testing.T) {
	config := DefaultConfig()
	config.MaxTournaments = 4
	config.TournamentClosedTTL = time.Hour
	config.TournamentInactiveTTL = time.Hour
	config.TournamentAbandonedTTL = time.Hour
	handler, err := NewHandlerWithConfig(config)
	if err != nil {
		t.Fatalf("new handler: %v", err)
	}
	now := time.Now().UTC()
	event := addLiveTournament(t, handler, "ACTIVE", tournament.StatusRunning, now.Add(-48*time.Hour))

	viewer := testTournamentSession("viewer", "192.0.2.21")
	viewer.setTournament(tournamentBinding{
		TournamentID: event.ID, Role: tournament.RoleViewer,
	})
	handler.registerSession(viewer)
	handler.evictExpiredTournaments(now)
	if handler.tournaments.entry(event.ID) == nil {
		t.Fatal("running tournament with a bound session was evicted")
	}
}

func TestAbandonedRegistrationTournamentIsEvicted(t *testing.T) {
	config := DefaultConfig()
	config.MaxTournaments = 4
	config.TournamentInactiveTTL = time.Hour
	config.TournamentAbandonedTTL = 48 * time.Hour
	handler, err := NewHandlerWithConfig(config)
	if err != nil {
		t.Fatalf("new handler: %v", err)
	}
	now := time.Now().UTC()
	event := addLiveTournament(t, handler, "STALE-REG", tournament.StatusRegistration,
		now.Add(-3*time.Hour))
	event.OrganizerConnectionID = "ghost-organizer"

	handler.evictExpiredTournaments(now)
	if handler.tournaments.entry(event.ID) != nil {
		t.Fatal("abandoned registration tournament remained in the registry")
	}
}

func TestRecentRegistrationTournamentIsKept(t *testing.T) {
	config := DefaultConfig()
	config.MaxTournaments = 4
	config.TournamentInactiveTTL = 2 * time.Hour
	handler, err := NewHandlerWithConfig(config)
	if err != nil {
		t.Fatalf("new handler: %v", err)
	}
	now := time.Now().UTC()
	event := addLiveTournament(t, handler, "FRESH-REG", tournament.StatusRegistration,
		now.Add(-30*time.Minute))

	handler.evictExpiredTournaments(now)
	if handler.tournaments.entry(event.ID) == nil {
		t.Fatal("recent registration tournament was evicted")
	}
}

func TestAbandonedRegistrationWithViewerIsKept(t *testing.T) {
	config := DefaultConfig()
	config.MaxTournaments = 4
	config.TournamentInactiveTTL = time.Hour
	handler, err := NewHandlerWithConfig(config)
	if err != nil {
		t.Fatalf("new handler: %v", err)
	}
	now := time.Now().UTC()
	event := addLiveTournament(t, handler, "WATCHED-REG", tournament.StatusRegistration,
		now.Add(-3*time.Hour))

	viewer := testTournamentSession("viewer", "192.0.2.22")
	viewer.setTournament(tournamentBinding{
		TournamentID: event.ID, Role: tournament.RoleViewer,
	})
	handler.registerSession(viewer)
	handler.evictExpiredTournaments(now)
	if handler.tournaments.entry(event.ID) == nil {
		t.Fatal("registration tournament was evicted while a viewer remained bound")
	}
}

func TestAbandonedRunningTournamentIsEvicted(t *testing.T) {
	config := DefaultConfig()
	config.MaxTournaments = 4
	config.TournamentInactiveTTL = 48 * time.Hour
	config.TournamentAbandonedTTL = 24 * time.Hour
	handler, err := NewHandlerWithConfig(config)
	if err != nil {
		t.Fatalf("new handler: %v", err)
	}
	now := time.Now().UTC()
	event := addLiveTournament(t, handler, "STALE-RUN", tournament.StatusRunning,
		now.Add(-48*time.Hour))

	handler.evictExpiredTournaments(now)
	if handler.tournaments.entry(event.ID) != nil {
		t.Fatal("abandoned running tournament remained in the registry")
	}
}

func TestAbandonedRunningTournamentYoungerThanTTLIsKept(t *testing.T) {
	config := DefaultConfig()
	config.MaxTournaments = 4
	config.TournamentAbandonedTTL = 24 * time.Hour
	handler, err := NewHandlerWithConfig(config)
	if err != nil {
		t.Fatalf("new handler: %v", err)
	}
	now := time.Now().UTC()
	event := addLiveTournament(t, handler, "FRESH-RUN", tournament.StatusRunning,
		now.Add(-2*time.Hour))

	handler.evictExpiredTournaments(now)
	if handler.tournaments.entry(event.ID) == nil {
		t.Fatal("recent running tournament was evicted")
	}
}

func TestOccupiedPairingRoomKeepsAbandonedRunningTournament(t *testing.T) {
	config := DefaultConfig()
	config.MaxTournaments = 4
	config.TournamentAbandonedTTL = time.Hour
	handler, err := NewHandlerWithConfig(config)
	if err != nil {
		t.Fatalf("new handler: %v", err)
	}
	now := time.Now().UTC()
	event := addLiveTournament(t, handler, "PAIR-RUN", tournament.StatusRunning,
		now.Add(-48*time.Hour))

	host := testTournamentSession("host", "192.0.2.23")
	_, _, _, operation, createErr := handler.hub.createTournamentRoom(
		"Pairing", protocol.FormatModern, protocol.DeckFormatModern, protocol.MatchBO3,
		protocol.CardLoadBackground, 2, event.ID, "r1-m1", "p-host", host)
	if createErr != nil {
		t.Fatalf("create pairing room: %v", createErr)
	}
	operation.opMu.Unlock()

	handler.evictExpiredTournaments(now)
	if handler.tournaments.entry(event.ID) == nil {
		t.Fatal("running tournament was evicted while a pairing room was occupied")
	}
}

func TestAbandonedRegistrationFreesRegistrySlot(t *testing.T) {
	config := DefaultConfig()
	config.MaxTournaments = 1
	config.TournamentCreatesPerMinute = 10
	config.TournamentInactiveTTL = time.Hour
	handler, err := NewHandlerWithConfig(config)
	if err != nil {
		t.Fatalf("new handler: %v", err)
	}
	now := time.Now().UTC()
	addLiveTournament(t, handler, "FULL", tournament.StatusRegistration, now.Add(-3*time.Hour))
	handler.evictExpiredTournaments(now)

	creator := testTournamentSession("creator", "192.0.2.24")
	if err := handler.handleTournamentCreate(
		creator, tournamentCreateEnvelope(t, "replacement-create", "Replacement")); err != nil {
		t.Fatalf("replacement create: %v", err)
	}
	select {
	case <-creator.Send:
	default:
		t.Fatal("evicted registration did not free a tournament slot")
	}
}

func TestTournamentEnterEvictsAbandonedRegistration(t *testing.T) {
	config := DefaultConfig()
	config.MaxTournaments = 4
	config.TournamentInactiveTTL = time.Hour
	handler, err := NewHandlerWithConfig(config)
	if err != nil {
		t.Fatalf("new handler: %v", err)
	}
	now := time.Now().UTC()
	event := addLiveTournament(t, handler, "STALE-ENTER", tournament.StatusRegistration,
		now.Add(-3*time.Hour))

	viewer := testTournamentSession("stale-enter", "192.0.2.25")
	if err := handler.handleTournamentEnter(
		viewer, tournamentEnterEnvelope(t, "enter-stale", event.ID, "credential")); err != nil {
		t.Fatalf("enter abandoned registration: %v", err)
	}
	payload := readWireError(t, viewer)
	if payload.Code != protocol.ErrTournamentNotFound {
		t.Fatalf("abandoned enter code = %q", payload.Code)
	}
	if handler.tournaments.entry(event.ID) != nil {
		t.Fatal("tournament.enter resurrected an expired registration")
	}
}

func TestTournamentEnterKeepsRecentRegistration(t *testing.T) {
	config := DefaultConfig()
	config.MaxTournaments = 4
	config.TournamentInactiveTTL = 2 * time.Hour
	handler, err := NewHandlerWithConfig(config)
	if err != nil {
		t.Fatalf("new handler: %v", err)
	}
	now := time.Now().UTC()
	event := addLiveTournament(t, handler, "FRESH-ENTER", tournament.StatusRegistration,
		now.Add(-30*time.Minute))

	viewer := testTournamentSession("fresh-enter", "192.0.2.26")
	if err := handler.handleTournamentEnter(
		viewer, tournamentEnterEnvelope(t, "enter-fresh", event.ID, "")); err != nil {
		t.Fatalf("enter recent registration: %v", err)
	}
	select {
	case <-viewer.Send:
	default:
		t.Fatal("recent registration did not accept tournament.enter")
	}
	if handler.tournaments.entry(event.ID) == nil {
		t.Fatal("recent registration was evicted during enter")
	}
}
