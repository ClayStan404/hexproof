// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

func piperLimitedDeck(differentPrinting bool) protocol.DeckSelect {
	first := protocol.DeckCard{Name: "The Prismatic Piper", Count: 1,
		SetCode: "CMR", CollectorNumber: "1", TypeLine: "Legendary Creature — Shapeshifter"}
	second := first
	if differentPrinting {
		second.SetCode = "CMM"
	}
	mainboard := []protocol.DeckCard{first, second,
		{Name: "Island", Count: 29, TypeLine: "Basic Land"},
		{Name: "Forest", Count: 29, TypeLine: "Basic Land"}}
	if !differentPrinting {
		mainboard[0].Count = 2
		mainboard = append(mainboard[:1], mainboard[2:]...)
	}
	return protocol.DeckSelect{
		Name: "Piper deck", Format: protocol.FormatEDH, DeckFormat: protocol.DeckFormatCommanderLimited,
		Commander: first.Name, Commanders: []string{first.Name, second.Name},
		CommanderPrintings: []protocol.DeckCard{first, second}, CommanderColors: []string{"U", "G"},
		Mainboard: mainboard,
		Sideboard: []protocol.DeckCard{{Name: "Private pool card", Count: 60, SetCode: "TST", CollectorNumber: "1"}},
	}
}

func TestCommanderPiperDeckInstallValidationAndClone(t *testing.T) {
	for _, differentPrinting := range []bool{false, true} {
		r := newCommanderLimitedRoom(t, 2)
		deck := piperLimitedDeck(differentPrinting)
		if _, err := r.SelectDeck("host-conn", deck); err != nil {
			t.Fatalf("same-name Commander Draft partners rejected: %v", err)
		}
		if len(r.Seats[0].Deck.Commanders) != 2 {
			t.Fatal("same-name physical commanders were deduplicated")
		}
		deck.CommanderColors[0] = "R"
		if r.Seats[0].Deck.CommanderColors[0] != "U" || r.Seats[0].RegisteredDeck.CommanderColors[0] != "U" {
			t.Fatal("installed color choice aliased supplied deck")
		}
		r.Seats[0].Deck.CommanderColors[0] = "B"
		if r.Seats[0].RegisteredDeck.CommanderColors[0] != "U" {
			t.Fatal("registered colors alias active deck")
		}
	}
	for _, test := range []struct {
		name string
		edit func(*protocol.DeckSelect)
	}{
		{"insufficient exact copies", func(deck *protocol.DeckSelect) {
			deck.Mainboard[0].Count = 1
			deck.Mainboard[1].Count++
		}},
		{"missing colors", func(deck *protocol.DeckSelect) { deck.CommanderColors = nil }},
		{"missing second color", func(deck *protocol.DeckSelect) { deck.CommanderColors = deck.CommanderColors[:1] }},
		{"invalid color", func(deck *protocol.DeckSelect) { deck.CommanderColors[0] = "C" }},
		{"wrong second printing", func(deck *protocol.DeckSelect) { deck.CommanderPrintings[1].SetCode = "BAD" }},
	} {
		t.Run(test.name, func(t *testing.T) {
			r := newCommanderLimitedRoom(t, 2)
			deck := piperLimitedDeck(false)
			test.edit(&deck)
			if _, err := r.SelectDeck("host-conn", deck); err == nil {
				t.Fatal("invalid fallback deck was installed")
			}
			if r.Seats[0].Deck != nil || r.Seats[0].RegisteredDeck != nil {
				t.Fatal("invalid deck mutated room state")
			}
		})
	}
	data, err := json.Marshal(piperLimitedDeck(false))
	if err != nil || strings.Contains(string(data), "commanderColors") {
		t.Fatalf("server-only colors leaked before game start: %s (%v)", data, err)
	}
	var forged protocol.DeckSelect
	if err := json.Unmarshal([]byte(`{"commanderPrintings":[{"name":"The Prismatic Piper","count":1}],"commanderColors":["U","G"]}`), &forged); err != nil ||
		len(forged.CommanderPrintings) != 0 || len(forged.CommanderColors) != 0 {
		t.Fatal("client supplied server-only commander identity or colors")
	}
	ordinary := piperLimitedDeck(false)
	ordinary.DeckFormat = protocol.DeckFormatCommander
	if len(deckCommanderNames(ordinary)) != 1 {
		t.Fatal("Commander Draft changed constructed duplicate-name handling")
	}
}

