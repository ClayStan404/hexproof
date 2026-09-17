// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
	"hexproof/server/internal/forgehost"
	"hexproof/server/internal/protocol"
)

func TestPlayerHostingBindingRejectsOtherRoomsVersionsAndRevokedTokens(t *testing.T) {
	config := DefaultConfig()
	config.AllowPlayerHosting = true
	srv, handler := newConfiguredTestServer(t, config)
	host := dial(t, srv)
	defer host.close()
	host.hello("Host")
	create, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{Name: "Host binding", Format: "modern", DeckFormat: "modern", RulesMode: "forge", HostingMode: "player", MatchMode: "bo1"})
	create.ID = "create"
	host.send(create)
	var grant protocol.ForgeHostGrant
	if err := host.recvType(protocol.TypeForgeHostGrant).DecodePayload(&grant); err != nil {
		t.Fatal(err)
	}
	hello := forgehost.Hello{Version: forgehost.Version, RuntimeID: forgehost.RuntimeID, RoomID: grant.RoomID, Token: grant.Token, HelperID: forgehost.NewID()}
	bind := func(hello forgehost.Hello, accepted bool) *websocket.Conn {
		t.Helper()
		ctx, cancel := context.WithTimeout(t.Context(), 2*time.Second)
		defer cancel()
		conn, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(srv.URL, "http")+"?engine=1", nil)
		if err != nil {
			t.Fatal(err)
		}
		raw, _ := json.Marshal(hello)
		if err := conn.Write(ctx, websocket.MessageText, raw); err != nil {
			t.Fatal(err)
		}
		_, raw, err = conn.Read(ctx)
		if accepted {
			var bound forgehost.Frame
			if err != nil || json.Unmarshal(raw, &bound) != nil || bound.Type != "bound" {
				t.Fatalf("valid helper was rejected: %v", err)
			}
		} else if err == nil {
			conn.CloseNow()
			t.Fatal("invalid binding accepted")
		}
		return conn
	}
	for _, change := range []func(*forgehost.Hello){
		func(h *forgehost.Hello) { h.RoomID = "OTHER" },
		func(h *forgehost.Hello) { h.Token = forgehost.NewID() },
		func(h *forgehost.Hello) { h.RuntimeID = "wrong-runtime" },
		func(h *forgehost.Hello) { h.Version++ },
	} {
		bad := hello
		change(&bad)
		bind(bad, false).CloseNow()
	}
	old := bind(hello, true)
	defer old.CloseNow()
	host.recvType(protocol.TypeForgeHostStatus)
	request, _ := protocol.NewEnvelope(protocol.TypeForgeHostRequest, protocol.EmptyPayload{})
	request.ID = "replace"
	host.send(request)
	if err := host.recvType(protocol.TypeForgeHostGrant).DecodePayload(&grant); err != nil {
		t.Fatal(err)
	}
	bind(hello, false).CloseNow()
	hello.Token = grant.Token
	hello.HelperID = forgehost.NewID()
	current := bind(hello, true)
	defer current.CloseNow()
	host.recvType(protocol.TypeForgeHostStatus)
	leave, _ := protocol.NewEnvelope(protocol.TypeRoomLeave, protocol.EmptyPayload{})
	leave.ID = "leave"
	host.send(leave)
	host.recvType(protocol.TypeRoomDisbanded)
	barrier, _ := protocol.NewEnvelope(protocol.TypeSessionPing, protocol.EmptyPayload{})
	barrier.ID = "barrier"
	host.send(barrier)
	host.recvType(protocol.TypeSessionPong)
	handler.forgeMu.Lock()
	remaining := len(handler.playerHosts)
	handler.forgeMu.Unlock()
	if remaining != 0 {
		t.Fatal("creator leave retained hosting capability")
	}
	bind(hello, false).CloseNow()
}

