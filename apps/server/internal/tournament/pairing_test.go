// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package tournament

import (
	"testing"
)

func TestPairCostInitialOrderTiebreakIsMonotonic(t *testing.T) {
	event := &Tournament{}
	ranks := map[string]int{"a": 0, "b": 0}
	points := map[string]int{"a": 0, "b": 0}
	distanceOne := event.pairCost(
		&Participant{ID: "a", InitialOrder: 0}, &Participant{ID: "b", InitialOrder: 1},
		ranks, points)
	distanceTen := event.pairCost(
		&Participant{ID: "a", InitialOrder: 0}, &Participant{ID: "b", InitialOrder: 10},
		ranks, points)
	distanceTwenty := event.pairCost(
		&Participant{ID: "a", InitialOrder: 0}, &Participant{ID: "b", InitialOrder: 20},
		ranks, points)
	if distanceOne >= distanceTen || distanceTen > distanceTwenty {
		t.Fatalf("initial-order tiebreak not monotonic: d1=%d d10=%d d20=%d",
			distanceOne, distanceTen, distanceTwenty)
	}
}
