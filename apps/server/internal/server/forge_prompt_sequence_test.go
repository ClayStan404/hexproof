// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"testing"

	"hexproof/server/internal/forgehost"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

func assertRulesSnapshotPromptPair(t *testing.T, snapshot, prompt protocol.Envelope) {
	t.Helper()
	if snapshot.Type != protocol.TypeRulesSnapshot || prompt.Type != protocol.TypeRulesPrompt ||
		snapshot.SeqPtr == nil || prompt.SeqPtr == nil || snapshot.SeqValue() <= 0 ||
		snapshot.SeqValue() != prompt.SeqValue() {
		t.Fatalf("rules publication has inconsistent sequence: snapshot=%s/%d prompt=%s/%d",
			snapshot.Type, snapshot.SeqValue(), prompt.Type, prompt.SeqValue())
	}
}

func TestRulesPromptSequenceOnResumeAndReceiptReplay(t *testing.T) {
	for _, resume := range []bool{false, true} {
		for _, pending := range []bool{false, true} {
			name := "receipt"
			if resume {
				name = "resume"
			}
			if pending {
				name += "/pending"
			} else {
				name += "/clear"
			}
			t.Run(name, func(t *testing.T) {
				h, r, host, _, runtime := modelTestRoom(t)
				if pending {
					runtime.submitted = 1 // The current decision now belongs to the human.
				}
				spectator := &Session{ConnectionID: "observer", Send: make(chan []byte, 16)}
				spectator.setRoom(r)
				h.registerSession(spectator)
				r.Spectators = append(r.Spectators, room.Spectator{ConnectionID: spectator.ConnectionID, DisplayName: "Observer"})
				for len(host.Send) > 0 {
					<-host.Send
				}
				entry, err := h.hub.lockRoomOperation(r.ID)
				if err != nil {
					t.Fatal(err)
				}
				defer entry.opMu.Unlock()
				before := runtime.submitted
				if resume {
					h.sendResumedRoomState(host, r, nil)
				} else {
					request := protocol.RulesRespond{PeerBinding: "binding", PromptID: 1, ResponseID: "$pass"}
					ack, _ := protocol.NewEnvelope(protocol.TypeRulesResponded, protocol.RulesResponded{RoomID: r.ID, PromptID: 1})
					h.playerPeers[r.ID] = &playerPeerState{receipt: &peerReceipt{
						connectionID: host.ConnectionID, requestHash: requestHash(request),
						reply: &forgehost.PeerReply{BindingID: "binding", OperationID: "prior-decision", Envelopes: []protocol.Envelope{ack}},
					}}
					if !h.replayPeerReceipt(r, host, "prior-decision", request) {
						t.Fatal("matching receipt was not replayed")
					}
				}
				if runtime.submitted != before {
					t.Fatal("read-only publication advanced the engine")
				}
				var snapshot, prompt protocol.Envelope
				for len(host.Send) > 0 {
					env, err := protocol.ParseEnvelope(<-host.Send)
					if err != nil {
						t.Fatal(err)
					}
					switch env.Type {
					case protocol.TypeRulesSnapshot:
						snapshot = env
					case protocol.TypeRulesPrompt:
						prompt = env
					}
				}
				assertRulesSnapshotPromptPair(t, snapshot, prompt)
				var decision protocol.RulesPrompt
				if prompt.DecodePayload(&decision) != nil || decision.Pending != pending || (!pending && decision.Title != "") {
					t.Fatalf("prompt ownership changed: %+v", decision)
				}
				for len(spectator.Send) > 0 {
					env, err := protocol.ParseEnvelope(<-spectator.Send)
					if err != nil || env.Type == protocol.TypeRulesPrompt {
						t.Fatal("spectator received a private prompt")
					}
				}
			})
		}
	}
}
