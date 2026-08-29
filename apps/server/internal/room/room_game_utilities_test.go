// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
)

func newStartedUtilityRoom(t *testing.T, matchMode string) *Room {
	t.Helper()
	r, err := New("UTIL12", "Utilities", protocol.FormatModern, matchMode,
		protocol.CardLoadPreload, 2, true, false,
		"Host", "host-conn", testNow)
	if err != nil {
		t.Fatalf("new utility room: %v", err)
	}
	if _, err = r.Join("guest-conn", "Guest", false, ""); err != nil {
		t.Fatalf("join guest: %v", err)
	}
	hostDeck := testDeck(protocol.FormatModern)
	guestDeck := testDeck(protocol.FormatModern)
	r.Seats[0].Deck = &hostDeck
	r.Seats[1].Deck = &guestDeck
	r.Phase = protocol.RoomPhaseStarted
	r.Score = []int{1, 0}
	r.Game = &GameState{
		Number: 2, StartingSeat: 1, ActiveSeat: 1,
		Seats: []PlayerGameState{
			{
				Seat: 0, DisplayName: "Host",
				Battlefield: []protocol.GameCard{{
					ID: "field-a", Name: "Alpha", OwnerSeat: 0,
				}},
			},
			{
				Seat: 1, DisplayName: "Guest",
				Battlefield: []protocol.GameCard{{
					ID: "field-b", Name: "Beta", OwnerSeat: 1,
					FaceDown: true,
				}},
			},
		},
		NextLogID: 1,
	}
	r.randomIndex = func(maximum int) (int, error) {
		return maximum - 1, nil
	}
	return r
}

func TestDeclareDrawPreservesBO3ScoreAndStartsSideboard(t *testing.T) {
	r := newStartedUtilityRoom(t, protocol.MatchBO3)
	now := time.Date(2026, 8, 3, 12, 0, 0, 0, time.UTC)
	result, err := r.DeclareDrawAt("guest-conn", now)
	if err != nil {
		t.Fatalf("declare draw: %v", err)
	}
	if r.Game.Result == nil ||
		r.Game.Result.Reason != protocol.GameResultDraw ||
		r.Game.Result.WinnerSeat != -1 ||
		r.Game.Result.MatchFinished ||
		r.Game.Sideboard == nil ||
		r.Game.Sideboard.PreviousLoser != -1 ||
		r.Game.Sideboard.Deadline != now.Add(sideboardDuration) {
		t.Fatalf("draw state = %+v sideboard=%+v",
			r.Game.Result, r.Game.Sideboard)
	}
	if r.Score[0] != 1 || r.Score[1] != 0 || r.DrawnGames != 1 ||
		result.SideboardDeadline != now.Add(sideboardDuration) {
		t.Fatalf("draw changed score/deadline: score=%v drawn=%d result=%+v",
			r.Score, r.DrawnGames, result)
	}
	var reply protocol.GameDrawDeclared
	if result.Reply == nil || result.Reply.DecodePayload(&reply) != nil ||
		reply.MatchFinished || reply.DeclaredSeat != 1 || reply.DrawnGames != 1 {
		t.Fatalf("draw reply = %+v", reply)
	}

	for index := range r.Game.Sideboard.Players {
		r.Game.Sideboard.Players[index].Ready = true
	}
	if _, err := r.completeSideboard(protocol.SideboardEndReady, true); err != nil {
		t.Fatalf("complete draw sideboard: %v", err)
	}
	if r.Game.Number != 3 || r.Game.StartingSeat != 1 ||
		len(r.Game.Log) == 0 ||
		!strings.Contains(r.Game.Log[0].Text, "won the roll for Game 3") {
		t.Fatalf("post-draw game = %+v log=%+v", r.Game, r.Game.Log)
	}
	if r.DrawnGames != 1 {
		t.Fatalf("drawn games reset after sideboard: %d", r.DrawnGames)
	}
}

