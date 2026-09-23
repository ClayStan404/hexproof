// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package peerlink

import (
	"bytes"
	"context"
	"io"
	"net"
	"strings"
	"testing"
	"time"

	"github.com/pion/logging"
	"github.com/pion/turn/v5"
)

func TestTURNRelayCarriesAuthenticatedOrderedMessages(t *testing.T) {
	listener, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	const realm, username, credential = "hexproof-test", "test-user", "test-credential"
	relay, err := turn.NewServer(turn.ServerConfig{
		Realm: realm,
		LoggerFactory: &logging.DefaultLoggerFactory{Writer: io.Discard,
			DefaultLogLevel: logging.LogLevelDisabled, ScopeLevels: map[string]logging.LogLevel{}},
		AuthHandler: func(request *turn.RequestAttributes) (string, []byte, bool) {
			if request.Username != username || request.Realm != realm {
				return "", nil, false
			}
			return username, turn.GenerateAuthKey(username, realm, credential), true
		},
		PacketConnConfigs: []turn.PacketConnConfig{{
			PacketConn: listener,
			RelayAddressGenerator: &turn.RelayAddressGeneratorStatic{
				RelayAddress: net.ParseIP("127.0.0.1"), Address: "127.0.0.1",
			},
		}},
	})
	if err != nil {
		_ = listener.Close()
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = relay.Close() })
	peers, messages := testTransportPair(t, false, nil, func(_ int, config *Config) {
		config.RelayOnly = true
		config.TURN = []TURNServer{{URLs: []string{"turn:" + listener.LocalAddr().String() + "?transport=udp"}, Username: username, Credential: credential}}
	})
	for sender := range 2 {
		if peers[sender].Transport() != "relay" {
			t.Fatal("forced TURN connection unexpectedly selected a direct route")
		}
		for _, payload := range [][]byte{[]byte(`{"type":"session.hello"}`), bytes.Repeat([]byte("viewer-only-data"), 10000)} {
			ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
			err := peers[sender].Send(ctx, payload)
			if err != nil {
				cancel()
				t.Fatal(err)
			}
			select {
			case received := <-messages[1-sender]:
				if !bytes.Equal(received, payload) {
					t.Fatal("TURN changed or reordered an application message")
				}
			case <-ctx.Done():
				t.Fatal("TURN message was not delivered")
			}
			cancel()
		}
	}
}

func TestTURNConfigurationRejectsInvalidCredentialsAndEndpoints(t *testing.T) {
	valid := TURNServer{URLs: []string{"turn:relay.example:3478?transport=udp", "turns:relay.example:5349?transport=tcp"}, Username: "time:session", Credential: "secret"}
	if err := ValidateTURNServers([]TURNServer{valid}); err != nil {
		t.Fatal(err)
	}
	for _, endpoint := range []string{"stun:relay.example", "turn:user:secret@relay.example", "turn:relay.example/path", "turns:relay.example?transport=udp", "turn:relay.example:0", "turn:relay.example:99999", "turn:relay.example?other=value", "turn:relay.example#fragment"} {
		t.Run(endpoint, func(t *testing.T) {
			candidate := valid
			candidate.URLs = []string{endpoint}
			if ValidateTURNServers([]TURNServer{candidate}) == nil {
				t.Fatal("invalid TURN URL was accepted")
			}
		})
	}
	for _, servers := range [][]TURNServer{
		{valid, valid, valid},
		{{URLs: valid.URLs, Username: "", Credential: "secret"}},
		{{URLs: valid.URLs, Username: "user", Credential: ""}},
		{{URLs: valid.URLs, Username: "user\nlog", Credential: "secret"}},
		{{URLs: valid.URLs, Username: "user", Credential: strings.Repeat("x", 257)}},
		{{Username: "user", Credential: "secret"}},
	} {
		if ValidateTURNServers(servers) == nil {
			t.Fatal("invalid TURN configuration accepted")
		}
	}
	if _, err := New(t.Context(), Config{BindingID: strings.Repeat("a", 64), Token: strings.Repeat("b", 64), RelayOnly: true}, Callbacks{}); err == nil {
		t.Fatal("relay-only transport accepted without a TURN server")
	}
}
