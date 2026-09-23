// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestTopCardViewMoveRevealsOnlyWhenRequested(t *testing.T) {
	for _, test := range []struct {
		name   string
		remote bool
		reveal bool
	}{
		{name: "own hidden"},
		{name: "own revealed", reveal: true},
		{name: "approved remote hidden", remote: true},
		{name: "approved remote revealed", remote: true, reveal: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			setup := newPrivateZoneConsentSetup(t)
			sourceSeat := 0
			if test.remote {
				sourceSeat = 1
			}
			card := setup.room.Game.Seats[sourceSeat].Library[0]
			dump, _ := protocol.NewEnvelope(protocol.TypeGameDumpZone,
				protocol.GameDumpZone{Zone: protocol.ZoneLibrary, Seat: &sourceSeat, TopCount: 1})
			if err := setup.handler.handleGameDumpZone(setup.host, dump); err != nil {
				t.Fatal(err)
			}
			if test.remote {
				receivePrivateZoneEnvelope(t, setup.host)
				requested := receivePrivateZoneEnvelope(t, setup.guest)
				var approval protocol.GameZoneDumpRequested
				if err := requested.DecodePayload(&approval); err != nil {
					t.Fatal(err)
				}
				response, _ := protocol.NewEnvelope(protocol.TypeGameRespondZoneDump,
					protocol.GameRespondZoneDump{ApprovalID: approval.ApprovalID, Approved: true})
				if err := setup.handler.handleGameRespondZoneDump(setup.guest, response); err != nil {
					t.Fatal(err)
				}
				receivePrivateZoneEnvelope(t, setup.guest)
			}
			dumped := receivePrivateZoneEnvelope(t, setup.host)
			var viewed protocol.GameZoneDumped
			if dumped.Type != protocol.TypeGameZoneDumped || dumped.DecodePayload(&viewed) != nil ||
				viewed.TopCount != 1 || len(viewed.Cards) != 1 {
				t.Fatalf("private top view = %+v", dumped)
			}
			for _, sess := range []*Session{setup.host, setup.guest, setup.spectator} {
				receivePrivateZoneEnvelope(t, sess)
			}

			fixture := loadPrivateZoneFixture(t, "game-search-library-top-card.json")
			var move protocol.GameSearchLibrary
			if err := fixture.DecodePayload(&move); err != nil || !move.TopCard {
				t.Fatalf("top-card fixture = %+v, error = %v", move, err)
			}
			move.CardIDs = []string{card.ID}
			move.SourceSeat = &sourceSeat
			move.ApprovalID = viewed.ApprovalID
			move.Reveal = test.reveal
			request, _ := protocol.NewEnvelope(protocol.TypeGameSearchLibrary, move)
			request.ID = fixture.ID
			if err := setup.handler.handleGameSearchLibrary(setup.host, request); err != nil {
				t.Fatal(err)
			}
			reply := receivePrivateZoneEnvelope(t, setup.host)
			var moved protocol.GameLibrarySearched
			if reply.Type != protocol.TypeGameLibrarySearched || reply.ID != request.ID ||
				reply.DecodePayload(&moved) != nil || moved.Revealed != test.reveal || moved.Count != 1 ||
				moved.SourceSeat != sourceSeat || moved.ToSeat != 0 {
				t.Fatalf("top-card move acknowledgement = %+v", reply)
			}
			owner := "their"
			if test.remote {
				owner = "Bob's"
			}
			wantLog := "Alice resolved the top 1 card(s) of " + owner + " library and put 1 card(s) into hand."
			if test.reveal {
				wantLog = "Alice revealed " + card.Name + " from the top 1 card(s) of " + owner + " library and put them into hand."
			}
			if strings.Contains(string(reply.Payload), card.ID) || strings.Contains(string(reply.Payload), card.Name) {
				t.Fatalf("acknowledgement exposed the card: %+v", reply)
			}
			for _, sess := range []*Session{setup.host, setup.guest, setup.spectator} {
				env := receivePrivateZoneEnvelope(t, sess)
				var snapshot protocol.GameSnapshot
				if env.Type != protocol.TypeGameSnapshot || env.DecodePayload(&snapshot) != nil ||
					len(snapshot.Log) != 2 {
					t.Fatalf("%s snapshot = %+v", sess.DisplayName, env)
				}
				log := snapshot.Log[1]
				if log.Kind != "library_view" || log.Text != wantLog {
					t.Fatalf("%s top-card move log = %+v", sess.DisplayName, log)
				}
				if snapshot.Seats[0].HandCount != 1 {
					t.Fatalf("%s hand count = %d", sess.DisplayName, snapshot.Seats[0].HandCount)
				}
				if sess != setup.host && (len(snapshot.Seats[0].Hand) != 0 ||
					strings.Contains(string(env.Payload), card.ID) ||
					!test.reveal && strings.Contains(string(env.Payload), card.Name)) {
					t.Fatalf("%s received the private hand card", sess.DisplayName)
				}
			}
		})
	}
}

func TestTopCardMoveRejectsStaleOrMultipleCards(t *testing.T) {
	for _, test := range []struct {
		name string
		ids  []string
		code string
	}{
		{"no longer on top", []string{"s0-lower"}, protocol.ErrCardNotFound},
		{"multiple cards", []string{"s0-c8", "s0-lower"}, protocol.ErrInvalidMove},
	} {
		t.Run(test.name, func(t *testing.T) {
			setup := newPrivateZoneConsentSetup(t)
			setup.room.Game.Seats[0].Library = append(setup.room.Game.Seats[0].Library,
				protocol.GameCard{ID: "s0-lower", Name: "Lower card", OwnerSeat: 0})
			before, _ := json.Marshal(setup.room.Game)
			request, _ := protocol.NewEnvelope(protocol.TypeGameSearchLibrary,
				protocol.GameSearchLibrary{CardIDs: test.ids, ToZone: protocol.ZoneHand, TopCard: true})
			if err := setup.handler.handleGameSearchLibrary(setup.host, request); err != nil {
				t.Fatal(err)
			}
			env := receivePrivateZoneEnvelope(t, setup.host)
			var failure protocol.ErrorPayload
			if env.Type != protocol.TypeError || env.DecodePayload(&failure) != nil || failure.Code != test.code {
				t.Fatalf("invalid top-card move = %+v", env)
			}
			after, _ := json.Marshal(setup.room.Game)
			if !reflect.DeepEqual(before, after) {
				t.Fatal("rejected top-card move changed the game or log")
			}
		})
	}
}
