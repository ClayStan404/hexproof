// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package homenode

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/pion/logging"
	"github.com/pion/turn/v5"
)

func TestConfigurationRejectsArbitraryDestinations(t *testing.T) {
	valid := NodeConfig{NodeID: "home", Token: strings.Repeat("a", 32), GatewayURL: "wss://gateway.example/home/register", BackendURL: "ws://127.0.0.1:1234/ws", HealthURL: "http://127.0.0.1:1234/healthz"}
	if valid.Validate() != nil {
		t.Fatal("valid config rejected")
	}
	for _, endpoint := range []string{"ws://example.org/ws", "ws://localhost/ws", "ws://127.0.0.1/ws?target=other", "ws://u:p@127.0.0.1/ws", "ws://127.0.0.1/ws#fragment"} {
		copy := valid
		copy.BackendURL = endpoint
		if copy.Validate() == nil {
			t.Errorf("unsafe backend accepted: %q", endpoint)
		}
	}
	for _, endpoint := range []string{"ws://gateway.example/home/home/ws", "wss://gateway.example/home/home/ws?target=127.0.0.1", "wss://gateway.example/home/home/ws?engine=1&ai=1"} {
		if _, err := homeURL(endpoint); err == nil {
			t.Errorf("unsafe home URL accepted: %q", endpoint)
		}
	}
	for _, query := range []string{"", "engine=1", "ai=1"} {
		q, _ := url.ParseQuery(query)
		if !validQuery(q) {
			t.Error("valid helper query rejected")
		}
	}
}

func TestGatewayAuthenticationFencingHealthAndLimits(t *testing.T) {
	g, err := NewGateway(GatewayConfig{Nodes: map[string]string{"home": strings.Repeat("a", 32)}, MaxSessions: 2, MaxSessionsPerNode: 2, MaxSessionsPerIP: 1})
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(g)
	defer server.Close()
	defer g.Close()
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	endpoint := "ws" + strings.TrimPrefix(server.URL, "http")
	if conn, err := dial(ctx, endpoint+"/home/register", http.Header{"X-Hexproof-Node": []string{"home"}, "Authorization": []string{"Bearer invalid"}}); err == nil {
		conn.CloseNow()
		t.Fatal("invalid registration accepted")
	}
	register := func() *websocket.Conn {
		conn, err := dial(ctx, endpoint+"/home/register", http.Header{"X-Hexproof-Node": []string{"home"}, "Authorization": []string{"Bearer " + strings.Repeat("a", 32)}})
		if err != nil {
			t.Fatal(err)
		}
		if writeFrame(ctx, conn, frame{Type: "health", Health: json.RawMessage(`{"ok":true,"capabilities":{"forge":true}}`)}) != nil {
			t.Fatal("health failed")
		}
		return conn
	}
	first := register()
	defer first.CloseNow()
	waitHomeHealth(t, server.URL+"/home/home/healthz")
	session := g.reserve(ctx, "home", "192.0.2.2")
	if session == nil {
		t.Fatal("valid session refused")
	}
	defer g.release(session)
	if g.reserve(ctx, "home", "192.0.2.2") != nil {
		t.Fatal("per-IP connection limit bypassed")
	}
	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/home/attach", nil)
	request.Header.Set("X-Hexproof-Session", session.id)
	request.Header.Set("X-Hexproof-Node", "other")
	request.Header.Set("Authorization", "Bearer "+session.token)
	g.ServeHTTP(response, request)
	if response.Code != http.StatusUnauthorized || session.claimed {
		t.Fatal("cross-node attachment consumed grant")
	}
	second := register()
	defer second.CloseNow()
	select {
	case <-session.ctx.Done():
	case <-ctx.Done():
		t.Fatal("registration replacement did not fence prior sessions")
	}
	waitHomeHealth(t, server.URL+"/home/home/healthz")
	g.mu.Lock()
	g.nodes["home"].healthAt = time.Now().Add(-31 * time.Second)
	g.mu.Unlock()
	response = httptest.NewRecorder()
	g.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/home/home/healthz", nil))
	if response.Code != 503 || response.Header().Get("X-Hexproof-Capabilities") != "" || strings.Contains(response.Body.String(), "forge") {
		t.Fatal("stale health was advertised")
	}
	if g.reserve(ctx, "home", "192.0.2.3") != nil {
		t.Fatal("stale node accepted a client")
	}
}

