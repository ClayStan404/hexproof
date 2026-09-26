// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"hexproof/server/internal/buildinfo"
	"hexproof/server/internal/cluster"
	"hexproof/server/internal/protocol"
)

func clusterServers(t *testing.T) ([2]*httptest.Server, [2]*Handler) {
	t.Helper()
	servers := [2]*httptest.Server{httptest.NewUnstartedServer(nil), httptest.NewUnstartedServer(nil)}
	nodes := []cluster.Node{
		{ID: "N1", Name: "One", URL: "ws://" + servers[0].Listener.Addr().String() + "/ws", Weight: 1},
		{ID: "N2", Name: "Two", URL: "ws://" + servers[1].Listener.Addr().String() + "/ws", Weight: 100},
	}
	key := strings.Repeat("cluster-integration-", 2)
	var handlers [2]*Handler
	for i := range servers {
		cfg := DefaultConfig()
		cfg.AccountRealm, cfg.AccountServiceKey = "cluster-integration", key
		cfg.Cluster = &cluster.Config{Realm: cfg.AccountRealm, NodeID: nodes[i].ID, Key: key, Nodes: nodes}
		if i == 0 {
			cfg.AccountDir = t.TempDir()
		} else {
			cfg.AccountAuthority = servers[0].URL + "/internal/accounts"
			cfg.Cluster.Coordinator = servers[0].URL + "/internal/cluster"
		}
		h, err := NewHandlerWithConfig(cfg)
		if err != nil {
			t.Fatal(err)
		}
		handlers[i] = h
		mux := http.NewServeMux()
		mux.Handle("/ws", h)
		mux.HandleFunc("/internal/accounts", h.ServeAccountAuthority)
		mux.HandleFunc("/internal/cluster", h.ServeClusterCoordinator)
		servers[i].Config.Handler = mux
		servers[i].Start()
	}
	t.Cleanup(func() {
		for i := len(handlers) - 1; i >= 0; i-- {
			_ = handlers[i].Close()
			servers[i].Close()
		}
	})
	return servers, handlers
}

func routedClient(t *testing.T, server *httptest.Server, route protocol.Envelope, token string) *wsClient {
	t.Helper()
	var r protocol.SessionRoute
	if route.Type != protocol.TypeSessionRoute || route.DecodePayload(&r) != nil || r.NodeID != "N2" {
		t.Fatalf("expected N2 route, got %s %s", route.Type, route.Payload)
	}
	c := dial(t, server)
	hello, _ := protocol.NewEnvelope(protocol.TypeSessionHello, protocol.SessionHello{
		DisplayName: "Player", ClientVersion: buildinfo.Version, ClusterRealm: "cluster-integration", ClusterTicket: r.Ticket, AccountSession: token,
	})
	hello.ID = "hello-target"
	c.send(hello)
	welcome := c.recvType(protocol.TypeSessionWelcome, protocol.TypeError)
	if welcome.Type != protocol.TypeSessionWelcome {
		t.Fatal(string(welcome.Payload))
	}
	return c
}

func clusterRoomCreate() protocol.Envelope {
	env, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{
		Name: "Shared lobby table", Format: protocol.FormatModern, MatchMode: protocol.MatchBO1,
		AllowSpectators: true, Password: "secret",
	})
	env.ID = "original-create"
	return env
}

