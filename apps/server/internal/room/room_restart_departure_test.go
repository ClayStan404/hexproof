// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"encoding/json"
	"reflect"
	"testing"

	"hexproof/server/internal/protocol"
)

func newRestartCommanderRoom(t *testing.T) *Room {
	t.Helper()
	r := newTestRoom(t, 4, true)
	for _, connID := range []string{"guest-1", "guest-2", "guest-3"} {
		if _, err := r.Join(connID, connID, false, ""); err != nil {
			t.Fatal(err)
		}
	}
	for index := range r.Seats {
		deck := testDeck(protocol.FormatEDH)
		deck.Mainboard[0].Count = 12
		r.Seats[index].Deck = &deck
	}
	r.randomIndex = func(int) (int, error) { return 0, nil }
	r.Phase = protocol.RoomPhaseStarted
	r.Score = []int{0, 0, 0, 0}
	if err := r.setupGameNumberWithTurnOrder(3, 2, []int{2, 0, 3, 1}); err != nil {
		t.Fatal(err)
	}
	return r
}

func TestRestartCommanderGameAfterDeparture(t *testing.T) {
	for _, tc := range []struct {
		name       string
		departed   int
		conceded   string
		expireHost bool
		kick       bool
		rotate     bool
		twoRemain  bool
		wantOrder  []int
	}{
		{name: "nonstarting player", departed: 1, wantOrder: []int{2, 0, 3}},
		{name: "starting player", departed: 2, wantOrder: []int{0, 3, 1}},
		{name: "two remaining players", departed: 2, twoRemain: true, wantOrder: []int{0, 1}},
		{name: "rotated starting player", departed: 2, rotate: true, wantOrder: []int{0, 3, 1}},
		{name: "kicked player", departed: 1, kick: true, wantOrder: []int{2, 0, 3}},
		{name: "occupied conceded player", departed: 1, conceded: "guest-3", wantOrder: []int{2, 0, 3}},
		{name: "occupied conceded host", departed: 1, conceded: "host-conn", wantOrder: []int{2, 0, 3}},
		{name: "starting host timeout", departed: 0, expireHost: true, wantOrder: []int{3, 1, 2}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := newRestartCommanderRoom(t)
			if tc.twoRemain {
				if _, err := r.Leave("guest-3"); err != nil {
					t.Fatal(err)
				}
			}
			if tc.rotate {
				r.Game.TurnOrder = []int{0, 3, 1, 2}
			}
			if tc.conceded != "" {
				if _, err := r.ConcedeAt(tc.conceded, testNow); err != nil {
					t.Fatal(err)
				}
			}
			hostConnID := "host-conn"
			departedConnID := r.Seats[tc.departed].ConnectionID
			if tc.expireHost {
				r.Game.StartingSeat = 0
				if _, empty, err := r.ExpireDisconnected(departedConnID); err != nil || empty {
					t.Fatalf("expire host: empty=%v, err=%v", empty, err)
				}
				hostConnID = "guest-1"
				if !r.IsHost(hostConnID) {
					t.Fatal("existing timeout host transfer did not select seat 1")
				}
			} else if tc.kick {
				if _, err := r.Kick(hostConnID, &tc.departed, nil); err != nil {
					t.Fatal(err)
				}
			} else if _, err := r.Leave(departedConnID); err != nil {
				t.Fatal(err)
			}
			if r.Game.Result != nil || r.Seats[tc.departed].Occupied {
				t.Fatal("departure should leave an active game and an empty seat")
			}
			score := append([]int{}, r.Score...)
			result, err := r.RestartGame(hostConnID)
			if err != nil {
				t.Fatalf("restart remaining players: %v", err)
			}
			if !reflect.DeepEqual(r.Game.TurnOrder, tc.wantOrder) ||
				r.Game.StartingSeat != tc.wantOrder[0] || r.Game.ActiveSeat != tc.wantOrder[0] ||
				r.Game.Number != 3 || !reflect.DeepEqual(r.Score, score) {
				t.Fatalf("restart changed coordinates: order=%v start=%d active=%d number=%d score=%v",
					r.Game.TurnOrder, r.Game.StartingSeat, r.Game.ActiveSeat, r.Game.Number, r.Score)
			}
			for seat, membership := range r.Seats {
				state := r.Game.Seats[seat]
				if membership.Occupied {
					if state.Eliminated || len(state.Hand) != 7 || state.Life != 40 {
						t.Fatalf("occupied seat %d was not rebuilt: %+v", seat, state)
					}
				} else if !state.Eliminated || len(state.Hand) != 0 {
					t.Fatalf("empty seat %d rejoined the game: %+v", seat, state)
				}
			}
			if result.Reply == nil || len(result.Broadcast) != 1 || !result.ProjectGame {
				t.Fatalf("missing restart lifecycle: %+v", result)
			}
			for _, envelope := range []protocol.Envelope{*result.Reply, result.Broadcast[0]} {
				var payload protocol.GameRestarted
				if envelope.Type != protocol.TypeGameRestarted || envelope.DecodePayload(&payload) != nil ||
					payload.StartingSeat != r.Game.StartingSeat || payload.GameNumber != r.Game.Number {
					t.Fatalf("restart event disagrees with game: %+v", payload)
				}
			}
			if result.Broadcast[0].SeqValue() <= 0 {
				t.Fatal("restart lifecycle broadcast must be sequenced")
			}
		})
	}
}