func TestIngressIPAndTURNGrantIsolation(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/", nil)
	request.RemoteAddr = "192.0.2.3:1234"
	request.Header.Set("X-Real-IP", "198.51.100.1")
	if remoteIP(request) != "192.0.2.3" {
		t.Fatal("public client spoofed IP")
	}
	request.RemoteAddr = "127.0.0.1:1234"
	if remoteIP(request) != "198.51.100.1" {
		t.Fatal("trusted local proxy IP lost")
	}
	config := GatewayConfig{Nodes: map[string]string{"home": strings.Repeat("a", 32)}, TURNURLs: []string{"turn:relay.example:3478?transport=udp"}, TURNSecret: strings.Repeat("b", 32)}
	if config.Validate() != nil {
		t.Fatal("TURN config invalid")
	}
	a := config.peerGrant("home", "session", randomID(), randomID(), true, false)
	b := config.peerGrant("home", "session", randomID(), randomID(), false, false)
	if a.TURN[0].Username == b.TURN[0].Username || a.TURN[0].Credential == b.TURN[0].Credential {
		t.Fatal("TURN endpoint credentials not isolated")
	}
	mac := hmac.New(sha1.New, []byte(config.TURNSecret))
	_, _ = mac.Write([]byte(a.TURN[0].Username))
	if a.TURN[0].Credential != base64.StdEncoding.EncodeToString(mac.Sum(nil)) {
		t.Fatal("REST credential does not match coturn")
	}
}

type echoFixture struct {
	url            string
	backendHeaders chan http.Header
	gateway        *Gateway
}

func startEchoHome(t *testing.T, configurations ...GatewayConfig) echoFixture {
	t.Helper()
	headers := make(chan http.Header, 16)
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/healthz" {
			w.Header().Set("X-Hexproof-Capabilities", `{"forge":true,"playerHosting":true}`)
			_, _ = w.Write([]byte("ok\n"))
			return
		}
		conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{CompressionMode: websocket.CompressionDisabled})
		if err != nil {
			return
		}
		defer conn.CloseNow()
		conn.SetReadLimit(16 << 20)
		select {
		case headers <- r.Header.Clone():
		default:
		}
		for {
			kind, raw, err := conn.Read(r.Context())
			if err != nil {
				return
			}
			if conn.Write(r.Context(), kind, raw) != nil {
				return
			}
		}
	}))
	config := GatewayConfig{Nodes: map[string]string{"home": strings.Repeat("a", 32)}}
	if len(configurations) > 0 {
		config = configurations[0]
		config.Nodes = map[string]string{"home": strings.Repeat("a", 32)}
	}
	g, err := NewGateway(config)
	if err != nil {
		t.Fatal(err)
	}
	public := httptest.NewServer(g)
	ctx, cancel := context.WithCancel(t.Context())
	done := make(chan struct{})
	go func() {
		defer close(done)
		_ = RunNode(ctx, NodeConfig{NodeID: "home", Token: strings.Repeat("a", 32), GatewayURL: "ws" + strings.TrimPrefix(public.URL, "http") + "/home/register", BackendURL: "ws" + strings.TrimPrefix(backend.URL, "http") + "/ws", HealthURL: backend.URL + "/healthz"})
	}()
	t.Cleanup(func() {
		cancel()
		g.Close()
		public.Close()
		backend.Close()
		select {
		case <-done:
		case <-time.After(3 * time.Second):
			t.Error("node did not stop")
		}
	})
	waitHomeHealth(t, public.URL+"/home/home/healthz")
	return echoFixture{url: "ws" + strings.TrimPrefix(public.URL, "http") + "/home/home/ws", backendHeaders: headers, gateway: g}
}

