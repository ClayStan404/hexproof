// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package homenode

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/buildinfo"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/server"
)

type homeGameClient struct {
	t         *testing.T
	ctx       context.Context
	cancel    context.CancelFunc
	transport gameTransport
	messages  chan protocol.Envelope
	done      chan struct{}
	sequence  int
}

func openHomeGameClient(t *testing.T, endpoint string, relay bool) *homeGameClient {
	t.Helper()
	ctx, cancel := context.WithCancel(t.Context())
	transport, err := connect(ctx, ConnectConfig{URL: endpoint, ForceRelay: relay})
	if err != nil {
		cancel()
		t.Fatal("connect home game client:", err)
	}
	client := &homeGameClient{t: t, ctx: ctx, cancel: cancel, transport: transport,
		messages: make(chan protocol.Envelope, 128), done: make(chan struct{})}
	go func() {
		defer close(client.done)
		for {
			raw, err := transport.read(ctx)
			if err != nil {
				return
			}
			envelope, err := protocol.ParseEnvelope(raw)
			if err != nil {
				return
			}
			select {
			case client.messages <- envelope:
			case <-ctx.Done():
				return
			}
		}
	}()
	t.Cleanup(client.close)
	return client
}

func (c *homeGameClient) close() {
	c.cancel()
	c.transport.close()
	select {
	case <-c.done:
	case <-time.After(2 * time.Second):
		c.t.Error("home game reader leaked")
	}
}

