// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package cluster

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"

	legacy "hexproof/server/internal/cluster/testdata/v1"
)

func legacyConfig(c Config) legacy.Config {
	old := legacy.Config{Realm: c.Realm, NodeID: c.NodeID, Key: c.Key, Coordinator: c.Coordinator}
	for _, node := range c.Nodes {
		old.Nodes = append(old.Nodes, legacy.Node{ID: node.ID, Name: node.Name, URL: node.URL, Weight: node.Weight})
	}
	return old
}

func legacyReport(t *testing.T) legacy.Report {
	t.Helper()
	r := report()
	r.ForgeAI, r.PlayerHosting = true, true
	raw, err := json.Marshal(r)
	if err != nil {
		t.Fatal(err)
	}
	var old legacy.Report
	if err = json.Unmarshal(raw, &old); err != nil {
		t.Fatal(err)
	}
	return old
}

func newRemotePeer(t *testing.T, cfg Config, handler http.Handler) *Remote {
	t.Helper()
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	cfg.Coordinator = server.URL
	remote, err := NewRemote(cfg)
	if err != nil {
		t.Fatal(err)
	}
	return remote
}

func TestFrozenClusterPeerSources(t *testing.T) {
	var provenance struct {
		Commit string `json:"commit"`
		Files  map[string]struct {
			SHA256 string `json:"sha256"`
		} `json:"files"`
	}
	raw, err := os.ReadFile("testdata/v1/provenance.json")
	if err != nil {
		t.Fatal(err)
	}
	if err = json.Unmarshal(raw, &provenance); err != nil {
		t.Fatal(err)
	}
	if provenance.Commit != "7f6ee48ebdefb15ef64e949e3d22720ba0022842" || len(provenance.Files) != 4 {
		t.Fatal("unexpected frozen peer")
	}
	for name, record := range provenance.Files {
		raw, err = os.ReadFile(filepath.Join("testdata/v1", name))
		if err != nil {
			t.Fatal(err)
		}
		digest := sha256.Sum256(raw)
		if hex.EncodeToString(digest[:]) != record.SHA256 {
			t.Fatalf("frozen peer changed: %s", name)
		}
	}
}

func TestNewAgentRejectsFrozenCoordinatorRPCBaseline(t *testing.T) {
	cfg := testConfig()
	oldCfg := legacyConfig(cfg)
	coordinator, err := legacy.New(oldCfg)
	if err != nil {
		t.Fatal(err)
	}
	remote := newRemotePeer(t, cfg, legacy.HTTPHandler(coordinator, oldCfg))
	agent := Start(remote, "N1", func() Report { return report() })
	defer agent.Close()
	if agent.Status().Ready || agent.Capabilities().DuelAIPlacement {
		t.Fatal("v2 agent admitted by frozen v1 coordinator")
	}
	if err = agent.Publish(t.Context(), ""); err != ErrInvalid {
		t.Fatal("cross-RPC registration was not rejected", err)
	}
	if _, err = agent.Do(t.Context(), allocation("", "", Demand{Rooms: 1})); err != ErrUnavailable {
		t.Fatal("unregistered agent allocated a ticket", err)
	}
	// An unmodified frozen v1 HTTP client observes no registration side effect.
	oldCfg.Coordinator = remote.endpoint
	oldRemote, err := legacy.NewRemote(oldCfg)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = oldRemote.Do(t.Context(), legacy.Request{RPCVersion: legacy.RPCVersion, Operation: "view", NodeID: "N1"}); err != legacy.ErrRegistration {
		t.Fatal("rejected registration changed frozen coordinator state", err)
	}
}

func TestFrozenAgentRejectsNewCoordinatorRPCBaseline(t *testing.T) {
	cfg := testConfig()
	coordinator, err := New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(HTTPHandler(coordinator, cfg))
	defer server.Close()
	oldCfg := legacyConfig(cfg)
	oldCfg.Coordinator = server.URL
	remote, err := legacy.NewRemote(oldCfg)
	if err != nil {
		t.Fatal(err)
	}
	agent := legacy.Start(remote, "N1", func() legacy.Report { return legacyReport(t) })
	defer agent.Close()
	if agent.Status().Ready {
		t.Fatal("frozen v1 agent admitted by v2 coordinator")
	}
	if err = agent.Publish(t.Context(), ""); err != legacy.ErrInvalid {
		t.Fatal("cross-RPC registration was not rejected", err)
	}
	if len(coordinator.states) != 0 || len(coordinator.tickets) != 0 || len(coordinator.createOperations) != 0 {
		t.Fatal("cross-RPC request mutated coordinator state")
	}
}

