// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package homenode

import (
	"context"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/coder/websocket"
	"hexproof/server/internal/peerlink"
)

// RunNode maintains an outbound registration. Replacing its registration fences
// every connection from the old epoch; sessions reconnect through the game hub.
func RunNode(ctx context.Context, config NodeConfig) error {
	if err := config.Validate(); err != nil {
		return err
	}
	for ctx.Err() == nil {
		runRegistration(ctx, config)
		timer := time.NewTimer(time.Second)
		select {
		case <-ctx.Done():
			timer.Stop()
			return nil
		case <-timer.C:
		}
	}
	return nil
}

func runRegistration(parent context.Context, config NodeConfig) {
	ctx, cancel := context.WithCancel(parent)
	defer cancel()
	headers := http.Header{"Authorization": []string{"Bearer " + config.Token}, "X-Hexproof-Node": []string{config.NodeID}}
	conn, err := dial(ctx, config.GatewayURL, headers)
	if err != nil {
		return
	}
	defer conn.CloseNow()
	conn.SetReadLimit(maxControlBytes)
	writer := newControlWriter(ctx, cancel, conn)
	var wg sync.WaitGroup
	wg.Go(func() { heartbeat(ctx, conn) })
	wg.Go(func() { reportHealth(ctx, config, writer) })
	defer func() { cancel(); _ = conn.CloseNow(); wg.Wait() }()
	permits := make(chan struct{}, config.MaxSessions)
	for {
		open, err := readFrame(ctx, conn)
		if err != nil {
			return
		}
		if open.Type != "open" || len(open.ID) != 64 || len(open.Token) != 64 ||
			(open.Mode != "ws" && open.Mode != "signal") || net.ParseIP(open.RemoteIP) == nil {
			return
		}
		query, err := url.ParseQuery(open.Query)
		if err != nil || !validQuery(query) || (open.Mode == "signal" && open.Peer == nil) {
			return
		}
		select {
		case permits <- struct{}{}:
			wg.Go(func() { defer func() { <-permits }(); serveNodeConnection(ctx, config, open) })
		default:
			// Close this epoch instead of accepting unbounded work. The gateway
			// observes node loss and closes all outstanding public connections.
			return
		}
	}
}

func reportHealth(ctx context.Context, config NodeConfig, writer *controlWriter) {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()
	for {
		probe, stop := context.WithTimeout(ctx, 5*time.Second)
		request, err := http.NewRequestWithContext(probe, http.MethodGet, config.HealthURL, nil)
		if err == nil {
			response, err := noRedirectClient.Do(request)
			if err == nil {
				body, readErr := io.ReadAll(io.LimitReader(response.Body, (32<<10)+1))
				_ = response.Body.Close()
				capabilities, valid := canonicalCapabilities(json.RawMessage(response.Header.Get("X-Hexproof-Capabilities")))
				if readErr == nil && response.StatusCode == http.StatusOK && strings.TrimSpace(string(body)) == "ok" && valid {
					report, _ := json.Marshal(healthReport{OK: true, Capabilities: capabilities})
					writer.send(frame{Type: "health", Health: report})
				}
			}
		}
		stop()
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func serveNodeConnection(parent context.Context, config NodeConfig, open frame) {
	ctx, cancel := context.WithCancel(parent)
	defer cancel()
	endpoint, _ := url.Parse(config.GatewayURL)
	endpoint.Path = "/home/attach"
	headers := http.Header{"Authorization": []string{"Bearer " + open.Token}, "X-Hexproof-Node": []string{config.NodeID}, "X-Hexproof-Session": []string{open.ID}}
	attached, err := dial(ctx, endpoint.String(), headers)
	if err != nil {
		return
	}
	defer attached.CloseNow()
	go heartbeat(ctx, attached)
	if open.Mode == "signal" {
		serveNodeRTC(ctx, cancel, config, open, attached)
		return
	}
	backend, err := dialBackend(ctx, config, open)
	if err != nil {
		return
	}
	defer backend.CloseNow()
	query, _ := url.ParseQuery(open.Query)
	attached.SetReadLimit(int64(gameFrameLimit(query)))
	go heartbeat(ctx, backend)
	bridge(ctx, attached, backend, gameFrameLimit(query))
}

func dialBackend(ctx context.Context, config NodeConfig, open frame) (*websocket.Conn, error) {
	backend, _ := url.Parse(config.BackendURL)
	backend.RawQuery = open.Query
	conn, err := dial(ctx, backend.String(), http.Header{"X-Forwarded-For": []string{open.RemoteIP}})
	if err == nil {
		conn.SetReadLimit(int64(gameFrameLimit(backend.Query())))
	}
	return conn, err
}

func serveNodeRTC(ctx context.Context, cancel context.CancelFunc, config NodeConfig, open frame, signal *websocket.Conn) {
	signal.SetReadLimit(maxControlBytes)
	writer := newControlWriter(ctx, cancel, signal)
	ready := make(chan struct{}, 1)
	messages := newMessageQueue()
	peer, err := peerlink.New(ctx, *open.Peer, peerlink.Callbacks{
		Signal: func(s peerlink.Signal) { writer.send(frame{Type: "signal", Signal: &s}) },
		State: func(state string) {
			if state == "direct" {
				select {
				case ready <- struct{}{}:
				default:
				}
			} else if state == "relay" {
				cancel()
			}
		},
		Message: func(data []byte) {
			if !json.Valid(data) {
				cancel()
				return
			}
			if !messages.push(data) {
				cancel()
			}
		},
	})
	if err != nil {
		return
	}
	defer peer.Close()
	var wg sync.WaitGroup
	wg.Go(func() {
		defer cancel()
		for count := 0; ; count++ {
			f, err := readFrame(ctx, signal)
			if err != nil || count >= 66 || f.Type != "signal" || f.Signal == nil || peer.ApplySignal(*f.Signal) != nil {
				return
			}
		}
	})
	defer func() { cancel(); _ = signal.CloseNow(); wg.Wait() }()
	if peer.Start() != nil {
		return
	}
	select {
	case <-ready:
	case <-ctx.Done():
		return
	}
	backend, err := dialBackend(ctx, config, open)
	if err != nil {
		return
	}
	defer backend.CloseNow()
	if !writer.send(frame{Type: "ready"}) {
		return
	}
	wg.Go(func() { heartbeat(ctx, backend) })
	wg.Go(func() {
		defer cancel()
		for {
			kind, data, err := backend.Read(ctx)
			if err != nil || kind != websocket.MessageText || !json.Valid(data) {
				return
			}
			limited, stop := context.WithTimeout(ctx, 10*time.Second)
			err = peer.Send(limited, data)
			stop()
			if err != nil {
				return
			}
		}
	})
	for {
		select {
		case <-ctx.Done():
			return
		case data := <-messages.messages:
			messages.consumed(data)
			limited, stop := context.WithTimeout(ctx, 10*time.Second)
			err := backend.Write(limited, websocket.MessageText, data)
			stop()
			if err != nil {
				return
			}
		}
	}
}
