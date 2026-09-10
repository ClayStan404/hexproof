// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package tournament

import (
	"reflect"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
)

func TestCubeInvitationsRequireConsentAndCanAlwaysBeDeclinedBeforeOpening(t *testing.T) {
	event, organizer := cubeDraftThroughDeckBuilding(t, protocol.LimitedCoordinatorCasual)
	a, b, outsider := actorFor(event, 0), actorFor(event, 1), actorFor(event, 2)
	if _, err := event.CreateCasualMatch(organizer, a.ParticipantID, b.ParticipantID); ErrorCode(err) != ErrForbidden {
		t.Fatal("nonparticipating organizer could assign other players")
	}
	if _, err := event.CreateCasualMatch(a, b.ParticipantID, outsider.ParticipantID); ErrorCode(err) != ErrForbidden {
		t.Fatal("participant could choose two other players")
	}
	pairing, err := event.CreateCasualMatch(a, a.ParticipantID, b.ParticipantID)
	if err != nil || !pairing.Invited {
		t.Fatalf("invitation: %+v %v", pairing, err)
	}
	if err := event.CancelCubeMatch(outsider, a.ParticipantID, b.ParticipantID); ErrorCode(err) != ErrForbidden {
		t.Fatal("outsider cancelled another invitation")
	}
	if _, err := event.CreateCasualMatch(a, a.ParticipantID, b.ParticipantID); err == nil || !pairing.Invited {
		t.Fatal("inviter supplied consent on behalf of opponent")
	}
	if err := event.CancelCubeMatch(b, b.ParticipantID, a.ParticipantID); err != nil || len(event.CasualPairings) != 0 {
		t.Fatalf("recipient could not decline: %v", err)
	}
	_, _ = event.CreateCasualMatch(a, a.ParticipantID, b.ParticipantID)
	accepted, err := event.CreateCasualMatch(b, b.ParticipantID, a.ParticipantID)
	if err != nil || accepted.Invited {
		t.Fatal("reciprocal choice did not consent")
	}
	if err := event.CancelCubeMatch(a, a.ParticipantID, b.ParticipantID); err != nil || len(event.CasualPairings) != 0 {
		t.Fatal("accepted unopened pairing trapped its players")
	}
	_, _ = event.CreateCasualMatch(a, a.ParticipantID, b.ParticipantID)
	event.Disconnect(b.ConnectionID, testNow.Add(time.Minute))
	if len(event.CasualPairings) != 0 {
		t.Fatal("disconnect left an unopened invitation reserving players")
	}
	if _, err := event.CreateCasualMatch(b, b.ParticipantID, a.ParticipantID); ErrorCode(err) != ErrForbidden {
		t.Fatal("disconnected participant retained match authority")
	}
	if _, _, ok := event.BindCredential(CredentialHash("token-2"), "new-connection", testNow); !ok {
		t.Fatal("participant credential did not recover")
	}
	if _, err := event.CreateCasualMatch(b, b.ParticipantID, a.ParticipantID); ErrorCode(err) != ErrForbidden {
		t.Fatal("old connection regained authority after credential transfer")
	}
	b.ConnectionID = "new-connection"
	_, _ = event.CreateCasualMatch(a, a.ParticipantID, b.ParticipantID)
	accepted, _ = event.CreateCasualMatch(b, b.ParticipantID, a.ParticipantID)
	if err := event.SetPairingRoom(a, accepted.ID, "ROOM12"); err != nil {
		t.Fatal(err)
	}
	if err := event.CancelCubeMatch(b, a.ParticipantID, b.ParticipantID); ErrorCode(err) != ErrForbidden {
		t.Fatal("cancel invitation detached an already opened game")
	}
	event.Disconnect(b.ConnectionID, testNow)
	if len(event.CasualPairings) != 1 {
		t.Fatal("disconnect discarded a live match instead of preserving reconnect")
	}
}

func TestCubeFreePlayDeckEditsRetainContainmentAndRespectReservations(t *testing.T) {
	event, _ := cubeDraftThroughDeckBuilding(t, protocol.LimitedCoordinatorCasual)
	a, b := actorFor(event, 0), actorFor(event, 1)
	request := protocol.LimitedSubmitDeck{Name: "Rebuilt deck", BasicLands: []protocol.LimitedBasicLand{{Name: "Island", Count: 17}}}
	for _, card := range event.LimitedSnapshot(a.ParticipantID).Pool[:23] {
		request.MainboardInstanceIDs = append(request.MainboardInstanceIDs, card.InstanceID)
	}
	if _, err := event.SubmitLimitedDeck(a, request); err != nil || event.Stage != protocol.LimitedStageCompetition {
		t.Fatalf("free-play rebuild failed: %v", err)
	}
	before := cloneDeck(*event.Participant(a.ParticipantID).Deck)
	invalid := request
	invalid.MainboardInstanceIDs = []string{"not-in-this-pool"}
	if _, err := event.SubmitLimitedDeck(a, invalid); err == nil {
		t.Fatal("free-play deck escaped the locked pool")
	}
	if !reflect.DeepEqual(before, *event.Participant(a.ParticipantID).Deck) {
		t.Fatal("invalid free-play rebuild modified the submitted deck")
	}
	_, _ = event.CreateCasualMatch(a, a.ParticipantID, b.ParticipantID)
	if _, err := event.SubmitLimitedDeck(a, request); ErrorCode(err) != ErrNotReady {
		t.Fatal("reserved player could change the agreed deck")
	}
	_ = event.CancelCubeMatch(b, a.ParticipantID, b.ParticipantID)
	if _, err := event.SubmitLimitedDeck(a, request); err != nil {
		t.Fatalf("cancel did not unlock deck editing: %v", err)
	}
}
