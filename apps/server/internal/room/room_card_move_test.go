// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

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
