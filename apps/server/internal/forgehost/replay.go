// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forgehost

import (
	"context"
	"encoding/json"

	"hexproof/server/internal/rulesengine/forge"
)

func (r *Runtime) Replay(_ context.Context, sessionID string, _ int64) (*forge.ReplayBatch, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.publication == nil || r.publication.Handle.SessionID != sessionID {
		return nil, ErrUnavailable
	}
	if r.publication.Replay == nil {
		return nil, nil
	}
	raw, err := json.Marshal(r.publication.Replay)
	if err != nil {
		return nil, err
	}
	var copy forge.ReplayBatch
	err = json.Unmarshal(raw, &copy)
	return &copy, err
}
