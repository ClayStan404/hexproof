// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"errors"
	"fmt"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/buildinfo"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"

	"github.com/coder/websocket"
)

func testIntPointer(value int) *int {
	return &value
}

func testStringPointer(value string) *string {
	return &value
}

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
		protocol.CardLoadPreload, 2, true, "", host)
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
		protocol.CardLoadPreload, 2, true, "", host)
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
		protocol.CardLoadPreload, 2, true, "", host)
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
func (c *wsClient) createRoom(name, format string, seats int, allowSpec bool, password string) (protocol.Envelope, string) {
	c.t.Helper()
	env, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{
		Name: name, Format: format, DeckFormat: protocol.DefaultDeckFormatForTableMode(format),
		MaxSeats: seats, AllowSpectators: allowSpec,
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
func TestTwoClientCreateJoin(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	guest := dial(t, srv)
	defer guest.close()

	host.hello("Alice")
	guest.hello("Bob")

	_, roomID := host.createRoom("Friday EDH", protocol.FormatEDH, 4, true, "")
	initial := host.recvType(protocol.TypeRoomSnapshot)
	if !initial.HasSeq() || initial.SeqValue() != 1 {
		t.Fatalf("initial snapshot seq = %d (present=%v), want 1", initial.SeqValue(), initial.HasSeq())
	}

	joinEnv, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{
		RoomID: roomID, AsSpectator: false,
	})
	joinEnv.ID = "join"
	guest.send(joinEnv)
	joined := guest.recvType(protocol.TypeRoomJoined)
	var rj protocol.RoomJoined
	if err := joined.DecodePayload(&rj); err != nil {
		t.Fatalf("decode joined: %v", err)
	}
	if rj.Role != "player" || rj.Seat == nil || *rj.Seat != 1 {
		t.Fatalf("joined = %+v, want role=player seat=1", rj)
	}

	// Host should receive a snapshot showing Bob in seat 1.
	snap := host.recvType(protocol.TypeRoomSnapshot)
	if !snap.HasSeq() || snap.SeqValue() != 2 {
		t.Fatalf("join snapshot seq = %d (present=%v), want 2", snap.SeqValue(), snap.HasSeq())
	}
	var snapPayload protocol.RoomSnapshot
	if err := snap.DecodePayload(&snapPayload); err != nil {
		t.Fatalf("decode snapshot: %v", err)
	}
	if !snapPayload.Seats[1].Occupied || snapPayload.Seats[1].DisplayName != "Bob" {
		t.Fatalf("host snapshot seats[1] = %+v, want Bob", snapPayload.Seats[1])
	}
}

func TestCreateDuelCommanderCanonicalizesSeatsAndKeepsBO3(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	host.hello("Alice")

	createdEnvelope, _ := host.createRoom(
		"Duel Commander", protocol.FormatDuel, 4, true, "")
	var created protocol.RoomCreated
	if err := createdEnvelope.DecodePayload(&created); err != nil {
		t.Fatalf("decode duel room.created: %v", err)
	}
	if created.Settings.Format != protocol.FormatDuel ||
		created.Settings.MaxSeats != 2 ||
		created.Settings.MatchMode != protocol.MatchBO3 {
		t.Fatalf("duel settings = %+v", created.Settings)
	}
	host.recvType(protocol.TypeRoomSnapshot)
}

func TestHubRoomListExposesOnlyPublicJoinMetadata(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	browser := dial(t, srv)
	defer browser.close()
	host.hello("Alice")
	browser.hello("Browser")

	_, roomID := host.createRoom(
		"Private Table", protocol.FormatModern, 2, true, "secret-password")
	host.recvType(protocol.TypeRoomSnapshot)

	request, _ := protocol.NewEnvelope(protocol.TypeRoomList, map[string]any{})
	request.ID = "list"
	browser.send(request)
	listedEnvelope := browser.recvType(protocol.TypeRoomListed)
	var listed protocol.RoomListed
	if err := listedEnvelope.DecodePayload(&listed); err != nil {
		t.Fatalf("decode room list: %v", err)
	}
	if len(listed.Rooms) != 1 {
		t.Fatalf("room list = %+v", listed.Rooms)
	}
	entry := listed.Rooms[0]
	if entry.RoomID != roomID || entry.Name != "Private Table" ||
		entry.PlayerCount != 1 || entry.MaxSeats != 2 ||
		!entry.HasPassword || !entry.PlayerJoinable ||
		!entry.SpectatorJoinable {
		t.Fatalf("room list entry = %+v", entry)
	}
	raw := string(listedEnvelope.Payload)
	if strings.Contains(raw, "Alice") ||
		strings.Contains(raw, "secret-password") ||
		strings.Contains(raw, "connectionId") {
		t.Fatalf("room list leaked private membership data: %s", raw)
	}
}

func TestReplayEndpointsReturnPublicLogOnly(t *testing.T) {
	config := DefaultConfig()
	config.RetentionDir = t.TempDir()
	srv, handler := newConfiguredTestServer(t, config)

	now := time.Now().UTC()
	retained, err := room.New(
		"ABCDEF", "Archived Table", protocol.FormatModern, protocol.MatchBO1,
		protocol.CardLoadPreload, 2, true, false, "Alice", "conn-secret", now)
	if err != nil {
		t.Fatalf("new retained room: %v", err)
	}
	retained.Game = &room.GameState{
		Number: 1,
		Seats: []room.PlayerGameState{{
			Seat: 0, DisplayName: "Alice",
			Hand: []protocol.GameCard{{
				ID: "secret-card", Name: "Demonic Tutor",
				SetCode: "STA", CollectorNumber: "27",
			}},
		}},
		Log: []protocol.GameLogEntry{{
			ID: 1, Kind: "draw", Seat: 0, Text: "Alice drew a card.",
		}},
	}
	if err := handler.retention.save(retained, now); err != nil {
		t.Fatalf("save retained replay: %v", err)
	}

	client := dial(t, srv)
	defer client.close()
	client.hello("Viewer")
	listRequest, _ := protocol.NewEnvelope(protocol.TypeReplayList, map[string]any{})
	listRequest.ID = "replays"
	client.send(listRequest)
	listedEnvelope := client.recvType(protocol.TypeReplayListed)
	var listed protocol.ReplayListed
	if err := listedEnvelope.DecodePayload(&listed); err != nil {
		t.Fatalf("decode replay list: %v", err)
	}
	if len(listed.Replays) != 1 {
		t.Fatalf("replay list = %+v", listed.Replays)
	}

	getRequest, _ := protocol.NewEnvelope(protocol.TypeReplayGet,
		protocol.ReplayGet{ReplayID: listed.Replays[0].ReplayID})
	getRequest.ID = "replay"
	client.send(getRequest)
	loadedEnvelope := client.recvType(protocol.TypeReplayLoaded)
	var loaded protocol.ReplayLoaded
	if err := loadedEnvelope.DecodePayload(&loaded); err != nil {
		t.Fatalf("decode replay: %v", err)
	}
	if len(loaded.Log) != 1 || loaded.Log[0].Kind != "draw" {
		t.Fatalf("loaded public log = %+v", loaded.Log)
	}
	raw := string(loadedEnvelope.Payload)
	if strings.Contains(raw, "secret-card") ||
		strings.Contains(raw, "Demonic Tutor") ||
		strings.Contains(raw, "conn-secret") ||
		strings.Contains(raw, "library") ||
		strings.Contains(raw, "hand") {
		t.Fatalf("replay endpoint leaked hidden state: %s", raw)
	}
}

func modernTestDeck(name string) protocol.DeckSelect {
	return protocol.DeckSelect{
		Name:       name,
		Format:     protocol.FormatModern,
		DeckFormat: protocol.DeckFormatCustom,
		Mainboard: []protocol.DeckCard{
			{Name: "Lightning Bolt", Count: 10, SetCode: "M11", CollectorNumber: "149"},
		},
		Sideboard: []protocol.DeckCard{},
	}
}

func TestTwoClientDeckSelectionAndReadyRemainPrivate(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	guest := dial(t, srv)
	defer guest.close()

	host.hello("Alice")
	guest.hello("Bob")
	_, roomID := host.createRoom("Modern", protocol.FormatModern, 2, true, "")
	host.recvType(protocol.TypeRoomSnapshot)

	join, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: roomID})
	join.ID = "join"
	guest.send(join)
	guest.recvType(protocol.TypeRoomJoined)
	host.recvType(protocol.TypeRoomSnapshot)
	guest.recvType(protocol.TypeRoomSnapshot)

	selectHost, _ := protocol.NewEnvelope(protocol.TypeDeckSelect, modernTestDeck("Burn"))
	selectHost.ID = "deck-host"
	host.send(selectHost)
	selected := host.recvType(protocol.TypeDeckSelected)
	if selected.ID != selectHost.ID {
		t.Fatalf("deck.selected id = %q, want %q", selected.ID, selectHost.ID)
	}
	host.recvType(protocol.TypeRoomSnapshot)
	guestView := guest.recvType(protocol.TypeRoomSnapshot)
	if strings.Contains(string(guestView.Payload), "Lightning Bolt") || strings.Contains(string(guestView.Payload), "Burn") {
		t.Fatalf("opponent snapshot leaked deck identities: %s", guestView.Payload)
	}
	var snapshot protocol.RoomSnapshot
	if err := guestView.DecodePayload(&snapshot); err != nil {
		t.Fatalf("decode snapshot: %v", err)
	}
	if !snapshot.Seats[0].DeckSelected || snapshot.Seats[0].Ready {
		t.Fatalf("host public state = %+v", snapshot.Seats[0])
	}

	selectGuest, _ := protocol.NewEnvelope(protocol.TypeDeckSelect, modernTestDeck("Prowess"))
	selectGuest.ID = "deck-guest"
	guest.send(selectGuest)
	guest.recvType(protocol.TypeDeckSelected)
	guest.recvType(protocol.TypeRoomSnapshot)
	host.recvType(protocol.TypeRoomSnapshot)

	readyHost, _ := protocol.NewEnvelope(protocol.TypePlayerReady, protocol.PlayerReady{Ready: true})
	readyHost.ID = "ready-host"
	host.send(readyHost)
	host.recvType(protocol.TypePlayerReadyChanged)
	host.recvType(protocol.TypeRoomSnapshot)
	guest.recvType(protocol.TypeRoomSnapshot)

	readyGuest, _ := protocol.NewEnvelope(protocol.TypePlayerReady, protocol.PlayerReady{Ready: true})
	readyGuest.ID = "ready-guest"
	guest.send(readyGuest)
	guest.recvType(protocol.TypePlayerReadyChanged)
	guest.recvType(protocol.TypeRoomSnapshot)
	final := host.recvType(protocol.TypeRoomSnapshot)
	if err := final.DecodePayload(&snapshot); err != nil {
		t.Fatalf("decode final snapshot: %v", err)
	}
	if !snapshot.Seats[0].Ready || !snapshot.Seats[1].Ready {
		t.Fatalf("final ready state = %+v", snapshot.Seats)
	}

	hostLoad := host.recvType(protocol.TypeMatchLoadRequired)
	guestLoad := guest.recvType(protocol.TypeMatchLoadRequired)
	var hostRequired, guestRequired protocol.MatchLoadRequired
	if err := hostLoad.DecodePayload(&hostRequired); err != nil {
		t.Fatalf("decode host load: %v", err)
	}
	if err := guestLoad.DecodePayload(&guestRequired); err != nil {
		t.Fatalf("decode guest load: %v", err)
	}
	if hostRequired.LoadID == 0 || hostRequired.LoadID != guestRequired.LoadID || len(hostRequired.CardKeys) != 1 {
		t.Fatalf("load payloads host=%+v guest=%+v", hostRequired, guestRequired)
	}

	hostComplete, _ := protocol.NewEnvelope(protocol.TypeClientLoadComplete,
		protocol.ClientLoadComplete{LoadID: hostRequired.LoadID})
	hostComplete.ID = "load-host"
	host.send(hostComplete)
	host.recvType(protocol.TypeClientLoadCompleted)
	host.recvType(protocol.TypeRoomSnapshot)
	guest.recvType(protocol.TypeRoomSnapshot)

	guestComplete, _ := protocol.NewEnvelope(protocol.TypeClientLoadComplete,
		protocol.ClientLoadComplete{LoadID: guestRequired.LoadID})
	guestComplete.ID = "load-guest"
	guest.send(guestComplete)
	completed := guest.recvType(protocol.TypeClientLoadCompleted)
	if completed.ID != guestComplete.ID {
		t.Fatalf("client.load_completed id = %q, want %q", completed.ID, guestComplete.ID)
	}
	guest.recvType(protocol.TypeMatchStarted)
	startedEvent := host.recvType(protocol.TypeMatchStarted)
	var startedPayload protocol.MatchStarted
	if err := startedEvent.DecodePayload(&startedPayload); err != nil {
		t.Fatalf("decode started: %v", err)
	}
	if startedPayload.LoadID != hostRequired.LoadID {
		t.Fatalf("match.started = %+v", startedPayload)
	}

	hostGameEvent := host.recvType(protocol.TypeGameSnapshot)
	guestGameEvent := guest.recvType(protocol.TypeGameSnapshot)
	var hostGame, guestGame protocol.GameSnapshot
	if err := hostGameEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host game: %v", err)
	}
	if err := guestGameEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest game: %v", err)
	}
	if hostGameEvent.SeqValue() != guestGameEvent.SeqValue() || len(hostGame.Log) < 3 {
		t.Fatalf("initial game projections host=%+v guest=%+v", hostGameEvent, guestGameEvent)
	}
	if len(hostGame.Seats[0].Hand) != 7 || len(hostGame.Seats[1].Hand) != 0 ||
		len(guestGame.Seats[0].Hand) != 0 || len(guestGame.Seats[1].Hand) != 7 {
		t.Fatalf("private opening hands host=%+v guest=%+v", hostGame.Seats, guestGame.Seats)
	}
	if hostGame.ActiveSeat != hostGame.StartingSeat ||
		hostGame.CurrentPhase != protocol.GamePhaseUntap ||
		guestGame.ActiveSeat != hostGame.ActiveSeat ||
		guestGame.CurrentPhase != hostGame.CurrentPhase {
		t.Fatalf("initial turn state host=%+v guest=%+v", hostGame, guestGame)
	}
	if hostGame.Seats[0].LibraryCount != 3 || guestGame.Seats[0].HandCount != 7 {
		t.Fatalf("opening counts host=%+v guest=%+v", hostGame.Seats, guestGame.Seats)
	}

	setLife, _ := protocol.NewEnvelope(protocol.TypeGameSetCounter,
		protocol.GameSetCounter{
			Counter: protocol.PlayerCounterLife,
			Value:   testIntPointer(17),
		})
	setLife.ID = "set-life"
	host.send(setLife)
	counterSet := host.recvType(protocol.TypeGameCounterSet)
	if counterSet.ID != setLife.ID {
		t.Fatalf("game.counter_set id = %q, want %q", counterSet.ID, setLife.ID)
	}
	lifeHostEvent := host.recvType(protocol.TypeGameSnapshot)
	lifeGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := lifeHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host life projection: %v", err)
	}
	if err := lifeGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest life projection: %v", err)
	}
	if hostGame.Seats[0].Life != 17 || guestGame.Seats[0].Life != 17 ||
		hostGame.Log[len(hostGame.Log)-1].Kind != "counter" ||
		hostGame.Log[len(hostGame.Log)-1].Text != guestGame.Log[len(guestGame.Log)-1].Text {
		t.Fatalf("life projections host=%+v guest=%+v logs=%+v/%+v",
			hostGame.Seats, guestGame.Seats, hostGame.Log, guestGame.Log)
	}

	adjustCounter, _ := protocol.NewEnvelope(protocol.TypeGameSetCounter,
		protocol.GameSetCounter{
			Counter: "counter-1",
			Delta:   testIntPointer(1),
		})
	adjustCounter.ID = "adjust-counter"
	host.send(adjustCounter)
	if counterSet := host.recvType(protocol.TypeGameCounterSet); counterSet.ID != adjustCounter.ID {
		t.Fatalf("adjust game.counter_set id = %q, want %q",
			counterSet.ID, adjustCounter.ID)
	}
	counterHostEvent := host.recvType(protocol.TypeGameSnapshot)
	counterGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := counterHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host counter projection: %v", err)
	}
	if err := counterGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest counter projection: %v", err)
	}
	if hostGame.Seats[0].Counters[0].Value != 1 ||
		guestGame.Seats[0].Counters[0].Value != 1 {
		t.Fatalf("counter projections host=%+v guest=%+v",
			hostGame.Seats[0].Counters, guestGame.Seats[0].Counters)
	}

	renameCounter, _ := protocol.NewEnvelope(protocol.TypeGameSetCounter,
		protocol.GameSetCounter{
			Counter: "counter-1",
			Label:   testStringPointer("Energy"),
		})
	renameCounter.ID = "rename-counter"
	host.send(renameCounter)
	if counterSet := host.recvType(protocol.TypeGameCounterSet); counterSet.ID != renameCounter.ID {
		t.Fatalf("rename game.counter_set id = %q, want %q",
			counterSet.ID, renameCounter.ID)
	}
	counterHostEvent = host.recvType(protocol.TypeGameSnapshot)
	counterGuestEvent = guest.recvType(protocol.TypeGameSnapshot)
	if err := counterHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host renamed counter projection: %v", err)
	}
	if err := counterGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest renamed counter projection: %v", err)
	}
	if hostGame.Seats[0].Counters[0].Label != "Energy" ||
		guestGame.Seats[0].Counters[0].Label != "Energy" ||
		hostGame.Log[len(hostGame.Log)-1].Text !=
			"Alice renamed counter counter-1 to Energy." {
		t.Fatalf("renamed counter projections host=%+v guest=%+v logs=%+v",
			hostGame.Seats[0].Counters, guestGame.Seats[0].Counters, hostGame.Log)
	}

	setCounterCount, _ := protocol.NewEnvelope(protocol.TypeGameSetCounterCount,
		protocol.GameSetCounterCount{Count: 3})
	setCounterCount.ID = "set-counter-count"
	host.send(setCounterCount)
	if countSet := host.recvType(protocol.TypeGameCounterCountSet); countSet.ID != setCounterCount.ID {
		t.Fatalf("game.counter_count_set id = %q, want %q",
			countSet.ID, setCounterCount.ID)
	}
	counterHostEvent = host.recvType(protocol.TypeGameSnapshot)
	counterGuestEvent = guest.recvType(protocol.TypeGameSnapshot)
	if err := counterHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host counter-count projection: %v", err)
	}
	if err := counterGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest counter-count projection: %v", err)
	}
	if hostGame.Seats[0].CounterCount != 3 ||
		guestGame.Seats[0].CounterCount != 3 ||
		hostGame.Seats[1].CounterCount != 0 ||
		guestGame.Seats[1].CounterCount != 0 {
		t.Fatalf("counter-count projections host=%+v guest=%+v",
			hostGame.Seats, guestGame.Seats)
	}

	draw, _ := protocol.NewEnvelope(protocol.TypeGameDraw, protocol.GameDraw{})
	draw.ID = "draw-host"
	host.send(draw)
	drawn := host.recvType(protocol.TypeGameDrawn)
	if drawn.ID != draw.ID {
		t.Fatalf("game.drawn id = %q, want %q", drawn.ID, draw.ID)
	}
	drawnHostEvent := host.recvType(protocol.TypeGameSnapshot)
	drawnGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := drawnHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host draw projection: %v", err)
	}
	if err := drawnGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest draw projection: %v", err)
	}
	if len(hostGame.Seats[0].Hand) != 8 || hostGame.Seats[0].LibraryCount != 2 ||
		len(guestGame.Seats[0].Hand) != 0 || guestGame.Seats[0].HandCount != 8 {
		t.Fatalf("draw projections host=%+v guest=%+v", hostGame.Seats, guestGame.Seats)
	}

	mulligan, _ := protocol.NewEnvelope(protocol.TypeGameMulligan, protocol.GameMulligan{})
	mulligan.ID = "mulligan-host"
	host.send(mulligan)
	mulliganed := host.recvType(protocol.TypeGameMulliganed)
	if mulliganed.ID != mulligan.ID {
		t.Fatalf("game.mulliganed id = %q, want %q", mulliganed.ID, mulligan.ID)
	}
	var mulliganReply protocol.GameMulliganed
	if err := mulliganed.DecodePayload(&mulliganReply); err != nil {
		t.Fatalf("decode game.mulliganed: %v", err)
	}
	if mulliganReply.HandSize != 7 || mulliganReply.MulliganCount != 1 {
		t.Fatalf("game.mulliganed payload = %+v", mulliganReply)
	}
	mulliganHostEvent := host.recvType(protocol.TypeGameSnapshot)
	mulliganGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := mulliganHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host mulligan projection: %v", err)
	}
	if err := mulliganGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest mulligan projection: %v", err)
	}
	if len(hostGame.Seats[0].Hand) != 7 || hostGame.Seats[0].LibraryCount != 3 ||
		len(guestGame.Seats[0].Hand) != 0 ||
		hostGame.Seats[0].MulliganCount != 1 ||
		guestGame.Seats[0].MulliganCount != 1 ||
		hostGame.Log[len(hostGame.Log)-1].Kind != "mulligan" {
		t.Fatalf("mulligan projections host=%+v guest=%+v log=%+v",
			hostGame.Seats, guestGame.Seats, hostGame.Log)
	}

	cardID := hostGame.Seats[0].Hand[0].ID
	move, _ := protocol.NewEnvelope(protocol.TypeGameMoveCard, protocol.GameMoveCard{
		CardID: cardID, FromZone: protocol.ZoneHand, ToZone: protocol.ZoneBattlefield,
		Position: &protocol.CardPosition{X: 0.35, Y: 0.65},
	})
	move.ID = "move-host"
	host.send(move)
	moved := host.recvType(protocol.TypeGameCardMoved)
	if moved.ID != move.ID {
		t.Fatalf("game.card_moved id = %q, want %q", moved.ID, move.ID)
	}
	movedHostEvent := host.recvType(protocol.TypeGameSnapshot)
	movedGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := movedHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host move projection: %v", err)
	}
	if err := movedGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest move projection: %v", err)
	}
	if len(hostGame.Seats[0].Hand) != 6 || len(hostGame.Seats[0].Battlefield) != 1 ||
		hostGame.Seats[0].Battlefield[0].ID != cardID ||
		hostGame.Seats[0].Battlefield[0].Position == nil ||
		len(guestGame.Seats[0].Hand) != 0 || guestGame.Seats[0].HandCount != 6 ||
		len(guestGame.Seats[0].Battlefield) != 1 ||
		guestGame.Seats[0].Battlefield[0].Name != "Lightning Bolt" {
		t.Fatalf("move projections host=%+v guest=%+v", hostGame.Seats, guestGame.Seats)
	}

	setTapped, _ := protocol.NewEnvelope(protocol.TypeGameSetTapped,
		protocol.GameSetTapped{CardID: cardID, Tapped: true})
	setTapped.ID = "tap-host"
	host.send(setTapped)
	tappedAck := host.recvType(protocol.TypeGameTappedSet)
	if tappedAck.ID != setTapped.ID {
		t.Fatalf("game.tapped_set id = %q, want %q", tappedAck.ID, setTapped.ID)
	}
	tappedHostEvent := host.recvType(protocol.TypeGameSnapshot)
	tappedGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := tappedHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host tapped projection: %v", err)
	}
	if err := tappedGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest tapped projection: %v", err)
	}
	if !hostGame.Seats[0].Battlefield[0].Tapped ||
		!guestGame.Seats[0].Battlefield[0].Tapped {
		t.Fatalf("tapped projections host=%+v guest=%+v",
			hostGame.Seats[0].Battlefield, guestGame.Seats[0].Battlefield)
	}

	toStack, _ := protocol.NewEnvelope(protocol.TypeGameMoveCard, protocol.GameMoveCard{
		CardID: cardID, FromZone: protocol.ZoneBattlefield, ToZone: protocol.ZoneStack,
	})
	toStack.ID = "move-stack"
	host.send(toStack)
	host.recvType(protocol.TypeGameCardMoved)
	stackHostEvent := host.recvType(protocol.TypeGameSnapshot)
	stackGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := stackHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host stack projection: %v", err)
	}
	if err := stackGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest stack projection: %v", err)
	}
	if len(hostGame.Stack) != 1 || hostGame.Stack[0].OwnerSeat != 0 ||
		hostGame.Stack[0].Name != "Lightning Bolt" ||
		len(guestGame.Stack) != 1 || guestGame.Stack[0].Name != "Lightning Bolt" {
		t.Fatalf("stack projections host=%+v guest=%+v", hostGame.Stack, guestGame.Stack)
	}

	opponentResolve, _ := protocol.NewEnvelope(protocol.TypeGameMoveCard, protocol.GameMoveCard{
		CardID: cardID, FromZone: protocol.ZoneStack, ToZone: protocol.ZoneGraveyard,
	})
	opponentResolve.ID = "opponent-resolve"
	guest.send(opponentResolve)
	stackErrorEnv := guest.recvType(protocol.TypeError)
	var stackError protocol.ErrorPayload
	if err := stackErrorEnv.DecodePayload(&stackError); err != nil {
		t.Fatalf("decode stack ownership error: %v", err)
	}
	if stackError.Code != protocol.ErrCardNotFound {
		t.Fatalf("opponent stack code = %q, want %q",
			stackError.Code, protocol.ErrCardNotFound)
	}

	reveal, _ := protocol.NewEnvelope(protocol.TypeGameReveal, protocol.GameReveal{
		Zone: protocol.ZoneHand,
	})
	reveal.ID = "reveal-hand"
	host.send(reveal)
	revealed := host.recvType(protocol.TypeGameRevealed)
	if revealed.ID != reveal.ID {
		t.Fatalf("game.revealed id = %q, want %q", revealed.ID, reveal.ID)
	}
	revealHostEvent := host.recvType(protocol.TypeGameSnapshot)
	revealGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	hostGame = protocol.GameSnapshot{}
	guestGame = protocol.GameSnapshot{}
	if err := revealHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host reveal projection: %v", err)
	}
	if err := revealGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest reveal projection: %v", err)
	}
	if len(hostGame.Seats[0].Hand) != 0 || hostGame.Seats[0].HandCount != 0 ||
		len(hostGame.Revealed) != 6 || len(guestGame.Revealed) != 6 ||
		guestGame.Revealed[0].OwnerSeat != 0 ||
		guestGame.Revealed[0].Name == "" {
		t.Fatalf("reveal projections host=%+v guest=%+v",
			hostGame.Revealed, guestGame.Revealed)
	}

	active := host
	inactive := guest
	activeSeat := hostGame.ActiveSeat
	if activeSeat == 1 {
		active = guest
		inactive = host
	}
	setPhase, _ := protocol.NewEnvelope(protocol.TypeGameSetPhase, protocol.GameSetPhase{
		Phase: protocol.GamePhaseCombatDamage,
	})
	setPhase.ID = "set-phase"
	active.send(setPhase)
	phaseSet := active.recvType(protocol.TypeGamePhaseSet)
	if phaseSet.ID != setPhase.ID {
		t.Fatalf("game.phase_set id = %q, want %q", phaseSet.ID, setPhase.ID)
	}
	phaseHostEvent := host.recvType(protocol.TypeGameSnapshot)
	phaseGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := phaseHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host phase projection: %v", err)
	}
	if err := phaseGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest phase projection: %v", err)
	}
	if hostGame.ActiveSeat != activeSeat ||
		hostGame.CurrentPhase != protocol.GamePhaseCombatDamage ||
		guestGame.ActiveSeat != hostGame.ActiveSeat ||
		guestGame.CurrentPhase != hostGame.CurrentPhase {
		t.Fatalf("phase projections host=%+v guest=%+v", hostGame, guestGame)
	}

	invalidPhase, _ := protocol.NewEnvelope(protocol.TypeGameSetPhase, protocol.GameSetPhase{
		Phase: protocol.GamePhaseEnd,
	})
	invalidPhase.ID = "inactive-phase"
	inactive.send(invalidPhase)
	errEnv := inactive.recvType(protocol.TypeError)
	var phaseError protocol.ErrorPayload
	if err := errEnv.DecodePayload(&phaseError); err != nil {
		t.Fatalf("decode inactive phase error: %v", err)
	}
	if phaseError.Code != protocol.ErrNotActivePlayer {
		t.Fatalf("inactive phase code = %q, want %q",
			phaseError.Code, protocol.ErrNotActivePlayer)
	}

	nextTurn, _ := protocol.NewEnvelope(protocol.TypeGameNextTurn, protocol.GameNextTurn{})
	nextTurn.ID = "next-turn"
	active.send(nextTurn)
	advanced := active.recvType(protocol.TypeGameTurnAdvanced)
	if advanced.ID != nextTurn.ID {
		t.Fatalf("game.turn_advanced id = %q, want %q", advanced.ID, nextTurn.ID)
	}
	turnHostEvent := host.recvType(protocol.TypeGameSnapshot)
	turnGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := turnHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host turn projection: %v", err)
	}
	if err := turnGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest turn projection: %v", err)
	}
	if hostGame.ActiveSeat != (activeSeat+1)%2 ||
		hostGame.CurrentPhase != protocol.GamePhaseUntap ||
		guestGame.ActiveSeat != hostGame.ActiveSeat ||
		guestGame.CurrentPhase != hostGame.CurrentPhase {
		t.Fatalf("turn projections host=%+v guest=%+v", hostGame, guestGame)
	}

	guestSeat := 1
	dumpGuestTop, _ := protocol.NewEnvelope(protocol.TypeGameDumpZone,
		protocol.GameDumpZone{
			Zone: protocol.ZoneLibrary, Seat: &guestSeat, TopCount: 1,
		})
	dumpGuestTop.ID = "dump-guest-top"
	host.send(dumpGuestTop)
	pending := host.recvType(protocol.TypeGameZoneDumpPending)
	var pendingDump protocol.GameZoneDumpPending
	if err := pending.DecodePayload(&pendingDump); err != nil {
		t.Fatalf("decode pending guest dump: %v", err)
	}
	requested := guest.recvType(protocol.TypeGameZoneDumpRequested)
	var requestedDump protocol.GameZoneDumpRequested
	if err := requested.DecodePayload(&requestedDump); err != nil {
		t.Fatalf("decode requested guest dump: %v", err)
	}
	if pending.ID != dumpGuestTop.ID ||
		pendingDump.ApprovalID == "" ||
		requestedDump.ApprovalID != pendingDump.ApprovalID ||
		requestedDump.TopCount != 1 {
		t.Fatalf("remote dump approval pending=%+v requested=%+v",
			pendingDump, requestedDump)
	}
	approveTop, _ := protocol.NewEnvelope(protocol.TypeGameRespondZoneDump,
		protocol.GameRespondZoneDump{
			ApprovalID: pendingDump.ApprovalID, Approved: true,
		})
	approveTop.ID = "approve-guest-top"
	guest.send(approveTop)
	responded := guest.recvType(protocol.TypeGameZoneDumpResponded)
	if responded.ID != approveTop.ID {
		t.Fatalf("zone_dump_responded id = %q, want %q",
			responded.ID, approveTop.ID)
	}
	dumpedTopEnvelope := host.recvType(protocol.TypeGameZoneDumped)
	var dumpedTop protocol.GameZoneDumped
	if err := dumpedTopEnvelope.DecodePayload(&dumpedTop); err != nil {
		t.Fatalf("decode approved top dump: %v", err)
	}
	if dumpedTopEnvelope.ID != dumpGuestTop.ID ||
		len(dumpedTop.Cards) != 1 ||
		dumpedTop.ApprovalID != pendingDump.ApprovalID {
		t.Fatalf("approved top dump = env %+v payload %+v",
			dumpedTopEnvelope, dumpedTop)
	}
	topDumpHostSnapshot := host.recvType(protocol.TypeGameSnapshot)
	topDumpGuestSnapshot := guest.recvType(protocol.TypeGameSnapshot)
	if err := topDumpHostSnapshot.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host top-dump projection: %v", err)
	}
	if err := topDumpGuestSnapshot.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest top-dump projection: %v", err)
	}

	guestHandIDs := make(map[string]bool, len(guestGame.Seats[guestSeat].Hand))
	for _, card := range guestGame.Seats[guestSeat].Hand {
		guestHandIDs[card.ID] = true
	}
	outsideApprovedPrefix := ""
	for instance := 1; instance <= 10; instance++ {
		cardID := fmt.Sprintf("s1-c%d", instance)
		if cardID != dumpedTop.Cards[0].ID && !guestHandIDs[cardID] {
			outsideApprovedPrefix = cardID
			break
		}
	}
	if outsideApprovedPrefix == "" {
		t.Fatal("could not identify a guest library card outside approved prefix")
	}
	escalatedSearch, _ := protocol.NewEnvelope(protocol.TypeGameSearchLibrary,
		protocol.GameSearchLibrary{
			CardID:     outsideApprovedPrefix,
			SourceSeat: &guestSeat,
			ApprovalID: dumpedTop.ApprovalID,
			ToZone:     protocol.LibraryDestinationHand,
		})
	escalatedSearch.ID = "reuse-top-approval"
	host.send(escalatedSearch)
	escalationError := host.recvType(protocol.TypeError)
	var escalationPayload protocol.ErrorPayload
	if err := escalationError.DecodePayload(&escalationPayload); err != nil {
		t.Fatalf("decode top approval escalation error: %v", err)
	}
	if escalationPayload.Code != protocol.ErrApprovalExpired {
		t.Fatalf("top approval escalation code = %q, want %q",
			escalationPayload.Code, protocol.ErrApprovalExpired)
	}

	dumpLibrary, _ := protocol.NewEnvelope(protocol.TypeGameDumpZone,
		protocol.GameDumpZone{Zone: "library"})
	dumpLibrary.ID = "dump-library"
	host.send(dumpLibrary)
	dumpedEnv := host.recvType(protocol.TypeGameZoneDumped)
	if dumpedEnv.ID != dumpLibrary.ID {
		t.Fatalf("game.zone_dumped id = %q, want %q", dumpedEnv.ID, dumpLibrary.ID)
	}
	var dumped protocol.GameZoneDumped
	if err := dumpedEnv.DecodePayload(&dumped); err != nil {
		t.Fatalf("decode private library dump: %v", err)
	}
	if dumped.Zone != "library" || len(dumped.Cards) == 0 {
		t.Fatalf("private library dump = %+v", dumped)
	}
	dumpHostEvent := host.recvType(protocol.TypeGameSnapshot)
	dumpGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := dumpHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host library-search projection: %v", err)
	}
	if err := dumpGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest library-search projection: %v", err)
	}
	if len(hostGame.Log) == 0 ||
		hostGame.Log[len(hostGame.Log)-1].Text != "Alice is searching their library." ||
		len(guestGame.Log) == 0 ||
		guestGame.Log[len(guestGame.Log)-1].Text != "Alice is searching their library." {
		t.Fatalf("library-search logs host=%+v guest=%+v", hostGame.Log, guestGame.Log)
	}
	searchedCard := dumped.Cards[0]
	searchLibrary, _ := protocol.NewEnvelope(protocol.TypeGameSearchLibrary,
		protocol.GameSearchLibrary{
			CardID: searchedCard.ID, ToZone: protocol.LibraryDestinationHand,
			Reveal: false,
		})
	searchLibrary.ID = "search-library"
	host.send(searchLibrary)
	searchedEnv := host.recvType(protocol.TypeGameLibrarySearched)
	if searchedEnv.ID != searchLibrary.ID {
		t.Fatalf("game.library_searched id = %q, want %q",
			searchedEnv.ID, searchLibrary.ID)
	}
	searchHostEvent := host.recvType(protocol.TypeGameSnapshot)
	// The private game.zone_dumped response must never have been queued for
	// the opponent; its next event is the role-specific public snapshot.
	searchGuestEvent := guest.recv()
	if searchGuestEvent.Type != protocol.TypeGameSnapshot {
		t.Fatalf("opponent received private dump/event: %+v", searchGuestEvent)
	}
	if err := searchHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host search projection: %v", err)
	}
	if err := searchGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest search projection: %v", err)
	}
	hostLog := hostGame.Log[len(hostGame.Log)-1]
	guestLog := guestGame.Log[len(guestGame.Log)-1]
	if hostLog.Kind != "library_search" || guestLog.Text != hostLog.Text ||
		strings.Contains(hostLog.Text, searchedCard.Name) ||
		len(guestGame.Seats[0].Hand) != 0 ||
		guestGame.Seats[0].HandCount != hostGame.Seats[0].HandCount {
		t.Fatalf("hidden search projections host=%+v guest=%+v",
			hostGame, guestGame)
	}

	say, _ := protocol.NewEnvelope(protocol.TypeGameSay,
		protocol.GameSay{Message: "Good luck!"})
	say.ID = "say-host"
	host.send(say)
	said := host.recvType(protocol.TypeGameSaid)
	if said.ID != say.ID {
		t.Fatalf("game.said id = %q, want %q", said.ID, say.ID)
	}
	var saidPayload protocol.GameSaid
	if err := said.DecodePayload(&saidPayload); err != nil {
		t.Fatalf("decode game.said: %v", err)
	}
	sayHostEvent := host.recvType(protocol.TypeGameSnapshot)
	sayGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := sayHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host chat projection: %v", err)
	}
	if err := sayGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest chat projection: %v", err)
	}
	if saidPayload.LogID <= 0 ||
		hostGame.Log[len(hostGame.Log)-1].Kind != "chat" ||
		hostGame.Log[len(hostGame.Log)-1].Text != "Alice: Good luck!" ||
		guestGame.Log[len(guestGame.Log)-1].Text !=
			hostGame.Log[len(hostGame.Log)-1].Text {
		t.Fatalf("chat projections host=%+v guest=%+v",
			hostGame.Log, guestGame.Log)
	}

	concede, _ := protocol.NewEnvelope(protocol.TypeGameConcede,
		protocol.GameConcede{})
	concede.ID = "concede-host"
	host.send(concede)
	conceded := host.recvType(protocol.TypeGameConceded)
	if conceded.ID != concede.ID {
		t.Fatalf("game.conceded id = %q, want %q", conceded.ID, concede.ID)
	}
	var concededPayload protocol.GameConceded
	if err := conceded.DecodePayload(&concededPayload); err != nil {
		t.Fatalf("decode concede reply: %v", err)
	}
	if concededPayload.ConcededSeat != 0 || concededPayload.WinnerSeat != 1 ||
		concededPayload.MatchFinished || len(concededPayload.Score) != 2 ||
		concededPayload.Score[1] != 1 {
		t.Fatalf("concede reply = %+v", concededPayload)
	}
	concedeHostEvent := host.recvType(protocol.TypeGameSnapshot)
	concedeGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := concedeHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host concede projection: %v", err)
	}
	if err := concedeGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest concede projection: %v", err)
	}
	if hostGame.Result == nil || guestGame.Result == nil ||
		hostGame.Result.WinnerSeat != 1 ||
		guestGame.Result.ConcededSeat != 0 ||
		hostGame.ActiveSeat != -1 || guestGame.ActiveSeat != -1 ||
		hostGame.Score[1] != 1 || guestGame.Score[1] != 1 ||
		hostGame.Log[len(hostGame.Log)-1].Kind != "concede" ||
		guestGame.Log[len(guestGame.Log)-1].Text !=
			hostGame.Log[len(hostGame.Log)-1].Text {
		t.Fatalf("concede projections host=%+v guest=%+v", hostGame, guestGame)
	}

	postGameSay, _ := protocol.NewEnvelope(protocol.TypeGameSay,
		protocol.GameSay{Message: "Thanks for the game."})
	postGameSay.ID = "say-after-finish"
	guest.send(postGameSay)
	if said := guest.recvType(protocol.TypeGameSaid); said.ID != postGameSay.ID {
		t.Fatalf("post-game game.said id = %q, want %q",
			said.ID, postGameSay.ID)
	}
	postChatHostEvent := host.recvType(protocol.TypeGameSnapshot)
	postChatGuestEvent := guest.recvType(protocol.TypeGameSnapshot)
	if err := postChatHostEvent.DecodePayload(&hostGame); err != nil {
		t.Fatalf("decode host post-game chat projection: %v", err)
	}
	if err := postChatGuestEvent.DecodePayload(&guestGame); err != nil {
		t.Fatalf("decode guest post-game chat projection: %v", err)
	}
	if hostGame.Result == nil || guestGame.Result == nil ||
		hostGame.Log[len(hostGame.Log)-1].Text !=
			"Bob: Thanks for the game." ||
		guestGame.Log[len(guestGame.Log)-1].Text !=
			hostGame.Log[len(hostGame.Log)-1].Text {
		t.Fatalf("post-game chat projections host=%+v guest=%+v",
			hostGame, guestGame)
	}

	drawAfterFinish, _ := protocol.NewEnvelope(protocol.TypeGameDraw,
		protocol.GameDraw{})
	drawAfterFinish.ID = "draw-after-finish"
	guest.send(drawAfterFinish)
	finishedError := guest.recvType(protocol.TypeError)
	var finishedPayload protocol.ErrorPayload
	if err := finishedError.DecodePayload(&finishedPayload); err != nil {
		t.Fatalf("decode finished error: %v", err)
	}
	if finishedError.ID != drawAfterFinish.ID ||
		finishedPayload.Code != protocol.ErrGameFinished {
		t.Fatalf("finished error = env %+v payload %+v",
			finishedError, finishedPayload)
	}
}

