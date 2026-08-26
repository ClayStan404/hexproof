// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"fmt"
	"testing"

	"hexproof/server/internal/protocol"
)

func FuzzGameMoveSequencePreservesCards(f *testing.F) {
	f.Add([]byte{0, 1, 2, 3, 4, 5, 6, 7, 8})
	f.Add([]byte{1, 1, 2, 4, 5, 0, 6, 2, 3})
	f.Add([]byte{})

	f.Fuzz(func(t *testing.T, operations []byte) {
		if len(operations) > 256 {
			t.Skip()
		}
		r := newFuzzPlaytestRoom(t)
		baseline := assertUniqueGameCards(t, r.Game)
		for _, operation := range operations {
			applyFuzzGameOperation(r, operation)
			if got := assertUniqueGameCards(t, r.Game); got != baseline {
				t.Fatalf("card count changed after operation %d: got %d, want %d",
					operation, got, baseline)
			}
		}
	})
}

func newFuzzPlaytestRoom(t *testing.T) *Room {
	t.Helper()
	r, err := New("FUZZ01", "Fuzz playtest", protocol.FormatModern,
		protocol.MatchBO1, protocol.CardLoadPreload, 1, false, false,
		"Host", "host-conn", testNow)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	r.randomIndex = func(int) (int, error) { return 0, nil }
	deck := protocol.DeckSelect{
		Name:       "Fuzz deck",
		Format:     protocol.FormatModern,
		DeckFormat: protocol.DeckFormatCustom,
		Mainboard: []protocol.DeckCard{
			{Name: "Alpha", Count: 10, SetCode: "LEA", CollectorNumber: "1"},
			{Name: "Beta", Count: 10, SetCode: "LEB", CollectorNumber: "2"},
		},
		Sideboard: []protocol.DeckCard{},
	}
	if _, err := r.SelectDeck("host-conn", deck); err != nil {
		t.Fatalf("SelectDeck: %v", err)
	}
	if _, err := r.SetReady("host-conn", true); err != nil {
		t.Fatalf("SetReady: %v", err)
	}
	if _, err := r.CompleteLoad("host-conn", r.LoadID); err != nil {
		t.Fatalf("CompleteLoad: %v", err)
	}
	if r.Game == nil {
		t.Fatal("game was not created")
	}
	return r
}

func applyFuzzGameOperation(r *Room, operation byte) {
	seat := &r.Game.Seats[0]
	position := &protocol.CardPosition{X: 0.5, Y: 0.5}
	switch operation % 9 {
	case 0:
		_, _ = r.Draw("host-conn", 1)
	case 1:
		if cardID, ok := firstCardID(seat.Hand); ok {
			_, _ = r.MoveCard("host-conn", protocol.GameMoveCard{
				CardID: cardID, FromZone: protocol.ZoneHand,
				ToZone: protocol.ZoneBattlefield, Position: position,
			})
		}
	case 2:
		if cardID, ok := firstCardID(seat.Battlefield); ok {
			_, _ = r.MoveCard("host-conn", protocol.GameMoveCard{
				CardID: cardID, FromZone: protocol.ZoneBattlefield,
				ToZone: protocol.ZoneGraveyard,
			})
		}
	case 3:
		if cardID, ok := firstCardID(seat.Graveyard); ok {
			_, _ = r.MoveCard("host-conn", protocol.GameMoveCard{
				CardID: cardID, FromZone: protocol.ZoneGraveyard,
				ToZone: protocol.ZoneHand,
			})
		}
	case 4:
		if cardID, ok := firstCardID(seat.Hand); ok {
			_, _ = r.MoveCard("host-conn", protocol.GameMoveCard{
				CardID: cardID, FromZone: protocol.ZoneHand,
				ToZone: protocol.ZoneExile,
			})
		}
	case 5:
		if cardID, ok := firstCardID(seat.Exile); ok {
			_, _ = r.MoveCard("host-conn", protocol.GameMoveCard{
				CardID: cardID, FromZone: protocol.ZoneExile,
				ToZone:           protocol.ZoneLibrary,
				LibraryPlacement: protocol.LibraryPlacementBottom,
			})
		}
	case 6:
		_, _ = r.MoveCard("host-conn", protocol.GameMoveCard{
			FromZone: protocol.ZoneLibrary, ToZone: protocol.ZoneBattlefield,
			Position: position,
		})
	case 7:
		if cardID, ok := firstCardID(seat.Battlefield); ok {
			_, _ = r.MoveCard("host-conn", protocol.GameMoveCard{
				CardID: cardID, FromZone: protocol.ZoneBattlefield,
				ToZone: protocol.ZoneHand,
			})
		}
	case 8:
		_, _ = r.ShuffleLibrary("host-conn")
	}
}

func firstCardID(cards []protocol.GameCard) (string, bool) {
	if len(cards) == 0 {
		return "", false
	}
	return cards[0].ID, true
}

func assertUniqueGameCards(t *testing.T, game *GameState) int {
	t.Helper()
	seen := map[string]string{}
	count := 0
	add := func(card protocol.GameCard, location string) {
		t.Helper()
		if card.ID == "" {
			t.Fatalf("card in %s has empty id", location)
		}
		if previous, exists := seen[card.ID]; exists {
			t.Fatalf("card %s appears in both %s and %s", card.ID, previous, location)
		}
		if card.OwnerSeat < 0 || card.OwnerSeat >= len(game.Seats) {
			t.Fatalf("card %s in %s has invalid owner %d", card.ID, location, card.OwnerSeat)
		}
		seen[card.ID] = location
		count++
	}
	for seatIndex, seat := range game.Seats {
		zones := []struct {
			name  string
			cards []protocol.GameCard
		}{
			{"library", seat.Library}, {"hand", seat.Hand},
			{"sideboard", seat.Sideboard}, {"battlefield", seat.Battlefield},
			{"graveyard", seat.Graveyard}, {"exile", seat.Exile},
			{"command", seat.CommandZone},
		}
		for _, zone := range zones {
			for _, card := range zone.cards {
				add(card, fmt.Sprintf("seat %d %s", seatIndex, zone.name))
			}
		}
	}
	for _, card := range game.Stack {
		add(card.GameCard, "stack")
	}
	for _, card := range game.Revealed {
		add(card.GameCard, "revealed")
	}
	return count
}
