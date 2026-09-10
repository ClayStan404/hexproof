// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import (
	"encoding/json"
	"reflect"
	"testing"

	"hexproof/server/internal/protocol"
)

func piperRequest(event *Event, copies int) protocol.LimitedSubmitDeck {
	request := commanderRequest(event, "p-1", 35)
	request.CommanderInstanceIDs = nil
	for index, card := range event.Snapshot("p-1").FallbackCommanders[:copies] {
		request.CommanderInstanceIDs = append(request.CommanderInstanceIDs, card.InstanceID)
		request.CommanderColors = append(request.CommanderColors, protocol.LimitedCommanderColor{
			InstanceID: card.InstanceID, Color: []string{"U", "G"}[index],
		})
	}
	request.BasicLands[0].Count -= copies
	return request
}

func copyLimitedRequest(t *testing.T, request protocol.LimitedSubmitDeck) protocol.LimitedSubmitDeck {
	t.Helper()
	data, err := json.Marshal(request)
	if err != nil {
		t.Fatal(err)
	}
	var result protocol.LimitedSubmitDeck
	if err := json.Unmarshal(data, &result); err != nil {
		t.Fatal(err)
	}
	return result
}

func TestCommanderPiperFallbackIsPrivateStableAndSeparateFromPicks(t *testing.T) {
	event := newCommanderCube(t, 2)
	if len(event.Snapshot("p-1").FallbackCommanders) != 0 {
		t.Fatal("fallback candidates appeared during drafting")
	}
	finishCommanderDraft(t, event)
	owner := event.Snapshot("p-1")
	if len(owner.FallbackCommanders) != 2 || len(owner.Pool) != 60 || owner.Participants[0].Picked != 60 {
		t.Fatal("fallback candidates changed the physical pool or pick count")
	}
	for _, recipient := range []string{"", "observer", "host-not-playing"} {
		view := event.Snapshot(recipient)
		if len(view.FallbackCommanders) != 0 || len(view.CommanderColors) != 0 {
			t.Fatalf("recipient %q received private fallback construction", recipient)
		}
	}
	other := event.Snapshot("p-2")
	for index, card := range owner.FallbackCommanders {
		if card.Name != prismaticPiperName || card.SetCode != "CMR" || card.CollectorNumber != "1" ||
			card.TypeLine != "Legendary Creature — Shapeshifter" || card.Rarity != "special" ||
			card.InstanceID == other.FallbackCommanders[index].InstanceID {
			t.Fatalf("invalid fallback identity: %+v", card)
		}
	}
	if owner.FallbackCommanders[0].InstanceID == owner.FallbackCommanders[1].InstanceID ||
		!reflect.DeepEqual(owner.FallbackCommanders, event.Snapshot("p-1").FallbackCommanders) {
		t.Fatal("fallback IDs are duplicate or unstable")
	}
	owner.FallbackCommanders[0].Name = "Mutated"
	if event.Snapshot("p-1").FallbackCommanders[0].Name != prismaticPiperName {
		t.Fatal("snapshot aliases authoritative fallback identity")
	}
}

