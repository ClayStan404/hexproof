// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestFaceDownProjectionKeepsIdentityOnlyForController(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("guest-conn", "Guest", false, ""); err != nil {
		t.Fatalf("join guest: %v", err)
	}
	if _, err := r.Join("spectator-conn", "Watcher", true, ""); err != nil {
		t.Fatalf("join spectator: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{Seat: 0, DisplayName: "Host"},
			{
				Seat: 1, DisplayName: "Guest",
				Battlefield: []protocol.GameCard{{
					ID: "borrowed", Name: "Hidden permanent",
					SetCode: "TST", CollectorNumber: "1",
					TypeLine:  "Artifact Creature — Construct",
					OwnerSeat: 0, FaceName: "Back",
				}},
			},
		},
		NextLogID: 1,
	}

	if _, err := r.SetCardFace("host-conn", protocol.GameSetCardFace{
		CardID: "borrowed", FaceName: "Alternate",
	}); err == nil || err.Error() != protocol.ErrInvalidTarget {
		t.Fatalf("owner changed controlled card face: %v", err)
	}
	if _, err := r.SetFaceDown("host-conn", protocol.GameSetFaceDown{
		CardID: "borrowed", FaceDown: true,
	}); err == nil || err.Error() != protocol.ErrInvalidTarget {
		t.Fatalf("owner turned controlled card face down: %v", err)
	}

	result, err := r.SetFaceDown("guest-conn", protocol.GameSetFaceDown{
		CardID: "borrowed", FaceDown: true,
	})
	if err != nil {
		t.Fatalf("set face down: %v", err)
	}
	var reply protocol.GameFaceDownSet
	if result.Reply == nil || result.Reply.DecodePayload(&reply) != nil ||
		!reply.FaceDown || reply.CardID != "borrowed" {
		t.Fatalf("face-down reply = %+v", reply)
	}
	if card := r.Game.Seats[1].Battlefield[0]; !card.FaceDown ||
		card.FaceName != "" || card.Name != "Hidden permanent" {
		t.Fatalf("authoritative card = %+v", card)
	}

	controllerSnapshot, err := r.GameSnapshot("guest-conn")
	if err != nil {
		t.Fatalf("controller snapshot: %v", err)
	}
	if card := controllerSnapshot.Seats[1].Battlefield[0]; card.Name != "Hidden permanent" || !card.FaceDown {
		t.Fatalf("controller projection = %+v", card)
	}
	for _, viewer := range []string{"host-conn", "spectator-conn"} {
		snapshot, snapshotErr := r.GameSnapshot(viewer)
		if snapshotErr != nil {
			t.Fatalf("snapshot for %s: %v", viewer, snapshotErr)
		}
		card := snapshot.Seats[1].Battlefield[0]
		if !card.FaceDown || card.ID != "borrowed" || card.OwnerSeat != 0 ||
			card.Name != "" || card.SetCode != "" ||
			card.CollectorNumber != "" || card.TypeLine != "" ||
			card.FaceName != "" {
			t.Fatalf("redacted projection for %s = %+v", viewer, card)
		}
	}
	if len(r.Game.Log) != 1 ||
		r.Game.Log[0].Text == "" ||
		strings.Contains(r.Game.Log[0].Text, "Hidden permanent") {
		t.Fatalf("face-down log = %+v", r.Game.Log)
	}
}