func TestNewAgentNegotiatesDuelPlacementThroughHTTP(t *testing.T) {
	cfg := testConfig()
	coordinator, err := New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	remote := newRemotePeer(t, cfg, HTTPHandler(coordinator, cfg))
	snapshot := report()
	snapshot.ForgeAI, snapshot.PlayerHosting, snapshot.ForgeDuelAI, snapshot.PlayerHostedDuelAI = true, true, true, true
	agent := Start(remote, "N1", func() Report { return snapshot })
	defer agent.Close()
	capabilities := agent.Capabilities()
	if !agent.Status().Ready || !capabilities.DuelAIPlacement || !capabilities.ForgeDuelAI || !capabilities.PlayerHostedDuelAI {
		t.Fatalf("negotiated capability missing: %+v", capabilities)
	}
	for _, demand := range []Demand{{Rooms: 1, Forge: 1, ForgeAI: true, ForgeDuelAI: true}, {Rooms: 1, PlayerHosting: true, PlayerHostedDuelAI: true}} {
		out, err := agent.Do(t.Context(), allocation("", "", demand))
		if err != nil || out.Ticket == nil || out.Ticket.Demand != demand {
			t.Fatalf("Duel AI placement requirement lost: %+v %v", out, err)
		}
	}
}

func TestCoordinatorRPCDowngradeDoesNotTriggerFallbackRegistration(t *testing.T) {
	cfg := testConfig()
	current, err := New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	oldCfg := legacyConfig(cfg)
	old, err := legacy.New(oldCfg)
	if err != nil {
		t.Fatal(err)
	}
	currentHTTP, oldHTTP := HTTPHandler(current, cfg), legacy.HTTPHandler(old, oldCfg)
	var useLegacy atomic.Bool
	remote := newRemotePeer(t, cfg, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if useLegacy.Load() {
			oldHTTP.ServeHTTP(w, r)
		} else {
			currentHTTP.ServeHTTP(w, r)
		}
	}))
	snapshot := report()
	snapshot.ForgeDuelAI, snapshot.PlayerHostedDuelAI = true, true
	agent := Start(remote, "N1", func() Report { return snapshot })
	defer agent.Close()
	agent.mu.Lock()
	generation := agent.generation
	agent.mu.Unlock()
	useLegacy.Store(true)
	if err = agent.Publish(context.Background(), ""); err != ErrInvalid {
		t.Fatal("RPC downgrade was not rejected", err)
	}
	if _, err = agent.Do(t.Context(), allocation("", "", Demand{Rooms: 1})); err != ErrInvalid {
		t.Fatal("ordinary allocation silently fell back to old RPC", err)
	}
	agent.mu.Lock()
	unchanged := agent.generation == generation
	agent.mu.Unlock()
	if !unchanged {
		t.Fatal("protocol error triggered replacement registration")
	}
	useLegacy.Store(false)
	if err = agent.Publish(t.Context(), ""); err != nil || !agent.Capabilities().DuelAIPlacement {
		t.Fatal("matching RPC did not recover", err)
	}
}

func TestInvalidExtendedReportDoesNotRenegotiateRegistration(t *testing.T) {
	cfg := testConfig()
	coordinator, err := New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	remote := newRemotePeer(t, cfg, HTTPHandler(coordinator, cfg))
	var invalid atomic.Bool
	agent := Start(remote, "N1", func() Report {
		snapshot := report()
		snapshot.ForgeDuelAI = true
		if invalid.Load() {
			snapshot.MaxRooms = -1
		}
		return snapshot
	})
	defer agent.Close()
	agent.mu.Lock()
	generation := agent.generation
	agent.mu.Unlock()
	invalid.Store(true)
	if err = agent.Publish(t.Context(), ""); err != ErrInvalid {
		t.Fatal("invalid report was downgraded or retried", err)
	}
	agent.mu.Lock()
	unchanged := agent.generation == generation
	agent.mu.Unlock()
	if !unchanged || !agent.Capabilities().DuelAIPlacement {
		t.Fatal("ordinary validation failure changed negotiated generation")
	}
}

func TestDuelNegotiationPreservesStrictRequestValidation(t *testing.T) {
	cfg := testConfig()
	coordinator, err := New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(http.MethodPost, "/", strings.NewReader(`{"rpcVersion":"hexproof.cluster.v2","operation":"register","nodeId":"N1","unexpected":true}`))
	request.Header.Set("Authorization", "Bearer "+cfg.Key)
	request.Header.Set("X-Hexproof-Cluster-Realm", cfg.Realm)
	response := httptest.NewRecorder()
	HTTPHandler(coordinator, cfg).ServeHTTP(response, request)
	if response.Code != http.StatusBadRequest || len(coordinator.states) != 0 {
		t.Fatal("unknown request fields reached registration")
	}
}
