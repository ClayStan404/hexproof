// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forgehost

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"sync"
	"time"

	"github.com/coder/websocket"
)

var ErrUnavailable = errors.New("player-hosted engine is unavailable")
var ErrPaused = errors.New("player-hosted engine is reconnecting")

// Link owns a room capability and one helper connection at a time. No callback
// or reply delivery may acquire the caller's room operation lock.
type Link struct {
	RoomID string
	Token  string
	Grace  time.Duration
	// Seat is assigned by the hub before publication and is immutable.
	Seat            int
	OnState         func(bool)
	OnPeerCommit    func(PeerCommit)
	peerBusy        bool
	mu              sync.Mutex
	callMu          sync.Mutex
	notifyMu        sync.Mutex
	conn            *websocket.Conn
	epoch           uint64
	cancelledEngine string
	helperID        string
	sequence        uint64
	pending         *Request
	reply           chan Response
	active          *Runtime
	closed          bool
	timer           *time.Timer
	done            chan struct{}
	rateStart       time.Time
	rateFrames      int
	rateBytes       int
	bindStart       time.Time
	bindCount       int
}

func NewLink(roomID string, grace time.Duration) *Link {
	return &Link{RoomID: roomID, Token: NewID(), Grace: grace, done: make(chan struct{})}
}

func NewID() string {
	var b [32]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b[:])
}

func (l *Link) Ready() bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	return !l.closed && l.conn != nil
}

// Serve is called only after validating the capability and handshake limits.
// A connection epoch fences delayed frames from a replaced socket.
func (l *Link) Serve(ctx context.Context, conn *websocket.Conn, hello Hello) error {
	l.mu.Lock()
	if time.Since(l.bindStart) >= time.Second {
		l.bindStart = time.Now()
		l.bindCount = 0
	}
	l.bindCount++
	if l.bindCount > 8 {
		l.mu.Unlock()
		return ErrUnavailable
	}
	if l.closed || (l.helperID != "" && l.helperID != hello.HelperID) {
		l.mu.Unlock()
		return ErrUnavailable
	}
	if l.active != nil && (l.pending == nil || l.pending.Command == "action") &&
		(hello.EngineID != l.active.engineID || !hello.Alive) {
		active := l.active
		l.mu.Unlock()
		active.Invalidate()
		return ErrUnavailable
	}
	old := l.conn
	epoch := l.epoch + 1
	if err := writeFrame(ctx, conn, Frame{Type: "bound", Epoch: epoch}); err != nil {
		l.mu.Unlock()
		return err
	}
	if hello.Alive && hello.EngineID == l.cancelledEngine {
		if err := writeFrame(ctx, conn, Frame{Type: "cancel", Epoch: epoch, EngineID: hello.EngineID}); err != nil {
			l.mu.Unlock()
			return err
		}
	}
	l.conn = conn
	l.helperID = hello.HelperID
	l.epoch = epoch
	if l.timer != nil {
		l.timer.Stop()
		l.timer = nil
	}
	pending := l.pending
	l.mu.Unlock()
	if old != nil {
		_ = old.CloseNow()
	}
	defer l.detach(conn, epoch)
	l.notifyState()
	if pending != nil {
		if err := writeFrame(ctx, conn, Frame{Type: "request", Epoch: epoch, Request: pending}); err != nil {
			return err
		}
	}
	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			return err
		}
		l.mu.Lock()
		if time.Since(l.rateStart) >= time.Second {
			l.rateStart = time.Now()
			l.rateFrames = 0
			l.rateBytes = 0
		}
		l.rateFrames++
		l.rateBytes += len(data)
		overLimit := l.rateFrames > 1024 || l.rateBytes > 64<<20
		l.mu.Unlock()
		if overLimit {
			return ErrUnavailable
		}
		var frame Frame
		if json.Unmarshal(data, &frame) != nil {
			return ErrUnavailable
		}
		l.mu.Lock()
		if l.closed || l.conn != conn || l.epoch != epoch || frame.Epoch != epoch {
			l.mu.Unlock()
			return ErrUnavailable
		}
		switch frame.Type {
		case "response":
			r := frame.Response
			p := l.pending
			if r != nil && r.RoomID == l.RoomID && r.ID <= l.sequence && (p == nil || r.ID < p.ID) {
				l.mu.Unlock()
				continue
			}
			if r == nil || p == nil || r.RoomID != l.RoomID || r.EngineID != p.EngineID || r.ID != p.ID {
				l.mu.Unlock()
				return ErrUnavailable
			}
			select {
			case l.reply <- *r:
			default:
			}
		case "peer_commit":
			commit := frame.PeerCommit
			if commit == nil || commit.EngineID == "" || l.OnPeerCommit == nil {
				l.mu.Unlock()
				return ErrUnavailable
			}
			if !l.peerBusy {
				l.peerBusy = true
				go func() {
					defer func() { l.mu.Lock(); l.peerBusy = false; l.mu.Unlock() }()
					l.OnPeerCommit(*commit)
				}()
			}
		case "failed":
			active := l.active
			l.mu.Unlock()
			if active != nil && active.engineID == frame.EngineID {
				active.Invalidate()
			}
			continue
		default:
			l.mu.Unlock()
			return ErrUnavailable
		}
		l.mu.Unlock()
	}
}

