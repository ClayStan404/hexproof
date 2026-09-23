// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"reflect"
	"time"

	"hexproof/server/internal/forgehost"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
)

// One explicitly consenting successor is bounded to each two-player room.
// Protected by forgeMu; long replay work never holds the room operation lock.
type playerBackup struct {
	link         *forgehost.Link
	connectionID string
	approved     bool
	migrationID  string
	cancel       context.CancelFunc
	replacement  *forgehost.Runtime
	failure      string
}

func (h *Handler) playerHostingStatus(roomID string) protocol.ForgeHostStatus {
	h.forgeMu.Lock()
	defer h.forgeMu.Unlock()
	status := protocol.ForgeHostStatus{RoomID: roomID}
	if link := h.playerHosts[roomID]; link != nil {
		status.HostSeat, status.Connected = link.Seat, link.Ready()
		status.GraceSeconds = int(link.Grace / time.Second)
	}
	if backup := h.playerBackups[roomID]; backup != nil {
		seat := backup.link.Seat
		status.BackupSeat, status.BackupConnected = &seat, backup.link.Ready()
		status.BackupApproved, status.Migrating = backup.approved, backup.migrationID != ""
		status.MigrationError = backup.failure
	}
	if game, ok := h.forgeGames[roomID]; ok {
		if remote, ok := game.client.(*forgehost.Runtime); ok {
			status.MigrationAvailable = remote.CanMigrate()
		}
	}
	return status
}

func (h *Handler) playerHostMigrating(roomID string) bool {
	h.forgeMu.Lock()
	defer h.forgeMu.Unlock()
	backup := h.playerBackups[roomID]
	return backup != nil && backup.migrationID != ""
}

func (h *Handler) refreshPlayerHostStatus(r *room.Room) {
	if r.HostingMode != protocol.HostingModePlayer {
		return
	}
	h.playerHostStateMu.Lock()
	defer h.playerHostStateMu.Unlock()
	status := h.playerHostingStatus(r.ID)
	entry := h.hub.roomEntryFor(r.ID)
	if entry == nil {
		return
	}
	entry.mu.Lock()
	same := reflect.DeepEqual(entry.room.HostStatus, &status)
	entry.mu.Unlock()
	if !same {
		h.sendPlayerHostState(r)
	}
}

func (h *Handler) handlePlayerHostMigration(sess *Session, env protocol.Envelope, action string) error {
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
	seat := r.FindSeatByConnection(sess.ConnectionID)
	allowed := h.config.AllowPlayerHosting && r.HostingMode == protocol.HostingModePlayer && !r.HasAI() && !r.Disbanded && seat >= 0
	phase := r.Phase
	operation.mu.Unlock()
	if !allowed {
		h.sendError(sess, env.ID, protocol.ErrNotHost, "hosting requires a player seat")
		return nil
	}
	defer h.refreshPlayerHostStatus(r)
	h.forgeMu.Lock()
	primary, backup := h.playerHosts[r.ID], h.playerBackups[r.ID]
	if primary == nil || h.forgeClosed {
		h.forgeMu.Unlock()
		h.sendError(sess, env.ID, protocol.ErrRulesUnavailable, "hosting is unavailable")
		return nil
	}
	busy := backup != nil && backup.migrationID != ""
	switch action {
	case "refresh":
		h.forgeMu.Unlock()
		h.sendHostingReply(sess, env.ID, r.ID)
		return nil
	case "offer":
		if seat == primary.Seat || busy || (phase != protocol.RoomPhaseWaiting && phase != protocol.RoomPhaseStarted) {
			break
		}
		link := forgehost.NewLink(r.ID, primary.Grace)
		link.Seat = seat
		link.OnPeerCommit = func(commit forgehost.PeerCommit) { h.commitPlayerPeer(r, link, commit) }
		link.OnState = func(connected bool) { h.publishPlayerHostState(r, link, connected) }
		h.playerBackups[r.ID] = &playerBackup{link: link, connectionID: sess.ConnectionID}
		h.forgeMu.Unlock()
		if backup != nil {
			backup.link.Close()
		}
		h.sendPlayerHostGrant(sess, link, env.ID)
		return nil
	case "withdraw", "revoke":
		if backup == nil || (action == "withdraw" && seat != backup.link.Seat) || (action == "revoke" && seat != primary.Seat) {
			break
		}
		if busy {
			break
		}
		delete(h.playerBackups, r.ID)
		h.forgeMu.Unlock()
		backup.link.Close()
		h.sendHostingReply(sess, env.ID, r.ID)
		return nil
	case "approve":
		if seat != primary.Seat || backup == nil || busy {
			break
		}
		backup.approved = true
		h.forgeMu.Unlock()
		h.sendHostingReply(sess, env.ID, r.ID)
		return nil
	case "migrate":
		if busy || backup == nil || !backup.approved || !backup.link.Ready() || phase != protocol.RoomPhaseStarted {
			break
		}
		// A consenting backup can request recovery after loss, but cannot take
		// an otherwise connected engine away from its current host.
		if seat != primary.Seat && primary.Ready() {
			break
		}
		h.forgeMu.Unlock()
		if !h.beginPlayerHostMigration(r) {
			h.sendError(sess, env.ID, protocol.ErrRulesActionRejected, "This position cannot be migrated")
		} else {
			h.sendHostingReply(sess, env.ID, r.ID)
		}
		return nil
	}
	h.forgeMu.Unlock()
	h.sendError(sess, env.ID, protocol.ErrRulesActionRejected, "Hosting request is not available in this state")
	return nil
}