func TestBO3MatchDrawnGamesSurviveLaterWins(t *testing.T) {
	r := newStartedUtilityRoom(t, protocol.MatchBO3)
	now := time.Date(2026, 8, 3, 12, 0, 0, 0, time.UTC)
	if _, err := r.DeclareDrawAt("guest-conn", now); err != nil {
		t.Fatalf("game 2 draw: %v", err)
	}
	readySideboard(t, r)
	if _, err := r.ConcedeAt("host-conn", now.Add(time.Minute)); err != nil {
		t.Fatalf("game 3 concede: %v", err)
	}
	readySideboard(t, r)
	result, err := r.ConcedeAt("guest-conn", now.Add(2*time.Minute))
	if err != nil {
		t.Fatalf("game 4 concede: %v", err)
	}
	if r.Score[0] != 2 || r.Score[1] != 1 || r.DrawnGames != 1 ||
		r.Game.Result == nil || !r.Game.Result.MatchFinished {
		t.Fatalf("finished match score=%v drawn=%d result=%+v",
			r.Score, r.DrawnGames, r.Game.Result)
	}
	snapshot, err := r.GameSnapshot("host-conn")
	if err != nil {
		t.Fatalf("snapshot: %v", err)
	}
	if snapshot.DrawnGames != 1 || snapshot.Score[0] != 2 || snapshot.Score[1] != 1 {
		t.Fatalf("snapshot score=%v drawn=%d", snapshot.Score, snapshot.DrawnGames)
	}
	var reply protocol.GameConceded
	if result.Reply == nil || result.Reply.DecodePayload(&reply) != nil ||
		!reply.MatchFinished {
		t.Fatalf("final concede reply = %+v", reply)
	}
	if _, err := r.ReturnToRoom("host-conn"); err != nil {
		t.Fatalf("return to room: %v", err)
	}
	if r.DrawnGames != 0 || r.Score[0] != 0 || r.Score[1] != 0 {
		t.Fatalf("new match kept old stats: score=%v drawn=%d", r.Score, r.DrawnGames)
	}
}

func readySideboard(t *testing.T, r *Room) {
	t.Helper()
	if r.Game == nil || r.Game.Sideboard == nil {
		t.Fatalf("missing sideboard: %+v", r.Game)
	}
	for index := range r.Game.Sideboard.Players {
		r.Game.Sideboard.Players[index].Ready = true
	}
	if _, err := r.completeSideboard(protocol.SideboardEndReady, true); err != nil {
		t.Fatalf("complete sideboard: %v", err)
	}
}

func TestTimedGameResultsRejectZeroTimeWithoutMutation(t *testing.T) {
	drawRoom := newStartedUtilityRoom(t, protocol.MatchBO3)
	if _, err := drawRoom.DeclareDrawAt("host-conn", time.Time{}); err == nil ||
		err.Error() != protocol.ErrInternal {
		t.Fatalf("zero-time draw error = %v", err)
	}
	if drawRoom.Game.Result != nil || drawRoom.Game.Sideboard != nil {
		t.Fatalf("zero-time draw mutated game: %+v", drawRoom.Game)
	}

	concedeRoom := newStartedUtilityRoom(t, protocol.MatchBO3)
	if _, err := concedeRoom.ConcedeAt("host-conn", time.Time{}); err == nil ||
		err.Error() != protocol.ErrInternal {
		t.Fatalf("zero-time concede error = %v", err)
	}
	if concedeRoom.Game.Result != nil || concedeRoom.Game.Sideboard != nil ||
		concedeRoom.Score[0] != 1 || concedeRoom.Score[1] != 0 {
		t.Fatalf("zero-time concede mutated game: %+v score=%v",
			concedeRoom.Game, concedeRoom.Score)
	}
}

func TestDeclareDrawFinishesBO1(t *testing.T) {
	r := newStartedUtilityRoom(t, protocol.MatchBO1)
	result, err := r.DeclareDrawAt("host-conn", testNow)
	if err != nil {
		t.Fatalf("declare BO1 draw: %v", err)
	}
	if r.Game.Result == nil || !r.Game.Result.MatchFinished ||
		r.Game.Sideboard != nil || !result.SideboardDeadline.IsZero() {
		t.Fatalf("BO1 draw state = %+v result=%+v", r.Game, result)
	}
}

