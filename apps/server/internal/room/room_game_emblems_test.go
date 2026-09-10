// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"bytes"
	"encoding/json"
	"fmt"
	"reflect"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

func emblemRequest(seat int) protocol.GameCreateEmblem {
	return protocol.GameCreateEmblem{Seat: &seat, Name: "Chandra, Awakened Inferno Emblem",
		SetCode: "TM20", CollectorNumber: "1", TypeLine: "Emblem — Chandra"}
}

func mustCreateEmblem(t *testing.T, r *Room, actor string, owner int) string {
	t.Helper()
	result, err := r.CreateEmblem(actor, emblemRequest(owner))
	if err != nil {
		t.Fatal(err)
	}
	var created protocol.GameEmblemCreated
	if result.Reply == nil || result.Reply.Type != protocol.TypeGameEmblemCreated ||
		result.Reply.DecodePayload(&created) != nil || !result.ProjectGame ||
		created.RoomID != r.ID || created.Seat != owner || created.EmblemID == "" {
		t.Fatalf("invalid creation acknowledgement: %+v", result)
	}
	return created.EmblemID
}

func assertEmblemRejectedWithoutMutation(t *testing.T, r *Room, code string, action func() error) {
	t.Helper()
	before, _ := json.Marshal(r.Game)
	err := action()
	if err == nil || err.Error() != code {
		t.Fatalf("error=%v, want %s", err, code)
	}
	after, _ := json.Marshal(r.Game)
	if !bytes.Equal(before, after) {
		t.Fatalf("rejected emblem action mutated game\nbefore:%s\nafter:%s", before, after)
	}
}

func TestEmblemPublicProjectionReconnectAndOwnerCorrection(t *testing.T) {
	r := newStartedUtilityRoom(t, protocol.MatchBO1)
	if _, err := r.Join("observer", "Observer", true, ""); err != nil {
		t.Fatal(err)
	}
	r.Game.Seats[0].Hand = []protocol.GameCard{{ID: "secret", Name: "Private card", OwnerSeat: 0}}
	id := mustCreateEmblem(t, r, "host-conn", 1)
	second := mustCreateEmblem(t, r, "host-conn", 1)
	if id == second || len(r.Game.Seats[1].CommandZone) != 0 ||
		len(r.Game.Seats[1].CommanderTaxes) != 0 {
		t.Fatal("emblem instances must be independent of cards/commanders")
	}
	for _, viewer := range []string{"host-conn", "guest-conn", "observer"} {
		snapshot, err := r.GameSnapshot(viewer)
		if err != nil || len(snapshot.Seats[1].Emblems) != 2 || snapshot.Seats[1].Emblems[0].ID != id {
			t.Fatalf("public projection for %s: %+v err=%v", viewer, snapshot, err)
		}
		if viewer != "host-conn" && len(snapshot.Seats[0].Hand) != 0 {
			t.Fatal("emblem projection leaked a private hand")
		}
		snapshot.Seats[1].Emblems[0].Name = "mutated projection"
		if r.Game.Seats[1].Emblems[0].Name == "mutated projection" {
			t.Fatal("projection aliases authoritative emblem state")
		}
	}
	assertEmblemRejectedWithoutMutation(t, r, protocol.ErrInvalidTarget, func() error {
		_, err := r.RemoveEmblem("host-conn", protocol.GameRemoveEmblem{EmblemID: id})
		return err
	})
	if _, err := r.Reconnect("guest-conn", "guest-resumed"); err != nil {
		t.Fatal(err)
	}
	snapshot, err := r.GameSnapshot("guest-resumed")
	if err != nil || len(snapshot.Seats[1].Emblems) != 2 || snapshot.Seats[1].Emblems[0].ID != id {
		t.Fatalf("reconnect lost emblems: %+v, %v", snapshot, err)
	}
	result, err := r.RemoveEmblem("guest-resumed", protocol.GameRemoveEmblem{EmblemID: id})
	var removed protocol.GameEmblemRemoved
	if err != nil || !result.ProjectGame || result.Reply.DecodePayload(&removed) != nil ||
		removed.Seat != 1 || removed.EmblemID != id || result.Reply.Type != protocol.TypeGameEmblemRemoved {
		t.Fatalf("remove result %+v, error=%v", result, err)
	}
	if len(r.Game.Seats[1].Emblems) != 1 || r.Game.Seats[1].Emblems[0].ID != second ||
		r.Game.Log[len(r.Game.Log)-1].Kind != "remove_emblem" || r.Game.Log[0].Kind != "create_emblem" {
		t.Fatalf("wrong emblem removed or missing public logs: %+v", r.Game)
	}
	assertEmblemRejectedWithoutMutation(t, r, protocol.ErrInvalidTarget, func() error {
		_, err := r.RemoveEmblem("guest-resumed", protocol.GameRemoveEmblem{EmblemID: id})
		return err
	})
	// Server-side state serialization must retain both public identities and the
	// next id, without relying on card/command-zone traversal.
	encoded, _ := json.Marshal(r.Game)
	var restored GameState
	if json.Unmarshal(encoded, &restored) != nil ||
		!reflect.DeepEqual(restored.Seats[1].Emblems, r.Game.Seats[1].Emblems) ||
		restored.NextEmblemID != r.Game.NextEmblemID {
		t.Fatal("emblem state did not survive serialization")
	}
}

