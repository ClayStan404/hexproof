// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package cluster

import (
	"context"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
)

func testConfig() Config {
	return Config{Realm: "cluster-test", NodeID: "N1", Key: strings.Repeat("k", 32), Nodes: []Node{
		{ID: "N1", Name: "One", URL: "ws://127.0.0.1:1111/ws", Weight: 1},
		{ID: "N2", Name: "Two", URL: "ws://127.0.0.1:2222/ws", Weight: 1},
	}}
}

func report() Report {
	return Report{Version: "test", MaxRooms: 4, MaxEvents: 4, MaxConnections: 100, MaxForge: 4, Forge: true,
		MemoryMB: 4096, Resources: map[string][]protocol.AccountResource{}}
}

func register(t *testing.T, c *Coordinator, id string, r Report) string {
	t.Helper()
	out, err := c.Do(context.Background(), Request{Operation: "register", NodeID: id})
	if err != nil {
		t.Fatal(err)
	}
	_, err = c.Do(context.Background(), Request{Operation: "report", ReportSequence: 1, NodeID: id, Generation: out.Generation, Report: &r})
	if err != nil {
		t.Fatal(err)
	}
	return out.Generation
}

func allocation(node, generation string, demand Demand) Request {
	return Request{Operation: "allocate", NodeID: node, Generation: generation, Demand: demand,
		CommandType: protocol.TypeRoomCreate, Digest: strings.Repeat("a", 64), AccountID: "account-one"}
}

func TestConcurrentReservationsBoundCapacity(t *testing.T) {
	c, _ := New(testConfig())
	generation := register(t, c, "N1", report())
	register(t, c, "N2", report())
	var accepted atomic.Int64
	var wg sync.WaitGroup
	for i := 0; i < 48; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := c.Do(context.Background(), allocation("N1", generation, Demand{Rooms: 1, Forge: 1}))
			if err == nil {
				accepted.Add(1)
			} else if err != ErrFull {
				t.Error(err)
			}
		}()
	}
	wg.Wait()
	if accepted.Load() != 8 {
		t.Fatalf("reserved %d slots, want exactly 8", accepted.Load())
	}
}

func TestPlacementCapabilitiesLoadVersionAndExpiry(t *testing.T) {
	c, _ := New(testConfig())
	now := time.Now()
	c.now = func() time.Time { return now }
	one, two := report(), report()
	one.Forge = false
	two.ForgeAI = true
	g1 := register(t, c, "N1", one)
	g2 := register(t, c, "N2", two)
	q := allocation("N1", g1, Demand{Rooms: 1, Forge: 1, ForgeAI: true})
	out, err := c.Do(context.Background(), q)
	if err != nil || out.Ticket.NodeID != "N2" {
		t.Fatalf("runtime placement: %+v %v", out, err)
	}
	two.MemoryMB = 100
	_, _ = c.Do(context.Background(), Request{Operation: "report", ReportSequence: 2, NodeID: "N2", Generation: g2, Report: &two})
	if _, err := c.Do(context.Background(), q); err != ErrFull {
		t.Fatal("low-memory node selected", err)
	}
	two.MemoryMB = 4096
	two.Version = "different"
	_, _ = c.Do(context.Background(), Request{Operation: "report", ReportSequence: 3, NodeID: "N2", Generation: g2, Report: &two})
	if _, err := c.Do(context.Background(), q); err != ErrFull {
		t.Fatal("different-version node selected", err)
	}
	now = now.Add(NodeLifetime)
	if _, err := c.Do(context.Background(), allocation("N1", g1, Demand{Rooms: 1})); err != ErrFull {
		t.Fatal("expired node selected", err)
	}
}

