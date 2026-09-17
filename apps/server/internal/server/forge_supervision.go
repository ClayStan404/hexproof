// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"log"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
)

const forgeRestartCooldown = time.Second

// watchForgeRuntime responds to actual child exit, including an idle crash.
// There is no automatic restart loop: only a new game can launch a replacement.
func (h *Handler) watchForgeRuntime(client forge.Runtime) {
	<-client.Done()
	h.forgeMu.Lock()
	delete(h.forgeClients, client)
	if h.forgeClosed {
		h.forgeMu.Unlock()
		return
	}
	affected := make(map[string]forgeRoomGame)
	for roomID, game := range h.forgeGames {
		if game.client == client {
			affected[roomID] = game
		}
	}
	h.forgeMu.Unlock()
	for roomID, game := range affected {
		operation, err := h.hub.lockRoomOperation(roomID)
		if err != nil {
			continue
		}
		current, exists := h.forgeGame(roomID)
		if exists && current.client == game.client && !h.beginPlayerHostMigration(operation.room) {
			h.terminateForgeGame(operation.room, game)
		}
		operation.opMu.Unlock()
	}
}

// failForgeGame is called within the room operation, never reacquires opMu,
// and fails closed without logging the upstream payload or disconnecting the
// whole room. Invalid projections cannot be trusted on this runtime again.
func (h *Handler) failForgeGame(r *room.Room) {
	game, ok := h.forgeGame(r.ID)
	if !ok {
		return
	}
	game.client.Invalidate()
	h.terminateForgeGame(r, game)
}

// terminateForgeGame requires this room's opMu. Revalidate the runtime and
// game identity after acquiring it: an old watcher must not reset a new match.
func (h *Handler) terminateForgeGame(r *room.Room, expected forgeRoomGame) {
	if r == nil || r.RulesMode != protocol.RulesModeForge {
		return
	}
	h.forgeMu.Lock()
	current, ok := h.forgeGames[r.ID]
	if h.forgeClosed || !ok || current.client != expected.client ||
		current.sessionID != expected.sessionID || current.gameID != expected.gameID {
		h.forgeMu.Unlock()
		return
	}
	delete(h.forgeGames, r.ID)
	h.forgeMu.Unlock()
	reset := false
	result, err := h.hub.reduceRoom(r, func(locked *room.Room) (room.Result, error) {
		if locked.Phase != protocol.RoomPhaseStarted || locked.Game != nil {
			return room.Result{}, nil
		}
		reset = true
		return locked.ResetRulesStartFailure(), nil
	})
	if err != nil {
		// The public failure reason must never include engine diagnostics.
		log.Print("Forge game termination could not publish the waiting room")
		return
	}
	if !reset {
		return
	}
	code := protocol.ErrRulesUnavailable
	if r.HostingMode == protocol.HostingModePlayer {
		code = protocol.ErrPlayerHostLost
	}
	for _, member := range h.sessionsForRoomPointer(r) {
		h.sendError(member, "", code,
			"Forge stopped; this game was aborted and the room is waiting for players to ready again")
	}
	h.fanout(r, result.Broadcast)
}
