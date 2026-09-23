// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

func commanderLimitedDeck(commanders int) protocol.DeckSelect {
	deck := protocol.DeckSelect{
		Name: "Commander Cube deck", Format: protocol.FormatEDH,
		DeckFormat: protocol.DeckFormatCommanderLimited,
		Commander:  "Draft Captain", Commanders: []string{"Draft Captain"},
		CommanderPrintings: []protocol.DeckCard{
			{Name: "Draft Captain", Count: 1, SetCode: "NEW", CollectorNumber: "20"},
		},
		Mainboard: []protocol.DeckCard{
			{Name: "Draft Captain", Count: 1, SetCode: "OLD", CollectorNumber: "1"},
			{Name: "Draft Captain", Count: 1, SetCode: "NEW", CollectorNumber: "20"},
			{Name: "Other Captain", Count: 1, SetCode: "TST", CollectorNumber: "2"},
			{Name: "Draft Creature", Count: 20, SetCode: "TST", CollectorNumber: "3"},
			{Name: "Forest", Count: 37, TypeLine: "Basic Land"},
		},
		Sideboard: []protocol.DeckCard{
			{Name: "Private Leftover", Count: 2, SetCode: "TST", CollectorNumber: "4"},
		},
	}
	if commanders == 2 {
		deck.Commanders = append(deck.Commanders, "Other Captain")
		deck.CommanderPrintings = append(deck.CommanderPrintings, protocol.DeckCard{
			Name: "Other Captain", Count: 1, SetCode: "TST", CollectorNumber: "2",
		})
	}
	return deck
}

func newCommanderLimitedRoom(t *testing.T, seats int) *Room {
	t.Helper()
	r := newTestRoom(t, seats, true)
	r.DeckFormat = protocol.DeckFormatCommanderLimited
	r.LimitedDeckLocked = true
	r.CardLoadMode = protocol.CardLoadBackground
	r.randomIndex = func(maximum int) (int, error) { return 0, nil }
	return r
}

func TestCommanderLimitedDeckRequiresServerLockAndExactCommanders(t *testing.T) {
	for _, commanders := range []int{1, 2} {
		r := newCommanderLimitedRoom(t, 2)
		deck := commanderLimitedDeck(commanders)
		if _, err := r.SelectDeck("host-conn", deck); err != nil {
			t.Fatalf("valid %d-commander pool deck rejected: %v", commanders, err)
		}
		deck.CommanderPrintings[0].SetCode = "MUTATED"
		if r.Seats[0].Deck.CommanderPrintings[0].SetCode != "NEW" ||
			r.Seats[0].RegisteredDeck.CommanderPrintings[0].SetCode != "NEW" {
			t.Fatal("room deck installation aliased private printing selection")
		}
		r.Seats[0].Deck.CommanderPrintings[0].SetCode = "ACTIVE"
		if r.Seats[0].RegisteredDeck.CommanderPrintings[0].SetCode != "NEW" {
			t.Fatal("registered commander identity aliased active deck")
		}
	}
	for _, test := range []struct {
		name string
		edit func(*Room, *protocol.DeckSelect)
	}{
		{"unlocked", func(r *Room, deck *protocol.DeckSelect) { r.LimitedDeckLocked = false }},
		{"short", func(r *Room, deck *protocol.DeckSelect) { deck.Mainboard[4].Count-- }},
		{"no exact printings", func(r *Room, deck *protocol.DeckSelect) { deck.CommanderPrintings = nil }},
		{"foreign printing", func(r *Room, deck *protocol.DeckSelect) { deck.CommanderPrintings[0].SetCode = "BAD" }},
		{"wrong name", func(r *Room, deck *protocol.DeckSelect) { deck.CommanderPrintings[0].Name = "Other Captain" }},
		{"printing copies", func(r *Room, deck *protocol.DeckSelect) { deck.CommanderPrintings[0].Count = 2 }},
		{"virtual Wastes", func(r *Room, deck *protocol.DeckSelect) { deck.Mainboard[4].Name = "Wastes" }},
		{"partial basic printing", func(r *Room, deck *protocol.DeckSelect) { deck.Mainboard[4].SetCode = "TST" }},
		{"ordinary EDH virtual basic", func(r *Room, deck *protocol.DeckSelect) {
			r.DeckFormat = protocol.DeckFormatCommander
			deck.DeckFormat = protocol.DeckFormatCommander
		}},
	} {
		t.Run(test.name, func(t *testing.T) {
			r := newCommanderLimitedRoom(t, 2)
			deck := commanderLimitedDeck(1)
			test.edit(r, &deck)
			if _, err := r.SelectDeck("host-conn", deck); err == nil {
				t.Fatal("invalid Commander limited deck accepted")
			}
			if r.Seats[0].Deck != nil || r.Seats[0].RegisteredDeck != nil {
				t.Fatal("rejected deck mutated room")
			}
		})
	}
	data, err := json.Marshal(commanderLimitedDeck(2))
	if err != nil || strings.Contains(string(data), "commanderPrintings") {
		t.Fatalf("server-only commander refs leaked to wire: %s (%v)", data, err)
	}
	var forged protocol.DeckSelect
	if err := json.Unmarshal([]byte(`{"commanderPrintings":[{"name":"Forged","count":1}]}`), &forged); err != nil ||
		len(forged.CommanderPrintings) != 0 {
		t.Fatal("client could supply the server-only commander references")
	}
}

