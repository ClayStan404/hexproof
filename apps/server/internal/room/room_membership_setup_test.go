// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
)

func TestErrorCodeRejectsArbitraryErrors(t *testing.T) {
	typed := newError(protocol.ErrInvalidMove)
	if code, ok := ErrorCode(typed); !ok || code != protocol.ErrInvalidMove {
		t.Fatalf("ErrorCode(typed) = %q, %t", code, ok)
	}
	if code, ok := ErrorCode(errors.New(protocol.ErrInvalidMove)); ok || code != "" {
		t.Fatalf("ErrorCode(arbitrary) = %q, %t", code, ok)
	}
}

func newTestRoom(t *testing.T, maxSeats int, allowSpec bool) *Room {
	t.Helper()
	r, err := New("ABCDEF", "Friday EDH", protocol.FormatEDH, protocol.MatchBO3,
		protocol.CardLoadPreload, maxSeats, allowSpec, false, "Host", "host-conn", testNow)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	return r
}

func TestNewHostTakesSeatZero(t *testing.T) {
	r := newTestRoom(t, 4, true)
	if r.HostSeat != 0 || !r.Seats[0].Host || !r.Seats[0].Occupied {
		t.Fatalf("host seat 0 not set: %+v", r.Seats[0])
	}
	if r.PlayerCount() != 1 {
		t.Fatalf("playerCount = %d, want 1", r.PlayerCount())
	}
	if r.MatchMode != protocol.MatchBO1 {
		t.Fatalf("EDH matchMode = %q, want %q", r.MatchMode, protocol.MatchBO1)
	}
}

func TestNewWithRulesModeKeepsAuthorityInPublicProjections(t *testing.T) {
	r, err := NewWithRulesMode("FORGE1", "Rules table", protocol.FormatModern,
		protocol.MatchBO1, protocol.CardLoadPreload, protocol.RulesModeForge,
		2, true, false, "Host", "host-conn", testNow)
	if err != nil {
		t.Fatalf("NewWithRulesMode: %v", err)
	}
	if r.RulesMode != protocol.RulesModeForge ||
		r.MatchMode != protocol.MatchBO1 ||
		r.Snapshot().RulesMode != protocol.RulesModeForge ||
		r.ListEntry().RulesMode != protocol.RulesModeForge {
		t.Fatalf("rules mode was not preserved: room=%q snapshot=%q list=%q",
			r.RulesMode, r.Snapshot().RulesMode, r.ListEntry().RulesMode)
	}

	bo3, err := NewWithRulesMode("FORGE3", "Rules table", protocol.FormatModern,
		protocol.MatchBO3, protocol.CardLoadPreload, protocol.RulesModeForge,
		2, true, false, "Host", "host-conn", testNow)
	if err != nil || bo3.MatchMode != protocol.MatchBO1 {
		t.Fatalf("Forge BO3 normalization = %+v, %v", bo3, err)
	}

	if _, err := NewWithRulesMode("BADMOD", "Bad rules", protocol.FormatModern,
		protocol.MatchBO1, protocol.CardLoadPreload, "unknown", 2, true, false,
		"Host", "host-conn", testNow); err == nil {
		t.Fatal("NewWithRulesMode accepted an unknown rules mode")
	} else if code, ok := ErrorCode(err); !ok || code != protocol.ErrInvalidRulesMode {
		t.Fatalf("rules mode error = %v (%q, %t)", err, code, ok)
	}
}