func waitHomeHealth(t *testing.T, endpoint string) {
	t.Helper()
	deadline := time.Now().Add(4 * time.Second)
	for time.Now().Before(deadline) {
		response, err := http.Get(endpoint)
		if err == nil {
			body, _ := io.ReadAll(response.Body)
			_ = response.Body.Close()
			if response.StatusCode == 200 && string(body) == "ok\n" && response.Header.Get("X-Hexproof-Capabilities") != "" {
				return
			}
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("home node did not publish healthy backend")
}

func TestDirectAndWSSFallbackCarryIndependentSessions(t *testing.T) {
	fixture := startEchoHome(t)
	ctx, cancel := context.WithTimeout(t.Context(), 25*time.Second)
	defer cancel()
	for _, relay := range []bool{false, true} {
		name := "direct"
		if relay {
			name = "relay"
		}
		t.Run(name, func(t *testing.T) {
			transport, err := connect(ctx, ConnectConfig{URL: fixture.url, ForceRelay: relay})
			if err != nil {
				t.Fatal("connection failed", err)
			}
			defer transport.close()
			if transport.transport() != name {
				t.Fatalf("route=%s expected %s", transport.transport(), name)
			}
			payload := []byte(`{"type":"test","private":"` + name + `"}`)
			if transport.send(ctx, payload) != nil {
				t.Fatal("send failed")
			}
			got, err := transport.read(ctx)
			if err != nil || !bytes.Equal(got, payload) {
				t.Fatal("end-to-end payload changed", err)
			}
			select {
			case headers := <-fixture.backendHeaders:
				if headers.Get("X-Forwarded-For") != "127.0.0.1" {
					t.Fatal("original address missing")
				}
			case <-ctx.Done():
				t.Fatal("backend session missing")
			}
		})
	}
}

func TestEngineCompatibilityRetainsLargerPrivateFrames(t *testing.T) {
	fixture := startEchoHome(t)
	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	defer cancel()
	conn, err := dial(ctx, fixture.url+"?engine=1", nil)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.CloseNow()
	conn.SetReadLimit(16 << 20)
	raw := []byte(`{"publication":"` + strings.Repeat("a", (4<<20)+1) + `"}`)
	if err := conn.Write(ctx, websocket.MessageText, raw); err != nil {
		t.Fatal(err)
	}
	_, got, err := conn.Read(ctx)
	if err != nil || !bytes.Equal(got, raw) {
		t.Fatal("private engine frame truncated", err)
	}
}

func TestParentPipeCancellationClosesEstablishedStream(t *testing.T) {
	fixture := startEchoHome(t)
	input, writer := io.Pipe()
	output, reader := io.Pipe()
	done := make(chan error, 1)
	go func() { done <- RunConnectPipe(t.Context(), input, reader); _ = reader.Close() }()
	defer input.Close()
	defer output.Close()
	config, _ := json.Marshal(ConnectConfig{URL: fixture.url, ForceRelay: true})
	_, _ = writer.Write(append(config, '\n'))
	decoder := json.NewDecoder(output)
	var event map[string]any
	if decoder.Decode(&event) != nil || event["state"] != "connected" || event["transport"] != "relay" {
		t.Fatal("missing connection event")
	}
	_ = writer.Close()
	if decoder.Decode(&event) != nil || event["state"] != "closed" {
		t.Fatal("missing serialized close event")
	}
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("stdin EOF did not stop helper")
	}
}

func TestConcurrentCancellationReturnsAllGatewaySlots(t *testing.T) {
	fixture := startEchoHome(t)
	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	defer cancel()
	var wg sync.WaitGroup
	for range 6 {
		wg.Go(func() {
			transport, err := connect(ctx, ConnectConfig{URL: fixture.url, ForceRelay: true})
			if err == nil {
				_ = transport.send(ctx, []byte(`{"test":true}`))
				transport.close()
			}
		})
	}
	wg.Wait()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		fixture.gateway.mu.Lock()
		count := len(fixture.gateway.sessions)
		fixture.gateway.mu.Unlock()
		if count == 0 {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("closed sessions retained gateway slots")
}

func TestRTCFailureClosesGameStreamWithoutSecondBackend(t *testing.T) {
	fixture := startEchoHome(t)
	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	defer cancel()
	transport, err := connect(ctx, ConnectConfig{URL: fixture.url})
	if err != nil {
		t.Fatal(err)
	}
	defer transport.close()
	if transport.transport() != "direct" {
		t.Fatal("test requires established real RTC")
	}
	payload := []byte(`{"type":"mutation","id":"one"}`)
	if transport.send(ctx, payload) != nil {
		t.Fatal("send failed")
	}
	if _, err := transport.read(ctx); err != nil {
		t.Fatal(err)
	}
	<-fixture.backendHeaders
	fixture.gateway.Close()
	if _, err := transport.read(ctx); err == nil {
		t.Fatal("failed RTC did not close game stream")
	}
	select {
	case <-fixture.backendHeaders:
		t.Fatal("transport implicitly started another backend")
	default:
	}
}

func TestParentEOFCancelsPendingRTCSetup(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := websocket.Accept(w, r, nil)
		if err != nil {
			return
		}
		defer conn.CloseNow()
		_, _, _ = conn.Read(r.Context())
	}))
	defer server.Close()
	input, writer := io.Pipe()
	output, reader := io.Pipe()
	done := make(chan error, 1)
	go func() { done <- RunConnectPipe(t.Context(), input, reader); _ = reader.Close() }()
	defer input.Close()
	defer output.Close()
	config, _ := json.Marshal(ConnectConfig{URL: "ws" + strings.TrimPrefix(server.URL, "http") + "/home/home/ws"})
	_, _ = writer.Write(append(config, '\n'))
	_ = writer.Close()
	var event map[string]any
	if json.NewDecoder(output).Decode(&event) != nil || event["state"] != "closed" {
		t.Fatal("setup cancellation missing close event")
	}
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("setup ignored parent EOF")
	}
}

