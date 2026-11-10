// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestClusterCreateOperationAcrossConcurrentEntrances(t *testing.T) {
	servers, handlers := clusterServers(t)
	one, two := dial(t, servers[0]), dial(t, servers[1])
	defer one.close()
	defer two.close()
	clusterHello(one, "One")
	clusterHello(two, "Two")
	request := cubeRoomRequest(2)
	request.OperationID = "global-create-operation"
	env := cubeCommandEnvelope(t, protocol.TypeTournamentCreate, request)
	// Independent socket read loops race through the coordinator's one claim.
	one.send(env)
	two.send(env)
	replies := []protocol.Envelope{
		one.recvType(protocol.TypeTournamentCreated, protocol.TypeSessionRoute, protocol.TypeError),
		two.recvType(protocol.TypeTournamentCreated, protocol.TypeSessionRoute, protocol.TypeError),
	}
	successes, replays := 0, 0
	for _, reply := range replies {
		switch reply.Type {
		case protocol.TypeTournamentCreated:
			successes++
		case protocol.TypeSessionRoute:
			target := routedClient(t, servers[1], reply, "")
			defer target.close()
			target.send(env)
			if target.recvType(protocol.TypeTournamentCreated, protocol.TypeError).Type != protocol.TypeTournamentCreated {
				t.Fatal("winning route failed")
			}
			successes++
		case protocol.TypeError:
			failure := tournamentOperationError(t, reply, protocol.ErrInvalidMessage)
			if !strings.Contains(failure.Message, "Creation operation already attempted") {
				t.Fatal("replay error lost actionable semantics", failure)
			}
			replays++
		}
	}
	if successes != 1 || replays != 1 || len(handlers[0].tournaments.snapshot())+len(handlers[1].tournaments.snapshot()) != 1 {
		t.Fatal("concurrent entries created multiple events or credentials")
	}
	request.Name = "Changed payload must not create another event"
	retry := cubeCommandEnvelope(t, protocol.TypeTournamentCreate, request)
	for _, srv := range servers {
		peer := dial(t, srv)
		defer peer.close()
		clusterHello(peer, "Retry")
		peer.send(retry)
		failure := tournamentOperationError(t, peer.recvType(protocol.TypeError, protocol.TypeSessionRoute, protocol.TypeTournamentCreated), protocol.ErrInvalidMessage)
		if !strings.Contains(failure.Message, "Creation operation already attempted") {
			t.Fatal(failure)
		}
	}
	if len(handlers[0].tournaments.snapshot())+len(handlers[1].tournaments.snapshot()) != 1 {
		t.Fatal("changed request bypassed cross-node operation identity")
	}
}

func TestClusterCreateRetryKeepsOriginalTicketAndDigestBinding(t *testing.T) {
	servers, handlers := clusterServers(t)
	origin := dial(t, servers[0])
	defer origin.close()
	clusterHello(origin, "Host")
	request := cubeRoomRequest(2)
	request.OperationID = "routed-create-operation"
	env := cubeCommandEnvelope(t, protocol.TypeTournamentCreate, request)
	origin.send(env)
	route := origin.recvType(protocol.TypeSessionRoute)
	// Simulate retry through another entrance while the first route is unresolved.
	retry := dial(t, servers[1])
	defer retry.close()
	clusterHello(retry, "Retry")
	retry.send(env)
	tournamentOperationError(t, retry.recvType(protocol.TypeError, protocol.TypeSessionRoute, protocol.TypeTournamentCreated), protocol.ErrInvalidMessage)
	if len(handlers[0].tournaments.snapshot())+len(handlers[1].tournaments.snapshot()) != 0 {
		t.Fatal("retry executed an unresolved creation")
	}
	target := routedClient(t, servers[1], route, "")
	defer target.close()
	request.Name = "Tampered recipe envelope"
	modified := cubeCommandEnvelope(t, protocol.TypeTournamentCreate, request)
	target.send(modified)
	tournamentOperationError(t, target.recvType(protocol.TypeError, protocol.TypeTournamentCreated), protocol.ErrInvalidMessage)
	if len(handlers[1].tournaments.snapshot()) != 0 {
		t.Fatal("modified routed payload bypassed ticket digest")
	}
	target.send(env)
	if target.recvType(protocol.TypeTournamentCreated, protocol.TypeError).Type != protocol.TypeTournamentCreated || len(handlers[1].tournaments.snapshot()) != 1 {
		t.Fatal("original route was lost after replay or digest rejection")
	}
}
