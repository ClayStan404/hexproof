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

func TestLimitedSideboardSupportsUnlimitedOrdinaryBasics(t *testing.T) {
	r := newTestRoom(t, 2, false)
	r.Format = protocol.FormatModern
	r.DeckFormat = protocol.DeckFormatLimited
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Sideboard: &SideboardState{Players: []SideboardPlayerState{
			{
				Mainboard: []protocol.DeckCard{
					{Name: "Pool card", Count: 23, SetCode: "TST", CollectorNumber: "1"},
					{Name: "Island", Count: 17, TypeLine: "Basic Land"},
				},
				Sideboard: []protocol.DeckCard{
					{Name: "Island", Count: 1, SetCode: "TST", CollectorNumber: "2",
						TypeLine: "Basic Land — Island"},
				},
			},
		}},
	}

	if _, err := r.MoveSideboard("host-conn", protocol.SideboardMove{
		Name: "island", FromZone: protocol.SideboardZoneMain,
		ToZone: protocol.SideboardZoneBasicLands,
	}); err != nil {
		t.Fatalf("remove virtual Island: %v", err)
	}
	player := &r.Game.Sideboard.Players[0]
	if got := player.Mainboard[1].Count; got != 16 {
		t.Fatalf("virtual Island count = %d, want 16", got)
	}
	if got := player.Sideboard[0]; got.SetCode != "TST" || got.Count != 1 {
		t.Fatalf("physical pool Island changed = %+v", got)
	}

	if _, err := r.MoveSideboard("host-conn", protocol.SideboardMove{
		Name: "Plains", FromZone: protocol.SideboardZoneBasicLands,
		ToZone: protocol.SideboardZoneMain,
	}); err != nil {
		t.Fatalf("add virtual Plains: %v", err)
	}
	last := player.Mainboard[len(player.Mainboard)-1]
	if last.Name != "Plains" || last.Count != 1 || last.SetCode != "" ||
		last.CollectorNumber != "" || last.TypeLine != "Basic Land" {
		t.Fatalf("added virtual Plains = %+v", last)
	}

	if _, err := r.MoveSideboard("host-conn", protocol.SideboardMove{
		Name: "Wastes", FromZone: protocol.SideboardZoneBasicLands,
		ToZone: protocol.SideboardZoneMain,
	}); err == nil {
		t.Fatal("added virtual Wastes")
	} else if code, ok := ErrorCode(err); !ok || code != protocol.ErrInvalidSideboardMove {
		t.Fatalf("virtual Wastes error = %v (%q, %t)", err, code, ok)
	}

	if _, err := r.MoveSideboard("host-conn", protocol.SideboardMove{
		Name: "Plains", FromZone: protocol.SideboardZoneMain,
		ToZone: protocol.SideboardZoneBasicLands,
	}); err != nil {
		t.Fatalf("remove virtual Plains: %v", err)
	}
	if _, err := r.SetSideboardReady("host-conn", true); err == nil {
		t.Fatal("limited sideboard accepted a 39-card mainboard")
	} else if code, ok := ErrorCode(err); !ok || code != protocol.ErrInvalidDeck {
		t.Fatalf("short limited mainboard error = %v (%q, %t)", err, code, ok)
	}

	r.DeckFormat = protocol.DeckFormatModern
	if _, err := r.MoveSideboard("host-conn", protocol.SideboardMove{
		Name: "Forest", FromZone: protocol.SideboardZoneBasicLands,
		ToZone: protocol.SideboardZoneMain,
	}); err == nil {
		t.Fatal("constructed sideboard accepted virtual basic-land supply")
	}
}
