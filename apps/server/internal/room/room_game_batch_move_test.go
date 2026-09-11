// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"reflect"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

func batchMoveRoom(t *testing.T, zone string) *Room {
	t.Helper()
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("guest", "Guest", false, ""); err != nil {
		t.Fatal(err)
	}
	if _, err := r.Join("viewer", "Viewer", true, ""); err != nil {
		t.Fatal(err)
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{Number: 1, Seats: []PlayerGameState{
		{Seat: 0, DisplayName: "Host", Library: []protocol.GameCard{
			{ID: "top", Name: "Hidden top", OwnerSeat: 0},
			{ID: "middle", Name: "Hidden middle", OwnerSeat: 0},
			{ID: "bottom", Name: "Hidden bottom", OwnerSeat: 0},
		}}, {Seat: 1, DisplayName: "Guest"},
	}, NextLogID: 1}
	*playerGameZone(&r.Game.Seats[0], zone) = []protocol.GameCard{
		{ID: "a", Name: "Chosen Alpha", OwnerSeat: 0},
		{ID: "b", Name: "Chosen Beta", OwnerSeat: 0},
		{ID: "c", Name: "Unselected Gamma", OwnerSeat: 0},
	}
	r.randomIndex = func(int) (int, error) { return 0, nil }
	return r
}

func batchCardIDs(cards []protocol.GameCard) []string {
	ids := make([]string, len(cards))
	for i, card := range cards {
		ids[i] = card.ID
	}
	return ids
}

func TestBatchLibraryPlacementsAndPrivateProjection(t *testing.T) {
	for _, source := range []string{protocol.ZoneGraveyard, protocol.ZoneExile, protocol.ZoneHand, protocol.ZoneBattlefield} {
		for _, scenario := range []struct {
			placement string
			random    bool
			want      []string
		}{
			{"top", false, []string{"b", "a", "top", "middle", "bottom"}},
			{"bottom", false, []string{"top", "middle", "bottom", "b", "a"}},
			{"top", true, []string{"a", "b", "top", "middle", "bottom"}},
			{"bottom", true, []string{"top", "middle", "bottom", "a", "b"}},
			{"shuffle", false, []string{"middle", "bottom", "b", "a", "top"}},
		} {
			t.Run(fmt.Sprintf("%s/%s/random=%v", source, scenario.placement, scenario.random), func(t *testing.T) {
				r := batchMoveRoom(t, source)
				result, err := r.MoveCards("host-conn", protocol.GameMoveCards{
					CardIDs: []string{"b", "a"}, FromZone: source, ToZone: protocol.ZoneLibrary,
					LibraryPlacement: scenario.placement, Randomize: scenario.random,
				})
				if err != nil {
					t.Fatal(err)
				}
				if got := batchCardIDs(r.Game.Seats[0].Library); !reflect.DeepEqual(got, scenario.want) {
					t.Fatalf("library = %v, want %v", got, scenario.want)
				}
				if got := batchCardIDs(*playerGameZone(&r.Game.Seats[0], source)); !reflect.DeepEqual(got, []string{"c"}) {
					t.Fatalf("remaining source = %v", got)
				}
				encoded, _ := json.Marshal(result.Reply)
				for _, secret := range []string{"Hidden", "Chosen", "Unselected", "cardIds"} {
					if strings.Contains(string(encoded), secret) {
						t.Fatalf("reply leaks %s: %s", secret, encoded)
					}
				}
				for _, viewer := range []string{"host-conn", "guest", "viewer"} {
					snapshot, err := r.GameSnapshot(viewer)
					if err != nil {
						t.Fatal(err)
					}
					encoded, _ := json.Marshal(snapshot)
					for _, secret := range []string{"Hidden", "Chosen"} {
						if strings.Contains(string(encoded), secret) {
							t.Fatalf("%s projection leaks %s", viewer, secret)
						}
					}
					if source == protocol.ZoneHand && viewer != "host-conn" && strings.Contains(string(encoded), "Unselected") {
						t.Fatalf("%s sees unselected hand", viewer)
					}
				}
				if !strings.Contains(r.Game.Log[0].Text, scenario.placement) {
					t.Fatalf("placement missing from log: %s", r.Game.Log[0].Text)
				}
			})
		}
	}
}

func TestBatchEnduranceMovesWholeGraveyardWithoutShufflingExistingLibrary(t *testing.T) {
	r := batchMoveRoom(t, protocol.ZoneGraveyard)
	calls := 0
	r.randomIndex = func(maximum int) (int, error) {
		calls++
		if maximum > 3 {
			t.Fatalf("shuffled existing library: %d", maximum)
		}
		return 0, nil
	}
	if _, err := r.MoveCards("host-conn", protocol.GameMoveCards{CardIDs: []string{"a", "b", "c"}, FromZone: protocol.ZoneGraveyard, ToZone: protocol.ZoneLibrary, LibraryPlacement: "bottom", Randomize: true}); err != nil {
		t.Fatal(err)
	}
	if calls != 2 || len(r.Game.Seats[0].Graveyard) != 0 {
		t.Fatalf("calls=%d remaining=%v", calls, r.Game.Seats[0].Graveyard)
	}
	if got := batchCardIDs(r.Game.Seats[0].Library); !reflect.DeepEqual(got, []string{"top", "middle", "bottom", "b", "c", "a"}) {
		t.Fatal(got)
	}
}

func TestBatchShuffleFailureRollsBackAllOwnersAndRelations(t *testing.T) {
	r := batchMoveRoom(t, protocol.ZoneBattlefield)
	r.Game.Seats[0].Battlefield[1].OwnerSeat = 1
	r.Game.Seats[1].Library = []protocol.GameCard{{ID: "foreign-top", OwnerSeat: 1}}
	r.Game.Seats[0].Battlefield[0].Tapped = true
	r.Game.Arrows = []protocol.GameArrow{{Seat: 0, SourceCardID: "a", Kind: protocol.ArrowKindTarget, TargetCardID: "b"}}
	r.Game.Attachments = []protocol.GameAttachment{{OwnerSeat: 0, SourceCardID: "a", TargetCardID: "b"}}
	calls := 0
	r.randomIndex = func(int) (int, error) {
		calls++
		if calls == 4 {
			return 0, errors.New("entropy unavailable")
		}
		return 0, nil
	}
	before, _ := json.Marshal(r.Game)
	_, err := r.MoveCards("host-conn", protocol.GameMoveCards{CardIDs: []string{"a", "b"}, FromZone: protocol.ZoneBattlefield, ToZone: protocol.ZoneLibrary, LibraryPlacement: "shuffle"})
	if err == nil || err.Error() != protocol.ErrGameSetupFailed || calls != 4 {
		t.Fatalf("err=%v calls=%d", err, calls)
	}
	after, _ := json.Marshal(r.Game)
	if string(before) != string(after) {
		t.Fatal("shuffle failure partially mutated a source/library/log")
	}
}

func TestBatchInvalidInputsAndRandomFailureAreAtomic(t *testing.T) {
	for _, scenario := range []struct {
		name       string
		conn       string
		move       protocol.GameMoveCards
		failRandom bool
	}{
		{name: "duplicate", move: protocol.GameMoveCards{CardIDs: []string{"a", "a"}}},
		{name: "stale", move: protocol.GameMoveCards{CardIDs: []string{"a", "missing"}}},
		{name: "empty", move: protocol.GameMoveCards{}},
		{name: "spectator", conn: "viewer", move: protocol.GameMoveCards{CardIDs: []string{"a"}}},
		{name: "foreign", conn: "guest", move: protocol.GameMoveCards{CardIDs: []string{"a"}}},
		{name: "shuffle and random", move: protocol.GameMoveCards{CardIDs: []string{"a"}, LibraryPlacement: "shuffle", Randomize: true}},
		{name: "bad placement", move: protocol.GameMoveCards{CardIDs: []string{"a"}, LibraryPlacement: "index"}},
		{name: "shuffle wrong zone", move: protocol.GameMoveCards{CardIDs: []string{"a"}, ToZone: protocol.ZoneExile, LibraryPlacement: "shuffle"}},
		{name: "random failure", move: protocol.GameMoveCards{CardIDs: []string{"a", "b"}, Randomize: true}, failRandom: true},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			r := batchMoveRoom(t, protocol.ZoneGraveyard)
			if scenario.failRandom {
				r.randomIndex = func(int) (int, error) { return 0, errors.New("unavailable") }
			}
			move := scenario.move
			move.FromZone = protocol.ZoneGraveyard
			if move.ToZone == "" {
				move.ToZone = protocol.ZoneLibrary
			}
			conn := scenario.conn
			if conn == "" {
				conn = "host-conn"
			}
			before, _ := json.Marshal(r.Game)
			if _, err := r.MoveCards(conn, move); err == nil {
				t.Fatal("accepted invalid batch")
			}
			after, _ := json.Marshal(r.Game)
			if string(before) != string(after) {
				t.Fatal("rejection changed game")
			}
		})
	}
}

