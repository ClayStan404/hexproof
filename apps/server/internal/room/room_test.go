// SPDX-License-Identifier: GPL-2.0-only
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

func testDeck(format string) protocol.DeckSelect {
	deck := protocol.DeckSelect{
		Name:       "Test deck",
		Format:     format,
		DeckFormat: protocol.DefaultDeckFormatForTableMode(format),
		Mainboard: []protocol.DeckCard{
			{Name: "Sol Ring", Count: protocol.MinMainboardCards, SetCode: "CMM", CollectorNumber: "396"},
		},
		Sideboard: []protocol.DeckCard{},
	}
	if protocol.IsCommanderFormat(format) {
		deck.Commander = "Sol Ring"
	}
	return deck
}

var testNow = time.Date(2026, 7, 22, 12, 0, 0, 0, time.UTC)

func intPointer(value int) *int {
	return &value
}

func stringPointer(value string) *string {
	return &value
}

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

func TestGameSetupDrawMulliganAndPrivateProjection(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.randomIndex = func(maximum int) (int, error) { return 0, nil }
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join: %v", err)
	}
	deck := testDeck(protocol.FormatEDH)
	deck.Mainboard = []protocol.DeckCard{
		{Name: "Sol Ring", Count: 5, SetCode: "CMM", CollectorNumber: "396"},
		{Name: "Command Tower", Count: 5, SetCode: "CMM", CollectorNumber: "1001"},
	}
	if _, err := r.SelectDeck("host-conn", deck); err != nil {
		t.Fatalf("host deck: %v", err)
	}
	if _, err := r.SelectDeck("g1", deck); err != nil {
		t.Fatalf("guest deck: %v", err)
	}
	if _, err := r.SetReady("host-conn", true); err != nil {
		t.Fatalf("host ready: %v", err)
	}
	if _, err := r.SetReady("g1", true); err != nil {
		t.Fatalf("guest ready: %v", err)
	}
	if _, err := r.CompleteLoad("host-conn", r.LoadID); err != nil {
		t.Fatalf("host load: %v", err)
	}
	result, err := r.CompleteLoad("g1", r.LoadID)
	if err != nil {
		t.Fatalf("guest load: %v", err)
	}
	if !result.ProjectGame || r.Game == nil || r.Phase != protocol.RoomPhaseStarted {
		t.Fatalf("game did not start: result=%+v phase=%q game=%+v", result, r.Phase, r.Game)
	}
	if r.Game.StartingSeat != 0 || len(r.Game.Log) != 3 || r.Game.Log[0].Kind != "roll" {
		t.Fatalf("opening game state = %+v", r.Game)
	}
	if r.Game.ActiveSeat != r.Game.StartingSeat ||
		r.Game.CurrentPhase != protocol.GamePhaseUntap {
		t.Fatalf("opening turn state = active %d phase %q",
			r.Game.ActiveSeat, r.Game.CurrentPhase)
	}
	for seat, state := range r.Game.Seats {
		if state.Life != 40 || len(state.Hand) != 7 || len(state.Library) != 2 ||
			len(state.CommandZone) != 1 || state.CommandZone[0].Name != "Sol Ring" {
			t.Fatalf("seat %d state = %+v", seat, state)
		}
		if len(state.Counters) != protocol.PlayerCounterSlotCount ||
			state.Counters[0].Key != "counter-1" ||
			state.Counters[0].Label != "" ||
			state.Counters[6].Label != "" {
			t.Fatalf("seat %d counters = %+v", seat, state.Counters)
		}
		seen := make(map[string]bool)
		allCards := append(append(append([]protocol.GameCard{}, state.Hand...),
			state.Library...), state.CommandZone...)
		for _, card := range allCards {
			if seen[card.ID] {
				t.Fatalf("seat %d duplicate card id %q", seat, card.ID)
			}
			seen[card.ID] = true
		}
		if len(seen) != 10 {
			t.Fatalf("seat %d unique card ids = %d, want 10", seat, len(seen))
		}
	}

	hostView, err := r.GameSnapshot("host-conn")
	if err != nil {
		t.Fatalf("host projection: %v", err)
	}
	guestView, err := r.GameSnapshot("g1")
	if err != nil {
		t.Fatalf("guest projection: %v", err)
	}
	if len(hostView.Seats[0].Hand) != 7 || len(hostView.Seats[1].Hand) != 0 {
		t.Fatalf("host hands leaked/omitted: %+v", hostView.Seats)
	}
	if hostView.ActiveSeat != r.Game.StartingSeat ||
		hostView.CurrentPhase != protocol.GamePhaseUntap {
		t.Fatalf("host turn projection = active %d phase %q",
			hostView.ActiveSeat, hostView.CurrentPhase)
	}
	if len(guestView.Seats[1].Hand) != 7 || len(guestView.Seats[0].Hand) != 0 {
		t.Fatalf("guest hands leaked/omitted: %+v", guestView.Seats)
	}

	draw, err := r.Draw("host-conn", 1)
	if err != nil {
		t.Fatalf("draw: %v", err)
	}
	if !draw.ProjectGame || len(r.Game.Seats[0].Hand) != 8 || len(r.Game.Seats[0].Library) != 1 {
		t.Fatalf("draw state = %+v", r.Game.Seats[0])
	}
	if r.Game.Log[len(r.Game.Log)-1].Kind != "draw" {
		t.Fatalf("draw log = %+v", r.Game.Log)
	}

	mulligan, err := r.Mulligan("host-conn")
	if err != nil {
		t.Fatalf("mulligan: %v", err)
	}
	if !mulligan.ProjectGame || len(r.Game.Seats[0].Hand) != 7 ||
		len(r.Game.Seats[0].Library) != 2 ||
		r.Game.Seats[0].MulliganCount != 1 {
		t.Fatalf("mulligan state = %+v", r.Game.Seats[0])
	}
	if r.Game.Log[len(r.Game.Log)-1].Kind != "mulligan" {
		t.Fatalf("mulligan log = %+v", r.Game.Log)
	}
	secondMulligan, err := r.Mulligan("host-conn")
	if err != nil {
		t.Fatalf("second mulligan: %v", err)
	}
	var secondMulliganed protocol.GameMulliganed
	if err := secondMulligan.Reply.DecodePayload(&secondMulliganed); err != nil {
		t.Fatalf("decode second mulligan reply: %v", err)
	}
	if secondMulliganed.MulliganCount != 2 ||
		r.Game.Seats[0].MulliganCount != 2 ||
		!strings.Contains(r.Game.Log[len(r.Game.Log)-1].Text, "mulligan 2") {
		t.Fatalf("second mulligan = reply %+v state %+v log %+v",
			secondMulliganed, r.Game.Seats[0], r.Game.Log[len(r.Game.Log)-1])
	}

	joined, err := r.Join("s1", "Observer", true, "")
	if err != nil {
		t.Fatalf("spectator join after start: %v", err)
	}
	if !joined.ProjectGame {
		t.Fatalf("spectator join result = %+v, want game projection", joined)
	}
	spectatorView, err := r.GameSnapshot("s1")
	if err != nil {
		t.Fatalf("spectator projection: %v", err)
	}
	encoded, err := json.Marshal(spectatorView)
	if err != nil {
		t.Fatalf("marshal spectator projection: %v", err)
	}
	if !strings.Contains(string(encoded), "Sol Ring") ||
		strings.Contains(string(encoded), "Command Tower") {
		t.Fatalf("spectator projection leaked hidden cards: %s", encoded)
	}
	if spectatorView.Seats[0].MulliganCount != 2 {
		t.Fatalf("spectator mulligan count = %d, want 2",
			spectatorView.Seats[0].MulliganCount)
	}
	if _, err := r.Draw("s1", 1); err == nil || err.Error() != protocol.ErrNotPlayer {
		t.Fatalf("spectator draw err = %v, want %q", err, protocol.ErrNotPlayer)
	}
	if _, err := r.Mulligan("s1"); err == nil || err.Error() != protocol.ErrNotPlayer {
		t.Fatalf("spectator mulligan err = %v, want %q", err, protocol.ErrNotPlayer)
	}
	for range 2 {
		if _, err := r.Draw("host-conn", 1); err != nil {
			t.Fatalf("drain library: %v", err)
		}
	}
	if _, err := r.Draw("host-conn", 1); err == nil || err.Error() != protocol.ErrLibraryEmpty {
		t.Fatalf("empty library draw err = %v, want %q", err, protocol.ErrLibraryEmpty)
	}
}

func TestDiscardHandRandomAndAll(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{
				Seat: 0, DisplayName: "Host",
				Hand: []protocol.GameCard{
					{ID: "hand-a", Name: "First", OwnerSeat: 0},
					{ID: "hand-b", Name: "Second", OwnerSeat: 0},
					{ID: "hand-c", Name: "Third", OwnerSeat: 0},
				},
			},
			{Seat: 1, DisplayName: "Guest"},
		},
		NextLogID: 1,
	}
	r.randomIndex = func(maximum int) (int, error) {
		if maximum != 3 {
			t.Fatalf("random discard maximum = %d, want 3", maximum)
		}
		return 1, nil
	}

	randomResult, err := r.DiscardHand("host-conn", false)
	if err != nil {
		t.Fatalf("random discard: %v", err)
	}
	var randomReply protocol.GameHandDiscarded
	if randomResult.Reply == nil ||
		randomResult.Reply.DecodePayload(&randomReply) != nil ||
		randomReply.Count != 1 || len(r.Game.Seats[0].Hand) != 2 ||
		r.Game.Seats[0].Hand[0].ID != "hand-a" ||
		r.Game.Seats[0].Hand[1].ID != "hand-c" ||
		len(r.Game.Seats[0].Graveyard) != 1 ||
		r.Game.Seats[0].Graveyard[0].ID != "hand-b" ||
		len(r.Game.Log) != 1 || r.Game.Log[0].Kind != "discard_random" ||
		!strings.Contains(r.Game.Log[0].Text, "randomly discarded Second") {
		t.Fatalf("random discard result/state = %+v %+v log=%+v",
			randomReply, r.Game.Seats[0], r.Game.Log)
	}

	allResult, err := r.DiscardHand("host-conn", true)
	if err != nil {
		t.Fatalf("discard all: %v", err)
	}
	var allReply protocol.GameHandDiscarded
	if allResult.Reply == nil || allResult.Reply.DecodePayload(&allReply) != nil ||
		allReply.Count != 2 || len(r.Game.Seats[0].Hand) != 0 ||
		len(r.Game.Seats[0].Graveyard) != 3 ||
		r.Game.Seats[0].Graveyard[1].ID != "hand-a" ||
		r.Game.Seats[0].Graveyard[2].ID != "hand-c" ||
		len(r.Game.Log) != 2 || r.Game.Log[1].Kind != "discard_hand" ||
		!strings.Contains(r.Game.Log[1].Text, "discarded their hand (2 cards)") {
		t.Fatalf("discard-all result/state = %+v %+v log=%+v",
			allReply, r.Game.Seats[0], r.Game.Log)
	}
	if _, err := r.DiscardHand("host-conn", false); err == nil ||
		err.Error() != protocol.ErrInvalidMove {
		t.Fatalf("empty-hand discard error = %v, want %q",
			err, protocol.ErrInvalidMove)
	}
}

func TestGameCommandsRequireStartedGame(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Draw("host-conn", 1); err == nil || err.Error() != protocol.ErrGameNotStarted {
		t.Fatalf("draw before start err = %v, want %q", err, protocol.ErrGameNotStarted)
	}
	if _, err := r.Mulligan("host-conn"); err == nil || err.Error() != protocol.ErrGameNotStarted {
		t.Fatalf("mulligan before start err = %v, want %q", err, protocol.ErrGameNotStarted)
	}
	if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{}); err == nil ||
		err.Error() != protocol.ErrGameNotStarted {
		t.Fatalf("move before start err = %v, want %q", err, protocol.ErrGameNotStarted)
	}
	if _, err := r.SetPhase("host-conn", protocol.GameSetPhase{
		Phase: protocol.GamePhaseDraw,
	}); err == nil || err.Error() != protocol.ErrGameNotStarted {
		t.Fatalf("set phase before start err = %v, want %q", err, protocol.ErrGameNotStarted)
	}
	if _, err := r.SetCounter("host-conn", protocol.GameSetCounter{
		Counter: protocol.PlayerCounterLife,
		Value:   intPointer(19),
	}); err == nil || err.Error() != protocol.ErrGameNotStarted {
		t.Fatalf("set counter before start err = %v, want %q", err, protocol.ErrGameNotStarted)
	}
	if _, err := r.NextTurn("host-conn"); err == nil ||
		err.Error() != protocol.ErrGameNotStarted {
		t.Fatalf("next turn before start err = %v, want %q", err, protocol.ErrGameNotStarted)
	}
	if _, err := r.Reveal("host-conn", protocol.GameReveal{
		Zone: protocol.ZoneHand,
	}); err == nil || err.Error() != protocol.ErrGameNotStarted {
		t.Fatalf("reveal before start err = %v, want %q", err, protocol.ErrGameNotStarted)
	}
	if _, err := r.ConcedeAt("host-conn", testNow); err == nil ||
		err.Error() != protocol.ErrGameNotStarted {
		t.Fatalf("concede before start err = %v, want %q", err, protocol.ErrGameNotStarted)
	}
}

func TestConcedeEndsModernGameAndProjectsPublicScore(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Format = protocol.FormatModern
	r.MatchMode = protocol.MatchBO3
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join player: %v", err)
	}
	if _, err := r.Join("s1", "Observer", true, ""); err != nil {
		t.Fatalf("join spectator: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number:       1,
		StartingSeat: 0,
		ActiveSeat:   0,
		CurrentPhase: protocol.GamePhaseUntap,
		Seats: []PlayerGameState{
			{Seat: 0, DisplayName: "Host"},
			{Seat: 1, DisplayName: "Guest1"},
		},
		Log:       []protocol.GameLogEntry{},
		NextLogID: 1,
	}

	result, err := r.ConcedeAt("host-conn", testNow)
	if err != nil {
		t.Fatalf("concede: %v", err)
	}
	if !result.ProjectGame || result.Reply == nil ||
		result.Reply.Type != protocol.TypeGameConceded {
		t.Fatalf("concede result = %+v", result)
	}
	var reply protocol.GameConceded
	if err := result.Reply.DecodePayload(&reply); err != nil {
		t.Fatalf("decode concede reply: %v", err)
	}
	if reply.ConcededSeat != 0 || reply.WinnerSeat != 1 ||
		reply.MatchFinished || len(reply.Score) != 2 ||
		reply.Score[0] != 0 || reply.Score[1] != 1 {
		t.Fatalf("concede reply = %+v", reply)
	}
	if r.Game.ActiveSeat != -1 || r.Game.Result == nil ||
		r.Game.Result.Reason != protocol.GameResultConcede ||
		r.Game.Result.WinnerSeat != 1 || r.Game.Result.ConcededSeat != 0 ||
		r.Game.Result.MatchFinished {
		t.Fatalf("game result = %+v", r.Game)
	}
	if len(r.Game.Log) != 1 || r.Game.Log[0].Kind != "concede" ||
		r.Game.Log[0].Text != "Host conceded. Guest1 wins Game 1." {
		t.Fatalf("concede log = %+v", r.Game.Log)
	}

	for _, viewer := range []string{"host-conn", "g1", "s1"} {
		view, err := r.GameSnapshot(viewer)
		if err != nil {
			t.Fatalf("%s projection: %v", viewer, err)
		}
		if view.Result == nil || view.Result.WinnerSeat != 1 ||
			view.Result.ConcededSeat != 0 || view.Result.MatchFinished ||
			len(view.Score) != 2 || view.Score[1] != 1 ||
			view.Log[len(view.Log)-1].Kind != "concede" {
			t.Fatalf("%s result projection = %+v", viewer, view)
		}
	}

	if _, err := r.ConcedeAt("host-conn", testNow); err == nil ||
		err.Error() != protocol.ErrGameFinished {
		t.Fatalf("duplicate concede err = %v, want %q", err, protocol.ErrGameFinished)
	}
	if _, err := r.Draw("g1", 1); err == nil ||
		err.Error() != protocol.ErrGameFinished {
		t.Fatalf("draw after finish err = %v, want %q", err, protocol.ErrGameFinished)
	}
	if _, err := r.SetCounter("g1", protocol.GameSetCounter{
		Counter: protocol.PlayerCounterLife,
		Value:   intPointer(19),
	}); err == nil || err.Error() != protocol.ErrGameFinished {
		t.Fatalf("counter after finish err = %v, want %q", err, protocol.ErrGameFinished)
	}
	if _, err := r.MoveCard("g1", protocol.GameMoveCard{}); err == nil ||
		err.Error() != protocol.ErrGameFinished {
		t.Fatalf("move after finish err = %v, want %q", err, protocol.ErrGameFinished)
	}
	if _, err := r.ReturnToRoom("g1"); err == nil ||
		err.Error() != protocol.ErrMatchNotFinished {
		t.Fatalf("return before BO3 match finish err = %v, want %q",
			err, protocol.ErrMatchNotFinished)
	}
}

func TestConcedeAuthorityAndBO1MatchResult(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Format = protocol.FormatModern
	r.MatchMode = protocol.MatchBO1
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join player: %v", err)
	}
	if _, err := r.Join("s1", "Observer", true, ""); err != nil {
		t.Fatalf("join spectator: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{Seat: 0, DisplayName: "Host"},
			{Seat: 1, DisplayName: "Guest1"},
		},
		Log:       []protocol.GameLogEntry{},
		NextLogID: 1,
	}

	if _, err := r.ConcedeAt("s1", testNow); err == nil ||
		err.Error() != protocol.ErrNotPlayer {
		t.Fatalf("spectator concede err = %v, want %q", err, protocol.ErrNotPlayer)
	}
	result, err := r.ConcedeAt("g1", testNow)
	if err != nil {
		t.Fatalf("guest concede: %v", err)
	}
	var reply protocol.GameConceded
	if err := result.Reply.DecodePayload(&reply); err != nil {
		t.Fatalf("decode concede reply: %v", err)
	}
	if !reply.MatchFinished || reply.WinnerSeat != 0 ||
		reply.ConcededSeat != 1 || reply.Score[0] != 1 {
		t.Fatalf("BO1 result = %+v", reply)
	}

	r.Seats[0].Deck = &protocol.DeckSelect{Name: "Host deck"}
	r.Seats[1].Deck = &protocol.DeckSelect{Name: "Guest deck"}
	for index := range r.Seats {
		r.Seats[index].Ready = true
		r.Seats[index].Loaded = true
	}
	returned, err := r.ReturnToRoom("s1")
	if err != nil {
		t.Fatalf("spectator return to room: %v", err)
	}
	if returned.Reply == nil ||
		returned.Reply.Type != protocol.TypeGameReturnedToRoom ||
		len(returned.Broadcast) != 1 ||
		r.Phase != protocol.RoomPhaseWaiting || r.Game != nil ||
		r.Score[0] != 0 || r.Score[1] != 0 {
		t.Fatalf("return to room result=%+v room=%+v", returned, r)
	}
	for index, seat := range r.Seats {
		if seat.Deck == nil || seat.Ready || seat.Loaded {
			t.Fatalf("returned seat %d = %+v", index, seat)
		}
	}
}

