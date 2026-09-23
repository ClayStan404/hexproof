//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/buildinfo"
	"hexproof/server/internal/forgehost"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"

	"github.com/coder/websocket"
)

// TestLiveForgeWebSocketMatch uses the real packaged Java engine and only the
// authenticated, normalized WebSocket API for game setup and decisions. The
// synthetic players finish by casting Lightning Bolt, never by conceding or
// mutating the engine/room state. Run explicitly with engineintegration and
// HEXPROOF_REAL_FORGE_ROOT naming an extracted pinned Forge runtime.
func TestLiveForgeWebSocketMatch(t *testing.T) {
	runLiveForgeWebSocketMatch(t, protocol.MatchBO1)
}

func TestLiveForgeWebSocketBO3Match(t *testing.T) {
	runLiveForgeWebSocketMatch(t, protocol.MatchBO3)
}

func runLiveForgeWebSocketMatch(t *testing.T, matchMode string) {
	srv, handler := newLiveForgeWebSocketServer(t)
	runLiveForgeWebSocketRoom(t, srv, handler, matchMode)
}

// The production handler owns one hosted JVM per game. Exercise concurrent
// rooms and replacement processes across successive waves.
func TestLiveForgeIsolatedRuntimeRooms(t *testing.T) {
	srv, handler := newLiveForgeWebSocketServer(t, 4)
	// Reuse the handler across waves; each new game must start its own JVM
	// after previous games have finished and their processes have been reaped.
	for wave := 0; wave < 5; wave++ {
		t.Run(fmt.Sprintf("wave-%d", wave), func(t *testing.T) {
			for roomNumber := 0; roomNumber < 4; roomNumber++ {
				t.Run(fmt.Sprintf("room-%d", roomNumber), func(t *testing.T) {
					t.Parallel()
					runLiveForgeWebSocketRoom(t, srv, handler, protocol.MatchBO1)
				})
			}
		})
	}
}

// Exercise the public room coordinator over two bounded JVMs, including BO3,
// restart, reconnect, private sideboarding and spectator projections.
func TestLiveForgeSharedRuntimeRooms(t *testing.T) {
	srv, handler := newLiveForgeWebSocketServer(t, 4, 2)
	for wave := range 3 {
		t.Run(fmt.Sprintf("wave-%d", wave), func(t *testing.T) {
			for roomNumber := range 4 {
				t.Run(fmt.Sprintf("room-%d", roomNumber), func(t *testing.T) {
					t.Parallel()
					mode := protocol.MatchBO1
					if roomNumber == 0 {
						mode = protocol.MatchBO3
					}
					runLiveForgeWebSocketRoom(t, srv, handler, mode)
				})
			}
		})
	}
}

func newLiveForgeWebSocketServer(t *testing.T, maxGames ...int) (*httptest.Server, *Handler) {
	t.Helper()
	runtimeRoot := os.Getenv("HEXPROOF_REAL_FORGE_ROOT")
	if runtimeRoot == "" {
		t.Fatal("HEXPROOF_REAL_FORGE_ROOT must name an extracted pinned runtime")
	}
	runtimeRoot, err := filepath.Abs(runtimeRoot)
	if err != nil {
		t.Fatal(err)
	}
	runtime := forge.JavaProcessConfig(os.Getenv("HEXPROOF_FORGE_JAVA"),
		filepath.Join(runtimeRoot, "forge-harness.jar"), filepath.Join(runtimeRoot, "forge-gui"))
	runtime.Dir = t.TempDir()
	runtime.Args = append([]string{"-Xmx1536m", "-Djava.awt.headless=true", "-Duser.home=" + runtime.Dir}, runtime.Args...)
	diagnostics, err := os.CreateTemp(t.TempDir(), "synthetic-engine-*.log")
	if err != nil {
		t.Fatal(err)
	}
	runtime.Stderr = diagnostics
	t.Cleanup(func() {
		_ = diagnostics.Close()
		if t.Failed() {
			data, _ := os.ReadFile(diagnostics.Name())
			t.Logf("synthetic-engine diagnostics: %s", data)
		}
	})
	config := DefaultConfig()
	config.RetentionDir = t.TempDir()
	if len(maxGames) > 0 {
		config.MaxForgeGames = maxGames[0]
	}
	if len(maxGames) > 1 {
		config.ForgeGamesPerJVM = maxGames[1]
	}
	config.ForgeRuntime = &runtime
	// The automated participants exceed human input rates. Rate limiting is
	// covered independently; keep this opt-in conformance test engine-bound.
	config.MessagesPerSecond = 10000
	config.RoomCreatesPerMinute = 10000
	config.ReconnectWindow = time.Minute
	srv, handler := newConfiguredTestServer(t, config)
	t.Cleanup(func() { _ = handler.Close() })
	return srv, handler
}