func TestCompleteRulesGameCreatesOnlyTerminalMatchShell(t *testing.T) {
	r, err := NewWithRulesMode("FORGE1", "Rules table", protocol.FormatModern,
		protocol.MatchBO1, protocol.CardLoadBackground, protocol.RulesModeForge,
		2, true, false, "Host", "host-conn", testNow)
	if err != nil {
		t.Fatalf("NewWithRulesMode: %v", err)
	}
	if _, err := r.Join("guest-conn", "Guest", false, ""); err != nil {
		t.Fatalf("Join: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	result, err := r.CompleteRulesGame(1, testNow.Add(time.Minute))
	if err != nil {
		t.Fatalf("CompleteRulesGame: %v", err)
	}
	if r.Game == nil || r.Game.Result == nil ||
		r.Game.Result.Reason != protocol.GameResultRules ||
		r.Game.Result.WinnerSeat != 1 || !r.Game.Result.MatchFinished ||
		r.Score[1] != 1 || len(result.Broadcast) != 1 {
		t.Fatalf("completed Forge room = game %+v score %v result %+v",
			r.Game, r.Score, result)
	}
	if len(r.Game.Seats[0].Hand) != 0 || len(r.Game.Seats[0].Library) != 0 {
		t.Fatal("Forge completion copied card state into the manual reducer")
	}
	if _, err := r.CompleteRulesGame(0, testNow.Add(2*time.Minute)); err == nil {
		t.Fatal("CompleteRulesGame accepted a duplicate terminal result")
	}
}

func TestForgePreloadStartDefersGameStateToExternalEngine(t *testing.T) {
	r, err := NewWithRulesMode("FORGE1", "Rules table", protocol.FormatModern,
		protocol.MatchBO1, protocol.CardLoadPreload, protocol.RulesModeForge,
		2, true, false, "Host", "host-conn", testNow)
	if err != nil {
		t.Fatalf("NewWithRulesMode: %v", err)
	}
	if _, err := r.Join("guest-conn", "Guest", false, ""); err != nil {
		t.Fatalf("Join: %v", err)
	}
	for _, connectionID := range []string{"host-conn", "guest-conn"} {
		if _, err := r.SelectDeck(connectionID, testDeck(protocol.FormatModern)); err != nil {
			t.Fatalf("SelectDeck(%s): %v", connectionID, err)
		}
		if _, err := r.SetReady(connectionID, true); err != nil {
			t.Fatalf("SetReady(%s): %v", connectionID, err)
		}
	}
	if r.Phase != protocol.RoomPhaseLoading || r.Game != nil {
		t.Fatalf("preload Forge room = phase %q game %+v", r.Phase, r.Game)
	}
	if _, err := r.CompleteLoad("host-conn", r.LoadID); err != nil {
		t.Fatalf("CompleteLoad(host): %v", err)
	}
	started, err := r.CompleteLoad("guest-conn", r.LoadID)
	if err != nil {
		t.Fatalf("CompleteLoad(guest): %v", err)
	}
	if r.Phase != protocol.RoomPhaseStarted || r.Game != nil ||
		started.ProjectGame || !started.StartRulesGame {
		t.Fatalf("started Forge room = phase %q game %+v project=%v startRules=%v",
			r.Phase, r.Game, started.ProjectGame, started.StartRulesGame)
	}
	players, err := r.RulesStartPlayers()
	if err != nil || len(players) != 2 || players[0].Deck.Mainboard[0].Name != "Sol Ring" {
		t.Fatalf("RulesStartPlayers() = %+v, %v", players, err)
	}
	reset := r.ResetRulesStartFailure()
	if r.Phase != protocol.RoomPhaseWaiting || r.Seats[0].Ready ||
		r.Seats[1].Ready || len(reset.Broadcast) != 1 {
		t.Fatalf("ResetRulesStartFailure = phase %q seats %+v result %+v",
			r.Phase, r.Seats, reset)
	}
}

func TestForgeBackgroundStartDefersGameStateToExternalEngine(t *testing.T) {
	r, err := NewWithRulesMode("FORGE2", "Rules table", protocol.FormatModern,
		protocol.MatchBO1, protocol.CardLoadBackground, protocol.RulesModeForge,
		2, true, false, "Host", "host-conn", testNow)
	if err != nil {
		t.Fatalf("NewWithRulesMode: %v", err)
	}
	_, _ = r.Join("guest-conn", "Guest", false, "")
	for _, connectionID := range []string{"host-conn", "guest-conn"} {
		_, _ = r.SelectDeck(connectionID, testDeck(protocol.FormatModern))
	}
	if _, err := r.SetReady("host-conn", true); err != nil {
		t.Fatalf("SetReady(host): %v", err)
	}
	started, err := r.SetReady("guest-conn", true)
	if err != nil {
		t.Fatalf("SetReady(guest): %v", err)
	}
	if r.Phase != protocol.RoomPhaseStarted || r.Game != nil ||
		started.ProjectGame || !started.StartRulesGame {
		t.Fatalf("background Forge start = phase %q game %+v project=%v startRules=%v",
			r.Phase, r.Game, started.ProjectGame, started.StartRulesGame)
	}
}

func TestPlaytestStartsWithOneSeat(t *testing.T) {
	r, err := New("SOLO12", "Solo playtest", protocol.FormatModern, protocol.MatchBO3,
		protocol.CardLoadPreload, 1, true, false, "Host", "host-conn", testNow)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	if !r.Playtest || r.MaxSeats != 1 || r.AllowSpectators ||
		r.MatchMode != protocol.MatchBO1 {
		t.Fatalf("playtest settings = %+v", r)
	}
	if _, err := r.Join("spectator", "Spectator", true, ""); err == nil ||
		err.Error() != protocol.ErrSpectatorsNotAllowed {
		t.Fatalf("spectator join error = %v, want %s", err, protocol.ErrSpectatorsNotAllowed)
	}

	deck := testDeck(protocol.FormatModern)
	if _, err := r.SelectDeck("host-conn", deck); err != nil {
		t.Fatalf("SelectDeck: %v", err)
	}
	ready, err := r.SetReady("host-conn", true)
	if err != nil {
		t.Fatalf("SetReady: %v", err)
	}
	loadRequired := false
	for _, envelope := range ready.Broadcast {
		if envelope.Type == protocol.TypeMatchLoadRequired {
			loadRequired = true
			break
		}
	}
	if r.Phase != protocol.RoomPhaseLoading || !loadRequired {
		t.Fatalf("phase = %q, loadRequired = %v", r.Phase, loadRequired)
	}
	if _, err := r.CompleteLoad("host-conn", r.LoadID); err != nil {
		t.Fatalf("CompleteLoad: %v", err)
	}
	if r.Phase != protocol.RoomPhaseStarted || r.Game == nil ||
		len(r.Game.Seats) != 1 || r.Game.ActiveSeat != 0 {
		t.Fatalf("playtest game = %+v", r.Game)
	}
}

func TestJoinPlayerFillsSeat(t *testing.T) {
	r := newTestRoom(t, 4, true)
	res, err := r.Join("g1", "Guest1", false, "")
	if err != nil {
		t.Fatalf("join: %v", err)
	}
	if res.Reply == nil || res.Reply.Type != protocol.TypeRoomJoined {
		t.Fatalf("reply = %+v", res.Reply)
	}
	var joined protocol.RoomJoined
	if err := res.Reply.DecodePayload(&joined); err != nil {
		t.Fatalf("decode joined: %v", err)
	}
	if joined.Role != "player" || joined.Seat == nil || *joined.Seat != 1 {
		t.Fatalf("joined = %+v, want role=player seat=1", joined)
	}
	if r.PlayerCount() != 2 {
		t.Fatalf("playerCount = %d, want 2", r.PlayerCount())
	}
	// snapshot broadcast present with 1-based seq
	if len(res.Broadcast) != 1 || res.Broadcast[0].Type != protocol.TypeRoomSnapshot {
		t.Fatalf("broadcast = %+v", res.Broadcast)
	}
	if !res.Broadcast[0].HasSeq() || res.Broadcast[0].SeqValue() != 1 {
		t.Fatalf("snapshot seq = %v, want 1", res.Broadcast[0].SeqValue())
	}
}

func TestJoinSpectator(t *testing.T) {
	r := newTestRoom(t, 2, true)
	res, err := r.Join("s1", "Spec1", true, "")
	if err != nil {
		t.Fatalf("spectator join: %v", err)
	}
	var joined protocol.RoomJoined
	_ = res.Reply.DecodePayload(&joined)
	if joined.Role != "spectator" || joined.Seat != nil {
		t.Fatalf("spectator joined = %+v", joined)
	}
	if len(r.Spectators) != 1 {
		t.Fatalf("spectators = %d", len(r.Spectators))
	}
}

func TestJoinSpectatorDisallowed(t *testing.T) {
	r := newTestRoom(t, 2, false)
	_, err := r.Join("s1", "Spec1", true, "")
	if err == nil || err.Error() != protocol.ErrSpectatorsNotAllowed {
		t.Fatalf("err = %v, want %q", err, protocol.ErrSpectatorsNotAllowed)
	}
}

func TestJoinSpectatorLimit(t *testing.T) {
	r := newTestRoom(t, 2, true)
	for i := 0; i < protocol.MaxSpectators; i++ {
		if _, err := r.Join("s"+itoa(i), "Spec"+itoa(i), true, ""); err != nil {
			t.Fatalf("fill spectator %d: %v", i, err)
		}
	}
	if _, err := r.Join("s9", "Spec9", true, ""); err == nil || err.Error() != protocol.ErrSpectatorLimit {
		t.Fatalf("9th spectator err = %v, want %q", err, protocol.ErrSpectatorLimit)
	}
}

func TestJoinPlayerRoomFull(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join g1: %v", err)
	}
	// seats 0,1 now full
	if _, err := r.Join("g2", "Guest2", false, ""); err == nil || err.Error() != protocol.ErrRoomFull {
		t.Fatalf("join full err = %v, want %q", err, protocol.ErrRoomFull)
	}
}

func TestStartedMatchRejectsPlayerJoinButAllowsSpectator(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Phase = protocol.RoomPhaseStarted

	if _, err := r.Join("g1", "Guest1", false, ""); err == nil || err.Error() != protocol.ErrMatchStarted {
		t.Fatalf("player join err = %v, want %q", err, protocol.ErrMatchStarted)
	}
	if _, err := r.Join("s1", "Spec1", true, ""); err != nil {
		t.Fatalf("spectator join: %v", err)
	}
}

func TestJoinAlreadyInRoom(t *testing.T) {
	r := newTestRoom(t, 4, true)
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join g1: %v", err)
	}
	if _, err := r.Join("g1", "Guest1", false, ""); err == nil || err.Error() != protocol.ErrAlreadyInRoom {
		t.Fatalf("rejoin err = %v, want %q", err, protocol.ErrAlreadyInRoom)
	}
}

