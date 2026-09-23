// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forgehost

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"sync"
	"time"

	"hexproof/server/internal/rulesengine/forge"
)

// Runtime exposes one remote game through the same coordinator interface as a
// local JVM. Reads use the last complete decision publication; mutations make
// exactly one relay request. No private publication is persisted or logged.
type Runtime struct {
	link            *Link
	engineID        string
	mu              sync.Mutex
	publication     *Publication
	checkpoint      *Checkpoint
	checkpointBytes int
	done            chan struct{}
	closeOnce       sync.Once
}

var _ forge.Runtime = (*Runtime)(nil)

func (l *Link) NewRuntime() (*Runtime, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.closed || l.conn == nil || l.active != nil {
		return nil, ErrUnavailable
	}
	r := &Runtime{link: l, engineID: NewID(), done: make(chan struct{})}
	l.active = r
	return r, nil
}

func (r *Runtime) RequestTimeout() time.Duration { return r.link.Grace + 45*time.Second }
func (r *Runtime) Done() <-chan struct{}         { return r.done }
func (r *Runtime) Healthy() bool {
	select {
	case <-r.done:
		return false
	default:
		return true
	}
}

func (r *Runtime) StartGame(ctx context.Context, request forge.StartGameRequest) (forge.SessionHandle, error) {
	response, err := r.mutate(ctx, Request{Command: "start", Start: &request})
	if err != nil {
		return forge.SessionHandle{}, err
	}
	return response.Handle, nil
}

func (r *Runtime) SubmitAction(ctx context.Context, sessionID string, action json.RawMessage) error {
	if _, err := r.current(sessionID); err != nil {
		return err
	}
	_, err := r.mutate(ctx, Request{Command: "action", Action: action})
	return err
}

func (r *Runtime) Concede(ctx context.Context, sessionID string, player int) error {
	if player < 0 || player > 1 {
		return ErrUnavailable
	}
	action, _ := json.Marshal(struct {
		Type      string            `json:"type"`
		Directive map[string]string `json:"directive"`
		Player    int               `json:"player"`
	}{"directive", map[string]string{"type": "concede"}, player})
	return r.SubmitAction(ctx, sessionID, action)
}

func (r *Runtime) mutate(ctx context.Context, request Request) (*Publication, error) {
	if !r.Healthy() {
		return nil, ErrUnavailable
	}
	request.EngineID = r.engineID
	response, err := r.link.call(ctx, request)
	if err != nil {
		if response.Error != "rejected" && !errors.Is(err, ErrPaused) {
			r.Invalidate()
		}
		if request.Command == "start" && request.Start != nil {
			if detail := forge.ParseStartFailure(response.StartFailure, *request.Start); detail != nil {
				return nil, detail
			}
		}
		return nil, err
	}
	p := response.Publication
	if err := validatePublication(p); err != nil {
		r.Invalidate()
		return nil, err
	}
	r.mu.Lock()
	if r.publication != nil && (p.Handle.SessionID != r.publication.Handle.SessionID || p.Revision <= r.publication.Revision) {
		r.mu.Unlock()
		r.Invalidate()
		return nil, ErrUnavailable
	}
	r.publication = p
	r.recordCheckpoint(request, p)
	r.mu.Unlock()
	return p, nil
}

// Checkpoint remains available after engine loss until its room releases this
// runtime, so an approved successor can restore the last confirmed boundary.
func (r *Runtime) Checkpoint() (Checkpoint, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.checkpoint.validate() != nil {
		return Checkpoint{}, ErrReplayMismatch
	}
	raw, err := json.Marshal(r.checkpoint)
	if err != nil {
		return Checkpoint{}, err
	}
	var copy Checkpoint
	err = json.Unmarshal(raw, &copy)
	return copy, err
}

func (r *Runtime) CanMigrate() bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.checkpoint != nil && r.publication != nil && !r.publication.GameOver
}

// LastSnapshotView is the last confirmed position, even after loss. It is only
// for a paused migration screen; it never claims that the old engine is live.
func (r *Runtime) LastSnapshotView(viewer int) (forge.GameView, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if viewer < -1 || viewer > 1 || r.publication == nil {
		return forge.GameView{}, ErrUnavailable
	}
	return forge.DecodeSnapshotView(r.publication.Views[viewer+1])
}

func (r *Runtime) RestoreGame(ctx context.Context, checkpoint Checkpoint) (forge.SessionHandle, error) {
	if checkpoint.validate() != nil {
		return forge.SessionHandle{}, ErrReplayMismatch
	}
	r.mu.Lock()
	started := r.publication != nil
	r.mu.Unlock()
	if started {
		return forge.SessionHandle{}, ErrReplayMismatch
	}
	p, err := r.mutate(ctx, Request{Command: "restore", Checkpoint: &checkpoint})
	if err != nil {
		return forge.SessionHandle{}, err
	}
	return p.Handle, nil
}

