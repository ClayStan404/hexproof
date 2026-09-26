// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"strings"
	"time"

	"hexproof/server/internal/cluster"
	"hexproof/server/internal/protocol"
)

func clusterDigest(env protocol.Envelope) string {
	var payload any
	if json.Unmarshal(env.Payload, &payload) != nil {
		return ""
	}
	canonical, err := json.Marshal(payload)
	if err != nil {
		return ""
	}
	digest := sha256.Sum256(append([]byte(env.Type+"\n"), canonical...))
	return hex.EncodeToString(digest[:])
}

// clusterCommand identifies only lobby navigation/creation. Game commands and
// event table operations always execute on their existing authoritative node.
func clusterCommand(env protocol.Envelope) (demand cluster.Demand, resourceField string, eligible bool) {
	switch env.Type {
	case protocol.TypeRoomCreate:
		var q protocol.RoomCreate
		if env.DecodePayload(&q) != nil {
			return
		}
		demand.Rooms = 1
		if q.RulesMode == protocol.RulesModeForge {
			if q.HostingMode == "player" {
				demand.PlayerHosting = true
			} else {
				demand.Forge = 1
			}
			demand.ForgeAI = q.HostingMode != "player" && (q.AISource == protocol.AISourceForge || (q.AISource == "" && q.AIDifficulty != ""))
		}
		eligible = true
	case protocol.TypeTournamentCreate:
		var q protocol.TournamentCreate
		if env.DecodePayload(&q) != nil {
			return
		}
		demand.Events = 1
		if strings.EqualFold(strings.TrimSpace(q.Coordinator), protocol.LimitedCoordinatorCasual) && protocol.IsCubeEventType(strings.ToLower(strings.TrimSpace(q.EventType))) {
			demand.Rooms = 1
		}
		if q.RulesMode == protocol.RulesModeForge {
			players := q.MaxPlayers
			if players == 0 {
				players = 64
				if q.EventType == protocol.LimitedEventSetDraft || protocol.IsCubeEventType(q.EventType) {
					players = 8
				}
			}
			demand.Forge = (players + 1) / 2
		}
		eligible = true
	case protocol.TypeRoomJoin:
		resourceField, eligible = "roomId", true
	case protocol.TypeTournamentEnter:
		resourceField, eligible = "tournamentId", true
	case protocol.TypeAccountCommand:
		var q protocol.AccountCommand
		if env.DecodePayload(&q) == nil && (q.Operation == "resume" || (q.Operation == "claim" && (q.Kind == "cube" || q.Kind == "tournament"))) {
			resourceField, eligible = "resourceId", true
		}
	}
	return
}