func TestTournamentParticipantCannotOccupyBothSeats(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Seats[0].TournamentParticipantID = "p-1"

	if _, err := r.JoinTournamentParticipant("conn-rebound", "Alice", "p-1"); err == nil || err.Error() != protocol.ErrAlreadyInRoom {
		t.Fatalf("duplicate participant join = %v", err)
	}
	if r.PlayerCount() != 1 {
		t.Fatalf("player count after duplicate join = %d", r.PlayerCount())
	}
	if _, err := r.JoinTournamentParticipant("conn-b", "Bob", "p-2"); err != nil {
		t.Fatalf("distinct participant join: %v", err)
	}
	if r.PlayerCount() != 2 || r.Seats[1].TournamentParticipantID != "p-2" {
		t.Fatalf("second tournament seat = %+v", r.Seats[1])
	}
}

func TestLeaveFreesSeat(t *testing.T) {
	r := newTestRoom(t, 4, true)
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join g1: %v", err)
	}
	res, err := r.Leave("g1")
	if err != nil {
		t.Fatalf("leave: %v", err)
	}
	if res.Reply.Type != protocol.TypeRoomLeft {
		t.Fatalf("reply = %+v", res.Reply)
	}
	if r.PlayerCount() != 1 {
		t.Fatalf("playerCount after leave = %d, want 1", r.PlayerCount())
	}
	// snapshot broadcast (not disbanded)
	if res.Broadcast[0].Type != protocol.TypeRoomSnapshot {
		t.Fatalf("broadcast = %+v", res.Broadcast[0])
	}
}

func TestStartedModernLeaveForfeitsWholeMatch(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Format = protocol.FormatModern
	r.MatchMode = protocol.MatchBO3
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join g1: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Score = []int{1, 0}
	r.Game = &GameState{
		Number:       2,
		StartingSeat: 1,
		ActiveSeat:   1,
		CurrentPhase: protocol.GamePhaseSecondMain,
		Seats: []PlayerGameState{
			{Seat: 0, DisplayName: "Host"},
			{Seat: 1, DisplayName: "Guest1"},
		},
		Log:       []protocol.GameLogEntry{},
		NextLogID: 1,
	}

	result, err := r.Leave("g1")
	if err != nil {
		t.Fatalf("leave started match: %v", err)
	}
	if !result.ProjectGame || result.Reply == nil ||
		result.Reply.Type != protocol.TypeRoomLeft ||
		r.Seats[1].Occupied {
		t.Fatalf("leave result/seat = %+v / %+v", result, r.Seats[1])
	}
	if r.Game.Result == nil ||
		r.Game.Result.Reason != protocol.GameResultDeparture ||
		r.Game.Result.WinnerSeat != 0 ||
		r.Game.Result.ConcededSeat != 1 ||
		!r.Game.Result.MatchFinished ||
		r.Game.ActiveSeat != -1 ||
		r.Score[0] != 2 ||
		r.Game.Sideboard != nil {
		t.Fatalf("departure game/score = %+v / %+v", r.Game, r.Score)
	}
	if len(r.Game.Log) != 1 ||
		r.Game.Log[0].Kind != "departure" ||
		r.Game.Log[0].Text != "Guest1 left the match. Host wins." {
		t.Fatalf("departure log = %+v", r.Game.Log)
	}
}

func TestStartedModernSideboardDepartureForfeitsWholeMatch(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Format = protocol.FormatModern
	r.MatchMode = protocol.MatchBO3
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join g1: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Score = []int{0, 1}
	r.Game = &GameState{
		Number: 1,
		Result: &protocol.GameResult{
			Reason: protocol.GameResultConcede, WinnerSeat: 1,
			ConcededSeat: 0, MatchFinished: false,
		},
		Seats: []PlayerGameState{
			{Seat: 0, DisplayName: "Host"},
			{Seat: 1, DisplayName: "Guest1"},
		},
		Log:       []protocol.GameLogEntry{},
		NextLogID: 1,
		Sideboard: &SideboardState{
			Deadline:      testNow.Add(5 * time.Minute),
			PreviousLoser: 0,
			Players:       make([]SideboardPlayerState, 2),
		},
	}

	result, empty, err := r.ExpireDisconnected("g1")
	if err != nil {
		t.Fatalf("expire sideboarding player: %v", err)
	}
	if empty || !result.ProjectGame ||
		r.Game.Sideboard != nil ||
		r.Game.Result == nil ||
		r.Game.Result.Reason != protocol.GameResultDeparture ||
		r.Game.Result.WinnerSeat != 0 ||
		!r.Game.Result.MatchFinished ||
		r.Score[0] != 2 {
		t.Fatalf("sideboard departure result/game/score = %+v / %+v / %+v",
			result, r.Game, r.Score)
	}
}

