// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
)

func TestSideboardTimeoutMatchesGoldenFixture(t *testing.T) {
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

	expired, err := r.ExpireSideboard(testNow.Add(5 * time.Minute))
	if err != nil {
		t.Fatalf("expire sideboard: %v", err)
	}
	if len(expired.Broadcast) != 1 {
		t.Fatalf("expiry broadcast count = %d, want 1", len(expired.Broadcast))
	}
	got := expired.Broadcast[0]

	fixturePath := filepath.Join(
		"../../../../testdata/protocol/v1", "sideboard-completed-timeout.json")
	data, err := os.ReadFile(fixturePath)
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}
	want, err := protocol.ParseEnvelope(data)
	if err != nil {
		t.Fatalf("parse fixture: %v", err)
	}
	var gotPayload, wantPayload any
	if err := json.Unmarshal(got.Payload, &gotPayload); err != nil {
		t.Fatalf("decode emitted payload: %v", err)
	}
	if err := json.Unmarshal(want.Payload, &wantPayload); err != nil {
		t.Fatalf("decode fixture payload: %v", err)
	}
	if got.Type != want.Type || !reflect.DeepEqual(gotPayload, wantPayload) {
		t.Fatalf("sideboard timeout event drifted:\nwant: %s\n got: %s",
			data, mustMarshalEnvelope(t, got))
	}
	if deckCardCount(r.Seats[0].Deck.Mainboard) != protocol.MinMainboardCards ||
		deckCardCount(r.Seats[0].Deck.Sideboard) != 1 {
		t.Fatal("timeout committed the pending sideboard partition")
	}
}

func mustMarshalEnvelope(t *testing.T, envelope protocol.Envelope) []byte {
	t.Helper()
	data, err := envelope.Marshal()
	if err != nil {
		t.Fatalf("marshal envelope: %v", err)
	}
	return data
}