func runLiveForgeWebSocketRoom(t *testing.T, srv *httptest.Server, handler *Handler, matchMode string, hostedRuntime ...forge.ProcessConfig) {
	runLiveForgeWebSocketStudy(t, srv, handler, matchMode, nil, hostedRuntime...)
}

type liveForgeStudyHook func(context.Context, string, []*liveForgePeer, *liveForgePeer, int)

func runLiveForgeWebSocketStudy(t *testing.T, srv *httptest.Server, handler *Handler, matchMode string, hook liveForgeStudyHook, hostedRuntime ...forge.ProcessConfig) {
	runLiveForgePeerStudy(t, srv, handler, matchMode, hook, forgehost.WorkerPeer{}, hostedRuntime...)
}

func runLiveForgePeerStudy(t *testing.T, srv *httptest.Server, handler *Handler, matchMode string, hook liveForgeStudyHook, peerWorker forgehost.WorkerPeer, hostedRuntime ...forge.ProcessConfig) {
	t.Helper()
	started := time.Now()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()
	players := []*liveForgePeer{
		{client: dialLiveForge(t, srv), seat: 0, name: "Synthetic Burn A"},
		{client: dialLiveForge(t, srv), seat: 1, name: "Synthetic Burn B"},
	}
	for _, player := range players {
		defer func(peer *liveForgePeer) { _ = peer.client.conn.CloseNow() }(player)
		player.command(t, ctx, protocol.TypeSessionHello, "hello", protocol.SessionHello{
			DisplayName: player.name, ClientVersion: buildinfo.Version, Protocol: protocol.ProtocolVersion,
		})
		welcome := player.until(t, ctx, protocol.TypeSessionWelcome)
		if err := welcome.DecodePayload(&player.welcome); err != nil || player.welcome.ResumeToken == "" {
			t.Fatalf("initial welcome missing authenticated resume token: %v", err)
		}
	}
	host, guest := players[0], players[1]
	hostingMode := ""
	if len(hostedRuntime) > 0 {
		hostingMode = "player"
	}
	host.command(t, ctx, protocol.TypeRoomCreate, "create", protocol.RoomCreate{
		Name: "Synthetic Forge E2E", Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatCustom,
		RulesMode: protocol.RulesModeForge, MatchMode: matchMode, HostingMode: hostingMode,
		MaxSeats: 2, AllowSpectators: true, CardLoadMode: protocol.CardLoadBackground,
	})
	created := host.until(t, ctx, protocol.TypeRoomCreated)
	var roomCreated protocol.RoomCreated
	if err := created.DecodePayload(&roomCreated); err != nil || roomCreated.RoomID == "" {
		t.Fatalf("create room: %v", err)
	}
	roomID := roomCreated.RoomID
	if len(hostedRuntime) > 0 {
		envelope := host.until(t, ctx, protocol.TypeForgeHostGrant)
		var grant protocol.ForgeHostGrant
		if err := envelope.DecodePayload(&grant); err != nil {
			t.Fatal(err)
		}
		workerCtx, stopWorker := context.WithCancel(ctx)
		completed := make(chan error, 1)
		go func() {
			completed <- forgehost.Run(workerCtx, forgehost.WorkerConfig{
				ServerURL: "ws" + strings.TrimPrefix(srv.URL, "http"), RoomID: roomID, Token: grant.Token, GraceSeconds: grant.GraceSeconds,
			}, func(ctx context.Context) (forge.Runtime, error) { return forge.Start(ctx, hostedRuntime[0]) }, nil, peerWorker)
		}()
		defer func() {
			stopWorker()
			select {
			case <-completed:
			case <-time.After(5 * time.Second):
				t.Error("host worker leaked")
			}
		}()
		for {
			status := host.until(t, ctx, protocol.TypeForgeHostStatus)
			var state protocol.ForgeHostStatus
			if err := status.DecodePayload(&state); err != nil {
				t.Fatal(err)
			}
			if state.Connected {
				break
			}
		}
	}
	guest.command(t, ctx, protocol.TypeRoomJoin, "join", protocol.RoomJoin{RoomID: roomID, AcceptPlayerHost: len(hostedRuntime) > 0})
	guest.until(t, ctx, protocol.TypeRoomJoined)
	deck := protocol.DeckSelect{
		Name: "Synthetic Burn", Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatCustom,
		Mainboard: []protocol.DeckCard{
			{Name: "Mountain", Count: 24, SetCode: "M11", CollectorNumber: "242"},
			{Name: "Lightning Bolt", Count: 36, SetCode: "M11", CollectorNumber: "149"},
		},
		Sideboard: []protocol.DeckCard{},
	}
	for _, player := range players {
		player.command(t, ctx, protocol.TypeDeckSelect, "deck", deck)
		player.until(t, ctx, protocol.TypeDeckSelected)
		player.command(t, ctx, protocol.TypePlayerReady, "ready", protocol.PlayerReady{Ready: true})
		player.until(t, ctx, protocol.TypePlayerReadyChanged)
	}
	for _, player := range players {
		player.until(t, ctx, protocol.TypeRulesPrompt)
		if player.snapshot.GameID == "" {
			t.Fatal("initial private prompt arrived without a normalized snapshot")
		}
	}
	t.Logf("real WebSocket Forge match ready in %s", time.Since(started))

	// A late observer must receive only public state, not cached player data.
	observer := &liveForgePeer{client: dialLiveForge(t, srv), seat: -1, name: "Synthetic Observer"}
	defer observer.client.conn.CloseNow()
	observer.command(t, ctx, protocol.TypeSessionHello, "hello", protocol.SessionHello{
		DisplayName: observer.name, ClientVersion: buildinfo.Version, Protocol: protocol.ProtocolVersion,
	})
	observer.until(t, ctx, protocol.TypeSessionWelcome)
	observer.command(t, ctx, protocol.TypeRoomJoin, "watch", protocol.RoomJoin{RoomID: roomID, AsSpectator: true, AcceptPlayerHost: len(hostedRuntime) > 0})
	observer.until(t, ctx, protocol.TypeRulesSnapshot)
	if observer.snapshot.GameID != host.snapshot.GameID {
		t.Fatal("late spectator joined a different engine game")
	}

	stats := make(map[string]int)
	var actionLatencies []time.Duration
	resumed := false
	for decisions := 0; decisions < 1500; decisions++ {
		if host.snapshot.GameOver {
			break
		}
		if hook != nil {
			hook(ctx, roomID, players, observer, decisions)
		}
		actor := liveForgeActor(t, players)
		if decisions == 12 {
			// Reconnect while this player owns an unanswered private prompt.
			before := actor.prompt.PromptID
			token := actor.welcome.ResumeToken
			_ = actor.client.conn.CloseNow()
			waitCtx, stopWaiting := context.WithTimeout(ctx, 5*time.Second)
			for {
				handler.resumeMu.Lock()
				_, held := handler.resumeHolds[token]
				handler.resumeMu.Unlock()
				if held {
					break
				}
				select {
				case <-waitCtx.Done():
					t.Fatal("disconnected player was not available for resume")
				case <-time.After(5 * time.Millisecond):
				}
			}
			stopWaiting()
			actor.client = dialLiveForge(t, srv)
			actor.command(t, ctx, protocol.TypeSessionHello, "resume", protocol.SessionHello{
				DisplayName: actor.name, ClientVersion: buildinfo.Version, Protocol: protocol.ProtocolVersion,
				ResumeToken: token, LastSeq: 0,
			})
			welcome := actor.until(t, ctx, protocol.TypeSessionWelcome)
			if err := welcome.DecodePayload(&actor.welcome); err != nil || !actor.welcome.Resumed ||
				actor.welcome.RoomID != roomID || actor.welcome.Seat == nil || *actor.welcome.Seat != actor.seat ||
				actor.welcome.ResumeToken == token {
				t.Fatalf("private player resume failed: %v", err)
			}
			actor.until(t, ctx, protocol.TypeRulesPrompt)
			if actor.prompt.PromptID != before || !actor.prompt.Pending || actor.snapshot.GameID != observer.snapshot.GameID {
				t.Fatal("resume did not restore the player's existing game and private prompt")
			}
			// Resume republishes fresh projections to the whole room. Consume
			// that update before submitting the next decision, so the test
			// cannot confuse its queued prompt with the action's later reply.
			for _, player := range players {
				if player != actor {
					player.until(t, ctx, protocol.TypeRulesPrompt)
				}
			}
			observer.until(t, ctx, protocol.TypeRulesSnapshot)
			resumed = true
		}
		answer := liveForgeAnswer(t, actor, stats)

		decisionKind := actor.prompt.Kind
		if decisions == 0 {
			// Knowing a prompt id and response token does not grant authority:
			// another player and a spectator must both be rejected over WS.
			for _, attempt := range []struct {
				peer *liveForgePeer
				code string
			}{
				{players[1-actor.seat], protocol.ErrRulesActionRejected},
				{observer, protocol.ErrNotPlayer},
			} {
				attempt.peer.command(t, ctx, protocol.TypeRulesRespond, "not-your-prompt", answer)
				rejected := attempt.peer.until(t, ctx, protocol.TypeError)
				var failure protocol.ErrorPayload
				if err := rejected.DecodePayload(&failure); err != nil || rejected.ID != "not-your-prompt" || failure.Code != attempt.code {
					t.Fatalf("unauthorized response was not rejected with %s: %s", attempt.code, rejected.Payload)
				}
			}
		}
		requestID := fmt.Sprintf("decision-%d", decisions)
		submittedAt := time.Now()
		actor.command(t, ctx, protocol.TypeRulesRespond, requestID, answer)
		ack := actor.until(t, ctx, protocol.TypeRulesResponded)
		actionLatencies = append(actionLatencies, time.Since(submittedAt))
		var responded protocol.RulesResponded
		if err := ack.DecodePayload(&responded); err != nil || ack.ID != requestID || responded.PromptID != answer.PromptID {
			t.Fatalf("uncorrelated decision acknowledgement: %v", err)
		}
		stats[decisionKind]++
		for _, player := range players {
			player.until(t, ctx, protocol.TypeRulesPrompt)
		}
		observer.until(t, ctx, protocol.TypeRulesSnapshot)
		if decisions < 10 || decisions%100 == 0 {
			t.Logf("decision=%d kind=%s turn=%d life=%v", decisions, decisionKind, host.snapshot.Turn, host.snapshot.Players)
		}
	}
	if !resumed || !host.snapshot.GameOver || host.snapshot.WinnerSeat == nil ||
		stats["land"] == 0 || stats["cast"] < 7 || stats["payManaCost"] == 0 || stats["chooseBoardTargets"] < 7 {
		t.Fatalf("real damage win/resume not completed: resumed=%v gameOver=%v winner=%v stats=%v",
			resumed, host.snapshot.GameOver, host.snapshot.WinnerSeat, stats)
	}
	winner := *host.snapshot.WinnerSeat
	if winner < 0 || winner >= len(players) {
		t.Fatalf("invalid terminal winner seat %d", winner)
	}
	lethalDamage := false
	for _, player := range host.snapshot.Players {
		if player.Seat != winner && player.Life <= 0 {
			lethalDamage = true
		}
	}
	if !lethalDamage {
		t.Fatal("synthetic burn game ended without lethal life loss")
	}
	for _, peer := range append(players, observer) {
		if !peer.snapshot.GameOver || peer.snapshot.WinnerSeat == nil || *peer.snapshot.WinnerSeat != winner {
			t.Fatal("terminal result differs between authenticated viewers")
		}
		peer.until(t, ctx, protocol.TypeRoomSnapshot)
	}
	if matchMode == protocol.MatchBO3 {
		winner = liveForgeContinueBO3(t, ctx, srv, handler, players, observer, roomID, stats)
	}
	if _, exists := handler.forgeGame(roomID); exists {
		t.Fatal("normally completed game retained a live engine session")
	}
	operation, err := handler.hub.lockRoomOperation(roomID)
	if err != nil {
		t.Fatal(err)
	}
	operation.mu.Lock()
	r := operation.room
	winsRequired := 1
	if matchMode == protocol.MatchBO3 {
		winsRequired = 2
	}
	validResult := r.Game != nil && r.Game.Result != nil && r.Game.Result.Reason == protocol.GameResultRules &&
		r.Game.Result.WinnerSeat == winner && r.Game.Result.MatchFinished && r.Score[winner] == winsRequired
	operation.mu.Unlock()
	operation.opMu.Unlock()
	if !validResult {
		t.Fatal("real engine win did not commit the ordinary match lifecycle result")
	}
	if handler.config.RetentionDir != "" {
		liveForgeVerifyReplay(t, ctx, players, observer, matchMode)
	}
	host.command(t, ctx, protocol.TypeGameReturnToRoom, "return", protocol.GameReturnToRoom{})
	host.until(t, ctx, protocol.TypeGameReturnedToRoom)
	for _, peer := range append(players, observer) {
		for snapshots := 0; snapshots < 12; snapshots++ {
			peer.until(t, ctx, protocol.TypeRoomSnapshot)
			if peer.room.Phase == protocol.RoomPhaseWaiting {
				break
			}
		}
		if peer.room.Phase != protocol.RoomPhaseWaiting {
			t.Fatal("completed match did not return every participant to the waiting room")
		}
		for _, seat := range peer.room.Seats {
			if seat.Ready || !seat.DeckSelected {
				t.Fatal("return to room did not preserve decks and reset readiness")
			}
		}
		// Drain to a same-connection barrier, including the last spectator
		// frame: a leaked private prompt must not hide behind the final view.
		peer.command(t, ctx, protocol.TypeSessionPing, "barrier", struct{}{})
		peer.until(t, ctx, protocol.TypeSessionPong)
	}
	slices.Sort(actionLatencies)
	t.Logf("first-game action latency: count=%d p50=%s p95=%s max=%s", len(actionLatencies), actionLatencies[len(actionLatencies)/2], actionLatencies[len(actionLatencies)*95/100], actionLatencies[len(actionLatencies)-1])
	t.Logf("real WS match completed in %s; winner seat=%d; decisions=%v; private snapshots=%d/%d/%d",
		time.Since(started), winner, stats, host.snapshots, guest.snapshots, observer.snapshots)
}