func TestStartedEDHDisconnectEliminatesAndAdvancesTurn(t *testing.T) {
	r := newTestRoom(t, 4, true)
	r.Format = protocol.FormatEDH
	r.MatchMode = protocol.MatchBO1
	for seat := 1; seat < 4; seat++ {
		connID := "g" + itoa(seat)
		if _, err := r.Join(connID, "Guest"+itoa(seat), false, ""); err != nil {
			t.Fatalf("join seat %d: %v", seat, err)
		}
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number:            1,
		StartingSeat:      0,
		ActiveSeat:        0,
		CurrentPhase:      protocol.GamePhaseEnd,
		LandPlaysThisTurn: 2,
		Seats: []PlayerGameState{
			{Seat: 0, DisplayName: "Host"},
			{Seat: 1, DisplayName: "Guest1"},
			{Seat: 2, DisplayName: "Guest2"},
			{Seat: 3, DisplayName: "Guest3"},
		},
		Log:       []protocol.GameLogEntry{},
		NextLogID: 1,
	}

	result, empty, err := r.ExpireDisconnected("host-conn")
	if err != nil {
		t.Fatalf("expire host: %v", err)
	}
	if empty || !result.ProjectGame || r.Seats[0].Occupied ||
		r.HostSeat != 1 || !r.Seats[1].Host {
		t.Fatalf("expiry result/room = %+v empty=%v seats=%+v host=%d",
			result, empty, r.Seats, r.HostSeat)
	}
	if !r.Game.Seats[0].Eliminated ||
		r.Game.ActiveSeat != 1 ||
		r.Game.CurrentPhase != protocol.GamePhaseUntap ||
		r.Game.LandPlaysThisTurn != 0 ||
		r.Game.Result != nil {
		t.Fatalf("EDH departure state = %+v", r.Game)
	}
}

func TestHostLeaveDisbands(t *testing.T) {
	r := newTestRoom(t, 4, true)
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join g1: %v", err)
	}
	res, err := r.Leave("host-conn")
	if err != nil {
		t.Fatalf("host leave: %v", err)
	}
	if !r.Disbanded {
		t.Fatal("room should be disbanded after host leave")
	}
	// Host reply is room.disbanded (not room.left): host initiated the disband.
	if res.Reply == nil || res.Reply.Type != protocol.TypeRoomDisbanded {
		t.Fatalf("host reply = %+v, want room.disbanded", res.Reply)
	}
	if res.Broadcast[0].Type != protocol.TypeRoomDisbanded {
		t.Fatalf("broadcast = %+v, want room.disbanded", res.Broadcast[0])
	}
}

func TestKickBySeatFreesSeat(t *testing.T) {
	r := newTestRoom(t, 4, true)
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join g1: %v", err)
	}
	seat := 1
	res, err := r.Kick("host-conn", &seat, nil)
	if err != nil {
		t.Fatalf("kick seat: %v", err)
	}
	if res.Reply.Type != protocol.TypeRoomKicked {
		t.Fatalf("reply = %+v", res.Reply)
	}
	if res.TargetConnID != "g1" {
		t.Fatalf("targetConnID = %q, want g1", res.TargetConnID)
	}
	if r.PlayerCount() != 1 {
		t.Fatalf("playerCount after kick = %d, want 1", r.PlayerCount())
	}
}

func TestKickDuringStartedMatchForfeitsTarget(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Format = protocol.FormatModern
	r.MatchMode = protocol.MatchBO1
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join g1: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number:       1,
		StartingSeat: 1,
		ActiveSeat:   1,
		CurrentPhase: protocol.GamePhaseUntap,
		Seats: []PlayerGameState{
			{Seat: 0, DisplayName: "Host"},
			{Seat: 1, DisplayName: "Guest1"},
		},
		Log:       []protocol.GameLogEntry{},
		NextLogID: 1,
	}

	seat := 1
	result, err := r.Kick("host-conn", &seat, nil)
	if err != nil {
		t.Fatalf("kick started player: %v", err)
	}
	if !result.ProjectGame || result.TargetConnID != "g1" ||
		r.Game.Result == nil ||
		r.Game.Result.Reason != protocol.GameResultDeparture ||
		r.Game.Result.WinnerSeat != 0 ||
		!r.Game.Result.MatchFinished {
		t.Fatalf("kick result/game = %+v / %+v", result, r.Game)
	}
}

func TestKickSpectatorByIndex(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("s1", "Spec1", true, ""); err != nil {
		t.Fatalf("spectator join: %v", err)
	}
	idx := 0
	res, err := r.Kick("host-conn", nil, &idx)
	if err != nil {
		t.Fatalf("kick spectator: %v", err)
	}
	if res.TargetConnID != "s1" {
		t.Fatalf("targetConnID = %q, want s1", res.TargetConnID)
	}
	if len(r.Spectators) != 0 {
		t.Fatalf("spectators after kick = %d", len(r.Spectators))
	}
}

func TestKickHostRejected(t *testing.T) {
	r := newTestRoom(t, 4, true)
	seat := 0 // host seat
	_, err := r.Kick("host-conn", &seat, nil)
	if err == nil || err.Error() != protocol.ErrCannotKickHost {
		t.Fatalf("kick host err = %v, want %q", err, protocol.ErrCannotKickHost)
	}
	if !r.Seats[0].Occupied {
		t.Fatal("host seat should still be occupied")
	}
}

