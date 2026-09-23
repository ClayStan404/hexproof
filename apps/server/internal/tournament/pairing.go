// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package tournament

import (
	"math"
	"sort"

	"hexproof/server/internal/protocol"
)

type playerPair [2]*Participant

func (t *Tournament) pairPlayers(players []*Participant, roundNumber int) []playerPair {
	if roundNumber == 1 {
		if t.Limited != nil && (t.EventType == protocol.LimitedEventSetDraft ||
			t.EventType == protocol.LimitedEventCubeDraft) {
			return t.draftOpeningPairs(players)
		}
		pairs := make([]playerPair, 0, len(players)/2)
		for index := 0; index < len(players); index += 2 {
			pairs = append(pairs, playerPair{players[index], players[index+1]})
		}
		return pairs
	}
	if len(players) <= 18 {
		return t.minimumCostPairs(players)
	}
	return t.greedyPairs(players)
}

// Draft seats have already been randomized at event start. Prefer the opposite
// original seat in an even pod, then the greatest circular distance when a bye
// or withdrawal leaves no exact opposite. Sealed and constructed remain random.
func (t *Tournament) draftOpeningPairs(players []*Participant) []playerPair {
	seatCount := len(t.Limited.Players)
	return minimumCostPairing(players, func(left, right *Participant) int {
		distance := abs(left.InitialOrder - right.InitialOrder)
		distance = min(distance, seatCount-distance)
		cost := seatCount - distance
		if seatCount%2 == 0 && distance == seatCount/2 {
			// Preserve every available opposite pair before optimizing the
			// remaining distances. Draft pods contain at most eight players.
			cost -= seatCount * seatCount
		}
		return cost
	})
}

func (t *Tournament) matchPointsByParticipant() map[string]int {
	points := make(map[string]int, len(t.Participants))
	for _, round := range t.Rounds {
		for _, pairing := range round.Pairings {
			if pairing.Result == nil {
				continue
			}
			score := pairing.Result.Score
			if pairing.Bye() || score.PlayerAWins > score.PlayerBWins {
				points[pairing.PlayerAID] += 3
			} else if score.PlayerBWins > score.PlayerAWins {
				points[pairing.PlayerBID] += 3
			} else {
				points[pairing.PlayerAID]++
				points[pairing.PlayerBID]++
			}
		}
	}
	return points
}

func (t *Tournament) havePlayed(left, right string) bool {
	for _, round := range t.Rounds {
		for _, pairing := range round.Pairings {
			if (pairing.PlayerAID == left && pairing.PlayerBID == right) ||
				(pairing.PlayerAID == right && pairing.PlayerBID == left) {
				return true
			}
		}
	}
	return false
}

func pairCost(left, right *Participant, ranks,
	points map[string]int, rematch bool) int {
	cost := abs(points[left.ID]-points[right.ID])*1000 +
		abs(ranks[left.ID]-ranks[right.ID])*10
	if rematch {
		cost += 1_000_000
	}
	// Stable initial order is only a deterministic final preference. The term
	// must stay monotonic and below the rank weight so it only breaks ties.
	cost += min(abs(left.InitialOrder-right.InitialOrder), 9)
	return cost
}

func (t *Tournament) pairingCosts(players []*Participant) func(*Participant, *Participant) int {
	count := len(players)
	ranks := make(map[string]int, len(players))
	for index, participant := range players {
		ranks[participant.ID] = index
	}
	// The search revisits the same opponents many times. Resolve history and
	// costs once; the matrix is bounded by MaxParticipants (512).
	costs := make([]int, count*count)
	for _, round := range t.Rounds {
		for _, pairing := range round.Pairings {
			left, leftPresent := ranks[pairing.PlayerAID]
			right, rightPresent := ranks[pairing.PlayerBID]
			if leftPresent && rightPresent {
				costs[left*count+right] = 1
				costs[right*count+left] = 1
			}
		}
	}
	points := t.matchPointsByParticipant()
	for left := 0; left < count; left++ {
		for right := left + 1; right < count; right++ {
			cost := pairCost(players[left], players[right], ranks, points,
				costs[left*count+right] != 0)
			costs[left*count+right], costs[right*count+left] = cost, cost
		}
	}
	return func(left, right *Participant) int {
		return costs[ranks[left.ID]*count+ranks[right.ID]]
	}
}

func (t *Tournament) minimumCostPairs(players []*Participant) []playerPair {
	return minimumCostPairing(players, t.pairingCosts(players))
}

func minimumCostPairing(players []*Participant, costFor func(*Participant, *Participant) int) []playerPair {
	type solution struct {
		cost   int
		second int
	}
	memo := make(map[uint64]solution)
	var solve func(uint64) solution
	solve = func(mask uint64) solution {
		if mask == 0 {
			return solution{}
		}
		if cached, ok := memo[mask]; ok {
			return cached
		}
		first := 0
		for mask&(uint64(1)<<first) == 0 {
			first++
		}
		best := solution{cost: math.MaxInt}
		withoutFirst := mask &^ (uint64(1) << first)
		for second := first + 1; second < len(players); second++ {
			if withoutFirst&(uint64(1)<<second) == 0 {
				continue
			}
			remainder := solve(withoutFirst &^ (uint64(1) << second))
			cost := costFor(players[first], players[second]) + remainder.cost
			if cost < best.cost {
				best = solution{cost: cost, second: second}
			}
		}
		memo[mask] = best
		return best
	}
	mask := (uint64(1) << len(players)) - 1
	solve(mask)
	// Keep only the winning choice per subproblem. Building complete pair
	// lists during the search repeatedly copies solutions that are discarded.
	pairs := make([]playerPair, 0, len(players)/2)
	for mask != 0 {
		first := 0
		for mask&(uint64(1)<<first) == 0 {
			first++
		}
		second := memo[mask].second
		pairs = append(pairs, playerPair{players[first], players[second]})
		mask &^= (uint64(1) << first) | (uint64(1) << second)
	}
	return pairs
}

func (t *Tournament) greedyPairs(players []*Participant) []playerPair {
	costFor := t.pairingCosts(players)
	remaining := append([]*Participant(nil), players...)
	pairs := make([]playerPair, 0, len(players)/2)
	for len(remaining) > 0 {
		left := remaining[0]
		remaining = remaining[1:]
		sort.SliceStable(remaining, func(first, second int) bool {
			return costFor(left, remaining[first]) < costFor(left, remaining[second])
		})
		pairs = append(pairs, playerPair{left, remaining[0]})
		remaining = remaining[1:]
	}

	// Two-opt removes avoidable repeats or large score floats introduced by a
	// local greedy choice without making large events exponentially expensive.
	for improved := true; improved; {
		improved = false
		for left := 0; left < len(pairs); left++ {
			for right := left + 1; right < len(pairs); right++ {
				current := costFor(pairs[left][0], pairs[left][1]) +
					costFor(pairs[right][0], pairs[right][1])
				swapped := costFor(pairs[left][0], pairs[right][1]) +
					costFor(pairs[right][0], pairs[left][1])
				if swapped < current {
					pairs[left][1], pairs[right][1] = pairs[right][1], pairs[left][1]
					improved = true
				}
			}
		}
	}
	return pairs
}

func abs(value int) int {
	if value < 0 {
		return -value
	}
	return value
}