// A complete match has public logs and board state larger than the WebSocket
// library's 32 KiB default. Keep test reads bounded while allowing full state.
func dialLiveForge(t *testing.T, srv *httptest.Server) *wsClient {
	client := dial(t, srv)
	client.conn.SetReadLimit(2 << 20)
	return client
}

type liveForgePeer struct {
	replay    protocol.ForgeReplayGrant
	client    *wsClient
	seat      int
	name      string
	welcome   protocol.SessionWelcome
	room      protocol.RoomSnapshot
	metadata  protocol.GameSnapshot
	snapshot  protocol.RulesGameSnapshot
	prompt    protocol.RulesPrompt
	snapshots int
}

func (peer *liveForgePeer) command(t *testing.T, ctx context.Context, kind, id string, payload any) {
	t.Helper()
	envelope, err := protocol.NewEnvelope(kind, payload)
	if err != nil {
		t.Fatal(err)
	}
	envelope.ID = id
	data, err := envelope.Marshal()
	if err != nil {
		t.Fatal(err)
	}
	if err := peer.client.conn.Write(ctx, websocket.MessageText, data); err != nil {
		t.Fatalf("seat %d write %s: %v", peer.seat, kind, err)
	}
}

func (peer *liveForgePeer) until(t *testing.T, ctx context.Context, kind string) protocol.Envelope {
	t.Helper()
	readCtx, cancel := context.WithTimeout(ctx, 50*time.Second)
	defer cancel()
	for messages := 0; messages < 80; messages++ {
		_, data, err := peer.client.conn.Read(readCtx)
		if err != nil {
			t.Fatalf("seat %d waiting for %s: %v", peer.seat, kind, err)
		}
		envelope, err := protocol.ParseEnvelope(data)
		if err != nil {
			t.Fatal(err)
		}
		peer.accept(t, envelope, kind)
		if envelope.Type == kind {
			return envelope
		}
	}
	t.Fatalf("seat %d never received %s", peer.seat, kind)
	return protocol.Envelope{}
}

