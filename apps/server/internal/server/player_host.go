// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"net/http"
	"time"

	"github.com/coder/websocket"
	"hexproof/server/internal/forgehost"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
)

func (h *Handler) handleForgeHostRequest(sess *Session, env protocol.Envelope) error {
	var request protocol.ForgeHostRequest
	if env.DecodePayload(&request) != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, "invalid hosting request")
		return nil
	}
	if request.Action != "" && request.Action != "prepare" {
		return h.handlePlayerHostMigration(sess, env, request.Action)
	}
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	operation, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	defer operation.opMu.Unlock()
	operation.mu.Lock()
	h.forgeMu.Lock()
	link := h.playerHosts[r.ID]
	hostSeat := 0
	if link != nil {
		hostSeat = link.Seat
	}
	h.forgeMu.Unlock()
	allowed := h.config.AllowPlayerHosting && r.HostingMode == "player" &&
		r.FindSeatByConnection(sess.ConnectionID) == hostSeat && r.Phase == protocol.RoomPhaseWaiting && !r.Disbanded
	operation.mu.Unlock()
	if !allowed {
		h.sendError(sess, env.ID, protocol.ErrNotHost, "Only the creator may prepare hosting while waiting")
		return nil
	}
	h.revokePlayerHost(r.ID)
	if replacement := h.allocatePlayerHost(r, hostSeat); replacement != nil {
		h.sendPlayerHostGrant(sess, replacement, env.ID)
	} else {
		h.sendError(sess, env.ID, protocol.ErrServerLimit, "player hosting capacity is full")
	}
	return nil
}

func (h *Handler) allocatePlayerHost(r *room.Room, seat ...int) *forgehost.Link {
	h.playerHostStateMu.Lock()
	defer h.playerHostStateMu.Unlock()
	h.forgeMu.Lock()
	defer h.forgeMu.Unlock()
	if h.forgeClosed || len(h.playerHosts) >= h.config.MaxPlayerHostedGames {
		return nil
	}
	grace := min(h.config.ReconnectWindow, 10*time.Minute)
	grace = max(grace, time.Second)
	link := forgehost.NewLink(r.ID, grace)
	if len(seat) > 0 {
		link.Seat = seat[0]
	}
	link.OnPeerCommit = func(commit forgehost.PeerCommit) { h.commitPlayerPeer(r, link, commit) }
	link.OnState = func(connected bool) { h.publishPlayerHostState(r, link, connected) }
	h.playerHosts[r.ID] = link
	return link
}

func (h *Handler) grantPlayerHost(sess *Session, r *room.Room, requestID string) {
	link := h.allocatePlayerHost(r)
	if link == nil {
		h.sendError(sess, requestID, protocol.ErrServerLimit, "player hosting capacity is full")
		return
	}
	h.sendPlayerHostGrant(sess, link, requestID)
}

func (h *Handler) sendPlayerHostGrant(sess *Session, link *forgehost.Link, requestID string) {
	h.forgeMu.Lock()
	backup := h.playerBackups[link.RoomID]
	standby := backup != nil && backup.link == link
	h.forgeMu.Unlock()
	grant, _ := protocol.NewEnvelope(protocol.TypeForgeHostGrant, protocol.ForgeHostGrant{
		RoomID: link.RoomID, Token: link.Token, RuntimeID: forgehost.RuntimeID,
		GraceSeconds: int(link.Grace / time.Second),
		Standby:      standby,
	})
	grant.ID = requestID
	h.send(sess, grant)
}

func (h *Handler) revokePlayerHost(roomID string) {
	h.revokePlayerPeer(roomID, true)
	h.playerHostStateMu.Lock()
	defer h.playerHostStateMu.Unlock()
	h.forgeMu.Lock()
	link := h.playerHosts[roomID]
	backup := h.playerBackups[roomID]
	delete(h.playerHosts, roomID)
	delete(h.playerBackups, roomID)
	h.forgeMu.Unlock()
	if backup != nil {
		if backup.cancel != nil {
			backup.cancel()
		}
		backup.link.Close()
	}
	if link != nil {
		link.Close()
	}
	if entry := h.hub.roomEntryFor(roomID); entry != nil {
		h.sendPlayerHostState(entry.room)
	}
}