func TestGameSayIsPublicForPlayersAndSpectators(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join player: %v", err)
	}
	if _, err := r.Join("s1", "Observer", true, ""); err != nil {
		t.Fatalf("join spectator: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{Seat: 0, DisplayName: "Host"},
			{Seat: 1, DisplayName: "Guest1"},
		},
		Log:       []protocol.GameLogEntry{},
		NextLogID: 1,
	}

	result, err := r.Say("host-conn", protocol.GameSay{
		Message: "  Good luck!  ",
	})
	if err != nil {
		t.Fatalf("player say: %v", err)
	}
	if !result.ProjectGame || result.Reply == nil ||
		result.Reply.Type != protocol.TypeGameSaid {
		t.Fatalf("player say result = %+v", result)
	}
	var reply protocol.GameSaid
	if err := result.Reply.DecodePayload(&reply); err != nil {
		t.Fatalf("decode game.said: %v", err)
	}
	if reply.RoomID != r.ID || reply.LogID != 1 ||
		len(r.Game.Log) != 1 || r.Game.Log[0].Kind != "chat" ||
		r.Game.Log[0].Seat != 0 ||
		r.Game.Log[0].Text != "Host: Good luck!" {
		t.Fatalf("player chat reply/log = %+v / %+v", reply, r.Game.Log)
	}

	if _, err := r.Say("s1", protocol.GameSay{
		Message: "Have fun.",
	}); err != nil {
		t.Fatalf("spectator say: %v", err)
	}
	if len(r.Game.Log) != 2 || r.Game.Log[1].Seat != -1 ||
		r.Game.Log[1].Text != "Observer: Have fun." {
		t.Fatalf("spectator chat log = %+v", r.Game.Log)
	}

	for _, viewer := range []string{"host-conn", "g1", "s1"} {
		view, err := r.GameSnapshot(viewer)
		if err != nil {
			t.Fatalf("%s projection: %v", viewer, err)
		}
		if len(view.Log) != 2 ||
			view.Log[0].Text != "Host: Good luck!" ||
			view.Log[1].Text != "Observer: Have fun." {
			t.Fatalf("%s chat projection = %+v", viewer, view.Log)
		}
	}

	r.Game.Result = &protocol.GameResult{
		Reason: protocol.GameResultConcede, WinnerSeat: 1, ConcededSeat: 0,
	}
	if _, err := r.Say("g1", protocol.GameSay{
		Message: "Thanks for the game.",
	}); err != nil {
		t.Fatalf("chat after result: %v", err)
	}
	if r.Game.Log[len(r.Game.Log)-1].Text !=
		"Guest1: Thanks for the game." {
		t.Fatalf("post-game chat log = %+v", r.Game.Log)
	}
}

func TestGameSayValidatesMembershipAndMessage(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number:    1,
		Seats:     []PlayerGameState{{Seat: 0, DisplayName: "Host"}},
		Log:       []protocol.GameLogEntry{},
		NextLogID: 1,
	}

	for index, message := range []string{
		"",
		"   ",
		"line one\nline two",
		strings.Repeat("界", protocol.MaxGameSayRunes+1),
	} {
		if _, err := r.Say("host-conn", protocol.GameSay{
			Message: message,
		}); err == nil || err.Error() != protocol.ErrInvalidChat {
			t.Fatalf("invalid chat %d err = %v, want %q",
				index, err, protocol.ErrInvalidChat)
		}
	}
	if _, err := r.Say("outsider", protocol.GameSay{
		Message: "hello",
	}); err == nil || err.Error() != protocol.ErrNotInRoom {
		t.Fatalf("outsider chat err = %v, want %q", err, protocol.ErrNotInRoom)
	}

	r.Phase = protocol.RoomPhaseWaiting
	if _, err := r.Say("host-conn", protocol.GameSay{
		Message: "too early",
	}); err == nil || err.Error() != protocol.ErrGameNotStarted {
		t.Fatalf("pre-game chat err = %v, want %q",
			err, protocol.ErrGameNotStarted)
	}
}

func TestPhaseAndTurnAreActivePlayerAuthoritative(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join player: %v", err)
	}
	if _, err := r.Join("s1", "Observer", true, ""); err != nil {
		t.Fatalf("join spectator: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number:       1,
		StartingSeat: 0,
		ActiveSeat:   0,
		CurrentPhase: protocol.GamePhaseUntap,
		Seats: []PlayerGameState{
			{Seat: 0, DisplayName: "Host"},
			{Seat: 1, DisplayName: "Guest1"},
		},
		Log:       []protocol.GameLogEntry{},
		NextLogID: 1,
	}

	phaseResult, err := r.SetPhase("host-conn", protocol.GameSetPhase{
		Phase: protocol.GamePhaseDeclareAttackers,
	})
	if err != nil {
		t.Fatalf("set phase: %v", err)
	}
	if !phaseResult.ProjectGame || phaseResult.Reply == nil ||
		phaseResult.Reply.Type != protocol.TypeGamePhaseSet {
		t.Fatalf("phase result = %+v", phaseResult)
	}
	var phaseReply protocol.GamePhaseSet
	if err := phaseResult.Reply.DecodePayload(&phaseReply); err != nil {
		t.Fatalf("decode phase reply: %v", err)
	}
	if phaseReply.Seat != 0 || phaseReply.Phase != protocol.GamePhaseDeclareAttackers ||
		r.Game.CurrentPhase != protocol.GamePhaseDeclareAttackers {
		t.Fatalf("phase state/reply = game %+v reply %+v", r.Game, phaseReply)
	}
	if len(r.Game.Log) != 1 || r.Game.Log[0].Kind != "phase" ||
		r.Game.Log[0].Text != "Host advanced to the Attackers step." {
		t.Fatalf("phase log = %+v", r.Game.Log)
	}

	for _, viewer := range []string{"host-conn", "g1", "s1"} {
		view, err := r.GameSnapshot(viewer)
		if err != nil {
			t.Fatalf("%s projection: %v", viewer, err)
		}
		if view.ActiveSeat != 0 || view.CurrentPhase != protocol.GamePhaseDeclareAttackers {
			t.Fatalf("%s turn projection = active %d phase %q",
				viewer, view.ActiveSeat, view.CurrentPhase)
		}
	}

	if _, err := r.SetPhase("g1", protocol.GameSetPhase{
		Phase: protocol.GamePhaseDraw,
	}); err == nil || err.Error() != protocol.ErrNotActivePlayer {
		t.Fatalf("inactive phase err = %v, want %q", err, protocol.ErrNotActivePlayer)
	}
	if _, err := r.SetPhase("host-conn", protocol.GameSetPhase{
		Phase: "combat",
	}); err == nil || err.Error() != protocol.ErrInvalidPhase {
		t.Fatalf("invalid phase err = %v, want %q", err, protocol.ErrInvalidPhase)
	}
	if _, err := r.SetPhase("s1", protocol.GameSetPhase{
		Phase: protocol.GamePhaseDraw,
	}); err == nil || err.Error() != protocol.ErrNotPlayer {
		t.Fatalf("spectator phase err = %v, want %q", err, protocol.ErrNotPlayer)
	}

	turnResult, err := r.NextTurn("host-conn")
	if err != nil {
		t.Fatalf("next turn: %v", err)
	}
	if !turnResult.ProjectGame || turnResult.Reply == nil ||
		turnResult.Reply.Type != protocol.TypeGameTurnAdvanced {
		t.Fatalf("turn result = %+v", turnResult)
	}
	var turnReply protocol.GameTurnAdvanced
	if err := turnResult.Reply.DecodePayload(&turnReply); err != nil {
		t.Fatalf("decode turn reply: %v", err)
	}
	if r.Game.ActiveSeat != 1 || r.Game.CurrentPhase != protocol.GamePhaseUntap ||
		turnReply.ActiveSeat != 1 || turnReply.CurrentPhase != protocol.GamePhaseUntap {
		t.Fatalf("turn state/reply = game %+v reply %+v", r.Game, turnReply)
	}
	if len(r.Game.Log) != 2 || r.Game.Log[1].Kind != "turn" ||
		r.Game.Log[1].Text != "Guest1 began their turn." {
		t.Fatalf("turn log = %+v", r.Game.Log)
	}
	if _, err := r.NextTurn("host-conn"); err == nil ||
		err.Error() != protocol.ErrNotActivePlayer {
		t.Fatalf("former active next-turn err = %v, want %q",
			err, protocol.ErrNotActivePlayer)
	}
	if _, err := r.NextTurn("g1"); err != nil {
		t.Fatalf("guest next turn: %v", err)
	}
	if r.Game.ActiveSeat != 0 || r.Game.CurrentPhase != protocol.GamePhaseUntap {
		t.Fatalf("wrapped turn state = %+v", r.Game)
	}
}

func TestResponseStatusIsPublicPlayerOwnedAndPhaseScoped(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join player: %v", err)
	}
	if _, err := r.Join("s1", "Observer", true, ""); err != nil {
		t.Fatalf("join spectator: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1, ActiveSeat: 0, CurrentPhase: protocol.GamePhaseFirstMain,
		Seats: []PlayerGameState{
			{Seat: 0, DisplayName: "Host"},
			{Seat: 1, DisplayName: "Guest1"},
		},
		Log: []protocol.GameLogEntry{}, NextLogID: 1,
	}

	result, err := r.SetResponseStatus("g1", protocol.GameSetResponseStatus{
		Status: protocol.ResponseStatusHold,
	})
	if err != nil {
		t.Fatalf("set hold status: %v", err)
	}
	if !result.ProjectGame || result.Reply == nil ||
		result.Reply.Type != protocol.TypeGameResponseStatusSet ||
		r.Game.Seats[1].ResponseStatus != protocol.ResponseStatusHold {
		t.Fatalf("hold result/state = result %+v game %+v", result, r.Game)
	}
	view, err := r.GameSnapshot("s1")
	if err != nil || view.Seats[1].ResponseStatus != protocol.ResponseStatusHold {
		t.Fatalf("spectator response status = view %+v err %v", view, err)
	}
	if len(r.Game.Log) != 1 || r.Game.Log[0].Kind != "response" ||
		r.Game.Log[0].Text != "Guest1 asked the table to wait." {
		t.Fatalf("response log = %+v", r.Game.Log)
	}
	if _, err := r.Say("host-conn", protocol.GameSay{Message: "Action changed."}); err != nil {
		t.Fatalf("say while holding: %v", err)
	}
	if r.Game.Seats[1].ResponseStatus != protocol.ResponseStatusHold {
		t.Fatalf("public event cleared hold status: %+v", r.Game.Seats)
	}
	if _, err := r.SetResponseStatus("g1", protocol.GameSetResponseStatus{
		Status: protocol.ResponseStatusPass,
	}); err != nil {
		t.Fatalf("set pass status: %v", err)
	}
	if _, err := r.Say("host-conn", protocol.GameSay{Message: "Another action."}); err != nil {
		t.Fatalf("say after pass: %v", err)
	}
	if r.Game.Seats[1].ResponseStatus != "" {
		t.Fatalf("public event retained pass status: %+v", r.Game.Seats)
	}
	if _, err := r.SetResponseStatus("g1", protocol.GameSetResponseStatus{
		Status: protocol.ResponseStatusHold,
	}); err != nil {
		t.Fatalf("restore hold status: %v", err)
	}
	if _, err := r.SetResponseStatus("s1", protocol.GameSetResponseStatus{
		Status: protocol.ResponseStatusPass,
	}); err == nil || err.Error() != protocol.ErrNotPlayer {
		t.Fatalf("spectator response err = %v, want %q", err, protocol.ErrNotPlayer)
	}
	if _, err := r.SetPhase("host-conn", protocol.GameSetPhase{
		Phase: protocol.GamePhaseEnd,
	}); err != nil {
		t.Fatalf("advance phase: %v", err)
	}
	if r.Game.Seats[1].ResponseStatus != "" {
		t.Fatalf("phase retained response status: %+v", r.Game.Seats)
	}
}

func TestLifeCounterIsOwnerAuthoritativeAndPublic(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join player: %v", err)
	}
	if _, err := r.Join("s1", "Observer", true, ""); err != nil {
		t.Fatalf("join spectator: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{Seat: 0, DisplayName: "Host", Life: 20},
			{Seat: 1, DisplayName: "Guest1", Life: 20},
		},
		Log:       []protocol.GameLogEntry{},
		NextLogID: 1,
	}

	result, err := r.SetCounter("host-conn", protocol.GameSetCounter{
		Counter: protocol.PlayerCounterLife,
		Value:   intPointer(17),
	})
	if err != nil {
		t.Fatalf("set life: %v", err)
	}
	if !result.ProjectGame || result.Reply == nil ||
		result.Reply.Type != protocol.TypeGameCounterSet ||
		r.Game.Seats[0].Life != 17 {
		t.Fatalf("set life result/state = %+v / %+v", result, r.Game.Seats[0])
	}
	var reply protocol.GameCounterSet
	if err := result.Reply.DecodePayload(&reply); err != nil {
		t.Fatalf("decode counter reply: %v", err)
	}
	if reply.Seat != 0 || reply.Counter != protocol.PlayerCounterLife ||
		reply.Value != 17 {
		t.Fatalf("counter reply = %+v", reply)
	}
	if len(r.Game.Log) != 1 || r.Game.Log[0].Kind != "counter" ||
		r.Game.Log[0].Text != "Host set life to 17 (-3)." {
		t.Fatalf("counter log = %+v", r.Game.Log)
	}

	for _, viewer := range []string{"host-conn", "g1", "s1"} {
		view, err := r.GameSnapshot(viewer)
		if err != nil {
			t.Fatalf("%s projection: %v", viewer, err)
		}
		if view.Seats[0].Life != 17 {
			t.Fatalf("%s host life = %d, want 17", viewer, view.Seats[0].Life)
		}
	}

	guestResult, err := r.SetCounter("g1", protocol.GameSetCounter{
		Counter: protocol.PlayerCounterLife,
		Value:   intPointer(-2),
	})
	if err != nil {
		t.Fatalf("guest negative life: %v", err)
	}
	if !guestResult.ProjectGame || r.Game.Seats[1].Life != -2 ||
		r.Game.Seats[0].Life != 17 {
		t.Fatalf("guest life state = %+v", r.Game.Seats)
	}

	logCount := len(r.Game.Log)
	unchanged, err := r.SetCounter("g1", protocol.GameSetCounter{
		Counter: protocol.PlayerCounterLife,
		Value:   intPointer(-2),
	})
	if err != nil {
		t.Fatalf("unchanged life: %v", err)
	}
	if unchanged.ProjectGame || unchanged.Reply == nil || len(r.Game.Log) != logCount {
		t.Fatalf("unchanged result/log = %+v / %+v", unchanged, r.Game.Log)
	}

	if _, err := r.SetCounter("s1", protocol.GameSetCounter{
		Counter: protocol.PlayerCounterLife,
		Value:   intPointer(99),
	}); err == nil || err.Error() != protocol.ErrNotPlayer {
		t.Fatalf("spectator counter err = %v, want %q", err, protocol.ErrNotPlayer)
	}
	if _, err := r.SetCounter("host-conn", protocol.GameSetCounter{
		Counter: "poison",
		Value:   intPointer(1),
	}); err == nil || err.Error() != protocol.ErrInvalidCounter {
		t.Fatalf("unknown counter err = %v, want %q", err, protocol.ErrInvalidCounter)
	}
	if _, err := r.SetCounter("host-conn", protocol.GameSetCounter{
		Counter: protocol.PlayerCounterLife,
		Value:   intPointer(protocol.MaxPlayerCounterValue + 1),
	}); err == nil || err.Error() != protocol.ErrInvalidCounter {
		t.Fatalf("out-of-range counter err = %v, want %q", err, protocol.ErrInvalidCounter)
	}
}

func TestCustomCountersAreOwnerAuthoritativeAndPublic(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join player: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{
				Seat:        0,
				DisplayName: "Host",
				Life:        20,
				Counters:    defaultPlayerCounters(),
			},
			{
				Seat:        1,
				DisplayName: "Guest1",
				Life:        20,
				Counters:    defaultPlayerCounters(),
			},
		},
		Log:       []protocol.GameLogEntry{},
		NextLogID: 1,
	}

	result, err := r.SetCounter("host-conn", protocol.GameSetCounter{
		Counter: "counter-1",
		Delta:   intPointer(1),
	})
	if err != nil {
		t.Fatalf("increment counter: %v", err)
	}
	if !result.ProjectGame || r.Game.Seats[0].Counters[0].Value != 1 ||
		r.Game.Seats[1].Counters[0].Value != 0 {
		t.Fatalf("increment result/state = %+v / %+v", result, r.Game.Seats)
	}
	var reply protocol.GameCounterSet
	if err := result.Reply.DecodePayload(&reply); err != nil {
		t.Fatalf("decode counter reply: %v", err)
	}
	if reply.Counter != "counter-1" || reply.Value != 1 || reply.Label != "" {
		t.Fatalf("counter reply = %+v", reply)
	}
	if len(r.Game.Log) != 1 ||
		r.Game.Log[0].Text != "Host set counter-1 to 1 (+1)." {
		t.Fatalf("increment log = %+v", r.Game.Log)
	}

	renameResult, err := r.SetCounter("host-conn", protocol.GameSetCounter{
		Counter: "counter-1",
		Label:   stringPointer("  Energy  "),
	})
	if err != nil {
		t.Fatalf("rename counter: %v", err)
	}
	if !renameResult.ProjectGame ||
		r.Game.Seats[0].Counters[0].Label != "Energy" ||
		r.Game.Seats[1].Counters[0].Label != "" ||
		r.Game.Log[len(r.Game.Log)-1].Text !=
			"Host renamed counter counter-1 to Energy." {
		t.Fatalf("rename state/log = %+v / %+v", r.Game.Seats, r.Game.Log)
	}

	countResult, err := r.SetCounterCount("host-conn",
		protocol.GameSetCounterCount{Count: 3})
	if err != nil {
		t.Fatalf("set counter count: %v", err)
	}
	var countReply protocol.GameCounterCountSet
	if err := countResult.Reply.DecodePayload(&countReply); err != nil {
		t.Fatalf("decode counter count reply: %v", err)
	}
	if !countResult.ProjectGame || countReply.Seat != 0 ||
		countReply.Count != 3 || r.Game.Seats[0].CounterCount != 3 ||
		r.Game.Seats[1].CounterCount != 0 {
		t.Fatalf("counter count result/state = %+v / %+v",
			countResult, r.Game.Seats)
	}
	if _, err := r.SetCounterCount("g1",
		protocol.GameSetCounterCount{Count: 8}); err == nil ||
		err.Error() != protocol.ErrInvalidCounter {
		t.Fatalf("invalid counter count err = %v, want %q",
			err, protocol.ErrInvalidCounter)
	}

	for _, viewer := range []string{"host-conn", "g1"} {
		view, err := r.GameSnapshot(viewer)
		if err != nil {
			t.Fatalf("%s projection: %v", viewer, err)
		}
		if len(view.Seats[0].Counters) != protocol.PlayerCounterSlotCount ||
			view.Seats[0].Counters[0].Label != "Energy" ||
			view.Seats[0].Counters[0].Value != 1 ||
			view.Seats[0].CounterCount != 3 ||
			view.Seats[1].CounterCount != 0 {
			t.Fatalf("%s counters = %+v", viewer, view.Seats[0].Counters)
		}
	}

	if _, err := r.SetCounter("host-conn", protocol.GameSetCounter{
		Counter: "counter-1",
		Delta:   intPointer(-1),
	}); err != nil {
		t.Fatalf("decrement counter: %v", err)
	}
	if r.Game.Seats[0].Counters[0].Value != 0 ||
		r.Game.Log[len(r.Game.Log)-1].Text != "Host set Energy to 0 (-1)." {
		t.Fatalf("decrement state/log = %+v / %+v",
			r.Game.Seats[0].Counters[0], r.Game.Log)
	}

	if _, err := r.SetCounter("host-conn", protocol.GameSetCounter{
		Counter: "counter-1",
		Value:   intPointer(-4),
	}); err != nil || r.Game.Seats[0].Counters[0].Value != -4 {
		t.Fatalf("exact signed counter = %+v, err = %v",
			r.Game.Seats[0].Counters[0], err)
	}

	invalidRequests := []protocol.GameSetCounter{
		{Counter: "counter-1"},
		{Counter: "counter-1", Delta: intPointer(2)},
		{Counter: "counter-1", Label: stringPointer("   ")},
		{Counter: "counter-1", Label: stringPointer("bad\nlabel")},
		{Counter: "counter-1", Label: stringPointer(strings.Repeat("x", 25))},
		{
			Counter: "counter-1",
			Value:   intPointer(2),
			Delta:   intPointer(1),
		},
		{Counter: protocol.PlayerCounterLife, Delta: intPointer(1)},
	}
	for index, request := range invalidRequests {
		if _, err := r.SetCounter("host-conn", request); err == nil ||
			err.Error() != protocol.ErrInvalidCounter {
			t.Fatalf("invalid request %d err = %v, want %q",
				index, err, protocol.ErrInvalidCounter)
		}
	}
}

