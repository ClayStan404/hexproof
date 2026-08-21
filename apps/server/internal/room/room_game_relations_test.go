// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"testing"

	"hexproof/server/internal/protocol"
)

func TestTargetArrowsAcceptControlledBattlefieldAndOwnedStackSources(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("g1", "Guest", false, ""); err != nil {
		t.Fatalf("join guest: %v", err)
	}
	position := &protocol.CardPosition{X: 0.4, Y: 0.5}
	hostArtifact := protocol.GameCard{
		ID: "host-artifact", Name: "Icy Manipulator", OwnerSeat: 0,
		Position: position,
	}
	guestPermanent := protocol.GameCard{
		ID: "guest-permanent", Name: "Grizzly Bears", OwnerSeat: 1,
		Position: position,
	}
	stackSpell := protocol.GameSharedCard{GameCard: protocol.GameCard{
		ID: "host-spell", Name: "Lightning Bolt", OwnerSeat: 0,
	}}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1, ActiveSeat: 0, CurrentPhase: protocol.GamePhaseFirstMain,
		Seats: []PlayerGameState{
			{Seat: 0, DisplayName: "Host", Battlefield: []protocol.GameCard{hostArtifact}},
			{Seat: 1, DisplayName: "Guest", Battlefield: []protocol.GameCard{guestPermanent}},
		},
		Stack:     []protocol.GameSharedCard{stackSpell},
		Arrows:    []protocol.GameArrow{},
		Log:       []protocol.GameLogEntry{},
		NextLogID: 1,
	}

	targetSeat := 1
	if _, err := r.SetArrow("host-conn", protocol.GameSetArrow{
		SourceCardIDs: []string{stackSpell.ID},
		Kind:          protocol.ArrowKindTarget,
		TargetSeat:    &targetSeat,
	}); err != nil {
		t.Fatalf("stack spell targets player: %v", err)
	}
	if len(r.Game.Arrows) != 1 || r.Game.Arrows[0].TargetSeat == nil ||
		*r.Game.Arrows[0].TargetSeat != 1 {
		t.Fatalf("player target arrow = %+v", r.Game.Arrows)
	}

	if _, err := r.SetArrow("host-conn", protocol.GameSetArrow{
		SourceCardIDs: []string{stackSpell.ID},
		Kind:          protocol.ArrowKindTarget,
		TargetCardID:  guestPermanent.ID,
	}); err != nil {
		t.Fatalf("stack spell targets permanent: %v", err)
	}
	if len(r.Game.Arrows) != 1 ||
		r.Game.Arrows[0].TargetCardID != guestPermanent.ID ||
		r.Game.Arrows[0].TargetSeat != nil {
		t.Fatalf("permanent target arrow = %+v", r.Game.Arrows)
	}

	if _, err := r.SetArrow("g1", protocol.GameSetArrow{
		SourceCardIDs: []string{stackSpell.ID},
		Kind:          protocol.ArrowKindTarget,
		TargetCardID:  hostArtifact.ID,
	}); err == nil || err.Error() != protocol.ErrInvalidTarget {
		t.Fatalf("opponent stack source error = %v", err)
	}

	if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: stackSpell.ID, FromZone: protocol.ZoneStack,
		ToZone: protocol.ZoneGraveyard,
	}); err != nil {
		t.Fatalf("resolve stack spell: %v", err)
	}
	if len(r.Game.Arrows) != 0 {
		t.Fatalf("resolved stack source retained arrows = %+v", r.Game.Arrows)
	}

	selfSeat := 0
	if _, err := r.SetArrow("host-conn", protocol.GameSetArrow{
		SourceCardIDs: []string{hostArtifact.ID},
		Kind:          protocol.ArrowKindTarget,
		TargetSeat:    &selfSeat,
	}); err != nil {
		t.Fatalf("artifact ability targets controller: %v", err)
	}
	guestSeat := 1
	if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: hostArtifact.ID, FromZone: protocol.ZoneBattlefield,
		ToZone: protocol.ZoneBattlefield, ToSeat: &guestSeat,
		Position: position,
	}); err != nil {
		t.Fatalf("move targeted source to another battlefield: %v", err)
	}
	if len(r.Game.Arrows) != 0 {
		t.Fatalf("transferred source retained arrows = %+v", r.Game.Arrows)
	}
}
