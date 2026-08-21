// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

func loadRandomFixture(t *testing.T, name string) protocol.Envelope {
	t.Helper()
	path := filepath.Join("../../../../testdata/protocol/v1", name)
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", name, err)
	}
	envelope, err := protocol.ParseEnvelope(data)
	if err != nil {
		t.Fatalf("parse %s: %v", name, err)
	}
	return envelope
}

func assertRandomFixture(t *testing.T, name, roomID string,
	got protocol.Envelope) {
	t.Helper()
	want := loadRandomFixture(t, name)
	gotData, err := got.Marshal()
	if err != nil {
		t.Fatalf("marshal actual %s: %v", name, err)
	}
	wantData, err := want.Marshal()
	if err != nil {
		t.Fatalf("marshal fixture %s: %v", name, err)
	}
	var gotValue, wantValue map[string]any
	if err := json.Unmarshal(gotData, &gotValue); err != nil {
		t.Fatalf("decode actual %s: %v", name, err)
	}
	if err := json.Unmarshal(wantData, &wantValue); err != nil {
		t.Fatalf("decode fixture %s: %v", name, err)
	}
	if payload, ok := wantValue["payload"].(map[string]any); ok {
		payload["roomId"] = roomID
	}
	if !reflect.DeepEqual(gotValue, wantValue) {
		t.Fatalf("%s drifted:\nwant: %s\n got: %s", name, wantData, gotData)
	}
}

func TestRandomSelectionMatchesGoldenFixtureAndRedactsFaceDownName(t *testing.T) {
	r := newStartedUtilityRoom(t, protocol.MatchBO3)
	r.Game.Seats[0].Battlefield = []protocol.GameCard{{
		ID: "s0-c8", Name: "Alpha", OwnerSeat: 0,
	}}
	r.Game.Seats[1].Battlefield = []protocol.GameCard{{
		ID: "s1-c2", Name: "Secret Beta", OwnerSeat: 1, FaceDown: true,
	}}
	r.randomIndex = func(maximum int) (int, error) { return maximum - 1, nil }

	requestEnvelope := loadRandomFixture(t, "game-random-select.json")
	var request protocol.GameRandomSelect
	if err := requestEnvelope.DecodePayload(&request); err != nil {
		t.Fatalf("decode random request: %v", err)
	}
	result, err := r.RandomSelect("host-conn", request)
	if err != nil {
		t.Fatalf("random select face-down card: %v", err)
	}
	if result.Reply == nil {
		t.Fatal("random selection omitted acknowledgement")
	}
	result.Reply.ID = requestEnvelope.ID
	assertRandomFixture(t, "game-random-selected.json", r.ID, *result.Reply)

	if len(r.Game.Log) != 1 || r.Game.Log[0].Kind != "random_select" ||
		r.Game.Log[0].Text != "Host randomly selected a face-down card." ||
		strings.Contains(r.Game.Log[0].Text, "Secret Beta") {
		t.Fatalf("face-down random log = %+v", r.Game.Log)
	}
	replyData, err := result.Reply.Marshal()
	if err != nil {
		t.Fatalf("marshal random reply: %v", err)
	}
	if strings.Contains(string(replyData), "Secret Beta") {
		t.Fatalf("random reply leaked face-down name: %s", replyData)
	}
}

func TestRandomSelectionNamesFaceUpPublicCard(t *testing.T) {
	r := newStartedUtilityRoom(t, protocol.MatchBO3)
	r.Game.Seats[0].Battlefield = []protocol.GameCard{{
		ID: "s0-c8", Name: "Alpha", OwnerSeat: 0,
	}}
	r.Game.Seats[1].Battlefield = []protocol.GameCard{{
		ID: "s1-c2", Name: "Secret Beta", OwnerSeat: 1, FaceDown: true,
	}}
	r.randomIndex = func(maximum int) (int, error) { return 0, nil }

	result, err := r.RandomSelect("host-conn", protocol.GameRandomSelect{
		Kind:    protocol.RandomSelectionCard,
		CardIDs: []string{"s0-c8", "s1-c2"},
	})
	if err != nil {
		t.Fatalf("random select face-up card: %v", err)
	}
	var selected protocol.GameRandomSelected
	if result.Reply == nil || result.Reply.DecodePayload(&selected) != nil ||
		selected.SelectedCardID != "s0-c8" {
		t.Fatalf("face-up random reply = %+v", selected)
	}
	if len(r.Game.Log) != 1 ||
		r.Game.Log[0].Text != "Host randomly selected Alpha." {
		t.Fatalf("face-up random log = %+v", r.Game.Log)
	}
}
