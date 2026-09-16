// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package tournament

import (
	"fmt"
	"reflect"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
)

func seatControlDraft(t *testing.T, eventType, coordinator string, seats int) (*Tournament, Actor) {
	t.Helper()
	product := tournamentLimitedProduct()
	product.ProductType, product.CardsPerPack, product.Variants = "cube", 0, nil
	product.Authentic = false
	for index := range product.Sheets[0].Cards {
		product.Sheets[0].Cards[index].Weight = seats
	}
	var settings *protocol.LimitedDraftSettings
	if eventType == protocol.LimitedEventCommanderCube {
		settings = &protocol.LimitedDraftSettings{PacksPerPlayer: 3, PacksPerBatch: 1}
	}
	event, err := New("SEATS1", Config{Name: "Seat control", Format: "Cube", EventType: eventType,
		Coordinator: coordinator, MatchMode: "bo1", RoundMinutes: 50, MaxPlayers: seats, Product: &product, DraftSettings: settings},
		"Host", "host-conn", CredentialHash("host-token"), testNow)
	if err != nil {
		t.Fatal(err)
	}
	for index := 0; index < seats; index++ {
		participant, err := event.Register(fmt.Sprintf("Player %d", index), fmt.Sprintf("conn-%d", index),
			CredentialHash(fmt.Sprintf("token-%d", index)), testNow)
		if err != nil {
			t.Fatal(err)
		}
		participant.CheckedIn = true
	}
	organizer := Actor{ConnectionID: "host-conn", Role: RoleOrganizer}
	if err := event.Start(organizer, 24, testNow); err != nil {
		t.Fatal(err)
	}
	return event, organizer
}

func finishSeatControlDraft(t *testing.T, event *Tournament) {
	t.Helper()
	for index := range event.Participants {
		if err := event.SetCubeDraftControl(actorFor(event, index), protocol.LimitedSetDraftControl{Automatic: true}, testNow); err != nil {
			t.Fatal(err)
		}
	}
	if event.Stage != protocol.LimitedStageDeckBuilding {
		t.Fatal("automatic draft did not finish")
	}
}

func submitSeatControlDeck(t *testing.T, event *Tournament, index int) {
	t.Helper()
	actor := actorFor(event, index)
	pool := event.LimitedSnapshot(actor.ParticipantID).Pool
	request := protocol.LimitedSubmitDeck{Name: "Preserved deck"}
	for _, card := range pool[:23] {
		request.MainboardInstanceIDs = append(request.MainboardInstanceIDs, card.InstanceID)
	}
	if event.IsCommanderCube() {
		request.CommanderInstanceIDs = request.MainboardInstanceIDs[:1]
		request.BasicLands = []protocol.LimitedBasicLand{{Name: "Island", Count: 37}}
	} else {
		request.BasicLands = []protocol.LimitedBasicLand{{Name: "Island", Count: 17}}
	}
	if _, err := event.SubmitLimitedDeck(actor, request); err != nil {
		t.Fatal(err)
	}
}

