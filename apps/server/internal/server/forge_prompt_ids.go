// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"errors"
	"sync"
)

// Forge restarts its own prompt sequence in every session. Public ids instead
// belong to this hub lifetime, so an old queued response cannot answer a new
// game's unrelated prompt after sideboarding, restart, or process replacement.
type forgePromptState struct {
	mu                 sync.Mutex
	engineID, publicID int64
}

func (h *Handler) publicForgePromptID(game forgeRoomGame, engineID int64) (int64, error) {
	if engineID <= 0 || game.promptState == nil {
		return 0, errors.New("invalid Forge prompt state")
	}
	state := game.promptState
	state.mu.Lock()
	defer state.mu.Unlock()
	if state.engineID == engineID && state.publicID > 0 {
		return state.publicID, nil
	}
	id := h.forgePromptSequence.Add(1)
	if id <= 0 || id > 1<<53-1 {
		return 0, errors.New("Forge prompt identifiers exhausted")
	}
	state.engineID, state.publicID = engineID, id
	return id, nil
}

func (state *forgePromptState) matches(publicID, engineID int64) bool {
	if state == nil || publicID <= 0 || engineID <= 0 {
		return false
	}
	state.mu.Lock()
	defer state.mu.Unlock()
	return publicID == state.publicID && engineID == state.engineID
}