func TestTicketIdentitySingleUseCompletionAndFencing(t *testing.T) {
	c, _ := New(testConfig())
	r := report()
	r.MaxRooms = 1
	g := register(t, c, "N1", r)
	out, err := c.Do(context.Background(), allocation("N1", g, Demand{Rooms: 1}))
	if err != nil {
		t.Fatal(err)
	}
	q := Request{Operation: "take", NodeID: "N1", Generation: g, Token: out.Ticket.Token, AccountID: "wrong-account"}
	if _, err := c.Do(context.Background(), q); err != ErrInvalid {
		t.Fatal("cross-account ticket", err)
	}
	q.AccountID = "account-one"
	if _, err := c.Do(context.Background(), q); err != nil {
		t.Fatal(err)
	}
	if _, err := c.Do(context.Background(), q); err != ErrInvalid {
		t.Fatal("reused ticket", err)
	}
	if _, err := c.Do(context.Background(), allocation("N1", g, Demand{Rooms: 1})); err != ErrFull {
		t.Fatal("taken lease released too early", err)
	}
	_, err = c.Do(context.Background(), Request{Operation: "report", ReportSequence: 2, NodeID: "N1", Generation: g, Report: &r, Completed: []string{q.Token}})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := c.Do(context.Background(), allocation("N1", g, Demand{Rooms: 1})); err != nil {
		t.Fatal("failed operation did not release reservation", err)
	}
	register(t, c, "N1", r)
	if _, err := c.Do(context.Background(), q); err != ErrFenced {
		t.Fatal("old node not fenced", err)
	}
}

func TestDirectoryNamespacesAndPrivateOwnership(t *testing.T) {
	c, _ := New(testConfig())
	r := report()
	r.Rooms = []protocol.RoomListEntry{{RoomID: "ABCDEF", Name: "Public"}}
	r.Events = []protocol.TournamentListEntry{{TournamentID: "EVENT1", Name: "Public event"}}
	r.Resources["alice"] = []protocol.AccountResource{{Kind: "room", ID: "PRIVATE", Name: "Private"}}
	r.Resources["bob"] = []protocol.AccountResource{{Kind: "cube", ID: "SECRET", Name: "Bob's pod"}}
	g := register(t, c, "N1", r)
	register(t, c, "N2", r)
	r.Rooms[0].Name = "mutated caller slice"
	r.Events[0].Name = "mutated caller event"
	r.Resources["alice"][0].Name = "mutated caller resource"
	delete(r.Resources, "alice")
	out, err := c.Do(context.Background(), Request{Operation: "view", NodeID: "N1", Generation: g, AccountID: "alice"})
	if err != nil || len(out.Rooms) != 2 || len(out.Events) != 2 || len(out.Resources) != 2 {
		t.Fatalf("view: %+v %v", out, err)
	}
	if out.Rooms[0].RoomID != "N1:ABCDEF" || out.Rooms[1].RoomID != "N2:ABCDEF" || out.Rooms[0].Name != "Public" {
		t.Fatal(out.Rooms)
	}
	for _, event := range out.Events {
		if event.Name != "Public event" {
			t.Fatal("published event retained caller storage", event)
		}
	}
	for _, resource := range out.Resources {
		if resource.Name != "Private" {
			t.Fatal("another account leaked", resource)
		}
	}
	guest, _ := c.Do(context.Background(), Request{Operation: "view", NodeID: "N1", Generation: g})
	if len(guest.Resources) != 0 {
		t.Fatal("guest received account locations")
	}
}

func TestRemoteAuthenticationAndCoordinatorRestart(t *testing.T) {
	cfg := testConfig()
	c, _ := New(cfg)
	srv := httptest.NewServer(HTTPHandler(c, cfg))
	defer srv.Close()
	cfg.Coordinator = srv.URL
	remote, err := NewRemote(cfg)
	if err != nil {
		t.Fatal(err)
	}
	a := Start(remote, cfg.NodeID, report)
	defer a.Close()
	if view, err := a.Do(context.Background(), Request{Operation: "view"}); err != nil || view.Rooms == nil || view.Events == nil || view.Resources == nil {
		t.Fatal("empty public collections must remain arrays across HTTP", view, err)
	}
	c.mu.Lock()
	c.states = map[string]nodeState{}
	c.mu.Unlock()
	if err := a.Publish(context.Background(), ""); err != ErrRegistration {
		t.Fatal(err)
	}
	if err := a.Publish(context.Background(), ""); err != nil {
		t.Fatal("registration not rebuilt", err)
	}
	register(t, c, cfg.NodeID, report())
	if err := a.Publish(context.Background(), ""); err != ErrFenced {
		t.Fatal(err)
	}
	if err := a.Publish(context.Background(), ""); err != ErrFenced {
		t.Fatal("fenced agent stole registration back", err)
	}
	cfg.Key = strings.Repeat("z", 32)
	wrong, _ := NewRemote(cfg)
	if _, err := wrong.Do(context.Background(), Request{Operation: "register", NodeID: cfg.NodeID}); err != ErrUnavailable {
		t.Fatal("wrong key accepted", err)
	}
}