func TestKickInvalidTarget(t *testing.T) {
	r := newTestRoom(t, 4, true)
	// both seat and spectatorIndex set -> invalid
	seat, spec := 1, 0
	if _, err := r.Kick("host-conn", &seat, &spec); err == nil ||
		err.Error() != protocol.ErrInvalidTarget {
		t.Fatalf("both-set err = %v, want %q", err, protocol.ErrInvalidTarget)
	}
	// neither set -> invalid
	if _, err := r.Kick("host-conn", nil, nil); err == nil ||
		err.Error() != protocol.ErrInvalidTarget {
		t.Fatalf("neither-set err = %v, want %q", err, protocol.ErrInvalidTarget)
	}
	// out of range seat
	seat = 99
	if _, err := r.Kick("host-conn", &seat, nil); err == nil ||
		err.Error() != protocol.ErrInvalidTarget {
		t.Fatalf("oor seat err = %v, want %q", err, protocol.ErrInvalidTarget)
	}
	// empty seat (seat 1 unoccupied)
	seat = 1
	if _, err := r.Kick("host-conn", &seat, nil); err == nil ||
		err.Error() != protocol.ErrInvalidTarget {
		t.Fatalf("empty seat err = %v, want %q", err, protocol.ErrInvalidTarget)
	}
}

func TestKickByNonHostFails(t *testing.T) {
	r := newTestRoom(t, 4, true)
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join g1: %v", err)
	}
	seat := 0
	_, err := r.Kick("g1", &seat, nil)
	if err == nil || err.Error() != protocol.ErrNotHost {
		t.Fatalf("non-host kick err = %v, want %q", err, protocol.ErrNotHost)
	}
}

func TestSnapshotProjectsPublicStructure(t *testing.T) {
	r := newTestRoom(t, 4, true)
	if _, err := r.Join("s1", "Spec1", true, ""); err != nil {
		t.Fatalf("spectator join: %v", err)
	}
	snap := r.Snapshot()
	if len(snap.Seats) != 4 || !snap.Seats[0].Host || snap.Seats[0].DisplayName != "Host" {
		t.Fatalf("seats = %+v", snap.Seats)
	}
	if len(snap.Spectators) != 1 || snap.Spectators[0].DisplayName != "Spec1" {
		t.Fatalf("spectators = %+v", snap.Spectators)
	}
	// No password hash or connection ids leak.
	if snap.HasPassword {
		t.Fatal("hasPassword should be false for no-password room")
	}
}

func TestDeckSelectionAndReadyState(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join: %v", err)
	}

	if _, err := r.SetReady("host-conn", true); err == nil || err.Error() != protocol.ErrDeckRequired {
		t.Fatalf("ready without deck err = %v, want %q", err, protocol.ErrDeckRequired)
	}
	selected, err := r.SelectDeck("host-conn", testDeck(protocol.FormatEDH))
	if err != nil {
		t.Fatalf("select deck: %v", err)
	}
	if selected.Reply == nil || selected.Reply.Type != protocol.TypeDeckSelected {
		t.Fatalf("select reply = %+v", selected.Reply)
	}
	if r.Seats[0].Deck == nil || r.Seats[0].Ready {
		t.Fatalf("host seat after select = %+v", r.Seats[0])
	}
	if !r.Snapshot().Seats[0].DeckSelected {
		t.Fatal("snapshot should expose deckSelected")
	}

	if _, err := r.SetReady("host-conn", true); err != nil {
		t.Fatalf("ready: %v", err)
	}
	if !r.Seats[0].Ready {
		t.Fatal("host should be ready")
	}
	if _, err := r.SelectDeck("host-conn", testDeck(protocol.FormatEDH)); err != nil {
		t.Fatalf("change deck: %v", err)
	}
	if r.Seats[0].Ready {
		t.Fatal("changing deck must clear ready")
	}

	projected, err := json.Marshal(r.Snapshot())
	if err != nil {
		t.Fatalf("marshal snapshot: %v", err)
	}
	for _, secret := range []string{"Test deck", "Sol Ring", "CMM", "396"} {
		if strings.Contains(string(projected), secret) {
			t.Fatalf("snapshot leaked %q: %s", secret, projected)
		}
	}
}

func TestReadyRequiresFilledSeats(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.SelectDeck("host-conn", testDeck(protocol.FormatEDH)); err != nil {
		t.Fatalf("select deck: %v", err)
	}
	if _, err := r.SetReady("host-conn", true); err == nil || err.Error() != protocol.ErrSeatsNotFilled {
		t.Fatalf("ready before full err = %v, want %q", err, protocol.ErrSeatsNotFilled)
	}
}