func (l *Link) detach(conn *websocket.Conn, epoch uint64) {
	l.mu.Lock()
	if l.conn != conn || l.epoch != epoch {
		l.mu.Unlock()
		return
	}
	l.conn = nil
	if !l.closed {
		l.timer = time.AfterFunc(l.Grace, func() {
			l.mu.Lock()
			active := l.active
			expired := !l.closed && l.conn == nil && l.epoch == epoch
			if expired && active != nil {
				active.invalidateLocked()
			}
			l.mu.Unlock()
		})
	}
	l.mu.Unlock()
	l.notifyState()
}

func (l *Link) call(ctx context.Context, request Request) (Response, error) {
	l.callMu.Lock()
	defer l.callMu.Unlock()
	l.mu.Lock()
	if l.closed {
		l.mu.Unlock()
		return Response{}, ErrUnavailable
	}
	if l.conn == nil {
		l.mu.Unlock()
		return Response{}, ErrPaused
	}
	l.sequence++
	request.ID = l.sequence
	request.RoomID = l.RoomID
	l.pending = &request
	l.reply = make(chan Response, 1)
	reply, conn, epoch := l.reply, l.conn, l.epoch
	var engineDone <-chan struct{}
	if l.active != nil && l.active.engineID == request.EngineID {
		engineDone = l.active.Done()
	}
	l.mu.Unlock()
	defer func() { l.mu.Lock(); l.pending = nil; l.reply = nil; l.mu.Unlock() }()
	if conn != nil {
		if err := writeFrame(ctx, conn, Frame{Type: "request", Epoch: epoch, Request: &request}); err != nil {
			_ = conn.CloseNow()
		}
	}
	select {
	case r := <-reply:
		if r.Error != "" {
			return r, ErrUnavailable
		}
		return r, nil
	case <-ctx.Done():
		return Response{}, ctx.Err()
	case <-l.done:
		return Response{}, ErrUnavailable
	case <-engineDone:
		return Response{}, ErrUnavailable
	}
}

func (l *Link) Close() {
	l.mu.Lock()
	if l.closed {
		l.mu.Unlock()
		return
	}
	l.closed = true
	if l.timer != nil {
		l.timer.Stop()
	}
	conn, active, epoch := l.conn, l.active, l.epoch
	l.conn = nil
	close(l.done)
	l.mu.Unlock()
	if active != nil {
		active.Invalidate()
	}
	if conn != nil {
		if active != nil {
			// Explicit revocation ends the game; unlike a dropped socket it
			// must not leave the helper waiting through a reconnect grace.
			ctx, cancel := context.WithTimeout(context.Background(), time.Second)
			_ = writeFrame(ctx, conn, Frame{Type: "cancel", Epoch: epoch, EngineID: active.engineID})
			cancel()
		}
		_ = conn.CloseNow()
	}
}

func writeFrame(ctx context.Context, conn *websocket.Conn, frame Frame) error {
	data, err := json.Marshal(frame)
	if err != nil || len(data) > MaxFrameBytes {
		return ErrUnavailable
	}
	writeCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	return conn.Write(writeCtx, websocket.MessageText, data)
}

func (l *Link) notifyState() {
	l.notifyMu.Lock()
	defer l.notifyMu.Unlock()
	if l.OnState != nil {
		l.OnState(l.Ready())
	}
}

// SendPeer uses the same authenticated engine connection and epoch. Payloads
// are private; callers must never put these frames on the public room fanout.
func (l *Link) SendPeer(frame Frame) error {
	l.mu.Lock()
	conn, epoch, closed := l.conn, l.epoch, l.closed
	l.mu.Unlock()
	if conn == nil || closed {
		return ErrPaused
	}
	frame.Epoch = epoch
	return writeFrame(context.Background(), conn, frame)
}
