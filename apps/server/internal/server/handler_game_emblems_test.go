// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
)

func TestEmblemRetentionSnapshotIsDetachedAndPersisted(t *testing.T) {
	setup := newPrivateZoneConsentSetup(t)
	owner := 0
	request := protocol.GameCreateEmblem{Seat: &owner, Name: "Test Emblem", SetCode: "TST", CollectorNumber: "1"}
	for range 2 {
		if _, err := setup.room.CreateEmblem(setup.host.ConnectionID, request); err != nil {
			t.Fatal(err)
		}
	}
	id := setup.room.Game.Seats[0].Emblems[0].ID
	now := time.Now()
	store, err := newRetentionStore(t.TempDir(), time.Hour, 10, 16<<20, now)
	if err != nil {
		t.Fatal(err)
	}
	record := store.snapshot(setup.room, now)
	if record == nil {
		t.Fatal("missing retained game")
	}
	if _, err := setup.room.RemoveEmblem(setup.host.ConnectionID, protocol.GameRemoveEmblem{EmblemID: id}); err != nil {
		t.Fatal(err)
	}
	if len(record.Game.Seats[0].Emblems) != 2 || record.Game.Seats[0].Emblems[0].ID != id {
		t.Fatal("live emblem removal mutated the detached retention snapshot")
	}
	if err := store.saveSnapshot(record); err != nil {
		t.Fatal(err)
	}
	entries, err := os.ReadDir(store.dir)
	if err != nil || len(entries) != 1 {
		t.Fatalf("retention files=%v err=%v", entries, err)
	}
	saved, err := readRetainedRoom(filepath.Join(store.dir, entries[0].Name()), 16<<20)
	if err != nil || len(saved.Game.Seats[0].Emblems) != 2 || saved.Game.Seats[0].Emblems[0].ID != id || saved.Game.NextEmblemID != 3 {
		t.Fatalf("retained emblem state lost: %+v, err=%v", saved, err)
	}
}

func TestEmblemConcurrentCreationRemovalAndOrderedPublicFanout(t *testing.T) {
	setup := newPrivateZoneConsentSetup(t)
	for _, sess := range []*Session{setup.host, setup.guest, setup.spectator} {
		sess.Send = make(chan []byte, 1024)
	}
	owner := 0
	request := protocol.GameCreateEmblem{Seat: &owner, Name: "Test Emblem",
		SetCode: "TEST", CollectorNumber: "1", TypeLine: "Emblem"}
	var workers sync.WaitGroup
	for _, sess := range []*Session{setup.host, setup.guest} {
		workers.Add(1)
		go func() {
			defer workers.Done()
			for index := 0; index < protocol.MaxEmblemsPerSeat/2; index++ {
				env, _ := protocol.NewEnvelope(protocol.TypeGameCreateEmblem, request)
				env.ID = fmt.Sprintf("%s-%d", sess.ConnectionID, index)
				if err := setup.handler.dispatch(context.Background(), nil, sess, env); err != nil {
					t.Errorf("dispatch create: %v", err)
				}
			}
		}()
	}
	workers.Wait()
	if len(setup.room.Game.Seats[owner].Emblems) != protocol.MaxEmblemsPerSeat {
		t.Fatalf("lost concurrent creation: %d", len(setup.room.Game.Seats[owner].Emblems))
	}
	ids := make(map[string]bool)
	for _, emblem := range setup.room.Game.Seats[owner].Emblems {
		if ids[emblem.ID] {
			t.Fatal("duplicate emblem id")
		}
		ids[emblem.ID] = true
	}
	for _, sess := range []*Session{setup.host, setup.guest, setup.spectator} {
		acknowledgements, snapshots := 0, 0
		lastSeq := int64(0)
		for len(sess.Send) > 0 {
			env := receivePrivateZoneEnvelope(t, sess)
			switch env.Type {
			case protocol.TypeGameEmblemCreated:
				acknowledgements++
				var ack protocol.GameEmblemCreated
				if env.DecodePayload(&ack) != nil || !ids[ack.EmblemID] || ack.Seat != owner || env.ID == "" {
					t.Fatalf("invalid correlated ack %+v", env)
				}
			case protocol.TypeGameSnapshot:
				snapshots++
				var snapshot protocol.GameSnapshot
				if env.DecodePayload(&snapshot) != nil || !env.HasSeq() || env.SeqValue() <= lastSeq ||
					len(snapshot.Seats[owner].Emblems) != snapshots {
					t.Fatalf("out-of-order public projection: seq=%d count=%d snapshot=%+v", env.SeqValue(), snapshots, snapshot)
				}
				lastSeq = env.SeqValue()
				if len(snapshot.Seats[1].Hand) != 0 {
					t.Fatal("opponent/spectator hand leak")
				}
			default:
				t.Fatalf("unexpected create event %s: %s", env.Type, env.Payload)
			}
		}
		wantAcks := protocol.MaxEmblemsPerSeat / 2
		if sess == setup.spectator {
			wantAcks = 0
		}
		if snapshots != protocol.MaxEmblemsPerSeat || acknowledgements != wantAcks {
			t.Fatalf("fanout to %s: snapshots=%d acks=%d", sess.ConnectionID, snapshots, acknowledgements)
		}
	}
	for id := range ids {
		workers.Add(1)
		go func() {
			defer workers.Done()
			env, _ := protocol.NewEnvelope(protocol.TypeGameRemoveEmblem, protocol.GameRemoveEmblem{EmblemID: id})
			env.ID = "remove-" + id
			if err := setup.handler.dispatch(context.Background(), nil, setup.host, env); err != nil {
				t.Errorf("dispatch remove: %v", err)
			}
		}()
	}
	workers.Wait()
	if len(setup.room.Game.Seats[owner].Emblems) != 0 {
		t.Fatal("concurrent removals lost state")
	}
	for _, sess := range []*Session{setup.host, setup.guest, setup.spectator} {
		count := protocol.MaxEmblemsPerSeat
		lastSeq := int64(0)
		for len(sess.Send) > 0 {
			env := receivePrivateZoneEnvelope(t, sess)
			if env.Type == protocol.TypeGameEmblemRemoved {
				if sess != setup.host {
					t.Fatal("private acknowledgement sent to non-actor")
				}
				continue
			}
			count--
			var snapshot protocol.GameSnapshot
			if env.Type != protocol.TypeGameSnapshot || env.DecodePayload(&snapshot) != nil ||
				env.SeqValue() <= lastSeq || len(snapshot.Seats[owner].Emblems) != count {
				t.Fatalf("out-of-order removal fanout: %+v", env)
			}
			lastSeq = env.SeqValue()
		}
		if count != 0 {
			t.Fatal("missing removal snapshots")
		}
	}
}

