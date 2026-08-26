// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"testing"

	"hexproof/server/internal/protocol"
)

func TestNormalizeLibraryPlacementSharesSingleAndBatchPolicy(t *testing.T) {
	t.Parallel()
	placement := ""
	if err := normalizeLibraryPlacement(protocol.ZoneLibrary, &placement, nil, false); err != nil {
		t.Fatalf("default batch placement: %v", err)
	}
	if placement != protocol.LibraryPlacementTop {
		t.Fatalf("default placement = %q, want top", placement)
	}

	index := 3
	placement = protocol.LibraryPlacementIndex
	if err := normalizeLibraryPlacement(
		protocol.ZoneLibrary, &placement, &index, true); err != nil {
		t.Fatalf("single-card indexed placement: %v", err)
	}
	if err := normalizeLibraryPlacement(
		protocol.ZoneLibrary, &placement, nil, false); err == nil || err.Error() != protocol.ErrInvalidMove {
		t.Fatalf("batch indexed placement error = %v, want %s", err, protocol.ErrInvalidMove)
	}
}

func TestOwnedPublicCardCannotMoveIntoActorHiddenZone(t *testing.T) {
	t.Parallel()
	if err := validateOwnedCardDestination(
		0, 1, protocol.ZoneGraveyard, protocol.ZoneHand); err == nil || err.Error() != protocol.ErrInvalidTarget {
		t.Fatalf("remote hidden-zone move error = %v, want %s", err, protocol.ErrInvalidTarget)
	}
	if err := validateOwnedCardDestination(
		0, 1, protocol.ZoneGraveyard, protocol.ZoneBattlefield); err != nil {
		t.Fatalf("approved public card should remain movable to battlefield: %v", err)
	}
	if err := validateOwnedCardDestination(
		0, 1, protocol.ZoneGraveyard, protocol.ZoneExile); err != nil {
		t.Fatalf("owned public destination should remain allowed: %v", err)
	}
}
