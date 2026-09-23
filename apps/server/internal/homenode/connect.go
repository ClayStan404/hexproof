// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package homenode

import (
	"bufio"
	"context"
	"encoding/json"
	"io"
	"os"
	"strings"
	"sync/atomic"
	"time"

	"github.com/coder/websocket"
	"hexproof/server/internal/peerlink"
)

type gameTransport interface {
	read(context.Context) ([]byte, error)
	send(context.Context, []byte) error
	close()
	transport() string
}
type wsTransport struct {
	conn   *websocket.Conn
	cancel context.CancelFunc
}

func (w *wsTransport) read(ctx context.Context) ([]byte, error) {
	kind, raw, err := w.conn.Read(ctx)
	if err != nil || kind != websocket.MessageText || !json.Valid(raw) {
		return nil, errUnavailable
	}
	return raw, nil
}
func (w *wsTransport) send(ctx context.Context, raw []byte) error {
	return w.conn.Write(ctx, websocket.MessageText, raw)
}
func (w *wsTransport) close()            { w.cancel(); _ = w.conn.CloseNow() }
func (w *wsTransport) transport() string { return "relay" }

type rtcTransport struct {
	ctx      context.Context
	cancel   context.CancelFunc
	peer     *peerlink.Connection
	signal   *websocket.Conn
	messages *messageQueue
}

func (r *rtcTransport) read(ctx context.Context) ([]byte, error) {
	select {
	case <-ctx.Done():
		return nil, errUnavailable
	case <-r.ctx.Done():
		return nil, errUnavailable
	case raw := <-r.messages.messages:
		r.messages.consumed(raw)
		return raw, nil
	}
}
func (r *rtcTransport) send(ctx context.Context, raw []byte) error {
	if r.ctx.Err() != nil {
		return errUnavailable
	}
	return r.peer.Send(ctx, raw)
}
func (r *rtcTransport) close()            { r.cancel(); _ = r.signal.CloseNow(); _ = r.peer.Close() }
func (r *rtcTransport) transport() string { return r.peer.Transport() }

// connect chooses exactly one game stream before any game command is sent.
// Subsequent failures close it; ordinary commands are never retried here.
func connect(ctx context.Context, config ConnectConfig) (gameTransport, error) {
	if _, err := homeURL(config.URL); err != nil || (config.ForceTURN && config.ForceRelay) {
		return nil, errUnavailable
	}
	if !config.ForceRelay {
		if rtc, err := connectRTC(ctx, config); err == nil {
			return rtc, nil
		}
		if config.ForceTURN {
			return nil, errUnavailable
		}
	}
	conn, err := dial(ctx, config.URL, nil)
	if err != nil {
		return nil, errUnavailable
	}
	owned, cancel := context.WithCancel(ctx)
	go heartbeat(owned, conn)
	return &wsTransport{conn: conn, cancel: cancel}, nil
}

func connectRTC(parent context.Context, config ConnectConfig) (*rtcTransport, error) {
	ctx, cancel := context.WithCancel(parent)
	result := &rtcTransport{ctx: ctx, cancel: cancel, messages: newMessageQueue()}
	succeeded := false
	defer func() {
		if !succeeded {
			cancel()
			if result.signal != nil {
				_ = result.signal.CloseNow()
			}
			if result.peer != nil {
				_ = result.peer.Close()
			}
		}
	}()
	// The deadline includes gateway registration/attachment and ICE setup. It is
	// canceled after establishment so it never limits an active game lifetime.
	timeout := time.AfterFunc(18*time.Second, cancel)
	defer timeout.Stop()
	endpoint, err := homeURL(config.URL)
	if err != nil {
		return nil, err
	}
	endpoint.Path = strings.TrimSuffix(endpoint.Path, "/ws") + "/signal"
	if config.ForceTURN {
		q := endpoint.Query()
		q.Set("forceTURN", "1")
		endpoint.RawQuery = q.Encode()
	}
	signal, err := dial(ctx, endpoint.String(), nil)
	if err != nil {
		return nil, err
	}
	result.signal = signal
	signal.SetReadLimit(maxControlBytes)
	grant, err := readFrame(ctx, signal)
	if err != nil || grant.Type != "grant" || grant.Peer == nil || !grant.Peer.Offerer || (config.ForceTURN && !grant.Peer.RelayOnly) {
		return nil, errUnavailable
	}
	writer := newControlWriter(ctx, cancel, signal)
	ready := make(chan struct{}, 2)
	peer, err := peerlink.New(ctx, *grant.Peer, peerlink.Callbacks{
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
		Message: func(raw []byte) {
			if !json.Valid(raw) {
				cancel()
				return
			}
			if !result.messages.push(raw) {
				cancel()
			}
		},
	})
	if err != nil {
		return nil, err
	}
	result.peer = peer
	backendReady := make(chan struct{}, 1)
	go func() {
		defer cancel()
		var count int
		var established bool
		for {
			message, err := readFrame(ctx, signal)
			if err != nil {
				return
			}
			switch message.Type {
			case "signal":
				count++
				if count > 66 || message.Signal == nil || peer.ApplySignal(*message.Signal) != nil {
					return
				}
			case "ready":
				if established {
					return
				}
				established = true
				backendReady <- struct{}{}
			default:
				return
			}
		}
	}()
	go heartbeat(ctx, signal)
	if peer.Start() != nil {
		return nil, errUnavailable
	}
	var rtcReady, hubReady bool
	for !rtcReady || !hubReady {
		select {
		case <-ctx.Done():
			return nil, errUnavailable
		case <-ready:
			rtcReady = true
		case <-backendReady:
			hubReady = true
		}
	}
	if ctx.Err() != nil {
		return nil, errUnavailable
	}
	succeeded = true
	return result, nil
}

