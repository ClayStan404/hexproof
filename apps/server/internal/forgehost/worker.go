// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forgehost

import (
	"context"
	"encoding/json"
	"net/url"
	"sync"
	"time"

	"github.com/coder/websocket"
)

// WorkerConfig arrives over the parent pipe, never through process arguments
// or logs. Only the parent selects the local runtime; the server cannot supply
// a command, executable path, URL to download, or shell fragment.
type WorkerConfig struct {
	RuntimeID    string `json:"runtimeId"`
	ServerURL    string `json:"serverUrl"`
	RoomID       string `json:"roomId"`
	Token        string `json:"token"`
	GraceSeconds int    `json:"graceSeconds"`
}

type workerJob struct {
	conn    *websocket.Conn
	epoch   uint64
	request Request
}

type WorkerPeer struct {
	Actions <-chan PeerAction
	Reply   func(PeerReply)
}

func Run(ctx context.Context, config WorkerConfig, start StartRuntime, status func(string), peers ...WorkerPeer) error {
	endpoint, err := url.Parse(config.ServerURL)
	if err != nil || endpoint.Host == "" || (endpoint.Scheme != "ws" && endpoint.Scheme != "wss") ||
		(config.RuntimeID != "" && config.RuntimeID != RuntimeID) || endpoint.User != nil || config.RoomID == "" || len(config.Token) != 64 ||
		config.GraceSeconds < 1 || config.GraceSeconds > 600 {
		return ErrUnavailable
	}
	query := endpoint.Query()
	query.Set("engine", "1")
	endpoint.RawQuery = query.Encode()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	var connMu sync.Mutex
	var current *websocket.Conn
	var epoch uint64
	executor := NewExecutor(config.RoomID, start, func(engineID string) {
		connMu.Lock()
		conn, generation := current, epoch
		connMu.Unlock()
		if conn != nil {
			_ = writeFrame(ctx, conn, Frame{Type: "failed", Epoch: generation, EngineID: engineID})
		}
	})
	defer executor.Cancel("")
	var peer WorkerPeer
	if len(peers) > 0 {
		peer = peers[0]
	}
	sendCommit := func(commit *PeerCommit) {
		connMu.Lock()
		conn, generation := current, epoch
		connMu.Unlock()
		if conn != nil && commit != nil {
			if writeFrame(ctx, conn, Frame{Type: "peer_commit", Epoch: generation, PeerCommit: commit}) != nil {
				_ = conn.CloseNow()
			}
		}
	}
	peerDone := make(chan struct{})
	go func() {
		defer close(peerDone)
		for {
			select {
			case <-ctx.Done():
				return
			case action, ok := <-peer.Actions:
				if !ok {
					return
				}
				commit, reply := executor.ExecutePeer(ctx, action)
				if commit != nil {
					sendCommit(commit)
				}
				if reply != nil && peer.Reply != nil {
					peer.Reply(*reply)
				}
			}
		}
	}()
	defer func() { cancel(); executor.Cancel(""); <-peerDone }()
	jobs := make(chan workerJob, 1)
	finished := make(chan struct{})
	go func() {
		defer close(finished)
		for {
			select {
			case <-ctx.Done():
				return
			case job := <-jobs:
				response := executor.Execute(ctx, job.request)
				if err := writeFrame(ctx, job.conn, Frame{Type: "response", Epoch: job.epoch, Response: &response}); err != nil {
					_ = job.conn.CloseNow()
				}
			}
		}
	}()
	defer func() { cancel(); executor.Cancel(""); <-finished }()
	helperID := NewID()
	disconnectedAt := time.Now()
	for ctx.Err() == nil {
		if time.Since(disconnectedAt) > time.Duration(config.GraceSeconds)*time.Second {
			return ErrUnavailable
		}
		connectCtx, stop := context.WithTimeout(ctx, 10*time.Second)
		conn, _, dialErr := websocket.Dial(connectCtx, endpoint.String(), &websocket.DialOptions{CompressionMode: websocket.CompressionDisabled})
		stop()
		if dialErr != nil {
			if status != nil {
				status("reconnecting")
			}
			if !retryDelay(ctx) {
				break
			}
			continue
		}
		conn.SetReadLimit(MaxFrameBytes)
		engineID, alive := executor.State()
		hello, _ := json.Marshal(Hello{Version: Version, RoomID: config.RoomID, Token: config.Token,
			HelperID: helperID, RuntimeID: RuntimeID, EngineID: engineID, Alive: alive})
		helloCtx, helloCancel := context.WithTimeout(ctx, 10*time.Second)
		err = conn.Write(helloCtx, websocket.MessageText, hello)
		var bound Frame
		if err == nil {
			_, data, readErr := conn.Read(helloCtx)
			err = readErr
			if err == nil {
				err = json.Unmarshal(data, &bound)
			}
			if err == nil && (bound.Type != "bound" || bound.Epoch == 0) {
				err = ErrUnavailable
			}
		}
		helloCancel()
		if err != nil {
			_ = conn.CloseNow()
			if !retryDelay(ctx) {
				break
			}
			continue
		}
		connMu.Lock()
		current = conn
		epoch = bound.Epoch
		connMu.Unlock()
		if status != nil {
			status("connected")
		}
		executor.mu.Lock()
		var pending *PeerCommit
		if executor.peerPending != nil && !executor.peerPending.confirmed {
			copy := executor.peerPending.commit
			pending = &copy
		}
		executor.mu.Unlock()
		sendCommit(pending)
		err = readWorker(ctx, conn, bound.Epoch, executor, jobs, peer.Reply)
		executor.PeerDisconnected()
		connMu.Lock()
		current = nil
		connMu.Unlock()
		_ = conn.CloseNow()
		disconnectedAt = time.Now()
		if status != nil {
			status("reconnecting")
		}
		if !retryDelay(ctx) {
			break
		}
	}
	return ctx.Err()
}

func readWorker(ctx context.Context, conn *websocket.Conn, epoch uint64, executor *Executor, jobs chan<- workerJob, reply func(PeerReply)) error {
	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			return err
		}
		if len(data) > MaxRequestBytes {
			return ErrUnavailable
		}
		var frame Frame
		if json.Unmarshal(data, &frame) != nil || frame.Epoch != epoch {
			return ErrUnavailable
		}
		switch frame.Type {
		case "request":
			if frame.Request == nil {
				return ErrUnavailable
			}
			select {
			case jobs <- workerJob{conn, epoch, *frame.Request}:
			default:
				return ErrUnavailable
			}
		case "peer_context":
			executor.SetPeerContext(frame.PeerContext)
		case "peer_reply":
			if executor.ConfirmPeer(frame.PeerReply) && reply != nil {
				reply(*frame.PeerReply)
			}
		case "cancel":
			if len(frame.EngineID) != 64 {
				return ErrUnavailable
			}
			executor.Cancel(frame.EngineID)
		default:
			return ErrUnavailable
		}
	}
}

func retryDelay(ctx context.Context) bool {
	timer := time.NewTimer(time.Second)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}
