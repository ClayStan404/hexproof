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

func tournamentOperationReply(t *testing.T, sess *Session, id string) protocol.Envelope {
	t.Helper()
	for _, env := range drainProjection(t, sess) {
		if env.ID == id {
			return env
		}
	}
	t.Fatalf("missing operation reply %q", id)
	return protocol.Envelope{}
}

func tournamentOperationError(t *testing.T, reply protocol.Envelope, want string) protocol.ErrorPayload {
	t.Helper()
	var failure protocol.ErrorPayload
	if reply.Type != protocol.TypeError || reply.DecodePayload(&failure) != nil || failure.Code != want {
		t.Fatalf("got %s %s, want %s", reply.Type, reply.Payload, want)
	}
	return failure
}

func TestCreateOperationsRejectReplayAcrossSessionsAndDeletion(t *testing.T) {
	h := NewHandler()
	t.Cleanup(func() { _ = h.Close() })
	request := protocol.TournamentCreate{OperationID: "stable-create", Name: "One event", Format: protocol.FormatModern,
		MatchMode: protocol.MatchBO3, RoundMinutes: 50, MaxPlayers: 4}
	host := cubeTestSession(h, 0)
	env := cubeCommandEnvelope(t, protocol.TypeTournamentCreate, request)
	_ = h.handleTournamentCreate(host, env)
	reply := tournamentOperationReply(t, host, env.ID)
	var created protocol.TournamentCreated
	if reply.Type != protocol.TypeTournamentCreated || reply.DecodePayload(&created) != nil {
		t.Fatal(reply)
	}
	request.Name = "Changed request must not bypass operation identity"
	retry := cubeCommandEnvelope(t, protocol.TypeTournamentCreate, request)
	other := cubeTestSession(h, 1)
	_ = h.handleTournamentCreate(other, retry)
	tournamentOperationError(t, tournamentOperationReply(t, other, retry.ID), protocol.ErrInvalidMessage)
	if len(h.tournaments.snapshot()) != 1 || other.Tournament().TournamentID != "" {
		t.Fatal("replayed creation changed membership or event count")
	}
	entry := h.tournaments.entry(created.TournamentID)
	if !h.tournaments.deleteIfSame(created.TournamentID, entry) {
		t.Fatal("delete failed")
	}
	_ = h.handleTournamentCreate(other, retry)
	tournamentOperationError(t, tournamentOperationReply(t, other, retry.ID), protocol.ErrInvalidMessage)
	if len(h.tournaments.snapshot()) != 0 {
		t.Fatal("deletion evicted the replay tombstone")
	}
}

func TestLegacyCreationUsesStableEnvelopeIdentity(t *testing.T) {
	h := NewHandler()
	t.Cleanup(func() { _ = h.Close() })
	host := cubeTestSession(h, 0)
	request := protocol.TournamentCreate{Name: "Legacy shape", Format: protocol.FormatModern, MatchMode: protocol.MatchBO3, RoundMinutes: 50, MaxPlayers: 4}
	env, _ := protocol.NewEnvelope(protocol.TypeTournamentCreate, request)
	env.ID = "legacy-create"
	_ = h.handleTournamentCreate(host, env)
	if tournamentOperationReply(t, host, env.ID).Type != protocol.TypeTournamentCreated {
		t.Fatal("legacy shape rejected")
	}
	_ = h.handleTournamentCreate(host, env)
	tournamentOperationError(t, tournamentOperationReply(t, host, env.ID), protocol.ErrInvalidMessage)
	if len(h.tournaments.snapshot()) != 1 {
		t.Fatal("legacy request replay created another event")
	}
}

func TestCreateOperationHistoryIsBoundedAndConcurrent(t *testing.T) {
	r := newTournamentRegistry(1)
	var successes atomic.Int64
	var wg sync.WaitGroup
	for range 32 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if r.claimCreateOperation("one") == nil {
				successes.Add(1)
			}
		}()
	}
	wg.Wait()
	if successes.Load() != 1 || len(r.createOperations) != 1 {
		t.Fatal("concurrent operation was claimed twice")
	}
	for i := 1; i < maxTournamentCreateOperations; i++ {
		if err := r.claimCreateOperation(fmt.Sprint(i)); err != nil {
			t.Fatal(err)
		}
	}
	if err := r.claimCreateOperation("overflow"); err == nil {
		t.Fatal("unbounded create history")
	}
	if err := r.claimCreateOperation("one"); err == nil {
		t.Fatal("full history forgot the first operation")
	}
}