func TestSpectatorSnapshotRedactsSelectedDeck(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	spectator := dial(t, srv)
	defer spectator.close()

	host.hello("Alice")
	spectator.hello("Observer")
	_, roomID := host.createRoom("Modern", protocol.FormatModern, 2, true, "")
	host.recvType(protocol.TypeRoomSnapshot)

	join, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{
		RoomID: roomID, AsSpectator: true,
	})
	join.ID = "watch"
	spectator.send(join)
	spectator.recvType(protocol.TypeRoomJoined)
	host.recvType(protocol.TypeRoomSnapshot)
	spectator.recvType(protocol.TypeRoomSnapshot)

	selectDeck, _ := protocol.NewEnvelope(protocol.TypeDeckSelect, modernTestDeck("Secret Burn"))
	selectDeck.ID = "secret-deck"
	host.send(selectDeck)
	host.recvType(protocol.TypeDeckSelected)
	host.recvType(protocol.TypeRoomSnapshot)
	view := spectator.recvType(protocol.TypeRoomSnapshot)
	for _, hidden := range []string{"Secret Burn", "Lightning Bolt", "M11", "149"} {
		if strings.Contains(string(view.Payload), hidden) {
			t.Fatalf("spectator snapshot leaked %q: %s", hidden, view.Payload)
		}
	}
	var snapshot protocol.RoomSnapshot
	if err := view.DecodePayload(&snapshot); err != nil {
		t.Fatalf("decode snapshot: %v", err)
	}
	if !snapshot.Seats[0].DeckSelected {
		t.Fatalf("spectator should see public deckSelected state: %+v", snapshot.Seats[0])
	}

	ready, _ := protocol.NewEnvelope(protocol.TypePlayerReady, protocol.PlayerReady{Ready: true})
	ready.ID = "spectator-ready"
	spectator.send(ready)
	errEnv := spectator.recvType(protocol.TypeError)
	var payload protocol.ErrorPayload
	if err := errEnv.DecodePayload(&payload); err != nil {
		t.Fatalf("decode error: %v", err)
	}
	if payload.Code != protocol.ErrNotPlayer {
		t.Fatalf("spectator ready code = %q, want %q", payload.Code, protocol.ErrNotPlayer)
	}
}

