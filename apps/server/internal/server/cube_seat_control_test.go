// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"fmt"
	"sync"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
)

func startedSeatControlRoom(t *testing.T, seats int) (*Handler, *tournamentEntry, []*Session, []string) {
	t.Helper()
	h, entry, sessions, hostToken := createCubeRoomHarness(t, seats)
	tokens := []string{hostToken}
	for index := 1; index < seats; index++ {
		sess, token := joinCubeRoomHarness(t, h, entry, index)
		sessions, tokens = append(sessions, sess), append(tokens, token)
	}
	for _, sess := range sessions {
		_ = h.handleTournamentCheckIn(sess, cubeCommandEnvelope(t, protocol.TypeTournamentCheckIn, protocol.TournamentCheckIn{CheckedIn: true}))
		if reply := cubeReply(t, sess); reply.Type != protocol.TypeTournamentCheckInSet {
			t.Fatal("seat not ready")
		}
	}
	_ = h.handleTournamentStart(sessions[0], cubeCommandEnvelope(t, protocol.TypeTournamentStart, protocol.EmptyPayload{}))
	if reply := cubeReply(t, sessions[0]); reply.Type != protocol.TypeTournamentStarted {
		t.Fatal("draft did not start")
	}
	for _, sess := range sessions {
		drainProjection(t, sess)
	}
	return h, entry, sessions, tokens
}

func TestCubeOfflineTimestampProjectionAndTakeoverReconnectRace(t *testing.T) {
	for attempt := 0; attempt < 12; attempt++ {
		t.Run(fmt.Sprint(attempt), func(t *testing.T) {
			h, entry, sessions, tokens := startedSeatControlRoom(t, 2)
			host, old := sessions[0], sessions[1]
			guestID := old.Tournament().ParticipantID
			h.unregisterSession(old)
			sawOffline := false
			for _, env := range drainProjection(t, host) {
				if env.Type != protocol.TypeTournamentSnapshot {
					continue
				}
				var snapshot protocol.TournamentSnapshot
				_ = env.DecodePayload(&snapshot)
				for _, participant := range snapshot.Participants {
					if participant.ParticipantID == guestID && !participant.Online && participant.DisconnectedAt != "" {
						sawOffline = true
						if _, err := time.Parse(time.RFC3339Nano, participant.DisconnectedAt); err != nil {
							t.Fatal(err)
						}
					}
				}
			}
			if !sawOffline || entry.event.Limited.Player(guestID).AutoDraft {
				t.Fatal("disconnect did not publish the wait timestamp or silently started auto-drafting")
			}
			stamp := entry.event.Participant(guestID).DisconnectedAt
			clockProbe := time.Now()
			if clockProbe != clockProbe.Round(0) && stamp == stamp.Round(0) {
				t.Fatal("disconnect handler stripped the server clock's monotonic reading")
			}
			// Advance only the authoritative fixture clock, never sleep three minutes.
			entry.mu.Lock()
			entry.event.Participant(guestID).DisconnectedAt = time.Now().Add(-4 * time.Minute)
			entry.mu.Unlock()
			replacement := cubeTestSession(h, 9)
			auto := cubeCommandEnvelope(t, protocol.TypeLimitedSetDraftControl, protocol.LimitedSetDraftControl{ParticipantID: guestID, Automatic: true})
			join := cubeCommandEnvelope(t, protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: entry.event.ID, Credential: tokens[1]})
			var wg sync.WaitGroup
			wg.Add(2)
			go func() {
				defer wg.Done()
				_ = h.dispatch(context.Background(), nil, host, auto)
			}()
			go func() {
				defer wg.Done()
				_ = h.dispatch(context.Background(), nil, replacement, join)
			}()
			wg.Wait()
			autoReply := cubeReply(t, host)
			if autoReply.Type != protocol.TypeLimitedDraftControlSet && autoReply.Type != protocol.TypeError {
				t.Fatalf("unexpected automatic control reply: %s", autoReply.Type)
			}
			if reply := cubeReply(t, replacement); reply.Type != protocol.TypeTournamentEntered {
				t.Fatalf("concurrent recovery failed: %s", reply.Payload)
			}
			participant := entry.event.Participant(guestID)
			if participant.ConnectionID != replacement.ConnectionID || !participant.DisconnectedAt.IsZero() ||
				entry.event.Limited.Player(guestID).AutoDraft != (autoReply.Type == protocol.TypeLimitedDraftControlSet) {
				t.Fatal("recovery and explicit takeover were not atomic")
			}
			projected := tournamentSnapshot(entry.event, replacement.Tournament())
			for _, view := range projected.Participants {
				if view.ParticipantID == guestID && (!view.Online || view.DisconnectedAt != "") {
					t.Fatal("reconnected public projection retained the offline timer")
				}
			}
			_ = h.handleLimitedSetDraftControl(old, cubeCommandEnvelope(t, protocol.TypeLimitedSetDraftControl, protocol.LimitedSetDraftControl{Automatic: false}))
			if reply := cubeReply(t, old); reply.Type != protocol.TypeError {
				t.Fatal("stale transport reclaimed a rebound seat")
			}
			_ = h.handleLimitedSetDraftControl(replacement, cubeCommandEnvelope(t, protocol.TypeLimitedSetDraftControl, protocol.LimitedSetDraftControl{Automatic: false}))
			if reply := cubeReply(t, replacement); reply.Type != protocol.TypeLimitedDraftControlSet || entry.event.Limited.Player(guestID).AutoDraft {
				t.Fatal("returning player could not explicitly reclaim control")
			}
		})
	}
}

