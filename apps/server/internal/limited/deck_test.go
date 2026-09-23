// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import (
	"fmt"
	"reflect"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestDeckSubmissionPreservesPlayableTransportBounds(t *testing.T) {
	for _, test := range []struct {
		name   string
		basics []protocol.LimitedBasicLand
	}{
		{"total includes unselected pool", []protocol.LimitedBasicLand{{Name: "Island", Count: 911}}},
		{"missing collector", []protocol.LimitedBasicLand{{Name: "Island", Count: 17, SetCode: "TST"}}},
		{"missing set", []protocol.LimitedBasicLand{{Name: "Island", Count: 17, CollectorNumber: "1"}}},
		{"long set", []protocol.LimitedBasicLand{{Name: "Island", Count: 17,
			SetCode: strings.Repeat("x", protocol.MaxSetCodeRunes+1), CollectorNumber: "1"}}},
		{"long collector", []protocol.LimitedBasicLand{{Name: "Island", Count: 17,
			SetCode: "TST", CollectorNumber: strings.Repeat("x", protocol.MaxCollectorNumberRunes+1)}}},
		{"control character", []protocol.LimitedBasicLand{{Name: "Island", Count: 17,
			SetCode: "TST", CollectorNumber: "1\x00"}}},
		{"too many entries", distinctBasicPrintings(protocol.MaxDeckEntries)},
	} {
		t.Run(test.name, func(t *testing.T) {
			event, err := New(Config{
				TournamentID: "deck-bounds", EventType: protocol.LimitedEventSetSealed,
				Product: testProduct(15, 60), Participants: testParticipants(2),
			}, 7)
			if err != nil {
				t.Fatal(err)
			}
			ids := make([]string, 23)
			for index := range ids {
				ids[index] = event.Player("p-1").Pool[index].ID
			}
			request := protocol.LimitedSubmitDeck{
				Name: "Playable deck", MainboardInstanceIDs: ids,
				BasicLands: []protocol.LimitedBasicLand{{Name: "Island", Count: 17}},
			}
			if _, err := event.SubmitDeck("p-1", request); err != nil {
				t.Fatal(err)
			}
			before := event.Snapshot("p-1")
			previousDeck := event.Player("p-1").Deck
			request.BasicLands = test.basics
			if _, err := event.SubmitDeck("p-1", request); ErrorCode(err) != ErrDeckInvalid {
				t.Fatalf("unplayable deck accepted: %v", err)
			}
			if event.Player("p-1").Deck != previousDeck || !reflect.DeepEqual(before, event.Snapshot("p-1")) {
				t.Fatal("invalid replacement changed the submitted deck or private construction")
			}
		})
	}
}

func TestDeckSubmissionAcceptsCombinedCardLimit(t *testing.T) {
	event, err := New(Config{
		TournamentID: "deck-limit", EventType: protocol.LimitedEventSetSealed,
		Product: testProduct(15, 60), Participants: testParticipants(2),
	}, 7)
	if err != nil {
		t.Fatal(err)
	}
	deck, err := event.SubmitDeck("p-1", protocol.LimitedSubmitDeck{
		Name:       "At transport limit",
		BasicLands: []protocol.LimitedBasicLand{{Name: "Island", Count: protocol.MaxDeckCards - 90}},
	})
	if err != nil {
		t.Fatal(err)
	}
	if got := deckCardTotal(deck.Mainboard) + deckCardTotal(deck.Sideboard); got != protocol.MaxDeckCards {
		t.Fatalf("combined card count = %d", got)
	}
}

func distinctBasicPrintings(count int) []protocol.LimitedBasicLand {
	result := make([]protocol.LimitedBasicLand, count)
	for index := range result {
		result[index] = protocol.LimitedBasicLand{
			Name: "Island", Count: 1, SetCode: "TST", CollectorNumber: fmt.Sprint(index),
		}
	}
	return result
}

func TestPrintedVirtualBasicsStayDistinctFromPhysicalPoolCards(t *testing.T) {
	event, err := New(Config{
		TournamentID: "printed-basics", EventType: protocol.LimitedEventSetSealed,
		Product: testProduct(15, 60), Participants: testParticipants(2),
	}, 7)
	if err != nil {
		t.Fatal(err)
	}
	physical := event.Player("p-1").Pool[0]
	physical.Name, physical.SetCode, physical.CollectorNumber, physical.TypeLine = "Island", "TST", "99", "Basic Land"
	basics := []protocol.LimitedBasicLand{{Name: "Island", Count: 39, SetCode: "TST", CollectorNumber: "99"}}
	deck, err := event.SubmitDeck("p-1", protocol.LimitedSubmitDeck{
		Name: "Matching art", MainboardInstanceIDs: []string{physical.ID}, BasicLands: basics,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(deck.Mainboard) != 2 {
		t.Fatalf("physical and virtual cards were merged: %#v", deck.Mainboard)
	}
	for _, card := range deck.Mainboard {
		if card.SetCode != "TST" || card.CollectorNumber != "99" || card.Name != "Island" {
			t.Fatal("the chosen basic land printing was lost")
		}
		if card.VirtualBasic && card.Count != 39 || !card.VirtualBasic && card.Count != 1 {
			t.Fatal("virtual supply ownership was not preserved")
		}
	}
	if !reflect.DeepEqual(event.Snapshot("p-1").BasicLands, basics) {
		t.Fatal("rejoining lost the owner's basic land printing")
	}
	if len(event.Snapshot("p-2").BasicLands) != 0 {
		t.Fatal("another player received the owner's basic land choices")
	}
}
