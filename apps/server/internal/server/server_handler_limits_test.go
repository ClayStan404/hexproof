// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"errors"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/buildinfo"
	"hexproof/server/internal/protocol"

	"github.com/coder/websocket"
)

func TestMapRoomErrorDoesNotExposeArbitraryErrors(t *testing.T) {
	mapped := mapRoomError(errors.New("database detail"))
	code, ok := ErrCode(mapped)
	if !ok || code != protocol.ErrInternal ||
		mapped.Error() != protocol.ErrInternal+": internal server error" {
		t.Fatalf("mapped error = %v, code = %q, ok = %t", mapped, code, ok)
	}
}

func TestClientIPTrustsForwardedHeaderOnlyFromConfiguredProxy(t *testing.T) {
	proxies, err := parseTrustedProxies([]string{"127.0.0.1/32"})
	if err != nil {
		t.Fatalf("parse trusted proxies: %v", err)
	}
	request := httptest.NewRequest("GET", "http://example.test/ws", nil)
	request.RemoteAddr = "127.0.0.1:42000"
	request.Header.Set("X-Forwarded-For", "203.0.113.24, 127.0.0.1")
	if got := clientIP(request, proxies); got != "203.0.113.24" {
		t.Fatalf("trusted proxy client IP = %q", got)
	}

	request.Header.Set("X-Forwarded-For",
		"198.51.100.66, 203.0.113.24")
	if got := clientIP(request, proxies); got != "203.0.113.24" {
		t.Fatalf("spoofed append-mode chain client IP = %q", got)
	}

	request.RemoteAddr = "198.51.100.7:42000"
	request.Header.Set("X-Forwarded-For", "203.0.113.99")
	if got := clientIP(request, proxies); got != "198.51.100.7" {
		t.Fatalf("untrusted forwarded header changed client IP to %q", got)
	}

	if _, err := parseTrustedProxies([]string{"not-a-cidr"}); err == nil {
		t.Fatal("invalid trusted proxy CIDR was accepted")
	}
}

func TestRandomIDGenerationFailureReturnsInternalError(t *testing.T) {
	originalRandomRead := secureRandomRead
	secureRandomRead = func([]byte) (int, error) {
		return 0, errors.New("entropy unavailable")
	}
	t.Cleanup(func() {
		secureRandomRead = originalRandomRead
	})

	if id, err := genRoomID(); err == nil || id != "" {
		t.Fatalf("genRoomID = %q, %v; want empty id and error", id, err)
	}
	if token, err := genResumeToken(); err == nil || token != "" {
		t.Fatalf("genResumeToken = %q, %v; want empty token and error",
			token, err)
	}

	hub := NewHub()
	host := &Session{
		ConnectionID: "host-conn",
		DisplayName:  "Alice",
		Send:         make(chan []byte, 1),
	}
	_, _, _, _, err := hub.CreateRoom(
		"Room", protocol.FormatModern, protocol.MatchBO1,
		protocol.CardLoadPreload, 2, true, false, "", host)
	code, ok := ErrCode(err)
	if !ok || code != protocol.ErrInternal {
		t.Fatalf("CreateRoom error = %v code %q, want %q",
			err, code, protocol.ErrInternal)
	}
}

func TestZoneDumpGrantIsScopedAndOneUse(t *testing.T) {
	newGrant := func() zoneDumpRequest {
		return zoneDumpRequest{
			requesterConnID: "requester",
			roomID:          "ABCDEF",
			targetSeat:      1,
			expiresAt:       time.Now().UTC().Add(time.Minute),
			approved:        true,
			allowedCardIDs:  map[string]struct{}{"allowed-card": {}},
		}
	}
	handler := &Handler{
		zoneDumpRequests: map[string]zoneDumpRequest{
			"allowed": newGrant(),
			"outside": newGrant(),
		},
	}
	allowedSearch := protocol.GameSearchLibrary{
		CardID: "allowed-card",
	}
	if err := handler.consumeZoneDumpGrant(
		"allowed", "requester", "ABCDEF", 1, allowedSearch); err != nil {
		t.Fatalf("consume allowed grant: %v", err)
	}
	if err := handler.consumeZoneDumpGrant(
		"allowed", "requester", "ABCDEF", 1, allowedSearch); err == nil {
		t.Fatal("reused grant succeeded")
	}

	outsideSearch := protocol.GameSearchLibrary{
		CardID: "outside-card",
	}
	err := handler.consumeZoneDumpGrant(
		"outside", "requester", "ABCDEF", 1, outsideSearch)
	code, ok := ErrCode(err)
	if !ok || code != protocol.ErrApprovalExpired {
		t.Fatalf("outside-prefix grant error = %v code %q, want %q",
			err, code, protocol.ErrApprovalExpired)
	}
	if _, retained := handler.zoneDumpRequests["outside"]; !retained {
		t.Fatal("rejected search consumed one-use grant")
	}
	if err := handler.consumeZoneDumpGrant(
		"outside", "requester", "ABCDEF", 1, allowedSearch); err != nil {
		t.Fatalf("retry allowed search after rejection: %v", err)
	}
	if _, retained := handler.zoneDumpRequests["outside"]; retained {
		t.Fatal("successful retry retained one-use grant")
	}
}