func (h *Handler) sendHostingReply(sess *Session, id, roomID string) {
	env, _ := protocol.NewEnvelope(protocol.TypeForgeHostStatus, h.playerHostingStatus(roomID))
	env.ID = id
	h.send(sess, env)
}

// Requires opMu. The old engine remains the current one until a fully verified
// replacement is installed. During replay both direct and relay actions pause.
func (h *Handler) beginPlayerHostMigration(r *room.Room) bool {
	h.forgeMu.Lock()
	backup, primary, game := h.playerBackups[r.ID], h.playerHosts[r.ID], h.forgeGames[r.ID]
	if backup == nil || !backup.approved || !backup.link.Ready() || h.forgeClosed {
		h.forgeMu.Unlock()
		return false
	}
	if backup.migrationID != "" {
		h.forgeMu.Unlock()
		return true
	}
	remote, ok := game.client.(*forgehost.Runtime)
	backupConnectionID := backup.connectionID
	h.forgeMu.Unlock()
	if !ok {
		return false
	}
	entry := h.hub.roomEntryFor(r.ID)
	if entry == nil {
		return false
	}
	entry.mu.Lock()
	member := r.FindSeatByConnection(backupConnectionID) == backup.link.Seat && r.Phase == protocol.RoomPhaseStarted && !r.Disbanded
	entry.mu.Unlock()
	if !member {
		return false
	}
	checkpoint, err := remote.Checkpoint()
	if err != nil {
		return false
	}
	next, err := backup.link.NewRuntime()
	if err != nil {
		return false
	}
	ctx, cancel := context.WithTimeout(context.Background(), forgehost.ReplayTimeout)
	h.forgeMu.Lock()
	if h.forgeClosed || h.playerBackups[r.ID] != backup {
		h.forgeMu.Unlock()
		cancel()
		next.Invalidate()
		return false
	}
	migrationID := forgehost.NewID()
	backup.migrationID, backup.cancel, backup.failure, backup.replacement = migrationID, cancel, "", next
	h.forgeClients[next] = struct{}{}
	h.forgeMu.Unlock()
	h.revokePlayerPeer(r.ID, false)
	h.refreshPlayerHostStatus(r)
	go func() {
		defer cancel()
		_, replayErr := next.RestoreGame(ctx, checkpoint)
		h.finishPlayerHostMigration(r, game, primary, backup, migrationID, next, replayErr)
	}()
	return true
}

func (h *Handler) finishPlayerHostMigration(r *room.Room, game forgeRoomGame, primary *forgehost.Link, backup *playerBackup, migrationID string, next *forgehost.Runtime, replayErr error) {
	operation, err := h.hub.lockRoomOperation(r.ID)
	if err != nil {
		h.forgeMu.Lock()
		delete(h.forgeClients, next)
		h.forgeMu.Unlock()
		next.Invalidate()
		return
	}
	defer operation.opMu.Unlock()
	h.playerHostStateMu.Lock()
	h.forgeMu.Lock()
	current, ok := h.forgeGames[r.ID]
	valid := !h.forgeClosed && h.playerBackups[r.ID] == backup && backup.migrationID == migrationID && h.playerHosts[r.ID] == primary && ok && current.client == game.client
	delete(h.forgeClients, next)
	if !valid {
		h.forgeMu.Unlock()
		h.playerHostStateMu.Unlock()
		next.Invalidate()
		return
	}
	backup.migrationID, backup.cancel, backup.replacement = "", nil, nil
	if replayErr != nil || !next.Healthy() {
		backup.failure = "verification_failed"
		h.forgeMu.Unlock()
		h.playerHostStateMu.Unlock()
		next.Invalidate()
		if !game.client.Healthy() {
			h.terminateForgeGame(r, game)
		}
		h.refreshPlayerHostStatus(r)
		return
	}
	game.client = next
	// Preserve the verified logical game/seat map; rotate public prompt IDs so
	// queued replies from before handover cannot answer the restored decision.
	game.promptState = &forgePromptState{}
	h.forgeGames[r.ID] = game
	h.playerHosts[r.ID] = backup.link
	delete(h.playerBackups, r.ID)
	h.forgeClients[next] = struct{}{}
	h.forgeMu.Unlock()
	h.playerHostStateMu.Unlock()
	primary.Close()
	go h.watchForgeRuntime(next)
	h.refreshPlayerHostStatus(r)
	projections, projectionErr := h.rulesProjections(r)
	prompts, promptErr := h.rulesPrompts(r)
	if projectionErr != nil || promptErr != nil {
		h.failForgeGame(r)
		return
	}
	h.sendRulesProjections(projections)
	h.sendRulesPrompts(prompts)
}

// The caller already owns the room operation lock. Clearing the migration ID
// also fences a late replay result from a restarted or explicitly closed game.
func (h *Handler) cancelPlayerHostMigration(roomID string) {
	h.forgeMu.Lock()
	backup := h.playerBackups[roomID]
	var cancel context.CancelFunc
	var replacement *forgehost.Runtime
	if backup != nil {
		cancel, replacement = backup.cancel, backup.replacement
		backup.migrationID, backup.cancel, backup.replacement = "", nil, nil
	}
	h.forgeMu.Unlock()
	if cancel != nil {
		cancel()
	}
	if replacement != nil {
		replacement.Invalidate()
	}
}
