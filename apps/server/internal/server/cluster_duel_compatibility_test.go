// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"net/http/httptest"
	"strings"
	"testing"

	"hexproof/server/internal/buildinfo"
	"hexproof/server/internal/cluster"
	legacy "hexproof/server/internal/cluster/testdata/v1"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
)

// Exercise the new hub's real report, welcome and create path against the
// frozen strict coordinator; no Forge game or external service is started.
func TestClusterDuelAIIsDisabledWithoutBreakingLegacyOrdinaryRooms(t *testing.T) {
	key := strings.Repeat("legacy-cluster-", 3)
	node := cluster.Node{ID: "N1", Name: "One", URL: "ws://127.0.0.1:1111/ws", Weight: 1}
	oldConfig := legacy.Config{Realm: "cluster-integration", NodeID: "N1", Key: key, Nodes: []legacy.Node{{ID: node.ID, Name: node.Name, URL: node.URL, Weight: node.Weight}}}
	old, err := legacy.New(oldConfig)
	if err != nil {
		t.Fatal(err)
	}
	coordinator := httptest.NewServer(legacy.HTTPHandler(old, oldConfig))
	t.Cleanup(coordinator.Close)
	cfg := DefaultConfig()
	cfg.AccountRealm, cfg.AccountServiceKey, cfg.AccountDir = "cluster-integration", key, t.TempDir()
	cfg.AllowPlayerHosting = true
	cfg.Cluster = &cluster.Config{Realm: cfg.AccountRealm, NodeID: "N1", Key: key, Coordinator: coordinator.URL, Nodes: []cluster.Node{node}}
	srv, handler := newConfiguredTestServer(t, cfg)
	// Capability metadata only: the test verifies hub admission, not engine play.
	handler.forgeMu.Lock()
	handler.forgeRuntime = &forge.ProcessConfig{}
	handler.forgeNativeAI, handler.forgeNativeDuelAI = true, true
	handler.forgeMu.Unlock()
	if err = handler.clusterAgent.Publish(context.Background(), ""); err != nil || !handler.clusterAgent.Status().Ready {
		t.Fatal("new hub could not report to frozen coordinator", err)
	}
	_, _, localDuel, localPlayerDuel, _ := handler.welcomeCapabilities(false)
	if !localDuel || !localPlayerDuel {
		t.Fatal("standalone local support was disabled")
	}
	host := dial(t, srv)
	defer host.close()
	hello, _ := protocol.NewEnvelope(protocol.TypeSessionHello, protocol.SessionHello{Protocol: protocol.ProtocolVersion, DisplayName: "Human", ClientVersion: buildinfo.Version, ClusterRealm: cfg.AccountRealm})
	hello.ID = "hello-legacy-cluster"
	host.send(hello)
	var welcome protocol.SessionWelcome
	if err = host.recvType(protocol.TypeSessionWelcome).DecodePayload(&welcome); err != nil {
		t.Fatal(err)
	}
	if !welcome.ForgeAIAvailable || !welcome.PlayerHostingAvailable || welcome.ForgeDuelAIAvailable || welcome.PlayerHostedDuelAIAvailable {
		t.Fatalf("legacy cluster welcome widened unsupported scope: %+v", welcome)
	}
	for _, hosting := range []string{"server", "player"} {
		create, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{Name: "Duel AI", Format: protocol.FormatDuel, DeckFormat: protocol.DeckFormatDuel, MatchMode: protocol.MatchBO1, RulesMode: protocol.RulesModeForge, AISource: protocol.AISourceForge, AIDifficulty: "normal", HostingMode: hosting})
		create.ID = "unsupported-duel-" + hosting
		host.send(create)
		var rejected protocol.ErrorPayload
		if err = host.recvType(protocol.TypeError).DecodePayload(&rejected); err != nil || rejected.Code != protocol.ErrRulesUnavailable {
			t.Fatalf("unsupported Duel AI: %+v %v", rejected, err)
		}
	}
	// Failure of the optional mode must not consume or block ordinary allocation.
	_, id := host.createRoom("Ordinary room", protocol.FormatModern, 2, true, "")
	if id == "" || handler.hub.FindRoom(id) == nil {
		t.Fatal("ordinary room creation failed after unsupported Duel requests")
	}
}
