// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package tournament

import (
	"reflect"
	"testing"

	"hexproof/server/internal/protocol"
)

func commanderGroupsHarness(t *testing.T) *Tournament {
	t.Helper()
	event, _ := newTestTournament(t, 4, protocol.MatchBO1)
	event.EventType = protocol.LimitedEventCommanderCube
	event.Coordinator = protocol.LimitedCoordinatorCasual
	event.Status = StatusRunning
	event.Stage = protocol.LimitedStageCompetition
	for _, player := range event.Participants {
		player.Competing = true
		player.Deck = &protocol.DeckSelect{Name: "Submitted pool deck"}
	}
	return event
}

func groupInvite(t *testing.T, event *Tournament, first int) *Pairing {
	t.Helper()
	ids := []string{}
	for index := first; index < first+4; index++ {
		ids = append(ids, event.Participants[index].ID)
	}
	if err := event.CommanderCubeMatch(actorFor(event, first), protocol.LimitedCreateCasualMatch{
		Action: "invite", PlayerIDs: ids,
	}); err != nil {
		t.Fatal(err)
	}
	return event.CurrentPairing(ids[0])
}

func TestCommanderCubeGroupsRequireEveryPlayersOwnConsent(t *testing.T) {
	event := commanderGroupsHarness(t)
	first := groupInvite(t, event, 0).ID
	pairing, _ := event.Pairing(first)
	if len(event.CasualPairings) != 1 || len(pairing.ParticipantIDs()) != 4 || pairing.Bye() {
		t.Fatal("four-player group did not reserve one table")
	}
	for index := 0; index < 4; index++ {
		if event.CurrentPairing(event.Participants[index].ID).ID != first {
			t.Fatal("invitation failed to reserve every selected player")
		}
	}
	request := protocol.LimitedCreateCasualMatch{Action: "accept", PairingID: first}
	if err := event.CommanderCubeMatch(Actor{ParticipantID: "outsider", ConnectionID: "outsider"}, request); err == nil {
		t.Fatal("outsider accepted another group's invitation")
	}
	for index := 1; index < 4; index++ {
		if err := event.SetPairingRoom(actorFor(event, 0), first, "GAME01"); err == nil {
			t.Fatal("room opened before every selected player accepted")
		}
		if err := event.CommanderCubeMatch(actorFor(event, index), request); err != nil {
			t.Fatal(err)
		}
		if pairing.Invited != (index < 3) {
			t.Fatal("group invitation became ready at the wrong acceptance count")
		}
	}
	if err := event.CommanderCubeMatch(actorFor(event, 3), request); err != nil || len(pairing.Group.AcceptedPlayerIDs) != 4 {
		t.Fatal("repeated acceptance changed group membership")
	}
	if err := event.SetPairingRoom(actorFor(event, 3), first, "GAME01"); err != nil {
		t.Fatalf("fourth player could not open agreed group: %v", err)
	}
	request.Action = "cancel"
	if err := event.CommanderCubeMatch(actorFor(event, 2), request); err == nil {
		t.Fatal("cancellation discarded an active group table")
	}
	event.ClearRoom("GAME01")
	for index := 0; index < 4; index++ {
		if event.CurrentPairing(event.Participants[index].ID) != nil {
			t.Fatal("retired group left a participant reserved")
		}
	}
	if len(event.CasualPairings) != 0 {
		t.Fatal("closing the table retained its reservation")
	}
}

func TestCommanderCubeRejectsForgedMembershipAndClearsPendingGroups(t *testing.T) {
	event := commanderGroupsHarness(t)
	a := actorFor(event, 0)
	ids := []string{event.Participants[0].ID, event.Participants[1].ID, event.Participants[2].ID}
	for _, selected := range [][]string{{ids[1], ids[2]}, {ids[0]}, {ids[0], ids[1], ids[1]},
		{ids[0], ids[1], ids[2], event.Participants[3].ID, "outside"}} {
		if err := event.CommanderCubeMatch(a, protocol.LimitedCreateCasualMatch{Action: "invite", PlayerIDs: selected}); err == nil {
			t.Fatal("invalid group accepted", selected)
		}
	}
	if len(event.CasualPairings) != 0 {
		t.Fatal("failed invitation mutated reservations")
	}
	if _, err := event.CreateCasualMatch(a, ids[0], ids[1]); err == nil {
		t.Fatal("legacy two-player endpoint bypassed Commander group semantics")
	}
	first := groupInvite(t, event, 0).ID
	request := protocol.LimitedCreateCasualMatch{Action: "accept", PairingID: first}
	stale := actorFor(event, 2)
	stale.ConnectionID = "not-the-seated-connection"
	if err := event.CommanderCubeMatch(stale, request); err == nil {
		t.Fatal("stale identity accepted on behalf of another player")
	}
	request.PlayerIDs = ids
	if err := event.CommanderCubeMatch(actorFor(event, 2), request); err == nil {
		t.Fatal("acceptance replaced invitation membership")
	}
	pairing, _ := event.Pairing(first)
	if !reflect.DeepEqual(pairing.Group.AcceptedPlayerIDs, []string{a.ParticipantID}) {
		t.Fatal("invalid actions changed accepted players")
	}
	request.PlayerIDs, request.Action = nil, "cancel"
	if err := event.CommanderCubeMatch(actorFor(event, 2), request); err != nil || len(event.CasualPairings) != 0 {
		t.Fatal("third invited player could not decline the group")
	}
	groupInvite(t, event, 0)
	event.Disconnect(actorFor(event, 3).ConnectionID, testNow)
	if len(event.CasualPairings) != 0 {
		t.Fatal("disconnected fourth member left a pending invitation reserving all players")
	}
}
