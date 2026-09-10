// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package tournament

import (
	"math"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestScoreBoundsRejectOverflowBeforeChangingPairing(t *testing.T) {
	for _, matchMode := range []string{protocol.MatchBO1, protocol.MatchBO3} {
		t.Run(matchMode, func(t *testing.T) {
			event, organizer := newTestTournament(t, 4, matchMode)
			if err := event.Start(organizer, 42, testNow); err != nil {
				t.Fatal(err)
			}
			pairing := event.CurrentPairing(event.Participants[0].ID)
			wins := 1
			if matchMode == protocol.MatchBO3 {
				wins = 2
			}
			invalid := MatchScore{PlayerAWins: wins, DrawnGames: math.MaxInt}
			actor := actorFor(event, 0)
			if err := event.Report(actor, pairing.ID, invalid, testNow); err == nil {
				t.Error("report accepted an overflowing game total")
			}
			if err := event.Correct(organizer, pairing.ID, invalid, testNow); err == nil {
				t.Error("correction accepted an overflowing game total")
			}
			current := event.CurrentPairing(actor.ParticipantID)
			if current.Pending != nil || current.Result != nil {
				t.Error("invalid score changed pairing or standings")
			}
			if err := event.Report(actor, pairing.ID,
				MatchScore{PlayerAWins: wins, DrawnGames: MaxReportedGames - wins}, testNow); err != nil {
				t.Fatalf("valid exact-boundary score rejected: %v", err)
			}
		})
	}
}
