// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package tournament

import (
	"fmt"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestCubeInitialTableFollowsCompleteConstructionOnce(t *testing.T) {
	for _, profile := range []struct {
		eventType string
		seats     int
		wantTable bool
	}{
		{protocol.LimitedEventCubeDraft, 2, true},
		{protocol.LimitedEventCubeDraft, 3, false},
		{protocol.LimitedEventCubeDraft, 4, false},
		{protocol.LimitedEventCubeDraft, 8, false},
		{protocol.LimitedEventCommanderCube, 2, true},
		{protocol.LimitedEventCommanderCube, 3, true},
		{protocol.LimitedEventCommanderCube, 4, true},
	} {
		t.Run(fmt.Sprintf("%s_%d", profile.eventType, profile.seats), func(t *testing.T) {
			event, _ := seatControlDraft(t, profile.eventType, protocol.LimitedCoordinatorCasual, profile.seats)
			finishSeatControlDraft(t, event)
			for index := range event.Participants {
				if event.Stage != protocol.LimitedStageDeckBuilding || len(event.CasualPairings) != 0 {
					t.Fatal("table opened before every active player submitted")
				}
				submitSeatControlDeck(t, event, index)
			}
			if event.Stage != protocol.LimitedStageCompetition || !event.Limited.AllDecksSubmitted() {
				t.Fatal("complete construction did not enter free play")
			}
			if !profile.wantTable {
				if len(event.CasualPairings) != 0 {
					t.Fatal("normal multiplayer pod silently selected opponents")
				}
				return
			}
			if len(event.CasualPairings) != 1 {
				t.Fatal("complete pod did not receive one initial table")
			}
			pair := &event.CasualPairings[0]
			if pair.Invited || pair.Bye() || pair.RoomID != "" || !pair.InitialCubeTable ||
				len(pair.ParticipantIDs()) != profile.seats {
				t.Fatal("initial table unexpectedly needs invitation consent or lost a participant")
			}
			for _, participant := range event.Participants {
				if !pair.AutoEntryPending(participant.ID) || event.CurrentPairing(participant.ID) != pair {
					t.Fatal("participant lacks a reserved initial seat and entry request")
				}
			}
			if event.IsCommanderCube() && len(pair.Group.AcceptedPlayerIDs) != profile.seats {
				t.Fatal("initial Commander table was not accepted for its whole pod")
			}
			if err := event.SetPairingRoom(actorFor(event, 0), pair.ID, "FIRST1"); err != nil {
				t.Fatal(err)
			}
			event.MarkCubeTableEntered(event.Participants[0].ID, pair.ID)
			if pair.AutoEntryPending(event.Participants[0].ID) || !pair.AutoEntryPending(event.Participants[1].ID) {
				t.Fatal("one entry consumed another player's request")
			}
			event.ClearRoom("FIRST1")
			submitSeatControlDeck(t, event, 0)
			if len(event.CasualPairings) != 0 {
				t.Fatal("editing after leaving recreated the initial table")
			}
		})
	}
}

func TestCubeInitialTableExcludesWithdrawnSeatsAndSurvivesOfflineSeats(t *testing.T) {
	for _, eventType := range []string{protocol.LimitedEventCubeDraft, protocol.LimitedEventCommanderCube} {
		t.Run(eventType, func(t *testing.T) {
			event, _ := seatControlDraft(t, eventType, protocol.LimitedCoordinatorCasual, 3)
			finishSeatControlDraft(t, event)
			submitSeatControlDeck(t, event, 0)
			submitSeatControlDeck(t, event, 1)
			first, second, withdrawn := actorFor(event, 0), actorFor(event, 1), actorFor(event, 2)
			event.Disconnect(second.ConnectionID, testNow)
			if err := event.SetCubeParticipation(withdrawn, false); err != nil {
				t.Fatal(err)
			}
			pair := event.CurrentPairing(first.ParticipantID)
			if pair == nil || len(pair.ParticipantIDs()) != 2 || !pair.HasParticipant(second.ParticipantID) ||
				pair.HasParticipant(withdrawn.ParticipantID) {
				t.Fatal("withdrawal transition omitted a submitted offline seat or included a withdrawn seat")
			}
			event.Disconnect(first.ConnectionID, testNow)
			if len(event.CasualPairings) != 1 || !pair.AutoEntryPending(first.ParticipantID) ||
				!pair.AutoEntryPending(second.ParticipantID) {
				t.Fatal("short disconnect discarded the initial table")
			}
			if _, _, ok := event.BindCredential(CredentialHash("token-0"), "replacement", testNow); !ok {
				t.Fatal("rebind failed")
			}
			first.ConnectionID = "replacement"
			var err error
			if event.IsCommanderCube() {
				err = event.CommanderCubeMatch(first, protocol.LimitedCreateCasualMatch{Action: "cancel", PairingID: pair.ID})
			} else {
				err = event.CancelCubeMatch(first, first.ParticipantID, second.ParticipantID)
			}
			if err != nil || len(event.CasualPairings) != 0 {
				t.Fatal("explicit cancellation could not release the initial table")
			}
			submitSeatControlDeck(t, event, 0)
			if len(event.CasualPairings) != 0 {
				t.Fatal("cancelled initial table reappeared")
			}
		})
	}
}

func TestCommanderCubeCapacitySupportsTwoToEightDraftSeats(t *testing.T) {
	product := tournamentLimitedProduct()
	product.ProductType, product.CardsPerPack, product.Variants, product.Authentic = "cube", 0, nil, false
	for index := range product.Sheets[0].Cards {
		product.Sheets[0].Cards[index].Weight = 8
	}
	for _, seats := range []int{0, 1, 2, 3, 4, 5, 8, 9} {
		event, err := New("CAPCMD", Config{Name: "Commander", Format: protocol.FormatEDH, EventType: protocol.LimitedEventCommanderCube,
			Coordinator: protocol.LimitedCoordinatorCasual, MatchMode: protocol.MatchBO1, MaxPlayers: seats,
			Product: &product}, "Host", "host", CredentialHash("token"), testNow)
		if seats == 1 || seats > 8 {
			if err == nil {
				t.Fatalf("accepted %d Commander Cube seats", seats)
			}
			continue
		}
		if err != nil {
			t.Fatal(err)
		}
		want := seats
		if want == 0 {
			want = 4
		}
		if event.MaxPlayers != want {
			t.Fatalf("capacity=%d, want %d", event.MaxPlayers, want)
		}
	}
}

func TestCommanderPackSizeLocksCapacityBeforePlayersJoin(t *testing.T) {
	const required = 8 * 3 * 25
	product := protocol.LimitedProductDefinition{ID: "custom-size", Name: "Custom pack Cube", ProductType: "cube",
		Sheets: []protocol.LimitedSheetDefinition{{Name: "stock", Cards: []protocol.LimitedCardDefinition{
			{Name: "Pack legend", SetCode: "TST", CollectorNumber: "1", TypeLine: "Legendary Creature", Weight: required - 1},
		}}}}
	settings := protocol.LimitedDraftSettings{PacksPerPlayer: 3, PacksPerBatch: 1, CardsPerPack: 25}
	config := Config{Name: "Custom packs", Format: protocol.FormatEDH, EventType: protocol.LimitedEventCommanderCube,
		Coordinator: protocol.LimitedCoordinatorCasual, MatchMode: protocol.MatchBO1, MaxPlayers: 8,
		Product: &product, DraftSettings: &settings}
	if _, err := New("SMALL", config, "Host", "host", CredentialHash("token"), testNow); ErrorCode(err) != ErrInvalid {
		t.Fatalf("capacity stock validation failed: %v", err)
	}
	product.Sheets[0].Cards[0].Weight = required
	event, err := New("SIZED", config, "Host", "host", CredentialHash("token"), testNow)
	if err != nil {
		t.Fatal(err)
	}
	settings.CardsPerPack = 40
	publicSettings := event.DraftSettings()
	if publicSettings.CardsPerPack != 25 {
		t.Fatal("creation settings alias the request")
	}
	publicSettings.CardsPerPack = 30
	if event.DraftSettings().CardsPerPack != 25 {
		t.Fatal("public settings alias the locked rules")
	}
	for index := 0; index < 2; index++ {
		participant, err := event.Register(fmt.Sprintf("Player %d", index), fmt.Sprintf("conn-%d", index),
			CredentialHash(fmt.Sprintf("token-%d", index)), testNow)
		if err != nil {
			t.Fatal(err)
		}
		participant.CheckedIn = true
	}
	if err := event.Start(Actor{ConnectionID: "host", Role: "organizer"}, 31, testNow); err != nil {
		t.Fatal(err)
	}
	for _, player := range event.Limited.Players {
		view := event.Limited.Snapshot(player.ID)
		if view.PacksPerPlayer != 3 || view.PacksThisBatch != 1 || len(view.CurrentPack) != 25 {
			t.Fatal("starting with fewer players changed the creation-time rules")
		}
	}
}

func TestCommanderInitialTablesSplitEverySubmittedPlayerOnce(t *testing.T) {
	for _, seats := range []int{5, 6, 7, 8} {
		t.Run(fmt.Sprint(seats), func(t *testing.T) {
			event, _ := seatControlDraft(t, protocol.LimitedEventCommanderCube, protocol.LimitedCoordinatorCasual, seats)
			finishSeatControlDraft(t, event)
			for index := range event.Participants {
				submitSeatControlDeck(t, event, index)
			}
			if len(event.CasualPairings) != 2 {
				t.Fatal("expected two initial tables")
			}
			seen := map[string]bool{}
			for _, pair := range event.CasualPairings {
				if len(pair.ParticipantIDs()) < 2 || len(pair.ParticipantIDs()) > 4 || pair.Invited || !pair.InitialCubeTable {
					t.Fatal("invalid initial pod")
				}
				for _, id := range pair.ParticipantIDs() {
					if seen[id] || !pair.AutoEntryPending(id) || event.CurrentPairing(id).ID != pair.ID {
						t.Fatal("missing or duplicate reservation")
					}
					seen[id] = true
				}
			}
			if len(seen) != seats {
				t.Fatal("submitted players were omitted")
			}
			if len(event.CasualPairings[0].ParticipantIDs())-len(event.CasualPairings[1].ParticipantIDs()) > 1 {
				t.Fatal("unbalanced pods")
			}
		})
	}
}