func TestCubeHostAutoDraftRequiresContinuousOfflineDelayAndExplicitReclaim(t *testing.T) {
	event, host := seatControlDraft(t, protocol.LimitedEventCommanderCube, protocol.LimitedCoordinatorCasual, 3)
	guest := actorFor(event, 1)
	request := protocol.LimitedSetDraftControl{ParticipantID: guest.ParticipantID, Automatic: true}
	before := event.LimitedSnapshot(guest.ParticipantID)
	if err := event.SetCubeDraftControl(host, request, testNow.Add(time.Hour)); ErrorCode(err) != ErrNotReady {
		t.Fatal("host took over an online seat")
	}
	event.Disconnect(guest.ConnectionID, testNow)
	if !reflect.DeepEqual(before, event.LimitedSnapshot(guest.ParticipantID)) {
		t.Fatal("disconnect automatically picked cards")
	}
	for _, elapsed := range []time.Duration{-time.Minute, 0, time.Minute, 3 * time.Minute} {
		if err := event.SetCubeDraftControl(host, request, testNow.Add(elapsed)); ErrorCode(err) != ErrNotReady {
			t.Fatalf("host takeover accepted at %v: %v", elapsed, err)
		}
	}
	event.Disconnect(guest.ConnectionID, testNow.Add(2*time.Minute))
	if event.Disconnect("", testNow.Add(2*time.Minute)) {
		t.Fatal("an empty transport identity disconnected reserved offline seats")
	}
	if !event.Participant(guest.ParticipantID).DisconnectedAt.Equal(testNow) {
		t.Fatal("redundant disconnect reset the offline clock")
	}
	if err := event.SetCubeDraftControl(host, request, testNow.Add(3*time.Minute+time.Nanosecond)); err != nil {
		t.Fatal(err)
	}
	if !event.Limited.Player(guest.ParticipantID).AutoDraft {
		t.Fatal("host did not explicitly enable automatic drafting")
	}
	if err := event.SetCubeDraftControl(guest, protocol.LimitedSetDraftControl{Automatic: false}, testNow); ErrorCode(err) != ErrForbidden {
		t.Fatal("stale disconnected session reclaimed a seat")
	}
	_, _, ok := event.BindCredential(CredentialHash("token-1"), "guest-new", testNow.Add(4*time.Minute))
	if !ok || !event.Participant(guest.ParticipantID).DisconnectedAt.IsZero() || !event.Limited.Player(guest.ParticipantID).AutoDraft {
		t.Fatal("reconnect lost control state or retained the offline timer")
	}
	request.Automatic = false
	if err := event.SetCubeDraftControl(host, request, testNow.Add(time.Hour)); ErrorCode(err) != ErrForbidden {
		t.Fatal("host reclaimed someone else's draft control")
	}
	guest.ConnectionID = "guest-new"
	if err := event.SetCubeDraftControl(guest, protocol.LimitedSetDraftControl{Automatic: false}, testNow); err != nil {
		t.Fatal(err)
	}
	event.Disconnect("conn-1", testNow.Add(time.Hour))
	if !event.Participant(guest.ParticipantID).DisconnectedAt.IsZero() {
		t.Fatal("old transport disconnect affected the replacement session")
	}
	event.Disconnect("guest-new", testNow.Add(5*time.Minute))
	request.Automatic = true
	if err := event.SetCubeDraftControl(host, request, testNow.Add(6*time.Minute)); ErrorCode(err) != ErrNotReady {
		t.Fatal("new disconnect reused the previous offline period")
	}
}

func TestCubeOfflineDelayRetainsMonotonicClock(t *testing.T) {
	event, host := seatControlDraft(t, protocol.LimitedEventCubeDraft, protocol.LimitedCoordinatorCasual, 2)
	guest := actorFor(event, 1)
	now := time.Now()
	if now == now.Round(0) {
		t.Skip("platform clock does not provide a monotonic reading")
	}
	event.Disconnect(guest.ConnectionID, now)
	// Direct equality includes the monotonic reading. Equal() alone would
	// incorrectly accept a UTC conversion that preserves only wall-clock time.
	if event.Participant(guest.ParticipantID).DisconnectedAt != now {
		t.Fatal("disconnect discarded the monotonic reading needed for elapsed-time checks")
	}
	request := protocol.LimitedSetDraftControl{ParticipantID: guest.ParticipantID, Automatic: true}
	if err := event.SetCubeDraftControl(host, request, now.Add(CubeHostAutoDraftDelay)); ErrorCode(err) != ErrNotReady {
		t.Fatal("monotonic deadline accepted takeover at exactly three minutes")
	}
	if err := event.SetCubeDraftControl(host, request, now.Add(CubeHostAutoDraftDelay+time.Nanosecond)); err != nil {
		t.Fatal(err)
	}
}

func TestCubeDraftControlAuthorityAndScope(t *testing.T) {
	event, host := seatControlDraft(t, protocol.LimitedEventCubeDraft, protocol.LimitedCoordinatorCasual, 3)
	guest, other := actorFor(event, 1), actorFor(event, 2)
	if err := event.SetCubeDraftControl(guest, protocol.LimitedSetDraftControl{ParticipantID: other.ParticipantID, Automatic: true}, testNow); ErrorCode(err) != ErrForbidden {
		t.Fatal("participant changed another seat")
	}
	event.BindCredential(CredentialHash("host-token"), "new-host", testNow)
	if err := event.SetCubeDraftControl(host, protocol.LimitedSetDraftControl{ParticipantID: guest.ParticipantID, Automatic: true}, testNow); ErrorCode(err) != ErrForbidden {
		t.Fatal("replaced host session kept control authority")
	}
	if err := event.SetCubeDraftControl(Actor{ConnectionID: "viewer", Role: RoleViewer}, protocol.LimitedSetDraftControl{ParticipantID: guest.ParticipantID, Automatic: true}, testNow); ErrorCode(err) != ErrForbidden {
		t.Fatal("spectator acquired draft control")
	}
	swiss, _ := seatControlDraft(t, protocol.LimitedEventCubeDraft, protocol.LimitedCoordinatorSwiss, 4)
	if err := swiss.SetCubeDraftControl(actorFor(swiss, 0), protocol.LimitedSetDraftControl{Automatic: true}, testNow); ErrorCode(err) != ErrInvalid {
		t.Fatal("Cube free-play opt-in changed Swiss draft policy")
	}
	if err := event.SetCubeParticipation(guest, false); ErrorCode(err) != ErrInvalid {
		t.Fatal("draft withdrawal bypassed reserved physical seat")
	}
}