func TestEDHThreePlayersCanStartWithFourthSeatOpen(t *testing.T) {
	r := newTestRoom(t, 4, true)
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join first guest: %v", err)
	}
	if _, err := r.SelectDeck("host-conn", testDeck(protocol.FormatEDH)); err != nil {
		t.Fatalf("host deck: %v", err)
	}
	if _, err := r.SelectDeck("g1", testDeck(protocol.FormatEDH)); err != nil {
		t.Fatalf("first guest deck: %v", err)
	}
	if _, err := r.SetReady("host-conn", true); err == nil ||
		err.Error() != protocol.ErrSeatsNotFilled {
		t.Fatalf("two-player EDH ready error = %v, want %q",
			err, protocol.ErrSeatsNotFilled)
	}
	if _, err := r.Join("g2", "Guest2", false, ""); err != nil {
		t.Fatalf("join second guest: %v", err)
	}
	if _, err := r.SelectDeck("g2", testDeck(protocol.FormatEDH)); err != nil {
		t.Fatalf("second guest deck: %v", err)
	}

	for _, connID := range []string{"host-conn", "g1"} {
		if _, err := r.SetReady(connID, true); err != nil {
			t.Fatalf("ready %s: %v", connID, err)
		}
	}
	result, err := r.SetReady("g2", true)
	if err != nil {
		t.Fatalf("ready third player: %v", err)
	}
	if r.Phase != protocol.RoomPhaseLoading || len(result.Broadcast) != 2 ||
		result.Broadcast[1].Type != protocol.TypeMatchLoadRequired {
		t.Fatalf("three-player loading result = phase %q broadcasts %+v",
			r.Phase, result.Broadcast)
	}
	if r.Seats[3].Occupied || r.Seats[3].Loaded {
		t.Fatalf("fourth seat should remain open: %+v", r.Seats[3])
	}
	if _, err := r.Join("g3", "Late Guest", false, ""); err == nil ||
		err.Error() != protocol.ErrMatchStarted {
		t.Fatalf("join during three-player loading error = %v, want %q",
			err, protocol.ErrMatchStarted)
	}
	if r.ListEntry().PlayerJoinable {
		t.Fatal("loading three-player EDH room must not advertise an open seat")
	}

	for _, connID := range []string{"host-conn", "g1"} {
		if _, err := r.CompleteLoad(connID, r.LoadID); err != nil {
			t.Fatalf("complete load %s: %v", connID, err)
		}
	}
	started, err := r.CompleteLoad("g2", r.LoadID)
	if err != nil {
		t.Fatalf("complete third load: %v", err)
	}
	if r.Phase != protocol.RoomPhaseStarted || !started.ProjectGame ||
		r.Game == nil || len(r.Game.Seats) != 4 ||
		!r.Game.Seats[3].Eliminated || r.Game.ActiveSeat < 0 ||
		r.Game.ActiveSeat > 2 {
		t.Fatalf("three-player game = phase %q project %v game %+v",
			r.Phase, started.ProjectGame, r.Game)
	}

	snapshot, err := r.GameSnapshot("host-conn")
	if err != nil {
		t.Fatalf("three-player snapshot: %v", err)
	}
	if len(snapshot.Seats) != 3 || snapshot.Seats[0].Seat != 0 ||
		snapshot.Seats[1].Seat != 1 || snapshot.Seats[2].Seat != 2 {
		t.Fatalf("projected three-player seats = %+v", snapshot.Seats)
	}
	activeConnections := map[int]string{0: "host-conn", 1: "g1", 2: "g2"}
	previousActive := r.Game.ActiveSeat
	if _, err := r.NextTurn(activeConnections[previousActive]); err != nil {
		t.Fatalf("advance three-player turn: %v", err)
	}
	if r.Game.ActiveSeat < 0 || r.Game.ActiveSeat > 2 ||
		r.Game.ActiveSeat == previousActive {
		t.Fatalf("next active seat = %d after %d", r.Game.ActiveSeat, previousActive)
	}
}

func TestSpectatorCannotSelectDeckOrReady(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("s1", "Spec1", true, ""); err != nil {
		t.Fatalf("spectator join: %v", err)
	}
	if _, err := r.SelectDeck("s1", testDeck(protocol.FormatEDH)); err == nil || err.Error() != protocol.ErrNotPlayer {
		t.Fatalf("spectator select err = %v, want %q", err, protocol.ErrNotPlayer)
	}
	if _, err := r.SetReady("s1", true); err == nil || err.Error() != protocol.ErrNotPlayer {
		t.Fatalf("spectator ready err = %v, want %q", err, protocol.ErrNotPlayer)
	}
}

func TestDeckSelectionValidatesFormatAndCommander(t *testing.T) {
	r := newTestRoom(t, 2, true)
	wrongFormat := testDeck(protocol.FormatModern)
	if _, err := r.SelectDeck("host-conn", wrongFormat); err == nil || err.Error() != protocol.ErrInvalidDeck {
		t.Fatalf("wrong format err = %v, want %q", err, protocol.ErrInvalidDeck)
	}
	missingCommander := testDeck(protocol.FormatEDH)
	missingCommander.Commander = ""
	if _, err := r.SelectDeck("host-conn", missingCommander); err == nil || err.Error() != protocol.ErrInvalidDeck {
		t.Fatalf("missing commander err = %v, want %q", err, protocol.ErrInvalidDeck)
	}

	normalized := testDeck(protocol.FormatEDH)
	normalized.Name = "  Commander deck  "
	normalized.Commander = "  Sol Ring  "
	normalized.Mainboard[0].Name = "  Sol Ring  "
	normalized.Mainboard[0].SetCode = "  CMM  "
	normalized.Mainboard[0].CollectorNumber = "  396  "
	normalized.Mainboard[0].TypeLine = "  Artifact  "
	if _, err := r.SelectDeck("host-conn", normalized); err != nil {
		t.Fatalf("select whitespace deck: %v", err)
	}
	stored := r.Seats[0].Deck
	if stored == nil || stored.Name != "Commander deck" ||
		stored.Commander != "Sol Ring" ||
		len(stored.Commanders) != 1 || stored.Commanders[0] != "Sol Ring" ||
		stored.Mainboard[0].Name != "Sol Ring" ||
		stored.Mainboard[0].SetCode != "CMM" ||
		stored.Mainboard[0].CollectorNumber != "396" ||
		stored.Mainboard[0].TypeLine != "Artifact" {
		t.Fatalf("stored deck was not normalized: %+v", stored)
	}

	tooManyCommanders := testDeck(protocol.FormatEDH)
	tooManyCommanders.Commander = ""
	tooManyCommanders.Commanders = []string{"Sol Ring", "Arcane Signet", "Command Tower"}
	tooManyCommanders.Mainboard = append(
		tooManyCommanders.Mainboard,
		protocol.DeckCard{Name: "Arcane Signet", Count: 1, SetCode: "CMM", CollectorNumber: "379"},
		protocol.DeckCard{Name: "Command Tower", Count: 1, SetCode: "CMM", CollectorNumber: "1004"},
	)
	if _, err := r.SelectDeck("host-conn", tooManyCommanders); err == nil ||
		err.Error() != protocol.ErrInvalidDeck {
		t.Fatalf("too many commanders err = %v, want %q", err, protocol.ErrInvalidDeck)
	}
}

func TestDeckSelectionValidatesConstructionFormat(t *testing.T) {
	r, err := New("ABCDEF", "Friday Modern", protocol.FormatModern, protocol.MatchBO3,
		protocol.CardLoadPreload, 2, true, false, "Host", "host-conn", testNow)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	r.DeckFormat = protocol.DeckFormatModern
	selected := testDeck(protocol.FormatModern)
	selected.DeckFormat = protocol.DeckFormatCustom
	if _, err := r.SelectDeck("host-conn", selected); err == nil ||
		err.Error() != protocol.ErrInvalidDeck {
		t.Fatalf("construction format mismatch = %v, want %q", err, protocol.ErrInvalidDeck)
	}
	selected.DeckFormat = protocol.DeckFormatModern
	if _, err := r.SelectDeck("host-conn", selected); err != nil {
		t.Fatalf("matching Modern deck: %v", err)
	}
}

