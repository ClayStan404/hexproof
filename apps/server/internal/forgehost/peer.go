// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forgehost

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
	"hexproof/server/internal/rulesinput"
)

// PeerContext is a short-lived hub authorization for one room, engine, seat
// and decision. It travels only over the authenticated engine connection.
type PeerContext struct {
	BindingID      string `json:"bindingId"`
	GameID         string `json:"gameId"`
	EngineID       string `json:"engineId"`
	PlayerIndex    int    `json:"playerIndex"`
	PublicPromptID int64  `json:"publicPromptId"`
	NativePromptID int64  `json:"nativePromptId"`
	Revision       uint64 `json:"revision"`
}

type PeerAction struct {
	BindingID   string                `json:"bindingId"`
	OperationID string                `json:"operationId"`
	Request     protocol.RulesRespond `json:"request"`
}

// PeerCommit contains private publications. Only the hub can redact them and
// confirm a decision; the helper never sends this object over the peer channel.
type PeerCommit struct {
	PeerAction
	EngineID         string          `json:"engineId"`
	PreviousRevision uint64          `json:"previousRevision"`
	Action           json.RawMessage `json:"action"`
	Publication      *Publication    `json:"publication"`
}

type PeerReply struct {
	BindingID   string              `json:"bindingId"`
	OperationID string              `json:"operationId"`
	Envelopes   []protocol.Envelope `json:"envelopes,omitempty"`
	Error       string              `json:"error,omitempty"`
}

type peerPending struct {
	commit    PeerCommit
	confirmed bool
	reply     *PeerReply
}

func (e *Executor) SetPeerContext(value *PeerContext) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.peerContext = value
	e.peerExpires = time.Now().Add(12 * time.Second)
}

func (e *Executor) PeerDisconnected() { e.SetPeerContext(nil) }

// ExecutePeer returns a private commit for the hub, never a speculative viewer
// response. e.mu is released before the worker waits for hub confirmation.
func (e *Executor) ExecutePeer(ctx context.Context, action PeerAction) (*PeerCommit, *PeerReply) {
	e.mu.Lock()
	defer e.mu.Unlock()
	denied := &PeerReply{BindingID: action.BindingID, OperationID: action.OperationID, Error: "relay"}
	if len(action.BindingID) != 64 || action.OperationID == "" || len(action.OperationID) > 128 || action.Request.PeerBinding != action.BindingID || !rulesinput.Valid(action.Request) {
		return nil, denied
	}
	if pending := e.peerPending; pending != nil && pending.commit.BindingID == action.BindingID && pending.commit.OperationID == action.OperationID {
		before, _ := json.Marshal(pending.commit.Request)
		after, _ := json.Marshal(action.Request)
		if !bytes.Equal(before, after) {
			return nil, denied
		}
		if pending.reply != nil {
			return nil, pending.reply
		}
		return &pending.commit, nil
	}
	binding := e.peerContext
	e.stateMu.Lock()
	runtime, engineID := e.runtime, e.engineID
	e.stateMu.Unlock()
	if binding == nil || time.Now().After(e.peerExpires) || binding.BindingID != action.BindingID ||
		binding.EngineID != engineID || binding.Revision != e.revision || binding.PublicPromptID != action.Request.PromptID ||
		runtime == nil || !runtime.Healthy() || (e.peerPending != nil && !e.peerPending.confirmed) {
		return nil, denied
	}
	raw, err := runtime.Prompt(ctx, e.handle.SessionID, binding.PlayerIndex)
	view, parseErr := forge.NormalizePrompt(raw)
	if err != nil || parseErr != nil || view.PromptID != binding.NativePromptID {
		return nil, denied
	}
	native, err := rulesinput.Build(action.Request, raw, binding.PlayerIndex)
	if err != nil {
		return nil, denied
	}
	previous := e.revision
	response := e.execute(ctx, Request{EngineID: engineID, Command: "action", Action: native}, Response{})
	if response.Error != "" || response.Publication == nil {
		return nil, denied
	}
	commit := PeerCommit{PeerAction: action, EngineID: engineID, PreviousRevision: previous, Action: native, Publication: response.Publication}
	e.peerPending = &peerPending{commit: commit}
	return &commit, nil
}

func (e *Executor) ConfirmPeer(reply *PeerReply) bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	pending := e.peerPending
	if reply == nil || pending == nil || reply.BindingID != pending.commit.BindingID || reply.OperationID != pending.commit.OperationID {
		return false
	}
	pending.confirmed = reply.Error == ""
	pending.reply = reply
	return true
}

// Called under e.mu on the ordinary relay path. A fallback of the same
// operation consumes the already computed publication exactly once.
func (e *Executor) peerRelay(req Request) (*Publication, bool) {
	p := e.peerPending
	if p == nil {
		return nil, false
	}
	if req.PeerBinding == p.commit.BindingID && req.OperationID == p.commit.OperationID && bytes.Equal(req.Action, p.commit.Action) {
		p.confirmed = true
		return p.commit.Publication, true
	}
	return nil, !p.confirmed
}

func (r *Runtime) EngineID() string { return r.engineID }

func (r *Runtime) PeerPosition() (uint64, int64, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.publication == nil || !r.Healthy() || r.publication.GameOver {
		return 0, 0, ErrUnavailable
	}
	view, err := forge.NormalizePrompt(r.publication.Prompt)
	return r.publication.Revision, view.PromptID, err
}

func (r *Runtime) SubmitPlayerAction(ctx context.Context, sessionID string, action json.RawMessage, binding, operationID string) error {
	if _, err := r.current(sessionID); err != nil {
		return err
	}
	_, err := r.mutate(ctx, Request{Command: "action", Action: action, PeerBinding: binding, OperationID: operationID})
	return err
}

// AdoptPeer is called under the room operation lock after checking the current
// public prompt, actor, binding and canonical response. It also journals once.
func (r *Runtime) AdoptPeer(commit PeerCommit) error {
	if !r.Healthy() || commit.EngineID != r.engineID || validatePublication(commit.Publication) != nil {
		return ErrUnavailable
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	p := commit.Publication
	if r.publication == nil || p.Handle.SessionID != r.publication.Handle.SessionID || p.Revision != commit.PreviousRevision+1 || r.publication.Revision != commit.PreviousRevision {
		return ErrUnavailable
	}
	r.publication = p
	r.recordCheckpoint(Request{Command: "action", Action: commit.Action}, p)
	return nil
}

// HashPublication also works when a position is not replay-migratable.
func HashPublication(p *Publication) [32]byte {
	if p == nil {
		return sha256.Sum256([]byte("null"))
	}
	position := *p
	position.Replay = nil
	raw, _ := json.Marshal(&position)
	return sha256.Sum256(raw)
}
func (r *Runtime) PublicationHash() [32]byte {
	r.mu.Lock()
	defer r.mu.Unlock()
	return HashPublication(r.publication)
}
