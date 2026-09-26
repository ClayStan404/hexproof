// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package tournament

import "testing"

func TestTimeoutResultAssignsTheMatchLoss(t *testing.T) {
	event, organizer := newTestTournament(t, 4, "bo3")
	if err := event.Start(organizer, 7, testNow); err != nil {
		t.Fatal(err)
	}
	round := event.CurrentRound()
	if round == nil || len(round.Pairings) == 0 {
		t.Fatal("expected a pairing")
	}
	pairing := &round.Pairings[0]
	if pairing.Bye() {
		t.Fatal("first pairing was a bye")
	}
	loser := pairing.PlayerBID
	if err := event.ApplyTimeout(pairing.ID, loser, 2, 0, testNow); err != nil {
		t.Fatal(err)
	}
	if pairing.Result == nil || pairing.Result.ConfirmedBy != "timeout" ||
		pairing.Result.Score.PlayerAWins != 2 || pairing.Result.Score.PlayerBWins != 0 {
		t.Fatalf("timeout result = %+v", pairing.Result)
	}
	if err := event.ApplyTimeout(pairing.ID, loser, 2, 0, testNow); ErrorCode(err) != ErrResultInvalid {
		t.Fatalf("second timeout = %v", err)
	}
}
