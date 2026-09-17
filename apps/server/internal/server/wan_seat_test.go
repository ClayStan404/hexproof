//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/netip"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/coder/websocket"
	"hexproof/server/internal/buildinfo"
	"hexproof/server/internal/forgehost"
	"hexproof/server/internal/peerlink"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
)

type wanEvent struct {
	envelope *protocol.Envelope
	observer bool
	signal   *peerlink.Signal
	message  []byte
	reply    *forgehost.PeerReply
	state    string
	err      error
}

type wanDecision struct {
	id       string
	request  protocol.RulesRespond
	started  time.Time
	direct   bool
	fallback bool
}

type wanReport struct {
	Case               string         `json:"case"`
	Role               string         `json:"role"`
	Mode               string         `json:"mode"`
	Passed             bool           `json:"passed"`
	GameOver           bool           `json:"gameOver"`
	Winner             *int           `json:"winner"`
	Turn               int            `json:"turn"`
	Decisions          int            `json:"decisions"`
	Direct             int            `json:"direct"`
	Fallbacks          int            `json:"fallbacks"`
	DroppedReplies     int            `json:"droppedReplies"`
	Disconnected       bool           `json:"disconnected"`
	DirectReady        bool           `json:"directReady"`
	PublicCandidates   int            `json:"publicCandidates"`
	FilteredCandidates int            `json:"filteredCandidates"`
	PrivateSnapshots   int            `json:"privateSnapshots"`
	ObserverSnapshots  int            `json:"observerSnapshots"`
	Path               map[string]any `json:"path,omitempty"`
	States             []string       `json:"states"`
	ElapsedMS          int64          `json:"elapsedMs"`
	P50MS              int64          `json:"p50Ms"`
	P95MS              int64          `json:"p95Ms"`
	NativeAttempts     int64          `json:"nativeAttempts"`
	NativeActions      int64          `json:"nativeActions"`
}

type wanRuntime struct {
	forge.Runtime
	attempts *atomic.Int64
	actions  *atomic.Int64
}

func (r *wanRuntime) SubmitAction(ctx context.Context, session string, action json.RawMessage) error {
	r.attempts.Add(1)
	err := r.Runtime.SubmitAction(ctx, session, action)
	if err == nil {
		r.actions.Add(1)
	}
	return err
}

func publicWANAddress(value string) bool {
	ip, err := netip.ParseAddr(value)
	return err == nil && ip.IsGlobalUnicast() && !ip.IsPrivate() &&
		!netip.MustParsePrefix("100.64.0.0/10").Contains(ip.Unmap())
}

// Candidate filtering is qualification isolation, not a different ICE engine.
// The public hub receives exactly the same production signaling messages, but
// no remote LAN/Tailscale addresses that could hide a failed Internet path.
func publicWANSignal(signal peerlink.Signal, block bool, report *wanReport) (peerlink.Signal, bool) {
	allowed := func(candidate string) bool {
		fields := strings.Fields(strings.TrimPrefix(candidate, "a="))
		if len(fields) < 8 || !publicWANAddress(fields[4]) || block {
			report.FilteredCandidates++
			return false
		}
		report.PublicCandidates++
		return true
	}
	if signal.Candidate != nil {
		return signal, allowed(signal.Candidate.Candidate)
	}
	if signal.Description != nil {
		copy := *signal.Description
		var lines []string
		for _, line := range strings.Split(copy.SDP, "\r\n") {
			if !strings.HasPrefix(line, "a=candidate:") || allowed(line) {
				lines = append(lines, line)
			}
		}
		copy.SDP = strings.Join(lines, "\r\n")
		signal.Description = &copy
	}
	return signal, true
}

