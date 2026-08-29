// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import (
	"fmt"
	"testing"

	"hexproof/server/internal/protocol"
)

func testProduct(cardsPerPack, cardCount int) protocol.LimitedProductDefinition {
	cards := make([]protocol.LimitedCardDefinition, 0, cardCount)
	for index := 0; index < cardCount; index++ {
		cards = append(cards, protocol.LimitedCardDefinition{
			Name: fmt.Sprintf("Card %d", index+1), SetCode: "TST",
			CollectorNumber: fmt.Sprintf("%d", index+1), TypeLine: "Creature — Test",
			Rarity: "common", Finish: "nonfoil", Weight: 1,
		})
	}
	return protocol.LimitedProductDefinition{
		ID: "tst-draft", Name: "Test Draft Booster", SetCode: "TST",
		ProductType: "official", Authentic: true, CardsPerPack: cardsPerPack,
		Sheets: []protocol.LimitedSheetDefinition{{
			Name: "cards", WithReplacement: false, Cards: cards,
		}},
		Variants: []protocol.LimitedPackVariantDefinition{{
			Weight: 1,
			Slots:  []protocol.LimitedSlotDefinition{{Sheet: "cards", Count: cardsPerPack}},
		}},
	}
}

func testParticipants(count int) []Participant {
	participants := make([]Participant, 0, count)
	for index := 0; index < count; index++ {
		participants = append(participants, Participant{
			ID: fmt.Sprintf("p-%d", index+1), DisplayName: fmt.Sprintf("Player %d", index+1),
		})
	}
	return participants
}

func TestSealedProjectionAndDeckSubmission(t *testing.T) {
	event, err := New(Config{
		TournamentID: "event-1", EventType: protocol.LimitedEventSetSealed,
		Product: testProduct(15, 60), Participants: testParticipants(4),
	}, 7)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	if event.Stage != protocol.LimitedStageDeckBuilding {
		t.Fatalf("stage = %q", event.Stage)
	}
	owner := event.Snapshot("p-1")
	viewer := event.Snapshot("")
	if got, want := len(owner.Pool), 90; got != want {
		t.Fatalf("owner pool = %d, want %d", got, want)
	}
	if len(viewer.Pool) != 0 || len(viewer.CurrentPack) != 0 {
		t.Fatal("viewer received a private limited pool")
	}
	ids := make([]string, 23)
	for index := range ids {
		ids[index] = owner.Pool[index].InstanceID
	}
	deck, err := event.SubmitDeck("p-1", protocol.LimitedSubmitDeck{
		Name: "Sealed deck", MainboardInstanceIDs: ids,
		BasicLands: []protocol.LimitedBasicLand{{Name: "Island", Count: 17}},
	})
	if err != nil {
		t.Fatalf("SubmitDeck: %v", err)
	}
	if got := deckCardTotal(deck.Mainboard); got != 40 {
		t.Fatalf("main deck = %d, want 40", got)
	}
	if got := deckCardTotal(deck.Sideboard); got != 67 {
		t.Fatalf("sideboard = %d, want 67", got)
	}
	restored := event.Snapshot("p-1")
	if got, want := len(restored.MainboardInstanceIDs), 23; got != want {
		t.Fatalf("restored main deck instances = %d, want %d", got, want)
	}
	if got, want := len(restored.BasicLands), 1; got != want {
		t.Fatalf("restored basic lands = %d, want %d", got, want)
	}
	redacted := event.Snapshot("p-2")
	if len(redacted.MainboardInstanceIDs) != 0 || len(redacted.BasicLands) != 0 {
		t.Fatal("another participant received private deck-construction state")
	}
}

func TestDraftPassesPacksAndAlternatesDirection(t *testing.T) {
	event, err := New(Config{
		TournamentID: "event-2", EventType: protocol.LimitedEventSetDraft,
		Product: testProduct(3, 20), Participants: testParticipants(8),
	}, 11)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	if event.Direction() != 1 {
		t.Fatalf("first pack direction = %d", event.Direction())
	}
	sawSecondRound := false
	sawThirdRound := false
	for steps := 0; event.Stage == protocol.LimitedStageDraft && steps < 100; steps++ {
		if event.packRound == 2 {
			sawSecondRound = true
			if event.Direction() != -1 {
				t.Fatalf("second pack direction = %d", event.Direction())
			}
		}
		if event.packRound == 3 {
			sawThirdRound = true
			if event.Direction() != 1 {
				t.Fatalf("third pack direction = %d", event.Direction())
			}
		}
		picked := false
		for _, player := range event.Players {
			if len(player.Inbox) == 0 || len(player.Inbox[0].Cards) == 0 {
				continue
			}
			if _, err := event.Pick(player.ID, player.Inbox[0].Cards[0].ID); err != nil {
				t.Fatalf("Pick(%s): %v", player.ID, err)
			}
			picked = true
		}
		if !picked && event.Stage == protocol.LimitedStageDraft {
			t.Fatal("draft stalled with no available pack")
		}
	}
	if !sawSecondRound || !sawThirdRound || event.Stage != protocol.LimitedStageDeckBuilding {
		t.Fatalf("draft did not complete three rounds: round=%d stage=%q", event.packRound, event.Stage)
	}
	for _, player := range event.Players {
		if got, want := len(player.Pool), 9; got != want {
			t.Fatalf("%s pool = %d, want %d", player.ID, got, want)
		}
	}
}

