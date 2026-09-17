//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/pion/webrtc/v4"
	"hexproof/server/internal/forgehost"
	"hexproof/server/internal/peerlink"
	"hexproof/server/internal/protocol"
)

// Native clients use their unmodified shipped helper. Restrict signaling at
// the isolated test ingress so a VPN/LAN candidate cannot qualify as public ICE.
func nativeWANFrame(data []byte, blocked bool, report *wanReport) ([]byte, bool) {
	var envelope protocol.Envelope
	if json.Unmarshal(data, &envelope) != nil || envelope.Type != protocol.TypeForgePeerSignal {
		return data, true
	}
	var request protocol.ForgePeerSignal
	var signal peerlink.Signal
	if json.Unmarshal(envelope.Payload, &request) != nil || json.Unmarshal([]byte(request.Data), &signal) != nil {
		return data, true // Leave invalid-message rejection to the production hub.
	}
	filtered, keep := publicWANSignal(signal, blocked, report)
	if !keep {
		return nil, false
	}
	signalData, _ := json.Marshal(filtered)
	request.Data = string(signalData)
	envelope.Payload, _ = json.Marshal(request)
	encoded, _ := json.Marshal(envelope)
	return encoded, true
}

func nativeWANProxy(t *testing.T, handler http.Handler, blocked bool) http.Handler {
	t.Helper()
	backend := httptest.NewServer(handler)
	t.Cleanup(backend.Close)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("engine") == "1" {
			handler.ServeHTTP(w, r)
			return
		}
		front, err := websocket.Accept(w, r, &websocket.AcceptOptions{CompressionMode: websocket.CompressionDisabled})
		if err != nil {
			return
		}
		defer front.CloseNow()
		ctx, cancel := context.WithCancel(r.Context())
		defer cancel()
		client := &http.Client{Transport: &http.Transport{Proxy: nil}}
		defer client.CloseIdleConnections()
		back, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(backend.URL, "http")+r.URL.RequestURI(),
			&websocket.DialOptions{HTTPClient: client, CompressionMode: websocket.CompressionDisabled})
		if err != nil {
			return
		}
		defer back.CloseNow()
		front.SetReadLimit(forgehost.MaxFrameBytes)
		back.SetReadLimit(forgehost.MaxFrameBytes)
		pump := func(destination, source *websocket.Conn, filter bool) {
			report := wanReport{}
			defer func() {
				if filter {
					t.Logf("native ICE ingress: public=%d filtered=%d blocked=%t", report.PublicCandidates, report.FilteredCandidates, blocked)
				}
			}()
			for {
				kind, data, err := source.Read(ctx)
				if err != nil {
					return
				}
				if filter {
					var keep bool
					data, keep = nativeWANFrame(data, blocked, &report)
					if !keep {
						continue
					}
				}
				if destination.Write(ctx, kind, data) != nil {
					return
				}
			}
		}
		done := make(chan struct{})
		go func() {
			defer close(done)
			pump(front, back, false)
			cancel()
		}()
		pump(back, front, true)
		cancel()
		<-done
	})
}

func TestNativeWANSignalProxy(t *testing.T) {
	for _, blocked := range []bool{false, true} {
		t.Run(map[bool]string{false: "public", true: "blocked"}[blocked], func(t *testing.T) {
			echo := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				conn, err := websocket.Accept(w, r, nil)
				if err != nil {
					return
				}
				defer conn.CloseNow()
				for {
					kind, data, err := conn.Read(r.Context())
					if err != nil || conn.Write(r.Context(), kind, data) != nil {
						return
					}
				}
			})
			server := httptest.NewServer(nativeWANProxy(t, echo, blocked))
			defer server.Close()
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			conn, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(server.URL, "http")+"/private/ws", nil)
			if err != nil {
				t.Fatal(err)
			}
			defer conn.CloseNow()
			for _, address := range []string{"100.64.12.34", "8.8.8.8"} {
				signal, _ := json.Marshal(peerlink.Signal{Candidate: &webrtc.ICECandidateInit{Candidate: "candidate:1 1 udp 123 " + address + " 4567 typ host"}})
				envelope, _ := protocol.NewEnvelope(protocol.TypeForgePeerSignal, protocol.ForgePeerSignal{RoomID: "room", BindingID: "binding", Data: string(signal)})
				envelope.ID = "operation"
				data, _ := json.Marshal(envelope)
				if err := conn.Write(ctx, websocket.MessageText, data); err != nil {
					t.Fatal(err)
				}
			}
			sentinel := []byte(`{"type":"session.ping","id":"unaltered"}`)
			if err := conn.Write(ctx, websocket.MessageText, sentinel); err != nil {
				t.Fatal(err)
			}
			if !blocked {
				_, data, err := conn.Read(ctx)
				var env protocol.Envelope
				var request protocol.ForgePeerSignal
				if err != nil || json.Unmarshal(data, &env) != nil || json.Unmarshal(env.Payload, &request) != nil ||
					env.ID != "operation" || request.RoomID != "room" || request.BindingID != "binding" || !strings.Contains(request.Data, "8.8.8.8") {
					t.Fatal("public signaling or its binding changed")
				}
			}
			_, received, err := conn.Read(ctx)
			if err != nil || string(received) != string(sentinel) {
				t.Fatal("private/blocked candidate escaped or unrelated traffic changed")
			}
		})
	}
}
