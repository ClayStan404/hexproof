// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"encoding/json"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

func manualChoiceRoom(t *testing.T) *Room {
	t.Helper()
	r := newTestRoom(t, 2, true)
	r.Format = protocol.FormatModern
	r.MatchMode = protocol.MatchBO3
	for _, member := range []struct {
		id        string
		spectator bool
	}{{"g1", false}, {"observer", true}} {
		if _, err := r.Join(member.id, member.id, member.spectator, ""); err != nil {
			t.Fatal(err)
		}
	}
	for index := range r.Seats {
		deck := testDeck(protocol.FormatModern)
		r.Seats[index].Deck = &deck
	}
	r.randomIndex = func(max int) (int, error) { return 0, nil }
	r.Phase = protocol.RoomPhaseStarted
	if err := r.setupGame(); err != nil {
		t.Fatal(err)
	}
	return r
}

func TestPreviousLoserChoosesDrawBeforeNextGame(t *testing.T) {
	for _, timeout := range []bool{false, true} {
		t.Run(map[bool]string{false: "ready", true: "timeout"}[timeout], func(t *testing.T) {
			r := manualChoiceRoom(t)
			if _, err := r.ConcedeAt("host-conn", testNow); err != nil {
				t.Fatal(err)
			}
			for _, id := range []string{"g1", "observer"} {
				if _, err := r.ChooseStartingPlayer(id, protocol.SideboardChooseStartingPlayer{StartingSeat: 1}); err == nil {
					t.Fatalf("%s could choose", id)
				}
			}
			if _, err := r.ChooseStartingPlayer("host-conn", protocol.SideboardChooseStartingPlayer{StartingSeat: 2}); err == nil {
				t.Fatal("invalid starting seat accepted")
			}
			if _, err := r.SetSideboardReady("host-conn", true); err != nil {
				t.Fatal(err)
			}
			if _, err := r.ChooseStartingPlayer("host-conn", protocol.SideboardChooseStartingPlayer{StartingSeat: 1}); err != nil {
				t.Fatal(err)
			}
			if r.Game.Sideboard.Players[0].Ready {
				t.Fatal("changing play/draw must clear readiness")
			}
			for _, id := range []string{"host-conn", "g1", "observer"} {
				view, err := r.GameSnapshot(id)
				if err != nil {
					t.Fatal(err)
				}
				if view.Sideboard.CanChooseStartingPlayer != (id == "host-conn") || view.Sideboard.ChosenStartingSeat == nil || *view.Sideboard.ChosenStartingSeat != 1 {
					t.Fatalf("invalid choice projection: %+v", view.Sideboard)
				}
				if id == "observer" && (len(view.Sideboard.Mainboard) > 0 || len(view.Sideboard.Sideboard) > 0) {
					t.Fatal("choice exposed private deck")
				}
			}
			if timeout {
				if _, err := r.ExpireSideboard(r.Game.Sideboard.Deadline); err != nil {
					t.Fatal(err)
				}
			} else {
				for _, id := range []string{"host-conn", "g1"} {
					if _, err := r.SetSideboardReady(id, true); err != nil {
						t.Fatal(err)
					}
				}
			}
			if r.Game.Number != 2 || r.Game.StartingSeat != 1 || r.Game.ActiveSeat != 1 || r.Score[1] != 1 {
				t.Fatalf("loser's draw choice ignored: %+v", r.Game)
			}
		})
	}
}