func TestEmblemDispatchRejectsMissingNullSeatAndMissingRequestID(t *testing.T) {
	for _, payload := range []string{
		`{"name":"Emblem","setCode":"TST","collectorNumber":"1"}`,
		`{"seat":null,"name":"Emblem","setCode":"TST","collectorNumber":"1"}`,
		`{"seat":"0","name":"Emblem","setCode":"TST","collectorNumber":"1"}`,
	} {
		t.Run(payload, func(t *testing.T) {
			setup := newPrivateZoneConsentSetup(t)
			env := protocol.Envelope{Type: protocol.TypeGameCreateEmblem, ID: "bad-create", Payload: json.RawMessage(payload)}
			if err := setup.handler.dispatch(context.Background(), nil, setup.host, env); err != nil {
				t.Fatal(err)
			}
			reply := receivePrivateZoneEnvelope(t, setup.host)
			if reply.Type != protocol.TypeError || reply.ID != env.ID || len(setup.room.Game.Seats[0].Emblems) != 0 {
				t.Fatalf("invalid target silently became seat zero: %+v", reply)
			}
			assertNoPrivateZoneEnvelope(t, setup.guest)
			assertNoPrivateZoneEnvelope(t, setup.spectator)
		})
	}
	for _, messageType := range []string{protocol.TypeGameCreateEmblem, protocol.TypeGameRemoveEmblem} {
		t.Run(messageType, func(t *testing.T) {
			setup := newPrivateZoneConsentSetup(t)
			if err := setup.handler.dispatch(context.Background(), nil, setup.host, protocol.Envelope{Type: messageType}); err != nil {
				t.Fatal(err)
			}
			reply := receivePrivateZoneEnvelope(t, setup.host)
			var payload protocol.ErrorPayload
			if reply.Type != protocol.TypeError || reply.DecodePayload(&payload) != nil || payload.Code != protocol.ErrInvalidMessage {
				t.Fatalf("missing request id accepted: %+v", reply)
			}
		})
	}
}
