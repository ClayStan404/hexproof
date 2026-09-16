// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package tournament

import (
	"fmt"
	"math"
	"math/rand"
	"testing"

	"hexproof/server/internal/protocol"
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
	for _, count := range []int{18, 20, 64, MaxParticipants} {
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

func TestMinimumCostPairingMatchesExhaustiveSearch(t *testing.T) {
	for _, count := range []int{2, 4, 6, 8, 10} {
		t.Run(fmt.Sprint(count), func(t *testing.T) {
			event := pairingWorkload(count)
			players := event.Participants
			costFor := event.pairingCosts(players)
			used := make([]bool, count)
			candidate := make([]playerPair, 0, count/2)
			var expected []playerPair
			bestCost := math.MaxInt
			// Enumerate complete matchings without sharing the production
			// memoization or reconstruction. Equal costs retain the first
			// stable participant ordering, including unavoidable rematches.
			var visit func(int)
			visit = func(cost int) {
				if len(candidate) == count/2 {
					if cost < bestCost {
						bestCost = cost
						expected = append([]playerPair(nil), candidate...)
					}
					return
				}
				first := 0
				for used[first] {
					first++
				}
				used[first] = true
				for second := first + 1; second < count; second++ {
					if used[second] {
						continue
					}
					used[second] = true
					candidate = append(candidate, playerPair{players[first], players[second]})
					visit(cost + costFor(players[first], players[second]))
					candidate = candidate[:len(candidate)-1]
					used[second] = false
				}
				used[first] = false
			}
			visit(0)
			actual := event.pairPlayers(players, 7)
			if len(actual) != len(expected) {
				t.Fatalf("pair count = %d, want %d", len(actual), len(expected))
			}
			for index, pair := range actual {
				if pair != expected[index] {
					t.Fatalf("pair %d = %s/%s, want %s/%s in stable minimum-cost matching",
						index, pair[0].ID, pair[1].ID, expected[index][0].ID, expected[index][1].ID)
				}
			}
		})
	}
}

func TestSwissPairingNineteenPlayersAssignsOneBye(t *testing.T) {
	event := pairingWorkload(20)
	event.Coordinator = protocol.LimitedCoordinatorSwiss
	event.Participants[19].Dropped = true
	round := event.buildRound(event.Participants[:19], testNow)
	seen := make(map[string]bool)
	byes := 0
	for _, pairing := range round.Pairings {
		ids := []string{pairing.PlayerAID}
		if pairing.Bye() {
			byes++
		} else {
			ids = append(ids, pairing.PlayerBID)
			if event.havePlayed(pairing.PlayerAID, pairing.PlayerBID) {
				t.Fatalf("avoidable rematch between %s and %s", pairing.PlayerAID, pairing.PlayerBID)
			}
		}
		for _, id := range ids {
			if id == event.Participants[19].ID || seen[id] {
				t.Fatalf("dropped or duplicate participant %s", id)
			}
			seen[id] = true
		}
	}
	if byes != 1 || len(seen) != 19 || len(round.Pairings) != 10 {
		t.Fatalf("19-player round has %d byes, %d players and %d pairings", byes, len(seen), len(round.Pairings))
	}
}

func BenchmarkSwissPairing(b *testing.B) {
	for _, count := range []int{18, 20, 64, MaxParticipants} {
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