func TestRestartGamePreservesMatchCoordinates(t *testing.T) {
	r := newStartedUtilityRoom(t, protocol.MatchBO3)
	result, err := r.RestartGame("host-conn")
	if err != nil {
		t.Fatalf("restart: %v", err)
	}
	if r.Game.Number != 2 || r.Game.StartingSeat != 1 ||
		r.Game.ActiveSeat != 1 || r.Score[0] != 1 || r.Score[1] != 0 ||
		r.Game.Result != nil || r.Game.Sideboard != nil {
		t.Fatalf("restarted state = %+v score=%v", r.Game, r.Score)
	}
	if len(r.Game.Log) == 0 || r.Game.Log[0].Kind != "restart" ||
		r.Game.Log[0].ID != 1 || r.Game.NextLogID != int64(len(r.Game.Log)+1) {
		t.Fatalf("restart log = %+v next=%d", r.Game.Log, r.Game.NextLogID)
	}
	var reply protocol.GameRestarted
	if result.Reply == nil || result.Reply.DecodePayload(&reply) != nil ||
		reply.GameNumber != 2 || reply.StartingSeat != 1 {
		t.Fatalf("restart reply = %+v", reply)
	}
	if _, err := r.RestartGame("guest-conn"); err == nil ||
		err.Error() != protocol.ErrNotHost {
		t.Fatalf("guest restart err = %v", err)
	}
}

func TestRandomToolsUseValidatedPublicCandidates(t *testing.T) {
	r := newStartedUtilityRoom(t, protocol.MatchBO3)
	rolled, err := r.RollDice("host-conn", protocol.GameRoll{
		Sides: 6, Count: 3,
	})
	if err != nil {
		t.Fatalf("roll: %v", err)
	}
	var rollReply protocol.GameRolled
	if rolled.Reply == nil || rolled.Reply.DecodePayload(&rollReply) != nil ||
		rollReply.Total != 18 || len(rollReply.Rolls) != 3 ||
		rollReply.Rolls[0] != 6 {
		t.Fatalf("roll reply = %+v", rollReply)
	}
	flipped, err := r.FlipCoin("host-conn")
	if err != nil {
		t.Fatalf("flip: %v", err)
	}
	var flipReply protocol.GameCoinFlipped
	if flipped.Reply == nil || flipped.Reply.DecodePayload(&flipReply) != nil ||
		flipReply.Result != "tails" {
		t.Fatalf("flip reply = %+v", flipReply)
	}
	selectedPlayer, err := r.RandomSelect("host-conn",
		protocol.GameRandomSelect{Kind: protocol.RandomSelectionPlayer})
	if err != nil {
		t.Fatalf("select player: %v", err)
	}
	var playerReply protocol.GameRandomSelected
	if selectedPlayer.Reply == nil ||
		selectedPlayer.Reply.DecodePayload(&playerReply) != nil ||
		playerReply.SelectedSeat != 1 {
		t.Fatalf("player selection = %+v", playerReply)
	}
	selectedCard, err := r.RandomSelect("host-conn",
		protocol.GameRandomSelect{
			Kind:    protocol.RandomSelectionCard,
			CardIDs: []string{"field-a", "field-b"},
		})
	if err != nil {
		t.Fatalf("select card: %v", err)
	}
	var cardReply protocol.GameRandomSelected
	if selectedCard.Reply == nil ||
		selectedCard.Reply.DecodePayload(&cardReply) != nil ||
		cardReply.SelectedCardID != "field-b" ||
		strings.Contains(r.Game.Log[len(r.Game.Log)-1].Text, "Beta") {
		t.Fatalf("card selection = %+v log=%+v", cardReply, r.Game.Log)
	}

	logCount := len(r.Game.Log)
	if _, err := r.RandomSelect("host-conn",
		protocol.GameRandomSelect{
			Kind:    protocol.RandomSelectionCard,
			CardIDs: []string{"field-a", "field-a"},
		}); err == nil || err.Error() != protocol.ErrInvalidTarget {
		t.Fatalf("duplicate card selection err = %v", err)
	}
	if len(r.Game.Log) != logCount {
		t.Fatalf("invalid selection appended log: %+v", r.Game.Log)
	}
	if _, err := r.RollDice("host-conn",
		protocol.GameRoll{Sides: 1}); err == nil ||
		err.Error() != protocol.ErrInvalidMessage {
		t.Fatalf("invalid roll err = %v", err)
	}
}