func TestFaceDownStateClearsAndHiddenMoveLogRedactsIdentity(t *testing.T) {
	for _, toZone := range []string{protocol.ZoneHand, protocol.ZoneLibrary} {
		t.Run(toZone, func(t *testing.T) {
			r := newTestRoom(t, 2, true)
			if _, err := r.Join("guest-conn", "Guest", false, ""); err != nil {
				t.Fatalf("join guest: %v", err)
			}
			if _, err := r.Join("spectator-conn", "Watcher", true, ""); err != nil {
				t.Fatalf("join spectator: %v", err)
			}
			r.Phase = protocol.RoomPhaseStarted
			r.Game = &GameState{
				Number: 1,
				Seats: []PlayerGameState{
					{
						Seat: 0, DisplayName: "Host",
						Battlefield: []protocol.GameCard{{
							ID: "hidden", Name: "Hidden permanent", OwnerSeat: 0,
							FaceDown: true,
						}},
					},
					{Seat: 1, DisplayName: "Guest"},
				},
				NextLogID: 1,
			}

			if _, err := r.MoveCard("host-conn", protocol.GameMoveCard{
				CardID: "hidden", FromZone: protocol.ZoneBattlefield,
				ToZone: toZone,
			}); err != nil {
				t.Fatalf("move face-down card: %v", err)
			}
			var moved []protocol.GameCard
			if toZone == protocol.ZoneHand {
				moved = r.Game.Seats[0].Hand
			} else {
				moved = r.Game.Seats[0].Library
			}
			if len(moved) != 1 || moved[0].FaceDown {
				t.Fatalf("%s retained face-down state: %+v", toZone, moved)
			}
			if len(r.Game.Log) != 1 ||
				strings.Contains(r.Game.Log[0].Text, "Hidden permanent") ||
				!strings.Contains(r.Game.Log[0].Text, "a face-down card") {
				t.Fatalf("authoritative log leaked face-down identity: %+v", r.Game.Log)
			}
			for _, viewer := range []string{"guest-conn", "spectator-conn"} {
				snapshot, err := r.GameSnapshot(viewer)
				if err != nil {
					t.Fatalf("snapshot for %s: %v", viewer, err)
				}
				if len(snapshot.Log) != 1 ||
					strings.Contains(snapshot.Log[0].Text, "Hidden permanent") {
					t.Fatalf("viewer %s log leaked face-down identity: %+v", viewer, snapshot.Log)
				}
			}
		})
	}
}

func TestFaceDownCardCounterLogRedactsIdentityForEveryViewer(t *testing.T) {
	r := newTestRoom(t, 2, true)
	if _, err := r.Join("guest-conn", "Guest", false, ""); err != nil {
		t.Fatalf("join guest: %v", err)
	}
	if _, err := r.Join("spectator-conn", "Watcher", true, ""); err != nil {
		t.Fatalf("join spectator: %v", err)
	}
	r.Phase = protocol.RoomPhaseStarted
	r.Game = &GameState{
		Number: 1,
		Seats: []PlayerGameState{
			{
				Seat: 0, DisplayName: "Host",
				Battlefield: []protocol.GameCard{{
					ID: "secret-permanent", Name: "Demonic Tutor",
					OwnerSeat: 0, FaceDown: true,
				}},
			},
			{Seat: 1, DisplayName: "Guest"},
		},
		NextLogID:         1,
		NextCardCounterID: 1,
	}

	if _, err := r.SetCardCounter("host-conn", protocol.GameSetCardCounter{
		CardID: "secret-permanent", Kind: protocol.CardCounterKindAbility,
		Label: "Manifest", Value: intPointer(1),
	}); err != nil {
		t.Fatalf("set face-down counter: %v", err)
	}
	if len(r.Game.Log) != 1 || strings.Contains(r.Game.Log[0].Text, "Demonic Tutor") ||
		!strings.Contains(r.Game.Log[0].Text, "a face-down card") {
		t.Fatalf("authoritative log leaked face-down identity: %+v", r.Game.Log)
	}
	for _, viewer := range []string{"guest-conn", "spectator-conn"} {
		snapshot, err := r.GameSnapshot(viewer)
		if err != nil {
			t.Fatalf("snapshot for %s: %v", viewer, err)
		}
		if len(snapshot.Log) != 1 || strings.Contains(snapshot.Log[0].Text, "Demonic Tutor") {
			t.Fatalf("viewer %s log leaked face-down identity: %+v", viewer, snapshot.Log)
		}
	}
}
