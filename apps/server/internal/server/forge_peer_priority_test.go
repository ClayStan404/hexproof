// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/coder/websocket"
	"hexproof/server/internal/forgehost"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
	"hexproof/server/internal/rulesinput"
)

type peerPriorityRuntime struct {
	forge.Runtime
	gameID  string
	done    chan struct{}
	once    sync.Once
	actions atomic.Int64
}

func (f *peerPriorityRuntime) StartGame(context.Context, forge.StartGameRequest) (forge.SessionHandle, error) {
	return forge.SessionHandle{SessionID: "session", PlayerIndexes: []int{0, 1}}, nil
}
func (f *peerPriorityRuntime) Prompt(context.Context, string, int) (json.RawMessage, error) {
	count := f.actions.Load()
	input := `{"type":"chooseAction","actions":[],"autoPassEligible":true}`
	if count >= 3 {
		input = `{"type":"acknowledge"}`
	}
	return json.RawMessage(fmt.Sprintf(`{"promptId":%d,"decidingPlayerId":"player-0","input":%s}`, count+1, input)), nil
}
func (f *peerPriorityRuntime) Snapshot(_ context.Context, _ string, viewer int) (json.RawMessage, error) {
	view := forgeLifecycleSnapshot(f.gameID, viewer, -1)
	view["turn"] = f.actions.Load() + 1
	return json.Marshal(view)
}
func (f *peerPriorityRuntime) SubmitAction(context.Context, string, json.RawMessage) error {
	f.actions.Add(1)
	return nil
}
func (f *peerPriorityRuntime) GameOver(context.Context, string) (bool, error) { return false, nil }
func (f *peerPriorityRuntime) Done() <-chan struct{}                          { return f.done }
func (f *peerPriorityRuntime) Healthy() bool {
	select {
	case <-f.done:
		return false
	default:
		return true
	}
}
func (f *peerPriorityRuntime) Invalidate()  { f.once.Do(func() { close(f.done) }) }
func (f *peerPriorityRuntime) Close() error { f.Invalidate(); return nil }

func peerPriorityRelay(t *testing.T, roomID string, runtime *peerPriorityRuntime) (*forgehost.Link,
	context.Context, chan<- forgehost.PeerAction, <-chan forgehost.PeerCommit, <-chan forgehost.PeerReply) {
	t.Helper()
	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	link := forgehost.NewLink(roomID, 3*time.Second)
	actions := make(chan forgehost.PeerAction, 1)
	commits := make(chan forgehost.PeerCommit, 1)
	replies := make(chan forgehost.PeerReply, 2)
	link.OnPeerCommit = func(commit forgehost.PeerCommit) { commits <- commit }
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := websocket.Accept(w, r, nil)
		if err != nil {
			return
		}
		defer conn.CloseNow()
		conn.SetReadLimit(forgehost.MaxFrameBytes)
		_, raw, err := conn.Read(r.Context())
		var hello forgehost.Hello
		if err != nil || json.Unmarshal(raw, &hello) != nil || hello.Token != link.Token {
			return
		}
		_ = link.Serve(r.Context(), conn, hello)
	}))
	finished := make(chan error, 1)
	go func() {
		finished <- forgehost.Run(ctx, forgehost.WorkerConfig{
			ServerURL: "ws" + strings.TrimPrefix(srv.URL, "http"), RoomID: roomID, Token: link.Token, GraceSeconds: 3,
		}, func(context.Context) (forge.Runtime, error) { return runtime, nil }, nil,
			forgehost.WorkerPeer{Actions: actions, Reply: func(reply forgehost.PeerReply) { replies <- reply }})
	}()
	t.Cleanup(func() {
		cancel()
		link.Close()
		srv.Close()
		select {
		case <-finished:
		case <-time.After(3 * time.Second):
			t.Error("peer worker did not stop")
		}
	})
	for !link.Ready() {
		select {
		case <-ctx.Done():
			t.Fatal("peer relay did not connect")
		case <-time.After(time.Millisecond):
		}
	}
	return link, ctx, actions, commits, replies
}

