// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import (
	"reflect"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestOrdinaryCubeDoesNotOfferOutsideStaples(t *testing.T) {
	event := autoDraftEvent(t, protocol.LimitedEventCubeDraft, 4)
	for _, player := range event.Players {
		if err := event.SetAutoDraft(player.ID, true); err != nil {
			t.Fatal(err)
		}
	}
	if len(event.Snapshot("p-1").OptionalCards) != 0 {
		t.Fatal("ordinary Cube received outside staples")
	}
	request := protocol.LimitedSubmitDeck{Name: "Forged staple", MainboardInstanceIDs: []string{"optional-forged"},
		BasicLands: []protocol.LimitedBasicLand{{Name: "Island", Count: 39}}}
	if _, err := event.SubmitDeck("p-1", request); ErrorCode(err) != ErrDeckInvalid {
		t.Fatal("outside staple accepted in ordinary Cube")
	}
}

func TestCommanderOptionalCardsArePrivateBoundedAndRestored(t *testing.T) {
	event := newCommanderCube(t, 2)
	if len(event.Snapshot("p-1").OptionalCards) != 0 {
		t.Fatal("optional cards entered drafting")
	}
	finishCommanderDraft(t, event)
	owner, other := event.Snapshot("p-1"), event.Snapshot("p-2")
	if len(owner.OptionalCards) != 3 || len(owner.Pool) != 60 || len(event.Snapshot("viewer").OptionalCards) != 0 {
		t.Fatal("optional cards changed draft counts or leaked to observers")
	}
	wantNames := []string{"Sol Ring", "Command Tower", "Arcane Signet"}
	request := commanderRequest(event, "p-1", 35)
	for i, card := range owner.OptionalCards {
		if card.Name != wantNames[i] || card.InstanceID == other.OptionalCards[i].InstanceID {
			t.Fatal("wrong owner candidate")
		}
		request.MainboardInstanceIDs = append(request.MainboardInstanceIDs, card.InstanceID)
	}
	request.BasicLands[0].Count -= 3
	deck, err := event.SubmitDeck("p-1", request)
	if err != nil {
		t.Fatal(err)
	}
	if deckCardTotal(deck.Mainboard) != 60 || deckCardTotal(deck.Sideboard) != 25 {
		t.Fatal("optional cards were double-counted or added to sideboard")
	}
	for _, candidate := range owner.OptionalCards {
		found := false
		for _, card := range deck.Mainboard {
			if card.Name == candidate.Name && card.SetCode == candidate.SetCode && card.CollectorNumber == candidate.CollectorNumber && card.Count == 1 {
				found = true
			}
		}
		if !found {
			t.Fatal("optional printing was not preserved")
		}
	}
	restored := event.Snapshot("p-1")
	if !reflect.DeepEqual(restored.MainboardInstanceIDs, request.MainboardInstanceIDs) ||
		!reflect.DeepEqual(restored.OptionalCards, owner.OptionalCards) || len(restored.Pool) != 60 {
		t.Fatal("optional selection did not restore")
	}
	for _, badID := range []string{owner.OptionalCards[0].InstanceID, other.OptionalCards[0].InstanceID, "optional-forged"} {
		bad := copyLimitedRequest(t, request)
		bad.MainboardInstanceIDs = append(bad.MainboardInstanceIDs, badID)
		before := eventStateJSON(t, event)
		if _, err := event.SubmitDeck("p-1", bad); ErrorCode(err) != ErrDeckInvalid || before != eventStateJSON(t, event) {
			t.Fatal("invalid optional card changed deck")
		}
	}
	bad := copyLimitedRequest(t, request)
	bad.CommanderInstanceIDs = []string{owner.OptionalCards[0].InstanceID}
	if _, err := event.SubmitDeck("p-1", bad); ErrorCode(err) != ErrDeckInvalid {
		t.Fatal("optional staple bypassed commander ownership")
	}
	if _, err := event.SubmitDeck("p-2", commanderRequest(event, "p-2", 35)); err != nil {
		t.Fatal(err)
	}
	if err := event.EnterCompetition(); err != nil {
		t.Fatal(err)
	}
	if _, err := event.UpdateCasualDeck("p-1", commanderRequest(event, "p-1", 35)); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(event.Snapshot("p-1").OptionalCards, owner.OptionalCards) {
		t.Fatal("free-play edit changed candidates")
	}
	for _, card := range event.Player("p-1").Deck.Sideboard {
		for _, name := range wantNames {
			if card.Name == name {
				t.Fatal("removed optional card entered the sideboard")
			}
		}
	}
}