func TestEmblemIdentityAndOwnerValidationIsAtomic(t *testing.T) {
	cases := []struct {
		name string
		edit func(*protocol.GameCreateEmblem, *Room)
		code string
	}{
		{"missing owner", func(p *protocol.GameCreateEmblem, _ *Room) { p.Seat = nil }, protocol.ErrInvalidTarget},
		{"negative owner", func(p *protocol.GameCreateEmblem, _ *Room) { p.Seat = intPointer(-1) }, protocol.ErrInvalidTarget},
		{"out of range", func(p *protocol.GameCreateEmblem, _ *Room) { p.Seat = intPointer(9) }, protocol.ErrInvalidTarget},
		{"vacant owner", func(_ *protocol.GameCreateEmblem, r *Room) { r.Game.Seats[1].DisplayName = "" }, protocol.ErrInvalidTarget},
		{"eliminated owner", func(_ *protocol.GameCreateEmblem, r *Room) { r.Game.Seats[1].Eliminated = true }, protocol.ErrInvalidTarget},
	}
	for index, limit := range []int{protocol.MaxCardNameRunes, protocol.MaxSetCodeRunes,
		protocol.MaxCollectorNumberRunes, protocol.MaxTypeLineRunes} {
		for _, invalid := range []string{"\xff", "bad\x00value", "\n", strings.Repeat("界", limit+1)} {
			cases = append(cases, struct {
				name string
				edit func(*protocol.GameCreateEmblem, *Room)
				code string
			}{fmt.Sprintf("field%d/%q", index, invalid), func(p *protocol.GameCreateEmblem, _ *Room) {
				fields := []*string{&p.Name, &p.SetCode, &p.CollectorNumber, &p.TypeLine}
				*fields[index] = invalid
			}, protocol.ErrInvalidMessage})
		}
		if index < 3 {
			cases = append(cases, struct {
				name string
				edit func(*protocol.GameCreateEmblem, *Room)
				code string
			}{fmt.Sprintf("empty%d", index), func(p *protocol.GameCreateEmblem, _ *Room) {
				fields := []*string{&p.Name, &p.SetCode, &p.CollectorNumber}
				*fields[index] = "  "
			}, protocol.ErrInvalidMessage})
		}
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			r := newStartedUtilityRoom(t, protocol.MatchBO1)
			request := emblemRequest(1)
			tc.edit(&request, r)
			assertEmblemRejectedWithoutMutation(t, r, tc.code, func() error {
				_, err := r.CreateEmblem("host-conn", request)
				return err
			})
		})
	}
	for _, format := range []string{protocol.FormatModern, protocol.FormatDuel, protocol.FormatEDH} {
		t.Run("format/"+format, func(t *testing.T) {
			r := newStartedUtilityRoom(t, protocol.MatchBO1)
			r.Format = format
			request := emblemRequest(0)
			request.Name, request.SetCode, request.CollectorNumber, request.TypeLine = " 徽记 ", " tm20 ", "7†", ""
			if _, err := r.CreateEmblem("host-conn", request); err != nil {
				t.Fatal(err)
			}
			emblem := r.Game.Seats[0].Emblems[0]
			if emblem.Name != "徽记" || emblem.SetCode != "TM20" || emblem.CollectorNumber != "7†" {
				t.Fatalf("normalization lost valid identity: %+v", emblem)
			}
		})
	}
}

