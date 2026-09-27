// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"hexproof/server/internal/accounts"
	"hexproof/server/internal/cluster"
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

// ServeReadiness reports control-plane dependencies separately from liveness.
// Account probes use an empty credential: rejection confirms a reachable
// authority without creating an account or reading any player's private data.
func (h *Handler) ServeReadiness(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	type dependency struct {
		Enabled bool   `json:"enabled"`
		Ready   bool   `json:"ready"`
		Error   string `json:"error,omitempty"`
	}
	account := dependency{Enabled: h.accounts != nil, Ready: true}
	if account.Enabled {
		ctx, cancel := context.WithTimeout(r.Context(), time.Second)
		defer cancel()
		if err := h.control.readinessGate.Lock(ctx); err != nil {
			account.Ready, account.Error = false, controlErrorCategory(err)
		} else {
			if time.Since(h.control.lastProbe) >= time.Second {
				_, err := h.accounts.Do(ctx, accounts.Request{Operation: "check"})
				h.control.accountReady = err == nil || errors.Is(err, accounts.ErrInvalid)
				h.control.accountError = ""
				if !h.control.accountReady {
					h.control.accountError = controlErrorCategory(err)
				}
				h.control.lastProbe = time.Now()
			}
			account.Ready, account.Error = h.control.accountReady, h.control.accountError
			h.control.readinessGate.Unlock()
		}
	}
	var coordinator *cluster.Status
	if h.clusterAgent != nil {
		status := h.clusterAgent.Status()
		coordinator = &status
	}
	ready := account.Ready && (coordinator == nil || coordinator.Ready)
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	if !ready {
		w.WriteHeader(http.StatusServiceUnavailable)
	}
	if r.Method == http.MethodHead {
		return
	}
	_ = json.NewEncoder(w).Encode(struct {
		Ready        bool            `json:"ready"`
		Accounts     dependency      `json:"accounts"`
		Cluster      *cluster.Status `json:"cluster,omitempty"`
		AccountRPC   timingSnapshot  `json:"accountRpc"`
		AccountGate  timingSnapshot  `json:"accountGate"`
		ClusterView  timingSnapshot  `json:"clusterView"`
		SendFailures uint64          `json:"sendFailures"`
	}{ready, account, coordinator, h.control.accountRPC.snapshot(),
		h.control.accountGate.snapshot(), h.control.clusterView.snapshot(), h.control.sendFailures.Load()})
}
