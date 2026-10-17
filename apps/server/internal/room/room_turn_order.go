// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"fmt"
	"sort"
	"strings"
)

const (
	commanderOpeningRollSides    = 20
	commanderOpeningRollAttempts = 8
)

type commanderOpeningRollRound struct {
	Seats    []int
	Values   []int
	TieBreak bool
}

// rollCommanderTurnOrder rolls a public d20 for every occupied Commander seat.
// Tied groups reroll independently, so the resulting lexicographic roll vectors
// define the order without changing immutable seat identities.
func (r *Room) rollCommanderTurnOrder(activeSeats []int) (
	[]int, []commanderOpeningRollRound, error,
) {
	order := append([]int{}, activeSeats...)
	scores := make(map[int][]int, len(activeSeats))
	pendingGroups := [][]int{append([]int{}, activeSeats...)}
	rounds := make([]commanderOpeningRollRound, 0, 2)

	for attempt := 0; attempt < commanderOpeningRollAttempts &&
		len(pendingGroups) > 0; attempt++ {
		nextGroups := make([][]int, 0)
		for _, group := range pendingGroups {
			values := make([]int, len(group))
			byValue := make(map[int][]int, len(group))
			for index, seat := range group {
				value, err := r.randomIndex(commanderOpeningRollSides)
				if err != nil {
					return nil, nil, err
				}
				value++
				values[index] = value
				scores[seat] = append(scores[seat], value)
				byValue[value] = append(byValue[value], seat)
			}
			rounds = append(rounds, commanderOpeningRollRound{
				Seats:    append([]int{}, group...),
				Values:   values,
				TieBreak: attempt > 0,
			})
			rollValues := make([]int, 0, len(byValue))
			for value := range byValue {
				rollValues = append(rollValues, value)
			}
			sort.Sort(sort.Reverse(sort.IntSlice(rollValues)))
			for _, value := range rollValues {
				tiedSeats := byValue[value]
				if len(tiedSeats) > 1 {
					nextGroups = append(nextGroups, tiedSeats)
				}
			}
		}
		pendingGroups = nextGroups
	}

	sort.SliceStable(order, func(left, right int) bool {
		leftSeat := order[left]
		rightSeat := order[right]
		leftScores := scores[leftSeat]
		rightScores := scores[rightSeat]
		limit := len(leftScores)
		if len(rightScores) < limit {
			limit = len(rightScores)
		}
		for index := 0; index < limit; index++ {
			if leftScores[index] != rightScores[index] {
				return leftScores[index] > rightScores[index]
			}
		}
		return leftSeat < rightSeat
	})
	return order, rounds, nil
}

func turnOrderStartingAt(activeSeats []int, startingSeat int) ([]int, error) {
	startingIndex := -1
	for index, seat := range activeSeats {
		if seat == startingSeat {
			startingIndex = index
			break
		}
	}
	if startingIndex < 0 {
		return nil, fmt.Errorf("starting seat %d is not active", startingSeat)
	}
	order := make([]int, 0, len(activeSeats))
	order = append(order, activeSeats[startingIndex:]...)
	order = append(order, activeSeats[:startingIndex]...)
	return order, nil
}

func validateFixedTurnOrder(order, activeSeats []int, startingSeat int) error {
	if len(order) != len(activeSeats) || len(order) == 0 || order[0] != startingSeat {
		return fmt.Errorf("turn order does not match active seats")
	}
	active := make(map[int]bool, len(activeSeats))
	for _, seat := range activeSeats {
		active[seat] = true
	}
	seen := make(map[int]bool, len(order))
	for _, seat := range order {
		if !active[seat] || seen[seat] {
			return fmt.Errorf("turn order contains invalid seat %d", seat)
		}
		seen[seat] = true
	}
	return nil
}

func commanderOpeningRollText(game *GameState, round commanderOpeningRollRound) string {
	parts := make([]string, 0, len(round.Seats))
	for index, seat := range round.Seats {
		parts = append(parts, fmt.Sprintf("%s %d",
			game.Seats[seat].DisplayName, round.Values[index]))
	}
	label := "Commander opening roll"
	if round.TieBreak {
		label = "Commander tie-break roll"
	}
	return fmt.Sprintf("%s: %s.", label, strings.Join(parts, ", "))
}

func commanderTurnOrderText(game *GameState) string {
	names := make([]string, 0, len(game.TurnOrder))
	for _, seat := range game.TurnOrder {
		names = append(names, game.Seats[seat].DisplayName)
	}
	return fmt.Sprintf("Commander turn order: %s.", strings.Join(names, " -> "))
}
