// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"encoding/json"
	"time"

	"hexproof/server/internal/forgehost"
	"hexproof/server/internal/peerlink"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

// All fields are protected by forgeMu. Consent belongs to a live authenticated
// seat connection; reconnection requires the consenting client to opt in again.
type playerPeerState struct {
	history     map[string]*playerPeerBinding
	consent     [2]string
	binding     *playerPeerBinding
	receipt     *peerReceipt
	lastAttempt time.Time
}

type playerPeerBinding struct {
	authorizedRevision uint64
	id, token, gameID  string
	connections        [2]string
	link               *forgehost.Link
	runtime            *forgehost.Runtime
	hostSeat           int
	signals            [2]int
	cancel             context.CancelFunc
}

func (h *Handler) handleForgePeerRequest(sess *Session, env protocol.Envelope) error {
	r := sess.Room()
	var request protocol.ForgePeerRequest
	if r == nil || env.DecodePayload(&request) != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, "invalid peer request")
		return nil
	}
	entry, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		return nil
	}
	defer entry.opMu.Unlock()
	entry.mu.Lock()
	seat := r.FindSeatByConnection(sess.ConnectionID)
	allowed := seat >= 0 && seat < 2 && r.HostingMode == protocol.HostingModePlayer && !r.Disbanded
	entry.mu.Unlock()
	if !allowed {
		h.sendError(sess, env.ID, protocol.ErrNotPlayer, "direct transport requires a player-hosted seat")
		return nil
	}
	h.forgeMu.Lock()
	if h.forgeClosed {
		h.forgeMu.Unlock()
		return nil
	}
	state := h.playerPeers[r.ID]
	if state == nil {
		state = &playerPeerState{}
		h.playerPeers[r.ID] = state
	}
	if request.Enabled && state.consent[seat] == sess.ConnectionID && request.Retry && time.Since(state.lastAttempt) < 5*time.Second {
		h.forgeMu.Unlock()
		h.sendPeerStatus(r, sess, env.ID)
		return nil
	}
	state.consent[seat] = ""
	if request.Enabled {
		state.consent[seat] = sess.ConnectionID
	}
	old := state.binding
	state.binding = nil
	state.lastAttempt = time.Now()
	h.forgeMu.Unlock()
	if old != nil {
		old.cancel()
		_ = old.link.SendPeer(forgehost.Frame{Type: "peer_context"})
	}
	h.refreshPeerBinding(r)
	for _, target := range h.peerMembers(r) {
		if member := h.sessionByConn(target); member != nil {
			id := ""
			if member == sess {
				id = env.ID
			}
			h.sendPeerStatus(r, member, id)
		}
	}
	return nil
}

