// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package tournament

import (
	"math"
	"sort"
)

type playerPair [2]*Participant

func (t *Tournament) pairPlayers(players []*Participant, roundNumber int) []playerPair {
	if roundNumber == 1 {
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

func (t *Tournament) pairCost(left, right *Participant, ranks,
	points map[string]int) int {
	cost := abs(points[left.ID]-points[right.ID])*1000 +
		abs(ranks[left.ID]-ranks[right.ID])*10
	if t.havePlayed(left.ID, right.ID) {
		cost += 1_000_000
	}
	// Stable initial order is only a deterministic final preference.
	cost += abs(left.InitialOrder-right.InitialOrder) % 10
	return cost
}

func (t *Tournament) pairingInputs(players []*Participant) (map[string]int, map[string]int) {
	ranks := make(map[string]int, len(players))
	for index, participant := range players {
		ranks[participant.ID] = index
	}
	return ranks, t.matchPointsByParticipant()
}

func (t *Tournament) minimumCostPairs(players []*Participant) []playerPair {
	ranks, points := t.pairingInputs(players)
	type solution struct {
		cost  int
		pairs []playerPair
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
			cost := t.pairCost(players[first], players[second], ranks, points) + remainder.cost
			if cost < best.cost {
				pairs := make([]playerPair, 1, len(remainder.pairs)+1)
				pairs[0] = playerPair{players[first], players[second]}
				pairs = append(pairs, remainder.pairs...)
				best = solution{cost: cost, pairs: pairs}
			}
		}
		memo[mask] = best
		return best
	}
	return solve((uint64(1) << len(players)) - 1).pairs
}

func (t *Tournament) greedyPairs(players []*Participant) []playerPair {
	ranks, points := t.pairingInputs(players)
	remaining := append([]*Participant(nil), players...)
	pairs := make([]playerPair, 0, len(players)/2)
	for len(remaining) > 0 {
		left := remaining[0]
		remaining = remaining[1:]
		sort.SliceStable(remaining, func(first, second int) bool {
			return t.pairCost(left, remaining[first], ranks, points) <
				t.pairCost(left, remaining[second], ranks, points)
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
				current := t.pairCost(pairs[left][0], pairs[left][1], ranks, points) +
					t.pairCost(pairs[right][0], pairs[right][1], ranks, points)
				swapped := t.pairCost(pairs[left][0], pairs[right][1], ranks, points) +
					t.pairCost(pairs[right][0], pairs[left][1], ranks, points)
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