// Called under r.mu after an accepted publication. Journal exhaustion or an
// unsupported logical-state fingerprint disables migration without stopping
// ordinary play. No truncated history is ever offered as a checkpoint.
func (r *Runtime) recordCheckpoint(req Request, p *Publication) {
	digest, err := publicationDigest(p)
	if err != nil {
		r.checkpoint = nil
		return
	}
	if req.Command == "start" && req.Start != nil {
		// Native AI evaluation threads do not promise deterministic replay.
		if req.Start.HasAI() {
			r.checkpoint = nil
			return
		}
		value := Checkpoint{RuntimeID: RuntimeID, Start: *req.Start, InitialDigest: digest, Actions: []ReplayAction{}}
		raw, err := json.Marshal(value)
		if err != nil || len(raw) > MaxCheckpointBytes {
			r.checkpoint = nil
			return
		}
		r.checkpoint = &Checkpoint{}
		if json.Unmarshal(raw, r.checkpoint) != nil {
			r.checkpoint = nil
			return
		}
		r.checkpointBytes = len(raw)
	} else if req.Command == "restore" && req.Checkpoint != nil {
		raw, err := json.Marshal(req.Checkpoint)
		if err != nil {
			r.checkpoint = nil
			return
		}
		r.checkpoint = &Checkpoint{}
		if json.Unmarshal(raw, r.checkpoint) != nil {
			r.checkpoint = nil
			return
		}
		r.checkpointBytes = len(raw)
	} else if req.Command == "action" && r.checkpoint != nil {
		action := ReplayAction{Action: bytes.Clone(req.Action), Digest: digest}
		raw, err := json.Marshal(action)
		if err != nil || r.checkpointBytes+len(raw)+1 > MaxCheckpointBytes || len(r.checkpoint.Actions) >= MaxReplayActions {
			r.checkpoint = nil
			return
		}
		r.checkpoint.Actions = append(r.checkpoint.Actions, action)
		r.checkpointBytes += len(raw) + 1
	}
}

func validatePublication(p *Publication) error {
	if p == nil || p.Revision == 0 || len(p.Views) != 3 || len(p.Handle.PlayerIndexes) != 2 ||
		p.Handle.SessionID == "" || len(p.Handle.SessionID) > 256 ||
		p.Handle.PlayerIndexes[0] != 0 || p.Handle.PlayerIndexes[1] != 1 {
		return ErrUnavailable
	}
	var gameID string
	for _, raw := range p.Views {
		v, err := forge.DecodeSnapshotView(raw)
		if err != nil || len(v.Players) != 2 || v.GameOver != p.GameOver {
			return ErrUnavailable
		}
		if gameID != "" && v.GameID != gameID {
			return ErrUnavailable
		}
		gameID = v.GameID
	}
	if !p.GameOver {
		prompt, err := forge.NormalizePrompt(p.Prompt)
		if err != nil || prompt.PlayerIndex < 0 || prompt.PlayerIndex > 1 {
			return ErrUnavailable
		}
	}
	return nil
}

func (r *Runtime) current(sessionID string) (*Publication, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if !r.Healthy() || r.publication == nil || sessionID != r.publication.Handle.SessionID {
		return nil, ErrUnavailable
	}
	return r.publication, nil
}

func (r *Runtime) Prompt(ctx context.Context, sessionID string, player int) (json.RawMessage, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if player < 0 || player > 1 {
		return nil, ErrUnavailable
	}
	p, err := r.current(sessionID)
	if err != nil {
		return nil, err
	}
	// A terminal publication has no decision. A nil RawMessage crosses JSON
	// as `null`, which is nonempty bytes after decoding; preserve the local
	// adapter's empty-prompt contract instead of normalizing it as a decision.
	if p.GameOver {
		return nil, nil
	}
	return p.Prompt, nil
}
func (r *Runtime) Snapshot(ctx context.Context, sessionID string, viewer int) (json.RawMessage, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if viewer < -1 || viewer > 1 {
		return nil, ErrUnavailable
	}
	p, err := r.current(sessionID)
	if err != nil {
		return nil, err
	}
	return p.Views[viewer+1], nil
}
func (r *Runtime) SnapshotView(ctx context.Context, sessionID string, viewer int) (forge.GameView, error) {
	raw, err := r.Snapshot(ctx, sessionID, viewer)
	if err != nil {
		return forge.GameView{}, err
	}
	return forge.DecodeSnapshotView(raw)
}
func (r *Runtime) GameOver(ctx context.Context, sessionID string) (bool, error) {
	if err := ctx.Err(); err != nil {
		return false, err
	}
	p, err := r.current(sessionID)
	if err != nil {
		return false, err
	}
	return p.GameOver, nil
}

func (r *Runtime) stop(ctx context.Context, sessionID string) error {
	if _, err := r.current(sessionID); err != nil {
		return err
	}
	_, err := r.link.call(ctx, Request{EngineID: r.engineID, Command: "stop"})
	r.Invalidate()
	return err
}
func (r *Runtime) EndGame(ctx context.Context, sessionID string) error { return r.stop(ctx, sessionID) }
func (r *Runtime) AbortGame(ctx context.Context, sessionID string) error {
	return r.stop(ctx, sessionID)
}
func (r *Runtime) Close() error { r.Invalidate(); return nil }

// invalidateLocked fences expiry against a simultaneous reconnect while the
// link mutex is held. Closing Done never waits for a room operation or caller.
func (r *Runtime) invalidateLocked() bool {
	changed := false
	r.closeOnce.Do(func() {
		changed = true
		close(r.done)
		r.link.cancelledEngine = r.engineID
		if r.link.active == r {
			r.link.active = nil
		}
	})
	return changed
}

func (r *Runtime) Invalidate() {
	r.link.mu.Lock()
	changed := r.invalidateLocked()
	conn, epoch := r.link.conn, r.link.epoch
	r.link.mu.Unlock()
	if changed && conn != nil {
		// Cancellation is out of band, so it cannot queue behind the
		// request whose completion is currently uncertain.
		go func() {
			_ = writeFrame(context.Background(), conn, Frame{Type: "cancel", Epoch: epoch, EngineID: r.engineID})
		}()
	}
}