func TestDeckSelectionRejectsOperationalLimitViolations(t *testing.T) {
	r := newTestRoom(t, 2, true)
	tests := []struct {
		name string
		deck protocol.DeckSelect
	}{
		{
			name: "opening hand too small",
			deck: func() protocol.DeckSelect {
				deck := testDeck(protocol.FormatEDH)
				deck.Mainboard[0].Count = protocol.MinMainboardCards - 1
				return deck
			}(),
		},
		{
			name: "aggregate card count too large",
			deck: func() protocol.DeckSelect {
				deck := testDeck(protocol.FormatEDH)
				deck.Mainboard[0].Count = protocol.MaxDeckCards
				deck.Sideboard = []protocol.DeckCard{{Name: "Forest", Count: 1, SetCode: "M21", CollectorNumber: "272"}}
				return deck
			}(),
		},
		{
			name: "too many entries",
			deck: func() protocol.DeckSelect {
				deck := testDeck(protocol.FormatEDH)
				deck.Sideboard = make([]protocol.DeckCard, protocol.MaxDeckEntries)
				for i := range deck.Sideboard {
					deck.Sideboard[i] = protocol.DeckCard{Name: "Forest", Count: 1, SetCode: "M21", CollectorNumber: "272"}
				}
				return deck
			}(),
		},
		{
			name: "card name too long",
			deck: func() protocol.DeckSelect {
				deck := testDeck(protocol.FormatEDH)
				deck.Mainboard[0].Name = strings.Repeat("x", protocol.MaxCardNameRunes+1)
				deck.Commander = deck.Mainboard[0].Name
				return deck
			}(),
		},
		{
			name: "control character",
			deck: func() protocol.DeckSelect {
				deck := testDeck(protocol.FormatEDH)
				deck.Name = "Commander\a deck"
				return deck
			}(),
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if _, err := r.SelectDeck("host-conn", test.deck); err == nil || err.Error() != protocol.ErrInvalidDeck {
				t.Fatalf("SelectDeck error = %v, want %q", err, protocol.ErrInvalidDeck)
			}
		})
	}
}

func TestReadyStartsLoadAndAllPlayersCompleteStartsMatch(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join: %v", err)
	}
	if _, err := r.Join("s1", "Observer", true, ""); err != nil {
		t.Fatalf("spectator join: %v", err)
	}
	if _, err := r.SelectDeck("host-conn", testDeck(protocol.FormatEDH)); err != nil {
		t.Fatalf("host deck: %v", err)
	}
	guestDeck := testDeck(protocol.FormatEDH)
	guestDeck.Name = "Guest deck"
	if _, err := r.SelectDeck("g1", guestDeck); err != nil {
		t.Fatalf("guest deck: %v", err)
	}
	if _, err := r.SetReady("host-conn", true); err != nil {
		t.Fatalf("host ready: %v", err)
	}
	result, err := r.SetReady("g1", true)
	if err != nil {
		t.Fatalf("guest ready: %v", err)
	}
	if r.Phase != protocol.RoomPhaseLoading || r.LoadID != 1 {
		t.Fatalf("load state = phase %q id %d", r.Phase, r.LoadID)
	}
	if len(result.Broadcast) != 2 || result.Broadcast[1].Type != protocol.TypeMatchLoadRequired {
		t.Fatalf("ready broadcasts = %+v", result.Broadcast)
	}
	if result.Broadcast[1].SeqValue() != result.Broadcast[0].SeqValue()+1 {
		t.Fatalf("load event seq does not follow snapshot: %d -> %d",
			result.Broadcast[0].SeqValue(), result.Broadcast[1].SeqValue())
	}
	var required protocol.MatchLoadRequired
	if err := result.Broadcast[1].DecodePayload(&required); err != nil {
		t.Fatalf("decode load required: %v", err)
	}
	if required.LoadID != r.LoadID || len(required.CardKeys) != 1 {
		t.Fatalf("load required = %+v", required)
	}

	// Spectators prefetch the same resources, but never participate in the gate.
	spectator, err := r.CompleteLoad("s1", required.LoadID)
	if err != nil || spectator.Reply == nil || len(spectator.Broadcast) != 0 {
		t.Fatalf("spectator complete = result %+v err %v", spectator, err)
	}
	if r.Phase != protocol.RoomPhaseLoading {
		t.Fatalf("spectator must not start match: %q", r.Phase)
	}
	if _, err := r.CompleteLoad("host-conn", required.LoadID+1); err == nil || err.Error() != protocol.ErrStaleLoad {
		t.Fatalf("stale load err = %v, want %q", err, protocol.ErrStaleLoad)
	}
	if _, err := r.CompleteLoad("host-conn", required.LoadID); err != nil {
		t.Fatalf("host complete: %v", err)
	}
	if !r.Seats[0].Loaded || r.Phase != protocol.RoomPhaseLoading {
		t.Fatalf("after host complete = phase %q seat %+v", r.Phase, r.Seats[0])
	}
	started, err := r.CompleteLoad("g1", required.LoadID)
	if err != nil {
		t.Fatalf("guest complete: %v", err)
	}
	if r.Phase != protocol.RoomPhaseStarted || !r.Seats[1].Loaded {
		t.Fatalf("started state = phase %q seats %+v", r.Phase, r.Seats)
	}
	if len(started.Broadcast) != 2 || started.Broadcast[1].Type != protocol.TypeMatchStarted {
		t.Fatalf("start broadcasts = %+v", started.Broadcast)
	}
	if started.Broadcast[1].SeqValue() != started.Broadcast[0].SeqValue()+1 {
		t.Fatalf("started event seq does not follow snapshot: %d -> %d",
			started.Broadcast[0].SeqValue(), started.Broadcast[1].SeqValue())
	}
}