func TestCardCountersAndLibraryPlacementAreAuthoritative(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join player: %v", err)
	}
	permanent := protocol.GameCard{
		ID: "s0-permanent", Name: "Grizzly Bears", OwnerSeat: 0,
		Position: &protocol.CardPosition{X: 0.2, Y: 0.3},
	}
	secondPermanent := protocol.GameCard{
		ID: "s0-second", Name: "Hill Giant", OwnerSeat: 0,
		Position: &protocol.CardPosition{X: 0.4, Y: 0.3},
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{
				Seat: 0, DisplayName: "Host",
				Library: []protocol.GameCard{
					{ID: "s0-lib-1", Name: "Island", OwnerSeat: 0},
					{ID: "s0-lib-2", Name: "Mountain", OwnerSeat: 0},
				},
				Battlefield: []protocol.GameCard{permanent, secondPermanent},
			},
			{Seat: 1, DisplayName: "Guest1"},
		},
		Log:               []protocol.GameLogEntry{},
		NextLogID:         1,
		NextCardCounterID: 1,
	}

	if _, err := r.SetCardCounter("host-conn",
		protocol.GameSetCardCounter{
			CardID: "s0-permanent", Kind: protocol.CardCounterKindNumber,
			Delta: intPointer(1),
		}); err != nil {
		t.Fatalf("add number counter: %v", err)
	}
	if _, err := r.SetCardCounter("host-conn",
		protocol.GameSetCardCounter{
			CardID: "s0-permanent", Kind: protocol.CardCounterKindAbility,
			Label: "Flying", Value: intPointer(2),
		}); err != nil {
		t.Fatalf("add ability counter: %v", err)
	}
	counters := r.Game.Seats[0].Battlefield[0].Counters
	if len(counters) != 2 || counters[0].ID != protocol.CardNumberCounterID ||
		counters[0].Value != 1 || counters[1].Label != "Flying" ||
		counters[1].Value != 2 {
		t.Fatalf("card counters = %+v", counters)
	}
	if _, err := r.SetCardCounter("g1", protocol.GameSetCardCounter{
		CardID: "s0-permanent", Kind: protocol.CardCounterKindNumber,
		Delta: intPointer(1),
	}); err == nil || err.Error() != protocol.ErrInvalidTarget {
		t.Fatalf("opponent card counter err = %v, want %q",
			err, protocol.ErrInvalidTarget)
	}

	index := 1
	if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: "s0-permanent", FromZone: protocol.ZoneBattlefield,
		ToZone: protocol.ZoneLibrary, LibraryPlacement: protocol.LibraryPlacementIndex,
		LibraryIndex: &index,
	}); err != nil {
		t.Fatalf("move to library index: %v", err)
	}
	if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: "s0-second", FromZone: protocol.ZoneBattlefield,
		ToZone: protocol.ZoneLibrary, LibraryPlacement: protocol.LibraryPlacementBottom,
	}); err != nil {
		t.Fatalf("move to library bottom: %v", err)
	}
	library := r.Game.Seats[0].Library
	if len(library) != 4 || library[1].ID != "s0-permanent" ||
		len(library[1].Counters) != 0 || library[3].ID != "s0-second" {
		t.Fatalf("library placement = %+v", library)
	}
}

func TestArrangeBattlefieldUpdatesPositionsAtomically(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join player: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{
				Seat: 0, DisplayName: "Host",
				Battlefield: []protocol.GameCard{
					{
						ID: "land", Name: "Forest", OwnerSeat: 0,
						Position: &protocol.CardPosition{X: 0.5, Y: 0.2},
						Tapped:   true,
						Counters: []protocol.GameCardCounter{{
							ID: "number", Kind: "number", Value: 2,
						}},
					},
					{
						ID: "creature", Name: "Grizzly Bears", OwnerSeat: 0,
						Position: &protocol.CardPosition{X: 0.6, Y: 0.2},
					},
				},
			},
			{Seat: 1, DisplayName: "Guest1"},
		},
		Log:       []protocol.GameLogEntry{},
		NextLogID: 1,
	}

	result, err := r.ArrangeBattlefield("host-conn",
		protocol.GameArrangeBattlefield{Cards: []protocol.BattlefieldCardPosition{
			{CardID: "land", Position: &protocol.CardPosition{X: 0.1, Y: 0.9}},
			{CardID: "creature", Position: &protocol.CardPosition{X: 0.2, Y: 0.4}},
		}})
	if err != nil {
		t.Fatalf("arrange battlefield: %v", err)
	}
	if !result.ProjectGame || result.Reply == nil ||
		result.Reply.Type != protocol.TypeGameBattlefieldArranged {
		t.Fatalf("arrange result = %+v", result)
	}
	var reply protocol.GameBattlefieldArranged
	if err := result.Reply.DecodePayload(&reply); err != nil {
		t.Fatalf("decode arrange reply: %v", err)
	}
	if reply.Seat != 0 || reply.Count != 2 {
		t.Fatalf("arrange reply = %+v", reply)
	}
	land := r.Game.Seats[0].Battlefield[0]
	creature := r.Game.Seats[0].Battlefield[1]
	if land.Position == nil || land.Position.X != 0.1 || land.Position.Y != 0.9 ||
		creature.Position == nil || creature.Position.X != 0.2 ||
		creature.Position.Y != 0.4 || !land.Tapped || len(land.Counters) != 1 ||
		len(r.Game.Log) != 0 {
		t.Fatalf("arranged battlefield = %+v", r.Game.Seats[0].Battlefield)
	}

	previous := *land.Position
	_, err = r.ArrangeBattlefield("host-conn",
		protocol.GameArrangeBattlefield{Cards: []protocol.BattlefieldCardPosition{
			{CardID: "land", Position: &protocol.CardPosition{X: 0.3, Y: 0.8}},
			{CardID: "missing", Position: &protocol.CardPosition{X: 0.4, Y: 0.4}},
		}})
	if err == nil || err.Error() != protocol.ErrCardNotFound {
		t.Fatalf("missing arrange target err = %v, want %q",
			err, protocol.ErrCardNotFound)
	}
	if *r.Game.Seats[0].Battlefield[0].Position != previous {
		t.Fatal("invalid arrangement partially mutated battlefield")
	}
}

func TestMoveCardPublishesIdentityAndRedactsReturnToHand(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join player: %v", err)
	}
	if _, err := r.Join("s1", "Observer", true, ""); err != nil {
		t.Fatalf("join spectator: %v", err)
	}
	movedCard := protocol.GameCard{
		ID: "s0-c1", Name: "Lightning Bolt", SetCode: "M11", CollectorNumber: "149",
	}
	hiddenCard := protocol.GameCard{
		ID: "s0-c2", Name: "Secret Card", SetCode: "TST", CollectorNumber: "2",
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{
				Seat: 0, DisplayName: "Host", Life: 20,
				Hand: []protocol.GameCard{movedCard, hiddenCard},
			},
			{Seat: 1, DisplayName: "Guest1", Life: 20, Hand: []protocol.GameCard{}},
		},
		Log:       []protocol.GameLogEntry{},
		NextLogID: 1,
	}

	position := &protocol.CardPosition{X: 0.25, Y: 0.6}
	result, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: movedCard.ID, FromZone: protocol.ZoneHand,
		ToZone: protocol.ZoneBattlefield, Position: position,
	})
	if err != nil {
		t.Fatalf("move hand to battlefield: %v", err)
	}
	if !result.ProjectGame || result.Reply == nil || result.Reply.Type != protocol.TypeGameCardMoved {
		t.Fatalf("move result = %+v", result)
	}
	var reply protocol.GameCardMoved
	if err := result.Reply.DecodePayload(&reply); err != nil {
		t.Fatalf("decode move reply: %v", err)
	}
	if reply.CardID != movedCard.ID || reply.ToZone != protocol.ZoneBattlefield ||
		reply.Position == nil || reply.Position.X != position.X || reply.Position.Y != position.Y {
		t.Fatalf("move reply = %+v", reply)
	}
	hostState := r.Game.Seats[0]
	if len(hostState.Hand) != 1 || hostState.Hand[0].ID != hiddenCard.ID ||
		len(hostState.Battlefield) != 1 || hostState.Battlefield[0].ID != movedCard.ID {
		t.Fatalf("authoritative zones = %+v", hostState)
	}
	if len(r.Game.Log) != 1 || r.Game.Log[0].Kind != "move_card" ||
		!strings.Contains(r.Game.Log[0].Text, movedCard.Name) {
		t.Fatalf("move log = %+v", r.Game.Log)
	}

	for _, viewer := range []string{"host-conn", "g1", "s1"} {
		view, err := r.GameSnapshot(viewer)
		if err != nil {
			t.Fatalf("%s projection: %v", viewer, err)
		}
		if len(view.Seats[0].Battlefield) != 1 ||
			view.Seats[0].Battlefield[0].Name != movedCard.Name ||
			view.Seats[0].Battlefield[0].Position == nil {
			t.Fatalf("%s public battlefield = %+v", viewer, view.Seats[0].Battlefield)
		}
		if viewer != "host-conn" && len(view.Seats[0].Hand) != 0 {
			t.Fatalf("%s received private hand: %+v", viewer, view.Seats[0].Hand)
		}
	}
	guestView, _ := r.GameSnapshot("g1")
	guestView.Seats[0].Battlefield[0].Position.X = 0.9
	if r.Game.Seats[0].Battlefield[0].Position.X != position.X {
		t.Fatal("projection position must not alias authoritative state")
	}

	if _, err := r.MoveCard("g1", protocol.GameMoveCard{
		CardID: movedCard.ID, FromZone: protocol.ZoneHand,
		ToZone: protocol.ZoneBattlefield, Position: position,
	}); err == nil || err.Error() != protocol.ErrCardNotFound {
		t.Fatalf("opponent move err = %v, want %q", err, protocol.ErrCardNotFound)
	}
	if _, err := r.MoveCard("s1", protocol.GameMoveCard{
		CardID: movedCard.ID, FromZone: protocol.ZoneBattlefield,
		ToZone: protocol.ZoneHand,
	}); err == nil || err.Error() != protocol.ErrNotPlayer {
		t.Fatalf("spectator move err = %v, want %q", err, protocol.ErrNotPlayer)
	}

	if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: movedCard.ID, FromZone: protocol.ZoneBattlefield,
		ToZone: protocol.ZoneHand,
	}); err != nil {
		t.Fatalf("return battlefield to hand: %v", err)
	}
	guestView, _ = r.GameSnapshot("g1")
	if len(guestView.Seats[0].Battlefield) != 0 || len(guestView.Seats[0].Hand) != 0 ||
		guestView.Seats[0].HandCount != 2 {
		t.Fatalf("return-to-hand projection = %+v", guestView.Seats[0])
	}
}

func TestStackAndRevealArePublicButOwnerControlled(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join player: %v", err)
	}
	if _, err := r.Join("s1", "Observer", true, ""); err != nil {
		t.Fatalf("join spectator: %v", err)
	}
	stackCard := protocol.GameCard{
		ID: "s0-c1", Name: "Lightning Bolt", SetCode: "M11", CollectorNumber: "149",
	}
	revealCard := protocol.GameCard{
		ID: "s0-c2", Name: "Secret Card", SetCode: "TST", CollectorNumber: "2",
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{
				Seat: 0, DisplayName: "Host", Life: 20,
				Hand: []protocol.GameCard{stackCard, revealCard},
			},
			{Seat: 1, DisplayName: "Guest1", Life: 20, Hand: []protocol.GameCard{}},
		},
		Stack:     []protocol.GameSharedCard{},
		Revealed:  []protocol.GameSharedCard{},
		Log:       []protocol.GameLogEntry{},
		NextLogID: 1,
	}

	if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: stackCard.ID, FromZone: protocol.ZoneHand, ToZone: protocol.ZoneStack,
	}); err != nil {
		t.Fatalf("move hand to stack: %v", err)
	}
	if len(r.Game.Stack) != 1 || r.Game.Stack[0].OwnerSeat != 0 ||
		r.Game.Stack[0].Name != stackCard.Name || len(r.Game.Seats[0].Hand) != 1 {
		t.Fatalf("stack state = %+v hand=%+v", r.Game.Stack, r.Game.Seats[0].Hand)
	}
	for _, viewer := range []string{"host-conn", "g1", "s1"} {
		view, err := r.GameSnapshot(viewer)
		if err != nil {
			t.Fatalf("%s projection: %v", viewer, err)
		}
		if len(view.Stack) != 1 || view.Stack[0].Name != stackCard.Name ||
			view.Stack[0].OwnerSeat != 0 {
			t.Fatalf("%s stack projection = %+v", viewer, view.Stack)
		}
	}
	if _, err := r.MoveCard("g1", protocol.GameMoveCard{
		CardID: stackCard.ID, FromZone: protocol.ZoneStack, ToZone: protocol.ZoneGraveyard,
	}); err == nil || err.Error() != protocol.ErrCardNotFound {
		t.Fatalf("opponent stack move err = %v, want %q", err, protocol.ErrCardNotFound)
	}
	if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: stackCard.ID, FromZone: protocol.ZoneStack, ToZone: protocol.ZoneGraveyard,
	}); err != nil {
		t.Fatalf("owner resolves stack to graveyard: %v", err)
	}
	if len(r.Game.Stack) != 0 || len(r.Game.Seats[0].Graveyard) != 1 {
		t.Fatalf("resolved stack = %+v graveyard=%+v",
			r.Game.Stack, r.Game.Seats[0].Graveyard)
	}

	revealResult, err := r.Reveal("host-conn", protocol.GameReveal{
		Zone: protocol.ZoneHand,
	})
	if err != nil {
		t.Fatalf("reveal hand: %v", err)
	}
	if !revealResult.ProjectGame || revealResult.Reply == nil ||
		revealResult.Reply.Type != protocol.TypeGameRevealed {
		t.Fatalf("reveal result = %+v", revealResult)
	}
	var revealReply protocol.GameRevealed
	if err := revealResult.Reply.DecodePayload(&revealReply); err != nil {
		t.Fatalf("decode reveal reply: %v", err)
	}
	if revealReply.Seat != 0 || revealReply.Count != 1 ||
		len(r.Game.Seats[0].Hand) != 0 || len(r.Game.Revealed) != 1 ||
		r.Game.Revealed[0].Name != revealCard.Name {
		t.Fatalf("reveal state/reply = game %+v reply %+v", r.Game, revealReply)
	}
	if r.Game.Log[len(r.Game.Log)-1].Kind != "reveal" {
		t.Fatalf("reveal log = %+v", r.Game.Log)
	}
	for _, viewer := range []string{"host-conn", "g1", "s1"} {
		view, err := r.GameSnapshot(viewer)
		if err != nil {
			t.Fatalf("%s reveal projection: %v", viewer, err)
		}
		if len(view.Revealed) != 1 || view.Revealed[0].Name != revealCard.Name ||
			view.Seats[0].HandCount != 0 {
			t.Fatalf("%s reveal projection = revealed %+v seat %+v",
				viewer, view.Revealed, view.Seats[0])
		}
	}
	if _, err := r.MoveCard("g1", protocol.GameMoveCard{
		CardID: revealCard.ID, FromZone: protocol.ZoneReveal, ToZone: protocol.ZoneHand,
	}); err == nil || err.Error() != protocol.ErrCardNotFound {
		t.Fatalf("opponent return reveal err = %v, want %q", err, protocol.ErrCardNotFound)
	}
	if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: revealCard.ID, FromZone: protocol.ZoneReveal, ToZone: protocol.ZoneHand,
	}); err != nil {
		t.Fatalf("owner returns reveal to hand: %v", err)
	}
	if len(r.Game.Revealed) != 0 || len(r.Game.Seats[0].Hand) != 1 {
		t.Fatalf("returned reveal = %+v hand=%+v", r.Game.Revealed, r.Game.Seats[0].Hand)
	}

	extraCard := protocol.GameCard{
		ID: "s0-c3", Name: "Other Secret", SetCode: "TST", CollectorNumber: "3",
	}
	r.Game.Seats[0].Hand = append(r.Game.Seats[0].Hand, extraCard)
	if _, err := r.Reveal("host-conn", protocol.GameReveal{
		Zone: protocol.ZoneHand, CardIDs: []string{revealCard.ID, revealCard.ID},
	}); err == nil || err.Error() != protocol.ErrInvalidMove {
		t.Fatalf("duplicate reveal card err = %v, want %q", err, protocol.ErrInvalidMove)
	}
	if len(r.Game.Seats[0].Hand) != 2 || len(r.Game.Revealed) != 0 {
		t.Fatalf("duplicate reveal mutated state: hand=%+v revealed=%+v",
			r.Game.Seats[0].Hand, r.Game.Revealed)
	}
	subsetResult, err := r.Reveal("host-conn", protocol.GameReveal{
		Zone: protocol.ZoneHand, CardIDs: []string{revealCard.ID},
	})
	if err != nil {
		t.Fatalf("reveal subset: %v", err)
	}
	var subsetReply protocol.GameRevealed
	if err := subsetResult.Reply.DecodePayload(&subsetReply); err != nil {
		t.Fatalf("decode subset reveal reply: %v", err)
	}
	if subsetReply.Count != 1 || len(r.Game.Revealed) != 1 ||
		r.Game.Revealed[0].ID != revealCard.ID ||
		len(r.Game.Seats[0].Hand) != 1 ||
		r.Game.Seats[0].Hand[0].ID != extraCard.ID {
		t.Fatalf("subset reveal = hand %+v revealed %+v reply %+v",
			r.Game.Seats[0].Hand, r.Game.Revealed, subsetReply)
	}

	if _, err := r.Reveal("host-conn", protocol.GameReveal{
		Zone: "library",
	}); err == nil || err.Error() != protocol.ErrInvalidZone {
		t.Fatalf("invalid reveal zone err = %v, want %q", err, protocol.ErrInvalidZone)
	}
	if _, err := r.Reveal("host-conn", protocol.GameReveal{
		Zone: protocol.ZoneHand, CardIDs: []string{"missing"},
	}); err == nil || err.Error() != protocol.ErrCardNotFound {
		t.Fatalf("missing reveal card err = %v, want %q", err, protocol.ErrCardNotFound)
	}
	if len(r.Game.Seats[0].Hand) != 1 || len(r.Game.Revealed) != 1 {
		t.Fatalf("missing reveal mutated state: hand=%+v revealed=%+v",
			r.Game.Seats[0].Hand, r.Game.Revealed)
	}
	if _, err := r.Reveal("s1", protocol.GameReveal{
		Zone: protocol.ZoneHand,
	}); err == nil || err.Error() != protocol.ErrNotPlayer {
		t.Fatalf("spectator reveal err = %v, want %q", err, protocol.ErrNotPlayer)
	}
}