func TestHandshakeValidation(t *testing.T) {
	srv, _ := newTestServer(t)
	client := dial(t, srv)
	defer client.close()

	missingID, _ := protocol.NewEnvelope(protocol.TypeSessionHello, protocol.SessionHello{
		DisplayName: "Alice", Protocol: protocol.ProtocolVersion,
	})
	client.send(missingID)
	errEnv := client.recvType(protocol.TypeError)
	var ep protocol.ErrorPayload
	_ = errEnv.DecodePayload(&ep)
	if ep.Code != protocol.ErrInvalidMessage {
		t.Fatalf("missing hello id code = %q, want %q", ep.Code, protocol.ErrInvalidMessage)
	}

	wrongVersion, _ := protocol.NewEnvelope(protocol.TypeSessionHello, protocol.SessionHello{
		DisplayName: "Alice", Protocol: "hexproof.v999",
	})
	wrongVersion.ID = "wrong-version"
	client.send(wrongVersion)
	errEnv = client.recvType(protocol.TypeError)
	_ = errEnv.DecodePayload(&ep)
	if ep.Code != protocol.ErrInvalidMessage || errEnv.ID != wrongVersion.ID {
		t.Fatalf("wrong protocol response = type %q id %q code %q", errEnv.Type, errEnv.ID, ep.Code)
	}

	missingClientVersion, _ := protocol.NewEnvelope(protocol.TypeSessionHello,
		protocol.SessionHello{
			DisplayName: "Alice",
			Protocol:    protocol.ProtocolVersion,
		})
	missingClientVersion.ID = "missing-client-version"
	client.send(missingClientVersion)
	errEnv = client.recvType(protocol.TypeError)
	_ = errEnv.DecodePayload(&ep)
	if ep.Code != protocol.ErrClientVersionMismatch ||
		ep.RequiredVersion != buildinfo.Version ||
		ep.ClientVersion != "" ||
		!strings.Contains(ep.Message, "download and install Hexproof") ||
		errEnv.ID != missingClientVersion.ID {
		t.Fatalf("missing client version response = id %q payload %+v",
			errEnv.ID, ep)
	}

	wrongClientVersion, _ := protocol.NewEnvelope(protocol.TypeSessionHello,
		protocol.SessionHello{
			DisplayName:   "Alice",
			ClientVersion: "99.0.0",
			Protocol:      protocol.ProtocolVersion,
		})
	wrongClientVersion.ID = "wrong-client-version"
	client.send(wrongClientVersion)
	errEnv = client.recvType(protocol.TypeError)
	_ = errEnv.DecodePayload(&ep)
	if ep.Code != protocol.ErrClientVersionMismatch ||
		ep.RequiredVersion != buildinfo.Version ||
		ep.ClientVersion != "99.0.0" ||
		!strings.Contains(ep.Message, "download and install Hexproof") ||
		errEnv.ID != wrongClientVersion.ID {
		t.Fatalf("wrong client version response = id %q payload %+v",
			errEnv.ID, ep)
	}

	longName, _ := protocol.NewEnvelope(protocol.TypeSessionHello, protocol.SessionHello{
		DisplayName: strings.Repeat("名", protocol.MaxDisplayNameRunes+1),
		Protocol:    protocol.ProtocolVersion,
	})
	longName.ID = "long-name"
	client.send(longName)
	errEnv = client.recvType(protocol.TypeError)
	_ = errEnv.DecodePayload(&ep)
	if ep.Code != protocol.ErrInvalidMessage || errEnv.ID != longName.ID {
		t.Fatalf("long name response = type %q id %q code %q", errEnv.Type, errEnv.ID, ep.Code)
	}

	controlName, _ := protocol.NewEnvelope(protocol.TypeSessionHello, protocol.SessionHello{
		DisplayName: "Alice\a", Protocol: protocol.ProtocolVersion,
	})
	controlName.ID = "control-name"
	client.send(controlName)
	errEnv = client.recvType(protocol.TypeError)
	_ = errEnv.DecodePayload(&ep)
	if ep.Code != protocol.ErrInvalidMessage || errEnv.ID != controlName.ID {
		t.Fatalf("control name response = type %q id %q code %q",
			errEnv.Type, errEnv.ID, ep.Code)
	}

	client.hello("  Alice  ")
	secondHello, _ := protocol.NewEnvelope(protocol.TypeSessionHello, protocol.SessionHello{
		DisplayName: "Mallory", Protocol: protocol.ProtocolVersion,
	})
	secondHello.ID = "second-hello"
	client.send(secondHello)
	errEnv = client.recvType(protocol.TypeError)
	_ = errEnv.DecodePayload(&ep)
	if ep.Code != protocol.ErrInvalidMessage || errEnv.ID != secondHello.ID {
		t.Fatalf("second hello response = type %q id %q code %q", errEnv.Type, errEnv.ID, ep.Code)
	}

	invalidRoom, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{
		Name: "  ", Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatCustom,
		MatchMode:       protocol.MatchBO1,
		AllowSpectators: true,
	})
	invalidRoom.ID = "invalid-room"
	client.send(invalidRoom)
	errEnv = client.recvType(protocol.TypeError)
	_ = errEnv.DecodePayload(&ep)
	if ep.Code != protocol.ErrInvalidMessage || errEnv.ID != invalidRoom.ID {
		t.Fatalf("invalid room response = type %q id %q code %q", errEnv.Type, errEnv.ID, ep.Code)
	}

	controlRoom, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{
		Name: "Room\a", Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatCustom,
		MatchMode:       protocol.MatchBO1,
		AllowSpectators: true,
	})
	controlRoom.ID = "control-room"
	client.send(controlRoom)
	errEnv = client.recvType(protocol.TypeError)
	_ = errEnv.DecodePayload(&ep)
	if ep.Code != protocol.ErrInvalidMessage || errEnv.ID != controlRoom.ID {
		t.Fatalf("control room response = type %q id %q code %q",
			errEnv.Type, errEnv.ID, ep.Code)
	}

	_, _ = client.createRoom("Room", protocol.FormatModern, 2, true, "")
	snapshot := client.recvType(protocol.TypeRoomSnapshot)
	var state protocol.RoomSnapshot
	if err := snapshot.DecodePayload(&state); err != nil {
		t.Fatalf("decode snapshot: %v", err)
	}
	if state.Seats[0].DisplayName != "Alice" {
		t.Fatalf("host display name = %q, want original handshake name Alice", state.Seats[0].DisplayName)
	}
}

