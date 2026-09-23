// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import (
	"encoding/json"
	"fmt"
	"reflect"
	"testing"

	"hexproof/server/internal/protocol"
)

func commanderCubeProduct(count int) protocol.LimitedProductDefinition {
	product := testProduct(1, count)
	product.ID = "commander-cube"
	product.ProductType = ProductTypeCube
	product.Authentic = false
	product.CardsPerPack = 0
	product.Variants = nil
	return product
}

func newCommanderCube(t *testing.T, players int) *Event {
	t.Helper()
	event, err := New(Config{
		TournamentID: "commander-pod", EventType: protocol.LimitedEventCommanderCube,
		Product:       commanderCubeProduct(players * 60),
		Participants:  testParticipants(players),
		DraftSettings: &protocol.LimitedDraftSettings{PacksPerPlayer: 3, PacksPerBatch: 1},
	}, 73)
	if err != nil {
		t.Fatalf("New Commander Cube: %v", err)
	}
	return event
}

func finishCommanderDraft(t *testing.T, event *Event) {
	t.Helper()
	for iteration := 0; event.Stage == protocol.LimitedStageDraft && iteration < 100; iteration++ {
		progress := false
		for _, player := range event.Players {
			if len(player.Inbox) == 0 {
				continue
			}
			pack := player.Inbox[0]
			if len(pack.Cards) < 2 {
				t.Fatal("terminal Commander pick was not drained")
			}
			if _, err := event.PickCards(player.ID, []string{pack.Cards[0].ID, pack.Cards[1].ID}); err != nil {
				t.Fatalf("PickCards: %v", err)
			}
			progress = true
		}
		if !progress && event.Stage == protocol.LimitedStageDraft {
			t.Fatal("Commander draft stalled")
		}
	}
	if event.Stage != protocol.LimitedStageDeckBuilding || event.packRound != 3 {
		t.Fatalf("draft not complete: stage=%s round=%d", event.Stage, event.packRound)
	}
}

func TestCommanderCubePhysicalStockAndProfile(t *testing.T) {
	for _, count := range []int{2, 3, 4} {
		t.Run(fmt.Sprintf("%d_players", count), func(t *testing.T) {
			event := newCommanderCube(t, count)
			snapshot := event.Snapshot("p-1")
			if snapshot.PicksRequired != 2 || snapshot.PacksPerPlayer != 3 ||
				snapshot.MinimumDeckCards != 60 || len(snapshot.CurrentPack) != 20 {
				t.Fatalf("Commander profile = %+v", snapshot)
			}
			finishCommanderDraft(t, event)
			seen := map[string]bool{}
			for _, player := range event.Players {
				if len(player.Pool) != 60 || len(player.Inbox) != 0 {
					t.Fatalf("%s pool=%d inbox=%d", player.ID, len(player.Pool), len(player.Inbox))
				}
				for _, card := range player.Pool {
					if seen[card.ID] {
						t.Fatal("a physical card was drafted twice")
					}
					seen[card.ID] = true
				}
			}
			if len(seen) != count*60 || len(event.cubeStock) != 0 {
				t.Fatalf("stock not conserved: picked=%d stock=%d", len(seen), len(event.cubeStock))
			}
		})
	}
	for _, count := range []int{1, 9} {
		if _, err := New(Config{EventType: protocol.LimitedEventCommanderCube,
			Product: commanderCubeProduct(count * 60), Participants: testParticipants(count)}, 1); err == nil {
			t.Fatalf("accepted %d Commander draft seats", count)
		}
	}
	if _, err := New(Config{EventType: protocol.LimitedEventCommanderCube,
		Product: commanderCubeProduct(119), Participants: testParticipants(2)}, 1); err == nil {
		t.Fatal("accepted ordinary-Cube-sized stock for Commander Cube")
	}
}

