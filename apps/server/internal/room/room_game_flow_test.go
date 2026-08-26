// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"encoding/json"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

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

func TestSpectatorHandVisibilityDoesNotExposeOtherPrivateZones(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("guest-conn", "Guest", false, ""); err != nil {
		t.Fatalf("join guest: %v", err)
	}
	if _, err := r.Join("spectator-conn", "Watcher", true, ""); err != nil {
		t.Fatalf("join spectator: %v", err)
	}
	r.SpectatorsSeeHands = true
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{
				Seat: 0, DisplayName: "Host",
				Hand:      []protocol.GameCard{{ID: "host-hand", Name: "Host Secret", OwnerSeat: 0}},
				Sideboard: []protocol.GameCard{{ID: "host-side", Name: "Side Secret", OwnerSeat: 0}},
				Battlefield: []protocol.GameCard{{
					ID: "host-facedown", Name: "Face Secret", OwnerSeat: 0, FaceDown: true,
				}},
			},
			{
				Seat: 1, DisplayName: "Guest",
				Hand: []protocol.GameCard{{ID: "guest-hand", Name: "Guest Secret", OwnerSeat: 1}},
			},
		},
	}

	spectatorView, err := r.GameSnapshot("spectator-conn")
	if err != nil {
		t.Fatalf("spectator snapshot: %v", err)
	}
	if len(spectatorView.Seats[0].Hand) != 1 ||
		spectatorView.Seats[0].Hand[0].Name != "Host Secret" ||
		len(spectatorView.Seats[1].Hand) != 1 ||
		spectatorView.Seats[1].Hand[0].Name != "Guest Secret" {
		t.Fatalf("spectator hands = %+v", spectatorView.Seats)
	}
	if len(spectatorView.Seats[0].Sideboard) != 0 ||
		len(spectatorView.Seats[0].Battlefield) != 1 ||
		spectatorView.Seats[0].Battlefield[0].Name != "" {
		t.Fatalf("spectator private zones leaked: %+v", spectatorView.Seats[0])
	}

	guestView, err := r.GameSnapshot("guest-conn")
	if err != nil {
		t.Fatalf("guest snapshot: %v", err)
	}
	if len(guestView.Seats[0].Hand) != 0 || len(guestView.Seats[1].Hand) != 1 {
		t.Fatalf("player hand projection changed: %+v", guestView.Seats)
	}

	r.SpectatorsSeeHands = false
	hiddenView, err := r.GameSnapshot("spectator-conn")
	if err != nil {
		t.Fatalf("hidden spectator snapshot: %v", err)
	}
	if len(hiddenView.Seats[0].Hand) != 0 || len(hiddenView.Seats[1].Hand) != 0 {
		t.Fatalf("spectator hands leaked with policy disabled: %+v", hiddenView.Seats)
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