func TestCommanderPipersStartAsIndependentCardsWithPersistentPublicColors(t *testing.T) {
	for _, differentPrinting := range []bool{false, true} {
		r := newCommanderLimitedRoom(t, 2)
		if _, err := r.Join("guest", "Guest", false, ""); err != nil {
			t.Fatal(err)
		}
		if _, err := r.Join("observer", "Observer", true, ""); err != nil {
			t.Fatal(err)
		}
		for _, connection := range []string{"host-conn", "guest"} {
			if _, err := r.SelectDeck(connection, piperLimitedDeck(differentPrinting)); err != nil {
				t.Fatal(err)
			}
			if _, err := r.SetReady(connection, true); err != nil {
				t.Fatal(err)
			}
		}
		if r.Game == nil {
			t.Fatal("Piper pairing did not start")
		}
		state := r.Game.Seats[0]
		if len(state.CommandZone) != 2 || len(state.Hand) != 7 || len(state.Library) != 51 || len(state.Sideboard) != 60 ||
			state.CommandZone[0].ID == state.CommandZone[1].ID || len(state.CommanderTaxes) != 2 {
			t.Fatal("Pipers did not become two independent command-zone cards")
		}
		first, second := state.CommandZone[0], state.CommandZone[1]
		if first.SetCode != "CMR" || first.CollectorNumber != "1" ||
			(differentPrinting && second.SetCode != "CMM") ||
			r.Game.CommanderColors[first.ID] != "U" || r.Game.CommanderColors[second.ID] != "G" {
			t.Fatal("index-based exact printing/color assignment failed")
		}
		for _, connection := range []string{"host-conn", "guest", "observer"} {
			view, err := r.GameSnapshot(connection)
			if err != nil {
				t.Fatal(err)
			}
			if len(view.Commanders) != 4 {
				t.Fatal("duplicate-name commanders missing from public projection")
			}
			colors := map[string]string{}
			for _, identity := range view.Commanders {
				colors[identity.CardID] = identity.ChosenColor
			}
			if colors[first.ID] != "U" || colors[second.ID] != "G" {
				t.Fatal("chosen colors not public from game start")
			}
			for seat, projection := range view.Seats {
				if (connection == "observer" || (connection == "guest" && seat == 0) ||
					(connection == "host-conn" && seat == 1)) && (len(projection.Hand) != 0 || len(projection.Sideboard) != 0) {
					t.Fatal("public commander color leaked hidden card identities")
				}
			}
		}
		if _, err := r.CastCommander("host-conn", protocol.GameCastCommander{CommanderID: second.ID}); err != nil {
			t.Fatal(err)
		}
		if state.CommanderTaxes[first.ID] != 0 || state.CommanderTaxes[second.ID] != 1 {
			t.Fatal("Piper commander taxes were combined by name")
		}
		if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{CardID: second.ID,
			FromZone: protocol.ZoneStack, ToZone: protocol.ZoneBattlefield,
			Position: &protocol.CardPosition{X: .4, Y: .3}}); err != nil {
			t.Fatal(err)
		}
		if _, err := r.SetCommanderDamage("host-conn", protocol.GameSetCommanderDamage{
			CommanderID: second.ID, TargetSeat: 1, Value: intPointer(3)}); err != nil {
			t.Fatal(err)
		}
		if r.Game.CommanderDamage[second.ID][1] != 3 || len(r.Game.CommanderDamage[first.ID]) != 0 {
			t.Fatal("Piper damage totals were combined by name")
		}
		if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{CardID: second.ID,
			FromZone: protocol.ZoneBattlefield, ToZone: protocol.ZoneHand}); err != nil {
			t.Fatal(err)
		}
		view, err := r.GameSnapshot("observer")
		if err != nil {
			t.Fatal(err)
		}
		found := false
		for _, identity := range view.Commanders {
			if identity.CardID == second.ID {
				found = identity.ChosenColor == "G"
			}
		}
		if !found || len(view.Seats[0].Hand) != 0 || !reflect.DeepEqual(r.Seats[0].RegisteredDeck.CommanderColors, []string{"U", "G"}) {
			t.Fatal("hidden-zone move lost public chosen color or changed registration")
		}
	}
}