func TestCommittedPeerPriorityWaitsForConfirmationAndRemainsIdempotent(t *testing.T) {
	for _, direct := range []bool{false, true} {
		t.Run(fmt.Sprintf("direct-delivery-%v", direct), func(t *testing.T) {
			h, r, host, _, _ := modelTestRoom(t)
			game := h.forgeGames[r.ID]
			engine := &peerPriorityRuntime{gameID: game.gameID, done: make(chan struct{})}
			link, ctx, actions, commits, replies := peerPriorityRelay(t, r.ID, engine)
			remote, err := link.NewRuntime()
			if err != nil {
				t.Fatal(err)
			}
			handle, err := remote.StartGame(ctx, forge.StartGameRequest{
				GameID: game.gameID, Variant: "Constructed", Players: make([]forge.PlayerConfig, 2),
			})
			if err != nil {
				t.Fatal(err)
			}
			game.client, game.sessionID = remote, handle.SessionID
			h.forgeGames[r.ID] = game
			bindingID := forgehost.NewID()
			link.Seat = 1
			h.playerHosts[r.ID] = link
			h.playerPeers[r.ID] = &playerPeerState{history: map[string]*playerPeerBinding{
				bindingID: {runtime: remote, authorizedRevision: 1},
			}}
			h.setPriorityPreference(r.ID, 0, priorityPreference{})
			binding := forgehost.PeerContext{BindingID: bindingID, GameID: game.gameID,
				EngineID: remote.EngineID(), PlayerIndex: 0, PublicPromptID: 91, NativePromptID: 1, Revision: 1}
			if err := link.SendPeer(forgehost.Frame{Type: "peer_context", PeerContext: &binding}); err != nil {
				t.Fatal(err)
			}
			action := forgehost.PeerAction{BindingID: bindingID, OperationID: "direct-pass",
				Request: protocol.RulesRespond{PromptID: 91, ResponseID: "$pass", PeerBinding: bindingID}}
			var commit forgehost.PeerCommit
			for {
				actions <- action
				select {
				case commit = <-commits:
					goto committed
				case denied := <-replies:
					if denied.Error != "relay" {
						t.Fatalf("unexpected pre-binding reply: %+v", denied)
					}
					select {
					case <-time.After(time.Millisecond):
					case <-ctx.Done():
						t.Fatal("peer context was not applied")
					}
				case <-ctx.Done():
					t.Fatal("direct action was not committed")
				}
			}
		committed:
			if err := remote.AdoptPeer(commit); err != nil {
				t.Fatal(err)
			}
			entry, _ := h.hub.lockRoomOperation(r.ID)
			reply := h.publishRulesDecision(r, game, host.ConnectionID, action.OperationID, action.Request, direct, true)
			entry.opMu.Unlock()
			if reply == nil || engine.actions.Load() != 1 {
				t.Fatal("hub tried to pass the unconfirmed direct position")
			}
			assertRulesSnapshotPromptPair(t, reply.Envelopes[1], reply.Envelopes[2])
			var snapshot protocol.RulesGameSnapshot
			if reply.Envelopes[1].DecodePayload(&snapshot) != nil || snapshot.Turn != 2 {
				t.Fatal("direct reply did not preserve the committed snapshot")
			}
			receipt := h.peerReceipt(r.ID, host.ConnectionID, action.OperationID, action.Request)
			if receipt == nil || receipt.publicationHash != forgehost.HashPublication(commit.Publication) {
				t.Fatal("receipt no longer identifies the original committed publication")
			}
			// Before confirmation the worker resends its same private commit.
			// The hub must confirm that receipt, rather than returning relay or
			// submitting the action again. This uses the real commit handler.
			actions <- action
			select {
			case repeated := <-commits:
				h.commitPlayerPeer(r, link, repeated)
			case <-ctx.Done():
				t.Fatal("duplicate commit was not retained")
			}
			select {
			case confirmed := <-replies:
				if confirmed.Error != "" || confirmed.OperationID != action.OperationID {
					t.Fatalf("duplicate was not confirmed: %+v", confirmed)
				}
				assertRulesSnapshotPromptPair(t, confirmed.Envelopes[1], confirmed.Envelopes[2])
			case <-ctx.Done():
				t.Fatal("duplicate confirmation was not delivered")
			}
			if engine.actions.Load() != 1 {
				t.Fatal("duplicate confirmation mutated the engine")
			}
			// After confirmation a normal response may advance, including the
			// next hub-delegated pass, without the executor's pending fence.
			raw, _ := remote.Prompt(ctx, game.sessionID, 0)
			native, err := rulesinput.Build(protocol.RulesRespond{PromptID: 2, ResponseID: "$pass"}, raw, 0)
			if err != nil || remote.SubmitAction(ctx, game.sessionID, native) != nil {
				t.Fatal("confirmed position did not accept the next normal pass")
			}
			entry, _ = h.hub.lockRoomOperation(r.ID)
			next := h.publishRulesDecision(r, game, host.ConnectionID, "normal-pass",
				protocol.RulesRespond{PromptID: 2, ResponseID: "$pass"}, false, false)
			entry.opMu.Unlock()
			if next == nil || engine.actions.Load() != 3 {
				t.Fatal("normal publication failed to resume delegated priority")
			}
		})
	}
}
