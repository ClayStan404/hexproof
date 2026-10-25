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

func TestNewAgentPreservesOrdinaryAllocationWithFrozenCoordinator(t *testing.T) {
	for _, capability := range []string{"forge", "player", "both"} {
		t.Run(capability, func(t *testing.T) {
			cfg := testConfig()
			oldCfg := legacyConfig(cfg)
			coordinator, err := legacy.New(oldCfg)
			if err != nil {
				t.Fatal(err)
			}
			remote := newRemotePeer(t, cfg, legacy.HTTPHandler(coordinator, oldCfg))
			snapshot := report()
			snapshot.ForgeAI, snapshot.PlayerHosting = true, true
			snapshot.ForgeDuelAI = capability != "player"
			snapshot.PlayerHostedDuelAI = capability != "forge"
			agent := Start(remote, "N1", func() Report { return snapshot })
			defer agent.Close()
			if !agent.Status().Ready || agent.Capabilities().DuelAIPlacement {
				t.Fatal("legacy coordinator broke readiness or advertised Duel AI")
			}
			for _, demand := range []Demand{{ForgeDuelAI: true, ForgeAI: true, Forge: 1, Rooms: 1}, {PlayerHostedDuelAI: true, PlayerHosting: true, Rooms: 1}} {
				if _, err = agent.Do(t.Context(), allocation("", "", demand)); err != ErrUnsupported {
					t.Fatal("unsupported Duel demand was not rejected locally", err)
				}
			}
			out, err := agent.Do(t.Context(), allocation("", "", Demand{Rooms: 1}))
			if err != nil || out.Ticket == nil || out.Ticket.NodeID != "N1" {
				t.Fatalf("ordinary allocation failed: %+v %v", out, err)
			}
			agent.mu.Lock()
			generation := agent.generation
			agent.mu.Unlock()
			// Raw unnegotiated extension fields remain forbidden by the real old decoder.
			for _, extended := range []Report{
				{ForgeDuelAI: true}, {PlayerHostedDuelAI: true},
			} {
				_, err = remote.Do(t.Context(), Request{RPCVersion: RPCVersion, Operation: "report", NodeID: "N1", Generation: generation, ReportSequence: 99, Report: &extended})
				if err != ErrInvalid {
					t.Fatal("frozen strict decoder unexpectedly accepted extended report", err)
				}
			}
		})
	}
}

func TestFrozenAgentUsesNewCoordinatorWithoutAdvertisingDuelAI(t *testing.T) {
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
	snapshot := legacyReport(t)
	agent := legacy.Start(remote, "N1", func() legacy.Report { return snapshot })
	defer agent.Close()
	if !agent.Status().Ready {
		t.Fatal("frozen agent could not register/report through new HTTP")
	}
	q := allocation("", "", Demand{Rooms: 1})
	out, err := agent.Do(t.Context(), legacy.Request{Operation: q.Operation, CommandType: q.CommandType, Digest: q.Digest, AccountID: q.AccountID, Demand: legacy.Demand{Rooms: 1}})
	if err != nil || out.Ticket == nil || out.Ticket.NodeID != "N1" {
		t.Fatalf("old agent ordinary allocation: %+v %v", out, err)
	}
	// A new caller cannot treat the old hub's ordinary AI/hosting as Duel AI support.
	coordinator.mu.Lock()
	generation := coordinator.states["N1"].generation
	coordinator.mu.Unlock()
	for _, demand := range []Demand{{Rooms: 1, Forge: 1, ForgeAI: true, ForgeDuelAI: true}, {Rooms: 1, PlayerHosting: true, PlayerHostedDuelAI: true}} {
		if _, err = coordinator.Do(t.Context(), allocation("N1", generation, demand)); err != ErrFull {
			t.Fatal("legacy node was selected for unsupported Duel AI", err)
		}
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

func TestDuelNegotiationFollowsCoordinatorRegistrationGeneration(t *testing.T) {
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
	if !agent.Capabilities().DuelAIPlacement {
		t.Fatal("new coordinator did not negotiate support")
	}
	useLegacy.Store(true)
	if err = agent.Publish(context.Background(), ""); err != ErrRegistration {
		t.Fatal("replacement coordinator did not revoke old registration", err)
	}
	if agent.Capabilities().DuelAIPlacement {
		t.Fatal("revoked generation retained Duel AI negotiation")
	}
	if err = agent.Publish(t.Context(), ""); err != nil || !agent.Status().Ready || agent.Capabilities().DuelAIPlacement {
		t.Fatal("legacy replacement did not recover ordinary reporting", err)
	}
	if _, err = agent.Do(t.Context(), allocation("", "", Demand{Rooms: 1})); err != nil {
		t.Fatal("ordinary placement failed after downgrade", err)
	}
	useLegacy.Store(false)
	current.mu.Lock()
	current.states = map[string]nodeState{}
	current.mu.Unlock()
	if err = agent.Publish(t.Context(), ""); err != ErrRegistration {
		t.Fatal("upgraded coordinator did not require new registration", err)
	}
	if err = agent.Publish(t.Context(), ""); err != nil || !agent.Capabilities().DuelAIPlacement {
		t.Fatal("fresh generation did not enable negotiated support", err)
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
	request := httptest.NewRequest(http.MethodPost, "/", strings.NewReader(`{"rpcVersion":"hexproof.cluster.v1","operation":"register","nodeId":"N1","unexpected":true}`))
	request.Header.Set("Authorization", "Bearer "+cfg.Key)
	request.Header.Set("X-Hexproof-Cluster-Realm", cfg.Realm)
	response := httptest.NewRecorder()
	HTTPHandler(coordinator, cfg).ServeHTTP(response, request)
	if response.Code != http.StatusBadRequest || len(coordinator.states) != 0 {
		t.Fatal("unknown request fields reached registration")
	}
}