func TestSetupFailureFallsBackBeforeSendingGameMessage(t *testing.T) {
	var signals, backends, messages atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "/signal") {
			signals.Add(1)
			http.Error(w, "unsupported", 404)
			return
		}
		// Dial can return as soon as Accept writes the upgrade response.
		// Count the backend before exposing that response to the client.
		backends.Add(1)
		conn, err := websocket.Accept(w, r, nil)
		if err != nil {
			return
		}
		defer conn.CloseNow()
		kind, raw, err := conn.Read(r.Context())
		if err == nil {
			messages.Add(1)
			_ = conn.Write(r.Context(), kind, raw)
		}
	}))
	defer server.Close()
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	transport, err := connect(ctx, ConnectConfig{URL: "ws" + strings.TrimPrefix(server.URL, "http") + "/home/home/ws"})
	if err != nil {
		t.Fatal(err)
	}
	defer transport.close()
	route, signalCount, backendCount, messageCount := transport.transport(), signals.Load(), backends.Load(), messages.Load()
	if route != "relay" || signalCount != 1 || backendCount != 1 || messageCount != 0 {
		t.Fatalf("fallback created an early game stream: route=%s signals=%d backends=%d messages=%d", route, signalCount, backendCount, messageCount)
	}
	if transport.send(ctx, []byte(`{"id":"only-once"}`)) != nil {
		t.Fatal("send failed")
	}
	if _, err := transport.read(ctx); err != nil || messages.Load() != 1 {
		t.Fatal("fallback duplicated command", err)
	}
}

