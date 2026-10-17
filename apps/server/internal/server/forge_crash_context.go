// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"sync"
	"time"

	"hexproof/server/internal/protocol"
)

// This game-owned ring contains fixed operation families and public scalars,
// never response IDs, choices, journal text or player-visible snapshots.
type forgeGameDiagnostics struct {
	mu          sync.Mutex
	context     protocol.RulesCrashContext
	observedAt  time.Time
	sequence    int64
	dropped     int
	failureCode string
}

func (d *forgeGameDiagnostics) observe(snapshot protocol.RulesGameSnapshot, seq int64) {
	if d == nil {
		return
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	step := forgeCrashStep(snapshot.Step)
	turn := min(10000000, max(0, snapshot.Turn))
	if d.context.Turn != turn || d.context.Step != step {
		d.appendLocked(protocol.RulesCrashEvent{Kind: "public_boundary", Turn: turn, Step: step})
	}
	d.context.Turn = turn
	d.context.Step = step
	d.context.ActiveSeat = nil
	if snapshot.ActiveSeat >= 0 && snapshot.ActiveSeat < 16 {
		seat := snapshot.ActiveSeat
		d.context.ActiveSeat = &seat
	}
	d.context.PublicSequence = min(int64(1<<53-1), max(0, seq))
	d.observedAt = time.Now()
}

func forgeCrashStep(step string) string {
	step = normalizedRulesStep(step)
	switch step {
	case "untap", "upkeep", "draw", "main1", "main2", "main_1", "main_2", "begin_combat", "declare_attackers", "declare_blockers", "combat_damage", "end_combat", "end", "cleanup":
		return step
	}
	return "unknown"
}

func (d *forgeGameDiagnostics) action(family string, seat int, automatic bool) {
	if d == nil || seat < 0 || seat >= 16 {
		return
	}
	// The stage is deliberately coarser than the private decision contents.
	stage := "decision"
	if family == "chooseAction" {
		stage = "priority"
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	d.appendLocked(protocol.RulesCrashEvent{Kind: "action_submitted", Stage: stage, Seat: &seat, Automatic: automatic})
}

func (d *forgeGameDiagnostics) appendLocked(event protocol.RulesCrashEvent) {
	d.sequence = min(int64(1<<53-1), d.sequence+1)
	event.Origin, event.Sequence = "hub", d.sequence
	if len(d.context.Events) == 32 {
		copy(d.context.Events, d.context.Events[1:])
		d.context.Events = d.context.Events[:31]
		d.dropped++
	}
	d.context.Events = append(d.context.Events, event)
}

func (d *forgeGameDiagnostics) fail(code string) {
	if d == nil {
		return
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.failureCode == "" {
		d.failureCode = code
	}
}

func (d *forgeGameDiagnostics) snapshot(now time.Time) (protocol.RulesCrashContext, int, string) {
	context := protocol.RulesCrashContext{Attribution: "unknown", Spans: []protocol.RulesCrashSpan{}, Sources: []protocol.RulesCrashSource{}, Events: []protocol.RulesCrashEvent{}}
	if d == nil {
		return context, 0, ""
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	context.Turn, context.Step, context.PublicSequence = d.context.Turn, d.context.Step, d.context.PublicSequence
	if d.context.ActiveSeat != nil {
		seat := *d.context.ActiveSeat
		context.ActiveSeat = &seat
	}
	context.Events = append(context.Events, d.context.Events...)
	for i := range context.Events {
		if context.Events[i].Seat != nil {
			seat := *context.Events[i].Seat
			context.Events[i].Seat = &seat
		}
	}
	if !d.observedAt.IsZero() {
		age := min(int64(365*24*60*60*1000), max(int64(0), now.Sub(d.observedAt).Milliseconds()))
		context.ObservationAgeMs = &age
		context.Attribution = "recent_context"
	}
	return context, d.dropped, d.failureCode
}
