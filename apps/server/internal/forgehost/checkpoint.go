// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forgehost

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"time"

	"hexproof/server/internal/rulesengine/forge"
)

const (
	MaxCheckpointBytes = 3 << 20
	MaxReplayActions   = 10000
	ReplayTimeout      = 3 * time.Minute
)

var ErrReplayMismatch = errors.New("replayed Forge state does not match the confirmed game")

// Checkpoint is a bounded, volatile operation journal, not a JVM snapshot.
// Decks, seed and choices are private. Transfer it only to an explicitly
// approved successor over an authenticated engine connection; never log it.
type Checkpoint struct {
	RuntimeID     string                 `json:"runtimeId"`
	Start         forge.StartGameRequest `json:"start"`
	InitialDigest string                 `json:"initialDigest"`
	Actions       []ReplayAction         `json:"actions"`
}

type ReplayAction struct {
	Action json.RawMessage `json:"action"`
	Digest string          `json:"digest"`
}

func canonicalJSON(raw []byte) ([]byte, error) {
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	var value any
	if err := decoder.Decode(&value); err != nil {
		return nil, err
	}
	var trailing any
	if decoder.Decode(&trailing) != io.EOF {
		return nil, ErrReplayMismatch
	}
	return json.Marshal(value)
}

func publicationDigest(p *Publication) (string, error) {
	if err := validatePublication(p); err != nil {
		return "", err
	}
	var integrity string
	for _, raw := range p.Views {
		view, err := forge.DecodeSnapshotView(raw)
		if err != nil || len(view.IntegrityHash) != 64 {
			return "", ErrReplayMismatch
		}
		if _, err := hex.DecodeString(view.IntegrityHash); err != nil {
			return "", ErrReplayMismatch
		}
		if integrity != "" && integrity != view.IntegrityHash {
			return "", ErrReplayMismatch
		}
		integrity = view.IntegrityHash
	}
	raw, err := json.Marshal(p)
	if err != nil {
		return "", err
	}
	canonical, err := canonicalJSON(raw)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(canonical)
	return hex.EncodeToString(sum[:]), nil
}

func (c *Checkpoint) validate() error {
	if c == nil || c.RuntimeID != RuntimeID || len(c.Start.Players) != 2 ||
		c.Start.GameID == "" || len(c.InitialDigest) != 64 || len(c.Actions) > MaxReplayActions {
		return ErrReplayMismatch
	}
	if _, err := hex.DecodeString(c.InitialDigest); err != nil {
		return ErrReplayMismatch
	}
	for _, action := range c.Actions {
		if len(action.Digest) != 64 || !json.Valid(action.Action) {
			return ErrReplayMismatch
		}
		if _, err := hex.DecodeString(action.Digest); err != nil {
			return ErrReplayMismatch
		}
	}
	raw, err := json.Marshal(c)
	if err != nil || len(raw) > MaxCheckpointBytes {
		return ErrReplayMismatch
	}
	return nil
}

// replay creates a fresh engine and checks every observed decision and logical
// hidden-state/random digest before returning the last confirmed publication.
// Only this explicit command may rebuild a lost engine. Normal request retries
// keep their existing exact-once transport watermark.
func (e *Executor) replay(ctx context.Context, req Request, response Response) Response {
	if req.Checkpoint.validate() != nil {
		response.Error = "checkpoint_invalid"
		return response
	}
	e.stateMu.Lock()
	busy := e.runtime != nil
	e.stateMu.Unlock()
	if busy {
		response.Error = "checkpoint_invalid"
		return response
	}
	ctx, cancel := context.WithTimeout(ctx, ReplayTimeout)
	defer cancel()
	start := req.Checkpoint.Start
	startRequest := Request{RoomID: req.RoomID, EngineID: req.EngineID, Command: "start", Start: &start}
	result := e.execute(ctx, startRequest, response)
	if result.Error != "" {
		return result
	}
	check := func(result Response, expected string) bool {
		digest, err := publicationDigest(result.Publication)
		return result.Error == "" && err == nil && digest == expected
	}
	if !check(result, req.Checkpoint.InitialDigest) {
		e.Cancel(req.EngineID)
		response.Error = "checkpoint_mismatch"
		return response
	}
	for _, action := range req.Checkpoint.Actions {
		result = e.execute(ctx, Request{RoomID: req.RoomID, EngineID: req.EngineID,
			Command: "action", Action: action.Action}, response)
		if !check(result, action.Digest) {
			e.Cancel(req.EngineID)
			response.Error = "checkpoint_mismatch"
			return response
		}
	}
	return result
}
