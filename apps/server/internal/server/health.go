// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"net/http"
)

// ServeHealth preserves the plain health response used by deployment probes.
// Capabilities describe supported modes, not available game slots or private
// runtime details. A relay can support player hosting without a local JVM.
func (h *Handler) ServeHealth(w http.ResponseWriter, _ *http.Request) {
	capabilities, _ := json.Marshal(struct {
		Forge         bool `json:"forge"`
		PlayerHosting bool `json:"playerHosting"`
		DirectPeer    bool `json:"directPeer"`
		HostMigration bool `json:"hostMigration"`
	}{h.forgeRulesAvailable(), h.config.AllowPlayerHosting, h.config.AllowPlayerHosting, h.config.AllowPlayerHosting})
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Hexproof-Capabilities", string(capabilities))
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok\n"))
}