func liveForgeActor(t *testing.T, players []*liveForgePeer) *liveForgePeer {
	t.Helper()
	var actor *liveForgePeer
	for _, player := range players {
		if player.prompt.Pending {
			if actor != nil {
				t.Fatal("more than one player received the current private decision")
			}
			actor = player
		}
	}
	if actor == nil {
		t.Fatal("live game has no actionable authenticated decision")
	}
	return actor
}

func liveForgeAnswer(t *testing.T, actor *liveForgePeer, stats map[string]int) protocol.RulesRespond {
	t.Helper()
	prompt := actor.prompt
	answer := protocol.RulesRespond{PromptID: prompt.PromptID, ResponseID: "$submit"}
	switch prompt.Kind {
	case "acknowledge", "diceRolled", "revealCards":
		answer.ResponseID = "$ack"
	case "mulligan":
		answer.ResponseID = "$keep"
	case "chooseAction":
		answer.ResponseID = "$pass"
		for _, option := range prompt.Options {
			if option.Kind == "playLand" {
				stats["land"]++
				answer.ResponseID = option.ResponseID
				return answer
			}
		}
		// This fixture contains only one-mana Lightning Bolts and Mountains.
		// Native Forge offers cast attempts before payment; the synthetic
		// player must avoid repeatedly attempting an unaffordable spell.
		mana := 0
		for _, zone := range actor.snapshot.Zones {
			if zone.Zone != "battlefield" {
				continue
			}
			for _, card := range zone.Cards {
				if card.ControllerSeat == actor.seat && !card.Tapped && card.Identity != nil && card.Identity.Name == "Mountain" {
					mana++
				}
			}
		}
		for _, player := range actor.snapshot.Players {
			if player.Seat == actor.seat {
				for _, counter := range player.ManaPool {
					mana += counter.Value
				}
			}
		}
		for _, option := range prompt.Options {
			if option.Kind == "cast" && mana > 0 {
				answer.ResponseID = option.ResponseID
				stats["cast"]++
				break
			}
		}
	case "payManaCost":
		for _, option := range prompt.Options {
			if !strings.HasPrefix(option.ResponseID, "$") {
				answer.ResponseID = option.ResponseID
				return answer
			}
		}
		for _, id := range []string{"$pay", "$auto-pay", "$cancel"} {
			for _, option := range prompt.Options {
				if option.ResponseID == id {
					answer.ResponseID = id
					return answer
				}
			}
		}
		t.Fatalf("native payment has no available action: %+v", prompt)
	case "chooseBoardTargets":
		if prompt.Minimum == 0 {
			break // Confirm the target already selected by the native input.
		}
		for _, target := range prompt.Targets {
			if target.Kind == "player" && !strings.HasPrefix(target.Label, actor.name+" · ") {
				answer.TargetIDs = []string{target.ResponseID}
				break
			}
		}
		if len(answer.TargetIDs) != 1 {
			t.Fatal("normalized burn prompt has no opponent target")
		}
	case "chooseAttackers", "chooseBlockers":
		// These decks have no creatures.
	case "chooseCards", "mulliganPutBack":
		for _, card := range prompt.Cards {
			if !card.ReadOnly && len(answer.CardIDs) < prompt.CardMinimum {
				answer.CardIDs = append(answer.CardIDs, card.ID)
			}
		}
	case "chooseBoolean", "chooseFromSelection":
		weight := 0
		for _, choice := range prompt.Choices {
			if weight >= prompt.ChoiceMinimum {
				break
			}
			answer.ChoiceIDs = append(answer.ChoiceIDs, choice.ResponseID)
			weight += choice.Weight
		}
	default:
		encoded, _ := json.Marshal(prompt)
		t.Fatalf("synthetic WebSocket game needs explicit policy for %s: %s", prompt.Kind, encoded)
	}
	return answer
}