func TestMoveCardValidatesZonesAndPosition(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{{
			Seat: 0, DisplayName: "Host",
			Hand: []protocol.GameCard{{ID: "s0-c1", Name: "Card"}},
		}},
		NextLogID: 1,
	}
	validPosition := &protocol.CardPosition{X: 0.5, Y: 0.5}
	seatZero := 0
	invalidSeat := 2
	tests := []struct {
		name string
		move protocol.GameMoveCard
		code string
	}{
		{
			name: "unknown source zone",
			move: protocol.GameMoveCard{CardID: "s0-c1", FromZone: "unknown",
				ToZone: protocol.ZoneBattlefield, Position: validPosition},
			code: protocol.ErrInvalidZone,
		},
		{
			name: "battlefield needs position",
			move: protocol.GameMoveCard{CardID: "s0-c1", FromZone: protocol.ZoneHand,
				ToZone: protocol.ZoneBattlefield},
			code: protocol.ErrInvalidPosition,
		},
		{
			name: "position must be normalized",
			move: protocol.GameMoveCard{CardID: "s0-c1", FromZone: protocol.ZoneHand,
				ToZone: protocol.ZoneBattlefield, Position: &protocol.CardPosition{X: 1.1, Y: 0}},
			code: protocol.ErrInvalidPosition,
		},
		{
			name: "non-battlefield rejects position",
			move: protocol.GameMoveCard{CardID: "s0-c1", FromZone: protocol.ZoneHand,
				ToZone: protocol.ZoneGraveyard, Position: validPosition},
			code: protocol.ErrInvalidPosition,
		},
		{
			name: "same hidden zone",
			move: protocol.GameMoveCard{CardID: "s0-c1", FromZone: protocol.ZoneHand,
				ToZone: protocol.ZoneHand},
			code: protocol.ErrInvalidMove,
		},
		{
			name: "hidden source rejects from seat",
			move: protocol.GameMoveCard{CardID: "s0-c1", FromZone: protocol.ZoneHand,
				FromSeat: &seatZero, ToZone: protocol.ZoneBattlefield,
				Position: validPosition},
			code: protocol.ErrInvalidMove,
		},
		{
			name: "public target rejects invalid seat",
			move: protocol.GameMoveCard{CardID: "s0-c1", FromZone: protocol.ZoneHand,
				ToZone: protocol.ZoneExile, ToSeat: &invalidSeat},
			code: protocol.ErrInvalidTarget,
		},
		{
			name: "missing card",
			move: protocol.GameMoveCard{CardID: "missing", FromZone: protocol.ZoneHand,
				ToZone: protocol.ZoneBattlefield, Position: validPosition},
			code: protocol.ErrCardNotFound,
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if _, err := r.MoveCard("host-conn", test.move); err == nil ||
				err.Error() != test.code {
				t.Fatalf("MoveCard error = %v, want %q", err, test.code)
			}
		})
	}
}

func TestMoveCardSupportsLibraryTopAndCrossSeatBattlefields(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("g1", "Guest", false, ""); err != nil {
		t.Fatalf("join guest: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{
				Seat: 0, DisplayName: "Host",
				Library: []protocol.GameCard{
					{ID: "s0-top", Name: "Borrowed Permanent", OwnerSeat: 0},
					{ID: "s0-hidden", Name: "Still Hidden", OwnerSeat: 0},
				},
				Graveyard: []protocol.GameCard{{
					ID: "s0-grave", Name: "Returned Permanent", OwnerSeat: 0,
				}},
				Battlefield: []protocol.GameCard{{
					ID: "s0-field", Name: "Exiled Permanent", OwnerSeat: 0,
				}},
			},
			{
				Seat: 1, DisplayName: "Guest",
				Graveyard: []protocol.GameCard{{
					ID: "s1-grave", Name: "Reanimated Permanent", OwnerSeat: 1,
				}},
			},
		},
		NextLogID: 1,
	}
	targetSeat := 1
	position := &protocol.CardPosition{X: 0.3, Y: 0.4}
	result, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: "__library_top__", FromZone: protocol.ZoneLibrary,
		ToZone: protocol.ZoneBattlefield, ToSeat: &targetSeat, Position: position,
	})
	if err != nil {
		t.Fatalf("move library top across battlefield: %v", err)
	}
	if len(r.Game.Seats[0].Library) != 1 ||
		len(r.Game.Seats[1].Battlefield) != 1 ||
		r.Game.Seats[1].Battlefield[0].OwnerSeat != 0 {
		t.Fatalf("cross-seat state = %+v", r.Game.Seats)
	}
	var moved protocol.GameCardMoved
	if err := result.Reply.DecodePayload(&moved); err != nil {
		t.Fatalf("decode move reply: %v", err)
	}
	if moved.CardID != "s0-top" || moved.ToSeat != 1 {
		t.Fatalf("move reply = %+v", moved)
	}

	if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: "__library_top__", FromZone: protocol.ZoneLibrary,
		ToZone: protocol.ZoneHand,
	}); err != nil {
		t.Fatalf("move library top to hidden hand: %v", err)
	}
	hiddenLog := r.Game.Log[len(r.Game.Log)-1].Text
	if strings.Contains(hiddenLog, "Still Hidden") ||
		len(r.Game.Seats[0].Hand) != 1 {
		t.Fatalf("hidden move leaked: hand=%+v log=%q",
			r.Game.Seats[0].Hand, hiddenLog)
	}

	if _, err := r.SetTapped("g1", protocol.GameSetTapped{
		CardID: "s0-top", Tapped: true,
	}); err != nil {
		t.Fatalf("controller taps donated permanent: %v", err)
	}
	if !r.Game.Seats[1].Battlefield[0].Tapped {
		t.Fatal("donated permanent did not stay tapped")
	}
	if _, err := r.SetTapped("host-conn", protocol.GameSetTapped{
		CardID: "s0-top", Tapped: false,
	}); err == nil || err.Error() != protocol.ErrInvalidTarget {
		t.Fatalf("non-controller tap error = %v, want %q", err, protocol.ErrInvalidTarget)
	}

	if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: "s0-grave", FromZone: protocol.ZoneGraveyard,
		ToZone: protocol.ZoneBattlefield, ToSeat: &targetSeat,
		Position: &protocol.CardPosition{X: 0.6, Y: 0.5},
	}); err != nil {
		t.Fatalf("move graveyard card across battlefield: %v", err)
	}
	if len(r.Game.Seats[1].Battlefield) != 2 {
		t.Fatalf("guest battlefield = %+v", r.Game.Seats[1].Battlefield)
	}

	if _, err := r.MoveCard("g1", protocol.GameMoveCard{
		CardID: "s0-top", FromZone: protocol.ZoneBattlefield,
		ToZone: protocol.ZoneGraveyard,
	}); err != nil {
		t.Fatalf("controller returns donated permanent: %v", err)
	}
	if len(r.Game.Seats[0].Graveyard) != 1 ||
		r.Game.Seats[0].Graveyard[0].ID != "s0-top" {
		t.Fatalf("owner graveyard = %+v", r.Game.Seats[0].Graveyard)
	}

	sourceSeat := 1
	hostSeat := 0
	remoteMove := protocol.GameMoveCard{
		CardID: "s1-grave", FromZone: protocol.ZoneGraveyard,
		FromSeat: &sourceSeat, ToZone: protocol.ZoneBattlefield,
		ToSeat: &hostSeat, Position: &protocol.CardPosition{X: 0.5, Y: 0.4},
	}
	if _, err := r.MoveCard("host-conn", remoteMove); err == nil ||
		err.Error() != protocol.ErrApprovalRequired {
		t.Fatalf("unapproved public-zone move error = %v, want %q",
			err, protocol.ErrApprovalRequired)
	}
	publicMove, err := r.MoveApprovedCard("host-conn", remoteMove)
	if err != nil {
		t.Fatalf("move opponent graveyard card to own battlefield: %v", err)
	}
	var publicMoved protocol.GameCardMoved
	if err := publicMove.Reply.DecodePayload(&publicMoved); err != nil {
		t.Fatalf("decode public-zone move: %v", err)
	}
	if publicMoved.FromSeat != 1 || publicMoved.ToSeat != 0 ||
		len(r.Game.Seats[0].Battlefield) != 2 ||
		r.Game.Seats[0].Battlefield[1].ID != "s1-grave" {
		t.Fatalf("public-zone battlefield move = reply %+v seats %+v",
			publicMoved, r.Game.Seats)
	}
	if got := r.Game.Log[len(r.Game.Log)-1].Text; !strings.Contains(got, "from Guest's graveyard to battlefield") {
		t.Fatalf("remote public-zone log = %q", got)
	}

	if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: "s1-grave", FromZone: protocol.ZoneBattlefield,
		ToZone: protocol.ZoneGraveyard, ToSeat: &hostSeat,
	}); err != nil {
		t.Fatalf("return controlled card to owner graveyard: %v", err)
	}
	if len(r.Game.Seats[0].Graveyard) != 1 ||
		len(r.Game.Seats[1].Graveyard) != 1 ||
		r.Game.Seats[1].Graveyard[0].ID != "s1-grave" {
		t.Fatalf("controlled card graveyard ownership = %+v", r.Game.Seats)
	}
	if _, err := r.MoveApprovedCard("host-conn", protocol.GameMoveCard{
		CardID: "s1-grave", FromZone: protocol.ZoneGraveyard,
		FromSeat: &sourceSeat, ToZone: protocol.ZoneBattlefield,
		ToSeat: &hostSeat, Position: &protocol.CardPosition{X: 0.5, Y: 0.4},
	}); err != nil {
		t.Fatalf("return opponent graveyard card to controlled battlefield: %v", err)
	}
	if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: "s1-grave", FromZone: protocol.ZoneBattlefield,
		ToZone: protocol.ZoneExile, ToSeat: &hostSeat,
	}); err != nil {
		t.Fatalf("return controlled card to owner exile: %v", err)
	}
	if len(r.Game.Seats[0].Exile) != 0 || len(r.Game.Seats[1].Exile) != 1 ||
		r.Game.Seats[1].Exile[0].ID != "s1-grave" {
		t.Fatalf("controlled card exile ownership = %+v", r.Game.Seats)
	}

	opponentZone := 1
	if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: "s0-field", FromZone: protocol.ZoneBattlefield,
		ToZone: protocol.ZoneExile, ToSeat: &opponentZone,
	}); err != nil {
		t.Fatalf("move own battlefield card to exile: %v", err)
	}
	if len(r.Game.Seats[0].Exile) != 1 ||
		r.Game.Seats[0].Exile[0].ID != "s0-field" ||
		r.Game.Seats[0].Exile[0].OwnerSeat != 0 ||
		len(r.Game.Seats[1].Exile) != 1 {
		t.Fatalf("owner-normalized exile = %+v", r.Game.Seats)
	}
}

func TestMoveCardRejectsForeignPublicCardToHiddenZoneWithoutMutation(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("g1", "Guest", false, ""); err != nil {
		t.Fatalf("join guest: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{Seat: 0, DisplayName: "Host"},
			{
				Seat: 1, DisplayName: "Guest",
				Graveyard: []protocol.GameCard{
					{ID: "guest-a", Name: "First", OwnerSeat: 1},
					{ID: "guest-b", Name: "Second", OwnerSeat: 1},
				},
			},
		},
		NextLogID: 1,
	}
	sourceSeat := 1
	for _, destination := range []string{
		protocol.ZoneHand,
		protocol.ZoneLibrary,
	} {
		_, err := r.MoveCard("host-conn", protocol.GameMoveCard{
			CardID: "guest-a", FromZone: protocol.ZoneGraveyard,
			FromSeat: &sourceSeat, ToZone: destination,
		})
		if err == nil || err.Error() != protocol.ErrInvalidTarget {
			t.Fatalf("foreign public card to %s err = %v, want %q",
				destination, err, protocol.ErrInvalidTarget)
		}
		if len(r.Game.Seats[1].Graveyard) != 2 ||
			r.Game.Seats[1].Graveyard[0].ID != "guest-a" ||
			r.Game.Seats[1].Graveyard[1].ID != "guest-b" ||
			len(r.Game.Seats[1].Hand) != 0 ||
			len(r.Game.Seats[1].Library) != 0 ||
			len(r.Game.Log) != 0 {
			t.Fatalf("rejected move to %s mutated state: %+v",
				destination, r.Game)
		}
	}
}

func TestMoveCardValidatesCommanderBeforeRemovingSourceCard(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{{
			Seat: 0, DisplayName: "Host",
			Hand: []protocol.GameCard{
				{ID: "ordinary", Name: "Ordinary", OwnerSeat: 0},
				{ID: "commander", Name: "Commander", OwnerSeat: 0, Commander: true},
			},
		}},
		NextLogID: 1,
	}

	_, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: "ordinary", FromZone: protocol.ZoneHand,
		ToZone: protocol.ZoneCommand,
	})
	if err == nil || err.Error() != protocol.ErrInvalidMove {
		t.Fatalf("non-commander move err = %v, want %q",
			err, protocol.ErrInvalidMove)
	}
	if len(r.Game.Seats[0].Hand) != 2 ||
		r.Game.Seats[0].Hand[0].ID != "ordinary" ||
		r.Game.Seats[0].Hand[1].ID != "commander" ||
		len(r.Game.Seats[0].CommandZone) != 0 ||
		len(r.Game.Log) != 0 {
		t.Fatalf("rejected commander move mutated state: %+v", r.Game)
	}
}

func TestMoveCardRejectsHiddenLibraryToCommandWithoutInspectingTopCard(t *testing.T) {
	for _, topCard := range []protocol.GameCard{
		{ID: "ordinary", Name: "Ordinary", OwnerSeat: 0},
		{ID: "commander", Name: "Commander", OwnerSeat: 0, Commander: true},
	} {
		r := newTestRoom(t, 2, true)
		r.Format = protocol.FormatEDH
		r.Phase = protocol.RoomPhaseStarted
		r.Game = &GameState{
			Number: 1,
			Seats: []PlayerGameState{{
				Seat: 0, DisplayName: "Host",
				Library: []protocol.GameCard{topCard},
			}},
			NextLogID: 1,
		}

		_, err := r.MoveCard("host-conn", protocol.GameMoveCard{
			FromZone: protocol.ZoneLibrary,
			ToZone:   protocol.ZoneCommand,
		})
		if err == nil || err.Error() != protocol.ErrInvalidMove {
			t.Fatalf("library top commander=%v err = %v, want %q",
				topCard.Commander, err, protocol.ErrInvalidMove)
		}
		if len(r.Game.Seats[0].Library) != 1 ||
			r.Game.Seats[0].Library[0].ID != topCard.ID ||
			len(r.Game.Seats[0].CommandZone) != 0 ||
			len(r.Game.Log) != 0 {
			t.Fatalf("rejected hidden commander move mutated state: %+v", r.Game)
		}
	}
}

func TestRecallRevealedAndBatchBattlefieldMoves(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{
				Seat: 0, DisplayName: "Host",
				Battlefield: []protocol.GameCard{
					{ID: "field-a", Name: "First", OwnerSeat: 0},
					{ID: "field-b", Name: "Second", OwnerSeat: 0, Tapped: true},
				},
			},
			{Seat: 1, DisplayName: "Guest"},
		},
		Revealed: []protocol.GameSharedCard{
			{GameCard: protocol.GameCard{ID: "reveal-a", Name: "Secret A", OwnerSeat: 0}},
			{GameCard: protocol.GameCard{ID: "reveal-b", Name: "Secret B", OwnerSeat: 0}},
			{GameCard: protocol.GameCard{ID: "reveal-other", Name: "Other", OwnerSeat: 1}},
		},
		NextLogID: 1,
	}

	recall, err := r.RecallRevealed("host-conn")
	if err != nil {
		t.Fatalf("recall revealed: %v", err)
	}
	var recalled protocol.GameRevealedRecalled
	if recall.Reply == nil || recall.Reply.DecodePayload(&recalled) != nil ||
		recalled.Count != 2 || len(r.Game.Seats[0].Hand) != 2 ||
		len(r.Game.Revealed) != 1 || r.Game.Revealed[0].OwnerSeat != 1 {
		t.Fatalf("recall result/state = %+v %+v", recalled, r.Game)
	}

	moved, err := r.MoveCards("host-conn", protocol.GameMoveCards{
		CardIDs:          []string{"field-b", "field-a"},
		FromZone:         protocol.ZoneBattlefield,
		ToZone:           protocol.ZoneLibrary,
		LibraryPlacement: protocol.LibraryPlacementBottom,
	})
	if err != nil {
		t.Fatalf("batch move: %v", err)
	}
	var reply protocol.GameCardsMoved
	if moved.Reply == nil || moved.Reply.DecodePayload(&reply) != nil ||
		reply.Count != 2 || len(r.Game.Seats[0].Battlefield) != 0 ||
		len(r.Game.Seats[0].Library) != 2 ||
		r.Game.Seats[0].Library[0].ID != "field-b" ||
		r.Game.Seats[0].Library[1].ID != "field-a" ||
		r.Game.Seats[0].Library[0].Tapped {
		t.Fatalf("batch result/state = %+v %+v", reply, r.Game.Seats[0])
	}
}

func TestBatchGraveyardMovesPreserveSelectionAndOwnership(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{
				Seat: 0, DisplayName: "Host",
				Graveyard: []protocol.GameCard{
					{ID: "grave-a", Name: "First", OwnerSeat: 0},
					{ID: "grave-b", Name: "Second", OwnerSeat: 0},
					{ID: "grave-foreign", Name: "Foreign", OwnerSeat: 1},
				},
			},
			{Seat: 1, DisplayName: "Guest"},
		},
		NextLogID: 1,
	}
	sourceSeat, targetSeat := 0, 1

	moved, err := r.MoveCards("host-conn", protocol.GameMoveCards{
		CardIDs:  []string{"grave-b", "grave-a"},
		FromZone: protocol.ZoneGraveyard,
		FromSeat: &sourceSeat,
		ToZone:   protocol.ZoneExile,
		ToSeat:   &targetSeat,
	})
	if err != nil {
		t.Fatalf("batch graveyard move: %v", err)
	}
	var reply protocol.GameCardsMoved
	if moved.Reply == nil || moved.Reply.DecodePayload(&reply) != nil ||
		reply.Count != 2 || len(r.Game.Seats[0].Graveyard) != 1 ||
		r.Game.Seats[0].Graveyard[0].ID != "grave-foreign" ||
		len(r.Game.Seats[0].Exile) != 2 ||
		r.Game.Seats[0].Exile[0].ID != "grave-b" ||
		r.Game.Seats[0].Exile[1].ID != "grave-a" ||
		r.Game.Seats[0].Exile[0].OwnerSeat != 0 ||
		len(r.Game.Seats[1].Exile) != 0 {
		t.Fatalf("graveyard batch result/state = %+v %+v", reply, r.Game.Seats)
	}

	_, err = r.MoveCards("host-conn", protocol.GameMoveCards{
		CardIDs:  []string{"grave-foreign"},
		FromZone: protocol.ZoneGraveyard,
		FromSeat: &sourceSeat,
		ToZone:   protocol.ZoneHand,
	})
	if err == nil || err.Error() != protocol.ErrInvalidTarget ||
		len(r.Game.Seats[0].Graveyard) != 1 ||
		len(r.Game.Seats[0].Hand) != 0 {
		t.Fatalf("foreign hidden-zone batch err/state = %v %+v", err, r.Game.Seats)
	}
}

