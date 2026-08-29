// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"testing"

	"hexproof/server/internal/protocol"
)

func TestLimitedDeckSelectionAcceptsOnlyVirtualOrdinaryBasics(t *testing.T) {
	newLimitedRoom := func() *Room {
		r, err := New("LIMIT1", "Limited pairing", protocol.FormatModern,
			protocol.MatchBO3, protocol.CardLoadBackground, 2, false, false,
			"Alice", "alice-conn", testNow)
		if err != nil {
			t.Fatalf("New: %v", err)
		}
		r.DeckFormat = protocol.DeckFormatLimited
		return r
	}
	deck := protocol.DeckSelect{
		Name: "Sealed deck", Format: protocol.FormatModern,
		DeckFormat: protocol.DeckFormatLimited,
		Mainboard: []protocol.DeckCard{
			{Name: "Pool card", Count: 23, SetCode: "TST", CollectorNumber: "1"},
			{Name: "Island", Count: 17, TypeLine: "Basic Land"},
		},
	}
	if _, err := newLimitedRoom().SelectDeck("alice-conn", deck); err != nil {
		t.Fatalf("SelectDeck with virtual basic lands: %v", err)
	}

	missingPrinting := deck
	missingPrinting.Mainboard = append([]protocol.DeckCard(nil), deck.Mainboard...)
	missingPrinting.Mainboard[1] = protocol.DeckCard{
		Name: "Wastes", Count: 17, TypeLine: "Basic Land",
	}
	if _, err := newLimitedRoom().SelectDeck("alice-conn", missingPrinting); err == nil {
		t.Fatal("SelectDeck accepted a virtual non-ordinary basic land")
	} else if code, ok := ErrorCode(err); !ok || code != protocol.ErrInvalidDeck {
		t.Fatalf("virtual non-ordinary basic error = %v (%q, %t)", err, code, ok)
	}

	partialPrinting := deck
	partialPrinting.Mainboard = append([]protocol.DeckCard(nil), deck.Mainboard...)
	partialPrinting.Mainboard[1].SetCode = "FDN"
	if _, err := newLimitedRoom().SelectDeck("alice-conn", partialPrinting); err == nil {
		t.Fatal("SelectDeck accepted a partial basic-land printing identity")
	} else if code, ok := ErrorCode(err); !ok || code != protocol.ErrInvalidDeck {
		t.Fatalf("partial basic printing error = %v (%q, %t)", err, code, ok)
	}
}
