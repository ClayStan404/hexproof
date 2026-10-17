// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"reflect"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestRoomSnapshotFanoutKeepsPrivateNamesAndPublicSequence(t *testing.T) {
	h := retentionHandler(t, DefaultConfig())
	host, guest, watcher := retentionSession(h, "host"), retentionSession(h, "guest"), retentionSession(h, "watcher")
	create, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{
		Name: "Private names", Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatModern,
		MaxSeats: 2, AllowSpectators: true,
		MatchMode: protocol.MatchBO1, RulesMode: protocol.RulesModeManual,
	})
	if err := h.handleRoomCreate(host, create); err != nil {
		t.Fatal(err)
	}
	initial := readDeckNameSnapshot(t, host, "", nil)
	if initial.SeqValue() != 1 {
		t.Fatalf("initial snapshot sequence = %d", initial.SeqValue())
	}
	for _, sess := range []*Session{guest, watcher} {
		join, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{
			RoomID: host.Room().ID, AsSpectator: sess == watcher,
		})
		if err := h.handleRoomJoin(sess, join); err != nil {
			t.Fatal(err)
		}
		readDeckNameSnapshot(t, host, "", nil)
		readDeckNameSnapshot(t, guest, "", nil)
		if sess == watcher {
			readDeckNameSnapshot(t, watcher, "", nil)
		}
	}
	for selectionIndex, selection := range []struct {
		sess *Session
		name string
	}{
		{host, "Private host deck"}, {guest, "Private guest deck"}, {host, "Changed host <literal> deck"},
	} {
		selectDeck, _ := protocol.NewEnvelope(protocol.TypeDeckSelect, protocol.DeckSelect{
			Name: selection.name, Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatModern,
			Mainboard: []protocol.DeckCard{{Name: "Forest", Count: 60, SetCode: "M21", CollectorNumber: "273"}},
			Sideboard: []protocol.DeckCard{{Name: "Negate", Count: 2, SetCode: "M21", CollectorNumber: "59"}},
		})
		if err := h.handleDeckSelect(selection.sess, selectDeck); err != nil {
			t.Fatal(err)
		}
		operation, err := h.hub.lockRoomOperation(host.Room().ID)
		if err != nil {
			t.Fatal(err)
		}
		operation.mu.Lock()
		public := operation.room.Snapshot()
		wantNames := []string{"", "", ""}
		for index, sess := range []*Session{host, guest} {
			seat := operation.room.FindSeatByConnection(sess.ConnectionID)
			if deck := operation.room.Seats[seat].RegisteredDeck; deck != nil {
				wantNames[index] = deck.Name
			}
		}
		operation.mu.Unlock()
		operation.opMu.Unlock()
		if public.OwnDeckName != "" {
			t.Fatal("public reducer snapshot acquired a private name")
		}
		var seq int64
		for index, sess := range []*Session{host, guest, watcher} {
			env := readDeckNameSnapshot(t, sess, wantNames[index], &public)
			if index == 0 {
				seq = env.SeqValue()
			} else if env.SeqValue() != seq {
				t.Fatalf("recipient %s changed the shared public sequence", sess.ConnectionID)
			}
		}
		if seq != int64(4+selectionIndex) {
			t.Fatalf("selection snapshot sequence = %d, want %d", seq, 4+selectionIndex)
		}
	}
}

func readDeckNameSnapshot(t *testing.T, sess *Session, ownName string, public *protocol.RoomSnapshot) protocol.Envelope {
	t.Helper()
	var result protocol.Envelope
	count := 0
	for len(sess.Send) > 0 {
		env := receiveEventEnvelope(t, sess)
		if env.Type == protocol.TypeError {
			t.Fatalf("%s error: %s", sess.ConnectionID, env.Payload)
		}
		if env.Type != protocol.TypeRoomSnapshot {
			continue
		}
		count++
		result = env
		var snapshot protocol.RoomSnapshot
		if err := env.DecodePayload(&snapshot); err != nil || !env.HasSeq() || env.SeqValue() <= 0 {
			t.Fatalf("invalid room snapshot: %+v, err=%v", env, err)
		}
		if snapshot.OwnDeckName != ownName {
			t.Fatalf("%s own name %q, want %q", sess.ConnectionID, snapshot.OwnDeckName, ownName)
		}
		for _, hidden := range []string{"Private host deck", "Private guest deck", "Changed host <literal> deck", "Forest", "Negate", "mainboard", "sideboard"} {
			if hidden != ownName && strings.Contains(string(env.Payload), hidden) {
				t.Fatalf("%s exposed %q: %s", sess.ConnectionID, hidden, env.Payload)
			}
		}
		snapshot.OwnDeckName = ""
		if public != nil && !reflect.DeepEqual(snapshot, *public) {
			t.Fatalf("recipient-private projection changed public room state: %+v vs %+v", snapshot, *public)
		}
	}
	if count != 1 {
		t.Fatalf("%s received %d room snapshots, want one", sess.ConnectionID, count)
	}
	return result
}