func eventStateJSON(t *testing.T, event *Event) string {
	t.Helper()
	data, err := json.Marshal(event)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestCommanderCubePicksAreAtomicAndPassOnce(t *testing.T) {
	event := newCommanderCube(t, 4)
	player := event.Players[0]
	pack := player.Inbox[0]
	ids := []string{pack.Cards[0].ID, pack.Cards[1].ID}
	foreign := event.Players[1].Inbox[0].Cards[0].ID
	for _, invalid := range [][]string{nil, {ids[0]}, {ids[0], ids[0]}, {ids[0], foreign},
		{ids[0], "missing"}, {ids[0], ids[1], pack.Cards[2].ID}} {
		before := eventStateJSON(t, event)
		if _, err := event.PickCards(player.ID, invalid); err == nil {
			t.Fatalf("accepted invalid pick %v", invalid)
		}
		if eventStateJSON(t, event) != before {
			t.Fatalf("invalid pick %v mutated event", invalid)
		}
	}
	before := eventStateJSON(t, event)
	if _, err := event.PickCards("viewer", ids); ErrorCode(err) != ErrForbidden || eventStateJSON(t, event) != before {
		t.Fatal("viewer pick changed state or did not fail authorization")
	}
	if _, err := event.Pick(player.ID, ids[0]); err == nil {
		t.Fatal("single-pick wrapper bypassed two-card profile")
	}
	if _, err := event.PickCards(player.ID, ids); err != nil {
		t.Fatal(err)
	}
	if len(player.Pool) != 2 || len(player.Inbox) != 0 || len(event.Players[1].Inbox) != 2 ||
		event.Players[1].Inbox[1] != pack || len(pack.Cards) != 18 {
		t.Fatal("two-card selection did not pass one 18-card pack once")
	}
	before = eventStateJSON(t, event)
	if _, err := event.PickCards(player.ID, ids); err == nil || eventStateJSON(t, event) != before {
		t.Fatal("duplicate command consumed another pack")
	}
	// Terminal selections remain visible until the owner confirms, including
	// an odd lone card in a two-card profile.
	for _, remaining := range []int{1, 2} {
		last := newCommanderCube(t, 2)
		owner := last.Players[0]
		owner.Inbox[0].Cards = owner.Inbox[0].Cards[:remaining]
		if err := last.advanceDraft(); err != nil || len(owner.Pool) != 0 || len(owner.Inbox) != 1 {
			t.Fatalf("terminal %d-card pack skipped owner confirmation: %v", remaining, err)
		}
		projection := last.Snapshot(owner.ID)
		if len(projection.CurrentPack) != remaining || projection.PicksRequired != remaining {
			t.Fatalf("terminal %d-card pack was not projected with its actual quota", remaining)
		}
		ids := make([]string, remaining)
		for i, card := range projection.CurrentPack {
			ids[i] = card.InstanceID
		}
		if _, err := last.PickCards(owner.ID, ids); err != nil || len(owner.Pool) != remaining || len(owner.Inbox) != 0 {
			t.Fatalf("terminal %d-card confirmation failed: %v", remaining, err)
		}
	}
}

func commanderRequest(event *Event, participant string, count int) protocol.LimitedSubmitDeck {
	player := event.Player(participant)
	ids := make([]string, count)
	for index := range ids {
		ids[index] = player.Pool[index].ID
	}
	return protocol.LimitedSubmitDeck{
		Name: "Commander draft deck", MainboardInstanceIDs: ids,
		CommanderInstanceIDs: []string{ids[0]},
		BasicLands:           []protocol.LimitedBasicLand{{Name: "Forest", Count: 60 - count}},
	}
}

func TestCommanderCubeSubmissionAndPrivateRestoration(t *testing.T) {
	event := newCommanderCube(t, 2)
	finishCommanderDraft(t, event)
	// Two physical copies of a name are legal; select the second printing as
	// commander and leave the first one in the 60-card main deck.
	pool := event.Player("p-1").Pool
	pool[1].Name = pool[0].Name
	request := commanderRequest(event, "p-1", 35)
	request.CommanderInstanceIDs = []string{pool[1].ID, pool[2].ID}
	deck, err := event.SubmitDeck("p-1", request)
	if err != nil {
		t.Fatal(err)
	}
	if deck.Format != protocol.FormatEDH || deck.DeckFormat != protocol.DeckFormatCommanderLimited ||
		deckCardTotal(deck.Mainboard) != 60 || deckCardTotal(deck.Sideboard) != 25 ||
		len(deck.Commanders) != 2 || deck.CommanderPrintings[0].CollectorNumber != pool[1].CollectorNumber {
		t.Fatalf("Commander deck installation lost selected printing or counts: %+v", deck)
	}
	owner := event.Snapshot("p-1")
	if !reflect.DeepEqual(owner.CommanderInstanceIDs, request.CommanderInstanceIDs) || !owner.DeckSubmitted {
		t.Fatal("owner snapshot lost submitted commanders")
	}
	owner.CommanderInstanceIDs[0] = "mutated"
	if event.Player("p-1").CommanderInstanceIDs[0] != pool[1].ID {
		t.Fatal("snapshot aliased retained commander selection")
	}
	for _, recipient := range []string{"", "viewer", "p-2"} {
		view := event.Snapshot(recipient)
		if len(view.CommanderInstanceIDs) != 0 || len(view.MainboardInstanceIDs) != 0 || view.DeckSubmitted {
			t.Fatalf("recipient %q received another player's construction", recipient)
		}
	}
	for _, invalid := range [][]string{nil, {pool[0].ID, pool[0].ID},
		{pool[0].ID, pool[2].ID, pool[3].ID}, {pool[35].ID}, {event.Players[1].Pool[0].ID}} {
		bad := request
		bad.CommanderInstanceIDs = invalid
		before := eventStateJSON(t, event)
		if _, err := event.SubmitDeck("p-1", bad); ErrorCode(err) != ErrDeckInvalid {
			t.Fatalf("invalid commanders %v error=%v", invalid, err)
		}
		if eventStateJSON(t, event) != before {
			t.Fatal("invalid submission replaced the prior deck")
		}
	}
	short := commanderRequest(event, "p-1", 35)
	short.BasicLands[0].Count--
	if _, err := event.SubmitDeck("p-1", short); err == nil {
		t.Fatal("accepted 59 cards including commander")
	}
	if _, err := event.SubmitDeck("p-2", commanderRequest(event, "p-2", 35)); err != nil {
		t.Fatal(err)
	}
	if err := event.EnterCompetition(); err != nil {
		t.Fatal(err)
	}
	request.CommanderInstanceIDs = []string{pool[0].ID}
	if _, err := event.UpdateCasualDeck("p-1", request); err != nil {
		t.Fatalf("free-play deck edit: %v", err)
	}
	if event.Player("p-1").Deck.CommanderPrintings[0].CollectorNumber != pool[0].CollectorNumber ||
		len(event.Player("p-1").CommanderInstanceIDs) != 1 {
		t.Fatal("free-play edit did not replace commander identity")
	}
}

func TestOrdinaryLimitedRejectsCommanderDesignation(t *testing.T) {
	event, err := New(Config{EventType: protocol.LimitedEventSetSealed,
		Product: testProduct(15, 60), Participants: testParticipants(2)}, 7)
	if err != nil {
		t.Fatal(err)
	}
	request := commanderRequest(event, "p-1", 35)
	if _, err := event.SubmitDeck("p-1", request); ErrorCode(err) != ErrDeckInvalid {
		t.Fatalf("ordinary sealed commander error=%v", err)
	}
}