// RunConnectPipe is the desktop transport helper contract. Closing stdin owns
// the entire transport lifetime; output contains no endpoint or credentials.
func RunConnectPipe(parent context.Context, input io.Reader, output io.Writer) error {
	ctx, cancel := context.WithCancel(parent)
	defer cancel()
	scanner := bufio.NewScanner(input)
	scanner.Buffer(make([]byte, 8192), maxMessageBytes+(64<<10))
	if !scanner.Scan() || len(scanner.Bytes()) > 8192 {
		return errUnavailable
	}
	var config ConnectConfig
	if json.Unmarshal(scanner.Bytes(), &config) != nil {
		return errUnavailable
	}
	if os.Getenv("HEXPROOF_HOME_FORCE_RELAY") == "1" {
		config.ForceRelay = true
	}
	if os.Getenv("HEXPROOF_HOME_FORCE_TURN") == "1" {
		config.ForceTURN = true
	}
	commands := make(chan []byte, 2)
	go func() {
		defer cancel()
		for scanner.Scan() {
			var command struct {
				Message json.RawMessage `json:"message"`
			}
			if json.Unmarshal(scanner.Bytes(), &command) != nil || len(command.Message) == 0 || len(command.Message) > maxMessageBytes || !json.Valid(command.Message) {
				return
			}
			select {
			case commands <- command.Message:
			case <-ctx.Done():
				return
			}
		}
	}()
	events := make(chan []byte, 64)
	outputDone := make(chan struct{})
	defer func() {
		cancel()
		select {
		case <-outputDone:
		case <-time.After(250 * time.Millisecond):
		}
	}()
	var queued atomic.Int64
	emit := func(value any) bool {
		if ctx.Err() != nil {
			return false
		}
		raw, err := json.Marshal(value)
		if err != nil || queued.Add(int64(len(raw))) > 8<<20 {
			cancel()
			return false
		}
		select {
		case events <- raw:
			return true
		default:
			queued.Add(-int64(len(raw)))
			cancel()
			return false
		}
	}
	go func() {
		defer close(outputDone)
		for {
			select {
			case <-ctx.Done():
				// Drain complete messages received before EOF before publishing the
				// close event. Never expose a partially received network message.
				for {
					select {
					case raw := <-events:
						if _, err := output.Write(append(raw, '\n')); err != nil {
							return
						}
					default:
						_, _ = output.Write([]byte("{\"state\":\"closed\"}\n"))
						return
					}
				}
			case raw := <-events:
				_, err := output.Write(append(raw, '\n'))
				queued.Add(-int64(len(raw)))
				if err != nil {
					cancel()
					return
				}
			}
		}
	}()
	transport, err := connect(ctx, config)
	if err != nil {
		return err
	}
	defer transport.close()
	if !emit(map[string]any{"state": "connected", "transport": transport.transport()}) {
		return errUnavailable
	}
	go func() {
		defer cancel()
		for {
			raw, err := transport.read(ctx)
			if err != nil {
				return
			}
			if !emit(map[string]any{"message": json.RawMessage(raw)}) {
				return
			}
		}
	}()
	for {
		select {
		case <-ctx.Done():
			return nil
		case raw := <-commands:
			limited, stop := context.WithTimeout(ctx, 10*time.Second)
			err := transport.send(limited, raw)
			stop()
			if err != nil {
				return errUnavailable
			}
		}
	}
}
