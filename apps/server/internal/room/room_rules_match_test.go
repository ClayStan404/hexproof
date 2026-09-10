// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
)

func newRulesMatch(t *testing.T, format string) *Room {
	t.Helper()
	r, err := NewWithRulesMode("FORGE3", "Rules match", format, protocol.MatchBO3,
		protocol.CardLoadBackground, protocol.RulesModeForge, 2, true, false,
		"Alice", "alice", testNow)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := r.Join("bob", "Bob", false, ""); err != nil {
		t.Fatal(err)
	}
	if _, err := r.Join("observer", "Observer", true, ""); err != nil {
		t.Fatal(err)
	}
	for index, conn := range []string{"alice", "bob"} {
		land, spell := "Forest", "Grizzly Bears"
		if index == 1 {
			land, spell = "Mountain", "Lightning Bolt"
		}
		deck := protocol.DeckSelect{Name: "Private deck", Format: format, DeckFormat: r.DeckFormat,
			Mainboard: []protocol.DeckCard{{Name: land, Count: 60, SetCode: "TST", CollectorNumber: "1"}},
			Sideboard: []protocol.DeckCard{{Name: spell, Count: 1, SetCode: "TST", CollectorNumber: "2"}},
		}
		if format == protocol.FormatDuel {
			deck.Commander = land
			deck.Commanders = []string{land}
		}
		if _, err := r.SelectDeck(conn, deck); err != nil {
			t.Fatal(err)
		}
		ready, err := r.SetReady(conn, true)
		if err != nil || index == 1 && !ready.StartRulesGame {
			t.Fatalf("rules ready: %+v %v", ready, err)
		}
	}
	if r.Game != nil {
		t.Fatal("rules match created manual game state")
	}
	return r
}

func TestRulesBO3CommitsSideboardStartsFreshEngineAndEndsAtTwoWins(t *testing.T) {
	r := newRulesMatch(t, protocol.FormatModern)
	r.SpectatorsSeeHands = true // This must never grant sideboard identities.
	first := r.LoadID
	result, err := r.CompleteRulesGame(1, testNow)
	if err != nil || result.SideboardDeadline != testNow.Add(5*time.Minute) ||
		r.Game.Result.MatchFinished || r.Game.Number != 1 || r.Score[1] != 1 {
		t.Fatalf("first game result: %+v %v", result, err)
	}
	for _, conn := range []string{"alice", "bob", "observer"} {
		view, err := r.RulesGameSnapshot(conn)
		if err != nil || view.Sideboard == nil || view.Result == nil || view.Result.MatchFinished {
			t.Fatalf("missing sideboard metadata for %s: %+v %v", conn, view, err)
		}
		data, _ := json.Marshal(view)
		if conn != "alice" && (strings.Contains(string(data), "Forest") || strings.Contains(string(data), "Grizzly Bears")) {
			t.Fatalf("private Alice partition leaked to %s", conn)
		}
		if conn != "bob" && (strings.Contains(string(data), "Mountain") || strings.Contains(string(data), "Lightning Bolt")) {
			t.Fatalf("private Bob partition leaked to %s", conn)
		}
	}
	move := protocol.SideboardMove{FromZone: protocol.SideboardZoneSide, ToZone: protocol.SideboardZoneMain,
		Name: "Grizzly Bears", SetCode: "TST", CollectorNumber: "2"}
	if _, err := r.MoveSideboard("observer", move); err == nil {
		t.Fatal("spectator changed a registered partition")
	}
	if _, err := r.MoveSideboard("alice", move); err != nil {
		t.Fatal(err)
	}
	if len(r.Seats[0].Deck.Mainboard) != 1 {
		t.Fatal("pending partition committed before both players ready")
	}
	if _, err := r.SetSideboardReady("alice", true); err != nil {
		t.Fatal(err)
	}
	ready, err := r.SetSideboardReady("bob", true)
	if err != nil || !ready.StartRulesGame || ready.ProjectGame || r.Game != nil ||
		r.LoadID <= first || r.RulesStartingSeat == nil || *r.RulesStartingSeat != 0 ||
		len(r.Seats[0].Deck.Mainboard) != 2 {
		t.Fatalf("next game must use new engine session and previous loser: %+v %v", ready, err)
	}
	active, err := r.RulesGameSnapshot("alice")
	if err != nil || active.GameNumber != 2 || active.Sideboard != nil || active.Result != nil || active.Score[1] != 1 {
		t.Fatalf("active metadata retained the old sideboard: %+v %v", active, err)
	}
	final, err := r.CompleteRulesGame(1, testNow.Add(time.Minute))
	if err != nil || !r.Game.Result.MatchFinished || r.Game.Sideboard != nil ||
		r.Score[1] != 2 || !final.SideboardDeadline.IsZero() {
		t.Fatalf("match did not finish at 2 wins: %+v %v", final, err)
	}
	if _, err := r.ReturnToRoom("observer"); err != nil {
		t.Fatal(err)
	}
	if len(r.Seats[0].Deck.Mainboard) != 1 || len(r.Seats[0].Deck.Sideboard) != 1 {
		t.Fatal("return to room did not restore originally registered partitions")
	}
}

