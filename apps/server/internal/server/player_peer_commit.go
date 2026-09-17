// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"

	"hexproof/server/internal/forgehost"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
	"hexproof/server/internal/rulesinput"
)

// One receipt per binding is enough: each normal client can have only one
// pending decision. The receipt fences a late fallback after the prompt changes.
type peerReceipt struct {
	engineID        string
	connectionID    string
	requestHash     [32]byte
	publicationHash [32]byte
	reply           *forgehost.PeerReply
}

func requestHash(request protocol.RulesRespond) [32]byte {
	raw, _ := json.Marshal(request)
	return sha256.Sum256(raw)
}

func (h *Handler) savePeerReceipt(roomID string, game forgeRoomGame, connection string, request protocol.RulesRespond, reply *forgehost.PeerReply) {
	if request.PeerBinding == "" {
		return
	}
	remote, ok := game.client.(*forgehost.Runtime)
	if !ok {
		return
	}
	publicationHash := remote.PublicationHash()
	h.forgeMu.Lock()
	defer h.forgeMu.Unlock()
	state := h.playerPeers[roomID]
	if state == nil || state.history[request.PeerBinding] == nil {
		return
	}
	state.receipt = &peerReceipt{engineID: remote.EngineID(), connectionID: connection, requestHash: requestHash(request), publicationHash: publicationHash, reply: reply}
}

func (h *Handler) peerReceipt(roomID, connection, operationID string, request protocol.RulesRespond) *peerReceipt {
	h.forgeMu.Lock()
	defer h.forgeMu.Unlock()
	state := h.playerPeers[roomID]
	if state == nil || state.receipt == nil {
		return nil
	}
	receipt := state.receipt
	if receipt.connectionID != connection || receipt.reply.OperationID != operationID || receipt.reply.BindingID != request.PeerBinding || receipt.requestHash != requestHash(request) {
		return nil
	}
	return receipt
}

func (h *Handler) replayPeerReceipt(r *room.Room, sess *Session, operationID string, request protocol.RulesRespond) bool {
	if request.PeerBinding == "" {
		return false
	}
	receipt := h.peerReceipt(r.ID, sess.ConnectionID, operationID, request)
	if receipt == nil {
		return false
	}
	// Do not replay an old position after the other seat has already acted.
	// Current projections go over the reliable hub path before releasing input.
	if _, active := h.forgeGame(r.ID); active {
		if projections, err := h.rulesProjections(r); err == nil {
			if snapshot, exists := projections[sess.ConnectionID]; exists {
				h.send(sess, snapshot)
			}
		}
		if prompts, err := h.rulesPrompts(r); err == nil {
			if prompt, exists := prompts[sess.ConnectionID]; exists {
				h.send(sess, prompt)
			}
		}
	}
	h.send(sess, receipt.reply.Envelopes[0])
	return true
}

func (h *Handler) commitPlayerPeer(r *room.Room, link *forgehost.Link, commit forgehost.PeerCommit) {
	reply := &forgehost.PeerReply{BindingID: commit.BindingID, OperationID: commit.OperationID, Error: "relay"}
	defer func() { _ = link.SendPeer(forgehost.Frame{Type: "peer_reply", PeerReply: reply}) }()
	entry, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		return
	}
	defer entry.opMu.Unlock()
	defer h.refreshPlayerHostStatus(r)
	members := h.peerMembers(r)
	h.forgeMu.Lock()
	state := h.playerPeers[r.ID]
	primary := h.playerHosts[r.ID]
	var binding *playerPeerBinding
	if state != nil {
		binding = state.history[commit.BindingID]
	}
	h.forgeMu.Unlock()
	if primary != link || link.Seat < 0 || link.Seat > 1 || commit.OperationID == "" || len(commit.OperationID) > 128 {
		return
	}
	connection := members[1-link.Seat]
	sess := h.sessionByConn(connection)
	if sess != nil && sess.Room() != r {
		return
	}
	if receipt := h.peerReceipt(r.ID, connection, commit.OperationID, commit.Request); receipt != nil {
		if receipt.engineID == commit.EngineID && receipt.publicationHash == forgehost.HashPublication(commit.Publication) {
			reply = receipt.reply
		}
		return
	}
	if binding == nil || binding.link != link || binding.authorizedRevision != commit.PreviousRevision ||
		commit.Request.PeerBinding != binding.id || commit.EngineID != binding.runtime.EngineID() || !rulesinput.Valid(commit.Request) {
		return
	}
	if h.playerHostPaused(r) {
		return
	}
	game, ok := h.forgeGame(r.ID)
	if !ok || game.client != binding.runtime || game.gameID != binding.gameID {
		return
	}
	seat, err := h.hub.RulesActorSeat(r, connection)
	if err != nil || seat != 1-binding.hostSeat {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), forgePromptTimeout)
	defer cancel()
	raw, err := game.client.Prompt(ctx, game.sessionID, game.seatToPlayer[seat])
	view, parseErr := forge.NormalizePrompt(raw)
	if err != nil || parseErr != nil || !game.promptState.matches(commit.Request.PromptID, view.PromptID) {
		return
	}
	native, err := rulesinput.Build(commit.Request, raw, game.seatToPlayer[seat])
	if err != nil || !bytes.Equal(native, commit.Action) {
		return
	}
	if binding.runtime.AdoptPeer(commit) != nil {
		return
	}
	h.forgeMu.Lock()
	direct := state.binding == binding && binding.connections == members && sess != nil
	h.forgeMu.Unlock()
	if result := h.publishRulesDecision(r, game, connection, commit.OperationID, commit.Request, direct); result != nil {
		reply = result
	}
}
