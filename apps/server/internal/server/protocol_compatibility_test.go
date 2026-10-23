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
	for _, offered := range []string{"", "hexproof.v0", "hexproof.v02", "hexproof.v2147483648", "hexproof.v1", "hexproof.v3"} {
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
	peer := dial(t, srv)
	defer peer.close()
	data, err := os.ReadFile("../../../../testdata/protocol/legacy-v1/session-hello.json")
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
	if failure.Code != protocol.ErrProtocolMismatch || failure.ClientProtocol != "hexproof.v1" {
		t.Fatalf("legacy peer admitted: %+v", failure)
	}
}