func TestRequiredRequestIDs(t *testing.T) {
	required := []string{
		protocol.TypeSessionHello,
		protocol.TypeRoomCreate,
		protocol.TypeRoomJoin,
		protocol.TypeRoomKick,
		protocol.TypeRoomDisband,
		protocol.TypeDeckSelect,
		protocol.TypePlayerReady,
		protocol.TypeClientLoadComplete,
		protocol.TypeGameDraw,
		protocol.TypeGameShuffleLibrary,
		protocol.TypeGameMulligan,
		protocol.TypeGameDiscardHand,
		protocol.TypeGameMoveCard,
		protocol.TypeGameMoveCards,
		protocol.TypeGameMoveLibraryCards,
		protocol.TypeGameSetCardFace,
		protocol.TypeGameSetCardCounter,
		protocol.TypeGameSetPhase,
		protocol.TypeGameSetResponseStatus,
		protocol.TypeGameSetCounter,
		protocol.TypeGameSetCounterCount,
		protocol.TypeGameConcede,
		protocol.TypeGameReturnToRoom,
		protocol.TypeGameSay,
		protocol.TypeGameNextTurn,
		protocol.TypeGameReveal,
		protocol.TypeGameRecallRevealed,
		protocol.TypeGameDumpZone,
		protocol.TypeGameRespondZoneDump,
		protocol.TypeGameSearchLibrary,
		protocol.TypeGameReorderLibrary,
	}
	for _, messageType := range required {
		if !requiresRequestID(messageType) {
			t.Errorf("requiresRequestID(%q) = false, want true", messageType)
		}
	}
	for _, optional := range []string{protocol.TypeSessionPing, protocol.TypeRoomLeave} {
		if requiresRequestID(optional) {
			t.Errorf("requiresRequestID(%q) = true, want false", optional)
		}
	}
}