func wanDial(t *testing.T, ctx context.Context, cfg wanConfig, seat int) *liveForgePeer {
	t.Helper()
	conn, _, err := websocket.Dial(ctx, cfg.socketURL(), &websocket.DialOptions{
		HTTPClient:      &http.Client{Transport: &http.Transport{Proxy: nil}},
		CompressionMode: websocket.CompressionDisabled,
	})
	if err != nil {
		t.Fatal(strings.ReplaceAll(err.Error(), cfg.Token, "[namespace]"))
	}
	conn.SetReadLimit(2 << 20)
	peer := &liveForgePeer{client: &wsClient{t: t, conn: conn}, seat: seat, name: fmt.Sprintf("WAN test seat %d", seat)}
	peer.command(t, ctx, protocol.TypeSessionHello, "hello", protocol.SessionHello{
		DisplayName: peer.name, ClientVersion: buildinfo.Version, Protocol: protocol.ProtocolVersion,
	})
	env := peer.until(t, ctx, protocol.TypeSessionWelcome)
	if env.DecodePayload(&peer.welcome) != nil || !peer.welcome.PlayerHostingAvailable {
		t.Fatal("WAN hub does not allow player hosting")
	}
	return peer
}

func wanRead(ctx context.Context, conn *websocket.Conn, observer bool, events chan<- wanEvent) {
	for {
		_, data, err := conn.Read(ctx)
		var env protocol.Envelope
		if err == nil {
			env, err = protocol.ParseEnvelope(data)
		}
		select {
		case events <- wanEvent{envelope: &env, observer: observer, err: err}:
		case <-ctx.Done():
			return
		}
		if err != nil {
			return
		}
	}
}

func wanWaitRecord(t *testing.T, ctx context.Context, cfg wanConfig, key string) []byte {
	t.Helper()
	for {
		data, err := cfg.coordinate(ctx, key, nil)
		if err != nil {
			t.Fatal(strings.ReplaceAll(err.Error(), cfg.Token, "[namespace]"))
		}
		if len(data) != 0 {
			return data
		}
		select {
		case <-ctx.Done():
			t.Fatal("WAN coordination deadline", key)
		case <-time.After(200 * time.Millisecond):
		}
	}
}

