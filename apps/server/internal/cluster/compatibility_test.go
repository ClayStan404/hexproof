// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package cluster

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestRPCVersionRequiredBeforeRegistration(t *testing.T) {
	c, _ := New(testConfig())
	for _, version := range []string{"", "hexproof.cluster.v2"} {
		out, err := c.Do(context.Background(), Request{RPCVersion: version, Operation: "register", NodeID: "N1"})
		if err != ErrInvalid || out.RPCVersion != RPCVersion || len(c.states) != 0 {
			t.Fatalf("invalid RPC changed state: %+v %v", out, err)
		}
	}
}

func TestApplicationVersionsShareProtocolAndTickets(t *testing.T) {
	c, _ := New(testConfig())
	one, two := report(), report()
	one.Version, two.Version = "1.2.3", "99.0.0"
	two.Rooms = []protocol.RoomListEntry{{RoomID: "ROOM12", Name: "Different release"}}
	one.Forge, two.ForgeAI = false, true
	g1 := register(t, c, "N1", one)
	g2 := register(t, c, "N2", two)
	view, err := c.Do(context.Background(), Request{RPCVersion: RPCVersion, Operation: "view", NodeID: "N1", Generation: g1})
	if err != nil || len(view.Rooms) != 1 || !view.ForgeAI {
		t.Fatalf("compatible release hidden: %+v %v", view, err)
	}
	q := allocation("N1", g1, Demand{Forge: 1})
	q.Target = "N2"
	allocated, err := c.Do(context.Background(), q)
	if err != nil || allocated.Ticket.Protocol != protocol.ProtocolVersion {
		t.Fatalf("allocation: %+v %v", allocated, err)
	}
	changed := two
	changed.Protocol = "hexproof.v3"
	_, err = c.Do(context.Background(), Request{RPCVersion: RPCVersion, Operation: "report", NodeID: "N2", Generation: g2, ReportSequence: 2, Report: &changed})
	if err != ErrInvalid {
		t.Fatal("protocol changed inside registration", err)
	}
	// A new generation may switch protocols, but cannot consume the old grant.
	g2 = register(t, c, "N2", changed)
	_, err = c.Do(context.Background(), Request{RPCVersion: RPCVersion, Operation: "take", NodeID: "N2", Generation: g2, AccountID: q.AccountID, Token: allocated.Ticket.Token})
	if err != ErrInvalid || c.tickets[allocated.Ticket.Token].Taken {
		t.Fatal("cross-generation ticket consumed", err)
	}
	view, err = c.Do(context.Background(), Request{RPCVersion: RPCVersion, Operation: "view", NodeID: "N1", Generation: g1})
	if err != nil || len(view.Rooms) != 0 || view.ForgeAI {
		t.Fatalf("incompatible protocol visible: %+v %v", view, err)
	}
	if _, err = c.Do(context.Background(), q); err != ErrFull {
		t.Fatal("cross-protocol placement", err)
	}
}

func TestRemoteRejectsUnversionedSuccess(t *testing.T) {
	peer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"generation":"must-not-be-used"}`))
	}))
	defer peer.Close()
	config := testConfig()
	config.Coordinator = peer.URL
	remote, err := NewRemote(config)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := remote.Do(context.Background(), Request{RPCVersion: RPCVersion, Operation: "register", NodeID: "N1"}); err == nil {
		t.Fatal("unversioned reply accepted")
	}
}