func TestEmblemLimitAndPermissions(t *testing.T) {
	r := newStartedUtilityRoom(t, protocol.MatchBO1)
	id := mustCreateEmblem(t, r, "host-conn", 1)
	for i := 1; i < protocol.MaxEmblemsPerSeat; i++ {
		mustCreateEmblem(t, r, "host-conn", 1)
	}
	assertEmblemRejectedWithoutMutation(t, r, protocol.ErrInvalidMessage, func() error {
		_, err := r.CreateEmblem("host-conn", emblemRequest(1))
		return err
	})
	mustCreateEmblem(t, r, "host-conn", 0)
	if _, err := r.RemoveEmblem("guest-conn", protocol.GameRemoveEmblem{EmblemID: id}); err != nil {
		t.Fatal(err)
	}
	if replacement := mustCreateEmblem(t, r, "host-conn", 1); replacement == id {
		t.Fatal("removed emblem ids must not be reused")
	}
	for _, scenario := range []string{"spectator", "outsider", "eliminated", "finished", "not started", "forge"} {
		t.Run(scenario, func(t *testing.T) {
			r := newStartedUtilityRoom(t, protocol.MatchBO1)
			id := mustCreateEmblem(t, r, "host-conn", 0)
			actor, code := "host-conn", ""
			switch scenario {
			case "spectator":
				_, err := r.Join("observer", "Observer", true, "")
				if err != nil {
					t.Fatal(err)
				}
				actor, code = "observer", protocol.ErrNotPlayer
			case "outsider":
				actor, code = "outsider", protocol.ErrNotInRoom
			case "eliminated":
				r.Game.Seats[0].Eliminated, code = true, protocol.ErrPlayerEliminated
			case "finished":
				r.Game.Result, code = &protocol.GameResult{}, protocol.ErrGameFinished
			case "not started":
				r.Game, code = nil, protocol.ErrGameNotStarted
			case "forge":
				r.RulesMode, code = protocol.RulesModeForge, protocol.ErrRulesActionRejected
			}
			assertEmblemRejectedWithoutMutation(t, r, code, func() error {
				_, err := r.CreateEmblem(actor, emblemRequest(0))
				return err
			})
			assertEmblemRejectedWithoutMutation(t, r, code, func() error {
				_, err := r.RemoveEmblem(actor, protocol.GameRemoveEmblem{EmblemID: id})
				return err
			})
		})
	}
}

func TestEmblemsClearForDepartedOwnerNotCreator(t *testing.T) {
	for _, transition := range []string{"concede", "leave", "kick", "expiry"} {
		t.Run(transition, func(t *testing.T) {
			r := newStartedUtilityRoom(t, protocol.MatchBO1)
			r.Format, r.MaxSeats = protocol.FormatEDH, 3
			r.Seats = append(r.Seats, Seat{Occupied: true, DisplayName: "Third", ConnectionID: "third"})
			r.Game.Seats = append(r.Game.Seats, PlayerGameState{Seat: 2, DisplayName: "Third"})
			mustCreateEmblem(t, r, "host-conn", 1)
			id := mustCreateEmblem(t, r, "guest-conn", 2)
			var err error
			switch transition {
			case "concede":
				_, err = r.ConcedeAt("guest-conn", testNow)
			case "leave":
				_, err = r.Leave("guest-conn")
			case "kick":
				_, err = r.Kick("host-conn", intPointer(1), nil)
			case "expiry":
				_, _, err = r.ExpireDisconnected("guest-conn")
			}
			if err != nil {
				t.Fatal(err)
			}
			if !r.Game.Seats[1].Eliminated || len(r.Game.Seats[1].Emblems) != 0 ||
				len(r.Game.Seats[2].Emblems) != 1 || r.Game.Seats[2].Emblems[0].ID != id || r.Game.Result != nil {
				t.Fatalf("wrong emblem lifetime after %s: %+v", transition, r.Game)
			}
		})
	}
}

func TestEmblemsNeverEnterCardOrCommanderOperations(t *testing.T) {
	r := newStartedUtilityRoom(t, protocol.MatchBO1)
	r.Format = protocol.FormatDuel
	id := mustCreateEmblem(t, r, "host-conn", 0)
	assertEmblemRejectedWithoutMutation(t, r, protocol.ErrCardNotFound, func() error {
		_, err := r.MoveCard("host-conn", protocol.GameMoveCard{CardID: id,
			FromZone: protocol.ZoneCommand, ToZone: protocol.ZoneHand})
		return err
	})
	assertEmblemRejectedWithoutMutation(t, r, protocol.ErrCardNotFound, func() error {
		_, err := r.CastCommander("host-conn", protocol.GameCastCommander{CommanderID: id})
		return err
	})
	assertEmblemRejectedWithoutMutation(t, r, protocol.ErrInvalidCounter, func() error {
		_, err := r.AdjustCommanderTax("host-conn", protocol.GameAdjustCommanderTax{CommanderID: id, Delta: 1})
		return err
	})
}