func (h *Handler) peerMembers(r *room.Room) [2]string {
	var result [2]string
	entry := h.hub.roomEntryFor(r.ID)
	if entry == nil {
		return result
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()
	for seat := 0; seat < 2 && seat < len(r.Seats); seat++ {
		if r.Seats[seat].Occupied {
			result[seat] = r.Seats[seat].ConnectionID
		}
	}
	return result
}

func (h *Handler) sendPeerStatus(r *room.Room, sess *Session, id string) {
	members := h.peerMembers(r)
	seat := -1
	for i, connection := range members {
		if connection == sess.ConnectionID {
			seat = i
		}
	}
	if seat < 0 {
		return
	}
	status := protocol.ForgePeerStatus{RoomID: r.ID, Available: h.config.AllowPlayerHosting}
	h.forgeMu.Lock()
	if state := h.playerPeers[r.ID]; state != nil {
		if state.binding != nil {
			status.BindingID = state.binding.id
		}
		status.Enabled = state.consent[seat] == sess.ConnectionID
		status.OtherEnabled = members[1-seat] != "" && state.consent[1-seat] == members[1-seat]
	}
	h.forgeMu.Unlock()
	env, _ := protocol.NewEnvelope(protocol.TypeForgePeerStatus, status)
	env.ID = id
	h.send(sess, env)
}

// refreshPeerBinding is called at decision boundaries and periodically under
// opMu. A new native engine, room membership or game rotates the capability.
func (h *Handler) refreshPeerBinding(r *room.Room) {
	members := h.peerMembers(r)
	h.forgeMu.Lock()
	state := h.playerPeers[r.ID]
	game, exists := h.forgeGames[r.ID]
	link := h.playerHosts[r.ID]
	remote, remoteOK := game.client.(*forgehost.Runtime)
	backup := h.playerBackups[r.ID]
	migrating := backup != nil && backup.migrationID != ""
	eligible := state != nil && exists && remoteOK && link != nil && !h.forgeClosed && !migrating && link.Ready() &&
		members[0] != "" && members[1] != "" && state.consent == members
	var old *playerPeerBinding
	if state != nil && state.binding != nil && (!eligible || state.binding.runtime != remote || state.binding.connections != members) {
		old = state.binding
		state.binding = nil
	}
	if state != nil && remoteOK {
		revision, _, _ := remote.PeerPosition()
		for id, prior := range state.history {
			if prior != state.binding && (prior.runtime != remote || prior.authorizedRevision+1 < revision) {
				delete(state.history, id)
			}
		}
	}
	var created bool
	var binding *playerPeerBinding
	var bindingCtx context.Context
	if eligible {
		binding = state.binding
		if binding == nil && len(state.history) < 8 {
			var cancel context.CancelFunc
			bindingCtx, cancel = context.WithCancel(context.Background())
			binding = &playerPeerBinding{id: forgehost.NewID(), token: forgehost.NewID(), gameID: game.gameID,
				connections: members, link: link, runtime: remote, hostSeat: link.Seat, cancel: cancel}
			state.binding = binding
			if state.history == nil {
				state.history = make(map[string]*playerPeerBinding)
			}
			state.history[binding.id] = binding
			created = true
		}
	}
	h.forgeMu.Unlock()
	if old != nil {
		old.cancel()
		_ = old.link.SendPeer(forgehost.Frame{Type: "peer_context"})
	}
	if binding == nil {
		return
	}
	if created {
		// Both grants are enqueued before signaling is accepted on either seat.
		for seat, conn := range members {
			if sess := h.sessionByConn(conn); sess != nil {
				env, _ := protocol.NewEnvelope(protocol.TypeForgePeerGrant, protocol.ForgePeerGrant{
					RoomID: r.ID, GameID: game.gameID, BindingID: binding.id, Token: binding.token,
					HostSeat: link.Seat, Offerer: seat == link.Seat, STUN: h.config.PeerSTUNServers,
				})
				h.send(sess, env)
			}
		}
		go h.renewPeerContext(bindingCtx, r)
	}
	revision, nativePrompt, err := remote.PeerPosition()
	if err != nil {
		_ = link.SendPeer(forgehost.Frame{Type: "peer_context"})
		return
	}
	h.forgeMu.Lock()
	if state == h.playerPeers[r.ID] {
		binding.authorizedRevision = revision
		for id, prior := range state.history {
			if prior != binding && (prior.runtime != remote || prior.authorizedRevision+1 < revision) {
				delete(state.history, id)
			}
		}
	}
	h.forgeMu.Unlock()
	publicPrompt, err := h.publicForgePromptID(game, nativePrompt)
	if err != nil {
		return
	}
	_ = link.SendPeer(forgehost.Frame{Type: "peer_context", PeerContext: &forgehost.PeerContext{
		BindingID: binding.id, GameID: game.gameID, EngineID: remote.EngineID(), PlayerIndex: game.seatToPlayer[1-link.Seat],
		PublicPromptID: publicPrompt, NativePromptID: nativePrompt, Revision: revision,
	}})
}

func (h *Handler) renewPeerContext(ctx context.Context, r *room.Room) {
	ticker := time.NewTicker(4 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			entry, err := h.hub.lockRoomOperation(r.ID)
			if err != nil {
				return
			}
			if ctx.Err() == nil {
				h.refreshPeerBinding(r)
			}
			entry.opMu.Unlock()
		}
	}
}

func (h *Handler) handleForgePeerSignal(sess *Session, env protocol.Envelope) error {
	r := sess.Room()
	var request protocol.ForgePeerSignal
	var signal peerlink.Signal
	if r == nil || env.DecodePayload(&request) != nil || request.RoomID != r.ID || len(request.Data) > peerlink.MaxSignalBytes ||
		json.Unmarshal([]byte(request.Data), &signal) != nil || (signal.Description == nil) == (signal.Candidate == nil) {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, "invalid peer signal")
		return nil
	}
	members := h.peerMembers(r)
	h.forgeMu.Lock()
	state := h.playerPeers[r.ID]
	if state == nil || state.binding == nil || state.binding.id != request.BindingID || state.binding.connections != members {
		h.forgeMu.Unlock()
		return nil
	}
	binding := state.binding
	seat := -1
	for i, conn := range binding.connections {
		if conn == sess.ConnectionID {
			seat = i
		}
	}
	if seat < 0 || binding.signals[seat] >= 66 {
		h.forgeMu.Unlock()
		return nil
	}
	binding.signals[seat]++
	target := binding.connections[1-seat]
	h.forgeMu.Unlock()
	if other := h.sessionByConn(target); other != nil {
		out, _ := protocol.NewEnvelope(protocol.TypeForgePeerSignaled, request)
		h.send(other, out)
	}
	return nil
}

func (h *Handler) revokePlayerPeer(roomID string, forget bool) {
	h.forgeMu.Lock()
	state := h.playerPeers[roomID]
	var binding *playerPeerBinding
	if state != nil {
		binding = state.binding
		state.binding = nil
		if forget {
			delete(h.playerPeers, roomID)
		}
	}
	h.forgeMu.Unlock()
	if binding != nil {
		binding.cancel()
		_ = binding.link.SendPeer(forgehost.Frame{Type: "peer_context"})
	}
}