func TestCubeLastSubmissionAndWithdrawalSerializeWithoutRegressingStage(t *testing.T) {
	h, entry, sessions, _ := startedSeatControlRoom(t, 3)
	for _, sess := range sessions {
		_ = h.handleLimitedSetDraftControl(sess, cubeCommandEnvelope(t, protocol.TypeLimitedSetDraftControl, protocol.LimitedSetDraftControl{Automatic: true}))
		if reply := cubeReply(t, sess); reply.Type != protocol.TypeLimitedDraftControlSet {
			t.Fatal("could not enable automatic draft")
		}
	}
	deckFor := func(sess *Session) protocol.LimitedSubmitDeck {
		request := protocol.LimitedSubmitDeck{Name: "Ready", BasicLands: []protocol.LimitedBasicLand{{Name: "Forest", Count: 17}}}
		for _, card := range entry.event.LimitedSnapshot(sess.Tournament().ParticipantID).Pool[:23] {
			request.MainboardInstanceIDs = append(request.MainboardInstanceIDs, card.InstanceID)
		}
		return request
	}
	_ = h.handleLimitedSubmitDeck(sessions[0], cubeCommandEnvelope(t, protocol.TypeLimitedSubmitDeck, deckFor(sessions[0])))
	if reply := cubeReply(t, sessions[0]); reply.Type != protocol.TypeLimitedDeckSubmitted {
		t.Fatal("first submission failed")
	}
	submit := cubeCommandEnvelope(t, protocol.TypeLimitedSubmitDeck, deckFor(sessions[1]))
	withdraw := cubeCommandEnvelope(t, protocol.TypeLimitedSetParticipation, protocol.LimitedSetParticipation{Participating: false})
	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		_ = h.dispatch(context.Background(), nil, sessions[1], submit)
	}()
	go func() {
		defer wg.Done()
		_ = h.dispatch(context.Background(), nil, sessions[2], withdraw)
	}()
	wg.Wait()
	if reply := cubeReply(t, sessions[1]); reply.Type != protocol.TypeLimitedDeckSubmitted {
		t.Fatal("concurrent submission failed")
	}
	if reply := cubeReply(t, sessions[2]); reply.Type != protocol.TypeLimitedParticipationSet {
		t.Fatal("concurrent withdrawal failed")
	}
	if entry.event.Stage != protocol.LimitedStageCompetition || entry.event.Limited.Stage != protocol.LimitedStageCompetition ||
		!entry.event.Limited.AllDecksSubmitted() || !entry.event.Participant(sessions[2].Tournament().ParticipantID).Dropped {
		t.Fatal("last active deck and withdrawal did not open free play consistently")
	}
	if len(entry.event.CasualPairings) != 1 || entry.event.CasualPairings[0].Invited ||
		!entry.event.CasualPairings[0].AutoEntryPending(sessions[0].Tournament().ParticipantID) ||
		!entry.event.CasualPairings[0].AutoEntryPending(sessions[1].Tournament().ParticipantID) ||
		entry.event.CasualPairings[0].HasParticipant(sessions[2].Tournament().ParticipantID) {
		t.Fatal("concurrent final submission and withdrawal did not create exactly one active-player table")
	}
}