func TestCommanderPiperDeckConstructionAndRestoration(t *testing.T) {
	for _, test := range []struct {
		name          string
		copies        int
		edit          func(*Event, *protocol.LimitedSubmitDeck)
		wantColors    []string
		wantSideboard int
	}{
		{name: "single fallback", copies: 1, wantColors: []string{"U"}, wantSideboard: 25},
		{name: "dual fallback", copies: 2, wantColors: []string{"U", "G"}, wantSideboard: 25},
		{name: "same color pair", copies: 2, edit: func(_ *Event, request *protocol.LimitedSubmitDeck) {
			request.CommanderColors[1].Color = "U"
		}, wantColors: []string{"U", "U"}, wantSideboard: 25},
		{name: "drafted partner and fallback", copies: 1, edit: func(event *Event, request *protocol.LimitedSubmitDeck) {
			request.CommanderInstanceIDs = append([]string{event.Player("p-1").Pool[0].ID}, request.CommanderInstanceIDs...)
		}, wantColors: []string{"", "U"}, wantSideboard: 25},
		{name: "drafted Piper and fallback", copies: 1, edit: func(event *Event, request *protocol.LimitedSubmitDeck) {
			card := event.Player("p-1").Pool[0]
			card.Name = prismaticPiperName
			request.CommanderInstanceIDs = append(request.CommanderInstanceIDs, card.ID)
			request.CommanderColors = append(request.CommanderColors, protocol.LimitedCommanderColor{InstanceID: card.ID, Color: "R"})
		}, wantColors: []string{"U", "R"}, wantSideboard: 25},
		{name: "two drafted same-name commanders", copies: 0, edit: func(event *Event, request *protocol.LimitedSubmitDeck) {
			pool := event.Player("p-1").Pool
			pool[1].Name = pool[0].Name
			request.CommanderInstanceIDs = []string{pool[0].ID, pool[1].ID}
		}, wantColors: []string{"", ""}, wantSideboard: 25},
		{name: "only basics plus fallback", copies: 2, edit: func(_ *Event, request *protocol.LimitedSubmitDeck) {
			request.MainboardInstanceIDs = nil
			request.BasicLands[0].Count = 58
		}, wantColors: []string{"U", "G"}, wantSideboard: 60},
	} {
		t.Run(test.name, func(t *testing.T) {
			event := newCommanderCube(t, 2)
			finishCommanderDraft(t, event)
			request := piperRequest(event, test.copies)
			if test.edit != nil {
				test.edit(event, &request)
			}
			deck, err := event.SubmitDeck("p-1", request)
			if err != nil {
				t.Fatal(err)
			}
			if deckCardTotal(deck.Mainboard) != 60 || deckCardTotal(deck.Sideboard) != test.wantSideboard ||
				!reflect.DeepEqual(deck.CommanderColors, test.wantColors) ||
				len(deck.CommanderPrintings) != len(request.CommanderInstanceIDs) {
				t.Fatalf("wrong derived deck partition or colors: %+v", deck)
			}
			view := event.Snapshot("p-1")
			if !reflect.DeepEqual(view.CommanderColors, request.CommanderColors) ||
				!reflect.DeepEqual(view.CommanderInstanceIDs, request.CommanderInstanceIDs) ||
				!reflect.DeepEqual(view.MainboardInstanceIDs, request.MainboardInstanceIDs) || len(view.Pool) != 60 {
				t.Fatal("construction snapshot did not restore exact physical and fallback selection")
			}
			for _, recipient := range []string{"p-2", "observer"} {
				if len(event.Snapshot(recipient).CommanderColors) != 0 {
					t.Fatal("Piper color leaked to other participant or observer")
				}
			}
			if len(request.CommanderColors) > 0 {
				request.CommanderColors[0].Color = "B"
				view.CommanderColors[0].Color = "R"
				if event.Player("p-1").CommanderColors[0].Color != "U" {
					t.Fatal("stored color aliases request or snapshot")
				}
			}
			if _, err := event.SubmitDeck("p-2", commanderRequest(event, "p-2", 35)); err != nil {
				t.Fatal(err)
			}
			if err := event.EnterCompetition(); err != nil {
				t.Fatal(err)
			}
			before := event.Snapshot("p-1").FallbackCommanders
			if _, err := event.UpdateCasualDeck("p-1", piperRequest(event, 2)); err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(before, event.Snapshot("p-1").FallbackCommanders) ||
				deckCardTotal(event.Player("p-1").Deck.Mainboard) != 60 {
				t.Fatal("free-play edit changed fallback IDs or double-counted fallback copies")
			}
		})
	}
}