func TestRevealedLibraryTopTracksMutationsWithoutLeakingOtherCards(t *testing.T) {
	r := manualChoiceRoom(t)
	r.Game.Seats[0].Library = []protocol.GameCard{{ID: "top-a", Name: "Public first"}, {ID: "top-b", Name: "Public second"}, {ID: "hidden-c", Name: "Secret remaining"}}
	for _, id := range []string{"host-conn", "g1", "observer"} {
		view, _ := r.GameSnapshot(id)
		if view.Seats[0].LibraryTopCard != nil {
			t.Fatal("top card was public before opt-in")
		}
	}
	if _, err := r.SetLibraryTopRevealed("observer", protocol.GameSetLibraryTopRevealed{Revealed: true}); err == nil {
		t.Fatal("spectator enabled revealing")
	}
	if _, err := r.SetLibraryTopRevealed("host-conn", protocol.GameSetLibraryTopRevealed{Revealed: true}); err != nil {
		t.Fatal(err)
	}
	for _, id := range []string{"host-conn", "g1", "observer"} {
		view, _ := r.GameSnapshot(id)
		if !view.Seats[0].LibraryTopRevealed || view.Seats[0].LibraryTopCard == nil || view.Seats[0].LibraryTopCard.Name != "Public first" {
			t.Fatal("public top missing")
		}
		encoded, _ := json.Marshal(view)
		if strings.Contains(string(encoded), "Public second") || strings.Contains(string(encoded), "Secret remaining") {
			t.Fatal("revealed beyond top")
		}
	}
	if _, err := r.Draw("host-conn", 1); err != nil {
		t.Fatal(err)
	}
	view, _ := r.GameSnapshot("observer")
	if view.Seats[0].LibraryTopCard.Name != "Public second" || len(view.Seats[0].Hand) > 0 {
		t.Fatal("top did not update privately after draw")
	}
	if _, err := r.ShuffleLibrary("host-conn"); err != nil {
		t.Fatal(err)
	}
	view, _ = r.GameSnapshot("g1")
	if view.Seats[0].LibraryTopCard.ID != r.Game.Seats[0].Library[0].ID {
		t.Fatal("top did not update after shuffle")
	}
	if _, err := r.SetLibraryTopRevealed("host-conn", protocol.GameSetLibraryTopRevealed{Revealed: false}); err != nil {
		t.Fatal(err)
	}
	view, _ = r.GameSnapshot("observer")
	if view.Seats[0].LibraryTopCard != nil || view.Seats[0].LibraryTopRevealed {
		t.Fatal("disabled reveal retained top")
	}
	if _, err := r.SetLibraryTopRevealed("host-conn", protocol.GameSetLibraryTopRevealed{Revealed: true}); err != nil {
		t.Fatal(err)
	}
	if _, err := r.Draw("host-conn", 100); err != nil {
		t.Fatal(err)
	}
	view, _ = r.GameSnapshot("observer")
	if view.Seats[0].LibraryTopCard != nil || !view.Seats[0].LibraryTopRevealed {
		t.Fatal("empty library must retain mode without stale card")
	}
}

func TestTwoPlayerEDHStartsAtFortyLifeWithOpenSeatsExcluded(t *testing.T) {
	r := newTestRoom(t, 4, true)
	if _, err := r.Join("g1", "Guest", false, ""); err != nil {
		t.Fatal(err)
	}
	for _, id := range []string{"host-conn", "g1"} {
		if _, err := r.SelectDeck(id, testDeck(protocol.FormatEDH)); err != nil {
			t.Fatal(err)
		}
		if _, err := r.SetReady(id, true); err != nil {
			t.Fatal(err)
		}
	}
	for _, id := range []string{"host-conn", "g1"} {
		if _, err := r.CompleteLoad(id, r.LoadID); err != nil {
			t.Fatal(err)
		}
	}
	view, err := r.GameSnapshot("host-conn")
	if err != nil {
		t.Fatal(err)
	}
	if len(view.Seats) != 2 || len(view.TurnOrder) != 2 || view.Seats[0].Life != 40 || view.Seats[1].Life != 40 || !r.Game.Seats[2].Eliminated || !r.Game.Seats[3].Eliminated {
		t.Fatalf("incorrect 2-player EDH state: %+v", view)
	}
	if _, err := r.Join("late", "Late", false, ""); err == nil {
		t.Fatal("late join allowed after 2-player start")
	}
}
