// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package tournament

import (
	"fmt"
	"testing"

	"hexproof/server/internal/limited"
	"hexproof/server/internal/protocol"
)

func TestDraftOpeningRoundPairsOriginalOppositeSeats(t *testing.T) {
	for _, eventType := range []string{protocol.LimitedEventSetDraft, protocol.LimitedEventCubeDraft} {
		for _, count := range []int{2, 4, 6, 8} {
			t.Run(fmt.Sprintf("%s/%d", eventType, count), func(t *testing.T) {
				event := pairingWorkload(count)
				event.Rounds = nil
				event.EventType = eventType
				event.Limited = &limited.Event{Players: make([]*limited.PlayerState, count)}
				round := event.buildRound(event.activeParticipants(), testNow)
				seen := make(map[string]bool)
				for _, pairing := range round.Pairings {
					if pairing.Bye() || seen[pairing.PlayerAID] || seen[pairing.PlayerBID] {
						t.Fatalf("unexpected bye or duplicate: %+v", pairing)
					}
					seen[pairing.PlayerAID], seen[pairing.PlayerBID] = true, true
					var left, right int
					fmt.Sscan(pairing.PlayerAID, &left)
					fmt.Sscan(pairing.PlayerBID, &right)
					if abs(left-right) != count/2 {
						t.Fatalf("seats %d/%d are not opposite in a %d-player draft", left, right, count)
					}
				}
				if len(seen) != count {
					t.Fatalf("paired %d players, want %d", len(seen), count)
				}
			})
		}
	}
}

func TestDraftOpeningRoundOddPodsKeepByeAndDistantSeats(t *testing.T) {
	for _, count := range []int{3, 5, 7} {
		event := pairingWorkload(count + 1)
		event.Participants = event.Participants[:count]
		event.Rounds = nil
		event.EventType = protocol.LimitedEventSetDraft
		event.Limited = &limited.Event{Players: make([]*limited.PlayerState, count)}
		round := event.buildRound(event.activeParticipants(), testNow)
		for _, pairing := range round.Pairings {
			if pairing.Bye() {
				if pairing.PlayerAID != fmt.Sprint(count-1) {
					t.Fatalf("bye assignment changed: %+v", pairing)
				}
				continue
			}
			var left, right int
			fmt.Sscan(pairing.PlayerAID, &left)
			fmt.Sscan(pairing.PlayerBID, &right)
			distance := abs(left - right)
			if min(distance, count-distance) != count/2 {
				t.Fatalf("seats %d/%d are not farthest apart in a %d-player draft", left, right, count)
			}
		}
	}
}

func TestDraftOpeningRoundPreservesOppositeSeatsAfterDrops(t *testing.T) {
	event := pairingWorkload(8)
	event.Rounds = nil
	event.EventType = protocol.LimitedEventSetDraft
	event.Limited = &limited.Event{Players: make([]*limited.PlayerState, 8)}
	event.Participants[1].Dropped = true
	event.Participants[2].Dropped = true
	round := event.buildRound(event.activeParticipants(), testNow)
	want := map[string]string{"0": "4", "3": "7", "5": "6"}
	for _, pair := range round.Pairings {
		if want[pair.PlayerAID] != pair.PlayerBID {
			t.Fatalf("lost available opposite pair after withdrawals: %+v", round.Pairings)
		}
		delete(want, pair.PlayerAID)
	}
	if len(want) != 0 {
		t.Fatalf("missing pairings: %v", want)
	}
}

func TestCubeDraftOpeningRoundUsesPublishedDraftSeats(t *testing.T) {
	event, organizer := cubeDraftThroughDeckBuilding(t, protocol.LimitedCoordinatorSwiss)
	if err := event.Start(organizer, 987, testNow); err != nil {
		t.Fatal(err)
	}
	seats := make(map[string]int)
	for index, player := range event.Limited.Players {
		seats[player.ID] = index
	}
	for _, pair := range event.CurrentRound().Pairings {
		if abs(seats[pair.PlayerAID]-seats[pair.PlayerBID]) != 4 {
			t.Fatalf("round one ignores actual draft seats: %+v; seats %v", pair, seats)
		}
	}
}
