// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"encoding/json"
	"hexproof/server/internal/protocol"
	"strings"
	"testing"
	"time"
)

func newAIPracticeRoom(t *testing.T, loadMode string) *Room {
	t.Helper()
	r, err := NewWithRulesMode("AIGAME", "Practice", protocol.FormatModern, protocol.MatchBO1,
		loadMode, protocol.RulesModeForge, 2, true, false, "Human", "human", testNow)
	if err != nil {
		t.Fatal(err)
	}
	if err = r.AddForgeAI(protocol.AIDifficultyNormal); err != nil {
		t.Fatal(err)
	}
	return r
}

func TestAIPracticeGatePrivacyAndRematch(t *testing.T) {
	for _, mode := range []string{protocol.CardLoadPreload, protocol.CardLoadBackground} {
		t.Run(mode, func(t *testing.T) {
			r := newAIPracticeRoom(t, mode)
			if r.Member("") || r.FindSeatByConnection("") != -1 || r.Seats[1].ConnectionID != "" {
				t.Fatal("AI acquired transport membership")
			}
			if _, err := r.Join("other", "Other", false, ""); err == nil {
				t.Fatal("human replaced reserved AI seat")
			}
			deck := testDeck(protocol.FormatModern)
			deck.Name, deck.Mainboard[0].Name = "Private AI deck", "Private AI card"
			if _, err := r.ConfigureAI("human", protocol.RoomAIConfigure{Difficulty: protocol.AIDifficultyEasy, Deck: &deck}); err != nil {
				t.Fatal(err)
			}
			deck.Mainboard[0].Name = "mutated input"
			if r.Seats[1].Deck.Mainboard[0].Name != "Private AI card" {
				t.Fatal("deck was not copied")
			}
			raw, _ := json.Marshal(r.Snapshot())
			if strings.Contains(string(raw), "Private AI") || strings.Contains(string(raw), "human") {
				t.Fatal("snapshot leaked deck or connection")
			}
			if r.Snapshot().Seats[1].Controller != protocol.SeatControllerForgeAI || !r.Seats[1].Ready || r.ListEntry().PlayerJoinable {
				t.Fatal("AI room projection is incomplete")
			}
			human := testDeck(protocol.FormatModern)
			if _, err := r.SelectDeck("human", human); err != nil {
				t.Fatal(err)
			}
			result, err := r.SetReady("human", true)
			if err != nil {
				t.Fatal(err)
			}
			if mode == protocol.CardLoadPreload {
				if r.Phase != protocol.RoomPhaseLoading || !r.Seats[1].Loaded {
					t.Fatal("AI blocked load gate")
				}
				result, err = r.CompleteLoad("human", r.LoadID)
				if err != nil {
					t.Fatal(err)
				}
			}
			if !result.StartRulesGame || r.Phase != protocol.RoomPhaseStarted {
				t.Fatal("single human did not start game")
			}
			players, err := r.RulesStartPlayers()
			if err != nil || players[1].Controller != protocol.SeatControllerForgeAI || players[1].AIDifficulty != protocol.AIDifficultyEasy {
				t.Fatalf("lost AI controller: %v", err)
			}
			if _, err := r.ConfigureAI("human", protocol.RoomAIConfigure{Difficulty: protocol.AIDifficultyHard}); err == nil {
				t.Fatal("live difficulty changed")
			}
			if _, err := r.CompleteRulesGame(1, testNow.Add(time.Minute)); err != nil {
				t.Fatal(err)
			}
			if _, err := r.ReturnToRoom("human"); err != nil {
				t.Fatal(err)
			}
			if !r.Seats[1].Ready || r.Seats[0].Ready || r.Seats[1].Deck == nil {
				t.Fatal("rematch did not preserve AI deck/readiness")
			}
			if _, err := r.ConfigureAI("human", protocol.RoomAIConfigure{Difficulty: protocol.AIDifficultyHard}); err != nil {
				t.Fatal(err)
			}
			if r.Seats[1].Deck == nil || r.AIDifficulty != protocol.AIDifficultyHard {
				t.Fatal("difficulty-only update discarded AI deck")
			}
		})
	}
}

func TestAIPracticeAuthorizationReconnectAndFinalHumanCleanup(t *testing.T) {
	r := newAIPracticeRoom(t, protocol.CardLoadBackground)
	if _, err := r.Join("observer", "Observer", true, ""); err != nil {
		t.Fatal(err)
	}
	if _, err := r.ConfigureAI("observer", protocol.RoomAIConfigure{Difficulty: protocol.AIDifficultyEasy}); err == nil {
		t.Fatal("observer configured AI")
	}
	if _, err := r.Kick("human", intPointer(1), nil); err == nil {
		t.Fatal("AI was kicked as a network member")
	}
	if _, err := r.Reconnect("human", "resumed"); err != nil {
		t.Fatal(err)
	}
	if !r.IsHost("resumed") || r.Seats[1].Host {
		t.Fatal("reconnect changed controller authority")
	}
	result, empty, err := r.ExpireDisconnected("resumed")
	if err != nil || !empty || !r.Disbanded || r.HostSeat != -1 || r.Seats[1].Host || len(result.Broadcast) != 1 || result.Broadcast[0].Type != protocol.TypeRoomDisbanded {
		t.Fatalf("AI survived final human: %+v %v %v", result, empty, err)
	}
}

func TestAIPracticeRejectsInvalidScopeAndAtomicConfiguration(t *testing.T) {
	for _, alter := range []func(*Room){
		func(r *Room) { r.RulesMode = protocol.RulesModeManual },
		func(r *Room) { r.MatchMode = protocol.MatchBO3 },
		func(r *Room) { r.Format = protocol.FormatDuel },
		func(r *Room) { r.DeckFormat = protocol.DeckFormatCube },
		func(r *Room) { r.LimitedDeckLocked = true },
	} {
		r := newAIPracticeRoom(t, protocol.CardLoadBackground)
		r.Seats[1] = Seat{}
		alter(r)
		if err := r.AddForgeAI(protocol.AIDifficultyNormal); err == nil {
			t.Fatal("unsupported scope accepted")
		}
	}
	r := newAIPracticeRoom(t, protocol.CardLoadBackground)
	invalid := testDeck(protocol.FormatModern)
	invalid.Mainboard = nil
	if _, err := r.ConfigureAI("human", protocol.RoomAIConfigure{Difficulty: protocol.AIDifficultyHard, Deck: &invalid}); err == nil {
		t.Fatal("invalid AI deck accepted")
	}
	if r.AIDifficulty != protocol.AIDifficultyNormal || r.Seats[1].Deck != nil {
		t.Fatal("rejected config changed room")
	}
}
