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

func rulesLogTestRoom(t *testing.T) *Room {
	t.Helper()
	r, err := NewWithRulesMode("RULES1", "Rules", protocol.FormatModern,
		protocol.MatchBO1, protocol.CardLoadBackground, protocol.RulesModeForge,
		2, true, false, "Alice", "alice", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	r.Seats[1] = Seat{Occupied: true, DisplayName: "Bob", ConnectionID: "bob"}
	r.Spectators = []Spectator{{DisplayName: "Observer", ConnectionID: "observer"}}
	r.Phase = protocol.RoomPhaseStarted
	r.ResetRulesLog()
	return r
}

func rulesPublicLogFixture() protocol.RulesGameSnapshot {
	card := func(id, name string, down bool) protocol.RulesCardState {
		return protocol.RulesCardState{ID: id, OwnerSeat: 0, ControllerSeat: 0,
			Visible: true, FaceDown: down, Identity: &protocol.RulesCardIdentity{Name: name}}
	}
	return protocol.RulesGameSnapshot{
		RoomID: "RULES1", GameID: "RULES1-1", Turn: 1, Step: "main1",
		ActiveSeat: 0, Players: []protocol.RulesPlayerState{
			{Seat: 0, Life: 20, Status: "playing"}, {Seat: 1, Life: 20, Status: "playing"},
		}, Zones: []protocol.RulesZoneState{
			{Zone: "hand", OwnerSeat: 0, Count: 7, Cards: []protocol.RulesCardState{card("h", "SECRET HAND", false)}},
			{Zone: "library", OwnerSeat: 0, Count: 53, Cards: []protocol.RulesCardState{card("l", "SECRET LIBRARY", false)}},
			{Zone: "sideboard", OwnerSeat: 0, Count: 15, Cards: []protocol.RulesCardState{card("s", "SECRET SIDEBOARD", false)}},
			{Zone: "battlefield", OwnerSeat: 0, Count: 2, Cards: []protocol.RulesCardState{
				card("land", "Forest", false), card("morph", "SECRET MORPH", true),
			}},
		}, Stack: []protocol.RulesStackObject{{ID: "spell", ControllerSeat: 0,
			Identity: protocol.RulesCardIdentity{Name: "SECRET STACK"}, Text: "SECRET TEXT"}},
	}
}

func TestRulesPublicLogExcludesAllPrivateIdentityAndDeduplicates(t *testing.T) {
	r := rulesLogTestRoom(t)
	snapshot := rulesPublicLogFixture()
	r.ObserveRulesPublicState(snapshot)
	firstCount := len(r.RulesLog)
	if firstCount < 3 {
		t.Fatal("missing public observations")
	}
	r.ObserveRulesPublicState(snapshot)
	if len(r.RulesLog) != firstCount {
		t.Fatal("an unchanged viewer publication duplicated the journal")
	}
	snapshot.Players[0].Life = 17
	snapshot.Zones[0].Count = 6
	snapshot.Zones[3].Cards[0].Tapped = true
	r.ObserveRulesPublicState(snapshot)
	data, _ := json.Marshal(r.RulesLog)
	for _, forbidden := range []string{"SECRET", "morph", "\"h\"", "\"l\""} {
		if strings.Contains(string(data), forbidden) {
			t.Fatalf("journal leaked %q: %s", forbidden, data)
		}
	}
	for _, public := range []string{"Forest", "a face-down card", "life 20 → 17", "hand count 7 → 6", "Forest tapped"} {
		if !strings.Contains(string(data), public) {
			t.Fatalf("journal omitted %q: %s", public, data)
		}
	}
	if r.Game != nil {
		t.Fatal("public observation created a manual game")
	}
}

func TestRulesPublicLogNextGameResetAndTerminalObservation(t *testing.T) {
	r := rulesLogTestRoom(t)
	snapshot := rulesPublicLogFixture()
	r.ObserveRulesPublicState(snapshot)
	winner := 1
	snapshot.GameOver, snapshot.WinnerSeat = true, &winner
	r.ObserveRulesPublicState(snapshot)
	previousID := r.RulesNextLogID
	r.Score[1] = 1
	snapshot.GameID, snapshot.GameOver, snapshot.WinnerSeat = "RULES1-2", false, nil
	r.ObserveRulesPublicState(snapshot)
	if r.RulesNextLogID <= previousID {
		t.Fatal("next game reset monotonic log ids")
	}
	data, _ := json.Marshal(r.RulesLog)
	if !strings.Contains(string(data), "Bob won the game") ||
		!strings.Contains(string(data), "Game 2 started") {
		t.Fatalf("missing result/game boundary: %s", data)
	}
	r.ResetRulesLog()
	if len(r.RulesLog) != 0 || r.RulesNextLogID != 1 || r.rulesPublicLog != nil {
		t.Fatal("new match retained old public journal")
	}
}

func TestRulesPublicLogBoundsAndOwnerIndependentProjection(t *testing.T) {
	r := rulesLogTestRoom(t)
	for i := 0; i < protocol.MaxRetainedGameLog+5; i++ {
		r.AppendRulesLog("rules_phase", 0, "Public activity.")
	}
	if len(r.RulesLog) != protocol.MaxRetainedGameLog || r.RulesLog[0].ID != 6 {
		t.Fatalf("unbounded journal: %d", len(r.RulesLog))
	}
	log, start, truncated := r.RulesLogProjection()
	if len(log) != protocol.MaxProjectedGameLog || !truncated || start != log[0].ID {
		t.Fatalf("projection bounds: %d %d %v", len(log), start, truncated)
	}
	log[0].Text = "tampered"
	if r.RulesLog[len(r.RulesLog)-len(log)].Text == "tampered" {
		t.Fatal("projection aliases live journal")
	}
}

func TestRulesChatMembershipValidationAndTerminalShell(t *testing.T) {
	r := rulesLogTestRoom(t)
	for _, conn := range []string{"alice", "bob", "observer"} {
		result, err := r.SayRules(conn, protocol.GameSay{Message: "Hello"})
		if err != nil || result.Reply == nil || !result.ProjectGame {
			t.Fatalf("chat %s: %+v %v", conn, result, err)
		}
	}
	for _, test := range []struct{ conn, message string }{
		{"outsider", "Hello"}, {"alice", ""}, {"alice", "a\nb"},
		{"alice", strings.Repeat("x", protocol.MaxGameSayRunes+1)},
	} {
		before := r.RulesNextLogID
		if _, err := r.SayRules(test.conn, protocol.GameSay{Message: test.message}); err == nil || r.RulesNextLogID != before {
			t.Fatalf("accepted invalid chat or mutated journal: %+v", test)
		}
	}
	r.Game = &GameState{Result: &protocol.GameResult{MatchFinished: true}}
	if _, err := r.SayRules("observer", protocol.GameSay{Message: "Good game"}); err != nil {
		t.Fatal(err)
	}
	if len(r.Game.Log) != len(r.RulesLog) || r.Game.NextLogID != r.RulesNextLogID {
		t.Fatal("terminal retention shell lost public chat")
	}
	r.Phase = protocol.RoomPhaseWaiting
	if _, err := r.SayRules("alice", protocol.GameSay{Message: "stale"}); err == nil {
		t.Fatal("accepted game chat after return to waiting")
	}
}
