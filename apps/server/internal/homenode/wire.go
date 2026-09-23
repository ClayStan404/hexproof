// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package homenode

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/url"
	"sync"
	"sync/atomic"
	"time"

	"github.com/coder/websocket"
	"hexproof/server/internal/peerlink"
)

type frame struct {
	Type     string           `json:"type"`
	ID       string           `json:"id,omitempty"`
	Token    string           `json:"token,omitempty"`
	Mode     string           `json:"mode,omitempty"`
	Query    string           `json:"query,omitempty"`
	RemoteIP string           `json:"remoteIP,omitempty"`
	Peer     *peerlink.Config `json:"peer,omitempty"`
	Signal   *peerlink.Signal `json:"signal,omitempty"`
	Health   json.RawMessage  `json:"health,omitempty"`
}

type healthReport struct {
	OK           bool            `json:"ok"`
	Capabilities json.RawMessage `json:"capabilities"`
}

// Small game envelopes may arrive in a burst at a decision boundary. Bound
// both message count and bytes without rejecting a normal multi-message fanout.
type messageQueue struct {
	messages chan []byte
	bytes    atomic.Int64
}

func newMessageQueue() *messageQueue { return &messageQueue{messages: make(chan []byte, 64)} }
func (q *messageQueue) push(raw []byte) bool {
	if q.bytes.Add(int64(len(raw))) > 8<<20 {
		q.bytes.Add(-int64(len(raw)))
		return false
	}
	select {
	case q.messages <- raw:
		return true
	default:
		q.bytes.Add(-int64(len(raw)))
		return false
	}
}
func (q *messageQueue) consumed(raw []byte) { q.bytes.Add(-int64(len(raw))) }

func canonicalCapabilities(raw json.RawMessage) ([]byte, bool) {
	var capabilities struct {
		Forge         bool `json:"forge"`
		PlayerHosting bool `json:"playerHosting"`
		DirectPeer    bool `json:"directPeer"`
		HostMigration bool `json:"hostMigration"`
	}
	if len(raw) == 0 || len(raw) > 2048 || !bytes.HasPrefix(bytes.TrimSpace(raw), []byte("{")) || json.Unmarshal(raw, &capabilities) != nil {
		return nil, false
	}
	result, err := json.Marshal(capabilities)
	return result, err == nil
}

var noRedirectClient = &http.Client{Timeout: 15 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}

func dial(ctx context.Context, endpoint string, headers http.Header) (*websocket.Conn, error) {
	limited, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	c, _, err := websocket.Dial(limited, endpoint, &websocket.DialOptions{HTTPClient: noRedirectClient, HTTPHeader: headers, CompressionMode: websocket.CompressionDisabled})
	if err != nil {
		return nil, errUnavailable
	}
	c.SetReadLimit(maxMessageBytes)
	return c, nil
}

func writeFrame(ctx context.Context, c *websocket.Conn, f frame) error {
	raw, err := json.Marshal(f)
	if err != nil || len(raw) > maxControlBytes {
		return errUnavailable
	}
	w, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	return c.Write(w, websocket.MessageText, raw)
}

func readFrame(ctx context.Context, c *websocket.Conn) (frame, error) {
	_, raw, err := c.Read(ctx)
	var f frame
	if err != nil || len(raw) > maxControlBytes || json.Unmarshal(raw, &f) != nil {
		return f, errUnavailable
	}
	return f, nil
}

func heartbeat(ctx context.Context, c *websocket.Conn) {
	ticker := time.NewTicker(15 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			limited, stop := context.WithTimeout(ctx, 8*time.Second)
			err := c.Ping(limited)
			stop()
			if err != nil {
				_ = c.CloseNow()
				return
			}
		}
	}
}

func gameFrameLimit(query url.Values) int {
	if query.Get("engine") == "1" {
		return 16 << 20
	}
	return maxMessageBytes
}

func bridge(ctx context.Context, a, b *websocket.Conn, limit int) {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	var wg sync.WaitGroup
	for _, pair := range [][2]*websocket.Conn{{a, b}, {b, a}} {
		wg.Go(func() {
			defer cancel()
			for {
				kind, raw, err := pair[0].Read(ctx)
				if err != nil || kind != websocket.MessageText || len(raw) > limit || !json.Valid(raw) {
					return
				}
				limited, stop := context.WithTimeout(ctx, 10*time.Second)
				err = pair[1].Write(limited, websocket.MessageText, raw)
				stop()
				if err != nil {
					return
				}
			}
		})
	}
	<-ctx.Done()
	_ = a.CloseNow()
	_ = b.CloseNow()
	wg.Wait()
}

// controlWriter bounds queued signaling independently from game traffic.
type controlWriter struct {
	ctx    context.Context
	cancel context.CancelFunc
	conn   *websocket.Conn
	queue  chan frame
}

func newControlWriter(ctx context.Context, cancel context.CancelFunc, conn *websocket.Conn) *controlWriter {
	w := &controlWriter{ctx: ctx, cancel: cancel, conn: conn, queue: make(chan frame, 64)}
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			case f := <-w.queue:
				if writeFrame(ctx, conn, f) != nil {
					cancel()
					_ = conn.CloseNow()
					return
				}
			}
		}
	}()
	return w
}
func (w *controlWriter) send(f frame) bool {
	select {
	case <-w.ctx.Done():
		return false
	default:
	}
	select {
	case w.queue <- f:
		return true
	default:
		w.cancel()
		_ = w.conn.CloseNow()
		return false
	}
}
