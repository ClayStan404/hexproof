// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forgehost

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"sync"
	"time"

	"hexproof/server/internal/rulesengine/forge"
)

type StartRuntime func(context.Context) (forge.Runtime, error)

// Executor serializes mutations and retains the latest result across socket
// replacement. The relay allows only one outstanding operation, so older IDs
// can be rejected using a watermark without retaining unbounded game history.
type Executor struct {
	mu           sync.Mutex
	stateMu      sync.Mutex
	start        StartRuntime
	roomID       string
	engineID     string
	runtime      forge.Runtime
	cancel       context.CancelFunc
	handle       forge.SessionHandle
	revision     uint64
	lastID       uint64
	lastHash     [32]byte
	lastResponse Response
	onFailure    func(string)
	peerContext  *PeerContext
	peerExpires  time.Time
	peerPending  *peerPending
}

func NewExecutor(roomID string, start StartRuntime, onFailure func(string)) *Executor {
	return &Executor{roomID: roomID, start: start, onFailure: onFailure}
}

func (e *Executor) State() (string, bool) {
	e.stateMu.Lock()
	defer e.stateMu.Unlock()
	return e.engineID, e.runtime != nil && e.runtime.Healthy()
}

func (e *Executor) Execute(ctx context.Context, req Request) Response {
	e.mu.Lock()
	defer e.mu.Unlock()
	response := Response{RoomID: req.RoomID, EngineID: req.EngineID, ID: req.ID}
	raw, err := json.Marshal(req)
	if err != nil || len(raw) > MaxRequestBytes || req.RoomID != e.roomID ||
		len(req.EngineID) != 64 || req.ID == 0 {
		response.Error = "invalid"
		return response
	}
	hash := sha256.Sum256(raw)
	if req.ID == e.lastID && hash == e.lastHash {
		return e.lastResponse
	}
	if req.ID <= e.lastID {
		response.Error = "expired"
		return response
	}
	// Gaps indicate a lost operation/result, not permission to guess state.
	if req.ID != e.lastID+1 {
		response.Error = "expired"
		return response
	}
	defer func() { e.lastID = req.ID; e.lastHash = hash }()
	if req.Command == "restore" {
		response = e.replay(ctx, req, response)
	} else {
		response = e.execute(ctx, req, response)
	}
	if encoded, err := json.Marshal(response); err != nil || len(encoded) > MaxFrameBytes-512 {
		e.Cancel(req.EngineID)
		response.Publication = nil
		response.Error = "failed"
	}
	e.lastResponse = response
	return response
}