// Called before the domain handler, while only the account gate may be held.
// done publishes after all domain locks have been released. Remote routing is
// an acknowledgement of placement only: it must not execute the command here.
func (h *Handler) routeClusterCommand(sess *Session, env *protocol.Envelope) (handled bool, done func()) {
	if h.clusterAgent == nil || !sess.clusterEnabled || sess.DisplayName == "" {
		return false, nil
	}
	if sess.clusterRedirected {
		h.clusterError(sess, env.ID, cluster.ErrInvalid)
		return true, nil
	}
	demand, field, eligible := clusterCommand(*env)
	if !eligible && sess.clusterGrant == nil {
		return false, nil
	}
	var payload map[string]json.RawMessage
	var target, local string
	if field != "" {
		var code string
		if json.Unmarshal(env.Payload, &payload) != nil || json.Unmarshal(payload[field], &code) != nil {
			return false, nil
		}
		var ok bool
		target, local, ok = cluster.SplitCode(code)
		if strings.Contains(code, ":") && !ok {
			h.clusterError(sess, env.ID, cluster.ErrInvalid)
			return true, nil
		}
	}
	grant := sess.clusterGrant
	if grant != nil {
		if !time.Now().Before(grant.ExpiresAt) || grant.CommandType != env.Type || grant.Digest != clusterDigest(*env) || grant.AccountID != sess.Account().ID {
			h.clusterError(sess, env.ID, cluster.ErrInvalid)
			return true, nil
		}
		sess.clusterGrant = nil
	} else if field != "" && (target == "" || target == h.clusterNode()) {
		// Local invites remain usable when the coordinator is unavailable.
	} else {
		if sess.Room() != nil || h.cubeRoomBlocksNavigation(sess, "") {
			h.sendError(sess, env.ID, protocol.ErrAlreadyInRoom, "Leave the current room before switching nodes")
			return true, nil
		}
		limit := 30
		if env.Type == protocol.TypeRoomCreate {
			limit = h.config.RoomCreatesPerMinute
		}
		if env.Type == protocol.TypeTournamentCreate {
			limit = h.config.TournamentCreatesPerMinute
		}
		if !h.clusterRouteLimiter.allow(env.Type+":"+sess.RemoteIP, time.Now().UTC(), limit) {
			h.sendError(sess, env.ID, protocol.ErrRateLimited, "Official node transfer rate limit exceeded")
			return true, nil
		}
		if err := h.clusterAgent.Publish(context.Background(), ""); err != nil {
			h.clusterError(sess, env.ID, err)
			return true, nil
		}
		out, err := h.clusterAgent.Do(context.Background(), cluster.Request{Operation: "allocate", Target: target,
			AccountID: sess.Account().ID, CommandType: env.Type, Digest: clusterDigest(*env), Demand: demand, Latency: sess.clusterLatency})
		if err != nil {
			h.clusterError(sess, env.ID, err)
			return true, nil
		}
		if out.Ticket.NodeID != h.clusterNode() {
			route, _ := protocol.NewEnvelope(protocol.TypeSessionRoute, protocol.SessionRoute{URL: out.Ticket.URL, Realm: h.accountRealm(), Ticket: out.Ticket.Token, NodeID: out.Ticket.NodeID})
			route.ID = env.ID
			sess.clusterRedirected = true
			h.send(sess, route)
			return true, nil
		}
		out, err = h.clusterAgent.Do(context.Background(), cluster.Request{Operation: "take", Token: out.Ticket.Token, AccountID: sess.Account().ID})
		if err != nil {
			h.clusterError(sess, env.ID, err)
			return true, nil
		}
		grant = out.Ticket
	}
	if target != "" {
		if target != h.clusterNode() {
			h.clusterError(sess, env.ID, cluster.ErrInvalid)
			return true, nil
		}
		payload[field], _ = json.Marshal(local)
		env.Payload, _ = json.Marshal(payload)
	}
	if grant != nil {
		done = func() { _ = h.clusterAgent.Publish(context.Background(), grant.Token) }
	}
	return false, done
}

func (h *Handler) acceptClusterHello(sess *Session, hello protocol.SessionHello, accountID, requestID string) bool {
	sess.clusterEnabled = h.clusterAgent != nil && hello.ClusterRealm == h.accountRealm()
	if len(hello.ClusterRealm) > 64 || len(hello.NodeLatencies) > 16 || len(hello.ClusterTicket) > 128 {
		h.clusterError(sess, requestID, cluster.ErrInvalid)
		return false
	}
	if hello.ClusterTicket != "" {
		if !sess.clusterEnabled {
			h.clusterError(sess, requestID, cluster.ErrInvalid)
			return false
		}
		out, err := h.clusterAgent.Do(context.Background(), cluster.Request{Operation: "take", Token: hello.ClusterTicket, AccountID: accountID})
		if err != nil {
			h.clusterError(sess, requestID, err)
			return false
		}
		sess.clusterGrant = out.Ticket
	}
	sess.clusterLatency = map[string]int{}
	for _, latency := range hello.NodeLatencies {
		if len(latency.URL) <= 512 && latency.Milliseconds >= -1 && latency.Milliseconds <= 2000 {
			sess.clusterLatency[latency.URL] = latency.Milliseconds
		}
	}
	return true
}