func TestConfigRejectsUntrustedDestinations(t *testing.T) {
	for _, url := range []string{"ws://example.org/ws", "wss://user:secret@example.org/ws", "wss://example.org/ws?token=x"} {
		cfg := testConfig()
		cfg.Nodes[0].URL = url
		if cfg.Validate() == nil {
			t.Fatal("accepted", url)
		}
	}
	if node, local, ok := SplitCode(" n2:abcdef "); !ok || node != "N2" || local != "ABCDEF" {
		t.Fatal(node, local, ok)
	}
	for _, code := range []string{"N:ABCDEF", "N1:../ws", "N1:ABC:DEF"} {
		if _, _, ok := SplitCode(code); ok {
			t.Fatal(code)
		}
	}
}

func TestAbandonedTicketExpiryAndConnectionReservations(t *testing.T) {
	c, _ := New(testConfig())
	now := time.Now()
	c.now = func() time.Time { return now }
	one, two := report(), report()
	one.MaxConnections, one.Connections = 1, 1
	two.MaxConnections = 1
	g := register(t, c, "N1", one)
	register(t, c, "N2", two)
	local := allocation("N1", g, Demand{Rooms: 1})
	local.Target = "N1"
	if _, err := c.Do(context.Background(), local); err != nil {
		t.Fatal("existing local connection charged again", err)
	}
	remote := allocation("N1", g, Demand{})
	remote.Target = "N2"
	if _, err := c.Do(context.Background(), remote); err != nil {
		t.Fatal(err)
	}
	if _, err := c.Do(context.Background(), remote); err != ErrFull {
		t.Fatal("incoming connection reservation ignored", err)
	}
	now = now.Add(TicketLifetime)
	for id, state := range c.states {
		state.seen = now
		c.states[id] = state
	}
	if _, err := c.Do(context.Background(), remote); err != nil {
		t.Fatal("expired incoming ticket kept capacity", err)
	}
}

func TestDelayedReportCannotReopenReservedCapacity(t *testing.T) {
	c, _ := New(testConfig())
	stale := report()
	generation := register(t, c, "N1", stale)
	fresh := report()
	fresh.RoomCount = fresh.MaxRooms
	for _, q := range []Request{
		{Operation: "report", NodeID: "N1", Generation: generation, ReportSequence: 3, Report: &fresh},
		{Operation: "report", NodeID: "N1", Generation: generation, ReportSequence: 2, Report: &stale},
	} {
		if _, err := c.Do(context.Background(), q); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := c.Do(context.Background(), allocation("N1", generation, Demand{Rooms: 1})); err != ErrFull {
		t.Fatal("delayed snapshot reopened full capacity", err)
	}
}

func TestPlacementAvoidsFailedClientProbe(t *testing.T) {
	cfg := testConfig()
	cfg.Nodes[1].Weight = 100
	c, _ := New(cfg)
	g := register(t, c, "N1", report())
	register(t, c, "N2", report())
	q := allocation("N1", g, Demand{Rooms: 1})
	q.Latency = map[string]int{cfg.Nodes[0].URL: 30, cfg.Nodes[1].URL: -1}
	out, err := c.Do(context.Background(), q)
	if err != nil || out.Ticket.NodeID != "N1" {
		t.Fatal("failed endpoint won over reachable node", out, err)
	}
}