func (e *Executor) execute(parent context.Context, req Request, response Response) Response {
	ctx, cancel := context.WithTimeout(parent, 45*time.Second)
	defer cancel()
	e.stateMu.Lock()
	runtime, engineID := e.runtime, e.engineID
	e.cancel = cancel
	e.stateMu.Unlock()
	defer func() { e.stateMu.Lock(); e.cancel = nil; e.stateMu.Unlock() }()
	switch req.Command {
	case "start":
		e.peerPending = nil
		e.peerContext = nil
		if runtime != nil || req.Start == nil || len(req.Start.Players) != 2 ||
			(req.Start.Variant != "Constructed" && req.Start.Variant != "Commander") ||
			req.Start.Players[0].AI || req.Start.Players[1].AI {
			response.Error = "invalid"
			return response
		}
		e.stateMu.Lock()
		e.engineID = req.EngineID
		e.stateMu.Unlock()
		var err error
		runtime, err = e.start(ctx)
		if err != nil {
			response.Error = "failed"
			return response
		}
		e.stateMu.Lock()
		if ctx.Err() != nil {
			e.stateMu.Unlock()
			_ = runtime.Close()
			response.Error = "failed"
			return response
		}
		e.runtime = runtime
		e.engineID = req.EngineID
		e.stateMu.Unlock()
		e.handle, err = runtime.StartGame(ctx, *req.Start)
		if err != nil {
			e.Cancel(req.EngineID)
			response.Error = "failed"
			return response
		}
		e.revision = 0
		go func() {
			<-runtime.Done()
			e.stateMu.Lock()
			current := e.runtime == runtime
			e.stateMu.Unlock()
			if current && e.onFailure != nil {
				e.onFailure(req.EngineID)
			}
		}()
		publication, err := e.collect(ctx, runtime, nil)
		if err != nil {
			e.Cancel(req.EngineID)
			response.Error = "failed"
			return response
		}
		response.Publication = publication
	case "action":
		if runtime == nil || engineID != req.EngineID || !json.Valid(req.Action) {
			response.Error = "invalid"
			return response
		}
		if publication, handled := e.peerRelay(req); handled {
			response.Publication = publication
			if publication == nil {
				response.Error = "rejected"
			}
			return response
		}
		previous, err := runtime.Prompt(ctx, e.handle.SessionID, 0)
		if err == nil {
			err = runtime.SubmitAction(ctx, e.handle.SessionID, req.Action)
		}
		if err != nil {
			response.Error = "rejected"
			if !runtime.Healthy() {
				response.Error = "failed"
			}
			return response
		}
		publication, err := e.collect(ctx, runtime, previous)
		if err != nil {
			e.Cancel(req.EngineID)
			response.Error = "failed"
			return response
		}
		response.Publication = publication
	case "stop":
		if runtime == nil || engineID != req.EngineID {
			response.Error = "invalid"
			return response
		}
		e.Cancel(req.EngineID)
	default:
		response.Error = "invalid"
	}
	return response
}

func (e *Executor) collect(ctx context.Context, runtime forge.Runtime, previous json.RawMessage) (*Publication, error) {
	ticker := time.NewTicker(10 * time.Millisecond)
	defer ticker.Stop()
	for {
		over, err := runtime.GameOver(ctx, e.handle.SessionID)
		if err != nil {
			return nil, err
		}
		prompt, err := runtime.Prompt(ctx, e.handle.SessionID, 0)
		if err != nil {
			return nil, err
		}
		if over || (len(prompt) > 0 && !bytes.Equal(prompt, previous)) {
			p := &Publication{Handle: e.handle, Prompt: prompt, GameOver: over}
			for viewer := -1; viewer < 2; viewer++ {
				view, err := runtime.Snapshot(ctx, e.handle.SessionID, viewer)
				if err != nil {
					return nil, err
				}
				p.Views = append(p.Views, view)
			}
			// Detect publication changes during collection; never combine a
			// new private prompt with the preceding decision's views.
			latest, err := runtime.Prompt(ctx, e.handle.SessionID, 0)
			if err != nil {
				return nil, err
			}
			overAfter, err := runtime.GameOver(ctx, e.handle.SessionID)
			if err != nil {
				return nil, err
			}
			stable := over == overAfter && bytes.Equal(latest, prompt)
			for _, raw := range p.Views {
				view, err := forge.DecodeSnapshotView(raw)
				if err != nil {
					return nil, err
				}
				stable = stable && view.GameOver == overAfter
			}
			if !stable {
				select {
				case <-ctx.Done():
					return nil, ctx.Err()
				case <-ticker.C:
				}
				continue
			}
			e.revision++
			p.Revision = e.revision
			if err := validatePublication(p); err != nil {
				return nil, err
			}
			return p, nil
		}
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-ticker.C:
		}
	}
}

// Cancel may run while a mutation waits for the JVM. It cancels the in-flight
// operation and reaps only the named engine, never a later replacement.
func (e *Executor) Cancel(engineID string) {
	e.stateMu.Lock()
	if engineID != "" && e.engineID != engineID {
		e.stateMu.Unlock()
		return
	}
	runtime, cancel := e.runtime, e.cancel
	e.runtime = nil
	e.stateMu.Unlock()
	if cancel != nil {
		cancel()
	}
	if runtime != nil {
		runtime.Invalidate()
		_ = runtime.Close()
	}
}
