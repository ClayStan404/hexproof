// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"encoding/json"
	"sync"
	"testing"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/tournament"
)

func submittedInitialCubeRoom(t *testing.T, eventType string) (*Handler, *tournamentEntry, []*Session, []string) {
	t.Helper()
	h := NewHandler()
	host := cubeTestSession(h, 0)
	request := cubeRoomRequest(2)
	request.EventType = eventType
	if eventType == protocol.LimitedEventCommanderCube {
		request.Format = protocol.FormatEDH
		request.DraftSettings = &protocol.LimitedDraftSettings{PacksPerPlayer: 3, PacksPerBatch: 1}
		request.Product.Sheets[0].Cards[0].Weight = 120
	}
	_ = h.handleTournamentCreate(host, cubeCommandEnvelope(t, protocol.TypeTournamentCreate, request))
	created := cubeReply(t, host)
	var payload protocol.TournamentCreated
	if created.Type != protocol.TypeTournamentCreated || created.DecodePayload(&payload) != nil {
		t.Fatalf("could not create initial Cube pod: %s", created.Payload)
	}
	entry := h.tournaments.entry(payload.TournamentID)
	guest, guestToken := joinCubeRoomHarness(t, h, entry, 1)
	sessions, tokens := []*Session{host, guest}, []string{payload.OrganizerToken, guestToken}
	for _, sess := range sessions {
		_ = h.handleTournamentCheckIn(sess, cubeCommandEnvelope(t, protocol.TypeTournamentCheckIn,
			protocol.TournamentCheckIn{CheckedIn: true}))
		if reply := cubeReply(t, sess); reply.Type != protocol.TypeTournamentCheckInSet {
			t.Fatal("could not ready draft seat")
		}
	}
	_ = h.handleTournamentStart(host, cubeCommandEnvelope(t, protocol.TypeTournamentStart, protocol.EmptyPayload{}))
	if reply := cubeReply(t, host); reply.Type != protocol.TypeTournamentStarted {
		t.Fatal("could not start draft")
	}
	for _, sess := range sessions {
		_ = h.handleLimitedSetDraftControl(sess, cubeCommandEnvelope(t, protocol.TypeLimitedSetDraftControl,
			protocol.LimitedSetDraftControl{Automatic: true}))
		if reply := cubeReply(t, sess); reply.Type != protocol.TypeLimitedDraftControlSet {
			t.Fatal("could not complete draft")
		}
	}
	for _, sess := range sessions {
		deck := protocol.LimitedSubmitDeck{Name: "Initial deck", BasicLands: []protocol.LimitedBasicLand{{Name: "Forest", Count: 17}}}
		for _, card := range entry.event.LimitedSnapshot(sess.Tournament().ParticipantID).Pool[:23] {
			deck.MainboardInstanceIDs = append(deck.MainboardInstanceIDs, card.InstanceID)
		}
		if eventType == protocol.LimitedEventCommanderCube {
			deck.CommanderInstanceIDs = deck.MainboardInstanceIDs[:1]
			deck.BasicLands[0].Count = 37
		}
		_ = h.handleLimitedSubmitDeck(sess, cubeCommandEnvelope(t, protocol.TypeLimitedSubmitDeck, deck))
		if reply := cubeReply(t, sess); reply.Type != protocol.TypeLimitedDeckSubmitted {
			t.Fatal("could not submit initial deck")
		}
	}
	return h, entry, sessions, tokens
}