func (c *homeGameClient) command(kind string, payload any) {
	c.t.Helper()
	envelope, err := protocol.NewEnvelope(kind, payload)
	if err != nil {
		c.t.Fatal(err)
	}
	c.sequence++
	envelope.ID = fmt.Sprintf("command-%d", c.sequence)
	raw, err := json.Marshal(envelope)
	if err != nil {
		c.t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(c.ctx, 5*time.Second)
	defer cancel()
	if err := c.transport.send(ctx, raw); err != nil {
		c.t.Fatal("home game command:", err)
	}
}

func (c *homeGameClient) receive(kind string) protocol.Envelope {
	c.t.Helper()
	timer := time.NewTimer(8 * time.Second)
	defer timer.Stop()
	for {
		select {
		case envelope := <-c.messages:
			if envelope.Type == protocol.TypeError {
				c.t.Fatalf("home game error while waiting for %s: %s", kind, envelope.Payload)
			}
			if envelope.Type == kind {
				return envelope
			}
		case <-c.done:
			c.t.Fatalf("home transport closed while waiting for %s", kind)
		case <-timer.C:
			c.t.Fatalf("home game did not receive %s", kind)
		}
	}
}

func (c *homeGameClient) hello(name, token string) protocol.SessionWelcome {
	c.command(protocol.TypeSessionHello, protocol.SessionHello{DisplayName: name,
		ClientVersion: buildinfo.Version, Protocol: protocol.ProtocolVersion, ResumeToken: token})
	var welcome protocol.SessionWelcome
	if err := c.receive(protocol.TypeSessionWelcome).DecodePayload(&welcome); err != nil {
		c.t.Fatal(err)
	}
	return welcome
}

func (c *homeGameClient) snapshot() protocol.GameSnapshot {
	var snapshot protocol.GameSnapshot
	if err := c.receive(protocol.TypeGameSnapshot).DecodePayload(&snapshot); err != nil {
		c.t.Fatal(err)
	}
	return snapshot
}

func gameGatewayFixture(t *testing.T) (string, *Gateway) {
	t.Helper()
	config := GatewayConfig{Nodes: map[string]string{
		"first": strings.Repeat("a", 64), "second": strings.Repeat("b", 64)}}
	gateway, err := NewGateway(config)
	if err != nil {
		t.Fatal(err)
	}
	public := httptest.NewServer(gateway)
	t.Cleanup(func() { gateway.Close(); public.Close() })
	for id, token := range config.Nodes {
		hub := server.NewHandler()
		mux := http.NewServeMux()
		mux.Handle("/ws", hub)
		mux.HandleFunc("/healthz", hub.ServeHealth)
		backend := httptest.NewServer(mux)
		ctx, cancel := context.WithCancel(t.Context())
		done := make(chan struct{})
		go func() {
			defer close(done)
			_ = RunNode(ctx, NodeConfig{NodeID: id, Token: token,
				GatewayURL: "ws" + strings.TrimPrefix(public.URL, "http") + "/home/register",
				BackendURL: "ws" + strings.TrimPrefix(backend.URL, "http") + "/ws", HealthURL: backend.URL + "/healthz"})
		}()
		t.Cleanup(func() {
			cancel()
			select {
			case <-done:
			case <-time.After(3 * time.Second):
				t.Error("home node did not stop")
			}
			backend.Close()
			_ = hub.Close()
		})
	}
	deadline := time.Now().Add(5 * time.Second)
	for {
		gateway.mu.Lock()
		ready := len(gateway.nodes) == 2
		for _, node := range gateway.nodes {
			ready = ready && len(node.health) != 0
		}
		gateway.mu.Unlock()
		if ready {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("home hubs did not report ready")
		}
		time.Sleep(10 * time.Millisecond)
	}
	return "ws" + strings.TrimPrefix(public.URL, "http"), gateway
}

func TestHomeMixedRoutesKeepGamePrivacyAndResumeIdentity(t *testing.T) {
	endpoint, gateway := gameGatewayFixture(t)
	url := endpoint + "/home/first/ws"
	host := openHomeGameClient(t, url, false)
	guest := openHomeGameClient(t, url, true)
	observer := openHomeGameClient(t, url, true)
	if host.transport.transport() != "direct" || guest.transport.transport() != "relay" {
		t.Fatal("mixed-route test did not establish direct RTC and WSS relay")
	}
	hostWelcome := host.hello("Host", "")
	guest.hello("Guest", "")
	observer.hello("Observer", "")
	host.command(protocol.TypeRoomCreate, protocol.RoomCreate{Name: "Home transport test",
		Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatCustom, MaxSeats: 2,
		AllowSpectators: true, MatchMode: protocol.MatchBO1})
	var created protocol.RoomCreated
	if err := host.receive(protocol.TypeRoomCreated).DecodePayload(&created); err != nil {
		t.Fatal(err)
	}
	guest.command(protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: created.RoomID})
	guest.receive(protocol.TypeRoomJoined)
	for i, client := range []*homeGameClient{host, guest} {
		card := []protocol.DeckCard{{Name: "Lightning Bolt", Count: 10, SetCode: "M11", CollectorNumber: "149"}}
		if i == 1 {
			card = []protocol.DeckCard{{Name: "Counterspell", Count: 10, SetCode: "MH2", CollectorNumber: "267"}}
		}
		client.command(protocol.TypeDeckSelect, protocol.DeckSelect{Name: "Private deck",
			Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatCustom, Mainboard: card, Sideboard: []protocol.DeckCard{}})
		client.receive(protocol.TypeDeckSelected)
		client.command(protocol.TypePlayerReady, protocol.PlayerReady{Ready: true})
		client.receive(protocol.TypePlayerReadyChanged)
	}
	for _, client := range []*homeGameClient{host, guest} {
		var load protocol.MatchLoadRequired
		if err := client.receive(protocol.TypeMatchLoadRequired).DecodePayload(&load); err != nil {
			t.Fatal(err)
		}
		client.command(protocol.TypeClientLoadComplete, protocol.ClientLoadComplete{LoadID: load.LoadID})
		client.receive(protocol.TypeClientLoadCompleted)
	}
	host.receive(protocol.TypeMatchStarted)
	guest.receive(protocol.TypeMatchStarted)
	hostView, guestView := host.snapshot(), guest.snapshot()
	if len(hostView.Seats) != 2 || len(guestView.Seats) != 2 ||
		len(hostView.Seats[0].Hand) != 7 || len(hostView.Seats[1].Hand) != 0 ||
		len(guestView.Seats[0].Hand) != 0 || len(guestView.Seats[1].Hand) != 7 {
		t.Fatal("mixed routes changed owner/opponent hidden-hand projection")
	}
	observer.command(protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: created.RoomID, AsSpectator: true})
	observer.receive(protocol.TypeRoomJoined)
	observerView := observer.snapshot()
	if len(observerView.Seats[0].Hand) != 0 || len(observerView.Seats[1].Hand) != 0 {
		t.Fatal("relay observer received private hands")
	}
	drawCount := 1
	host.command(protocol.TypeGameDraw, protocol.GameDraw{Count: &drawCount})
	host.receive(protocol.TypeGameDrawn)
	hostView, guestView, observerView = host.snapshot(), guest.snapshot(), observer.snapshot()
	if len(hostView.Seats[0].Hand) != 8 || guestView.Seats[0].HandCount != 8 ||
		len(guestView.Seats[0].Hand) != 0 || observerView.Seats[0].HandCount != 8 || len(observerView.Seats[0].Hand) != 0 {
		t.Fatal("direct action was duplicated or exposed hidden cards through relay")
	}

	// The other operator node must not share either rooms or resume identity.
	other := openHomeGameClient(t, endpoint+"/home/second/ws", true)
	if other.hello("Host", hostWelcome.ResumeToken).Resumed {
		t.Fatal("home reconnect credential crossed node boundary")
	}
	other.command(protocol.TypeRoomList, map[string]any{})
	listed := other.receive(protocol.TypeRoomListed)
	if strings.Contains(string(listed.Payload), created.RoomID) {
		t.Fatal("room was published on a different home hub")
	}
	other.close()

	host.close()
	deadline := time.Now().Add(3 * time.Second)
	for {
		gateway.mu.Lock()
		remaining := len(gateway.sessions)
		gateway.mu.Unlock()
		if remaining == 2 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("old home transport did not release")
		}
		time.Sleep(10 * time.Millisecond)
	}
	var resumed *homeGameClient
	for time.Now().Before(deadline) {
		candidate := openHomeGameClient(t, url, true)
		welcome := candidate.hello("Host", hostWelcome.ResumeToken)
		if welcome.Resumed {
			if welcome.RoomID != created.RoomID || welcome.Seat == nil || *welcome.Seat != 0 {
				t.Fatal("route change resumed a different room or seat")
			}
			resumed = candidate
			break
		}
		candidate.close()
		time.Sleep(10 * time.Millisecond)
	}
	if resumed == nil {
		t.Fatal("relay reconnect did not resume the direct game session")
	}
	resumedView := resumed.snapshot()
	if len(resumedView.Seats[0].Hand) != 8 || len(resumedView.Seats[1].Hand) != 0 {
		t.Fatal("reconnect lost the committed action or changed privacy")
	}
}