func TestBatchHandMovesAndBattlefieldBounce(t *testing.T) {
	r := batchMoveRoom(t, protocol.ZoneHand)
	target := 1
	if _, err := r.MoveCards("host-conn", protocol.GameMoveCards{CardIDs: []string{"a", "b"}, FromZone: protocol.ZoneHand, ToZone: protocol.ZoneBattlefield, ToSeat: &target, Position: &protocol.CardPosition{X: .5, Y: .5}}); err != nil {
		t.Fatal(err)
	}
	r.Game.Seats[1].Battlefield[0].FaceDown = true
	r.Game.Seats[1].Battlefield[0].Tapped = true
	r.Game.Seats[1].Battlefield[1].Token = true
	if _, err := r.MoveCards("guest", protocol.GameMoveCards{CardIDs: []string{"a", "b"}, FromZone: protocol.ZoneBattlefield, ToZone: protocol.ZoneHand}); err != nil {
		t.Fatal(err)
	}
	hand := r.Game.Seats[0].Hand
	if len(hand) != 2 || hand[1].ID != "a" || hand[1].FaceDown || hand[1].Tapped || len(r.Game.Seats[1].Hand) != 0 || len(r.Game.Seats[1].Battlefield) != 0 {
		t.Fatalf("bounce = %+v", r.Game.Seats)
	}
	if !strings.Contains(r.Game.Log[len(r.Game.Log)-1].Text, "1 token(s)") {
		t.Fatal("removed token count missing")
	}
}