func TestShouldLogSessionEnd(t *testing.T) {
	for _, err := range []error{
		nil,
		context.Canceled,
		websocket.CloseError{Code: websocket.StatusNormalClosure},
		websocket.CloseError{Code: websocket.StatusGoingAway},
	} {
		if shouldLogSessionEnd(err) {
			t.Errorf("shouldLogSessionEnd(%v) = true, want false", err)
		}
	}
	if !shouldLogSessionEnd(errors.New("network failure")) {
		t.Error("unexpected network failure should be logged")
	}
}

// TestWrongPasswordRejected: password-protected room rejects empty password.
func TestWrongPasswordRejected(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	guest := dial(t, srv)
	defer guest.close()

	host.hello("Alice")
	guest.hello("Bob")

	_, roomID := host.createRoom("Private", protocol.FormatModern, 2, true, "secret")

	joinEnv, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{
		RoomID: roomID, AsSpectator: false, // no password
	})
	joinEnv.ID = "j"
	guest.send(joinEnv)
	err := guest.recvType(protocol.TypeError)
	var ep protocol.ErrorPayload
	if err2 := err.DecodePayload(&ep); err2 != nil {
		t.Fatalf("decode error: %v", err2)
	}
	if ep.Code != protocol.ErrWrongPassword {
		t.Fatalf("code = %q, want %q", ep.Code, protocol.ErrWrongPassword)
	}
}