func TestPlayerHostingCapacityRejectsCreationWithoutLeavingAnUnusableRoom(t *testing.T) {
	config := DefaultConfig()
	config.AllowPlayerHosting = true
	config.MaxPlayerHostedGames = 1
	srv, handler := newConfiguredTestServer(t, config)
	for index := 0; index < 2; index++ {
		host := dial(t, srv)
		defer host.close()
		host.hello("Host")
		env, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{Name: "Capacity", Format: "modern", DeckFormat: "modern", RulesMode: "forge", HostingMode: "player", MatchMode: "bo1"})
		env.ID = "create"
		host.send(env)
		if index == 0 {
			host.recvType(protocol.TypeForgeHostGrant)
			continue
		}
		var failure protocol.ErrorPayload
		if err := host.recvType(protocol.TypeError).DecodePayload(&failure); err != nil || failure.Code != protocol.ErrServerLimit {
			t.Fatal("capacity was not rejected")
		}
		// The rejected connection remains free to create an ordinary room.
		env, _ = protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{Name: "Manual", Format: "modern", DeckFormat: "modern", RulesMode: "manual", MatchMode: "bo1"})
		env.ID = "manual"
		host.send(env)
		host.recvType(protocol.TypeRoomCreated)
	}
	handler.forgeMu.Lock()
	count := len(handler.playerHosts)
	handler.forgeMu.Unlock()
	if count != 1 {
		t.Fatal("wrong number of reserved bindings")
	}
}

func TestPlayerHostingCapabilitiesConsentAndCreatorAuthorization(t *testing.T) {
	config := DefaultConfig()
	config.AllowPlayerHosting = true
	srv, _ := newConfiguredTestServer(t, config)
	host := dial(t, srv)
	defer host.close()
	guest := dial(t, srv)
	defer guest.close()
	var welcome protocol.SessionWelcome
	if err := host.hello("Host").DecodePayload(&welcome); err != nil {
		t.Fatal(err)
	}
	guest.hello("Guest")
	if welcome.ForgeRulesAvailable || !welcome.PlayerHostingAvailable {
		t.Fatal("runtime and relay capabilities were conflated")
	}
	create, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{
		Name: "Trusted host", Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatModern,
		RulesMode: protocol.RulesModeForge, HostingMode: "player", MatchMode: protocol.MatchBO3, AllowSpectators: true,
	})
	create.ID = "create"
	host.send(create)
	var created protocol.RoomCreated
	if err := host.recvType(protocol.TypeRoomCreated).DecodePayload(&created); err != nil {
		t.Fatal(err)
	}
	if created.Settings.HostingMode != "player" {
		t.Fatal("hosting mode not disclosed")
	}
	var grant protocol.ForgeHostGrant
	if err := host.recvType(protocol.TypeForgeHostGrant).DecodePayload(&grant); err != nil {
		t.Fatal(err)
	}
	if grant.RoomID != created.RoomID || len(grant.Token) != 64 {
		t.Fatal("missing private creator capability")
	}
	join, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: created.RoomID})
	join.ID = "join"
	guest.send(join)
	var failure protocol.ErrorPayload
	if err := guest.recvType(protocol.TypeError).DecodePayload(&failure); err != nil {
		t.Fatal(err)
	}
	if failure.Code != protocol.ErrPlayerHostTrustRequired {
		t.Fatal("joined without disclosing trusted-host mode")
	}
	join, _ = protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: created.RoomID, AcceptPlayerHost: true})
	join.ID = "join-consented"
	guest.send(join)
	guest.recvType(protocol.TypeRoomJoined)
	snapshot := guest.recvType(protocol.TypeRoomSnapshot)
	if strings.Contains(string(snapshot.Payload), grant.Token) {
		t.Fatal("creator capability leaked to guest")
	}
	request, _ := protocol.NewEnvelope(protocol.TypeForgeHostRequest, protocol.EmptyPayload{})
	request.ID = "steal-host"
	guest.send(request)
	if err := guest.recvType(protocol.TypeError).DecodePayload(&failure); err != nil {
		t.Fatal(err)
	}
	if failure.Code != protocol.ErrNotHost {
		t.Fatal("non-creator received hosting permission")
	}
}

