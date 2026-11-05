// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

// Close stops tournament cleanup timers and reaps every owned Forge process,
// including processes reserved by a startGame call. HTTP shutdown closes
// WebSocket sessions separately.
func (h *Handler) Close() error {
	h.closeOnce.Do(func() {
		h.cancelAllActionClocks()
		if h.forgeCrashes != nil {
			h.forgeCrashes.close()
		}
		if h.clusterAgent != nil {
			h.clusterAgent.Close()
		}
		if h.accountStore != nil {
			_ = h.accountStore.Close()
		}
		h.closeModelWorkers()
		h.tournaments.close()
		h.forge.mu.Lock()
		shutdown := h.forge.beginCloseLocked()
		links := h.playerHosts
		h.playerHosts = nil
		peers := h.playerPeers
		h.playerPeers = nil
		backups := h.playerBackups
		h.playerBackups = nil
		h.forgeGames = make(map[string]forgeRoomGame)
		h.forge.mu.Unlock()
		for _, peer := range peers {
			if peer.binding != nil {
				peer.binding.cancel()
			}
		}
		for _, link := range links {
			link.Close()
		}
		for _, backup := range backups {
			if backup.cancel != nil {
				backup.cancel()
			}
			backup.link.Close()
		}
		h.closeErr = shutdown.wait()
	})
	return h.closeErr
}
