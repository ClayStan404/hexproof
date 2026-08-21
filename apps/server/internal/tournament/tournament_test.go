// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package tournament

import (
	"math"
	"testing"
	"time"
)

var testNow = time.Date(2026, 8, 8, 12, 0, 0, 0, time.UTC)

func newTestTournament(t *testing.T, players int, matchMode string) (*Tournament, Actor) {
	t.Helper()
	event, err := New("ABC123", Config{
		Name: "Friday Swiss", Format: "modern", MatchMode: matchMode,
		RoundMinutes: 50, MaxPlayers: 64,
	}, "Judge", "organizer-conn", CredentialHash("organizer-token"), testNow)
	if err != nil {
		t.Fatalf("new tournament: %v", err)
	}
	for index := 0; index < players; index++ {
		participant, registerErr := event.Register(
			string(rune('A'+index)), "conn-"+string(rune('A'+index)),
			CredentialHash("token-"+string(rune('A'+index))), testNow)
		if registerErr != nil {
			t.Fatalf("register player %d: %v", index, registerErr)
		}
		participant.CheckedIn = true
	}
	return event, Actor{ConnectionID: "organizer-conn", Role: RoleOrganizer}
}

func actorFor(event *Tournament, index int) Actor {
	participant := event.Participants[index]
	return Actor{
		ConnectionID: participant.ConnectionID,
		Role:         RoleParticipant, ParticipantID: participant.ID,
	}
}

func TestRecommendedRounds(t *testing.T) {
	tests := []struct{ players, rounds int }{
		{3, 0}, {4, 3}, {8, 3}, {9, 5}, {32, 5}, {33, 6},
		{64, 6}, {65, 7}, {128, 7}, {129, 8}, {226, 8},
		{227, 9}, {409, 9}, {410, 10},
	}
	for _, test := range tests {
		if got := RecommendedRounds(test.players); got != test.rounds {
			t.Errorf("RecommendedRounds(%d) = %d, want %d",
				test.players, got, test.rounds)
		}
	}
}

func TestTerminalStatusRecordsClosedAt(t *testing.T) {
	cancelled, organizer := newTestTournament(t, 0, "bo3")
	cancelledAt := testNow.Add(time.Hour)
	if err := cancelled.Cancel(organizer, cancelledAt); err != nil {
		t.Fatalf("cancel: %v", err)
	}
	if cancelled.Status != StatusCancelled || !cancelled.ClosedAt.Equal(cancelledAt) {
		t.Fatalf("cancelled status=%q closedAt=%v", cancelled.Status, cancelled.ClosedAt)
	}

	completed, organizer := newTestTournament(t, 0, "bo3")
	completed.Status = StatusRunning
	completed.PlannedRounds = 1
	completed.Rounds = []Round{{Number: 1}}
	completedAt := testNow.Add(2 * time.Hour)
	if err := completed.Advance(organizer, completedAt); err != nil {
		t.Fatalf("complete: %v", err)
	}
	if completed.Status != StatusCompleted || !completed.ClosedAt.Equal(completedAt) {
		t.Fatalf("completed status=%q closedAt=%v", completed.Status, completed.ClosedAt)
	}
}

func TestCredentialReentryAndRegistrationPrivacyState(t *testing.T) {
	event, _ := newTestTournament(t, 4, "bo3")
	role, participantID, ok := event.BindCredential(
		CredentialHash("token-A"), "replacement-conn", testNow)
	if !ok || role != RoleParticipant || participantID != event.Participants[0].ID {
		t.Fatalf("participant bind = %q %q %t", role, participantID, ok)
	}
	if event.Participants[0].ConnectionID != "replacement-conn" {
		t.Fatal("participant connection was not rebound")
	}
	role, participantID, ok = event.BindCredential(
		CredentialHash("organizer-token"), "replacement-organizer", testNow)
	if !ok || role != RoleOrganizer || participantID != "" ||
		event.OrganizerConnectionID != "replacement-organizer" {
		t.Fatalf("organizer bind = %q %q %t", role, participantID, ok)
	}
	if _, _, ok := event.BindCredential(CredentialHash("wrong"), "attacker", testNow); ok {
		t.Fatal("wrong credential entered tournament")
	}
}