func TestZoneDumpGrantValidationDoesNotConsumeBeforeReducerSuccess(t *testing.T) {
	handler := &Handler{
		zoneDumpRequests: map[string]zoneDumpRequest{
			"approval": {
				requesterConnID: "requester",
				roomID:          "ABCDEF",
				targetSeat:      1,
				expiresAt:       time.Now().UTC().Add(time.Minute),
				approved:        true,
				allowedCardIDs:  map[string]struct{}{"allowed-card": {}},
			},
		},
	}
	search := protocol.GameSearchLibrary{CardID: "allowed-card"}
	if err := handler.validateZoneDumpGrant(
		"approval", "requester", "ABCDEF", 1, search); err != nil {
		t.Fatalf("validate grant before reducer: %v", err)
	}
	if _, retained := handler.zoneDumpRequests["approval"]; !retained {
		t.Fatal("validation consumed grant before reducer completed")
	}
	// A reducer rejection deliberately leaves the grant available for a corrected retry.
	if err := handler.validateZoneDumpGrant(
		"approval", "requester", "ABCDEF", 1, search); err != nil {
		t.Fatalf("validate grant for retry: %v", err)
	}
	handler.discardZoneDumpRequest("approval")
	if _, retained := handler.zoneDumpRequests["approval"]; retained {
		t.Fatal("successful reducer completion retained one-use grant")
	}
}

func TestRemoveRoomClearsRoomScopedTransientState(t *testing.T) {
	handler := NewHandler()
	host := &Session{
		ConnectionID: "host-conn",
		DisplayName:  "Alice",
		Send:         make(chan []byte, 1),
	}
	r, _, _, operation, err := handler.hub.CreateRoom(
		"Room", protocol.FormatModern, protocol.MatchBO1,
		protocol.CardLoadPreload, 2, true, false, "", host)
	if err != nil {
		t.Fatalf("create room: %v", err)
	}
	operation.opMu.Unlock()

	timer := time.NewTimer(time.Hour)
	handler.sideboardTimers[r.ID] = timer
	handler.zoneDumpRequests["approval"] = zoneDumpRequest{
		roomID:    r.ID,
		expiresAt: time.Now().UTC().Add(time.Minute),
	}
	handler.publicZoneMoveRequests["public-move"] = publicZoneMoveRequest{
		roomID:    r.ID,
		expiresAt: time.Now().UTC().Add(time.Minute),
	}
	handler.resumeHolds["resume"] = resumeHold{
		token:           "resume",
		oldConnectionID: host.ConnectionID,
		room:            r,
		expiresAt:       time.Now().UTC().Add(time.Minute),
	}

	handler.removeRoom(r)

	if handler.hub.FindRoom(r.ID) != nil {
		t.Fatal("removed room remains registered")
	}
	if len(handler.sideboardTimers) != 0 ||
		len(handler.zoneDumpRequests) != 0 ||
		len(handler.publicZoneMoveRequests) != 0 ||
		len(handler.resumeHolds) != 0 {
		t.Fatalf("room transients remain: timers=%d libraryApprovals=%d publicZoneApprovals=%d holds=%d",
			len(handler.sideboardTimers), len(handler.zoneDumpRequests),
			len(handler.publicZoneMoveRequests),
			len(handler.resumeHolds))
	}
}

func TestReconnectHoldRejectsDepartedMembership(t *testing.T) {
	handler := NewHandler()
	host := &Session{
		ConnectionID: "host-conn",
		DisplayName:  "Alice",
		Send:         make(chan []byte, 1),
	}
	guest := &Session{
		ConnectionID: "guest-conn",
		DisplayName:  "Bob",
		ResumeToken:  "guest-resume",
		Send:         make(chan []byte, 1),
	}
	r, _, _, operation, err := handler.hub.CreateRoom(
		"Room", protocol.FormatModern, protocol.MatchBO1,
		protocol.CardLoadPreload, 2, true, false, "", host)
	if err != nil {
		t.Fatalf("create room: %v", err)
	}
	operation.opMu.Unlock()
	joinOperation, err := handler.hub.beginJoin(r.ID, "")
	if err != nil {
		t.Fatalf("begin join: %v", err)
	}
	if _, _, err := handler.hub.joinRoom(joinOperation, guest, false); err != nil {
		joinOperation.opMu.Unlock()
		t.Fatalf("join room: %v", err)
	}
	joinOperation.opMu.Unlock()

	kickOperation, err := handler.hub.lockRoomOperation(r.ID)
	if err != nil {
		t.Fatalf("lock room for kick: %v", err)
	}
	guestSeat := 1
	if _, err := handler.hub.KickFromRoom(
		host.ConnectionID, &guestSeat, nil, r); err != nil {
		kickOperation.opMu.Unlock()
		t.Fatalf("kick guest: %v", err)
	}
	kickOperation.opMu.Unlock()

	// Simulate ServeHTTP having captured the old room pointer just before the
	// kick completed.
	handler.holdForReconnect(guest, r)

	if guest.Room() != nil {
		t.Fatal("departed session retained its room binding")
	}
	if len(handler.resumeHolds) != 0 {
		t.Fatalf("departed session created %d reconnect hold(s)",
			len(handler.resumeHolds))
	}
}

