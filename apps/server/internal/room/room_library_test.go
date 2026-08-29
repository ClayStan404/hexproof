// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"encoding/json"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

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

func TestResolveLibraryViewAssignsEveryTopCardIndependently(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{{
			Seat: 0, DisplayName: "Host",
			Library: []protocol.GameCard{
				{ID: "a", Name: "Hand Secret"},
				{ID: "b", Name: "Exile Secret"},
				{ID: "c", Name: "Bottom Secret"},
				{ID: "d", Name: "Top Secret"},
				{ID: "e", Name: "Battlefield Secret"},
				{ID: "suffix", Name: "Unseen"},
			},
		}},
		NextLogID: 1,
	}
	result, err := r.ResolveLibraryView("host-conn", protocol.GameResolveLibraryView{
		Assignments: []protocol.LibraryViewAssignment{
			{CardID: "a", ToZone: protocol.LibraryDestinationHand},
			{CardID: "b", ToZone: protocol.LibraryDestinationExile},
			{CardID: "c", ToZone: protocol.LibraryDestinationBottom},
			{CardID: "d", ToZone: protocol.LibraryDestinationTop},
			{CardID: "e", ToZone: protocol.LibraryDestinationBattlefield, FaceDown: true},
		},
		Position:           &protocol.CardPosition{X: 0.5, Y: 0.5},
		RemainderPlacement: protocol.LibraryPlacementTop,
	})
	if err != nil {
		t.Fatalf("resolve assigned library view: %v", err)
	}
	state := r.Game.Seats[0]
	if len(state.Hand) != 1 || state.Hand[0].ID != "a" {
		t.Fatalf("hand = %+v", state.Hand)
	}
	if len(state.Exile) != 1 || state.Exile[0].ID != "b" {
		t.Fatalf("exile = %+v", state.Exile)
	}
	if len(state.Battlefield) != 1 || state.Battlefield[0].ID != "e" ||
		!state.Battlefield[0].FaceDown || state.Battlefield[0].Position == nil {
		t.Fatalf("battlefield = %+v", state.Battlefield)
	}
	if len(state.Library) != 3 || state.Library[0].ID != "d" ||
		state.Library[1].ID != "suffix" || state.Library[2].ID != "c" {
		t.Fatalf("library = %+v", state.Library)
	}
	var reply protocol.GameLibraryViewResolved
	if result.Reply == nil || result.Reply.DecodePayload(&reply) != nil ||
		reply.MovedCount != 3 || reply.RemainderCount != 2 {
		t.Fatalf("reply = %+v", reply)
	}
	if len(r.Game.Log) != 1 ||
		!strings.Contains(r.Game.Log[0].Text, "across 5 destination(s)") ||
		strings.Contains(r.Game.Log[0].Text, "Secret") {
		t.Fatalf("log = %+v", r.Game.Log)
	}
}

func TestResolveLibraryViewRejectsInvalidPerCardAssignment(t *testing.T) {
	r := newTestRoom(t, 2, true)
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{{
			Seat: 0, DisplayName: "Host",
			Library: []protocol.GameCard{{ID: "a"}, {ID: "b"}},
		}},
		NextLogID: 1,
	}
	_, err := r.ResolveLibraryView("host-conn", protocol.GameResolveLibraryView{
		Assignments: []protocol.LibraryViewAssignment{
			{CardID: "a", ToZone: protocol.LibraryDestinationHand},
			{CardID: "a", ToZone: protocol.LibraryDestinationExile},
		},
		RemainderPlacement: protocol.LibraryPlacementTop,
	})
	if err == nil || err.Error() != protocol.ErrInvalidMove {
		t.Fatalf("duplicate assignment err = %v, want %q", err, protocol.ErrInvalidMove)
	}
	_, err = r.ResolveLibraryView("host-conn", protocol.GameResolveLibraryView{
		Assignments: []protocol.LibraryViewAssignment{{
			CardID: "a", ToZone: protocol.LibraryDestinationExile, FaceDown: true,
		}},
		RemainderPlacement: protocol.LibraryPlacementTop,
	})
	if err == nil || err.Error() != protocol.ErrInvalidMove {
		t.Fatalf("face-down exile err = %v, want %q", err, protocol.ErrInvalidMove)
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