func wanPath(t *testing.T, ctx context.Context, link *peerlink.Connection, iface string) map[string]any {
	t.Helper()
	pair, err := link.QualificationPair()
	if err != nil || pair == nil || !publicWANAddress(pair.Remote.Address) {
		t.Fatal("direct channel did not select a public remote candidate")
	}
	var output []byte
	interfaceField := "dev"
	if runtime.GOOS == "windows" {
		// The address has already passed netip parsing/public-address checks.
		// Find-NetRoute returns both address and route objects; retain the route.
		script := "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(); " +
			"ConvertTo-Json -Compress -InputObject @(Find-NetRoute -RemoteIPAddress '" + pair.Remote.Address +
			"' | Where-Object { $_.DestinationPrefix } | Select-Object InterfaceAlias,InterfaceIndex,DestinationPrefix,NextHop,RouteMetric)"
		output, err = exec.CommandContext(ctx, "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script).Output()
		interfaceField = "InterfaceAlias"
	} else {
		output, err = exec.CommandContext(ctx, "ip", "-j", "route", "get", pair.Remote.Address).Output()
	}
	var routes []map[string]any
	if err != nil || json.Unmarshal(output, &routes) != nil || len(routes) != 1 || routes[0][interfaceField] != iface {
		t.Fatal("selected direct candidate does not use the declared interface")
	}
	return map[string]any{"localAddress": pair.Local.Address, "localPort": pair.Local.Port,
		"localType": pair.Local.Typ.String(), "remoteAddress": pair.Remote.Address,
		"remotePort": pair.Remote.Port, "remoteType": pair.Remote.Typ.String(), "route": routes[0]}
}

func TestWANQualificationSeat(t *testing.T) {
	cfg := loadWANConfig(t)
	if cfg.Role != "host" && cfg.Role != "guest" {
		t.Skip("not a seat process")
	}
	// Also covers the production engine worker's outbound WS dial.
	http.DefaultTransport = &http.Transport{Proxy: nil}
	ctx, cancel := context.WithTimeout(t.Context(), 7*time.Minute)
	defer cancel()
	started := time.Now()
	report := wanReport{Case: cfg.Case, Role: cfg.Role, Mode: cfg.Mode, States: []string{}}
	var latencies []int64
	defer func() {
		report.Passed = !t.Failed()
		report.ElapsedMS = time.Since(started).Milliseconds()
		if len(latencies) > 0 {
			slices.Sort(latencies)
			report.P50MS, report.P95MS = latencies[(len(latencies)-1)/2], latencies[(len(latencies)-1)*95/100]
		}
		data, _ := json.MarshalIndent(report, "", "  ")
		if err := os.WriteFile(cfg.Output, append(data, '\n'), 0600); err != nil {
			t.Error(err)
		}
		t.Logf("WAN %s/%s finished: game=%t direct=%d fallback=%d elapsed=%dms", cfg.Case, cfg.Role,
			report.GameOver, report.Direct, report.Fallbacks, report.ElapsedMS)
	}()
	seat := 0
	if cfg.Role == "guest" {
		seat = 1
	}
	peer := wanDial(t, ctx, cfg, seat)
	defer peer.client.conn.CloseNow()
	events := make(chan wanEvent, 128)
	enqueue := func(event wanEvent) {
		select {
		case events <- event:
		default:
			cancel()
		}
	}
	actions := make(chan forgehost.PeerAction, 1)
	var nativeAttempts, nativeActions atomic.Int64
	var roomID string
	if seat == 0 {
		peer.command(t, ctx, protocol.TypeRoomCreate, "create", protocol.RoomCreate{
			Name: "Private WAN qualification " + cfg.Case, Format: protocol.FormatModern,
			DeckFormat: protocol.DeckFormatCustom, RulesMode: protocol.RulesModeForge,
			MatchMode: protocol.MatchBO1, HostingMode: protocol.HostingModePlayer,
			MaxSeats: 2, AllowSpectators: true, CardLoadMode: protocol.CardLoadBackground,
		})
		var created protocol.RoomCreated
		if peer.until(t, ctx, protocol.TypeRoomCreated).DecodePayload(&created) != nil {
			t.Fatal("missing created room")
		}
		roomID = created.RoomID
		var grant protocol.ForgeHostGrant
		if peer.until(t, ctx, protocol.TypeForgeHostGrant).DecodePayload(&grant) != nil {
			t.Fatal("missing private engine grant")
		}
		engine := forge.JavaOverlayProcessConfig(cfg.Java, filepath.Join(cfg.Runtime, "forge-harness.jar"), filepath.Join(cfg.Runtime, "forge-gui"), cfg.Overlay)
		engine.Args = append([]string{"-Xmx768m", "-XX:+UseSerialGC", "-XX:ActiveProcessorCount=2", "-Djava.awt.headless=true"}, engine.Args...)
		workerCtx, stopWorker := context.WithCancel(ctx)
		workerDone := make(chan error, 1)
		go func() {
			workerDone <- forgehost.Run(workerCtx, forgehost.WorkerConfig{ServerURL: cfg.socketURL(), RoomID: roomID,
				Token: grant.Token, GraceSeconds: grant.GraceSeconds},
				func(ctx context.Context) (forge.Runtime, error) {
					runtime, err := forge.Start(ctx, engine)
					if err != nil {
						return nil, err
					}
					return &wanRuntime{Runtime: runtime, attempts: &nativeAttempts, actions: &nativeActions}, nil
				}, nil,
				forgehost.WorkerPeer{Actions: actions, Reply: func(reply forgehost.PeerReply) { enqueue(wanEvent{reply: &reply}) }})
		}()
		defer func() {
			stopWorker()
			select {
			case <-workerDone:
			case <-time.After(5 * time.Second):
				t.Error("WAN worker did not stop")
			}
		}()
		for {
			var status protocol.ForgeHostStatus
			if peer.until(t, ctx, protocol.TypeForgeHostStatus).DecodePayload(&status) != nil {
				t.Fatal("invalid host status")
			}
			if status.Connected {
				break
			}
		}
		if _, err := cfg.coordinate(ctx, cfg.Case+"-room", map[string]string{"roomId": roomID}); err != nil {
			t.Fatal("cannot publish test room")
		}
	} else {
		var created map[string]string
		if json.Unmarshal(wanWaitRecord(t, ctx, cfg, cfg.Case+"-room"), &created) != nil {
			t.Fatal("invalid private room coordination")
		}
		roomID = created["roomId"]
		peer.command(t, ctx, protocol.TypeRoomJoin, "join", protocol.RoomJoin{RoomID: roomID, AcceptPlayerHost: true})
		peer.until(t, ctx, protocol.TypeRoomJoined)
	}
	peer.command(t, ctx, protocol.TypeDeckSelect, "deck", protocol.DeckSelect{Name: "Synthetic WAN burn",
		Format: protocol.FormatModern, DeckFormat: protocol.DeckFormatCustom,
		Mainboard: []protocol.DeckCard{{Name: "Mountain", Count: 24, SetCode: "M11", CollectorNumber: "242"},
			{Name: "Lightning Bolt", Count: 36, SetCode: "M11", CollectorNumber: "149"}}, Sideboard: []protocol.DeckCard{}})
	peer.until(t, ctx, protocol.TypeDeckSelected)
	if _, err := cfg.coordinate(ctx, cfg.Case+"-"+cfg.Role+"-ready", map[string]bool{"ready": true}); err != nil {
		t.Fatal("cannot publish seat readiness")
	}
	other := "host"
	if seat == 0 {
		other = "guest"
	}
	wanWaitRecord(t, ctx, cfg, cfg.Case+"-"+other+"-ready")
	peer.command(t, ctx, protocol.TypePlayerReady, "ready", protocol.PlayerReady{Ready: true})
	peer.until(t, ctx, protocol.TypeRulesPrompt)
	var observer *liveForgePeer
	if seat == 0 {
		observer = wanDial(t, ctx, cfg, -1)
		defer observer.client.conn.CloseNow()
		observer.command(t, ctx, protocol.TypeRoomJoin, "watch", protocol.RoomJoin{RoomID: roomID, AsSpectator: true, AcceptPlayerHost: true})
		observer.until(t, ctx, protocol.TypeRulesSnapshot)
		go wanRead(ctx, observer.client.conn, true, events)
	}
	go wanRead(ctx, peer.client.conn, false, events)
	if cfg.Mode != "relay" {
		peer.command(t, ctx, protocol.TypeForgePeerRequest, "peer-enable", protocol.ForgePeerRequest{Enabled: true})
	}
	var link *peerlink.Connection
	defer func() {
		if link != nil {
			_ = link.Close()
		}
	}()
	var grant protocol.ForgePeerGrant
	var pending *wanDecision
	var lastSubmitted int64
	var snapshotSeq int64
	var dropped = map[string]bool{}
	var confirmed = map[string]bool{}
	stats := make(map[string]int)
	readyAt := time.Now()
	if cfg.Mode != "relay" {
		readyAt = readyAt.Add(15 * time.Second)
	}
	fallback := func() {
		if pending == nil || pending.fallback {
			return
		}
		pending.fallback = true
		report.Fallbacks++
		peer.command(t, ctx, protocol.TypeRulesRespond, pending.id, pending.request)
	}
	accept := func(env protocol.Envelope, direct bool) {
		if env.Type == protocol.TypeRulesSnapshot {
			if env.SeqValue() < snapshotSeq {
				return
			}
			snapshotSeq = env.SeqValue()
		}
		peer.accept(t, env, "WAN decision")
		if env.Type == protocol.TypeRulesResponded && pending != nil && env.ID == pending.id {
			var response protocol.RulesResponded
			if env.DecodePayload(&response) != nil || response.PromptID != pending.request.PromptID {
				t.Fatal("WAN decision acknowledgement mismatch")
			}
			report.Decisions++
			if direct {
				report.Direct++
			}
			latencies = append(latencies, time.Since(pending.started).Milliseconds())
			pending = nil
		}
	}
	ticker := time.NewTicker(20 * time.Millisecond)
	defer ticker.Stop()
	for !peer.snapshot.GameOver {
		select {
		case <-ctx.Done():
			t.Fatal("WAN game deadline", report.Decisions, report.States)
		case event := <-events:
			if event.err != nil {
				t.Fatal("WAN socket closed", event.err)
			}
			if event.observer {
				observer.accept(t, *event.envelope, "WAN spectator")
				continue
			}
			if event.envelope != nil {
				env := *event.envelope
				switch env.Type {
				case protocol.TypeForgePeerGrant:
					if env.DecodePayload(&grant) != nil {
						t.Fatal("invalid peer grant")
					}
					if link != nil {
						_ = link.Close()
					}
					var err error
					link, err = peerlink.New(ctx, peerlink.Config{BindingID: grant.BindingID, Token: grant.Token, Offerer: grant.Offerer, STUN: grant.STUN},
						peerlink.Callbacks{Signal: func(s peerlink.Signal) { enqueue(wanEvent{signal: &s}) },
							State:   func(s string) { enqueue(wanEvent{state: s}) },
							Message: func(data []byte) { enqueue(wanEvent{message: data}) }})
					if err != nil || link.Start() != nil {
						t.Fatal("cannot start direct transport")
					}
				case protocol.TypeForgePeerSignaled:
					var message protocol.ForgePeerSignal
					var signal peerlink.Signal
					if env.DecodePayload(&message) != nil || json.Unmarshal([]byte(message.Data), &signal) != nil {
						t.Fatal("invalid signal")
					}
					if link != nil && message.BindingID == grant.BindingID {
						if filtered, keep := publicWANSignal(signal, cfg.Mode == "blocked", &report); keep {
							_ = link.ApplySignal(filtered)
						}
					}
				default:
					accept(env, false)
				}
			} else if event.signal != nil {
				if signal, keep := publicWANSignal(*event.signal, cfg.Mode == "blocked", &report); keep {
					data, _ := json.Marshal(signal)
					peer.command(t, ctx, protocol.TypeForgePeerSignal, "", protocol.ForgePeerSignal{RoomID: roomID, BindingID: grant.BindingID, Data: string(data)})
				}
			} else if event.state != "" {
				report.States = append(report.States, event.state)
				if event.state != "direct" && pending != nil && pending.direct {
					fallback()
				}
			} else if event.reply != nil && seat == 0 {
				reply := event.reply
				if reply.Error == "" && !confirmed[reply.OperationID] {
					confirmed[reply.OperationID] = true
					report.Direct++
					if cfg.Mode == "drop-replies" && len(dropped) < 4 {
						dropped[reply.OperationID] = true
						report.DroppedReplies++
					}
				}
				if link != nil && link.Ready() && !dropped[reply.OperationID] {
					data, _ := json.Marshal(reply)
					sendCtx, stop := context.WithTimeout(ctx, 1500*time.Millisecond)
					_ = link.Send(sendCtx, data)
					stop()
					if cfg.Mode == "disconnect" && report.Direct >= 12 && !report.Disconnected {
						report.Disconnected = true
						_ = link.Close()
					}
				}
			} else if len(event.message) > 0 {
				if seat == 0 {
					var action forgehost.PeerAction
					if json.Unmarshal(event.message, &action) != nil || action.BindingID != grant.BindingID {
						t.Fatal("invalid direct action")
					}
					select {
					case actions <- action:
					case <-ctx.Done():
						t.Fatal("host action deadline")
					}
				} else {
					var reply forgehost.PeerReply
					if json.Unmarshal(event.message, &reply) != nil || reply.BindingID != grant.BindingID {
						t.Fatal("invalid direct confirmation")
					}
					if pending != nil && reply.OperationID == pending.id {
						if reply.Error != "" {
							fallback()
						} else {
							if len(reply.Envelopes) != 3 {
								t.Fatal("invalid direct publication")
							}
							if reply.Envelopes[1].HasSeq() && reply.Envelopes[1].SeqValue() > snapshotSeq {
								accept(reply.Envelopes[1], true)
								accept(reply.Envelopes[2], true)
							}
							accept(reply.Envelopes[0], true)
						}
					}
				}
			}
		case <-ticker.C:
		}
		if link != nil && link.Ready() && !report.DirectReady {
			report.Path = wanPath(t, ctx, link, cfg.Interface)
			report.DirectReady = true
			t.Log("public direct candidate pair verified against the declared route")
		}
		if pending != nil && pending.direct && time.Since(pending.started) >= 1500*time.Millisecond {
			fallback()
		}
		if time.Now().Before(readyAt) || pending != nil || !peer.prompt.Pending || peer.prompt.PromptID == lastSubmitted || peer.snapshot.GameOver {
			continue
		}
		if report.Decisions >= 1500 {
			t.Fatal("WAN decision bound exceeded")
		}
		answer := liveForgeAnswer(t, peer, stats)
		lastSubmitted = answer.PromptID
		pending = &wanDecision{id: fmt.Sprintf("wan-%d-%d", seat, report.Decisions), request: answer, started: time.Now()}
		if seat == 1 && link != nil && link.Ready() {
			pending.direct = true
			pending.request.PeerBinding = grant.BindingID
			data, _ := json.Marshal(forgehost.PeerAction{BindingID: grant.BindingID, OperationID: pending.id, Request: pending.request})
			sendCtx, stop := context.WithTimeout(ctx, 1500*time.Millisecond)
			err := link.Send(sendCtx, data)
			stop()
			if err != nil {
				fallback()
			}
		} else {
			peer.command(t, ctx, protocol.TypeRulesRespond, pending.id, pending.request)
		}
	}
	// Read through a same-socket barrier so a private frame queued behind the
	// terminal snapshot cannot escape the spectator/privacy assertions.
	barriers := map[bool]bool{false: true}
	peer.command(t, ctx, protocol.TypeSessionPing, "wan-barrier", struct{}{})
	if observer != nil {
		barriers[true] = true
		observer.command(t, ctx, protocol.TypeSessionPing, "wan-barrier", struct{}{})
	}
	for len(barriers) > 0 {
		select {
		case <-ctx.Done():
			t.Fatal("WAN final publication deadline")
		case event := <-events:
			if event.err != nil {
				t.Fatal("WAN final publication socket closed")
			}
			if event.envelope == nil {
				continue
			}
			if event.observer {
				observer.accept(t, *event.envelope, "WAN final spectator")
			} else {
				accept(*event.envelope, false)
			}
			if event.envelope.Type == protocol.TypeSessionPong && event.envelope.ID == "wan-barrier" {
				delete(barriers, event.observer)
			}
		}
	}
	report.GameOver, report.Winner, report.Turn = peer.snapshot.GameOver, peer.snapshot.WinnerSeat, peer.snapshot.Turn
	report.PrivateSnapshots = peer.snapshots
	if observer != nil {
		report.ObserverSnapshots = observer.snapshots
	}
	lethal := false
	for _, player := range peer.snapshot.Players {
		if report.Winner != nil && player.Seat != *report.Winner && player.Life <= 0 {
			lethal = true
		}
	}
	if !lethal {
		t.Error("WAN match did not end through native lethal damage")
	}
	if cfg.RequireP2P && (!report.DirectReady || report.Direct < 8) {
		t.Error("public P2P confirmation requirement was not met")
	}
	if cfg.Mode == "blocked" && report.DirectReady {
		t.Error("blocked setup unexpectedly established direct transport")
	}
	if cfg.Mode == "drop-replies" && seat == 1 && report.Fallbacks < 4 {
		t.Error("dropped direct confirmations did not exercise relay retry")
	}
	if cfg.Mode == "disconnect" && seat == 0 && !report.Disconnected {
		t.Error("established direct transport was not interrupted")
	}
	if _, err := cfg.coordinate(ctx, cfg.Case+"-"+cfg.Role+"-done", map[string]int{"decisions": report.Decisions}); err != nil {
		t.Error("cannot publish completion")
	}
	var otherReport struct {
		Decisions int `json:"decisions"`
	}
	if json.Unmarshal(wanWaitRecord(t, ctx, cfg, cfg.Case+"-"+other+"-done"), &otherReport) != nil {
		t.Fatal("invalid remote completion record")
	}
	if seat == 0 {
		report.NativeAttempts, report.NativeActions = nativeAttempts.Load(), nativeActions.Load()
		expected := int64(report.Decisions + otherReport.Decisions)
		if report.NativeAttempts != expected || report.NativeActions != expected {
			t.Errorf("native action count mismatch: attempts=%d successful=%d acknowledged=%d", report.NativeAttempts, report.NativeActions, expected)
		}
	}
}