// dialClient opens a WebSocket against the test server and returns a helper
// that can send/receive envelopes.
type wsClient struct {
	t    *testing.T
	conn *websocket.Conn
}

func (c *wsClient) close() { c.conn.Close(websocket.StatusNormalClosure, "") }

func (c *wsClient) send(env protocol.Envelope) {
	c.t.Helper()
	data, err := env.Marshal()
	if err != nil {
		c.t.Fatalf("marshal: %v", err)
	}
	if err := c.conn.Write(context.Background(), websocket.MessageText, data); err != nil {
		c.t.Fatalf("write: %v", err)
	}
}

// recv reads one envelope with a timeout. Fatals on timeout/parse error.
// The timeout is generous (5s) because -race slows execution and fanout is
// asynchronous; we want flake-free tests, not tight latency bounds.
func (c *wsClient) recv() protocol.Envelope {
	c.t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_, data, err := c.conn.Read(ctx)
	if err != nil {
		c.t.Fatalf("read: %v", err)
	}
	env, err := protocol.ParseEnvelope(data)
	if err != nil {
		c.t.Fatalf("parse %q: %v", data, err)
	}
	return env
}

// recvType reads envelopes until one of the given types arrives, skipping
// snapshots/pings. Fatals if no match within a few messages.
func (c *wsClient) recvType(want ...string) protocol.Envelope {
	c.t.Helper()
	wantSet := make(map[string]bool, len(want))
	for _, w := range want {
		wantSet[w] = true
	}
	for i := 0; i < 8; i++ {
		env := c.recv()
		if wantSet[env.Type] {
			return env
		}
	}
	c.t.Fatalf("no message of type %v after several reads", want)
	return protocol.Envelope{}
}

func newTestServer(t *testing.T) (*httptest.Server, *Handler) {
	t.Helper()
	h := NewHandler()
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	return srv, h
}

func newConfiguredTestServer(t *testing.T, config Config) (*httptest.Server, *Handler) {
	t.Helper()
	h, err := NewHandlerWithConfig(config)
	if err != nil {
		t.Fatalf("new configured handler: %v", err)
	}
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	return srv, h
}

func TestSessionSendOverflowClosesAndCancels(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	session := &Session{Send: make(chan []byte, 1), cancel: cancel}
	if !session.trySend([]byte("first")) {
		t.Fatal("first send unexpectedly failed")
	}
	if session.trySend([]byte("overflow")) {
		t.Fatal("overflow send unexpectedly succeeded")
	}
	select {
	case <-ctx.Done():
	case <-time.After(time.Second):
		t.Fatal("overflow did not cancel the session")
	}
	if session.trySend([]byte("after close")) {
		t.Fatal("closed session accepted another send")
	}
	session.Close() // idempotent
}

func TestConnectionAndRoomLimits(t *testing.T) {
	connectionConfig := DefaultConfig()
	connectionConfig.MaxConnections = 1
	connectionServer, _ := newConfiguredTestServer(t, connectionConfig)
	first := dial(t, connectionServer)
	defer first.close()
	secondConnection, response, err := websocket.Dial(
		context.Background(), wsURL(connectionServer), nil)
	if secondConnection != nil {
		_ = secondConnection.CloseNow()
	}
	if err == nil || response == nil || response.StatusCode != 503 {
		t.Fatalf("second connection err=%v response=%v", err, response)
	}
	_ = response.Body.Close()

	roomConfig := DefaultConfig()
	roomConfig.MaxRooms = 1
	roomServer, _ := newConfiguredTestServer(t, roomConfig)
	host := dial(t, roomServer)
	defer host.close()
	other := dial(t, roomServer)
	defer other.close()
	host.hello("Alice")
	other.hello("Bob")
	host.createRoom("Only room", protocol.FormatModern, 2, true, "")
	host.recvType(protocol.TypeRoomSnapshot)
	create, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{
		Name: "Overflow", Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatCustom,
		MatchMode: protocol.MatchBO1, AllowSpectators: true,
	})
	create.ID = "room-limit"
	other.send(create)
	errorEnvelope := other.recvType(protocol.TypeError)
	var payload protocol.ErrorPayload
	if err := errorEnvelope.DecodePayload(&payload); err != nil {
		t.Fatalf("decode room limit: %v", err)
	}
	if payload.Code != protocol.ErrServerLimit {
		t.Fatalf("room limit code = %q", payload.Code)
	}
}

