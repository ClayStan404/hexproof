// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"fmt"
	"os"
	"testing"

	"hexproof/server/internal/cluster"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
)

func TestForgeRoomCreationFormatAdmission(t *testing.T) {
	for _, test := range []struct {
		name, format, deckFormat, rulesMode, hostingMode string
		maxSeats                                         int
		wantError                                        bool
	}{
		{"edh_default_host", protocol.FormatEDH, protocol.DeckFormatCommander, protocol.RulesModeForge, "", 4, false},
		{"edh_server", protocol.FormatEDH, protocol.DeckFormatCommander, protocol.RulesModeForge, protocol.HostingModeServer, 4, false},
		{"edh_player", protocol.FormatEDH, protocol.DeckFormatCommander, protocol.RulesModeForge, protocol.HostingModePlayer, 4, true},
		{"edh_two_requested_seats", protocol.FormatEDH, protocol.DeckFormatCommander, protocol.RulesModeForge, protocol.HostingModeServer, 2, false},
		{"edh_legacy_deck_default", protocol.FormatEDH, "", protocol.RulesModeForge, protocol.HostingModeServer, 4, false},
		{"manual_edh", protocol.FormatEDH, protocol.DeckFormatCommander, protocol.RulesModeManual, protocol.HostingModeServer, 4, false},
		{"forge_modern", protocol.FormatModern, protocol.DeckFormatModern, protocol.RulesModeForge, protocol.HostingModeServer, 2, false},
		{"forge_duel", protocol.FormatDuel, protocol.DeckFormatDuel, protocol.RulesModeForge, protocol.HostingModeServer, 2, false},
		{"forge_player_duel", protocol.FormatDuel, protocol.DeckFormatDuel, protocol.RulesModeForge, protocol.HostingModePlayer, 2, false},
		{"forge_limited", protocol.FormatModern, protocol.DeckFormatLimited, protocol.RulesModeForge, protocol.HostingModeServer, 2, false},
	} {
		t.Run(test.name, func(t *testing.T) {
			config := DefaultConfig()
			config.AllowPlayerHosting = true
			config.ForgeRuntime = &forge.ProcessConfig{
				Command: os.Args[0], Args: []string{"-test.run=^TestForgeRuntimeCapabilityProbe$"},
				Env: []string{"HEXPROOF_FORGE_SERVER_TEST_HELPER=1"},
			}
			srv, handler := newConfiguredTestServer(t, config)
			host := dial(t, srv)
			defer host.close()
			host.hello("Host")
			if !handler.forgeRulesAvailable() {
				t.Fatal("fixture must provide an available Forge runtime")
			}
			request, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{
				Name: test.name, Format: test.format, DeckFormat: test.deckFormat,
				RulesMode: test.rulesMode, HostingMode: test.hostingMode,
				MaxSeats: test.maxSeats, MatchMode: protocol.MatchBO1,
			})
			request.ID = "create"
			host.send(request)
			response := host.recvType(protocol.TypeError, protocol.TypeRoomCreated)
			if response.ID != request.ID {
				t.Fatal("lost creation request correlation")
			}
			if test.wantError {
				var failure protocol.ErrorPayload
				if response.Type != protocol.TypeError || response.DecodePayload(&failure) != nil || failure.Code != protocol.ErrRulesUnavailable {
					t.Fatalf("EDH Forge room was admitted: %s %s", response.Type, response.Payload)
				}
				if len(handler.hub.ListRooms()) != 0 {
					t.Fatal("rejected room was published")
				}
				return
			}
			var created protocol.RoomCreated
			if response.Type != protocol.TypeRoomCreated || response.DecodePayload(&created) != nil {
				t.Fatalf("supported room rejected: %s %s", response.Type, response.Payload)
			}
			if created.Settings.Format != test.format || created.Settings.RulesMode != test.rulesMode {
				t.Fatalf("room authority or format changed: %+v", created.Settings)
			}
			host.recvType(protocol.TypeRoomSnapshot)
		})
	}
}

