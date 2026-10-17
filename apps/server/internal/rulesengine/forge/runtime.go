// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"context"
	"encoding/json"
)

// Runtime is one isolated game engine, either a supervised local process or
// a player-hosted engine reached through the authenticated relay. Implementations
// must be pointer types: the coordinator uses identity to reject stale cleanup.
// Raw engine values remain private to the engine/coordinator boundary.
type Runtime interface {
	StartGame(context.Context, StartGameRequest) (SessionHandle, error)
	SubmitAction(context.Context, string, json.RawMessage) error
	Concede(context.Context, string, int) error
	Prompt(context.Context, string, int) (json.RawMessage, error)
	Snapshot(context.Context, string, int) (json.RawMessage, error)
	SnapshotView(context.Context, string, int) (GameView, error)
	GameOver(context.Context, string) (bool, error)
	EndGame(context.Context, string) error
	AbortGame(context.Context, string) error
	Healthy() bool
	Done() <-chan struct{}
	Invalidate()
	Close() error
}

var _ Runtime = (*Client)(nil)