func (peer *liveForgePeer) accept(t *testing.T, envelope protocol.Envelope, kind string) {
	t.Helper()
	assertNormalizedRulesWireArrays(t, envelope)
	switch envelope.Type {
	case protocol.TypeForgeReplayGrant:
		if peer.seat < 0 {
			t.Fatal("spectator received a private replay capability")
		}
		if err := envelope.DecodePayload(&peer.replay); err != nil {
			t.Fatal(err)
		}
	case protocol.TypeError:
		if kind != protocol.TypeError {
			t.Fatalf("seat %d received server error during %s: %s", peer.seat, kind, envelope.Payload)
		}
	case protocol.TypeRoomSnapshot:
		peer.room = protocol.RoomSnapshot{}
		if err := envelope.DecodePayload(&peer.room); err != nil {
			t.Fatal(err)
		}
		if strings.Contains(string(envelope.Payload), "Lightning Bolt") || strings.Contains(string(envelope.Payload), "Mountain") {
			t.Fatal("public room membership snapshot disclosed the selected deck")
		}
	case protocol.TypeRulesSnapshot:
		peer.snapshot = protocol.RulesGameSnapshot{}
		if err := envelope.DecodePayload(&peer.snapshot); err != nil {
			t.Fatal(err)
		}
		peer.snapshots++
		for _, zone := range peer.snapshot.Zones {
			private := zone.Zone == "library" || zone.Zone == "hand" && zone.OwnerSeat != peer.seat
			for _, card := range zone.Cards {
				if private && (card.Identity != nil || card.Visible) {
					t.Fatalf("viewer %d received a hidden %s card", peer.seat, zone.Zone)
				}
				if zone.Zone == "hand" && zone.OwnerSeat == peer.seat && (card.Identity == nil || !card.Visible) {
					t.Fatalf("player %d received a redacted card in their own hand", peer.seat)
				}
			}
			// Finished-game reconnect intentionally restores the public review
			// board; the separate match replay releases both hands only at completion.
			if !peer.snapshot.GameOver && zone.Zone == "hand" && zone.OwnerSeat == peer.seat && zone.Count > 0 && len(zone.Cards) != zone.Count {
				t.Fatalf("player %d did not receive their own complete hand: game=%s over=%v zone=%+v", peer.seat, peer.snapshot.GameID, peer.snapshot.GameOver, zone)
			}
		}
	case protocol.TypeGameSnapshot:
		peer.metadata = protocol.GameSnapshot{}
		if err := envelope.DecodePayload(&peer.metadata); err != nil {
			t.Fatal(err)
		}
		if peer.seat < 0 && peer.metadata.Sideboard != nil &&
			(len(peer.metadata.Sideboard.Mainboard) != 0 || len(peer.metadata.Sideboard.Sideboard) != 0 ||
				len(peer.metadata.Sideboard.Commanders) != 0) {
			t.Fatal("spectator received a private sideboard partition")
		}
	case protocol.TypeRulesPrompt:
		if peer.seat < 0 {
			t.Fatal("spectator received a private rules prompt")
		}
		peer.prompt = protocol.RulesPrompt{}
		if err := envelope.DecodePayload(&peer.prompt); err != nil {
			t.Fatal(err)
		}
		if peer.prompt.Pending {
			if !peer.prompt.Supported || peer.prompt.PromptID <= 0 {
				t.Fatalf("unsupported synthetic decision: %s", envelope.Payload)
			}
		} else if peer.prompt.PromptID != 0 || peer.prompt.Kind != "" || peer.prompt.Title != "" || peer.prompt.Detail != "" ||
			peer.prompt.ContextText != "" || len(peer.prompt.Options) != 0 || len(peer.prompt.Choices) != 0 ||
			len(peer.prompt.Cards) != 0 || len(peer.prompt.ContextCards) != 0 || len(peer.prompt.Targets) != 0 ||
			len(peer.prompt.OrderItems) != 0 || len(peer.prompt.ContextTargets) != 0 || len(peer.prompt.ScryDestinations) != 0 ||
			len(peer.prompt.CombatSources) != 0 || len(peer.prompt.CombatTargets) != 0 ||
			peer.prompt.DamageSource != nil || len(peer.prompt.DamageTargets) != 0 {
			t.Fatal("non-deciding player received private prompt details")
		}
	}
}