func (h *Handler) publishPlayerHostState(r *room.Room, link *forgehost.Link, connected bool) {
	// Serialize binding replacement with state publication. A callback from the
	// previous helper must not overwrite the new binding's connected state.
	h.playerHostStateMu.Lock()
	defer h.playerHostStateMu.Unlock()
	h.forgeMu.Lock()
	backup := h.playerBackups[r.ID]
	current := (h.playerHosts[r.ID] == link || backup != nil && backup.link == link) && !h.forgeClosed
	h.forgeMu.Unlock()
	if current {
		h.sendPlayerHostState(r)
	}
}

func (h *Handler) sendPlayerHostState(r *room.Room) {
	status := h.playerHostingStatus(r.ID)
	_, err := h.hub.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		locked.HostConnected = status.Connected
		locked.HostStatus = &status
		return room.Result{}, nil
	})
	if err != nil {
		return
	}
	env, _ := protocol.NewEnvelope(protocol.TypeForgeHostStatus, status)
	h.fanout(r, []protocol.Envelope{env})
}

func (h *Handler) playerHostPaused(r *room.Room) bool {
	if r.HostingMode != "player" {
		return false
	}
	h.forgeMu.Lock()
	link := h.playerHosts[r.ID]
	backup := h.playerBackups[r.ID]
	migrating := backup != nil && backup.migrationID != ""
	h.forgeMu.Unlock()
	return migrating || link == nil || !link.Ready()
}

func (h *Handler) servePlayerHost(w http.ResponseWriter, request *http.Request) {
	if !h.config.AllowPlayerHosting {
		http.Error(w, "player hosting disabled", http.StatusForbidden)
		return
	}
	conn, err := websocket.Accept(w, request, &websocket.AcceptOptions{CompressionMode: websocket.CompressionDisabled})
	if err != nil {
		return
	}
	defer conn.CloseNow()
	conn.SetReadLimit(4096)
	helloCtx, cancel := context.WithTimeout(request.Context(), h.config.HelloTimeout)
	_, data, err := conn.Read(helloCtx)
	cancel()
	var hello forgehost.Hello
	if err != nil || json.Unmarshal(data, &hello) != nil || hello.Version != forgehost.Version ||
		hello.RuntimeID != forgehost.RuntimeID || len(hello.HelperID) != 64 || len(hello.Token) != 64 {
		return
	}
	h.forgeMu.Lock()
	link := h.playerHosts[hello.RoomID]
	if backup := h.playerBackups[hello.RoomID]; backup != nil && subtle.ConstantTimeCompare([]byte(backup.link.Token), []byte(hello.Token)) == 1 {
		link = backup.link
	}
	h.forgeMu.Unlock()
	if link == nil || subtle.ConstantTimeCompare([]byte(link.Token), []byte(hello.Token)) != 1 {
		return
	}
	conn.SetReadLimit(forgehost.MaxFrameBytes)
	ctx, stop := context.WithCancel(request.Context())
	defer stop()
	go websocketHeartbeat(ctx, conn)
	_ = link.Serve(ctx, conn, hello)
}

func (h *Handler) startRoomForgeRuntime(ctx context.Context, r *room.Room) (forge.Runtime, error) {
	if r.HostingMode != "player" {
		return h.startForgeRuntime(ctx, r.ID)
	}
	h.forgeMu.Lock()
	defer h.forgeMu.Unlock()
	link := h.playerHosts[r.ID]
	if h.forgeClosed || link == nil || !link.Ready() {
		return nil, forgehost.ErrUnavailable
	}
	engine, err := link.NewRuntime()
	if err != nil {
		return nil, err
	}
	h.forgeClients[engine] = struct{}{}
	go h.watchForgeRuntime(engine)
	return engine, nil
}

func runtimeTimeout(runtime forge.Runtime, local time.Duration) time.Duration {
	if remote, ok := runtime.(interface{ RequestTimeout() time.Duration }); ok {
		return remote.RequestTimeout()
	}
	return local
}