func TestClusterCreateDiscoverJoinAndAccountRecovery(t *testing.T) {
	servers, handlers := clusterServers(t)
	origin := dial(t, servers[0])
	defer origin.close()
	clusterHello(origin, "Player")
	identity := accountCommand(t, origin, protocol.AccountCommand{Operation: "create", Name: "Alice", DeviceName: "First"})
	create := clusterRoomCreate()
	origin.send(create)
	route := origin.recvType(protocol.TypeSessionRoute, protocol.TypeError)
	if route.ID != create.ID {
		t.Fatal("lost request correlation")
	}
	if len(handlers[0].hub.ListRooms()) != 0 || len(handlers[1].hub.ListRooms()) != 0 {
		t.Fatal("route executed create before transfer")
	}
	owner := routedClient(t, servers[1], route, identity.SessionToken)
	defer owner.close()
	owner.send(create)
	created := owner.recvType(protocol.TypeRoomCreated, protocol.TypeError)
	var result protocol.RoomCreated
	if created.Type != protocol.TypeRoomCreated || created.DecodePayload(&result) != nil || created.ID != create.ID {
		t.Fatal(created)
	}
	owner.recvType(protocol.TypeRoomSnapshot)
	// A directory refresh also synchronizes the local report after account binding.
	if err := handlers[1].clusterAgent.Publish(context.Background(), ""); err != nil {
		t.Fatal(err)
	}
	lobby := dial(t, servers[0])
	defer lobby.close()
	clusterHello(lobby, "Guest")
	list, _ := protocol.NewEnvelope(protocol.TypeRoomList, struct{}{})
	list.ID = "list"
	lobby.send(list)
	var listed protocol.RoomListed
	lobby.recvType(protocol.TypeRoomListed).DecodePayload(&listed)
	code := "N2:" + result.RoomID
	if len(listed.Rooms) != 1 || listed.Rooms[0].RoomID != code || listed.Rooms[0].NodeName != "Two" || !listed.Rooms[0].HasPassword {
		t.Fatal(listed)
	}
	join, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: code, Password: "wrong"})
	join.ID = "join"
	lobby.send(join)
	guest := routedClient(t, servers[1], lobby.recvType(protocol.TypeSessionRoute), "")
	defer guest.close()
	guest.send(join)
	var rejected protocol.ErrorPayload
	guest.recvType(protocol.TypeError).DecodePayload(&rejected)
	if rejected.Code != protocol.ErrWrongPassword {
		t.Fatal("routing bypassed password", rejected)
	}
	join, _ = protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: code, Password: "secret", AsSpectator: true})
	join.ID = "spectate"
	guest.send(join)
	var joined protocol.RoomJoined
	guest.recvType(protocol.TypeRoomJoined).DecodePayload(&joined)
	if joined.Role != protocol.RoleSpectator {
		t.Fatal("spectator role changed", joined)
	}
	// New device logs in at N1; the directory locates the live N2 account seat.
	replacement := dial(t, servers[0])
	defer replacement.close()
	clusterHello(replacement, "Replacement")
	logged := accountCommand(t, replacement, protocol.AccountCommand{Operation: "login", LoginCode: identity.LoginCode, DeviceName: "Second"})
	if len(logged.Resources) != 1 || logged.Resources[0].ID != code {
		t.Fatal("account location lost", logged.Resources)
	}
	resume, _ := protocol.NewEnvelope(protocol.TypeAccountCommand, protocol.AccountCommand{Operation: "resume", ResourceID: code})
	resume.ID = "resume-global"
	replacement.send(resume)
	recovered := routedClient(t, servers[1], replacement.recvType(protocol.TypeSessionRoute), logged.SessionToken)
	defer recovered.close()
	recovered.send(resume)
	state := recovered.recvType(protocol.TypeAccountState, protocol.TypeError)
	if state.Type != protocol.TypeAccountState || state.ID != resume.ID {
		t.Fatal("cross-node recovery failed", state)
	}
	entry := handlers[1].hub.roomEntryFor(result.RoomID)
	entry.mu.Lock()
	if entry.room.Seats[0].AccountID != identity.AccountID || !entry.room.Seats[0].Host {
		t.Error("seat ownership changed")
	}
	entry.mu.Unlock()
}

func TestClusterTicketCannotChangeCommandOrBeReused(t *testing.T) {
	servers, handlers := clusterServers(t)
	origin := dial(t, servers[0])
	defer origin.close()
	clusterHello(origin, "Host")
	create := clusterRoomCreate()
	origin.send(create)
	route := origin.recvType(protocol.TypeSessionRoute)
	target := routedClient(t, servers[1], route, "")
	defer target.close()
	modified := create
	var payload protocol.RoomCreate
	modified.DecodePayload(&payload)
	payload.Password = "changed"
	modified, _ = protocol.NewEnvelope(protocol.TypeRoomCreate, payload)
	modified.ID = create.ID
	target.send(modified)
	target.recvType(protocol.TypeError)
	if len(handlers[1].hub.ListRooms()) != 0 {
		t.Fatal("modified command executed")
	}
	target.send(create)
	target.recvType(protocol.TypeRoomCreated)
	var r protocol.SessionRoute
	route.DecodePayload(&r)
	reuse := dial(t, servers[1])
	defer reuse.close()
	hello, _ := protocol.NewEnvelope(protocol.TypeSessionHello, protocol.SessionHello{DisplayName: "Thief", ClientVersion: buildinfo.Version, ClusterRealm: "cluster-integration", ClusterTicket: r.Ticket})
	hello.ID = "reuse"
	reuse.send(hello)
	reuse.recvType(protocol.TypeError)
}

func TestClusterWholeCubeOwnershipAndPrivacy(t *testing.T) {
	servers, handlers := clusterServers(t)
	origin := dial(t, servers[0])
	defer origin.close()
	clusterHello(origin, "Cube host")
	request := cubeCommandEnvelope(t, protocol.TypeTournamentCreate, cubeRoomRequest(2))
	origin.send(request)
	target := routedClient(t, servers[1], origin.recvType(protocol.TypeSessionRoute), "")
	defer target.close()
	target.send(request)
	created := target.recvType(protocol.TypeTournamentCreated)
	var result protocol.TournamentCreated
	created.DecodePayload(&result)
	if len(handlers[0].tournaments.snapshot()) != 0 || handlers[1].tournaments.entry(result.TournamentID) == nil {
		t.Fatal("event split between hubs")
	}
	_ = handlers[1].clusterAgent.Publish(context.Background(), "")
	view, err := handlers[0].clusterView("")
	if err != nil || len(view.Rooms) != 1 || view.Rooms[0].RoomKind != "cube" || view.Rooms[0].RoomID != "N2:"+result.TournamentID || len(view.Events) != 0 || len(view.Resources) != 0 {
		t.Fatalf("Cube public projection: %+v %v", view, err)
	}
	// An occupied Cube cannot be abandoned by routing a new create elsewhere.
	target.send(clusterRoomCreate())
	var rejected protocol.ErrorPayload
	target.recvType(protocol.TypeError).DecodePayload(&rejected)
	if rejected.Code != protocol.ErrAlreadyInRoom {
		t.Fatal(rejected)
	}
}

