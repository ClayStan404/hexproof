// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package tournament

import (
	"fmt"
	"math/rand"
	"testing"
)

func TestPairCostInitialOrderTiebreakIsMonotonic(t *testing.T) {
	ranks := map[string]int{"a": 0, "b": 0}
	points := map[string]int{"a": 0, "b": 0}
	distanceOne := pairCost(
		&Participant{ID: "a", InitialOrder: 0}, &Participant{ID: "b", InitialOrder: 1},
		ranks, points, false)
	distanceTen := pairCost(
		&Participant{ID: "a", InitialOrder: 0}, &Participant{ID: "b", InitialOrder: 10},
		ranks, points, false)
	distanceTwenty := pairCost(
		&Participant{ID: "a", InitialOrder: 0}, &Participant{ID: "b", InitialOrder: 20},
		ranks, points, false)
	if distanceOne >= distanceTen || distanceTen > distanceTwenty {
		t.Fatalf("initial-order tiebreak not monotonic: d1=%d d10=%d d20=%d",
			distanceOne, distanceTen, distanceTwenty)
	}
}

func pairingWorkload(count int) *Tournament {
	event := &Tournament{}
	for index := 0; index < count; index++ {
		event.Participants = append(event.Participants, &Participant{
			ID: fmt.Sprint(index), InitialOrder: index, Competing: true,
		})
	}
	random := rand.New(rand.NewSource(51))
	for roundNumber := 0; roundNumber < 6; roundNumber++ {
		round := Round{}
		order := random.Perm(count)
		for index := 0; index < count; index += 2 {
			round.Pairings = append(round.Pairings, Pairing{
				PlayerAID: event.Participants[order[index]].ID,
				PlayerBID: event.Participants[order[index+1]].ID,
				Result:    &ConfirmedResult{Score: MatchScore{PlayerAWins: 2, PlayerBWins: index % 2}},
			})
		}
		event.Rounds = append(event.Rounds, round)
	}
	return event
}

func TestSwissPairingCoversFieldWithoutAvoidableRematches(t *testing.T) {
	for _, count := range []int{18, 64, MaxParticipants} {
		t.Run(fmt.Sprint(count), func(t *testing.T) {
			event := pairingWorkload(count)
			pairs := event.pairPlayers(event.Participants, 7)
			if len(pairs) != count/2 {
				t.Fatalf("pair count = %d", len(pairs))
			}
			seen := make(map[string]bool)
			for _, pair := range pairs {
				if pair[0] == pair[1] || seen[pair[0].ID] || seen[pair[1].ID] {
					t.Fatalf("duplicate player in pairing: %v", pair)
				}
				seen[pair[0].ID], seen[pair[1].ID] = true, true
				if event.havePlayed(pair[0].ID, pair[1].ID) {
					t.Fatalf("avoidable rematch between %s and %s", pair[0].ID, pair[1].ID)
				}
			}
		})
	}
}

func BenchmarkSwissPairing(b *testing.B) {
	for _, count := range []int{18, 64, MaxParticipants} {
		b.Run(fmt.Sprint(count), func(b *testing.B) {
			event := pairingWorkload(count)
			b.ReportAllocs()
			b.ResetTimer()
			for b.Loop() {
				event.pairPlayers(event.Participants, 7)
			}
		})
	}
}
