// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"fmt"
	"net/http"
	"sync/atomic"

	"hexproof/server/internal/buildinfo"
	"hexproof/server/internal/cluster"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/tournament"
)

func (h *Handler) configureCluster() error {
	if h.config.Cluster == nil {
		return nil
	}
	c := *h.config.Cluster
	c.Nodes = append([]cluster.Node(nil), c.Nodes...)
	if err := c.Validate(); err != nil {
		return err
	}
	if h.accounts == nil || c.Realm != h.accountRealm() {
		return fmt.Errorf("cluster nodes must share the configured official account realm")
	}
	h.config.Cluster = &c
	var service cluster.Service
	if c.Coordinator == "" {
		coordinator, err := cluster.New(c)
		if err != nil {
			return err
		}
		service = coordinator
		h.clusterAPI = cluster.HTTPHandler(service, c)
	} else {
		remote, err := cluster.NewRemote(c)
		if err != nil {
			return err
		}
		service = remote
	}
	h.clusterAgent = cluster.Start(service, c.NodeID, h.clusterReport)
	return nil
}

func (h *Handler) ServeClusterCoordinator(w http.ResponseWriter, r *http.Request) {
	if h.clusterAPI == nil {
		http.NotFound(w, r)
		return
	}
	h.clusterAPI.ServeHTTP(w, r)
}

func (h *Handler) clusterNode() string {
	if h.config.Cluster == nil {
		return ""
	}
	return h.config.Cluster.NodeID
}

// Only public listings and account ownership references cross this boundary.
// Decks, packs, credentials, actions and authoritative game state stay local.
func (h *Handler) clusterReport() cluster.Report {
	r := cluster.Report{
		Version: buildinfo.Version, Rooms: h.listRooms(nil), Events: h.tournaments.list(),
		Resources: map[string][]protocol.AccountResource{},
		MaxRooms:  h.config.MaxRooms, MaxEvents: h.config.MaxTournaments,
		Connections: atomic.LoadInt64(&h.activeConnections), MaxConnections: h.config.MaxConnections,
		Forge: h.forgeRulesAvailable(), ForgeAI: h.forgeAIAvailable(),
		PlayerHosting: h.config.AllowPlayerHosting, MaxForge: h.config.MaxForgeGames,
	}
	r.MemoryMB, r.Load = cluster.HostMetrics()
	h.hub.mu.Lock()
	entries := make([]*roomEntry, 0, len(h.hub.rooms))
	for _, entry := range h.hub.rooms {
		entries = append(entries, entry)
	}
	r.RoomCount = len(h.hub.rooms) + len(h.hub.reservedRoomIDs)
	h.hub.mu.Unlock()
	for _, entry := range entries {
		entry.mu.Lock()
		room := entry.room
		if !room.Disbanded {
			if room.RulesMode == protocol.RulesModeForge && room.HostingMode != "player" && entry.tournamentID == "" {
				r.ForgeDemand++
			}
			for _, seat := range room.Seats {
				if seat.AccountID != "" && seat.ConnectionID != "" {
					r.Resources[seat.AccountID] = append(r.Resources[seat.AccountID], protocol.AccountResource{Kind: "room", ID: room.ID, Name: room.Name, Role: "player"})
				}
			}
		}
		entry.mu.Unlock()
	}
	events := h.tournaments.snapshot()
	r.EventCount = len(events)
	for _, entry := range events {
		entry.mu.Lock()
		e := entry.event
		if !e.IsTerminal() && e.RulesMode == protocol.RulesModeForge {
			r.ForgeDemand += (e.MaxPlayers + 1) / 2
		}
		kind := "tournament"
		if e.IsCubeRoom() {
			kind = "cube"
		}
		add := func(aid, role string) {
			if aid != "" {
				r.Resources[aid] = append(r.Resources[aid], protocol.AccountResource{Kind: kind, ID: e.ID, Name: e.Name, Role: role})
			}
		}
		add(e.OrganizerAccountID, tournament.RoleOrganizer)
		for _, p := range e.Participants {
			if p.AccountID != e.OrganizerAccountID {
				add(p.AccountID, tournament.RoleParticipant)
			}
		}
		entry.mu.Unlock()
	}
	h.forgeMu.Lock()
	r.ForgeDemand = max(r.ForgeDemand, h.forgeOccupiedLocked())
	h.forgeMu.Unlock()
	return r
}

func (h *Handler) clusterView(ctx context.Context, accountID string) (out cluster.Result, err error) {
	finish := h.control.clusterView.start()
	defer func() { finish(err) }()
	if err := h.clusterAgent.Refresh(ctx); err != nil {
		return cluster.Result{}, err
	}
	return h.clusterAgent.Do(ctx, cluster.Request{Operation: "view", AccountID: accountID})
}

func (h *Handler) clusterError(sess *Session, requestID string, err error) {
	code, message := protocol.ErrClusterUnavailable, "Official lobby is temporarily unavailable; retry later"
	if err == cluster.ErrFull {
		code, message = protocol.ErrClusterFull, "No healthy official node has capacity for this request"
	}
	if err == cluster.ErrInvalid {
		code, message = protocol.ErrInvalidMessage, "Invalid or expired node transfer"
	}
	h.sendError(sess, requestID, code, message)
}

func (h *Handler) accountVisibleResources(ctx context.Context, sess *Session) []protocol.AccountResource {
	if h.clusterAgent == nil || !sess.clusterEnabled {
		return h.accountResources(sess)
	}
	if out, err := h.clusterView(ctx, sess.Account().ID); err == nil {
		return out.Resources
	}
	// Authentication and the current node remain usable during coordinator loss.
	resources := h.accountResources(sess)
	for i := range resources {
		resources[i].ID = cluster.GlobalCode(h.clusterNode(), resources[i].ID)
	}
	return resources
}

func (h *Handler) welcomeCapabilities(enabled bool) (forge, ai, hosting bool) {
	forge, ai, hosting = h.forgeRulesAvailable(), h.forgeAIAvailable(), h.config.AllowPlayerHosting
	if enabled {
		c := h.clusterAgent.Capabilities()
		forge, ai, hosting = forge || c.Forge, ai || c.ForgeAI, hosting || c.PlayerHosting
	}
	return
}
