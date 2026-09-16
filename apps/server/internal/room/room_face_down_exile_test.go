// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"encoding/json"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestLibraryTopFaceDownExileHidesIdentityUntilReturned(t *testing.T) {
	for _, spectatorsSeeHands := range []bool{false, true} {
		t.Run(map[bool]string{false: "public-spectators", true: "hand-visible-spectators"}[spectatorsSeeHands], func(t *testing.T) {
			r := newTestRoom(t, 2, true)
			r.SpectatorsSeeHands = spectatorsSeeHands
			if _, err := r.Join("guest-conn", "Guest", false, ""); err != nil {
				t.Fatal(err)
			}
			if _, err := r.Join("spectator-conn", "Watcher", true, ""); err != nil {
				t.Fatal(err)
			}
			r.Phase = protocol.RoomPhaseStarted
			r.Game = &GameState{Number: 1, NextLogID: 1, Seats: []PlayerGameState{
				{Seat: 0, DisplayName: "Host", Library: []protocol.GameCard{
					{ID: "top-1", Name: "Secret One", SetCode: "TST", CollectorNumber: "1", TypeLine: "Sorcery", OwnerSeat: 0},
					{ID: "top-2", Name: "Secret Two", SetCode: "TST", CollectorNumber: "2", TypeLine: "Creature", OwnerSeat: 0},
					{ID: "untouched", Name: "Still in library", OwnerSeat: 0},
				}},
				{Seat: 1, DisplayName: "Guest"},
			}}

			for _, id := range []string{"top-1", "top-2"} {
				result, err := r.MoveCard("host-conn", protocol.GameMoveCard{
					CardID: "__library_top__", FromZone: protocol.ZoneLibrary,
					ToZone: protocol.ZoneExile, FaceDown: true,
				})
				if err != nil {
					t.Fatalf("exile library top: %v", err)
				}
				var reply protocol.GameCardMoved
				if result.Reply == nil || result.Reply.DecodePayload(&reply) != nil || reply.CardID != id {
					t.Fatalf("move reply = %+v", reply)
				}
			}
			if len(r.Game.Seats[0].Library) != 1 || r.Game.Seats[0].Library[0].ID != "untouched" {
				t.Fatal("exile did not consume the top two cards in order")
			}
			for _, viewer := range []string{"host-conn", "guest-conn", "spectator-conn"} {
				snapshot, err := r.GameSnapshot(viewer)
				if err != nil {
					t.Fatal(err)
				}
				if len(snapshot.Seats[0].Exile) != 2 {
					t.Fatalf("exile count for %s = %d", viewer, len(snapshot.Seats[0].Exile))
				}
				for _, card := range snapshot.Seats[0].Exile {
					if !card.FaceDown || card.ID == "" || card.OwnerSeat != 0 || card.Name != "" ||
						card.SetCode != "" || card.CollectorNumber != "" || card.TypeLine != "" || card.FaceName != "" {
						t.Fatalf("exile identity for %s = %+v", viewer, card)
					}
				}
				wire, err := json.Marshal(snapshot)
				if err != nil || strings.Contains(string(wire), "Secret") {
					t.Fatalf("identity escaped through %s snapshot/log: %s (%v)", viewer, wire, err)
				}
			}
			if r.Game.Seats[0].Exile[0].Name != "Secret One" {
				t.Fatal("redaction mutated the authoritative identity")
			}
			if _, err := r.DumpZone("host-conn", protocol.GameDumpZone{Zone: protocol.ZoneExile}); err == nil {
				t.Fatal("private dump exposed face-down exile")
			}
			if _, err := r.SetFaceDown("host-conn", protocol.GameSetFaceDown{CardID: "top-1", FaceDown: false}); err == nil {
				t.Fatal("battlefield flip command accepted an exiled card")
			}

			// Bomat Courier returns its selected exiled cards to the owner's hand
			// without revealing them to the opponent or in the shared log.
			if _, err := r.MoveCards("host-conn", protocol.GameMoveCards{
				CardIDs: []string{"top-1", "top-2"}, FromZone: protocol.ZoneExile, ToZone: protocol.ZoneHand,
			}); err != nil {
				t.Fatalf("return exiled cards: %v", err)
			}
			for _, viewer := range []string{"host-conn", "guest-conn", "spectator-conn"} {
				snapshot, err := r.GameSnapshot(viewer)
				if err != nil {
					t.Fatal(err)
				}
				state := snapshot.Seats[0]
				if len(state.Exile) != 0 || state.HandCount != 2 {
					t.Fatalf("return projection = %+v", state)
				}
				visible := viewer == "host-conn" || (viewer == "spectator-conn" && spectatorsSeeHands)
				if visible {
					if len(state.Hand) != 2 || state.Hand[0].Name != "Secret One" || state.Hand[0].FaceDown {
						t.Fatalf("owner hand not restored: %+v", state.Hand)
					}
				} else if len(state.Hand) != 0 {
					t.Fatalf("private hand exposed to %s: %+v", viewer, state.Hand)
				}
				for _, entry := range snapshot.Log {
					if strings.Contains(entry.Text, "Secret") {
						t.Fatalf("shared log leaked returned card: %s", entry.Text)
					}
				}
			}
		})
	}
}

func TestLibraryTopMovesToPublicStackWithoutPrivatePeek(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("guest-conn", "Guest", false, ""); err != nil {
		t.Fatal(err)
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{Number: 1, NextLogID: 1, Seats: []PlayerGameState{
		{Seat: 0, DisplayName: "Host", Library: []protocol.GameCard{
			{ID: "top", Name: "Lightning Bolt", OwnerSeat: 0},
		}},
		{Seat: 1, DisplayName: "Guest"},
	}}
	move := protocol.GameMoveCard{CardID: "__library_top__", FromZone: protocol.ZoneLibrary, ToZone: protocol.ZoneStack, FaceDown: true}
	if _, err := r.MoveCard("host-conn", move); err == nil || len(r.Game.Seats[0].Library) != 1 {
		t.Fatal("invalid face-down stack move must leave the library untouched")
	}
	move.FaceDown = false
	if _, err := r.MoveCard("host-conn", move); err != nil {
		t.Fatal(err)
	}
	snapshot, err := r.GameSnapshot("guest-conn")
	if err != nil || len(snapshot.Stack) != 1 || snapshot.Stack[0].Name != "Lightning Bolt" || snapshot.Seats[0].LibraryCount != 0 {
		t.Fatalf("stack projection = %+v (%v)", snapshot.Stack, err)
	}
	if len(r.Game.Log) != 1 || r.Game.Log[0].Kind != "move_card" {
		t.Fatalf("stack move performed a private peek: %+v", r.Game.Log)
	}
}