func TestBatchExileMoveToLibraryPreservesSelectionOrder(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{
				Seat: 0, DisplayName: "Host",
				Library: []protocol.GameCard{
					{ID: "library-old", Name: "Existing", OwnerSeat: 0},
				},
				Exile: []protocol.GameCard{
					{ID: "exile-a", Name: "First", OwnerSeat: 0},
					{ID: "exile-b", Name: "Second", OwnerSeat: 0},
				},
			},
			{Seat: 1, DisplayName: "Guest"},
		},
		NextLogID: 1,
	}
	sourceSeat := 0

	moved, err := r.MoveCards("host-conn", protocol.GameMoveCards{
		CardIDs:  []string{"exile-b", "exile-a"},
		FromZone: protocol.ZoneExile,
		FromSeat: &sourceSeat,
		ToZone:   protocol.ZoneLibrary,
	})
	if err != nil {
		t.Fatalf("batch exile to library: %v", err)
	}
	var reply protocol.GameCardsMoved
	if moved.Reply == nil || moved.Reply.DecodePayload(&reply) != nil ||
		reply.Count != 2 || len(r.Game.Seats[0].Exile) != 0 ||
		len(r.Game.Seats[0].Library) != 3 ||
		r.Game.Seats[0].Library[0].ID != "exile-b" ||
		r.Game.Seats[0].Library[1].ID != "exile-a" ||
		r.Game.Seats[0].Library[2].ID != "library-old" {
		t.Fatalf("exile batch result/state = %+v %+v", reply, r.Game.Seats[0])
	}
	if len(r.Game.Log) != 1 ||
		!strings.Contains(r.Game.Log[0].Text,
			"Host moved 2 card(s) from exile to library") {
		t.Fatalf("exile batch log = %+v", r.Game.Log)
	}
}

func TestBatchGraveyardMoveToBattlefieldUsesAnchor(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{
				Seat: 0, DisplayName: "Host",
				Graveyard: []protocol.GameCard{
					{ID: "grave-a", Name: "First", OwnerSeat: 0},
					{ID: "grave-b", Name: "Second", OwnerSeat: 0},
				},
			},
			{Seat: 1, DisplayName: "Guest"},
		},
		NextLogID: 1,
	}
	sourceSeat, targetSeat := 0, 0
	anchor := &protocol.CardPosition{X: 0.5, Y: 0.3}

	_, err := r.MoveCards("host-conn", protocol.GameMoveCards{
		CardIDs:  []string{"grave-a", "grave-b"},
		FromZone: protocol.ZoneGraveyard,
		FromSeat: &sourceSeat,
		ToZone:   protocol.ZoneBattlefield,
		ToSeat:   &targetSeat,
		Position: anchor,
	})
	if err != nil {
		t.Fatalf("batch graveyard to battlefield: %v", err)
	}
	if len(r.Game.Seats[0].Graveyard) != 0 ||
		len(r.Game.Seats[0].Battlefield) != 2 ||
		r.Game.Seats[0].Battlefield[0].Position == nil ||
		r.Game.Seats[0].Battlefield[1].Position == nil ||
		*r.Game.Seats[0].Battlefield[0].Position ==
			*r.Game.Seats[0].Battlefield[1].Position {
		t.Fatalf("battlefield batch positions = %+v", r.Game.Seats[0])
	}
}

func TestRemoteBatchPublicZoneMoveRequiresApprovalAndNamesSource(t *testing.T) {
	for _, sourceZone := range []string{protocol.ZoneGraveyard, protocol.ZoneExile} {
		t.Run(sourceZone, func(t *testing.T) {
			r := newTestRoom(t, 2, true)
			if _, err := r.Join("g1", "Guest", false, ""); err != nil {
				t.Fatalf("join guest: %v", err)
			}
			r.Phase = protocol.RoomPhaseStarted
			r.Game = &GameState{
				Number: 1,
				Seats: []PlayerGameState{
					{Seat: 0, DisplayName: "Host"},
					{Seat: 1, DisplayName: "Guest"},
				},
				NextLogID: 1,
			}
			cards := playerGameZone(&r.Game.Seats[1], sourceZone)
			*cards = []protocol.GameCard{
				{ID: "guest-a", Name: "First", OwnerSeat: 1},
				{ID: "guest-b", Name: "Second", OwnerSeat: 1},
			}
			sourceSeat, targetSeat := 1, 0
			move := protocol.GameMoveCards{
				CardIDs:  []string{"guest-a", "guest-b"},
				FromZone: sourceZone,
				FromSeat: &sourceSeat,
				ToZone:   protocol.ZoneBattlefield,
				ToSeat:   &targetSeat,
				Position: &protocol.CardPosition{X: 0.5, Y: 0.5},
			}
			if _, err := r.MoveCards("host-conn", move); err == nil ||
				err.Error() != protocol.ErrApprovalRequired {
				t.Fatalf("unapproved remote batch error = %v, want %q",
					err, protocol.ErrApprovalRequired)
			}
			if len(*cards) != 2 || len(r.Game.Seats[0].Battlefield) != 0 ||
				len(r.Game.Log) != 0 {
				t.Fatalf("unapproved remote batch mutated state: %+v", r.Game)
			}
			if _, err := r.MoveApprovedCards("host-conn", move); err != nil {
				t.Fatalf("approved remote batch: %v", err)
			}
			if len(*cards) != 0 || len(r.Game.Seats[0].Battlefield) != 2 {
				t.Fatalf("approved remote batch state = %+v", r.Game.Seats)
			}
			expectedLog := "Host moved 2 card(s) from Guest's " +
				sourceZone + " to battlefield"
			if len(r.Game.Log) != 1 ||
				!strings.Contains(r.Game.Log[0].Text, expectedLog) {
				t.Fatalf("remote batch log = %+v", r.Game.Log)
			}
		})
	}
}

func TestMoveCardSupportsSideboardToBattlefield(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{{
			Seat: 0, DisplayName: "Host",
			Sideboard: []protocol.GameCard{{
				ID: "s0-sideboard", Name: "Sideboard Card", OwnerSeat: 0,
			}},
		}},
		NextLogID: 1,
	}
	position := &protocol.CardPosition{X: 0.5, Y: 0.3}

	result, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID:   "s0-sideboard",
		FromZone: protocol.ZoneSideboard,
		ToZone:   protocol.ZoneBattlefield,
		Position: position,
	})
	if err != nil {
		t.Fatalf("move sideboard card to battlefield: %v", err)
	}
	var moved protocol.GameCardMoved
	if result.Reply == nil || result.Reply.DecodePayload(&moved) != nil ||
		len(r.Game.Seats[0].Sideboard) != 0 ||
		len(r.Game.Seats[0].Battlefield) != 1 ||
		r.Game.Seats[0].Battlefield[0].ID != "s0-sideboard" ||
		r.Game.Seats[0].Battlefield[0].Position == nil ||
		*r.Game.Seats[0].Battlefield[0].Position != *position {
		t.Fatalf("sideboard move result/state = %+v %+v", moved, r.Game.Seats[0])
	}
}

func TestMoveLibraryCardsToPublicZone(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{{
			Seat: 0, DisplayName: "Host",
			Library: []protocol.GameCard{
				{ID: "top-a", Name: "First", OwnerSeat: 0},
				{ID: "top-b", Name: "Second", OwnerSeat: 0},
				{ID: "rest", Name: "Third", OwnerSeat: 0},
			},
		}},
		NextLogID: 1,
	}

	result, err := r.MoveLibraryCards("host-conn", protocol.GameMoveLibraryCards{
		Count:  2,
		ToZone: protocol.ZoneExile,
	})
	if err != nil {
		t.Fatalf("move library cards: %v", err)
	}
	var moved protocol.GameLibraryCardsMoved
	state := r.Game.Seats[0]
	if result.Reply == nil || result.Reply.DecodePayload(&moved) != nil ||
		moved.Count != 2 || moved.ToZone != protocol.ZoneExile ||
		len(state.Library) != 1 || state.Library[0].ID != "rest" ||
		len(state.Exile) != 2 || state.Exile[0].ID != "top-a" ||
		state.Exile[1].ID != "top-b" {
		t.Fatalf("move result/state = %+v %+v", moved, state)
	}
	if len(r.Game.Log) != 1 ||
		strings.Contains(r.Game.Log[0].Text, "First") ||
		!strings.Contains(r.Game.Log[0].Text, "2 card(s)") {
		t.Fatalf("move library log = %+v", r.Game.Log)
	}
}

func TestLibraryTopViewReorderAndMultiSearch(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{{
			Seat: 0, DisplayName: "Host",
			Library: []protocol.GameCard{
				{ID: "top-a", Name: "First"},
				{ID: "top-b", Name: "Second"},
				{ID: "rest", Name: "Third"},
			},
		}},
		NextLogID: 1,
	}

	dump, err := r.DumpZone("host-conn", protocol.GameDumpZone{
		Zone: protocol.ZoneLibrary, TopCount: 2,
	})
	if err != nil {
		t.Fatalf("dump top cards: %v", err)
	}
	var viewed protocol.GameZoneDumped
	if dump.Reply == nil || dump.Reply.DecodePayload(&viewed) != nil ||
		viewed.TopCount != 2 || len(viewed.Cards) != 2 ||
		viewed.Cards[1].ID != "top-b" {
		t.Fatalf("top view = %+v", viewed)
	}

	if _, err := r.ReorderLibrary("host-conn", protocol.GameReorderLibrary{
		CardIDs: []string{"top-b", "top-a"},
	}); err != nil {
		t.Fatalf("reorder top cards: %v", err)
	}
	if got := r.Game.Seats[0].Library; got[0].ID != "top-b" ||
		got[1].ID != "top-a" || got[2].ID != "rest" {
		t.Fatalf("reordered library = %+v", got)
	}

	result, err := r.SearchLibrary("host-conn", protocol.GameSearchLibrary{
		CardIDs: []string{"top-b", "top-a"},
		ToZone:  protocol.LibraryDestinationGraveyard,
	})
	if err != nil {
		t.Fatalf("multi-card search: %v", err)
	}
	var searched protocol.GameLibrarySearched
	if result.Reply == nil || result.Reply.DecodePayload(&searched) != nil ||
		searched.Count != 2 || len(r.Game.Seats[0].Library) != 1 ||
		len(r.Game.Seats[0].Graveyard) != 2 ||
		r.Game.Seats[0].Graveyard[0].ID != "top-b" ||
		r.Game.Seats[0].Graveyard[1].ID != "top-a" {
		t.Fatalf("multi search result/state = %+v %+v", searched, r.Game.Seats[0])
	}
}

func TestResolveLibraryViewKeepsSelectedCardsInSourceLibrary(t *testing.T) {
	tests := []struct {
		name               string
		toZone             string
		remainderPlacement string
		wantIDs            []string
	}{
		{
			name:               "selected bottom remainder top",
			toZone:             protocol.LibraryDestinationBottom,
			remainderPlacement: protocol.LibraryPlacementTop,
			wantIDs:            []string{"a", "d", "e", "c", "b"},
		},
		{
			name:               "selected bottom remainder bottom",
			toZone:             protocol.LibraryDestinationBottom,
			remainderPlacement: protocol.LibraryPlacementBottom,
			wantIDs:            []string{"e", "a", "d", "c", "b"},
		},
		{
			name:               "selected top remainder bottom",
			toZone:             protocol.LibraryDestinationTop,
			remainderPlacement: protocol.LibraryPlacementBottom,
			wantIDs:            []string{"c", "b", "e", "a", "d"},
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			r := newTestRoom(t, 2, true)
			r.Phase = protocol.RoomPhaseStarted
			r.Game = &GameState{
				Number: 1,
				Seats: []PlayerGameState{{
					Seat: 0, DisplayName: "Host",
					Library: []protocol.GameCard{
						{ID: "a", Name: "A"},
						{ID: "b", Name: "B"},
						{ID: "c", Name: "C"},
						{ID: "d", Name: "D"},
						{ID: "e", Name: "E"},
					},
				}},
				NextLogID: 1,
			}
			result, err := r.ResolveLibraryView("host-conn", protocol.GameResolveLibraryView{
				SelectedCardIDs:    []string{"c", "b"},
				RemainderCardIDs:   []string{"a", "d"},
				ToZone:             tc.toZone,
				RemainderPlacement: tc.remainderPlacement,
			})
			if err != nil {
				t.Fatalf("resolve library view: %v", err)
			}
			got := r.Game.Seats[0].Library
			if len(got) != len(tc.wantIDs) {
				t.Fatalf("library = %+v, want %v", got, tc.wantIDs)
			}
			for index, id := range tc.wantIDs {
				if got[index].ID != id {
					t.Fatalf("library = %+v, want %v", got, tc.wantIDs)
				}
			}
			if len(r.Game.Seats[0].Hand) != 0 ||
				len(r.Game.Seats[0].Battlefield) != 0 {
				t.Fatalf("selected cards left the source library: hand=%+v battlefield=%+v",
					r.Game.Seats[0].Hand, r.Game.Seats[0].Battlefield)
			}
			var reply protocol.GameLibraryViewResolved
			if result.Reply == nil || result.Reply.DecodePayload(&reply) != nil ||
				reply.MovedCount != 2 || reply.RemainderCount != 2 {
				t.Fatalf("reply = %+v", reply)
			}
			destination := "on bottom of their library"
			if tc.toZone == protocol.LibraryDestinationTop {
				destination = "on top of their library"
			}
			if len(r.Game.Log) != 1 ||
				!strings.Contains(r.Game.Log[0].Text, "put 2 card(s) "+destination) ||
				strings.Contains(r.Game.Log[0].Text, "A") {
				t.Fatalf("log = %+v", r.Game.Log)
			}
		})
	}
}

func TestResolveLibraryViewRejectsFaceDownLibraryDestination(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{{
			Seat: 0, DisplayName: "Host",
			Library: []protocol.GameCard{
				{ID: "a", Name: "A"},
				{ID: "b", Name: "B"},
			},
		}},
		NextLogID: 1,
	}
	if _, err := r.ResolveLibraryView("host-conn", protocol.GameResolveLibraryView{
		SelectedCardIDs:    []string{"a"},
		RemainderCardIDs:   []string{"b"},
		ToZone:             protocol.LibraryDestinationBottom,
		RemainderPlacement: protocol.LibraryPlacementTop,
		FaceDown:           true,
	}); err == nil || err.Error() != protocol.ErrInvalidMove {
		t.Fatalf("face-down library bottom err = %v, want %q",
			err, protocol.ErrInvalidMove)
	}
}

func TestLibraryDumpAndSearchPreserveHiddenInformation(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("g1", "Guest", false, ""); err != nil {
		t.Fatalf("join guest: %v", err)
	}
	if _, err := r.Join("s1", "Spectator", true, ""); err != nil {
		t.Fatalf("join spectator: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	secret := protocol.GameCard{
		ID: "s0-c1", Name: "Demonic Tutor", SetCode: "STA", CollectorNumber: "27",
	}
	public := protocol.GameCard{
		ID: "s0-c2", Name: "Island", SetCode: "M21", CollectorNumber: "265",
	}
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{
				Seat: 0, DisplayName: "Host",
				Library: []protocol.GameCard{secret, public},
				Hand:    []protocol.GameCard{},
			},
			{
				Seat: 1, DisplayName: "Guest",
				Library: []protocol.GameCard{{
					ID: "s1-c1", Name: "Opponent Secret",
				}},
			},
		},
		Log:       []protocol.GameLogEntry{},
		NextLogID: 1,
	}

	dumpResult, err := r.DumpZone("host-conn", protocol.GameDumpZone{Zone: "library"})
	if err != nil {
		t.Fatalf("dump library: %v", err)
	}
	if !dumpResult.ProjectGame || dumpResult.Reply == nil ||
		dumpResult.Reply.Type != protocol.TypeGameZoneDumped {
		t.Fatalf("dump result = %+v", dumpResult)
	}
	var dump protocol.GameZoneDumped
	if err := dumpResult.Reply.DecodePayload(&dump); err != nil {
		t.Fatalf("decode dump: %v", err)
	}
	if dump.RoomID != r.ID || dump.Zone != "library" ||
		len(dump.Cards) != 2 || dump.Cards[0].Name != secret.Name {
		t.Fatalf("dump payload = %+v", dump)
	}
	dump.Cards[0].Name = "mutated clone"
	if r.Game.Seats[0].Library[0].Name != secret.Name {
		t.Fatal("dump returned mutable server state")
	}
	if len(r.Game.Log) != 1 ||
		r.Game.Log[0].Kind != "library_search" ||
		r.Game.Log[0].Text != "Host is searching their library." {
		t.Fatalf("library dump log = %+v", r.Game.Log)
	}
	if _, err := r.DumpZone("s1", protocol.GameDumpZone{Zone: "library"}); err == nil || err.Error() != protocol.ErrNotPlayer {
		t.Fatalf("spectator dump err = %v, want %q", err, protocol.ErrNotPlayer)
	}
	if _, err := r.DumpZone("host-conn", protocol.GameDumpZone{Zone: protocol.ZoneHand}); err == nil || err.Error() != protocol.ErrInvalidZone {
		t.Fatalf("hand dump err = %v, want %q", err, protocol.ErrInvalidZone)
	}

	hiddenResult, err := r.SearchLibrary("host-conn", protocol.GameSearchLibrary{
		CardID: secret.ID, ToZone: protocol.LibraryDestinationHand, Reveal: false,
	})
	if err != nil {
		t.Fatalf("hidden search: %v", err)
	}
	if !hiddenResult.ProjectGame || hiddenResult.Reply == nil ||
		hiddenResult.Reply.Type != protocol.TypeGameLibrarySearched {
		t.Fatalf("hidden search result = %+v", hiddenResult)
	}
	var searched protocol.GameLibrarySearched
	if err := hiddenResult.Reply.DecodePayload(&searched); err != nil {
		t.Fatalf("decode search reply: %v", err)
	}
	if searched.Seat != 0 || searched.ToZone != protocol.LibraryDestinationHand ||
		searched.Revealed || len(r.Game.Seats[0].Library) != 1 ||
		len(r.Game.Seats[0].Hand) != 1 ||
		r.Game.Seats[0].Hand[0].Name != secret.Name {
		t.Fatalf("hidden search state/reply = game %+v reply %+v", r.Game, searched)
	}
	hiddenLog := r.Game.Log[len(r.Game.Log)-1]
	if hiddenLog.Kind != "library_search" ||
		strings.Contains(hiddenLog.Text, secret.Name) ||
		!strings.Contains(hiddenLog.Text, "1 card(s) into hand") {
		t.Fatalf("hidden search log = %+v", hiddenLog)
	}
	for _, viewer := range []string{"g1", "s1"} {
		view, err := r.GameSnapshot(viewer)
		if err != nil {
			t.Fatalf("%s snapshot: %v", viewer, err)
		}
		encoded, err := json.Marshal(view)
		if err != nil {
			t.Fatalf("marshal %s snapshot: %v", viewer, err)
		}
		if strings.Contains(string(encoded), secret.Name) ||
			len(view.Seats[0].Hand) != 0 || view.Seats[0].HandCount != 1 {
			t.Fatalf("%s leaked hidden search: %s", viewer, encoded)
		}
	}

	revealResult, err := r.SearchLibrary("host-conn", protocol.GameSearchLibrary{
		CardID: public.ID, ToZone: protocol.LibraryDestinationGraveyard, Reveal: true,
	})
	if err != nil {
		t.Fatalf("revealed search: %v", err)
	}
	if !revealResult.ProjectGame || len(r.Game.Seats[0].Graveyard) != 1 {
		t.Fatalf("revealed search result/state = %+v %+v", revealResult, r.Game)
	}
	revealLog := r.Game.Log[len(r.Game.Log)-1]
	if !strings.Contains(revealLog.Text, public.Name) ||
		!strings.Contains(revealLog.Text, "into graveyard") {
		t.Fatalf("revealed search log = %+v", revealLog)
	}
	guestView, err := r.GameSnapshot("g1")
	if err != nil {
		t.Fatalf("guest snapshot: %v", err)
	}
	if len(guestView.Seats[0].Graveyard) != 1 ||
		guestView.Seats[0].Graveyard[0].Name != public.Name {
		t.Fatalf("public searched card missing from guest view: %+v", guestView.Seats[0])
	}
}

