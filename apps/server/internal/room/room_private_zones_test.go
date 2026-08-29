// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"testing"

	"hexproof/server/internal/protocol"
)

// newRemoteDumpRoom builds a started two-seat game where the host may ask to
// inspect the guest's library.
func newRemoteDumpRoom(t *testing.T) *Room {
	t.Helper()
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("guest-conn", "Guest", false, ""); err != nil {
		t.Fatalf("join guest: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{Seat: 0, DisplayName: "Host"},
			{Seat: 1, DisplayName: "Guest", Library: []protocol.GameCard{
				{ID: "guest-top", Name: "Guest Top", OwnerSeat: 1},
				{ID: "guest-rest", Name: "Guest Rest", OwnerSeat: 1},
			}},
		},
		NextLogID: 1,
	}
	return r
}

// ZoneDumpTarget gates the consent request, so it must reject the same
// out-of-range counts DumpZone rejects. Otherwise an invalid count survives
// until DumpApprovedZone and the target is asked to answer a doomed request.
func TestZoneDumpTargetRejectsOutOfRangeTopCount(t *testing.T) {
	targetSeat := 1
	cases := []struct {
		name     string
		topCount int
	}{
		{name: "negative", topCount: -1},
		{name: "above deck limit", topCount: protocol.MaxDeckCards + 1},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			r := newRemoteDumpRoom(t)
			request := protocol.GameDumpZone{
				Zone:     protocol.ZoneLibrary,
				Seat:     &targetSeat,
				TopCount: testCase.topCount,
			}
			if _, err := r.ZoneDumpTarget("host-conn", request); err == nil ||
				err.Error() != protocol.ErrInvalidMove {
				t.Fatalf("remote dump err = %v, want %q", err, protocol.ErrInvalidMove)
			}
			// The own-library path already rejected this count; both entry
			// points must agree.
			if _, err := r.DumpZone("guest-conn", protocol.GameDumpZone{
				Zone: protocol.ZoneLibrary, TopCount: testCase.topCount,
			}); err == nil || err.Error() != protocol.ErrInvalidMove {
				t.Fatalf("own dump err = %v, want %q", err, protocol.ErrInvalidMove)
			}
		})
	}
}

func TestZoneDumpTargetAcceptsValidTopCount(t *testing.T) {
	r := newRemoteDumpRoom(t)
	targetSeat := 1
	target, err := r.ZoneDumpTarget("host-conn", protocol.GameDumpZone{
		Zone:     protocol.ZoneLibrary,
		Seat:     &targetSeat,
		TopCount: 1,
	})
	if err != nil {
		t.Fatalf("remote dump target: %v", err)
	}
	if target.RequesterSeat != 0 || target.TargetSeat != targetSeat ||
		target.TargetConnID != "guest-conn" || target.TopCount != 1 {
		t.Fatalf("remote dump target = %+v", target)
	}
}

// A full-library search uses TopCount 0, which must stay valid at both entry
// points so the tightened bound does not break library search.
func TestZoneDumpTargetAcceptsFullLibrarySearch(t *testing.T) {
	r := newRemoteDumpRoom(t)
	targetSeat := 1
	target, err := r.ZoneDumpTarget("host-conn", protocol.GameDumpZone{
		Zone: protocol.ZoneLibrary, Seat: &targetSeat, TopCount: 0,
	})
	if err != nil {
		t.Fatalf("remote full search: %v", err)
	}
	if target.TopCount != 0 {
		t.Fatalf("remote full search topCount = %d, want 0", target.TopCount)
	}
	if _, err := r.DumpZone("guest-conn", protocol.GameDumpZone{
		Zone: protocol.ZoneLibrary, TopCount: 0,
	}); err != nil {
		t.Fatalf("own full search: %v", err)
	}
}