func TestCubeInitialEntryIsPrivateRetryableAndConcurrent(t *testing.T) {
	h, entry, sessions, tokens := submittedInitialCubeRoom(t, protocol.LimitedEventCubeDraft)
	if len(entry.event.CasualPairings) != 1 {
		t.Fatal("initial table missing")
	}
	pairID := entry.event.CasualPairings[0].ID
	for _, binding := range []tournamentBinding{
		{Role: tournament.RoleViewer},
		{Role: tournament.RoleViewer, ParticipantID: sessions[0].Tournament().ParticipantID},
		{Role: tournament.RoleParticipant, ParticipantID: "outside"},
		{Role: tournament.RoleOrganizer},
		{ParticipantID: sessions[0].Tournament().ParticipantID},
	} {
		view := tournamentSnapshot(entry.event, binding)
		data, _ := json.Marshal(view.Pairings[0])
		var fields map[string]any
		_ = json.Unmarshal(data, &fields)
		if _, present := fields["autoEnter"]; present {
			t.Fatal("automatic entry request appeared in a nonowner projection")
		}
	}
	for _, sess := range sessions {
		if !tournamentSnapshot(entry.event, sess.Tournament()).Pairings[0].AutoEnter {
			t.Fatal("owner missing automatic entry request")
		}
		drainProjection(t, sess)
	}

	// Capacity failures must not consume a successful deck submission or the
	// owner's one-shot entry request; an explicit retry can open the same table.
	h.hub.mu.Lock()
	h.hub.maxRooms = 1 // The Cube pod already reserves this one room slot.
	h.hub.mu.Unlock()
	open := cubeCommandEnvelope(t, protocol.TypeTournamentOpenMatch, protocol.TournamentPairingCommand{PairingID: pairID})
	_ = h.handleTournamentOpenMatch(sessions[0], open)
	if reply := cubeReply(t, sessions[0]); reply.Type != protocol.TypeError ||
		!entry.event.CasualPairings[0].AutoEntryPending(sessions[0].Tournament().ParticipantID) || sessions[0].Room() != nil {
		t.Fatal("failed room creation consumed the initial entry or retained a partial room")
	}
	h.hub.mu.Lock()
	h.hub.maxRooms = 0
	h.hub.mu.Unlock()

	// Recover before either player enters: the accepted initial assignment is
	// not an unanswered invitation and must survive a short transport drop.
	old := sessions[1]
	h.unregisterSession(old)
	if len(entry.event.CasualPairings) != 1 {
		t.Fatal("disconnect discarded the initial assignment")
	}
	replacement := cubeTestSession(h, 9)
	_ = h.handleCubeRoomJoin(replacement, cubeCommandEnvelope(t, protocol.TypeRoomJoin, protocol.RoomJoin{}),
		protocol.RoomJoin{RoomID: entry.event.ID, Credential: tokens[1]})
	if reply := cubeReply(t, replacement); reply.Type != protocol.TypeTournamentEntered {
		t.Fatal("participant could not recover before table entry")
	}
	sessions[1] = replacement
	_ = h.handleTournamentOpenMatch(old, open)
	if reply := cubeReply(t, old); reply.Type != protocol.TypeError {
		t.Fatal("superseded session entered the initial table")
	}

	var wg sync.WaitGroup
	for _, sess := range sessions {
		wg.Add(1)
		go func(sess *Session) {
			defer wg.Done()
			_ = h.dispatch(context.Background(), nil, sess, open)
		}(sess)
	}
	wg.Wait()
	for _, sess := range sessions {
		if reply := cubeReply(t, sess); reply.Type != protocol.TypeTournamentMatchOpened {
			t.Fatalf("simultaneous initial entry failed: %s", reply.Payload)
		}
		if tournamentSnapshot(entry.event, sess.Tournament()).Pairings[0].AutoEnter {
			t.Fatal("successful entry retained its one-shot flag")
		}
	}
	r := sessions[0].Room()
	if r == nil || sessions[1].Room() != r || r.PlayerCount() != 2 || !r.LimitedDeckLocked || r.Phase != protocol.RoomPhaseWaiting {
		t.Fatal("simultaneous entry did not produce one waiting locked-deck lobby")
	}
	for _, seat := range r.Seats {
		if seat.Ready {
			t.Fatal("automatic entry supplied readiness on a player's behalf")
		}
	}
	_ = h.handleTournamentOpenMatch(sessions[0], open)
	if reply := cubeReply(t, sessions[0]); reply.Type != protocol.TypeError || len(entry.event.CasualPairings) != 1 {
		t.Fatal("duplicate open duplicated or consumed a table")
	}
	expectedLeaveType := protocol.TypeRoomLeft
	if r.IsHost(sessions[0].ConnectionID) {
		// Either simultaneous entrant may win creation and become table host.
		expectedLeaveType = protocol.TypeRoomDisbanded
	}
	_ = h.handleRoomLeave(sessions[0], cubeCommandEnvelope(t, protocol.TypeRoomLeave, protocol.EmptyPayload{}))
	if reply := cubeReply(t, sessions[0]); reply.Type != expectedLeaveType {
		t.Fatalf("could not leave the initial table: got %s, want %s", reply.Type, expectedLeaveType)
	}
	if len(entry.event.CasualPairings) != 0 || sessions[1].Room() != nil {
		t.Fatal("table departure failed to release the pairing without automatic recreation")
	}
}

func TestExplicitCubePodDepartureCancelsUnopenedInitialTable(t *testing.T) {
	for _, eventType := range []string{protocol.LimitedEventCubeDraft, protocol.LimitedEventCommanderCube} {
		t.Run(eventType, func(t *testing.T) {
			h, entry, sessions, tokens := submittedInitialCubeRoom(t, eventType)
			guest := sessions[1]
			participantID := guest.Tournament().ParticipantID
			poolCount := len(entry.event.LimitedSnapshot(participantID).Pool)
			if len(entry.event.CasualPairings) != 1 || entry.event.CasualPairings[0].RoomID != "" {
				t.Fatal("fixture did not produce an unopened initial table")
			}
			_ = h.handleTournamentLeave(guest, cubeCommandEnvelope(t, protocol.TypeTournamentLeave, protocol.EmptyPayload{}))
			if reply := cubeReply(t, guest); reply.Type != protocol.TypeTournamentLeft {
				t.Fatal("explicit Cube departure failed")
			}
			if len(entry.event.CasualPairings) != 0 || guest.Tournament().TournamentID != "" ||
				len(entry.event.LimitedSnapshot(participantID).Pool) != poolCount || entry.event.Participant(participantID).Deck == nil {
				t.Fatal("departure retained an automatic table or discarded the private seat/deck")
			}
			_ = h.handleRoomJoin(guest, cubeCommandEnvelope(t, protocol.TypeRoomJoin,
				protocol.RoomJoin{RoomID: entry.event.ID, Credential: tokens[1]}))
			if reply := cubeReply(t, guest); reply.Type != protocol.TypeTournamentEntered {
				t.Fatal("departed participant could not reenter the pod")
			}
			if guest.Room() != nil || len(entry.event.CasualPairings) != 0 ||
				guest.Tournament().ParticipantID != participantID || !entry.event.LimitedSnapshot(participantID).DeckSubmitted {
				t.Fatal("explicit pod reentry auto-pulled the player or lost their submitted construction")
			}
		})
	}
}