func TestLibrarySearchDestinationsAndValidation(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Phase = protocol.RoomPhaseStarted
	cards := []protocol.GameCard{
		{ID: "hand", Name: "To Hand"},
		{ID: "battlefield-a", Name: "To Battlefield A"},
		{ID: "battlefield-b", Name: "To Battlefield B"},
		{ID: "top", Name: "To Top"},
		{ID: "bottom", Name: "To Bottom"},
		{ID: "graveyard", Name: "To Graveyard"},
		{ID: "exile", Name: "To Exile"},
	}
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{{
			Seat: 0, DisplayName: "Host", Library: append([]protocol.GameCard{}, cards...),
		}},
		NextLogID: 1,
	}
	position := &protocol.CardPosition{X: 0.4, Y: 0.6}
	searches := []protocol.GameSearchLibrary{
		{CardID: "hand", ToZone: protocol.LibraryDestinationHand},
		{CardIDs: []string{"battlefield-a", "battlefield-b"},
			ToZone: protocol.LibraryDestinationBattlefield, Position: position},
		{CardID: "graveyard", ToZone: protocol.LibraryDestinationGraveyard},
		{CardID: "exile", ToZone: protocol.LibraryDestinationExile},
		{CardID: "top", ToZone: protocol.LibraryDestinationTop},
		{CardID: "bottom", ToZone: protocol.LibraryDestinationBottom},
	}
	for _, search := range searches {
		if _, err := r.SearchLibrary("host-conn", search); err != nil {
			t.Fatalf("search %+v: %v", search, err)
		}
	}
	state := r.Game.Seats[0]
	if len(state.Hand) != 1 || state.Hand[0].ID != "hand" ||
		len(state.Battlefield) != 2 || state.Battlefield[0].ID != "battlefield-a" ||
		state.Battlefield[1].ID != "battlefield-b" ||
		state.Battlefield[0].Position == nil || state.Battlefield[1].Position == nil ||
		state.Battlefield[0].Position.X == state.Battlefield[1].Position.X ||
		len(state.Graveyard) != 1 || state.Graveyard[0].ID != "graveyard" ||
		len(state.Exile) != 1 || state.Exile[0].ID != "exile" ||
		len(state.Library) != 2 || state.Library[0].ID != "top" ||
		state.Library[1].ID != "bottom" {
		t.Fatalf("search destinations = %+v", state)
	}

	validationRoom := newTestRoom(t, 2, true)
	validationRoom.Phase = protocol.RoomPhaseStarted
	validationRoom.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{{
			Seat: 0, DisplayName: "Host",
			Library: []protocol.GameCard{{ID: "card", Name: "Card"}},
		}},
		NextLogID: 1,
	}
	tests := []struct {
		name    string
		request protocol.GameSearchLibrary
		code    string
	}{
		{
			name: "missing card id",
			request: protocol.GameSearchLibrary{
				ToZone: protocol.LibraryDestinationHand,
			},
			code: protocol.ErrInvalidMove,
		},
		{
			name: "invalid destination",
			request: protocol.GameSearchLibrary{
				CardID: "card", ToZone: protocol.ZoneStack,
			},
			code: protocol.ErrInvalidZone,
		},
		{
			name: "battlefield needs position",
			request: protocol.GameSearchLibrary{
				CardID: "card", ToZone: protocol.LibraryDestinationBattlefield,
			},
			code: protocol.ErrInvalidPosition,
		},
		{
			name: "non-battlefield rejects position",
			request: protocol.GameSearchLibrary{
				CardID: "card", ToZone: protocol.LibraryDestinationHand,
				Position: position,
			},
			code: protocol.ErrInvalidPosition,
		},
		{
			name: "missing instance",
			request: protocol.GameSearchLibrary{
				CardID: "missing", ToZone: protocol.LibraryDestinationHand,
			},
			code: protocol.ErrCardNotFound,
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if _, err := validationRoom.SearchLibrary("host-conn", test.request); err == nil || err.Error() != test.code {
				t.Fatalf("SearchLibrary err = %v, want %q", err, test.code)
			}
			if len(validationRoom.Game.Seats[0].Library) != 1 {
				t.Fatalf("validation mutated library: %+v",
					validationRoom.Game.Seats[0].Library)
			}
		})
	}
	if _, err := validationRoom.SearchLibrary("unknown", protocol.GameSearchLibrary{
		CardID: "card", ToZone: protocol.LibraryDestinationHand,
	}); err == nil || err.Error() != protocol.ErrNotInRoom {
		t.Fatalf("non-member search err = %v, want %q", err, protocol.ErrNotInRoom)
	}
}

func TestApprovedRemoteLibrarySearchDestinationSeat(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("guest-conn", "Guest", false, ""); err != nil {
		t.Fatalf("join guest: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	sourceSeat := 1
	requesterSeat := 0
	card := protocol.GameCard{ID: "remote-card", Name: "Remote Card", OwnerSeat: 1}
	graveCard := protocol.GameCard{
		ID: "remote-grave-card", Name: "Remote Grave Card", OwnerSeat: 1,
	}
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{Seat: 0, DisplayName: "Host"},
			{Seat: 1, DisplayName: "Guest", Library: []protocol.GameCard{card, graveCard}},
		},
		NextLogID: 1,
	}

	result, err := r.SearchApprovedLibrary("host-conn", protocol.GameSearchLibrary{
		CardID:     card.ID,
		SourceSeat: &sourceSeat,
		ApprovalID: "approved",
		ToZone:     protocol.LibraryDestinationHand,
		ToSeat:     &requesterSeat,
	})
	if err != nil {
		t.Fatalf("remote search: %v", err)
	}
	if len(r.Game.Seats[0].Hand) != 1 ||
		r.Game.Seats[0].Hand[0].ID != card.ID ||
		r.Game.Seats[0].Hand[0].OwnerSeat != sourceSeat {
		t.Fatalf("requester hand = %+v", r.Game.Seats[0].Hand)
	}
	var reply protocol.GameLibrarySearched
	if result.Reply == nil || result.Reply.DecodePayload(&reply) != nil ||
		reply.SourceSeat != sourceSeat || reply.ToSeat != requesterSeat {
		t.Fatalf("remote search reply = %+v", reply)
	}

	result, err = r.SearchApprovedLibrary("host-conn", protocol.GameSearchLibrary{
		CardID:     graveCard.ID,
		SourceSeat: &sourceSeat,
		ApprovalID: "approved",
		ToZone:     protocol.LibraryDestinationGraveyard,
		ToSeat:     &requesterSeat,
	})
	if err != nil {
		t.Fatalf("remote search to owner graveyard: %v", err)
	}
	reply = protocol.GameLibrarySearched{}
	if result.Reply == nil || result.Reply.DecodePayload(&reply) != nil ||
		reply.ToSeat != sourceSeat || len(r.Game.Seats[0].Graveyard) != 0 ||
		len(r.Game.Seats[1].Graveyard) != 1 ||
		r.Game.Seats[1].Graveyard[0].ID != graveCard.ID {
		t.Fatalf("remote owner graveyard state/reply = %+v %+v", reply, r.Game.Seats)
	}

	otherSeat := 1
	if _, err := r.SearchLibrary("host-conn", protocol.GameSearchLibrary{
		CardID: "missing", ToZone: protocol.LibraryDestinationHand,
		ToSeat: &otherSeat,
	}); err == nil || err.Error() != protocol.ErrInvalidTarget {
		t.Fatalf("own search to remote seat err = %v", err)
	}
}

func TestApprovedRemoteLibraryViewUsesSourcePrefixAndRequesterDestination(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("guest-conn", "Guest", false, ""); err != nil {
		t.Fatalf("join guest: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	sourceSeat := 1
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{Seat: 0, DisplayName: "Host"},
			{Seat: 1, DisplayName: "Guest", Library: []protocol.GameCard{
				{ID: "remote-1", Name: "Remote One", OwnerSeat: 1},
				{ID: "remote-2", Name: "Remote Two", OwnerSeat: 1},
				{ID: "remote-3", Name: "Remote Three", OwnerSeat: 1},
				{ID: "remote-4", Name: "Remote Four", OwnerSeat: 1},
			}},
		},
		NextLogID: 1,
	}
	request := protocol.GameResolveLibraryView{
		SelectedCardIDs:    []string{"remote-1"},
		RemainderCardIDs:   []string{"remote-3", "remote-2"},
		ToZone:             protocol.LibraryDestinationHand,
		SourceSeat:         &sourceSeat,
		ApprovalID:         "approved",
		RemainderPlacement: protocol.LibraryPlacementBottom,
	}
	if _, err := r.ResolveLibraryView("host-conn", request); err == nil ||
		err.Error() != protocol.ErrApprovalRequired {
		t.Fatalf("unapproved remote resolve err = %v, want %q",
			err, protocol.ErrApprovalRequired)
	}
	result, err := r.ResolveApprovedLibraryView("host-conn", request)
	if err != nil {
		t.Fatalf("approved remote resolve: %v", err)
	}
	if len(r.Game.Seats[0].Hand) != 1 ||
		r.Game.Seats[0].Hand[0].ID != "remote-1" ||
		r.Game.Seats[0].Hand[0].OwnerSeat != sourceSeat {
		t.Fatalf("requester hand = %+v", r.Game.Seats[0].Hand)
	}
	library := r.Game.Seats[1].Library
	if len(library) != 3 || library[0].ID != "remote-4" ||
		library[1].ID != "remote-3" || library[2].ID != "remote-2" {
		t.Fatalf("source library = %+v", library)
	}
	var reply protocol.GameLibraryViewResolved
	if result.Reply == nil || result.Reply.DecodePayload(&reply) != nil ||
		reply.Seat != 0 || reply.MovedCount != 1 || reply.RemainderCount != 2 {
		t.Fatalf("remote resolve reply = %+v", reply)
	}
}

func TestApprovedRemoteLibraryViewPutsSelectedCardsOnSourceLibraryBottom(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("guest-conn", "Guest", false, ""); err != nil {
		t.Fatalf("join guest: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	sourceSeat := 1
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{Seat: 0, DisplayName: "Host"},
			{Seat: 1, DisplayName: "Guest", Library: []protocol.GameCard{
				{ID: "remote-1", Name: "Remote One", OwnerSeat: 1},
				{ID: "remote-2", Name: "Remote Two", OwnerSeat: 1},
				{ID: "remote-3", Name: "Remote Three", OwnerSeat: 1},
				{ID: "remote-4", Name: "Remote Four", OwnerSeat: 1},
			}},
		},
		NextLogID: 1,
	}
	result, err := r.ResolveApprovedLibraryView("host-conn", protocol.GameResolveLibraryView{
		SelectedCardIDs:    []string{"remote-2", "remote-1"},
		RemainderCardIDs:   []string{"remote-3"},
		ToZone:             protocol.LibraryDestinationBottom,
		SourceSeat:         &sourceSeat,
		ApprovalID:         "approved",
		RemainderPlacement: protocol.LibraryPlacementTop,
	})
	if err != nil {
		t.Fatalf("approved remote library-bottom resolve: %v", err)
	}
	if len(r.Game.Seats[0].Hand) != 0 || len(r.Game.Seats[0].Library) != 0 {
		t.Fatalf("requester zones = %+v", r.Game.Seats[0])
	}
	library := r.Game.Seats[1].Library
	if len(library) != 4 || library[0].ID != "remote-3" ||
		library[1].ID != "remote-4" || library[2].ID != "remote-2" ||
		library[3].ID != "remote-1" || library[3].OwnerSeat != sourceSeat {
		t.Fatalf("source library = %+v", library)
	}
	var reply protocol.GameLibraryViewResolved
	if result.Reply == nil || result.Reply.DecodePayload(&reply) != nil ||
		reply.Seat != 0 || reply.MovedCount != 2 || reply.RemainderCount != 1 {
		t.Fatalf("remote library-bottom reply = %+v", reply)
	}
	if len(r.Game.Log) != 1 ||
		!strings.Contains(r.Game.Log[0].Text, "put 2 card(s) on bottom of their library") {
		t.Fatalf("remote library-bottom log = %+v", r.Game.Log)
	}
}

func TestApprovedRemoteFullDumpProjectsIdentityFreeSearchLog(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("guest-conn", "Guest", false, ""); err != nil {
		t.Fatalf("join guest: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{Seat: 0, DisplayName: "Host"},
			{
				Seat:        1,
				DisplayName: "Guest",
				Library: []protocol.GameCard{{
					ID: "remote-secret", Name: "Remote Secret",
				}},
			},
		},
		NextLogID: 1,
	}

	result, err := r.DumpApprovedZone(
		"host-conn", 1, "approved", 0)
	if err != nil {
		t.Fatalf("approved remote dump: %v", err)
	}
	if !result.ProjectGame || len(r.Game.Log) != 1 ||
		r.Game.Log[0].Kind != "library_search" ||
		strings.Contains(r.Game.Log[0].Text, "Remote Secret") {
		t.Fatalf("approved remote dump result=%+v log=%+v",
			result, r.Game.Log)
	}
}

func TestSeqMonotonicPerRoom(t *testing.T) {
	r := newTestRoom(t, 4, true)
	res1, _ := r.Join("g1", "Guest1", false, "")
	res2, _ := r.Join("g2", "Guest2", false, "")
	s1 := res1.Broadcast[0].SeqValue()
	s2 := res2.Broadcast[0].SeqValue()
	if s2 != s1+1 {
		t.Fatalf("seq not monotonic: %d -> %d", s1, s2)
	}
}

func TestValidateMatchMode(t *testing.T) {
	if code := ValidateMatchMode(protocol.MatchBO1); code != "" {
		t.Fatalf("bo1 code = %q, want empty", code)
	}
	if code := ValidateMatchMode(protocol.MatchBO3); code != "" {
		t.Fatalf("bo3 code = %q, want empty", code)
	}
	if code := ValidateMatchMode("best-of-5"); code != protocol.ErrInvalidMatchMode {
		t.Fatalf("bad matchMode code = %q, want %q", code, protocol.ErrInvalidMatchMode)
	}
}

func TestValidateFormatSupportsDuelCommander(t *testing.T) {
	maxSeats, err := ValidateFormat(protocol.FormatDuel)
	if err != nil {
		t.Fatalf("ValidateFormat duel: %v", err)
	}
	if maxSeats != 2 {
		t.Fatalf("duel maxSeats = %d, want 2", maxSeats)
	}
}

func TestTokenCreatedOnBattlefieldAndRemovedWhenItLeaves(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join player: %v", err)
	}
	if _, err := r.Join("s1", "Observer", true, ""); err != nil {
		t.Fatalf("join spectator: %v", err)
	}
	r.Format = protocol.FormatModern
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{Seat: 0, DisplayName: "Host"},
			{Seat: 1, DisplayName: "Guest1"},
		},
		NextTokenID: 1,
		NextLogID:   1,
	}

	position := &protocol.CardPosition{X: 0.25, Y: 0.75}
	created, err := r.CreateToken("host-conn", protocol.GameCreateToken{
		Name: "Goblin", SetCode: "tneo", CollectorNumber: "12",
		TypeLine: "Token Creature — Goblin", Position: position,
	})
	if err != nil {
		t.Fatalf("create token: %v", err)
	}
	if created.Reply == nil || created.Reply.Type != protocol.TypeGameTokenCreated ||
		len(r.Game.Seats[0].Battlefield) != 1 {
		t.Fatalf("create token result/state = %+v %+v", created, r.Game.Seats[0])
	}
	token := r.Game.Seats[0].Battlefield[0]
	if token.ID != "s0-t1" || token.Name != "Goblin" || token.SetCode != "TNEO" ||
		token.TypeLine != "Token Creature — Goblin" ||
		!token.Token || token.Position == nil || token.Position.X != 0.25 ||
		token.Position.Y != 0.75 {
		t.Fatalf("token = %+v", token)
	}
	spectatorView, err := r.GameSnapshot("s1")
	if err != nil {
		t.Fatalf("spectator snapshot: %v", err)
	}
	if len(spectatorView.Seats[0].Battlefield) != 1 ||
		!spectatorView.Seats[0].Battlefield[0].Token ||
		spectatorView.Seats[0].Battlefield[0].Name != "Goblin" {
		t.Fatalf("spectator token projection = %+v", spectatorView.Seats[0])
	}

	moved, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: token.ID, FromZone: protocol.ZoneBattlefield, ToZone: protocol.ZoneGraveyard,
	})
	if err != nil {
		t.Fatalf("move token off battlefield: %v", err)
	}
	var movedReply protocol.GameCardMoved
	if err := moved.Reply.DecodePayload(&movedReply); err != nil {
		t.Fatalf("decode moved token: %v", err)
	}
	if !movedReply.Removed || len(r.Game.Seats[0].Battlefield) != 0 ||
		len(r.Game.Seats[0].Graveyard) != 0 {
		t.Fatalf("token was not removed: reply %+v state %+v",
			movedReply, r.Game.Seats[0])
	}
	if _, err := r.CreateToken("s1", protocol.GameCreateToken{
		Name: "Goblin", SetCode: "TNEO", CollectorNumber: "12", Position: position,
	}); err == nil || err.Error() != protocol.ErrNotPlayer {
		t.Fatalf("spectator token err = %v, want %q", err, protocol.ErrNotPlayer)
	}
	invalidPosition := &protocol.CardPosition{X: 1.1, Y: 0.5}
	if _, err := r.CreateToken("host-conn", protocol.GameCreateToken{
		Name: "Goblin", SetCode: "TNEO", CollectorNumber: "12", Position: invalidPosition,
	}); err == nil || err.Error() != protocol.ErrInvalidToken {
		t.Fatalf("invalid token err = %v, want %q", err, protocol.ErrInvalidToken)
	}
}