func TestPasswordCheckRunsOutsideRoomOperationLock(t *testing.T) {
	hub := NewHub()
	r, err := room.New(
		"ABCDEF", "Private", protocol.FormatModern, protocol.MatchBO1,
		protocol.CardLoadPreload, 2, true, true,
		"Alice", "host-conn", time.Now().UTC())
	if err != nil {
		t.Fatalf("new room: %v", err)
	}
	entry := &roomEntry{room: r, passwordHash: []byte("test-hash")}
	hub.rooms[r.ID] = entry

	checkStarted := make(chan struct{})
	releaseCheck := make(chan struct{})
	hub.passwordCheck = func(hash []byte, password string) bool {
		close(checkStarted)
		<-releaseCheck
		return string(hash) == "test-hash" && password == "secret"
	}
	type beginJoinResult struct {
		entry *roomEntry
		err   error
	}
	result := make(chan beginJoinResult, 1)
	go func() {
		joinedEntry, joinErr := hub.beginJoin(r.ID, "secret")
		result <- beginJoinResult{entry: joinedEntry, err: joinErr}
	}()

	<-checkStarted
	if !entry.opMu.TryLock() {
		t.Fatal("room operation lock held during password comparison")
	}
	entry.opMu.Unlock()
	close(releaseCheck)

	joined := <-result
	if joined.err != nil || joined.entry != entry {
		t.Fatalf("begin join = entry %p err %v, want %p", joined.entry, joined.err, entry)
	}
	joined.entry.opMu.Unlock()
}

// TestSpectatorCap: 8 spectators allowed, 9th rejected.
func TestSpectatorCap(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	host.hello("Alice")
	_, roomID := host.createRoom("Spec EDH", protocol.FormatEDH, 4, true, "")

	for i := 0; i < protocol.MaxSpectators; i++ {
		sp := dial(t, srv)
		sp.hello("Spec")
		joinEnv, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{
			RoomID: roomID, AsSpectator: true,
		})
		joinEnv.ID = "j"
		sp.send(joinEnv)
		sp.recvType(protocol.TypeRoomJoined)
		// drain host snapshot fanout so its buffer doesn't block
		host.recvType(protocol.TypeRoomSnapshot)
	}

	// 9th spectator should be rejected.
	ninth := dial(t, srv)
	defer ninth.close()
	ninth.hello("Spec9")
	joinEnv, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{
		RoomID: roomID, AsSpectator: true,
	})
	joinEnv.ID = "j"
	ninth.send(joinEnv)
	err := ninth.recvType(protocol.TypeError)
	var ep protocol.ErrorPayload
	_ = err.DecodePayload(&ep)
	if ep.Code != protocol.ErrSpectatorLimit {
		t.Fatalf("9th spectator code = %q, want %q", ep.Code, protocol.ErrSpectatorLimit)
	}
}

// TestSeatsFull: Modern room (2 seats) rejects a 3rd player.
func TestSeatsFull(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	g1 := dial(t, srv)
	defer g1.close()
	g2 := dial(t, srv)
	defer g2.close()

	host.hello("Alice")
	g1.hello("Bob")
	g2.hello("Carol")

	_, roomID := host.createRoom("Modern", protocol.FormatModern, 2, true, "")
	joinRoom(t, g1, roomID, false)
	host.recvType(protocol.TypeRoomSnapshot) // drain fanout

	joinEnv, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{
		RoomID: roomID, AsSpectator: false,
	})
	joinEnv.ID = "j"
	g2.send(joinEnv)
	err := g2.recvType(protocol.TypeError)
	var ep protocol.ErrorPayload
	_ = err.DecodePayload(&ep)
	if ep.Code != protocol.ErrRoomFull {
		t.Fatalf("3rd player code = %q, want %q", ep.Code, protocol.ErrRoomFull)
	}
}

// TestHostKick: host kicks seat 1; guest receives room.kicked, is unbound
// (further commands fail with not_in_room), and host sees the seat freed.
func TestHostKick(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	guest := dial(t, srv)
	defer guest.close()

	host.hello("Alice")
	guest.hello("Bob")

	_, roomID := host.createRoom("EDH", protocol.FormatEDH, 4, true, "")
	joinRoom(t, guest, roomID, false)
	host.recvType(protocol.TypeRoomSnapshot) // drain join fanout

	seat := 1
	kickEnv, _ := protocol.NewEnvelope(protocol.TypeRoomKick, protocol.RoomKick{Seat: &seat})
	kickEnv.ID = "k"
	host.send(kickEnv)

	// Host: reply room.kicked (echo id) + snapshot with seat 1 free.
	hostReply := host.recvType(protocol.TypeRoomKicked)
	if hostReply.ID != "k" {
		t.Fatalf("host kicked reply id = %q, want k (echo)", hostReply.ID)
	}
	snap := host.recvType(protocol.TypeRoomSnapshot)
	var sp protocol.RoomSnapshot
	_ = snap.DecodePayload(&sp)
	if sp.Seats[1].Occupied {
		t.Fatalf("seat 1 should be free after kick: %+v", sp.Seats[1])
	}

	// Guest: server-push room.kicked (no echo id).
	guestKicked := guest.recvType(protocol.TypeRoomKicked)
	if guestKicked.ID != "" {
		t.Fatalf("guest kicked push should have no echoed id, got %q", guestKicked.ID)
	}

	// Guest is now unbound: a subsequent room.leave must fail with not_in_room.
	leaveEnv, _ := protocol.NewEnvelope(protocol.TypeRoomLeave, nil)
	leaveEnv.ID = "leave-after-kick"
	guest.send(leaveEnv)
	err := guest.recvType(protocol.TypeError)
	var ep protocol.ErrorPayload
	_ = err.DecodePayload(&ep)
	if ep.Code != protocol.ErrNotInRoom {
		t.Fatalf("kicked guest leave code = %q, want %q", ep.Code, protocol.ErrNotInRoom)
	}
}

// TestKickSpectatorByIndex: host kicks spectator by index.
func TestKickSpectatorByIndex(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	spec := dial(t, srv)
	defer spec.close()

	host.hello("Alice")
	spec.hello("Spec")
	_, roomID := host.createRoom("EDH", protocol.FormatEDH, 4, true, "")
	joinRoom(t, spec, roomID, true)
	host.recvType(protocol.TypeRoomSnapshot) // drain

	idx := 0
	kickEnv, _ := protocol.NewEnvelope(protocol.TypeRoomKick, protocol.RoomKick{SpectatorIndex: &idx})
	kickEnv.ID = "k"
	host.send(kickEnv)
	host.recvType(protocol.TypeRoomKicked)

	// Spectator receives a server-push room.kicked.
	spec.recvType(protocol.TypeRoomKicked)

	// Snapshot shows no spectators.
	snap := host.recvType(protocol.TypeRoomSnapshot)
	var sp protocol.RoomSnapshot
	_ = snap.DecodePayload(&sp)
	if len(sp.Spectators) != 0 {
		t.Fatalf("spectators after kick = %d, want 0", len(sp.Spectators))
	}
}