func TestHubAdmitsEDHForgeRooms(t *testing.T) {
	for _, hosting := range []string{"", protocol.HostingModeServer} {
		for _, seats := range []int{2, 3, 4} {
			t.Run(fmt.Sprintf("%s/%d", hosting, seats), func(t *testing.T) {
				hub := NewHub()
				host := &Session{ConnectionID: "host", DisplayName: "Host"}
				r, _, _, entry, err := hub.CreateRoomWithHostingMode("EDH", protocol.FormatEDH,
					protocol.DeckFormatCommander, protocol.MatchBO1, protocol.CardLoadBackground,
					protocol.RulesModeForge, hosting, seats, true, false, "", host)
				if entry != nil {
					entry.opMu.Unlock()
				}
				if err != nil || r == nil || r.RulesMode != protocol.RulesModeForge || r.MatchMode != protocol.MatchBO1 || r.MaxSeats != seats {
					t.Fatalf("hub rejected EDH Forge room: %v %v", r, err)
				}
				if host.Room() != r || len(hub.ListRooms()) != 1 {
					t.Fatal("admission did not publish and bind the room")
				}
			})
		}
	}
}

func TestClusterRejectsUnknownForgeBeforeRouting(t *testing.T) {
	servers, handlers := clusterServers(t)
	for _, hosting := range []string{"", protocol.HostingModeServer, protocol.HostingModePlayer} {
		t.Run(hosting, func(t *testing.T) {
			host := dial(t, servers[0])
			defer host.close()
			clusterHello(host, "Host")
			request, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{
				Name: "unknown-format rules", Format: "unsupported", DeckFormat: protocol.DeckFormatCommander,
				RulesMode: protocol.RulesModeForge, HostingMode: hosting, MatchMode: protocol.MatchBO1,
			})
			request.ID = "unsupported-create"
			host.send(request)
			response := host.recvType(protocol.TypeSessionRoute, protocol.TypeError)
			var failure protocol.ErrorPayload
			if response.ID != request.ID || response.Type != protocol.TypeError ||
				response.DecodePayload(&failure) != nil || failure.Code != protocol.ErrUnsupportedFormat {
				t.Fatalf("unsupported room reached allocation or routing: %s %s", response.Type, response.Payload)
			}
			for _, handler := range handlers {
				if len(handler.hub.ListRooms()) != 0 {
					t.Fatal("unsupported room was created on a cluster node")
				}
			}
			// Admission errors must keep the connection in the lobby for a valid retry.
			host.send(clusterRoomCreate())
			if response := host.recvType(protocol.TypeSessionRoute, protocol.TypeError); response.Type != protocol.TypeSessionRoute {
				t.Fatalf("rejection prevented a supported retry: %s", response.Payload)
			}
		})
	}
}

func TestClusterTargetRejectsUnsupportedForgeCreationGrant(t *testing.T) {
	servers, handlers := clusterServers(t)
	request, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{
		Name: "Unsupported format", Format: "unsupported",
		DeckFormat: protocol.DeckFormatCommander, RulesMode: protocol.RulesModeForge,
		HostingMode: protocol.HostingModeServer, MatchMode: protocol.MatchBO1,
	})
	request.ID = "previous-create"
	ctx := context.Background()
	if err := handlers[1].clusterAgent.Publish(ctx, ""); err != nil {
		t.Fatal(err)
	}
	// A valid placement ticket must not bypass target-side format validation.
	allocation, err := handlers[0].clusterAgent.Do(ctx, cluster.Request{
		Operation: "allocate", Target: "N2", CommandType: request.Type,
		Digest: clusterDigest(request), Demand: cluster.Demand{Rooms: 1},
	})
	if err != nil {
		t.Fatal(err)
	}
	route, _ := protocol.NewEnvelope(protocol.TypeSessionRoute, protocol.SessionRoute{
		URL: allocation.Ticket.URL, Realm: "cluster-integration",
		Ticket: allocation.Ticket.Token, NodeID: allocation.Ticket.NodeID,
	})
	host := routedClient(t, servers[1], route, "")
	defer host.close()
	host.send(request)
	response := host.recvType(protocol.TypeRoomCreated, protocol.TypeError)
	var failure protocol.ErrorPayload
	if response.ID != request.ID || response.Type != protocol.TypeError ||
		response.DecodePayload(&failure) != nil || failure.Code != protocol.ErrUnsupportedFormat {
		t.Fatalf("target admitted an unsupported-format Forge grant: %s %s", response.Type, response.Payload)
	}
	if len(handlers[1].hub.ListRooms()) != 0 {
		t.Fatal("target published the rejected room")
	}
	host.send(clusterRoomCreate())
	if response := host.recvType(protocol.TypeRoomCreated, protocol.TypeError); response.Type != protocol.TypeRoomCreated {
		t.Fatalf("rejected grant remained attached to the session: %s", response.Payload)
	}
}
