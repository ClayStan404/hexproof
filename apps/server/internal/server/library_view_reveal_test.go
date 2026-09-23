// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"fmt"
	"reflect"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestAssignedLibraryViewRevealsOnlyExplicitNamesAfterSuccess(t *testing.T) {
	for _, sourceSeat := range []int{0, 1} {
		t.Run(fmt.Sprintf("source seat %d", sourceSeat), func(t *testing.T) {
			setup := newPrivateZoneConsentSetup(t)
			cards := []protocol.GameCard{
				{ID: "hidden-hand", Name: "Hidden Hand"},
				{ID: "reveal-hand-a", Name: "Revealed Hand A"},
				{ID: "reveal-hand-b", Name: "Revealed Hand B"},
				{ID: "reveal-graveyard", Name: "Revealed Graveyard"},
				{ID: "reveal-top", Name: "Revealed Top"},
				{ID: "hidden-face-down", Name: "Hidden Face Down"},
				{ID: "hidden-bottom", Name: "Hidden Bottom"},
				{ID: "unseen-suffix", Name: "Unseen Suffix"},
			}
			for index := range cards {
				cards[index].OwnerSeat = sourceSeat
			}
			setup.room.Game.Seats[sourceSeat].Library = cards
			viewed := openPrivateTopLibraryView(t, setup, sourceSeat, 7)
			resolve := protocol.GameResolveLibraryView{
				Assignments: []protocol.LibraryViewAssignment{
					{CardID: "reveal-hand-b", ToZone: protocol.LibraryDestinationHand, Reveal: true},
					{CardID: "hidden-hand", ToZone: protocol.LibraryDestinationHand},
					{CardID: "reveal-graveyard", ToZone: protocol.LibraryDestinationGraveyard, Reveal: true},
					{CardID: "reveal-hand-a", ToZone: protocol.LibraryDestinationHand, Reveal: true},
					{CardID: "reveal-top", ToZone: protocol.LibraryDestinationTop, Reveal: true},
					{CardID: "hidden-face-down", ToZone: protocol.LibraryDestinationBattlefield, FaceDown: true, Reveal: true},
					{CardID: "hidden-bottom", ToZone: protocol.LibraryDestinationBottom},
				},
				Position:           &protocol.CardPosition{X: 0.5, Y: 0.5},
				SourceSeat:         &sourceSeat,
				ApprovalID:         viewed.ApprovalID,
				RemainderPlacement: protocol.LibraryPlacementTop,
			}

			// A failure after earlier reveal assignments must not publish names,
			// change state, or consume a remote grant needed for the retry.
			invalid := resolve
			invalid.Assignments = append([]protocol.LibraryViewAssignment(nil), resolve.Assignments...)
			invalid.Assignments[6].CardID = "unseen-suffix"
			before, _ := json.Marshal(setup.room.Game)
			request, _ := protocol.NewEnvelope(protocol.TypeGameResolveLibraryView, invalid)
			if err := setup.handler.handleGameResolveLibraryView(setup.host, request); err != nil {
				t.Fatal(err)
			}
			failure := receivePrivateZoneEnvelope(t, setup.host)
			if failure.Type != protocol.TypeError {
				t.Fatalf("invalid resolution = %+v", failure)
			}
			after, _ := json.Marshal(setup.room.Game)
			if !reflect.DeepEqual(before, after) || len(setup.guest.Send) != 0 || len(setup.spectator.Send) != 0 {
				t.Fatal("rejected resolution changed the game/log or fanned out private information")
			}
			for _, card := range cards {
				if strings.Contains(string(failure.Payload), card.Name) || strings.Contains(string(failure.Payload), card.ID) {
					t.Fatalf("rejection exposed a viewed card: %+v", failure)
				}
			}

			request, _ = protocol.NewEnvelope(protocol.TypeGameResolveLibraryView, resolve)
			request.ID = "resolve-revealed-prefix"
			if err := setup.handler.handleGameResolveLibraryView(setup.host, request); err != nil {
				t.Fatal(err)
			}
			reply := receivePrivateZoneEnvelope(t, setup.host)
			var resolved protocol.GameLibraryViewResolved
			if reply.Type != protocol.TypeGameLibraryViewResolved || reply.ID != request.ID ||
				reply.DecodePayload(&resolved) != nil || resolved.MovedCount != 5 || resolved.RemainderCount != 2 {
				t.Fatalf("resolution acknowledgement = %+v", reply)
			}
			for _, card := range cards {
				if strings.Contains(string(reply.Payload), card.Name) || strings.Contains(string(reply.Payload), card.ID) {
					t.Fatalf("acknowledgement exposed a viewed card: %+v", reply)
				}
			}
			owner, graveyard := "their", "into graveyard"
			if sourceSeat == 1 {
				owner, graveyard = "Bob's", "into Bob's graveyard"
			}
			wantLogs := []string{
				"Alice resolved the top 7 card(s) of " + owner + " library across 5 destination(s).",
				"Alice revealed Revealed Hand B, Revealed Hand A from the top 7 card(s) of " + owner + " library and put them into hand.",
				"Alice revealed Revealed Graveyard from the top 7 card(s) of " + owner + " library and put them " + graveyard + ".",
				"Alice revealed Revealed Top from the top 7 card(s) of " + owner + " library and put them on top of their library.",
			}
			for _, sess := range []*Session{setup.host, setup.guest, setup.spectator} {
				envelope := receivePrivateZoneEnvelope(t, sess)
				var snapshot protocol.GameSnapshot
				if envelope.Type != protocol.TypeGameSnapshot || envelope.DecodePayload(&snapshot) != nil ||
					len(snapshot.Log) != len(wantLogs)+1 {
					t.Fatalf("%s snapshot = %+v", sess.DisplayName, envelope)
				}
				for index, want := range wantLogs {
					if log := snapshot.Log[index+1]; log.Kind != "library_view" || log.Text != want {
						t.Fatalf("%s resolution log %d = %+v, want %q", sess.DisplayName, index, log, want)
					}
				}
				if sess != setup.host {
					for _, secret := range []string{
						"Hidden Hand", "Hidden Face Down", "Hidden Bottom", "Unseen Suffix",
						"hidden-hand", "reveal-hand-a", "reveal-hand-b", "reveal-top", "hidden-bottom", "unseen-suffix",
					} {
						if strings.Contains(string(envelope.Payload), secret) {
							t.Fatalf("%s learned private identity %q: %s", sess.DisplayName, secret, envelope.Payload)
						}
					}
					if len(snapshot.Seats[0].Hand) != 0 || snapshot.Seats[0].HandCount != 3 {
						t.Fatalf("%s hand projection = %+v", sess.DisplayName, snapshot.Seats[0])
					}
				}
			}
			for _, card := range setup.room.Game.Seats[0].Hand {
				if card.OwnerSeat != sourceSeat {
					t.Fatalf("revealing changed immutable ownership: %+v", card)
				}
			}
		})
	}
}