// TestKickHostRejected: host cannot kick their own seat.
func TestKickHostRejected(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	host.hello("Alice")
	_, _ = host.createRoom("EDH", protocol.FormatEDH, 4, true, "")
	host.recvType(protocol.TypeRoomSnapshot) // drain

	seat := 0
	kickEnv, _ := protocol.NewEnvelope(protocol.TypeRoomKick, protocol.RoomKick{Seat: &seat})
	kickEnv.ID = "k"
	host.send(kickEnv)
	err := host.recvType(protocol.TypeError)
	var ep protocol.ErrorPayload
	_ = err.DecodePayload(&ep)
	if ep.Code != protocol.ErrCannotKickHost {
		t.Fatalf("kick host code = %q, want %q", ep.Code, protocol.ErrCannotKickHost)
	}
}

// TestCreateWhileInRoom: a host already in a room cannot create another.
func TestCreateWhileInRoom(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	host.hello("Alice")
	_, _ = host.createRoom("First", protocol.FormatEDH, 4, true, "")
	host.recvType(protocol.TypeRoomSnapshot) // drain

	// Attempt a second create while still in the first room.
	createEnv, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{
		Name: "Second", Format: protocol.FormatEDH, DeckFormat: protocol.DeckFormatCommander,
		AllowSpectators: true, MatchMode: protocol.MatchBO3,
	})
	createEnv.ID = "c2"
	host.send(createEnv)
	err := host.recvType(protocol.TypeError)
	var ep protocol.ErrorPayload
	_ = err.DecodePayload(&ep)
	if ep.Code != protocol.ErrAlreadyInRoom {
		t.Fatalf("second create code = %q, want %q", ep.Code, protocol.ErrAlreadyInRoom)
	}
}

// TestHostLeaveDisbands: host leaving disbands the room; host receives
// room.disbanded (reply, echo id), guest receives room.disbanded (broadcast).
func TestHostLeaveDisbands(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	guest := dial(t, srv)
	defer guest.close()

	host.hello("Alice")
	guest.hello("Bob")

	_, roomID := host.createRoom("EDH", protocol.FormatEDH, 4, true, "")
	joinRoom(t, guest, roomID, false)
	host.recvType(protocol.TypeRoomSnapshot) // drain

	leaveEnv, _ := protocol.NewEnvelope(protocol.TypeRoomLeave, nil)
	leaveEnv.ID = "l"
	host.send(leaveEnv)

	// Host gets room.disbanded reply with echoed id.
	hostDisbanded := host.recvType(protocol.TypeRoomDisbanded)
	if hostDisbanded.ID != "l" {
		t.Fatalf("host disbanded reply id = %q, want l (echo)", hostDisbanded.ID)
	}

	// Guest gets room.disbanded broadcast (no echoed id).
	guestDisbanded := guest.recvType(protocol.TypeRoomDisbanded)
	if guestDisbanded.ID != "" {
		t.Fatalf("guest disbanded broadcast should have no echoed id, got %q", guestDisbanded.ID)
	}
	assertCanCreateRoom(t, guest, roomID)
}

func TestExplicitDisbandUnbindsGuest(t *testing.T) {
	srv, _ := newTestServer(t)
	host := dial(t, srv)
	defer host.close()
	guest := dial(t, srv)
	defer guest.close()

	host.hello("Alice")
	guest.hello("Bob")
	_, roomID := host.createRoom("EDH", protocol.FormatEDH, 4, true, "")
	host.recvType(protocol.TypeRoomSnapshot)
	joinRoom(t, guest, roomID, false)
	host.recvType(protocol.TypeRoomSnapshot)

	disband, _ := protocol.NewEnvelope(protocol.TypeRoomDisband, nil)
	disband.ID = "d"
	host.send(disband)
	if reply := host.recvType(protocol.TypeRoomDisbanded); reply.ID != disband.ID {
		t.Fatalf("host disband reply id = %q, want %q", reply.ID, disband.ID)
	}
	if push := guest.recvType(protocol.TypeRoomDisbanded); push.ID != "" {
		t.Fatalf("guest disband push id = %q, want empty", push.ID)
	}
	assertCanCreateRoom(t, guest, roomID)
}

func TestReconnectRestoresHostSeatAndPrivateProjection(t *testing.T) {
	config := DefaultConfig()
	config.ReconnectWindow = 500 * time.Millisecond
	srv, handler := newConfiguredTestServer(t, config)
	host := dial(t, srv)
	guest := dial(t, srv)
	defer guest.close()

	hostWelcomeEnvelope := host.hello("Alice")
	var hostWelcome protocol.SessionWelcome
	if err := hostWelcomeEnvelope.DecodePayload(&hostWelcome); err != nil {
		t.Fatalf("decode host welcome: %v", err)
	}
	if hostWelcome.ResumeToken == "" {
		t.Fatal("initial welcome omitted resume token")
	}
	guest.hello("Bob")
	_, roomID := host.createRoom("Modern", protocol.FormatModern, 2, true, "")
	host.recvType(protocol.TypeRoomSnapshot)
	joinRoom(t, guest, roomID, false)
	host.recvType(protocol.TypeRoomSnapshot)
	guest.recvType(protocol.TypeRoomSnapshot)

	r := handler.hub.FindRoom(roomID)
	operation, err := handler.hub.lockRoomOperation(roomID)
	if err != nil {
		t.Fatalf("lock room: %v", err)
	}
	operation.mu.Lock()
	r.Phase = protocol.RoomPhaseStarted
	r.Score = []int{0, 0}
	r.Game = &room.GameState{
		Number:       1,
		StartingSeat: 0,
		ActiveSeat:   0,
		CurrentPhase: protocol.GamePhaseUntap,
		Seats: []room.PlayerGameState{
			{
				Seat: 0, DisplayName: "Alice", Life: 20,
				Hand: []protocol.GameCard{{
					ID: "alice-secret", Name: "Lightning Bolt",
					SetCode: "M11", CollectorNumber: "149",
				}},
				Library: []protocol.GameCard{{
					ID: "alice-library", Name: "Mountain",
					SetCode: "M11", CollectorNumber: "242",
				}},
			},
			{
				Seat: 1, DisplayName: "Bob", Life: 20,
				Hand: []protocol.GameCard{{
					ID: "bob-secret", Name: "Counterspell",
					SetCode: "MH2", CollectorNumber: "267",
				}},
			},
		},
		Stack:       []protocol.GameSharedCard{},
		Revealed:    []protocol.GameSharedCard{},
		Log:         []protocol.GameLogEntry{},
		NextLogID:   1,
		NextTokenID: 1,
	}
	operation.mu.Unlock()
	operation.opMu.Unlock()

	host.close()
	time.Sleep(30 * time.Millisecond)

	resumedHost := dial(t, srv)
	defer resumedHost.close()
	resumedWelcome := resumedHost.resume("Alice", hostWelcome.ResumeToken, 2)
	if !resumedWelcome.Resumed || resumedWelcome.RoomID != roomID ||
		resumedWelcome.Role != protocol.RolePlayer ||
		resumedWelcome.Seat == nil || *resumedWelcome.Seat != 0 ||
		!resumedWelcome.Host {
		t.Fatalf("resumed welcome = %+v", resumedWelcome)
	}
	if resumedWelcome.ResumeToken == "" ||
		resumedWelcome.ResumeToken == hostWelcome.ResumeToken {
		t.Fatalf("resumed token was not rotated: initial=%q resumed=%q",
			hostWelcome.ResumeToken, resumedWelcome.ResumeToken)
	}
	resumedHost.recvType(protocol.TypeRoomSnapshot)
	gameEnvelope := resumedHost.recvType(protocol.TypeGameSnapshot)
	var game protocol.GameSnapshot
	if err := gameEnvelope.DecodePayload(&game); err != nil {
		t.Fatalf("decode resumed game: %v", err)
	}
	if len(game.Seats[0].Hand) != 1 ||
		game.Seats[0].Hand[0].ID != "alice-secret" ||
		len(game.Seats[1].Hand) != 0 {
		t.Fatalf("resumed private projection = %+v", game.Seats)
	}

	spectator := dial(t, srv)
	spectatorWelcomeEnvelope := spectator.hello("Observer")
	var spectatorWelcome protocol.SessionWelcome
	if err := spectatorWelcomeEnvelope.DecodePayload(&spectatorWelcome); err != nil {
		t.Fatalf("decode spectator welcome: %v", err)
	}
	joinRoom(t, spectator, roomID, true)
	spectator.recvType(protocol.TypeRoomSnapshot)
	spectator.recvType(protocol.TypeGameSnapshot)
	spectator.close()
	time.Sleep(30 * time.Millisecond)

	resumedSpectator := dial(t, srv)
	defer resumedSpectator.close()
	resumedObserverWelcome := resumedSpectator.resume(
		"Observer", spectatorWelcome.ResumeToken, 0)
	if !resumedObserverWelcome.Resumed ||
		resumedObserverWelcome.Role != protocol.RoleSpectator ||
		resumedObserverWelcome.Seat != nil {
		t.Fatalf("resumed spectator welcome = %+v", resumedObserverWelcome)
	}
	if resumedObserverWelcome.ResumeToken == "" ||
		resumedObserverWelcome.ResumeToken == spectatorWelcome.ResumeToken {
		t.Fatalf("spectator token was not rotated: initial=%q resumed=%q",
			spectatorWelcome.ResumeToken, resumedObserverWelcome.ResumeToken)
	}
	resumedSpectator.recvType(protocol.TypeRoomSnapshot)
	spectatorGameEnvelope := resumedSpectator.recvType(protocol.TypeGameSnapshot)
	var spectatorGame protocol.GameSnapshot
	if err := spectatorGameEnvelope.DecodePayload(&spectatorGame); err != nil {
		t.Fatalf("decode resumed spectator game: %v", err)
	}
	if len(spectatorGame.Seats[0].Hand) != 0 ||
		len(spectatorGame.Seats[1].Hand) != 0 ||
		spectatorGame.Seats[0].HandCount != 1 ||
		spectatorGame.Seats[1].HandCount != 1 {
		t.Fatalf("spectator reconnect leaked hidden hands: %+v", spectatorGame.Seats)
	}
}