func TestMessageAndRoomCreateRateLimits(t *testing.T) {
	messageConfig := DefaultConfig()
	messageConfig.MessagesPerSecond = 1
	messageServer, _ := newConfiguredTestServer(t, messageConfig)
	client := dial(t, messageServer)
	defer client.close()
	client.hello("Alice")
	ping, _ := protocol.NewEnvelope(protocol.TypeSessionPing, map[string]any{})
	ping.ID = "too-fast"
	client.send(ping)
	rateError := client.recvType(protocol.TypeError)
	var payload protocol.ErrorPayload
	if err := rateError.DecodePayload(&payload); err != nil {
		t.Fatalf("decode message rate error: %v", err)
	}
	if payload.Code != protocol.ErrRateLimited {
		t.Fatalf("message rate code = %q", payload.Code)
	}

	createConfig := DefaultConfig()
	createConfig.RoomCreatesPerMinute = 1
	createServer, _ := newConfiguredTestServer(t, createConfig)
	first := dial(t, createServer)
	defer first.close()
	second := dial(t, createServer)
	defer second.close()
	first.hello("Alice")
	second.hello("Bob")
	first.createRoom("First", protocol.FormatModern, 2, true, "")
	first.recvType(protocol.TypeRoomSnapshot)
	create, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{
		Name: "Second", Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatCustom,
		MatchMode: protocol.MatchBO1, AllowSpectators: true,
	})
	create.ID = "create-rate"
	second.send(create)
	createError := second.recvType(protocol.TypeError)
	if err := createError.DecodePayload(&payload); err != nil {
		t.Fatalf("decode create rate error: %v", err)
	}
	if payload.Code != protocol.ErrRateLimited {
		t.Fatalf("create rate code = %q", payload.Code)
	}
}

func wsURL(srv *httptest.Server) string {
	return "ws" + strings.TrimPrefix(srv.URL, "http") + "/ws"
}

func dial(t *testing.T, srv *httptest.Server) *wsClient {
	t.Helper()
	conn, _, err := websocket.Dial(context.Background(), wsURL(srv), &websocket.DialOptions{
		CompressionMode: websocket.CompressionDisabled,
	})
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	return &wsClient{t: t, conn: conn}
}

// hello performs the session.hello handshake and returns the welcome envelope.
func (c *wsClient) hello(name string) protocol.Envelope {
	c.t.Helper()
	env, _ := protocol.NewEnvelope(protocol.TypeSessionHello, protocol.SessionHello{
		DisplayName: name, ClientVersion: buildinfo.Version, Protocol: protocol.ProtocolVersion,
	})
	env.ID = "hello"
	c.send(env)
	return c.recvType(protocol.TypeSessionWelcome)
}

func (c *wsClient) resume(name, token string, lastSeq int64) protocol.SessionWelcome {
	c.t.Helper()
	env, _ := protocol.NewEnvelope(protocol.TypeSessionHello, protocol.SessionHello{
		DisplayName: name, ClientVersion: buildinfo.Version, Protocol: protocol.ProtocolVersion,
		ResumeToken: token, LastSeq: lastSeq,
	})
	env.ID = "resume"
	c.send(env)
	welcomeEnvelope := c.recvType(protocol.TypeSessionWelcome)
	var welcome protocol.SessionWelcome
	if err := welcomeEnvelope.DecodePayload(&welcome); err != nil {
		c.t.Fatalf("decode resumed welcome: %v", err)
	}
	return welcome
}

// createRoom sends room.create and returns the room.created event + room id.
func (c *wsClient) createRoom(name, format string, seats int, allowSpec bool, password string,
	spectatorHands ...bool) (protocol.Envelope, string) {
	c.t.Helper()
	seeHands := len(spectatorHands) > 0 && spectatorHands[0]
	env, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{
		Name: name, Format: format, DeckFormat: protocol.DefaultDeckFormatForTableMode(format),
		MaxSeats: seats, AllowSpectators: allowSpec, SpectatorsSeeHands: seeHands,
		MatchMode: protocol.MatchBO3, Password: password,
	})
	env.ID = "create"
	c.send(env)
	created := c.recvType(protocol.TypeRoomCreated)
	var rc protocol.RoomCreated
	_ = created.DecodePayload(&rc)
	return created, rc.RoomID
}

// TestTwoClientCreateJoin: host creates -> guest joins by id -> both see seat fill.