func TestCredentialRebindRevokesStaleParticipantAuthority(t *testing.T) {
	event, organizer := newTestTournament(t, 4, "bo3")
	staleActor := actorFor(event, 0)
	if err := event.Start(organizer, 7, testNow); err != nil {
		t.Fatalf("start: %v", err)
	}

	role, participantID, ok := event.BindCredential(
		CredentialHash("token-A"), "replacement-conn", testNow.Add(time.Minute))
	if !ok || role != RoleParticipant || participantID != staleActor.ParticipantID {
		t.Fatalf("rebind = (%q, %q, %v)", role, participantID, ok)
	}
	pairing := event.CurrentPairing(participantID)
	if pairing == nil {
		t.Fatal("replacement participant has no pairing")
	}
	score := MatchScore{PlayerAWins: 2}
	if pairing.PlayerBID == participantID {
		score = MatchScore{PlayerBWins: 2}
	}
	if err := event.Report(staleActor, pairing.ID, score, testNow); ErrorCode(err) != ErrForbidden {
		t.Fatalf("stale report = %v", err)
	}
	if err := event.SetPairingRoom(staleActor, pairing.ID, "ROOM-OLD"); ErrorCode(err) != ErrForbidden {
		t.Fatalf("stale room bind = %v", err)
	}
	replacement := Actor{
		ConnectionID: "replacement-conn", Role: RoleParticipant, ParticipantID: participantID,
	}
	if err := event.Report(replacement, pairing.ID, score, testNow); err != nil {
		t.Fatalf("replacement report: %v", err)
	}
}

func TestCredentialRebindRevokesStaleOrganizerAuthority(t *testing.T) {
	event, staleOrganizer := newTestTournament(t, 4, "bo3")
	role, _, ok := event.BindCredential(CredentialHash("organizer-token"),
		"replacement-organizer", testNow.Add(time.Minute))
	if !ok || role != RoleOrganizer {
		t.Fatalf("organizer rebind = (%q, %v)", role, ok)
	}
	if err := event.Start(staleOrganizer, 7, testNow); ErrorCode(err) != ErrForbidden {
		t.Fatalf("stale organizer start = %v", err)
	}
	replacement := Actor{ConnectionID: "replacement-organizer", Role: RoleOrganizer}
	if err := event.Start(replacement, 7, testNow); err != nil {
		t.Fatalf("replacement organizer start: %v", err)
	}
}

func TestOrganizerCredentialRestoresOwnParticipantSeat(t *testing.T) {
	event, organizer := newTestTournament(t, 0, "bo3")
	participant, err := event.Register("Judge", organizer.ConnectionID,
		CredentialHash("participant-token"), testNow)
	if err != nil {
		t.Fatalf("register organizer: %v", err)
	}
	event.OrganizerParticipantID = participant.ID
	event.Disconnect(organizer.ConnectionID, testNow)
	if event.OrganizerConnectionID != "" || event.OrganizerDisconnectedAt.IsZero() ||
		!event.LastActivityAt.Equal(testNow) {
		t.Fatalf("disconnect activity=%v organizer=%q disconnectedAt=%v",
			event.LastActivityAt, event.OrganizerConnectionID, event.OrganizerDisconnectedAt)
	}

	reconnectedAt := testNow.Add(time.Minute)
	role, participantID, ok := event.BindCredential(
		CredentialHash("organizer-token"), "organizer-reconnected", reconnectedAt)
	if !ok || role != RoleOrganizer || participantID != participant.ID {
		t.Fatalf("binding = (%q, %q, %v)", role, participantID, ok)
	}
	if participant.ConnectionID != "organizer-reconnected" {
		t.Fatalf("participant connection = %q", participant.ConnectionID)
	}
	if !event.OrganizerDisconnectedAt.IsZero() || !event.LastActivityAt.Equal(reconnectedAt) {
		t.Fatalf("rebind activity=%v disconnectedAt=%v",
			event.LastActivityAt, event.OrganizerDisconnectedAt)
	}
}