func TestEDHCommandZoneTaxAndEliminationContinueUntilOnePlayer(t *testing.T) {
	r := newTestRoom(t, 4, true)
	for index := 1; index < 4; index++ {
		if _, err := r.Join("g"+itoa(index), "Guest"+itoa(index), false, ""); err != nil {
			t.Fatalf("join seat %d: %v", index, err)
		}
	}
	for index := range r.Seats {
		deck := testDeck(protocol.FormatEDH)
		deck.Name = "Deck " + itoa(index)
		r.Seats[index].Deck = &deck
	}
	r.randomIndex = func(maximum int) (int, error) { return 0, nil }
	r.Phase = protocol.RoomPhaseStarted
	if err := r.setupGame(); err != nil {
		t.Fatalf("setup EDH: %v", err)
	}
	for index, seat := range r.Game.Seats {
		if seat.Life != 40 || len(seat.CommandZone) != 1 ||
			seat.CommandZone[0].Name != "Sol Ring" || seat.CommanderTax != 0 {
			t.Fatalf("seat %d EDH setup = %+v", index, seat)
		}
	}

	commander := r.Game.Seats[0].CommandZone[0]
	cast, err := r.CastCommander("host-conn", protocol.GameCastCommander{
		CommanderID: commander.ID,
	})
	if err != nil {
		t.Fatalf("cast commander: %v", err)
	}
	var castReply protocol.GameCommanderCast
	if cast.Reply == nil || cast.Reply.DecodePayload(&castReply) != nil ||
		castReply.CommanderID != commander.ID || castReply.Tax != 1 {
		t.Fatalf("cast commander reply = %+v", cast)
	}
	if len(r.Game.Seats[0].CommandZone) != 0 ||
		len(r.Game.Stack) != 1 || r.Game.Stack[0].ID != commander.ID ||
		r.Game.Seats[0].CommanderTax != 1 ||
		r.Game.Seats[0].CommanderTaxes[commander.ID] != 1 {
		t.Fatalf("commander state = %+v", r.Game.Seats[0])
	}

	r.Game.ActiveSeat = 0
	first, err := r.ConcedeAt("host-conn", testNow)
	if err != nil {
		t.Fatalf("first EDH concede: %v", err)
	}
	var firstReply protocol.GameConceded
	if err := first.Reply.DecodePayload(&firstReply); err != nil {
		t.Fatalf("decode first concede: %v", err)
	}
	if firstReply.MatchFinished || firstReply.WinnerSeat != -1 ||
		!r.Game.Seats[0].Eliminated || r.Game.ActiveSeat != 1 ||
		r.Game.Result != nil || r.Game.Sideboard != nil {
		t.Fatalf("EDH continued state/reply = %+v %+v", firstReply, r.Game)
	}
	if _, err := r.Draw("host-conn", 1); err == nil ||
		err.Error() != protocol.ErrPlayerEliminated {
		t.Fatalf("eliminated action err = %v, want %q", err, protocol.ErrPlayerEliminated)
	}
	if _, err := r.ConcedeAt("g1", testNow); err != nil {
		t.Fatalf("second EDH concede: %v", err)
	}
	final, err := r.ConcedeAt("g2", testNow)
	if err != nil {
		t.Fatalf("final EDH concede: %v", err)
	}
	var finalReply protocol.GameConceded
	if err := final.Reply.DecodePayload(&finalReply); err != nil {
		t.Fatalf("decode final concede: %v", err)
	}
	if !finalReply.MatchFinished || finalReply.WinnerSeat != 3 ||
		r.Game.Result == nil || r.Game.Result.WinnerSeat != 3 ||
		r.Score[3] != 1 || r.Game.Sideboard != nil {
		t.Fatalf("EDH final state/reply = %+v %+v", finalReply, r.Game)
	}
}

func TestDuelCommanderUsesTwoPlayerMatchFlow(t *testing.T) {
	r, err := New("DUEL12", "Duel Commander", protocol.FormatDuel, protocol.MatchBO3,
		protocol.CardLoadPreload, 2, true, false, "Host", "host-conn", testNow)
	if err != nil {
		t.Fatalf("New duel room: %v", err)
	}
	if r.MatchMode != protocol.MatchBO3 || r.MaxSeats != 2 {
		t.Fatalf("duel room settings = matchMode %q, maxSeats %d",
			r.MatchMode, r.MaxSeats)
	}
	if _, err := r.Join("g1", "Guest", false, ""); err != nil {
		t.Fatalf("join duel room: %v", err)
	}
	missingCommander := testDeck(protocol.FormatDuel)
	missingCommander.Commander = ""
	if _, err := r.SelectDeck("host-conn", missingCommander); err == nil ||
		err.Error() != protocol.ErrInvalidDeck {
		t.Fatalf("missing duel commander error = %v, want %q",
			err, protocol.ErrInvalidDeck)
	}
	for seat := range r.Seats {
		deck := testDeck(protocol.FormatDuel)
		deck.Name = "Duel deck " + itoa(seat)
		r.Seats[seat].Deck = &deck
	}
	r.randomIndex = func(maximum int) (int, error) { return 0, nil }
	r.Phase = protocol.RoomPhaseStarted
	if err := r.setupGame(); err != nil {
		t.Fatalf("setup duel game: %v", err)
	}
	for seat, state := range r.Game.Seats {
		if state.Life != 20 || len(state.CommandZone) != 1 ||
			state.CommandZone[0].Name != "Sol Ring" || state.CommanderTax != 0 {
			t.Fatalf("seat %d duel setup = %+v", seat, state)
		}
	}

	commander := r.Game.Seats[0].CommandZone[0]
	position := &protocol.CardPosition{X: 0.5, Y: 0.25}
	if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: commander.ID, FromZone: protocol.ZoneCommand,
		ToZone: protocol.ZoneBattlefield, Position: position,
	}); err != nil {
		t.Fatalf("move duel commander: %v", err)
	}
	if _, err := r.AdjustCommanderTax("host-conn",
		protocol.GameAdjustCommanderTax{Delta: 1}); err != nil {
		t.Fatalf("adjust duel commander tax: %v", err)
	}

	conceded, err := r.ConcedeAt("host-conn", testNow)
	if err != nil {
		t.Fatalf("concede duel game: %v", err)
	}
	var reply protocol.GameConceded
	if err := conceded.Reply.DecodePayload(&reply); err != nil {
		t.Fatalf("decode duel concede: %v", err)
	}
	if reply.MatchFinished || reply.WinnerSeat != 1 || r.Score[1] != 1 ||
		r.Game.Sideboard == nil || r.Game.Seats[0].Eliminated {
		t.Fatalf("duel BO3 result = reply %+v, game %+v", reply, r.Game)
	}
	if _, err := r.MoveSideboard("host-conn", protocol.SideboardMove{
		FromZone:        protocol.SideboardZoneMain,
		ToZone:          protocol.SideboardZoneSide,
		Name:            "Sol Ring",
		SetCode:         "CMM",
		CollectorNumber: "396",
	}); err == nil || err.Error() != protocol.ErrInvalidSideboardMove {
		t.Fatalf("duel sideboard move error = %v, want %q",
			err, protocol.ErrInvalidSideboardMove)
	}
}

func TestEDHSupportsTwoCommanders(t *testing.T) {
	r := newTestRoom(t, 2, false)
	if _, err := r.Join("g1", "Guest", false, ""); err != nil {
		t.Fatalf("join: %v", err)
	}
	for seat := range r.Seats {
		deck := protocol.DeckSelect{
			Name:       "Partners",
			Format:     protocol.FormatEDH,
			Commanders: []string{"Yoshimaru", "Keleth"},
			Mainboard: []protocol.DeckCard{
				{Name: "Yoshimaru", Count: 1, SetCode: "NEC", CollectorNumber: "32"},
				{Name: "Keleth", Count: 1, SetCode: "CMR", CollectorNumber: "27"},
				{Name: "Plains", Count: 7, SetCode: "CMM", CollectorNumber: "1064"},
			},
			Sideboard: []protocol.DeckCard{},
		}
		r.Seats[seat].Deck = &deck
	}
	r.randomIndex = func(maximum int) (int, error) { return 0, nil }
	r.Phase = protocol.RoomPhaseStarted
	if err := r.setupGame(); err != nil {
		t.Fatalf("setup partners: %v", err)
	}
	for seat, state := range r.Game.Seats {
		if len(state.CommandZone) != 2 || len(state.Hand) != 7 ||
			len(state.Library) != 0 {
			t.Fatalf("seat %d partner setup = %+v", seat, state)
		}
		for _, commander := range state.CommandZone {
			if !commander.Commander {
				t.Fatalf("seat %d unmarked commander = %+v", seat, commander)
			}
		}
	}

	second := r.Game.Seats[0].CommandZone[1]
	first := r.Game.Seats[0].CommandZone[0]
	if _, err := r.CastCommander("host-conn", protocol.GameCastCommander{
		CommanderID: second.ID,
	}); err != nil {
		t.Fatalf("cast second commander: %v", err)
	}
	if r.Game.Seats[0].CommanderTaxes[first.ID] != 0 ||
		r.Game.Seats[0].CommanderTaxes[second.ID] != 1 {
		t.Fatalf("partner taxes = %+v", r.Game.Seats[0].CommanderTaxes)
	}
	position := &protocol.CardPosition{X: 0.4, Y: 0.3}
	if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: second.ID, FromZone: protocol.ZoneStack,
		ToZone: protocol.ZoneBattlefield, Position: position,
	}); err != nil {
		t.Fatalf("resolve second commander: %v", err)
	}
	if !r.Game.Seats[0].Battlefield[0].Commander {
		t.Fatalf("battlefield commander marker was lost")
	}
}

func TestCommanderDamageTracksPhysicalCommanderAndCanAtomicallyChangeLife(t *testing.T) {
	r := newTestRoom(t, 2, false)
	if _, err := r.Join("g1", "Guest", false, ""); err != nil {
		t.Fatalf("join: %v", err)
	}
	for seat := range r.Seats {
		deck := testDeck(protocol.FormatEDH)
		r.Seats[seat].Deck = &deck
	}
	r.randomIndex = func(maximum int) (int, error) { return 0, nil }
	r.Phase = protocol.RoomPhaseStarted
	if err := r.setupGame(); err != nil {
		t.Fatalf("setup commander game: %v", err)
	}
	commander := r.Game.Seats[0].CommandZone[0]
	delta := 5
	result, err := r.SetCommanderDamage("host-conn",
		protocol.GameSetCommanderDamage{
			CommanderID: commander.ID, TargetSeat: 1,
			Delta: &delta, ApplyToLife: true,
		})
	if err != nil {
		t.Fatalf("record commander damage: %v", err)
	}
	var reply protocol.GameCommanderDamageSet
	if result.Reply == nil || result.Reply.DecodePayload(&reply) != nil ||
		reply.Value != 5 || reply.TargetLife != 35 || !reply.AppliedToLife ||
		r.Game.Seats[1].Life != 35 ||
		r.Game.CommanderDamage[commander.ID][1] != 5 {
		t.Fatalf("commander damage result = reply %+v state %+v",
			reply, r.Game)
	}

	corrected := 3
	if _, err := r.SetCommanderDamage("g1",
		protocol.GameSetCommanderDamage{
			CommanderID: commander.ID, TargetSeat: 1, Value: &corrected,
		}); err != nil {
		t.Fatalf("target correct commander damage: %v", err)
	}
	if r.Game.Seats[1].Life != 35 ||
		r.Game.CommanderDamage[commander.ID][1] != 3 {
		t.Fatalf("correction changed wrong state: %+v", r.Game)
	}

	snapshot, err := r.GameSnapshot("g1")
	if err != nil {
		t.Fatalf("project commander damage: %v", err)
	}
	if len(snapshot.Commanders) != 2 || len(snapshot.CommanderDamage) != 1 ||
		snapshot.CommanderDamage[0].CommanderID != commander.ID ||
		snapshot.CommanderDamage[0].TargetSeat != 1 ||
		snapshot.CommanderDamage[0].Value != 3 {
		t.Fatalf("commander projection = identities %+v damage %+v",
			snapshot.Commanders, snapshot.CommanderDamage)
	}
}

func TestEDHLastRemainingPlayerConcedeFinishesWithoutWinner(t *testing.T) {
	r := newTestRoom(t, 4, true)
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number:       1,
		StartingSeat: 0,
		ActiveSeat:   0,
		CurrentPhase: protocol.GamePhaseUntap,
		Seats: []PlayerGameState{
			{Seat: 0, DisplayName: "Host"},
			{Seat: 1, DisplayName: "Guest1", Eliminated: true},
			{Seat: 2, DisplayName: "Guest2", Eliminated: true},
			{Seat: 3, DisplayName: "Guest3", Eliminated: true},
		},
		Log:       []protocol.GameLogEntry{},
		NextLogID: 1,
	}

	result, err := r.ConcedeAt("host-conn", testNow)
	if err != nil {
		t.Fatalf("last EDH concede: %v", err)
	}
	var reply protocol.GameConceded
	if err := result.Reply.DecodePayload(&reply); err != nil {
		t.Fatalf("decode last EDH concede: %v", err)
	}
	if !reply.MatchFinished || reply.WinnerSeat != -1 ||
		r.Game.ActiveSeat != -1 || r.Game.Result == nil ||
		r.Game.Result.WinnerSeat != -1 ||
		!r.Game.Result.MatchFinished {
		t.Fatalf("last EDH concede state/reply = %+v %+v", reply, r.Game)
	}
}

func TestBO3SideboardPrivacyCommitAndPreviousLoserStarts(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Format = protocol.FormatModern
	r.MatchMode = protocol.MatchBO3
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join player: %v", err)
	}
	if _, err := r.Join("s1", "Observer", true, ""); err != nil {
		t.Fatalf("join spectator: %v", err)
	}
	for index := range r.Seats {
		deck := testDeck(protocol.FormatModern)
		deck.Name = "Deck " + itoa(index)
		deck.Sideboard = []protocol.DeckCard{{
			Name: "Side Card", Count: 2, SetCode: "TST", CollectorNumber: "2",
			TypeLine: "Creature",
		}}
		r.Seats[index].Deck = &deck
	}
	r.randomIndex = func(maximum int) (int, error) { return 0, nil }
	r.Phase = protocol.RoomPhaseStarted
	if err := r.setupGame(); err != nil {
		t.Fatalf("setup Modern: %v", err)
	}

	conceded, err := r.ConcedeAt("host-conn", testNow)
	if err != nil {
		t.Fatalf("concede game 1: %v", err)
	}
	if r.Game.Sideboard == nil ||
		!conceded.SideboardDeadline.Equal(testNow.Add(5*time.Minute)) {
		t.Fatalf("sideboard deadline/state = %v %+v",
			conceded.SideboardDeadline, r.Game.Sideboard)
	}
	hostView, _ := r.GameSnapshot("host-conn")
	guestView, _ := r.GameSnapshot("g1")
	spectatorView, _ := r.GameSnapshot("s1")
	if hostView.Sideboard == nil || len(hostView.Sideboard.Mainboard) == 0 ||
		len(hostView.Sideboard.Sideboard) != 1 ||
		hostView.Sideboard.Sideboard[0].TypeLine != "Creature" ||
		guestView.Sideboard == nil || len(guestView.Sideboard.Mainboard) == 0 ||
		spectatorView.Sideboard == nil ||
		len(spectatorView.Sideboard.Mainboard) != 0 ||
		len(spectatorView.Sideboard.Sideboard) != 0 ||
		spectatorView.Sideboard.Seats[0].SideboardCount != 2 {
		t.Fatalf("sideboard projections host=%+v guest=%+v spectator=%+v",
			hostView.Sideboard, guestView.Sideboard, spectatorView.Sideboard)
	}

	if _, err := r.MoveSideboard("host-conn", protocol.SideboardMove{
		Name: "Side Card", SetCode: "TST", CollectorNumber: "2",
		FromZone: protocol.SideboardZoneSide, ToZone: protocol.SideboardZoneMain,
	}); err != nil {
		t.Fatalf("move sideboard card: %v", err)
	}
	if _, err := r.SetSideboardReady("host-conn", true); err != nil {
		t.Fatalf("host sideboard ready: %v", err)
	}
	completed, err := r.SetSideboardReady("g1", true)
	if err != nil {
		t.Fatalf("guest sideboard ready: %v", err)
	}
	if len(completed.Broadcast) != 1 ||
		completed.Broadcast[0].Type != protocol.TypeSideboardCompleted ||
		r.Game.Number != 2 || r.Game.StartingSeat != 0 ||
		r.Game.ActiveSeat != 0 || r.Game.Sideboard != nil ||
		len(r.Score) != 2 || r.Score[1] != 1 ||
		deckCardCount(r.Seats[0].Deck.Mainboard) != protocol.MinMainboardCards+1 ||
		deckCardCount(r.Seats[0].Deck.Sideboard) != 1 ||
		r.Seats[0].Deck.Mainboard[len(r.Seats[0].Deck.Mainboard)-1].TypeLine != "Creature" {
		t.Fatalf("committed next game = completed %+v game %+v deck %+v score %+v",
			completed, r.Game, r.Seats[0].Deck, r.Score)
	}
}

func TestBO3SideboardTimeoutRestoresPreviousPartition(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Format = protocol.FormatModern
	r.MatchMode = protocol.MatchBO3
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join player: %v", err)
	}
	for index := range r.Seats {
		deck := testDeck(protocol.FormatModern)
		deck.Sideboard = []protocol.DeckCard{{
			Name: "Side Card", Count: 1, SetCode: "TST", CollectorNumber: "2",
		}}
		r.Seats[index].Deck = &deck
	}
	r.randomIndex = func(maximum int) (int, error) { return 0, nil }
	r.Phase = protocol.RoomPhaseStarted
	if err := r.setupGame(); err != nil {
		t.Fatalf("setup Modern: %v", err)
	}
	if _, err := r.ConcedeAt("g1", testNow); err != nil {
		t.Fatalf("concede game 1: %v", err)
	}
	if _, err := r.MoveSideboard("host-conn", protocol.SideboardMove{
		Name: "Side Card", SetCode: "TST", CollectorNumber: "2",
		FromZone: protocol.SideboardZoneSide, ToZone: protocol.SideboardZoneMain,
	}); err != nil {
		t.Fatalf("pending sideboard move: %v", err)
	}
	if _, err := r.ExpireSideboard(testNow.Add(4 * time.Minute)); err == nil ||
		err.Error() != protocol.ErrSideboardNotExpired {
		t.Fatalf("early expiry err = %v, want %q", err, protocol.ErrSideboardNotExpired)
	}
	expired, err := r.ExpireSideboard(testNow.Add(5 * time.Minute))
	if err != nil {
		t.Fatalf("expire sideboard: %v", err)
	}
	var event protocol.SideboardCompleted
	if len(expired.Broadcast) != 1 ||
		expired.Broadcast[0].Type != protocol.TypeSideboardCompleted {
		t.Fatalf("expiry broadcasts = %+v", expired.Broadcast)
	}
	if err := expired.Broadcast[0].DecodePayload(&event); err != nil {
		t.Fatalf("decode expiry event: %v", err)
	}
	if event.Reason != protocol.SideboardEndTimeout ||
		r.Game.Number != 2 || r.Game.StartingSeat != 1 ||
		deckCardCount(r.Seats[0].Deck.Mainboard) != protocol.MinMainboardCards ||
		deckCardCount(r.Seats[0].Deck.Sideboard) != 1 {
		t.Fatalf("timeout next game/event = %+v game %+v deck %+v",
			event, r.Game, r.Seats[0].Deck)
	}
}

