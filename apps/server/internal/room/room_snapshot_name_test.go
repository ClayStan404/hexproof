// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestRoomSnapshotDeckNameIsOwnerPrivateAndResumesWithoutLocalCache(t *testing.T) {
	r := newTestRoom(t, 4, true)
	if _, err := r.Join("guest-conn", "Guest", false, ""); err != nil {
		t.Fatal(err)
	}
	if _, err := r.Join("watcher-conn", "Watcher", true, ""); err != nil {
		t.Fatal(err)
	}
	for index, conn := range []string{"host-conn", "guest-conn"} {
		deck := testDeck(protocol.FormatEDH)
		deck.Name = []string{"Private host registration", "Private guest registration"}[index]
		if _, err := r.SelectDeck(conn, deck); err != nil {
			t.Fatal(err)
		}
	}
	public := r.Snapshot()
	// Even a reused recipient envelope must lose its previous private metadata.
	public.OwnDeckName = "Injected previous recipient name"
	for _, test := range []struct{ conn, want string }{
		{"host-conn", "Private host registration"}, {"guest-conn", "Private guest registration"},
		{"watcher-conn", ""}, {"unrelated-conn", ""},
	} {
		projected := r.ProjectRoomSnapshot(test.conn, public)
		if projected.OwnDeckName != test.want {
			t.Errorf("%s deck name %q, want %q", test.conn, projected.OwnDeckName, test.want)
		}
		projected.OwnDeckName = public.OwnDeckName
		if !reflect.DeepEqual(projected, public) {
			t.Errorf("%s projection changed public room state", test.conn)
		}
	}
	if r.Snapshot().OwnDeckName != "" {
		t.Fatal("public snapshot acquired owner metadata")
	}
	if _, err := r.Reconnect("host-conn", "resumed-host"); err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct{ conn, want string }{
		{"resumed-host", "Private host registration"}, {"watcher-conn", ""},
	} {
		envelopes, err := r.ResumeEnvelopes(test.conn)
		if err != nil {
			t.Fatal(err)
		}
		var snapshot protocol.RoomSnapshot
		if len(envelopes) != 1 || envelopes[0].DecodePayload(&snapshot) != nil ||
			!envelopes[0].HasSeq() || snapshot.OwnDeckName != test.want {
			t.Fatalf("%s resume lost private selected name: %+v", test.conn, envelopes)
		}
		encoded, _ := json.Marshal(snapshot)
		for _, secret := range []string{"Private guest registration", "Injected previous recipient name", "Sol Ring", "mainboard", "sideboard"} {
			if strings.Contains(string(encoded), secret) {
				t.Errorf("%s resume exposed %q", test.conn, secret)
			}
		}
	}
	if r.ProjectRoomSnapshot("host-conn", public).OwnDeckName != "" {
		t.Fatal("replaced connection retained owner display metadata")
	}
}

func TestRoomSnapshotDeckNameRequiresCurrentHumanSelectionAndMatchingPublicSeat(t *testing.T) {
	for _, scenario := range []string{"changed-selection", "cleared-selection", "automated-controller", "unoccupied-seat", "foreign-room", "missing-seat", "public-unselected"} {
		t.Run(scenario, func(t *testing.T) {
			r := newTestRoom(t, 4, true)
			deck := testDeck(protocol.FormatEDH)
			deck.Name = "Original private name"
			if _, err := r.SelectDeck("host-conn", deck); err != nil {
				t.Fatal(err)
			}
			snapshot := r.Snapshot()
			snapshot.OwnDeckName = "Another recipient's stale name"
			want := ""
			switch scenario {
			case "changed-selection":
				deck.Name = "New <literal> deck name"
				if _, err := r.SelectDeck("host-conn", deck); err != nil {
					t.Fatal(err)
				}
				want = deck.Name
			case "cleared-selection":
				r.Seats[0].Deck = nil
			case "automated-controller":
				r.Seats[0].Controller = "forge"
			case "unoccupied-seat":
				r.Seats[0].Occupied = false
			case "foreign-room":
				snapshot.RoomID = "OTHER1"
			case "missing-seat":
				snapshot.Seats = nil
			case "public-unselected":
				snapshot.Seats[0].DeckSelected = false
			}
			projected := r.ProjectRoomSnapshot("host-conn", snapshot)
			if projected.OwnDeckName != want {
				t.Fatalf("private name = %q, want %q", projected.OwnDeckName, want)
			}
			projected.OwnDeckName = snapshot.OwnDeckName
			if !reflect.DeepEqual(projected, snapshot) {
				t.Fatal("private projection changed public state")
			}
		})
	}
}