func TestCommanderLimitedAllInvitedSeatsStartWithPrivatePoolAndExactCommandZone(t *testing.T) {
	for _, count := range []int{2, 3, 4} {
		for _, commanders := range []int{1, 2} {
			t.Run(fmt.Sprintf("%d_players_%d_commanders", count, commanders), func(t *testing.T) {
				r := newCommanderLimitedRoom(t, count)
				connections := []string{"host-conn"}
				for seat := 1; seat < count; seat++ {
					connections = append(connections, fmt.Sprintf("guest-%d", seat))
				}
				for seat, connection := range connections {
					if seat > 0 {
						if _, err := r.Join(connection, connection, false, ""); err != nil {
							t.Fatal(err)
						}
					}
					if _, err := r.SelectDeck(connection, commanderLimitedDeck(commanders)); err != nil {
						t.Fatal(err)
					}
					if seat < count-1 {
						if _, err := r.SetReady(connection, true); err == nil {
							t.Fatal("ready accepted before every invited player joined")
						}
						if r.Game != nil || r.Phase != protocol.RoomPhaseWaiting {
							t.Fatal("Commander draft table started before every invited player joined")
						}
					}
				}
				for _, connection := range connections {
					if _, err := r.SetReady(connection, true); err != nil {
						t.Fatal(err)
					}
				}
				if r.Game == nil || r.Phase != protocol.RoomPhaseStarted || r.MatchMode != protocol.MatchBO1 {
					t.Fatal("full ready Commander table did not start BO1")
				}
				for _, state := range r.Game.Seats {
					if state.Life != 40 || len(state.Hand) != 7 || len(state.Library) != 60-commanders-7 ||
						len(state.CommandZone) != commanders || len(state.CommanderTaxes) != commanders {
						t.Fatalf("incorrect EDH setup: life=%d library=%d commanders=%d", state.Life, len(state.Library), len(state.CommandZone))
					}
					if state.CommandZone[0].SetCode != "NEW" || state.CommandZone[0].CollectorNumber != "20" ||
						!state.CommandZone[0].Commander {
						t.Fatalf("wrong same-name printing in command zone: %+v", state.CommandZone)
					}
					foundOtherPrinting := false
					for _, card := range append(append([]protocol.GameCard{}, state.Hand...), state.Library...) {
						if card.Name == "Draft Captain" && card.SetCode == "OLD" {
							foundOtherPrinting = true
							if card.Commander {
								t.Fatal("undesignated physical copy marked commander")
							}
						}
					}
					if !foundOtherPrinting {
						t.Fatal("other printing disappeared from the deck")
					}
				}
				if _, err := r.Join("observer", "Observer", true, ""); err != nil {
					t.Fatal(err)
				}
				for _, recipient := range []string{"host-conn", "guest-1", "observer"} {
					view, err := r.GameSnapshot(recipient)
					if err != nil {
						t.Fatal(err)
					}
					for seat, projection := range view.Seats {
						if len(projection.CommandZone) != commanders || projection.CommandZone[0].SetCode != "NEW" {
							t.Fatal("public command zone projection lost exact printing")
						}
						if recipient != connections[seat] && (len(projection.Hand) != 0 || len(projection.Sideboard) != 0) {
							t.Fatal("opponent or spectator received private hand/pool identities")
						}
					}
				}
			})
		}
	}
	ordinary := newTestRoom(t, 4, true)
	if ordinary.minimumPlayersToStart() != 2 {
		t.Fatal("Commander Cube changed ordinary EDH's two-player start policy")
	}
}
