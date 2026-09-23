// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"context"
	"encoding/json"
	"errors"
)

// ReplayBatch is privileged engine data, never a live viewer publication.
type ReplayBatch struct {
	Complete     bool          `json:"complete"`
	LastSequence int64         `json:"lastSequence"`
	Frames       []ReplayFrame `json:"frames"`
}

type ReplayFrame struct {
	Sequence  int64            `json:"sequence"`
	ElapsedMS int64            `json:"elapsedMs"`
	Kind      string           `json:"kind"`
	Actor     int              `json:"actor"`
	Text      string           `json:"text"`
	View      json.RawMessage  `json:"view"`
	Combat    []ReplayRelation `json:"combat"`
}

type ReplayRelation struct {
	Kind         string `json:"kind"`
	SourceID     string `json:"sourceId"`
	TargetID     string `json:"targetId,omitempty"`
	TargetPlayer *int   `json:"targetPlayer,omitempty"`
}

type ReplaySource interface {
	Replay(context.Context, string, int64) (*ReplayBatch, error)
}

func (client *Client) Replay(ctx context.Context, sessionID string, after int64) (*ReplayBatch, error) {
	if !client.supportsReplay {
		return nil, nil
	}
	if err := validateSessionID(sessionID); err != nil {
		return nil, err
	}
	result, err := client.call(ctx, rpcRequest{Command: "getReplay", SessionID: sessionID, After: after}, false, false)
	if err != nil {
		return nil, err
	}
	var batch ReplayBatch
	if len(result) > 4<<20 || json.Unmarshal([]byte(result), &batch) != nil || batch.LastSequence < after || len(batch.Frames) > 2000 {
		return nil, errors.New("invalid private replay batch")
	}
	return &batch, nil
}

func runtimeSupportsReplay(raw string) bool {
	var info struct {
		AdapterRevision int `json:"adapterRevision"`
	}
	return json.Unmarshal([]byte(raw), &info) == nil && info.AdapterRevision >= 17
}