func startOperationHarness(t *testing.T, checkedIn bool) (*Handler, *tournamentEntry, *Session) {
	t.Helper()
	h := NewHandler()
	t.Cleanup(func() { _ = h.Close() })
	host := cubeTestSession(h, 0)
	product := protocol.LimitedProductDefinition{ID: "small-set", Name: "Small set", SetCode: "TST", ProductType: "approximate", CardsPerPack: 1,
		Sheets:   []protocol.LimitedSheetDefinition{{Name: "cards", WithReplacement: true, Cards: []protocol.LimitedCardDefinition{{Name: "Card", SetCode: "TST", CollectorNumber: "1", Weight: 1}}}},
		Variants: []protocol.LimitedPackVariantDefinition{{Weight: 1, Slots: []protocol.LimitedSlotDefinition{{Sheet: "cards", Count: 1}}}}}
	now := time.Now()
	event, err := tournament.New("OPR123", tournament.Config{Name: "Operation sealed", Format: "Limited", EventType: protocol.LimitedEventSetSealed,
		MatchMode: protocol.MatchBO3, RoundMinutes: 50, MaxPlayers: 2, Product: &product}, host.DisplayName, host.ConnectionID, tournament.CredentialHash("organizer"), now)
	if err != nil {
		t.Fatal(err)
	}
	for i := 1; i <= 2; i++ {
		participant, err := event.Register(fmt.Sprint("Player ", i), fmt.Sprint("participant-", i), tournament.CredentialHash(fmt.Sprint(i)), now)
		if err != nil {
			t.Fatal(err)
		}
		if checkedIn {
			if err := event.SetCheckedIn(tournament.Actor{Role: tournament.RoleParticipant, ParticipantID: participant.ID, ConnectionID: participant.ConnectionID}, true); err != nil {
				t.Fatal(err)
			}
		}
	}
	entry, err := h.tournaments.create(event)
	if err != nil {
		t.Fatal(err)
	}
	host.setTournament(tournamentBinding{TournamentID: event.ID, Role: tournament.RoleOrganizer})
	return h, entry, host
}

func TestStartReplayDoesNotAdvanceConstructionOrRedraw(t *testing.T) {
	h, entry, host := startOperationHarness(t, true)
	request := protocol.TournamentStart{OperationID: "start-registration", ExpectedStage: protocol.LimitedStageRegistration}
	env := cubeCommandEnvelope(t, protocol.TypeTournamentStart, request)
	_ = h.handleTournamentStart(host, env)
	if tournamentOperationReply(t, host, env.ID).Type != protocol.TypeTournamentStarted {
		t.Fatal("start failed")
	}
	limitedEvent := entry.event.Limited
	for _, player := range entry.event.Participants {
		if _, err := limitedEvent.SubmitDeck(player.ID, protocol.LimitedSubmitDeck{Name: "Forty basics", BasicLands: []protocol.LimitedBasicLand{{Name: "Plains", Count: 40}}}); err != nil {
			t.Fatal(err)
		}
	}
	// If replay called Start again, all submitted decks would advance competition.
	_ = h.handleTournamentStart(host, env)
	if tournamentOperationReply(t, host, env.ID).Type != protocol.TypeTournamentStarted || entry.event.Limited != limitedEvent || entry.event.Stage != protocol.LimitedStageDeckBuilding || len(entry.event.Rounds) != 0 {
		t.Fatal("registration replay changed the stage or physical pools")
	}
	conflict := cubeCommandEnvelope(t, protocol.TypeTournamentStart, protocol.TournamentStart{OperationID: request.OperationID, ExpectedStage: protocol.LimitedStageDeckBuilding})
	_ = h.handleTournamentStart(host, conflict)
	tournamentOperationError(t, tournamentOperationReply(t, host, conflict.ID), protocol.ErrInvalidMessage)
	competition := cubeCommandEnvelope(t, protocol.TypeTournamentStart, protocol.TournamentStart{OperationID: "start-competition", ExpectedStage: protocol.LimitedStageDeckBuilding})
	_ = h.handleTournamentStart(host, competition)
	if tournamentOperationReply(t, host, competition.ID).Type != protocol.TypeTournamentStarted || entry.event.Stage != protocol.LimitedStageCompetition || len(entry.event.Rounds) != 1 {
		t.Fatal("explicit construction transition failed")
	}
	_ = h.handleTournamentStart(host, env)
	if tournamentOperationReply(t, host, env.ID).Type != protocol.TypeTournamentStarted || len(entry.event.Rounds) != 1 {
		t.Fatal("old start replay advanced Swiss")
	}
	entry.event.OrganizerConnectionID = "replacement-organizer"
	_ = h.handleTournamentStart(host, env)
	tournamentOperationError(t, tournamentOperationReply(t, host, env.ID), protocol.ErrTournamentForbidden)
}

func TestStartFailuresAreStableAndHistoryIsBounded(t *testing.T) {
	h, entry, host := startOperationHarness(t, false)
	env := cubeCommandEnvelope(t, protocol.TypeTournamentStart, protocol.TournamentStart{OperationID: "not-ready", ExpectedStage: protocol.LimitedStageRegistration})
	_ = h.handleTournamentStart(host, env)
	first := tournamentOperationError(t, tournamentOperationReply(t, host, env.ID), protocol.ErrTournamentNotReady)
	for _, player := range entry.event.Participants {
		player.CheckedIn = true
	}
	_ = h.handleTournamentStart(host, env)
	second := tournamentOperationError(t, tournamentOperationReply(t, host, env.ID), protocol.ErrTournamentNotReady)
	if first != second || entry.event.Stage != protocol.LimitedStageRegistration || entry.event.Limited != nil {
		t.Fatal("failed retry did not reuse the failure")
	}
	for i := 1; i < maxTournamentStartOperations; i++ {
		entry.startOperations[fmt.Sprint(i)] = tournamentStartOperation{expectedStage: protocol.LimitedStageRegistration}
	}
	fresh := cubeCommandEnvelope(t, protocol.TypeTournamentStart, testTournamentStart(protocol.LimitedStageRegistration))
	_ = h.handleTournamentStart(host, fresh)
	tournamentOperationError(t, tournamentOperationReply(t, host, fresh.ID), protocol.ErrServerLimit)
	if entry.event.Limited != nil || entry.event.Stage != protocol.LimitedStageRegistration {
		t.Fatal("history overflow started the tournament")
	}
}