func TestBackgroundCardLoadingStartsMatchImmediately(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.CardLoadMode = protocol.CardLoadBackground
	_, _ = r.Join("g1", "Guest1", false, "")
	_, _ = r.SelectDeck("host-conn", testDeck(protocol.FormatEDH))
	_, _ = r.SelectDeck("g1", testDeck(protocol.FormatEDH))
	if _, err := r.SetReady("host-conn", true); err != nil {
		t.Fatalf("host ready: %v", err)
	}
	result, err := r.SetReady("g1", true)
	if err != nil {
		t.Fatalf("guest ready: %v", err)
	}
	if r.Phase != protocol.RoomPhaseStarted || r.Game == nil || !result.ProjectGame {
		t.Fatalf("background start = phase %q game %v project %v",
			r.Phase, r.Game != nil, result.ProjectGame)
	}
	if len(result.Broadcast) != 3 ||
		result.Broadcast[1].Type != protocol.TypeMatchLoadRequired ||
		result.Broadcast[2].Type != protocol.TypeMatchStarted {
		t.Fatalf("background broadcasts = %+v", result.Broadcast)
	}
	if _, err := r.CompleteLoad("host-conn", r.LoadID); err == nil ||
		err.Error() != protocol.ErrNotLoading {
		t.Fatalf("background completion err = %v, want %q", err, protocol.ErrNotLoading)
	}
}

func TestBackgroundSetupFailureRollsBackReady(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.CardLoadMode = protocol.CardLoadBackground
	_, _ = r.Join("g1", "Guest1", false, "")
	_, _ = r.SelectDeck("host-conn", testDeck(protocol.FormatEDH))
	_, _ = r.SelectDeck("g1", testDeck(protocol.FormatEDH))
	if _, err := r.SetReady("host-conn", true); err != nil {
		t.Fatalf("host ready: %v", err)
	}
	r.randomIndex = func(int) (int, error) {
		return 0, errors.New("entropy unavailable")
	}
	if _, err := r.SetReady("g1", true); err == nil ||
		err.Error() != protocol.ErrGameSetupFailed {
		t.Fatalf("guest ready error = %v, want %q",
			err, protocol.ErrGameSetupFailed)
	}
	if !r.Seats[0].Ready || r.Seats[1].Ready ||
		r.Phase != protocol.RoomPhaseWaiting ||
		r.LoadID != 0 || r.Game != nil {
		t.Fatalf("failed background setup state = phase %q load %d seats %+v game %+v",
			r.Phase, r.LoadID, r.Seats, r.Game)
	}
}

func TestPreloadSetupFailureReturnsRoomToWaiting(t *testing.T) {
	r := newTestRoom(t, 2, true)
	_, _ = r.Join("g1", "Guest1", false, "")
	_, _ = r.SelectDeck("host-conn", testDeck(protocol.FormatEDH))
	_, _ = r.SelectDeck("g1", testDeck(protocol.FormatEDH))
	_, _ = r.SetReady("host-conn", true)
	_, _ = r.SetReady("g1", true)
	if _, err := r.CompleteLoad("host-conn", r.LoadID); err != nil {
		t.Fatalf("host load: %v", err)
	}
	r.randomIndex = func(int) (int, error) {
		return 0, errors.New("entropy unavailable")
	}
	result, err := r.CompleteLoad("g1", r.LoadID)
	if err == nil || err.Error() != protocol.ErrGameSetupFailed {
		t.Fatalf("guest load error = %v, want %q",
			err, protocol.ErrGameSetupFailed)
	}
	if r.Phase != protocol.RoomPhaseWaiting || r.Game != nil {
		t.Fatalf("failed preload setup phase = %q game %+v", r.Phase, r.Game)
	}
	for _, seat := range r.Seats {
		if seat.Ready || seat.Loaded {
			t.Fatalf("failed preload setup retained gate state: %+v", r.Seats)
		}
	}
	if len(result.Broadcast) != 1 ||
		result.Broadcast[0].Type != protocol.TypeRoomSnapshot {
		t.Fatalf("failed preload setup broadcast = %+v", result.Broadcast)
	}
	var snapshot protocol.RoomSnapshot
	if err := result.Broadcast[0].DecodePayload(&snapshot); err != nil {
		t.Fatalf("decode reset snapshot: %v", err)
	}
	if snapshot.Phase != protocol.RoomPhaseWaiting {
		t.Fatalf("reset snapshot phase = %q", snapshot.Phase)
	}
}

func TestChangingDeckCancelsActiveLoad(t *testing.T) {
	r := newTestRoom(t, 2, true)
	_, _ = r.Join("g1", "Guest1", false, "")
	_, _ = r.SelectDeck("host-conn", testDeck(protocol.FormatEDH))
	_, _ = r.SelectDeck("g1", testDeck(protocol.FormatEDH))
	_, _ = r.SetReady("host-conn", true)
	_, _ = r.SetReady("g1", true)
	loadID := r.LoadID

	if _, err := r.SelectDeck("host-conn", testDeck(protocol.FormatEDH)); err != nil {
		t.Fatalf("change deck: %v", err)
	}
	if r.Phase != protocol.RoomPhaseWaiting || r.Seats[0].Ready || r.Seats[0].Loaded {
		t.Fatalf("cancelled state = phase %q seat %+v", r.Phase, r.Seats[0])
	}
	if _, err := r.CompleteLoad("g1", loadID); err == nil || err.Error() != protocol.ErrNotLoading {
		t.Fatalf("completion after cancel err = %v, want %q", err, protocol.ErrNotLoading)
	}
}

func TestSpectatorJoiningDuringLoadReceivesResourceEvent(t *testing.T) {
	r := newTestRoom(t, 2, true)
	_, _ = r.Join("g1", "Guest1", false, "")
	_, _ = r.SelectDeck("host-conn", testDeck(protocol.FormatEDH))
	_, _ = r.SelectDeck("g1", testDeck(protocol.FormatEDH))
	_, _ = r.SetReady("host-conn", true)
	_, _ = r.SetReady("g1", true)

	joined, err := r.Join("s1", "Observer", true, "")
	if err != nil {
		t.Fatalf("spectator join: %v", err)
	}
	if len(joined.Broadcast) != 2 || joined.Broadcast[1].Type != protocol.TypeMatchLoadRequired {
		t.Fatalf("join broadcasts = %+v", joined.Broadcast)
	}
}