func TestCommanderPiperInvalidSubmissionsAreAtomic(t *testing.T) {
	event := newCommanderCube(t, 2)
	finishCommanderDraft(t, event)
	request := piperRequest(event, 2)
	if _, err := event.SubmitDeck("p-1", request); err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct {
		name string
		edit func(*protocol.LimitedSubmitDeck)
	}{
		{"missing colors", func(r *protocol.LimitedSubmitDeck) { r.CommanderColors = nil }},
		{"missing second color", func(r *protocol.LimitedSubmitDeck) { r.CommanderColors = r.CommanderColors[:1] }},
		{"colorless", func(r *protocol.LimitedSubmitDeck) { r.CommanderColors[0].Color = "C" }},
		{"multicolor", func(r *protocol.LimitedSubmitDeck) { r.CommanderColors[0].Color = "UG" }},
		{"duplicate color record", func(r *protocol.LimitedSubmitDeck) {
			r.CommanderColors = append(r.CommanderColors, r.CommanderColors[0])
		}},
		{"unselected color", func(r *protocol.LimitedSubmitDeck) { r.CommanderColors[0].InstanceID = "unknown" }},
		{"non-Piper color", func(r *protocol.LimitedSubmitDeck) {
			r.CommanderInstanceIDs[0] = r.MainboardInstanceIDs[0]
			r.CommanderColors[0].InstanceID = r.MainboardInstanceIDs[0]
		}},
		{"foreign fallback", func(r *protocol.LimitedSubmitDeck) {
			r.CommanderInstanceIDs[0] = event.Snapshot("p-2").FallbackCommanders[0].InstanceID
			r.CommanderColors[0].InstanceID = r.CommanderInstanceIDs[0]
		}},
		{"forged fallback", func(r *protocol.LimitedSubmitDeck) {
			r.CommanderInstanceIDs[0] = "piper-forged"
			r.CommanderColors[0].InstanceID = r.CommanderInstanceIDs[0]
		}},
		{"duplicate fallback", func(r *protocol.LimitedSubmitDeck) { r.CommanderInstanceIDs[1] = r.CommanderInstanceIDs[0] }},
		{"fallback in physical main deck", func(r *protocol.LimitedSubmitDeck) {
			r.MainboardInstanceIDs = append(r.MainboardInstanceIDs, r.CommanderInstanceIDs[0])
		}},
		{"short deck", func(r *protocol.LimitedSubmitDeck) { r.BasicLands[0].Count-- }},
	} {
		t.Run(test.name, func(t *testing.T) {
			bad := copyLimitedRequest(t, request)
			test.edit(&bad)
			before := eventStateJSON(t, event)
			if _, err := event.SubmitDeck("p-1", bad); ErrorCode(err) != ErrDeckInvalid {
				t.Fatalf("invalid submission returned %v", err)
			}
			if eventStateJSON(t, event) != before {
				t.Fatal("invalid Piper request changed construction")
			}
		})
	}
	// A drafted Piper requires a choice just like an external fallback.
	pool := event.Player("p-1").Pool
	pool[0].Name = prismaticPiperName
	if _, err := event.SubmitDeck("p-1", commanderRequest(event, "p-1", 35)); ErrorCode(err) != ErrDeckInvalid {
		t.Fatalf("drafted Piper without a chosen color: %v", err)
	}
	// Selected fallback copies participate in the aggregate transport bound.
	for len(event.Player("p-1").Pool) < protocol.MaxDeckCards-request.BasicLands[0].Count {
		index := len(event.Player("p-1").Pool)
		event.Player("p-1").Pool = append(event.Player("p-1").Pool,
			&CardInstance{ID: "extra-" + itoa(index), Name: "Extra", SetCode: "TST", CollectorNumber: "1"})
	}
	if _, err := event.SubmitDeck("p-1", request); ErrorCode(err) != ErrDeckInvalid {
		t.Fatalf("fallback copies were not counted against the transport limit: %v", err)
	}
}

func TestOrdinaryLimitedRejectsPiperColorAndFallbackInjection(t *testing.T) {
	event, err := New(Config{EventType: protocol.LimitedEventSetSealed,
		Product: testProduct(15, 60), Participants: testParticipants(2)}, 7)
	if err != nil {
		t.Fatal(err)
	}
	if len(event.Snapshot("p-1").FallbackCommanders) != 0 {
		t.Fatal("ordinary Limited received fallback candidates")
	}
	request := commanderRequest(event, "p-1", 35)
	request.CommanderInstanceIDs = nil
	request.CommanderColors = []protocol.LimitedCommanderColor{{InstanceID: request.MainboardInstanceIDs[0], Color: "W"}}
	if _, err := event.SubmitDeck("p-1", request); ErrorCode(err) != ErrDeckInvalid {
		t.Fatalf("ordinary Limited accepted a commander color: %v", err)
	}
}
