// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"bytes"
	"errors"
	"fmt"
	"testing"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func TestProjectionSetKeepsPrivatePayloadsAndHeadersSeparate(t *testing.T) {
	h := NewHandler()
	t.Cleanup(func() { _ = h.Close() })
	shared, _ := protocol.NewEnvelope(protocol.TypeGameSnapshot, map[string]string{"view": "public"})
	shared = shared.WithSeq(9)
	private, _ := protocol.NewEnvelope(protocol.TypeGameSnapshot, map[string]string{"view": "private hand"})
	private = private.WithSeq(9)
	differentID := shared
	differentID.ID = "correlated"
	differentType := shared
	differentType.Type = protocol.TypeRulesSnapshot
	envelopes := []protocol.Envelope{shared, shared, private, differentID, differentType,
		shared.WithSeq(10), {Type: shared.Type, Payload: shared.Payload}}
	projections := make(map[string]protocol.Envelope)
	for index, envelope := range envelopes {
		id := fmt.Sprintf("recipient-%d", index)
		h.registerSession(&Session{ConnectionID: id, Send: make(chan []byte, 1)})
		projections[id] = envelope
	}
	h.sendProjectionSet(projections)
	var sharedBytes []byte
	for index, expected := range envelopes {
		id := fmt.Sprintf("recipient-%d", index)
		actual := <-h.sessionByConn(id).Send
		encoded, _ := expected.Marshal()
		if !bytes.Equal(actual, encoded) {
			t.Fatalf("recipient %d received a different audience/header: %s", index, actual)
		}
		if index == 0 {
			sharedBytes = actual
		} else if index == 1 && &actual[0] != &sharedBytes[0] {
			t.Fatal("identical spectator output was not shared")
		}
	}
}

func TestProjectionSetSharedMarshalFailureClosesOnlyAffectedAudience(t *testing.T) {
	h := NewHandler()
	t.Cleanup(func() { _ = h.Close() })
	shared, _ := protocol.NewEnvelope(protocol.TypeGameSnapshot, map[string]string{"view": "public"})
	private, _ := protocol.NewEnvelope(protocol.TypeGameSnapshot, map[string]string{"view": "private"})
	h.marshalEnvelope = func(envelope protocol.Envelope) ([]byte, error) {
		if len(envelope.Payload) > 0 && &envelope.Payload[0] == &shared.Payload[0] {
			return nil, errors.New("injected shared encoding failure")
		}
		return envelope.Marshal()
	}
	projections := make(map[string]protocol.Envelope)
	for index := range 5 {
		id := fmt.Sprintf("recipient-%d", index)
		h.registerSession(&Session{ConnectionID: id, Send: make(chan []byte, 2)})
		projections[id] = shared
		if index == 0 {
			projections[id] = private
		}
	}
	h.sendProjectionSet(projections)
	for index := range 5 {
		session := h.sessionByConn(fmt.Sprintf("recipient-%d", index))
		envelope := receivePrivateZoneEnvelope(t, session)
		if index == 0 {
			if envelope.Type != protocol.TypeGameSnapshot || session.closed {
				t.Fatal("private audience was lost when the unrelated spectator encoding failed")
			}
		} else if envelope.Type != protocol.TypeError || !session.closed {
			t.Fatal("spectator did not fail closed after its projection encoding failed")
		}
	}
}

func TestGameProjectionFanoutEncodesSharedSpectatorEnvelopeOnce(t *testing.T) {
	h, r, _, _ := newRunningManualJoinTestRoom(t, protocol.CardLoadPreload)
	for i := range protocol.MaxSpectators {
		spectator := newManualJoinTestSession(fmt.Sprintf("watcher-%d", i), "Watcher")
		joinCriticalSession(t, h, r, spectator, true)
		h.registerSession(spectator)
	}
	encodings := 0
	h.marshalEnvelope = func(envelope protocol.Envelope) ([]byte, error) {
		if envelope.Type == protocol.TypeGameSnapshot {
			encodings++
		}
		return envelope.Marshal()
	}
	h.fanoutGameProjections(r)
	if encodings != 3 {
		t.Fatalf("encoded %d full projections, want two private players plus one shared spectator projection", encodings)
	}
}

func BenchmarkGameProjectionFanout(b *testing.B) {
	for _, spectators := range []int{0, 8} {
		b.Run(fmt.Sprintf("4players-%dspectators", spectators), func(b *testing.B) {
			h := NewHandler()
			b.Cleanup(func() { _ = h.Close() })
			r := &room.Room{
				ID: "BENCH1", Format: protocol.FormatEDH, Phase: protocol.RoomPhaseStarted,
				Seats: make([]room.Seat, 4), RulesMode: protocol.RulesModeManual,
				Game: &room.GameState{Number: 1, Seats: make([]room.PlayerGameState, 4)},
			}
			h.hub.rooms[r.ID] = &roomEntry{room: r}
			members := make([]*Session, 0, 4+spectators)
			for index := range 4 + spectators {
				id := fmt.Sprintf("member-%d", index)
				session := &Session{ConnectionID: id, Send: make(chan []byte, 1)}
				session.setRoom(r)
				h.registerSession(session)
				members = append(members, session)
				if index >= 4 {
					r.Spectators = append(r.Spectators, room.Spectator{ConnectionID: id})
					continue
				}
				r.Seats[index] = room.Seat{Occupied: true, ConnectionID: id}
				r.Game.Seats[index] = room.PlayerGameState{Seat: index, DisplayName: id, Life: 40}
				for cardIndex := range 20 {
					r.Game.Seats[index].Battlefield = append(r.Game.Seats[index].Battlefield,
						protocol.GameCard{ID: fmt.Sprintf("s%d-c%d", index, cardIndex), OwnerSeat: index,
							Name: "Battlefield Creature", SetCode: "SET", CollectorNumber: "12",
							TypeLine: "Creature — Human Wizard"})
				}
				for cardIndex := range 7 {
					r.Game.Seats[index].Hand = append(r.Game.Seats[index].Hand,
						protocol.GameCard{ID: fmt.Sprintf("s%d-h%d", index, cardIndex), OwnerSeat: index,
							Name: "Private Hand Card", SetCode: "SET", CollectorNumber: "13"})
				}
			}
			for index := range protocol.MaxProjectedGameLog {
				r.Game.Log = append(r.Game.Log, protocol.GameLogEntry{ID: int64(index + 1), Kind: "move_card",
					Text: "Player moved a battlefield permanent to the shared stack."})
			}
			r.Game.NextLogID = int64(len(r.Game.Log) + 1)
			b.ReportAllocs()
			b.ResetTimer()
			for b.Loop() {
				h.fanoutGameProjections(r)
				for _, session := range members {
					<-session.Send
				}
			}
		})
	}
}
