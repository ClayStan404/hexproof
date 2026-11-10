// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"os"
	"testing"

	"hexproof/server/internal/buildinfo"
	"hexproof/server/internal/protocol"
)

func TestProtocolRejectionPrecedesAuthenticationAndResume(t *testing.T) {
	srv, _ := newTestServer(t)
	for _, offered := range []string{"", "hexproof.v0", "hexproof.v02", "hexproof.v2147483648", "hexproof.v1", "hexproof.v2", "hexproof.v4"} {
		t.Run(offered, func(t *testing.T) {
			peer := dial(t, srv)
			defer peer.close()
			hello, _ := protocol.NewEnvelope(protocol.TypeSessionHello, protocol.SessionHello{
				DisplayName: "Player", ClientVersion: buildinfo.Version, Protocol: offered,
				AccountSession: "must-not-be-authenticated", ResumeToken: "must-not-be-restored",
			})
			hello.ID = "invalid-protocol"
			peer.send(hello)
			response := peer.recvType(protocol.TypeError)
			var failure protocol.ErrorPayload
			_ = response.DecodePayload(&failure)
			want := protocol.ErrInvalidMessage
			if protocol.ValidProtocol(offered) {
				want = protocol.ErrProtocolMismatch
			}
			if response.ID != hello.ID || failure.Code != want {
				t.Fatalf("unexpected failure: %+v", failure)
			}
			if want == protocol.ErrProtocolMismatch && (failure.ClientProtocol != offered || failure.ServerProtocol != protocol.ProtocolVersion) {
				t.Fatalf("missing protocol tuple: %+v", failure)
			}
			// A rejected hello has not bound an account or resumed a session.
			peer.hello("Valid guest")
		})
	}
}

func TestFrozenLegacyHelloRejected(t *testing.T) {
	srv, _ := newTestServer(t)
	for _, legacy := range []string{"v1", "v2"} {
		t.Run(legacy, func(t *testing.T) {
			peer := dial(t, srv)
			defer peer.close()
			data, err := os.ReadFile("../../../../testdata/protocol/legacy-" + legacy + "/session-hello.json")
			if err != nil {
				t.Fatal(err)
			}
			hello, err := protocol.ParseEnvelope(data)
			if err != nil {
				t.Fatal(err)
			}
			peer.send(hello)
			var failure protocol.ErrorPayload
			_ = peer.recvType(protocol.TypeError).DecodePayload(&failure)
			if failure.Code != protocol.ErrProtocolMismatch || failure.ClientProtocol != "hexproof."+legacy || failure.ServerProtocol != protocol.ProtocolVersion {
				t.Fatalf("legacy peer admitted: %+v", failure)
			}
		})
	}
}

func TestV2HelloCannotConsumeClusterTicket(t *testing.T) {
	servers, handlers := clusterServers(t)
	origin := dial(t, servers[0])
	defer origin.close()
	clusterHello(origin, "Host")
	create := clusterRoomCreate()
	origin.send(create)
	route := origin.recvType(protocol.TypeSessionRoute)
	var r protocol.SessionRoute
	if err := route.DecodePayload(&r); err != nil {
		t.Fatal(err)
	}
	rejected := dial(t, servers[1])
	defer rejected.close()
	hello, _ := protocol.NewEnvelope(protocol.TypeSessionHello, protocol.SessionHello{
		Protocol: "hexproof.v2", DisplayName: "Legacy", ClientVersion: buildinfo.Version,
		ClusterRealm: "cluster-integration", ClusterTicket: r.Ticket,
		AccountSession: "must-not-be-authenticated", ResumeToken: "must-not-be-restored",
	})
	hello.ID = "v2-ticket"
	rejected.send(hello)
	var failure protocol.ErrorPayload
	_ = rejected.recvType(protocol.TypeError).DecodePayload(&failure)
	if failure.Code != protocol.ErrProtocolMismatch {
		t.Fatal(failure)
	}
	if len(handlers[1].hub.ListRooms()) != 0 {
		t.Fatal("legacy hello created membership")
	}
	// The exact ticket remains redeemable after the rejected hello.
	target := routedClient(t, servers[1], route, "")
	defer target.close()
	target.send(create)
	if target.recvType(protocol.TypeRoomCreated, protocol.TypeError).Type != protocol.TypeRoomCreated {
		t.Fatal("rejected protocol consumed the ticket")
	}
}