func TestStartRequiresFourCheckedInPlayers(t *testing.T) {
	event, organizer := newTestTournament(t, 4, "bo3")
	event.Participants[3].CheckedIn = false
	if err := event.Start(organizer, 7, testNow); ErrorCode(err) != ErrNotReady {
		t.Fatalf("start with three checked in = %v", err)
	}
	event.Participants[3].CheckedIn = true
	if err := event.Start(organizer, 7, testNow); err != nil {
		t.Fatalf("start: %v", err)
	}
	if event.Status != StatusRunning || event.PlannedRounds != 3 ||
		len(event.Rounds) != 1 || len(event.Rounds[0].Pairings) != 2 {
		t.Fatalf("started state = %+v", event)
	}
}

func TestOddFieldAwardsLowestEligibleByeAndIgnoresItForOpponentAverage(t *testing.T) {
	event, organizer := newTestTournament(t, 5, "bo3")
	if err := event.Start(organizer, 11, testNow); err != nil {
		t.Fatalf("start: %v", err)
	}
	var bye *Pairing
	for index := range event.Rounds[0].Pairings {
		if event.Rounds[0].Pairings[index].Bye() {
			bye = &event.Rounds[0].Pairings[index]
		}
	}
	if bye == nil || bye.Result == nil || bye.Result.Score.PlayerAWins != 2 {
		t.Fatalf("bye pairing = %+v", bye)
	}
	standing := event.Standings()
	var byeStanding *Standing
	for index := range standing {
		if standing[index].ParticipantID == bye.PlayerAID {
			byeStanding = &standing[index]
		}
	}
	if byeStanding == nil || byeStanding.MatchPoints != 3 || byeStanding.Wins != 1 ||
		byeStanding.GameWin != 1 || byeStanding.OppMatchWin != percentageFloor {
		t.Fatalf("bye standing = %+v", byeStanding)
	}
}

func TestReportRejectConfirmAndOrganizerCorrection(t *testing.T) {
	event, organizer := newTestTournament(t, 4, "bo3")
	if err := event.Start(organizer, 3, testNow); err != nil {
		t.Fatalf("start: %v", err)
	}
	pairing := &event.Rounds[0].Pairings[0]
	left := event.participantByID[pairing.PlayerAID]
	right := event.participantByID[pairing.PlayerBID]
	leftActor := Actor{ConnectionID: left.ConnectionID, Role: RoleParticipant,
		ParticipantID: left.ID}
	rightActor := Actor{ConnectionID: right.ConnectionID, Role: RoleParticipant,
		ParticipantID: right.ID}

	if err := event.Report(leftActor, pairing.ID,
		MatchScore{PlayerAWins: 2, PlayerBWins: 1}, testNow); err != nil {
		t.Fatalf("report: %v", err)
	}
	if err := event.Confirm(leftActor, pairing.ID, testNow); ErrorCode(err) != ErrForbidden {
		t.Fatalf("self-confirm = %v", err)
	}
	if err := event.Reject(rightActor, pairing.ID); err != nil {
		t.Fatalf("reject: %v", err)
	}
	if pairing.Pending != nil {
		t.Fatal("rejected result remained pending")
	}
	if err := event.Report(leftActor, pairing.ID,
		MatchScore{PlayerAWins: 2}, testNow); err != nil {
		t.Fatalf("report retry: %v", err)
	}
	if err := event.Confirm(rightActor, pairing.ID, testNow); err != nil {
		t.Fatalf("confirm: %v", err)
	}
	if pairing.Result == nil || pairing.Result.Score.PlayerAWins != 2 {
		t.Fatalf("confirmed result = %+v", pairing.Result)
	}
	if err := event.Correct(organizer, pairing.ID,
		MatchScore{PlayerBWins: 2, PlayerAWins: 1}, testNow); err != nil {
		t.Fatalf("correct: %v", err)
	}
	if !pairing.Result.Corrected || pairing.Result.Score.PlayerBWins != 2 {
		t.Fatalf("corrected result = %+v", pairing.Result)
	}
}