func clusterHello(c *wsClient, name string) {
	hello, _ := protocol.NewEnvelope(protocol.TypeSessionHello, protocol.SessionHello{DisplayName: name, ClientVersion: buildinfo.Version, ClusterRealm: "cluster-integration"})
	hello.ID = "hello"
	c.send(hello)
	c.recvType(protocol.TypeSessionWelcome)
}

func TestClusterCustomConnectionStaysLocalAndPrivateRoomsStayHidden(t *testing.T) {
	servers, handlers := clusterServers(t)
	custom := dial(t, servers[0])
	defer custom.close()
	var welcome protocol.SessionWelcome
	custom.hello("Custom guest").DecodePayload(&welcome)
	if welcome.ClusterNode != "" {
		t.Fatal("untrusted custom connection opted into routing")
	}
	_, roomID := custom.createRoom("Node local", protocol.FormatModern, 2, true, "")
	if handlers[0].hub.roomEntryFor(roomID) == nil {
		t.Fatal("custom create was routed")
	}
	private := dial(t, servers[1])
	defer private.close()
	private.hello("Private host")
	request := clusterRoomCreate()
	var payload protocol.RoomCreate
	request.DecodePayload(&payload)
	payload.Playtest = true
	request, _ = protocol.NewEnvelope(protocol.TypeRoomCreate, payload)
	request.ID = "private"
	private.send(request)
	private.recvType(protocol.TypeRoomCreated)
	_ = handlers[1].clusterAgent.Publish(context.Background(), "")
	view, err := handlers[0].clusterView("")
	if err != nil || len(view.Rooms) != 1 || view.Rooms[0].RoomID != "N1:"+roomID || len(view.Resources) != 0 {
		t.Fatalf("private room leaked: %+v %v", view, err)
	}
}

func TestClusterReservationsHaveSourceRateLimit(t *testing.T) {
	servers, handlers := clusterServers(t)
	for i := 0; i < handlers[0].config.RoomCreatesPerMinute+1; i++ {
		client := dial(t, servers[0])
		clusterHello(client, "Guest")
		client.send(clusterRoomCreate())
		response := client.recvType(protocol.TypeSessionRoute, protocol.TypeError)
		client.close()
		if i < handlers[0].config.RoomCreatesPerMinute {
			if response.Type != protocol.TypeSessionRoute {
				t.Fatal(string(response.Payload))
			}
		} else {
			var rejected protocol.ErrorPayload
			response.DecodePayload(&rejected)
			if rejected.Code != protocol.ErrRateLimited {
				t.Fatal("abandoned reservations bypassed rate limit", rejected)
			}
		}
	}
}

func TestClusterOutageDoesNotMoveOrBlockEstablishedGuestRoom(t *testing.T) {
	servers, handlers := clusterServers(t)
	origin := dial(t, servers[0])
	defer origin.close()
	clusterHello(origin, "Host")
	create := clusterRoomCreate()
	origin.send(create)
	target := routedClient(t, servers[1], origin.recvType(protocol.TypeSessionRoute), "")
	defer target.close()
	target.send(create)
	var created protocol.RoomCreated
	target.recvType(protocol.TypeRoomCreated).DecodePayload(&created)
	target.recvType(protocol.TypeRoomSnapshot)
	servers[0].Close()
	newcomer := dial(t, servers[1])
	defer newcomer.close()
	clusterHello(newcomer, "New room")
	newcomer.send(create)
	var failure protocol.ErrorPayload
	newcomer.recvType(protocol.TypeError).DecodePayload(&failure)
	if failure.Code != protocol.ErrClusterUnavailable {
		t.Fatal(failure)
	}
	if handlers[1].hub.roomEntryFor(created.RoomID) == nil {
		t.Fatal("coordinator outage lost the live room")
	}
	leave, _ := protocol.NewEnvelope(protocol.TypeRoomLeave, struct{}{})
	leave.ID = "leave-during-outage"
	target.send(leave)
	if reply := target.recvType(protocol.TypeRoomLeft, protocol.TypeRoomDisbanded, protocol.TypeError); reply.Type == protocol.TypeError {
		t.Fatal("local operation blocked by coordinator", reply)
	}
}