func TestCubeDraftsPhysicalCardsWithoutReplacement(t *testing.T) {
	for playerCount := MinCubeDraftPlayers; playerCount <= MaxCubeDraftPlayers; playerCount++ {
		t.Run(fmt.Sprintf("%d_players", playerCount), func(t *testing.T) {
			product := testProduct(1, CubeDraftCardsRequired(playerCount))
			product.ID = "cube-1"
			product.Name = "Test Cube"
			product.ProductType = ProductTypeCube
			product.Authentic = false
			product.CardsPerPack = 0
			product.Variants = nil
			event, err := New(Config{
				TournamentID: "event-3", EventType: protocol.LimitedEventCubeDraft,
				Product: product, Participants: testParticipants(playerCount),
			}, 19)
			if err != nil {
				t.Fatalf("New: %v", err)
			}
			for steps := 0; event.Stage == protocol.LimitedStageDraft && steps < 100; steps++ {
				picked := false
				for _, player := range event.Players {
					if len(player.Inbox) == 0 {
						continue
					}
					if _, err := event.Pick(player.ID, player.Inbox[0].Cards[0].ID); err != nil {
						t.Fatalf("Pick(%s): %v", player.ID, err)
					}
					picked = true
				}
				if !picked && event.Stage == protocol.LimitedStageDraft {
					t.Fatal("Cube draft stalled with no available pack")
				}
			}
			if event.Stage != protocol.LimitedStageDeckBuilding {
				t.Fatalf("Cube draft stage = %q", event.Stage)
			}
			seen := map[string]bool{}
			for _, player := range event.Players {
				if got, want := len(player.Pool), 45; got != want {
					t.Fatalf("%s pool = %d, want %d", player.ID, got, want)
				}
				for _, card := range player.Pool {
					key := card.SetCode + "/" + card.CollectorNumber
					if seen[key] {
						t.Fatalf("Cube card %s was dealt twice", key)
					}
					seen[key] = true
				}
			}
		})
	}
}

func TestLimitedModeInvariants(t *testing.T) {
	product := testProduct(3, 20)
	if _, err := New(Config{
		TournamentID: "bad-draft", EventType: protocol.LimitedEventSetDraft,
		Product: product, Participants: testParticipants(7),
	}, 1); ErrorCode(err) != ErrInvalid {
		t.Fatalf("seven-seat draft error = %v", err)
	}
	cube := testProduct(1, 359)
	cube.ProductType = ProductTypeCube
	cube.Authentic = false
	cube.CardsPerPack = 0
	cube.Variants = nil
	if _, err := New(Config{
		TournamentID: "small-cube-draft", EventType: protocol.LimitedEventCubeDraft,
		Product: cube, Participants: testParticipants(8),
	}, 1); ErrorCode(err) != ErrInvalid {
		t.Fatalf("small Cube draft error = %v", err)
	}
	cube = testProduct(1, 180)
	cube.ProductType = ProductTypeCube
	cube.Authentic = false
	cube.CardsPerPack = 0
	cube.Variants = nil
	for _, players := range []int{3, 9} {
		if _, err := New(Config{
			TournamentID: "bad-cube-seats", EventType: protocol.LimitedEventCubeDraft,
			Product: cube, Participants: testParticipants(players),
		}, 1); ErrorCode(err) != ErrInvalid {
			t.Fatalf("%d-seat Cube draft error = %v", players, err)
		}
	}
}

func TestProductRejectsUnboundedWeights(t *testing.T) {
	product := testProduct(1, 1)
	product.Variants[0].Weight = maxProductWeight + 1
	if _, err := NewProduct(product); ErrorCode(err) != ErrInvalid {
		t.Fatalf("oversized variant weight error = %v", err)
	}

	product = testProduct(1, 1)
	product.ProductType = ProductTypeCube
	product.Variants = nil
	product.Sheets[0].Cards[0].Weight = maxCubePhysicalCards + 1
	if _, err := NewProduct(product); ErrorCode(err) != ErrInvalid {
		t.Fatalf("oversized Cube error = %v", err)
	}

	product = testProduct(1, 1)
	product.ProductType = "organizer-claims-exact"
	if _, err := NewProduct(product); ErrorCode(err) != ErrInvalid {
		t.Fatalf("unknown product type error = %v", err)
	}
}

func deckCardTotal(cards []protocol.DeckCard) int {
	total := 0
	for _, card := range cards {
		total += card.Count
	}
	return total
}
