// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"encoding/json"
	"errors"
	"testing"

	"hexproof/server/internal/rulesengine/forge"
)

type promptWaitRuntime struct {
	*modelTestRuntime
	raw            json.RawMessage
	waited         bool
	waitErr        error
	terminal       bool
	terminalErr    error
	terminalChecks int
}

func (f *promptWaitRuntime) AwaitPrompt(context.Context, string, int64) (json.RawMessage, bool, error) {
	return f.raw, f.waited, f.waitErr
}

func (f *promptWaitRuntime) GameOver(ctx context.Context, _ string) (bool, error) {
	if _, bounded := ctx.Deadline(); !bounded {
		return false, errors.New("terminal check has no deadline")
	}
	f.terminalChecks++
	return f.terminal, f.terminalErr
}

func TestAwaitPromptRequiresProgressOrAuthoritativeCompletion(t *testing.T) {
	unchanged := json.RawMessage(`{"promptId":1,"decidingPlayerId":"player-0","input":{"type":"acknowledge"}}`)
	changed := json.RawMessage(`{"promptId":2,"decidingPlayerId":"player-0","input":{"type":"acknowledge"}}`)
	unavailable := errors.New("engine unavailable")
	for _, tc := range []struct {
		name           string
		raw            json.RawMessage
		terminal       bool
		terminalErr    error
		waitErr        error
		wantErr        error
		terminalChecks int
	}{
		{name: "empty timeout", wantErr: context.DeadlineExceeded, terminalChecks: 1},
		{name: "empty completion", terminal: true, terminalChecks: 1},
		{name: "unchanged timeout", raw: unchanged, wantErr: context.DeadlineExceeded, terminalChecks: 1},
		{name: "unchanged completion", raw: unchanged, terminal: true, terminalChecks: 1},
		{name: "new prompt", raw: changed},
		{name: "terminal unavailable", terminalErr: unavailable, wantErr: unavailable, terminalChecks: 1},
		{name: "wait unavailable", waitErr: unavailable, wantErr: unavailable},
	} {
		t.Run(tc.name, func(t *testing.T) {
			runtime := &promptWaitRuntime{modelTestRuntime: &modelTestRuntime{serial: 1}, raw: tc.raw,
				waited: true, terminal: tc.terminal, terminalErr: tc.terminalErr, waitErr: tc.waitErr}
			game := forgeRoomGame{client: runtime, sessionID: "session",
				seatToPlayer: map[int]int{0: 0, 1: 1}, playerToSeat: map[int]int{0: 0, 1: 1}}
			err := waitForForgePromptChange(game, 1)
			if !errors.Is(err, tc.wantErr) || runtime.terminalChecks != tc.terminalChecks {
				t.Fatalf("wait result=%v terminalChecks=%d, want %v/%d", err, runtime.terminalChecks, tc.wantErr, tc.terminalChecks)
			}
		})
	}
}

func TestAwaitPromptUnavailableUsesPolling(t *testing.T) {
	runtime := &promptWaitRuntime{modelTestRuntime: &modelTestRuntime{serial: 2}}
	game := forgeRoomGame{client: runtime, sessionID: "session",
		seatToPlayer: map[int]int{0: 0, 1: 1}, playerToSeat: map[int]int{0: 0, 1: 1}}
	if err := waitForForgePromptChange(game, 1); err != nil || runtime.terminalChecks != 0 {
		t.Fatalf("fallback polling did not observe the changed prompt: %v", err)
	}
}

var _ forge.Runtime = (*promptWaitRuntime)(nil)