func TestTopCardViewFaceDownSuppressesExplicitReveal(t *testing.T) {
	for _, sourceSeat := range []int{0, 1} {
		t.Run(fmt.Sprintf("source seat %d", sourceSeat), func(t *testing.T) {
			setup := newPrivateZoneConsentSetup(t)
			viewed := openPrivateTopLibraryView(t, setup, sourceSeat, 1)
			card := viewed.Cards[0]
			request, _ := protocol.NewEnvelope(protocol.TypeGameSearchLibrary, protocol.GameSearchLibrary{
				CardID: card.ID, ToZone: protocol.LibraryDestinationBattlefield,
				Position: &protocol.CardPosition{X: 0.5, Y: 0.5},
				TopCard:  true, Reveal: true, FaceDown: true,
				SourceSeat: &sourceSeat, ApprovalID: viewed.ApprovalID,
			})
			if err := setup.handler.handleGameSearchLibrary(setup.host, request); err != nil {
				t.Fatal(err)
			}
			reply := receivePrivateZoneEnvelope(t, setup.host)
			var moved protocol.GameLibrarySearched
			if reply.Type != protocol.TypeGameLibrarySearched || reply.DecodePayload(&moved) != nil || moved.Revealed {
				t.Fatalf("face-down top-card reply = %+v", reply)
			}
			for _, sess := range []*Session{setup.host, setup.guest, setup.spectator} {
				envelope := receivePrivateZoneEnvelope(t, sess)
				var snapshot protocol.GameSnapshot
				if envelope.Type != protocol.TypeGameSnapshot || envelope.DecodePayload(&snapshot) != nil || len(snapshot.Log) != 2 {
					t.Fatalf("%s snapshot = %+v", sess.DisplayName, envelope)
				}
				log := snapshot.Log[1]
				if log.Kind != "library_view" || strings.Contains(log.Text, card.Name) ||
					!strings.Contains(log.Text, "put 1 card(s) face down onto battlefield") {
					t.Fatalf("face-down top-card log = %+v", log)
				}
				if sess != setup.host && strings.Contains(string(envelope.Payload), card.Name) {
					t.Fatalf("%s learned face-down identity: %s", sess.DisplayName, envelope.Payload)
				}
			}
		})
	}
}

func openPrivateTopLibraryView(t *testing.T, setup privateZoneConsentSetup, sourceSeat, count int) protocol.GameZoneDumped {
	t.Helper()
	dump, _ := protocol.NewEnvelope(protocol.TypeGameDumpZone,
		protocol.GameDumpZone{Zone: protocol.ZoneLibrary, Seat: &sourceSeat, TopCount: count})
	if err := setup.handler.handleGameDumpZone(setup.host, dump); err != nil {
		t.Fatal(err)
	}
	if sourceSeat != 0 {
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
		viewed.TopCount != count || len(viewed.Cards) != count {
		t.Fatalf("private top view = %+v", dumped)
	}
	for _, sess := range []*Session{setup.host, setup.guest, setup.spectator} {
		if snapshot := receivePrivateZoneEnvelope(t, sess); snapshot.Type != protocol.TypeGameSnapshot {
			t.Fatalf("%s dump projection = %+v", sess.DisplayName, snapshot)
		}
	}
	return viewed
}