func TestStandingsUseOfficialTiebreakerOrderAndFloors(t *testing.T) {
	event, organizer := newTestTournament(t, 4, "bo3")
	if err := event.Start(organizer, 13, testNow); err != nil {
		t.Fatalf("start: %v", err)
	}
	for index := range event.Rounds[0].Pairings {
		pairing := &event.Rounds[0].Pairings[index]
		left := event.participantByID[pairing.PlayerAID]
		actor := Actor{ConnectionID: left.ConnectionID, Role: RoleParticipant,
			ParticipantID: left.ID}
		if err := event.Report(actor, pairing.ID, MatchScore{PlayerAWins: 2}, testNow); err != nil {
			t.Fatalf("report %d: %v", index, err)
		}
		right := event.participantByID[pairing.PlayerBID]
		if err := event.Confirm(Actor{ConnectionID: right.ConnectionID,
			Role: RoleParticipant, ParticipantID: right.ID}, pairing.ID, testNow); err != nil {
			t.Fatalf("confirm %d: %v", index, err)
		}
	}
	standings := event.Standings()
	if len(standings) != 4 || standings[0].MatchPoints != 3 ||
		standings[2].MatchPoints != 0 {
		t.Fatalf("standings = %+v", standings)
	}
	for _, standing := range standings {
		if standing.OppMatchWin < percentageFloor || standing.GameWin < percentageFloor ||
			standing.OppGameWin < percentageFloor {
			t.Fatalf("percentage floor not applied: %+v", standing)
		}
	}
	if math.Abs(standings[2].GameWin-percentageFloor) > 0.000001 {
		t.Fatalf("loser GWP = %f, want floor", standings[2].GameWin)
	}
}

func TestLaterSwissRoundAvoidsRematches(t *testing.T) {
	event, organizer := newTestTournament(t, 8, "bo3")
	if err := event.Start(organizer, 19, testNow); err != nil {
		t.Fatalf("start: %v", err)
	}
	finishRound := func() {
		round := event.CurrentRound()
		for index := range round.Pairings {
			pairing := &round.Pairings[index]
			if pairing.Bye() {
				continue
			}
			left := event.participantByID[pairing.PlayerAID]
			right := event.participantByID[pairing.PlayerBID]
			if err := event.Report(Actor{ConnectionID: left.ConnectionID,
				Role: RoleParticipant, ParticipantID: left.ID}, pairing.ID,
				MatchScore{PlayerAWins: 2}, testNow); err != nil {
				t.Fatalf("report: %v", err)
			}
			if err := event.Confirm(Actor{ConnectionID: right.ConnectionID,
				Role: RoleParticipant, ParticipantID: right.ID}, pairing.ID, testNow); err != nil {
				t.Fatalf("confirm: %v", err)
			}
		}
	}
	firstOpponents := make(map[string]string)
	for _, pairing := range event.CurrentRound().Pairings {
		firstOpponents[pairing.PlayerAID] = pairing.PlayerBID
		firstOpponents[pairing.PlayerBID] = pairing.PlayerAID
	}
	finishRound()
	if err := event.Advance(organizer, testNow.Add(time.Hour)); err != nil {
		t.Fatalf("advance: %v", err)
	}
	for _, pairing := range event.CurrentRound().Pairings {
		if firstOpponents[pairing.PlayerAID] == pairing.PlayerBID {
			t.Fatalf("avoidable rematch: %+v", pairing)
		}
	}
}

func TestDropExcludesPlayerFromLaterPairings(t *testing.T) {
	event, organizer := newTestTournament(t, 5, "bo1")
	if err := event.Start(organizer, 23, testNow); err != nil {
		t.Fatalf("start: %v", err)
	}
	for index := range event.CurrentRound().Pairings {
		pairing := &event.CurrentRound().Pairings[index]
		if pairing.Bye() {
			continue
		}
		left := event.participantByID[pairing.PlayerAID]
		right := event.participantByID[pairing.PlayerBID]
		_ = event.Report(Actor{ConnectionID: left.ConnectionID, Role: RoleParticipant,
			ParticipantID: left.ID}, pairing.ID, MatchScore{PlayerAWins: 1}, testNow)
		_ = event.Confirm(Actor{ConnectionID: right.ConnectionID, Role: RoleParticipant,
			ParticipantID: right.ID}, pairing.ID, testNow)
	}
	dropped := event.Participants[0]
	if err := event.Drop(actorFor(event, 0), ""); err != nil {
		t.Fatalf("drop: %v", err)
	}
	if err := event.Advance(organizer, testNow.Add(time.Hour)); err != nil {
		t.Fatalf("advance: %v", err)
	}
	for _, pairing := range event.CurrentRound().Pairings {
		if pairing.PlayerAID == dropped.ID || pairing.PlayerBID == dropped.ID {
			t.Fatalf("dropped participant paired: %+v", pairing)
		}
	}
}