func TestRulesSideboardTimeoutUsesPreviousCommittedDeckAndDrawHasNoLoser(t *testing.T) {
	r := newRulesMatch(t, protocol.FormatModern)
	if _, err := r.CompleteRulesGame(-1, testNow); err != nil {
		t.Fatal(err)
	}
	if r.DrawnGames != 1 || r.Game.Sideboard.PreviousLoser != -1 {
		t.Fatal("draw awarded a win or a fixed next starting player")
	}
	if _, err := r.MoveSideboard("alice", protocol.SideboardMove{
		FromZone: protocol.SideboardZoneSide, ToZone: protocol.SideboardZoneMain,
		Name: "Grizzly Bears", SetCode: "TST", CollectorNumber: "2",
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := r.SetSideboardReady("alice", true); err != nil {
		t.Fatal(err)
	}
	if _, err := r.ExpireSideboard(testNow.Add(5*time.Minute - time.Millisecond)); err == nil {
		t.Fatal("sideboard expired before its deadline")
	}
	result, err := r.ExpireSideboard(testNow.Add(5 * time.Minute))
	if err != nil || !result.StartRulesGame || r.Game != nil || r.RulesStartingSeat != nil ||
		len(r.Seats[0].Deck.Mainboard) != 1 || len(r.Seats[0].Deck.Sideboard) != 1 {
		t.Fatalf("timeout did not restore previous split: %+v %v", result, err)
	}
}

func TestRulesDuelSideboardKeepsCardsAndRestartKeepsScoreAndFirstPlayer(t *testing.T) {
	r := newRulesMatch(t, protocol.FormatDuel)
	if _, err := r.CompleteRulesGame(0, testNow); err != nil {
		t.Fatal(err)
	}
	if _, err := r.MoveSideboard("alice", protocol.SideboardMove{
		FromZone: protocol.SideboardZoneSide, ToZone: protocol.SideboardZoneMain,
		Name: "Grizzly Bears", SetCode: "TST", CollectorNumber: "2",
	}); err == nil {
		t.Fatal("Duel Commander allowed card movement")
	}
	if _, err := r.SetSideboardCommander("alice", protocol.SideboardSetCommander{Name: "Forest", Designated: true}); err != nil {
		t.Fatal(err)
	}
	for _, conn := range []string{"alice", "bob"} {
		if _, err := r.SetSideboardReady(conn, true); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := r.RestartRulesGame("bob"); err == nil {
		t.Fatal("guest restarted a rules game")
	}
	if _, err := r.RestartRulesGame("observer"); err == nil {
		t.Fatal("observer restarted a rules game")
	}
	generation := r.LoadID
	result, err := r.RestartRulesGame("alice")
	if err != nil || !result.StartRulesGame || r.LoadID <= generation || r.Game != nil ||
		r.Score[0] != 1 || r.rulesGameNumber() != 2 || *r.RulesStartingSeat != 1 {
		t.Fatalf("restart changed match state: %+v %v", result, err)
	}
	if len(result.Broadcast) != 2 || result.Broadcast[0].Type != protocol.TypeGameRestarted ||
		result.Broadcast[0].ID != "" || result.Broadcast[0].SeqValue() <= 0 ||
		result.Broadcast[1].Type != protocol.TypeRoomSnapshot ||
		result.Broadcast[1].SeqValue() <= result.Broadcast[0].SeqValue() {
		t.Fatalf("Forge restart omitted its ordered room-wide lifecycle event: %+v", result.Broadcast)
	}
}