func TestReconnectExpiryTransfersHostWithoutDisbandingRoom(t *testing.T) {
	config := DefaultConfig()
	config.ReconnectWindow = 60 * time.Millisecond
	srv, _ := newConfiguredTestServer(t, config)
	host := dial(t, srv)
	guest := dial(t, srv)
	defer guest.close()

	host.hello("Alice")
	guest.hello("Bob")
	_, roomID := host.createRoom("Modern", protocol.FormatModern, 2, true, "")
	host.recvType(protocol.TypeRoomSnapshot)
	joinRoom(t, guest, roomID, false)
	host.recvType(protocol.TypeRoomSnapshot)
	guest.recvType(protocol.TypeRoomSnapshot)

	host.close()
	expiredSnapshot := guest.recvType(protocol.TypeRoomSnapshot)
	var expired protocol.RoomSnapshot
	if err := expiredSnapshot.DecodePayload(&expired); err != nil {
		t.Fatalf("decode expiry snapshot: %v", err)
	}
	if expired.Seats[0].Occupied || expired.HostSeat != 1 ||
		!expired.Seats[1].Host {
		t.Fatalf("expired host seat = %+v hostSeat=%d", expired.Seats[0], expired.HostSeat)
	}

	replacement := dial(t, srv)
	defer replacement.close()
	replacement.hello("Carol")
	joinRoom(t, replacement, roomID, false)
	replacementSnapshot := replacement.recvType(protocol.TypeRoomSnapshot)
	var joined protocol.RoomSnapshot
	if err := replacementSnapshot.DecodePayload(&joined); err != nil {
		t.Fatalf("decode replacement snapshot: %v", err)
	}
	if !joined.Seats[0].Occupied || joined.Seats[0].DisplayName != "Carol" ||
		joined.Seats[0].Host || !joined.Seats[1].Host {
		t.Fatalf("replacement seat = %+v", joined.Seats[0])
	}
}

func TestReconnectExpiryForfeitsStartedModernMatch(t *testing.T) {
	config := DefaultConfig()
	config.ReconnectWindow = 60 * time.Millisecond
	srv, handler := newConfiguredTestServer(t, config)
	host := dial(t, srv)
	defer host.close()
	guest := dial(t, srv)

	host.hello("Alice")
	guest.hello("Bob")
	_, roomID := host.createRoom("Modern", protocol.FormatModern, 2, true, "")
	host.recvType(protocol.TypeRoomSnapshot)
	joinRoom(t, guest, roomID, false)
	host.recvType(protocol.TypeRoomSnapshot)
	guest.recvType(protocol.TypeRoomSnapshot)

	r := handler.hub.FindRoom(roomID)
	operation, err := handler.hub.lockRoomOperation(roomID)
	if err != nil {
		t.Fatalf("lock room: %v", err)
	}
	operation.mu.Lock()
	r.Phase = protocol.RoomPhaseStarted
	r.Score = []int{0, 0}
	r.Game = &room.GameState{
		Number:       1,
		StartingSeat: 1,
		ActiveSeat:   1,
		CurrentPhase: protocol.GamePhaseEnd,
		Seats: []room.PlayerGameState{
			{Seat: 0, DisplayName: "Alice", Life: 20},
			{Seat: 1, DisplayName: "Bob", Life: 20},
		},
		Log:       []protocol.GameLogEntry{},
		NextLogID: 1,
	}
	operation.mu.Unlock()
	operation.opMu.Unlock()

	guest.close()
	host.recvType(protocol.TypeRoomSnapshot)
	gameEnvelope := host.recvType(protocol.TypeGameSnapshot)
	var game protocol.GameSnapshot
	if err := gameEnvelope.DecodePayload(&game); err != nil {
		t.Fatalf("decode departure game: %v", err)
	}
	if game.Result == nil ||
		game.Result.Reason != protocol.GameResultDeparture ||
		game.Result.WinnerSeat != 0 ||
		game.Result.ConcededSeat != 1 ||
		!game.Result.MatchFinished ||
		game.ActiveSeat != -1 ||
		len(game.Score) != 2 || game.Score[0] != 2 ||
		len(game.Log) != 1 || game.Log[0].Kind != "departure" {
		t.Fatalf("departure projection = %+v", game)
	}
}

func TestConcurrentJoinAndDisbandLeavesSessionReusable(t *testing.T) {
	for i := 0; i < 25; i++ {
		srv, _ := newTestServer(t)
		host := dial(t, srv)
		guest := dial(t, srv)
		host.hello("Alice")
		guest.hello("Bob")
		_, roomID := host.createRoom("EDH", protocol.FormatEDH, 4, true, "")
		host.recvType(protocol.TypeRoomSnapshot)

		join, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: roomID})
		join.ID = "concurrent-join"
		disband, _ := protocol.NewEnvelope(protocol.TypeRoomDisband, nil)
		disband.ID = "concurrent-disband"
		guest.send(join)
		host.send(disband)
		host.recvType(protocol.TypeRoomDisbanded)

		assertCanCreateRoom(t, guest, roomID)
		host.close()
		guest.close()
		srv.Close()
	}
}

// joinRoom is a helper that joins a client to a room and drains the joined reply.
func joinRoom(t *testing.T, c *wsClient, roomID string, asSpec bool) {
	t.Helper()
	joinEnv, _ := protocol.NewEnvelope(protocol.TypeRoomJoin, protocol.RoomJoin{
		RoomID: roomID, AsSpectator: asSpec,
	})
	joinEnv.ID = "j"
	c.send(joinEnv)
	c.recvType(protocol.TypeRoomJoined)
}

func assertCanCreateRoom(t *testing.T, c *wsClient, previousRoomID string) {
	t.Helper()
	env, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{
		Name: "Next room", Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatCustom,
		AllowSpectators: true,
		MatchMode:       protocol.MatchBO1,
	})
	env.ID = "create-after-disband"
	c.send(env)
	var result protocol.Envelope
	for i := 0; i < 12; i++ {
		candidate := c.recv()
		if candidate.ID == env.ID && (candidate.Type == protocol.TypeRoomCreated || candidate.Type == protocol.TypeError) {
			result = candidate
			break
		}
	}
	if result.Type == "" {
		t.Fatal("no correlated create result after disband")
	}
	if result.Type == protocol.TypeError {
		var ep protocol.ErrorPayload
		_ = result.DecodePayload(&ep)
		t.Fatalf("create after disband failed: %s: %s", ep.Code, ep.Message)
	}
	var created protocol.RoomCreated
	if err := result.DecodePayload(&created); err != nil {
		t.Fatalf("decode created: %v", err)
	}
	if created.RoomID == "" || created.RoomID == previousRoomID {
		t.Fatalf("new room id = %q, previous = %q", created.RoomID, previousRoomID)
	}
	c.recvType(protocol.TypeRoomSnapshot)
}

func TestSessionHelloTimeoutClosesIdleConnection(t *testing.T) {
	config := DefaultConfig()
	config.HelloTimeout = 50 * time.Millisecond
	srv, _ := newConfiguredTestServer(t, config)
	client := dial(t, srv)
	defer client.close()
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	_, _, err := client.conn.Read(ctx)
	if err == nil {
		t.Fatal("idle connection remained open past session.hello timeout")
	}
	if status := websocket.CloseStatus(err); status != websocket.StatusPolicyViolation {
		t.Fatalf("hello timeout close status = %v, want %v (err=%v)",
			status, websocket.StatusPolicyViolation, err)
	}
}

func TestPasswordJoinRateLimitResetsAfterWindow(t *testing.T) {
	handler := NewHandler()
	handler.config.PasswordJoinsPerMinute = 2
	now := time.Date(2026, time.August, 5, 10, 0, 0, 0, time.UTC)
	if !handler.allowPasswordJoin("203.0.113.5", now) ||
		!handler.allowPasswordJoin("203.0.113.5", now.Add(time.Second)) {
		t.Fatal("allowed password joins were rejected")
	}
	if handler.allowPasswordJoin("203.0.113.5", now.Add(2*time.Second)) {
		t.Fatal("password join rate limit did not reject excess attempt")
	}
	if !handler.allowPasswordJoin("203.0.113.5", now.Add(time.Minute)) {
		t.Fatal("password join rate limit did not reset")
	}
}

func TestReplayRequestRateLimitIsPerIPAndResetsAfterWindow(t *testing.T) {
	handler := NewHandler()
	handler.config.ReplayRequestsPerMinute = 2
	now := time.Date(2026, time.August, 5, 10, 0, 0, 0, time.UTC)
	if !handler.allowReplayRequest("203.0.113.5", now) ||
		!handler.allowReplayRequest("203.0.113.5", now.Add(time.Second)) {
		t.Fatal("allowed replay requests were rejected")
	}
	if handler.allowReplayRequest("203.0.113.5", now.Add(2*time.Second)) {
		t.Fatal("replay request rate limit did not reject excess attempt")
	}
	if !handler.allowReplayRequest("198.51.100.8", now.Add(2*time.Second)) {
		t.Fatal("one client IP exhausted another client's replay allowance")
	}
	if !handler.allowReplayRequest("203.0.113.5", now.Add(time.Minute)) {
		t.Fatal("replay request rate limit did not reset")
	}
}

func TestPasswordCheckConcurrencyIsBounded(t *testing.T) {
	hub := NewHubWithLimits(4, 1)
	r, err := room.New(
		"ABCDEF", "Protected", protocol.FormatModern, protocol.MatchBO1,
		protocol.CardLoadPreload, 2, true, true, "Alice", "host", time.Now().UTC())
	if err != nil {
		t.Fatalf("new room: %v", err)
	}
	hub.rooms[r.ID] = &roomEntry{room: r, passwordHash: []byte("hash")}
	entered := make(chan struct{})
	release := make(chan struct{})
	hub.passwordCheck = func([]byte, string) bool {
		close(entered)
		<-release
		return true
	}
	result := make(chan error, 1)
	go func() {
		entry, err := hub.beginJoin(r.ID, "secret")
		if err == nil {
			entry.opMu.Unlock()
		}
		result <- err
	}()
	select {
	case <-entered:
	case <-time.After(time.Second):
		t.Fatal("first password check did not start")
	}
	if _, err := hub.beginJoin(r.ID, "secret"); err == nil {
		t.Fatal("second concurrent password check was accepted")
	} else if code, ok := ErrCode(err); !ok || code != protocol.ErrRateLimited {
		t.Fatalf("second password check err=%v code=%q", err, code)
	}
	close(release)
	if err := <-result; err != nil {
		t.Fatalf("first password check failed: %v", err)
	}
}