func TestBackupRequiresBothPlayersConsentAndRevokesWithdrawnCapability(t *testing.T) {
	config := DefaultConfig()
	config.AllowPlayerHosting = true
	srv, handler := newConfiguredTestServer(t, config)
	host, guest, observer := dial(t, srv), dial(t, srv), dial(t, srv)
	defer host.close()
	defer guest.close()
	defer observer.close()
	host.hello("Host")
	guest.hello("Guest")
	observer.hello("Observer")
	create, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{Name: "Migration consent", Format: "modern", DeckFormat: "modern", RulesMode: "forge", HostingMode: "player", MatchMode: "bo1", AllowSpectators: true})
	create.ID = "create"
	host.send(create)
	var primary protocol.ForgeHostGrant
	if host.recvType(protocol.TypeForgeHostGrant).DecodePayload(&primary) != nil {
		t.Fatal("missing creator grant")
	}
	for i, peer := range []*wsClient{guest, observer} {
		join, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: primary.RoomID, AcceptPlayerHost: true, AsSpectator: i == 1})
		join.ID = "join"
		peer.send(join)
		peer.recvType(protocol.TypeRoomJoined)
	}
	command := func(peer *wsClient, action, id string) {
		env, _ := protocol.NewEnvelope(protocol.TypeForgeHostRequest, protocol.ForgeHostRequest{Action: action})
		env.ID = id
		peer.send(env)
	}
	command(observer, "offer", "spectator-offer")
	observer.recvType(protocol.TypeError)
	command(guest, "offer", "volunteer")
	var backup protocol.ForgeHostGrant
	if guest.recvType(protocol.TypeForgeHostGrant).DecodePayload(&backup) != nil || !backup.Standby || backup.Token == primary.Token {
		t.Fatal("standby capability was not independent")
	}
	status := handler.playerHostingStatus(primary.RoomID)
	if status.BackupApproved || status.BackupSeat == nil || *status.BackupSeat != 1 {
		t.Fatal("volunteering implied approval")
	}
	command(guest, "approve", "self-approve")
	guest.recvType(protocol.TypeError)
	command(guest, "migrate", "unapproved")
	guest.recvType(protocol.TypeError)
	command(host, "approve", "approve")
	for {
		if env := host.recvType(protocol.TypeForgeHostStatus); env.ID == "approve" {
			break
		}
	}
	if !handler.playerHostingStatus(primary.RoomID).BackupApproved {
		t.Fatal("host approval not recorded")
	}
	command(guest, "withdraw", "withdraw")
	for {
		if env := guest.recvType(protocol.TypeForgeHostStatus); env.ID == "withdraw" {
			break
		}
	}
	if handler.playerHostingStatus(primary.RoomID).BackupSeat != nil {
		t.Fatal("withdrawn standby retained")
	}
	ctx, cancel := context.WithTimeout(t.Context(), 2*time.Second)
	defer cancel()
	conn, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(srv.URL, "http")+"?engine=1", nil)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.CloseNow()
	hello, _ := json.Marshal(forgehost.Hello{Version: forgehost.Version, RuntimeID: forgehost.RuntimeID, RoomID: primary.RoomID, Token: backup.Token, HelperID: forgehost.NewID()})
	if conn.Write(ctx, websocket.MessageText, hello) != nil {
		t.Fatal("write revoked hello")
	}
	if _, _, err := conn.Read(ctx); err == nil {
		t.Fatal("withdrawn helper bound again")
	}
}

func TestPlayerHostingRejectsUnsupportedRooms(t *testing.T) {
	for _, mode := range []string{"disabled", "manual", "edh"} {
		t.Run(mode, func(t *testing.T) {
			config := DefaultConfig()
			config.AllowPlayerHosting = mode != "disabled"
			srv, _ := newConfiguredTestServer(t, config)
			host := dial(t, srv)
			defer host.close()
			host.hello("Host")
			rules, format, deck := protocol.RulesModeForge, protocol.FormatModern, protocol.DeckFormatModern
			if mode == "manual" {
				rules = protocol.RulesModeManual
			}
			if mode == "edh" {
				format = protocol.FormatEDH
				deck = protocol.DeckFormatCommander
			}
			env, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{Name: "Invalid host", Format: format, DeckFormat: deck, RulesMode: rules, HostingMode: "player", MatchMode: protocol.MatchBO1})
			env.ID = "create"
			host.send(env)
			var failure protocol.ErrorPayload
			if err := host.recvType(protocol.TypeError).DecodePayload(&failure); err != nil {
				t.Fatal(err)
			}
			if failure.Code != protocol.ErrRulesUnavailable {
				t.Fatalf("unexpected failure: %s", failure.Code)
			}
		})
	}
}