func TestBatchTokenRecyclingStillShufflesItsOwnersLibrary(t *testing.T) {
	r := batchMoveRoom(t, protocol.ZoneBattlefield)
	r.Game.Seats[0].Battlefield[0].Token = true
	if _, err := r.MoveCards("host-conn", protocol.GameMoveCards{CardIDs: []string{"a"}, FromZone: protocol.ZoneBattlefield, ToZone: protocol.ZoneLibrary, LibraryPlacement: "shuffle"}); err != nil {
		t.Fatal(err)
	}
	if got := batchCardIDs(r.Game.Seats[0].Library); !reflect.DeepEqual(got, []string{"middle", "bottom", "top"}) {
		t.Fatal(got)
	}
	if len(r.Game.Seats[0].Battlefield) != 2 {
		t.Fatal("token was not removed")
	}
}

func TestBattlefieldBatchPositionsStayReachable(t *testing.T) {
	for _, count := range []int{1, 2, 7, 100, protocol.MaxDeckCards} {
		for _, anchor := range []protocol.CardPosition{{X: 0, Y: 0}, {X: .5, Y: .5}, {X: 1, Y: 1}} {
			seen := make(map[protocol.CardPosition]bool)
			for index := 0; index < count; index++ {
				position := *battlefieldBatchPosition(anchor, index, count)
				if position.X < 0 || position.X > 1 || position.Y < 0 || position.Y > 1 || seen[position] {
					t.Fatalf("count=%d index=%d unreachable position=%+v", count, index, position)
				}
				seen[position] = true
			}
		}
	}
	// Keep this compact seven-card scenario aligned with the client layout
	// regression: each card's center remains outside later cards' hitboxes.
	positions := make([]protocol.CardPosition, 7)
	for index := range positions {
		positions[index] = *battlefieldBatchPosition(protocol.CardPosition{X: .5, Y: .5}, index, len(positions))
	}
	for i, left := range positions {
		for _, right := range positions[i+1:] {
			dx, dy := math.Abs(left.X-right.X)*500, math.Abs(left.Y-right.Y)*220
			if dx < 40 && dy < 56 {
				t.Fatalf("card center covered: %+v %+v", left, right)
			}
		}
	}
}