func TestRestartCommanderGameRejectsInvalidOrder(t *testing.T) {
	for _, tc := range []struct {
		name  string
		order []int
		start int
	}{
		{name: "empty", start: 2},
		{name: "missing starting player", order: []int{0, 3, 1}, start: 2},
		{name: "duplicate", order: []int{2, 0, 3, 3, 1}, start: 2},
		{name: "duplicate departed", order: []int{2, 0, 3, 1, 1}, start: 2},
		{name: "negative seat", order: []int{2, 0, -1, 3, 1}, start: 2},
		{name: "out of range seat", order: []int{2, 0, 4, 3, 1}, start: 2},
		{name: "missing occupied player", order: []int{2, 0, 1}, start: 2},
		{name: "no remaining ordered player", order: []int{1}, start: 1},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := newRestartCommanderRoom(t)
			if _, err := r.Leave("guest-1"); err != nil {
				t.Fatal(err)
			}
			r.Game.TurnOrder, r.Game.StartingSeat = tc.order, tc.start
			before, err := json.Marshal(r.Game)
			if err != nil {
				t.Fatal(err)
			}
			result, err := r.RestartGame("host-conn")
			if err == nil || err.Error() != protocol.ErrGameSetupFailed {
				t.Fatalf("invalid order error = %v", err)
			}
			after, marshalErr := json.Marshal(r.Game)
			if marshalErr != nil || string(before) != string(after) ||
				result.Reply != nil || len(result.Broadcast) != 0 || result.ProjectGame {
				t.Fatal("failed restart changed the current game or emitted lifecycle events")
			}
		})
	}
}

func TestStartedCommanderHostLeaveStillDisbands(t *testing.T) {
	r := newRestartCommanderRoom(t)
	result, err := r.Leave("host-conn")
	if err != nil || !r.Disbanded || result.Reply == nil ||
		result.Reply.Type != protocol.TypeRoomDisbanded {
		t.Fatalf("host leave no longer disbands: result=%+v, err=%v", result, err)
	}
	for _, membership := range r.Seats {
		if membership.Host {
			t.Fatal("intentional host leave transferred authority")
		}
	}
	if _, err := r.RestartGame("guest-1"); err == nil || err.Error() != protocol.ErrNotHost {
		t.Fatalf("non-host restarted a disbanded room: %v", err)
	}
}