func TestRTCDecisionBurstRemainsOrderedWhileConsumerIsBusy(t *testing.T) {
	fixture := startEchoHome(t)
	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	defer cancel()
	transport, err := connect(ctx, ConnectConfig{URL: fixture.url})
	if err != nil {
		t.Fatal(err)
	}
	defer transport.close()
	rtc, ok := transport.(*rtcTransport)
	if !ok {
		t.Fatal("test requires RTC")
	}
	for i := range 64 {
		if transport.send(ctx, []byte(fmt.Sprintf(`{"event":%d,"viewer":"owner"}`, i))) != nil {
			t.Fatal("burst send failed")
		}
	}
	deadline := time.Now().Add(time.Second)
	for len(rtc.messages.messages) < 64 && rtc.ctx.Err() == nil && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if len(rtc.messages.messages) != 64 || rtc.ctx.Err() != nil {
		t.Fatal("ordinary burst closed transport before the client consumed it")
	}
	for i := range 64 {
		raw, err := transport.read(ctx)
		if err != nil || string(raw) != fmt.Sprintf(`{"event":%d,"viewer":"owner"}`, i) {
			t.Fatal("decision fanout was lost or reordered", err)
		}
	}
}

func TestHomeTURNUsesGatewayIssuedCredentialsAndCarriesGame(t *testing.T) {
	listener, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	const realm = "hexproof-home-test"
	secret := strings.Repeat("turn-secret-", 4)
	var usersMu sync.Mutex
	users := make(map[string]bool)
	relay, err := turn.NewServer(turn.ServerConfig{
		Realm:         realm,
		LoggerFactory: &logging.DefaultLoggerFactory{Writer: io.Discard, DefaultLogLevel: logging.LogLevelDisabled, ScopeLevels: map[string]logging.LogLevel{}},
		AuthHandler: func(request *turn.RequestAttributes) (string, []byte, bool) {
			parts := strings.Split(request.Username, ":")
			if len(parts) != 4 || parts[1] != "home" || len(parts[2]) != 64 || request.Realm != realm {
				return "", nil, false
			}
			expires, err := strconv.ParseInt(parts[0], 10, 64)
			if err != nil || expires <= time.Now().Unix() {
				return "", nil, false
			}
			mac := hmac.New(sha1.New, []byte(secret))
			_, _ = mac.Write([]byte(request.Username))
			credential := base64.StdEncoding.EncodeToString(mac.Sum(nil))
			usersMu.Lock()
			users[request.Username] = true
			usersMu.Unlock()
			return request.Username, turn.GenerateAuthKey(request.Username, realm, credential), true
		},
		PacketConnConfigs: []turn.PacketConnConfig{{PacketConn: listener, RelayAddressGenerator: &turn.RelayAddressGeneratorStatic{RelayAddress: net.ParseIP("127.0.0.1"), Address: "127.0.0.1"}}},
	})
	if err != nil {
		_ = listener.Close()
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = relay.Close() })
	fixture := startEchoHome(t, GatewayConfig{TURNURLs: []string{"turn:" + listener.LocalAddr().String() + "?transport=udp"}, TURNSecret: secret})
	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	defer cancel()
	transport, err := connect(ctx, ConnectConfig{URL: fixture.url, ForceTURN: true})
	if err != nil {
		t.Fatal("home TURN connection failed", err)
	}
	defer transport.close()
	if transport.transport() != "relay" {
		t.Fatal("forced TURN selected direct candidate")
	}
	raw := []byte(`{"type":"rules.snapshot","private":"` + strings.Repeat("viewer-only", 20000) + `"}`)
	if transport.send(ctx, raw) != nil {
		t.Fatal("TURN game send failed")
	}
	received, err := transport.read(ctx)
	if err != nil || !bytes.Equal(received, raw) {
		t.Fatal("TURN game payload changed", err)
	}
	usersMu.Lock()
	count := len(users)
	usersMu.Unlock()
	if count != 2 {
		t.Fatalf("expected separate node/client credentials, got %d", count)
	}
}