func TestBO3SideboardReadyRejectsUnplayableMainboard(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Format = protocol.FormatModern
	r.MatchMode = protocol.MatchBO3
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join player: %v", err)
	}
	for index := range r.Seats {
		deck := testDeck(protocol.FormatModern)
		r.Seats[index].Deck = &deck
	}
	r.randomIndex = func(maximum int) (int, error) { return 0, nil }
	r.Phase = protocol.RoomPhaseStarted
	if err := r.setupGame(); err != nil {
		t.Fatalf("setup Modern: %v", err)
	}
	if _, err := r.ConcedeAt("g1", testNow); err != nil {
		t.Fatalf("concede game 1: %v", err)
	}
	if _, err := r.MoveSideboard("host-conn", protocol.SideboardMove{
		Name: "Sol Ring", SetCode: "CMM", CollectorNumber: "396",
		FromZone: protocol.SideboardZoneMain, ToZone: protocol.SideboardZoneSide,
	}); err != nil {
		t.Fatalf("move mainboard card: %v", err)
	}

	if _, err := r.SetSideboardReady("host-conn", true); err == nil ||
		err.Error() != protocol.ErrInvalidDeck {
		t.Fatalf("short mainboard ready err=%v, want %q",
			err, protocol.ErrInvalidDeck)
	}
	if r.Game.Sideboard.Players[0].Ready ||
		deckCardCount(r.Game.Sideboard.Players[0].Mainboard) !=
			protocol.MinMainboardCards-1 {
		t.Fatalf("rejected ready mutated sideboard=%+v", r.Game.Sideboard)
	}
}

func TestBO3SideboardSetupFailureRollsBackCommitAndReady(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Format = protocol.FormatModern
	r.MatchMode = protocol.MatchBO3
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join player: %v", err)
	}
	for index := range r.Seats {
		deck := testDeck(protocol.FormatModern)
		deck.Sideboard = []protocol.DeckCard{{
			Name: "Side Card", Count: 1, SetCode: "TST", CollectorNumber: "2",
		}}
		r.Seats[index].Deck = &deck
	}
	r.randomIndex = func(maximum int) (int, error) { return 0, nil }
	r.Phase = protocol.RoomPhaseStarted
	if err := r.setupGame(); err != nil {
		t.Fatalf("setup Modern: %v", err)
	}
	if _, err := r.ConcedeAt("g1", testNow); err != nil {
		t.Fatalf("concede game 1: %v", err)
	}
	if _, err := r.MoveSideboard("host-conn", protocol.SideboardMove{
		Name: "Side Card", SetCode: "TST", CollectorNumber: "2",
		FromZone: protocol.SideboardZoneSide, ToZone: protocol.SideboardZoneMain,
	}); err != nil {
		t.Fatalf("pending sideboard move: %v", err)
	}
	if _, err := r.SetSideboardReady("host-conn", true); err != nil {
		t.Fatalf("host ready: %v", err)
	}
	committedMainCount := deckCardCount(r.Seats[0].Deck.Mainboard)
	committedSideCount := deckCardCount(r.Seats[0].Deck.Sideboard)
	r.randomIndex = func(int) (int, error) {
		return 0, errors.New("entropy unavailable")
	}

	if _, err := r.SetSideboardReady("g1", true); err == nil ||
		err.Error() != protocol.ErrGameSetupFailed {
		t.Fatalf("failed next-game setup err=%v, want %q",
			err, protocol.ErrGameSetupFailed)
	}
	if r.Game.Number != 1 || r.Game.Sideboard == nil ||
		!r.Game.Sideboard.Players[0].Ready ||
		r.Game.Sideboard.Players[1].Ready ||
		deckCardCount(r.Seats[0].Deck.Mainboard) != committedMainCount ||
		deckCardCount(r.Seats[0].Deck.Sideboard) != committedSideCount {
		t.Fatalf("failed setup was not atomic: game=%+v deck=%+v",
			r.Game, r.Seats[0].Deck)
	}
}

func TestShuffleLibraryDoesNotLeakIdentity(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join player: %v", err)
	}
	if _, err := r.Join("s1", "Observer", true, ""); err != nil {
		t.Fatalf("join spectator: %v", err)
	}
	secret := protocol.GameCard{
		ID: "s0-secret", Name: "Demonic Tutor",
		SetCode: "STA", CollectorNumber: "27",
	}
	second := protocol.GameCard{
		ID: "s0-secret-2", Name: "Island",
		SetCode: "M21", CollectorNumber: "265",
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1, ActiveSeat: 0, CurrentPhase: protocol.GamePhaseDraw,
		Seats: []PlayerGameState{
			{
				Seat: 0, DisplayName: "Host", Life: 20,
				Library: []protocol.GameCard{secret, second},
				Hand:    []protocol.GameCard{},
			},
			{Seat: 1, DisplayName: "Guest1", Life: 20},
		},
		Log:       []protocol.GameLogEntry{},
		NextLogID: 1,
	}

	result, err := r.ShuffleLibrary("host-conn")
	if err != nil {
		t.Fatalf("shuffle library: %v", err)
	}
	if result.Reply == nil ||
		result.Reply.Type != protocol.TypeGameLibraryShuffled ||
		len(r.Game.Seats[0].Library) != 2 {
		t.Fatalf("shuffle result=%+v state=%+v", result, r.Game.Seats[0])
	}
	hostView, _ := r.GameSnapshot("host-conn")
	guestView, _ := r.GameSnapshot("g1")
	spectatorView, _ := r.GameSnapshot("s1")
	for name, view := range map[string]protocol.GameSnapshot{
		"host": hostView, "guest": guestView, "spectator": spectatorView,
	} {
		data, _ := json.Marshal(view)
		if strings.Contains(string(data), secret.ID) ||
			strings.Contains(string(data), secret.Name) {
			t.Fatalf("%s shuffle projection leaked identity: %s", name, data)
		}
	}
	if log := r.Game.Log[len(r.Game.Log)-1]; log.Kind != "shuffle_library" ||
		strings.Contains(log.Text, secret.Name) {
		t.Fatalf("shuffle log leaked identity: %+v", log)
	}
}

func TestShuffleLibraryFailureLeavesOrderUnchanged(t *testing.T) {
	r := newStartedUtilityRoom(t, protocol.MatchBO1)
	r.Game.Seats[0].Library = []protocol.GameCard{
		{ID: "first", Name: "First"},
		{ID: "second", Name: "Second"},
		{ID: "third", Name: "Third"},
	}
	original := append([]protocol.GameCard(nil), r.Game.Seats[0].Library...)
	randomCalls := 0
	r.randomIndex = func(int) (int, error) {
		randomCalls++
		if randomCalls == 2 {
			return 0, errors.New("entropy unavailable")
		}
		return 0, nil
	}

	if _, err := r.ShuffleLibrary("host-conn"); err == nil {
		t.Fatal("shuffle succeeded without entropy")
	} else if code, ok := ErrorCode(err); !ok || code != protocol.ErrGameSetupFailed {
		t.Fatalf("shuffle error = %v code=%q", err, code)
	}
	if len(r.Game.Seats[0].Library) != len(original) {
		t.Fatalf("library length changed: got %d want %d",
			len(r.Game.Seats[0].Library), len(original))
	}
	for index := range original {
		if r.Game.Seats[0].Library[index].ID != original[index].ID {
			t.Fatalf("failed shuffle changed order at %d: got %q want %q",
				index, r.Game.Seats[0].Library[index].ID, original[index].ID)
		}
	}
	if len(r.Game.Log) != 0 {
		t.Fatalf("failed shuffle appended log: %+v", r.Game.Log)
	}
}

func TestArrowsAndAttachmentsArePublicOwnerControlledAndSelfCleaning(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join player: %v", err)
	}
	if _, err := r.Join("s1", "Observer", true, ""); err != nil {
		t.Fatalf("join spectator: %v", err)
	}
	position := &protocol.CardPosition{X: 0.2, Y: 0.3}
	hostAura := protocol.GameCard{
		ID: "s0-aura", Name: "Pacifism", OwnerSeat: 0, Position: position,
	}
	hostCreature := protocol.GameCard{
		ID: "s0-creature", Name: "Bear", OwnerSeat: 0, Position: position,
	}
	guestCreature := protocol.GameCard{
		ID: "s1-creature", Name: "Dragon", OwnerSeat: 1, Position: position,
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1, ActiveSeat: 0, CurrentPhase: protocol.GamePhaseDeclareAttackers,
		Seats: []PlayerGameState{
			{
				Seat: 0, DisplayName: "Host", Life: 20,
				Battlefield: []protocol.GameCard{hostAura, hostCreature},
			},
			{
				Seat: 1, DisplayName: "Guest1", Life: 20,
				Battlefield: []protocol.GameCard{guestCreature},
			},
		},
		Arrows:      []protocol.GameArrow{},
		Attachments: []protocol.GameAttachment{},
		Log:         []protocol.GameLogEntry{},
		NextLogID:   1,
	}

	targetSeat := 1
	if _, err := r.SetArrow("host-conn", protocol.GameSetArrow{
		SourceCardIDs:       []string{hostAura.ID, hostCreature.ID},
		TappedSourceCardIDs: []string{hostCreature.ID},
		Kind:                protocol.ArrowKindAttack,
		TargetSeat:          &targetSeat,
	}); err != nil {
		t.Fatalf("declare attacks: %v", err)
	}
	if r.Game.Seats[0].Battlefield[0].Tapped ||
		!r.Game.Seats[0].Battlefield[1].Tapped {
		t.Fatalf("atomic attacker taps = %+v", r.Game.Seats[0].Battlefield)
	}
	spectatorView, _ := r.GameSnapshot("s1")
	if len(spectatorView.Arrows) != 2 ||
		spectatorView.Arrows[0].Kind != protocol.ArrowKindAttack ||
		spectatorView.Arrows[0].TargetSeat == nil ||
		*spectatorView.Arrows[0].TargetSeat != 1 {
		t.Fatalf("spectator arrows=%+v", spectatorView.Arrows)
	}
	if _, err := r.SetArrow("host-conn", protocol.GameSetArrow{
		SourceCardIDs: []string{hostAura.ID},
		Kind:          protocol.ArrowKindAttack,
		TargetCardID:  guestCreature.ID,
	}); err != nil {
		t.Fatalf("declare attack against permanent: %v", err)
	}
	if len(r.Game.Arrows) != 2 ||
		r.Game.Arrows[1].SourceCardID != hostAura.ID ||
		r.Game.Arrows[1].TargetCardID != guestCreature.ID ||
		r.Game.Arrows[1].TargetSeat != nil {
		t.Fatalf("permanent attack arrows=%+v", r.Game.Arrows)
	}
	if log := r.Game.Log[len(r.Game.Log)-1]; !strings.Contains(log.Text, "battlefield permanent controlled by Guest1") {
		t.Fatalf("permanent attack log=%+v", log)
	}
	if _, err := r.SetArrow("host-conn", protocol.GameSetArrow{
		SourceCardIDs:       []string{hostAura.ID},
		TappedSourceCardIDs: []string{hostCreature.ID},
		Kind:                protocol.ArrowKindAttack,
		TargetSeat:          &targetSeat,
	}); err == nil || err.Error() != protocol.ErrInvalidTarget {
		t.Fatalf("tap non-source err=%v, want %q", err, protocol.ErrInvalidTarget)
	}
	if _, err := r.SetArrow("host-conn", protocol.GameSetArrow{
		SourceCardIDs: []string{hostAura.ID},
	}); err != nil {
		t.Fatalf("clear one attack: %v", err)
	}
	if len(r.Game.Arrows) != 1 ||
		r.Game.Arrows[0].SourceCardID != hostCreature.ID {
		t.Fatalf("source clear arrows=%+v", r.Game.Arrows)
	}
	if _, err := r.SetArrow("host-conn", protocol.GameSetArrow{
		SourceCardIDs: []string{hostAura.ID},
		Kind:          protocol.ArrowKindAttack,
		TargetCardID:  guestCreature.ID,
	}); err != nil {
		t.Fatalf("restore attack: %v", err)
	}
	if _, err := r.SetPhase("host-conn", protocol.GameSetPhase{
		Phase: protocol.GamePhaseDeclareBlockers,
	}); err != nil {
		t.Fatalf("advance to blockers: %v", err)
	}
	if _, err := r.SetArrow("g1", protocol.GameSetArrow{
		SourceCardIDs: []string{guestCreature.ID},
		Kind:          protocol.ArrowKindBlock,
		TargetCardID:  hostAura.ID,
	}); err != nil {
		t.Fatalf("block attacker aimed at permanent: %v", err)
	}
	if len(r.Game.Arrows) != 3 ||
		r.Game.Arrows[2].Kind != protocol.ArrowKindBlock {
		t.Fatalf("combat arrows=%+v", r.Game.Arrows)
	}
	if _, err := r.SetAttachment("g1", protocol.GameSetAttachment{
		SourceCardID: hostAura.ID, TargetCardID: guestCreature.ID,
	}); err == nil || err.Error() != protocol.ErrInvalidTarget {
		t.Fatalf("opponent attachment err=%v, want %q",
			err, protocol.ErrInvalidTarget)
	}
	if _, err := r.SetAttachment("host-conn", protocol.GameSetAttachment{
		SourceCardID: hostAura.ID, TargetCardID: guestCreature.ID,
	}); err != nil {
		t.Fatalf("attach: %v", err)
	}
	spectatorView, _ = r.GameSnapshot("s1")
	if len(spectatorView.Attachments) != 1 ||
		spectatorView.Attachments[0].SourceCardID != hostAura.ID {
		t.Fatalf("spectator attachments=%+v", spectatorView.Attachments)
	}
	if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{
		CardID: hostAura.ID, FromZone: protocol.ZoneBattlefield,
		ToZone: protocol.ZoneBattlefield, ToSeat: intPointer(1),
		Position: position,
	}); err != nil {
		t.Fatalf("move owned attachment source across battlefields: %v", err)
	}
	if _, err := r.SetAttachment("g1", protocol.GameSetAttachment{
		SourceCardID: hostAura.ID,
	}); err == nil || err.Error() != protocol.ErrInvalidTarget {
		t.Fatalf("controller detached non-owned source err=%v, want %q",
			err, protocol.ErrInvalidTarget)
	}
	if _, err := r.SetAttachment("host-conn", protocol.GameSetAttachment{
		SourceCardID: hostAura.ID, TargetCardID: guestCreature.ID,
	}); err != nil {
		t.Fatalf("owner reattached cross-controlled source: %v", err)
	}
	if len(r.Game.Attachments) != 1 ||
		r.Game.Attachments[0].OwnerSeat != 0 {
		t.Fatalf("cross-controlled attachment owner=%+v", r.Game.Attachments)
	}

	if _, err := r.SetPhase("host-conn", protocol.GameSetPhase{
		Phase: protocol.GamePhaseBeginningCombat,
	}); err != nil {
		t.Fatalf("set phase: %v", err)
	}
	if len(r.Game.Arrows) != 0 {
		t.Fatalf("phase change retained arrows: %+v", r.Game.Arrows)
	}
	if _, err := r.MoveCard("g1", protocol.GameMoveCard{
		CardID: guestCreature.ID, FromZone: protocol.ZoneBattlefield,
		ToZone: protocol.ZoneGraveyard,
	}); err != nil {
		t.Fatalf("move attachment target: %v", err)
	}
	if len(r.Game.Attachments) != 0 {
		t.Fatalf("target move retained attachments: %+v", r.Game.Attachments)
	}
}

// itoa avoids importing strconv just for test labels.
func itoa(i int) string {
	if i == 0 {
		return "0"
	}
	neg := i < 0
	if neg {
		i = -i
	}
	var b [20]byte
	pos := len(b)
	for i > 0 {
		pos--
		b[pos] = byte('0' + i%10)
		i /= 10
	}
	if neg {
		pos--
		b[pos] = '-'
	}
	return string(b[pos:])
}

func TestTokenAndAbilityCounterLimits(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Phase = protocol.RoomPhaseStarted
	battlefield := make([]protocol.GameCard, 0, protocol.MaxTokensPerSeat+1)
	for index := 0; index < protocol.MaxTokensPerSeat; index++ {
		battlefield = append(battlefield, protocol.GameCard{
			ID: "token-" + itoa(index), Name: "Token", OwnerSeat: 0, Token: true,
		})
	}
	battlefield = append(battlefield, protocol.GameCard{
		ID: "permanent", Name: "Permanent", OwnerSeat: 0,
	})
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{Seat: 0, DisplayName: "Host", Battlefield: battlefield},
			{Seat: 1},
		},
		NextTokenID:       1,
		NextCardCounterID: 1,
	}
	position := &protocol.CardPosition{X: 0.5, Y: 0.5}
	if _, err := r.CreateToken("host-conn", protocol.GameCreateToken{
		Name: "Goblin", SetCode: "TKN", CollectorNumber: "1", Position: position,
	}); err == nil || err.Error() != protocol.ErrInvalidToken {
		t.Fatalf("token over limit err = %v, want %q", err, protocol.ErrInvalidToken)
	}

	for index := 0; index < protocol.MaxCardAbilityCounters; index++ {
		value := 1
		if _, err := r.SetCardCounter("host-conn", protocol.GameSetCardCounter{
			CardID: "permanent", Kind: protocol.CardCounterKindAbility,
			Label: "Ability " + itoa(index), Value: &value,
		}); err != nil {
			t.Fatalf("ability counter %d: %v", index, err)
		}
	}
	value := 1
	if _, err := r.SetCardCounter("host-conn", protocol.GameSetCardCounter{
		CardID: "permanent", Kind: protocol.CardCounterKindAbility,
		Label: "Too many", Value: &value,
	}); err == nil || err.Error() != protocol.ErrInvalidCounter {
		t.Fatalf("ability counter over limit err = %v, want %q",
			err, protocol.ErrInvalidCounter)
	}
}

func TestNextPlayerBecomesHostAfterSpectatorOnlyInterval(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("spectator", "Watcher", true, ""); err != nil {
		t.Fatalf("join spectator: %v", err)
	}
	if _, empty, err := r.ExpireDisconnected("host-conn"); err != nil || empty {
		t.Fatalf("expire host: empty=%v err=%v", empty, err)
	}
	if r.HostSeat != -1 || r.PlayerCount() != 0 || len(r.Spectators) != 1 {
		t.Fatalf("spectator-only room state: host=%d players=%d spectators=%d",
			r.HostSeat, r.PlayerCount(), len(r.Spectators))
	}
	result, err := r.Join("next-player", "Next", false, "")
	if err != nil {
		t.Fatalf("join next player: %v", err)
	}
	if r.HostSeat != 0 || !r.Seats[0].Host || !r.IsHost("next-player") {
		t.Fatalf("next player did not become host: result=%+v room=%+v", result, r)
	}
}