func TestEmblemsDoNotSurviveRestartOrNextGame(t *testing.T) {
	for _, transition := range []string{"restart", "next game"} {
		t.Run(transition, func(t *testing.T) {
			r := newStartedUtilityRoom(t, protocol.MatchBO3)
			r.Score = []int{0, 0}
			mustCreateEmblem(t, r, "host-conn", 0)
			mustCreateEmblem(t, r, "host-conn", 1)
			var err error
			if transition == "restart" {
				_, err = r.RestartGame("host-conn")
			} else {
				_, err = r.ConcedeAt("guest-conn", testNow)
				if err != nil {
					t.Fatal(err)
				}
				if len(r.Game.Seats[1].Emblems) != 0 || len(r.Game.Seats[0].Emblems) != 1 {
					t.Fatal("concede did not remove only the departed owner's emblems")
				}
				for i := range r.Game.Sideboard.Players {
					r.Game.Sideboard.Players[i].Ready = true
				}
				_, err = r.completeSideboard(protocol.SideboardEndReady, true)
			}
			if err != nil {
				t.Fatal(err)
			}
			for _, seat := range r.Game.Seats {
				if len(seat.Emblems) != 0 {
					t.Fatal("old emblem carried into new game")
				}
			}
		})
	}
}

func TestEmblemsSurviveRejectedRestartAndClearOnTwoPlayerDeparture(t *testing.T) {
	for _, transition := range []string{"leave", "kick", "expiry"} {
		t.Run(transition, func(t *testing.T) {
			r := newStartedUtilityRoom(t, protocol.MatchBO3)
			mustCreateEmblem(t, r, "host-conn", 0)
			mustCreateEmblem(t, r, "host-conn", 1)
			assertEmblemRejectedWithoutMutation(t, r, protocol.ErrNotHost, func() error {
				_, err := r.RestartGame("guest-conn")
				return err
			})
			var err error
			switch transition {
			case "leave":
				_, err = r.Leave("guest-conn")
			case "kick":
				_, err = r.Kick("host-conn", intPointer(1), nil)
			case "expiry":
				_, _, err = r.ExpireDisconnected("guest-conn")
			}
			if err != nil {
				t.Fatal(err)
			}
			if r.Game.Result == nil || !r.Game.Result.MatchFinished ||
				len(r.Game.Seats[0].Emblems) != 1 || len(r.Game.Seats[1].Emblems) != 0 {
				t.Fatalf("wrong terminal emblem ownership after %s: %+v", transition, r.Game)
			}
		})
	}
}

func TestEmblemsInSingleSeatPlaytest(t *testing.T) {
	// Use the real solo deck/ready/load flow, not a manually truncated two-seat
	// game, so this also exercises playtest canonicalization and initialization.
	r := newFuzzPlaytestRoom(t)
	if !r.Playtest || len(r.Game.Seats) != 1 || r.Game.ActiveSeat != 0 {
		t.Fatal("fixture did not start a one-seat playtest")
	}
	cardCount := assertUniqueGameCards(t, r.Game)
	id := mustCreateEmblem(t, r, "host-conn", 0)
	assertEmblemRejectedWithoutMutation(t, r, protocol.ErrInvalidTarget, func() error {
		_, err := r.CreateEmblem("host-conn", emblemRequest(1))
		return err
	})
	if _, err := r.Reconnect("host-conn", "solo-resumed"); err != nil {
		t.Fatal(err)
	}
	snapshot, err := r.GameSnapshot("solo-resumed")
	if err != nil || len(snapshot.Seats) != 1 || len(snapshot.Seats[0].Emblems) != 1 ||
		snapshot.Seats[0].Emblems[0].ID != id || len(snapshot.Seats[0].Hand) != 7 {
		t.Fatalf("solo snapshot lost emblem or private hand: %+v, err=%v", snapshot, err)
	}
	if _, err := r.RemoveEmblem("solo-resumed", protocol.GameRemoveEmblem{EmblemID: id}); err != nil {
		t.Fatal(err)
	}
	if len(r.Game.Seats[0].Emblems) != 0 || assertUniqueGameCards(t, r.Game) != cardCount {
		t.Fatal("solo emblem removal changed real card membership")
	}
	mustCreateEmblem(t, r, "solo-resumed", 0)
	if _, err := r.RestartGame("solo-resumed"); err != nil {
		t.Fatal(err)
	}
	if len(r.Game.Seats[0].Emblems) != 0 || assertUniqueGameCards(t, r.Game) != cardCount {
		t.Fatal("solo restart retained an emblem or changed the registered deck")
	}
}
