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

func TestNewMatchRestoresRegisteredSideboardPartition(t *testing.T) {
	r, err := New("MOD123", "Modern rematch", protocol.FormatModern,
		protocol.MatchBO3, protocol.CardLoadBackground, 2, true, false,
		"Host", "host-conn", testNow)
	if err != nil {
		t.Fatalf("new room: %v", err)
	}
	if _, err := r.Join("g1", "Guest1", false, ""); err != nil {
		t.Fatalf("join player: %v", err)
	}
	for _, connID := range []string{"host-conn", "g1"} {
		deck := testDeck(protocol.FormatModern)
		deck.Sideboard = []protocol.DeckCard{{
			Name: "Side Card", Count: 1, SetCode: "TST", CollectorNumber: "2",
		}}
		if _, err := r.SelectDeck(connID, deck); err != nil {
			t.Fatalf("select %s deck: %v", connID, err)
		}
	}
	r.randomIndex = func(maximum int) (int, error) { return 0, nil }
	if _, err := r.SetReady("host-conn", true); err != nil {
		t.Fatalf("host ready: %v", err)
	}
	if _, err := r.SetReady("g1", true); err != nil {
		t.Fatalf("guest ready: %v", err)
	}
	if r.Game == nil || r.Game.Number != 1 {
		t.Fatalf("initial game = %+v", r.Game)
	}

	if _, err := r.ConcedeAt("g1", testNow); err != nil {
		t.Fatalf("concede game 1: %v", err)
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
	if _, err := r.SetSideboardReady("g1", true); err != nil {
		t.Fatalf("guest sideboard ready: %v", err)
	}
	if deckCardCount(r.Seats[0].Deck.Mainboard) != protocol.MinMainboardCards+1 ||
		deckCardCount(r.Seats[0].Deck.Sideboard) != 0 {
		t.Fatalf("committed match partition = %+v", r.Seats[0].Deck)
	}

	if _, err := r.ConcedeAt("g1", testNow.Add(time.Minute)); err != nil {
		t.Fatalf("concede game 2: %v", err)
	}
	if r.Game.Result == nil || !r.Game.Result.MatchFinished {
		t.Fatalf("match result = %+v", r.Game.Result)
	}
	if _, err := r.ReturnToRoom("host-conn"); err != nil {
		t.Fatalf("return to room: %v", err)
	}
	if r.Seats[0].RegisteredDeck == nil ||
		deckCardCount(r.Seats[0].Deck.Mainboard) != protocol.MinMainboardCards ||
		deckCardCount(r.Seats[0].Deck.Sideboard) != 1 {
		t.Fatalf("restored registered partition = %+v", r.Seats[0])
	}

	if _, err := r.SetReady("host-conn", true); err != nil {
		t.Fatalf("host rematch ready: %v", err)
	}
	if _, err := r.SetReady("g1", true); err != nil {
		t.Fatalf("guest rematch ready: %v", err)
	}
	if r.Game == nil || r.Game.Number != 1 ||
		len(r.Game.Seats[0].Sideboard) != 1 ||
		r.Game.Seats[0].Sideboard[0].Name != "Side Card" ||
		len(r.Game.Seats[0].Library)+len(r.Game.Seats[0].Hand) !=
			protocol.MinMainboardCards {
		t.Fatalf("new match partition = %+v", r.Game)
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