func TestCubeWithdrawalRetainsPoolAndDoesNotBlockOtherDecks(t *testing.T) {
	for _, eventType := range []string{protocol.LimitedEventCubeDraft, protocol.LimitedEventCommanderCube} {
		t.Run(eventType, func(t *testing.T) {
			event, host := seatControlDraft(t, eventType, protocol.LimitedCoordinatorCasual, 3)
			finishSeatControlDraft(t, event)
			guest := actorFor(event, 2)
			before := event.LimitedSnapshot(guest.ParticipantID).Pool
			if err := event.SetCubeParticipation(host, false); ErrorCode(err) != ErrForbidden {
				t.Fatal("nonparticipating organizer changed a player's participation")
			}
			if err := event.SetCubeParticipation(guest, false); err != nil {
				t.Fatal(err)
			}
			submitSeatControlDeck(t, event, 0)
			if event.Stage != protocol.LimitedStageDeckBuilding {
				t.Fatal("free play opened with only one submitted active player")
			}
			submitSeatControlDeck(t, event, 1)
			if event.Stage != protocol.LimitedStageCompetition || !event.Limited.AllDecksSubmitted() || !event.Participant(guest.ParticipantID).Dropped {
				t.Fatal("withdrawn player blocked the ready players")
			}
			if !reflect.DeepEqual(before, event.LimitedSnapshot(guest.ParticipantID).Pool) {
				t.Fatal("withdrawal discarded private pool")
			}
			if err := event.SetCubeParticipation(guest, true); ErrorCode(err) != ErrNotReady || !event.Participant(guest.ParticipantID).Dropped {
				t.Fatal("unbuilt player resumed during free play")
			}
			submitSeatControlDeck(t, event, 2)
			if !event.Participant(guest.ParticipantID).Dropped || !event.Limited.Player(guest.ParticipantID).Withdrawn {
				t.Fatal("submitting silently restored participation")
			}
			if err := event.SetCubeParticipation(guest, true); err != nil || event.Participant(guest.ParticipantID).Dropped || event.Limited.Player(guest.ParticipantID).Withdrawn {
				t.Fatal("built player could not explicitly return")
			}
			if event.Stage != protocol.LimitedStageCompetition {
				t.Fatal("resuming a seat regressed free play")
			}
		})
	}
}

func TestCubeWithdrawalMinimumAndRestoreBeforeFreePlay(t *testing.T) {
	event, _ := seatControlDraft(t, protocol.LimitedEventCubeDraft, protocol.LimitedCoordinatorCasual, 2)
	finishSeatControlDraft(t, event)
	guest := actorFor(event, 1)
	if err := event.SetCubeParticipation(guest, false); err != nil {
		t.Fatal(err)
	}
	submitSeatControlDeck(t, event, 0)
	if event.Limited.AllDecksSubmitted() || event.Stage != protocol.LimitedStageDeckBuilding {
		t.Fatal("one-player Cube entered free play")
	}
	if err := event.SetCubeParticipation(guest, true); err != nil || event.Stage != protocol.LimitedStageDeckBuilding {
		t.Fatal("unsubmitted seat could not restore during construction")
	}
	submitSeatControlDeck(t, event, 1)
	a := actorFor(event, 0)
	pair := event.CurrentPairing(a.ParticipantID)
	if pair == nil || pair.Invited {
		t.Fatal("all submitted players did not receive the initial table")
	}
	if err := event.SetCubeParticipation(guest, false); ErrorCode(err) != ErrNotReady {
		t.Fatal("reserved seat withdrew without releasing invitation")
	}
	if err := event.SetPairingRoom(a, pair.ID, "TABLE1"); err != nil {
		t.Fatal(err)
	}
	if err := event.SetCubeParticipation(a, false); ErrorCode(err) != ErrNotReady {
		t.Fatal("active table seat withdrew")
	}
}
