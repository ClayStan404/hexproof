// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"fmt"
	"testing"
	"time"

	"hexproof/server/internal/forgediag"
	"hexproof/server/internal/protocol"
)

func TestForgeCrashEnrichmentKeepsFirstBoundaryAndCapturedEvidence(t *testing.T) {
	first := crashTestEvidence("session")
	first.CollectionDone = false
	first.RuntimeID = forgediag.SymbolRuntimeID()
	candidate := forgediag.FailureInfo{ProducerID: first.ProducerID, Boundary: &forgediag.Boundary{Code: "process_exited", RequestFamily: "abortGame"}, CollectionDone: true}
	merged := mergeForgeFailure(first, candidate)
	if merged.Boundary.Code != "native_failure" || merged.Boundary.RequestFamily != "submitAction" || merged.Native == nil || merged.Exit == nil || !merged.CollectionDone || merged.RuntimeID != forgediag.SymbolRuntimeID() {
		t.Fatalf("cleanup erased or rewrote evidence: %+v", merged)
	}
	replacement := crashTestEvidence("session")
	replacement.ProducerID = "replacement"
	replacement.Native.Causes[0].ClassName = "java.lang.NumberFormatException"
	if mergeForgeFailure(first, replacement).Native.Causes[0].ClassName != "java.lang.IllegalStateException" {
		t.Fatal("replacement producer overwrote first incident")
	}
	base := protocol.RulesCrashReport{Versions: protocol.RulesCrashVersions{Runtime: "unknown", Forge: "unknown"}, Context: protocol.RulesCrashContext{Events: []protocol.RulesCrashEvent{}}}
	report := completeForgeCrashReport(base, merged, true)
	if report.Versions.Runtime != forgediag.SymbolRuntimeID() || report.Versions.Forge == "unknown" {
		t.Fatal("verified declared runtime identity not displayed")
	}
}

func TestForgeCrashRecoveryCollectsIndependentlyWithoutReplacingPrimary(t *testing.T) {
	h, _ := newSupervisedForgeHandler(t)
	r, members := newSupervisedRoom(t, h, "crash-recovery-evidence", protocol.RulesModeForge)
	members[0].rulesCrashReports.Store(true)
	game, _ := h.forgeGame(r.ID)
	first := crashTestEvidence(game.sessionID)
	primary := &crashTestRuntime{Runtime: game.client, info: first}
	recovery := &crashTestRuntime{info: forgediag.FailureInfo{ProducerID: "recovery-1", Boundary: &forgediag.Boundary{Code: "protocol_eof", RequestFamily: "restore"}}}
	game.client = primary
	op, _ := h.hub.lockRoomOperation(r.ID)
	h.forgeMu.Lock()
	h.forgeGames[r.ID] = game
	h.forgeMu.Unlock()
	h.terminateForgeGame(r, game, recovery)
	op.opMu.Unlock()
	initial := nextCrashReport(t, members[0], 1)
	if initial.CollectionState != "collecting" || initial.RecoveryFailure == nil {
		t.Fatal("primary completion prematurely closed recovery collection")
	}
	primary.set(forgediag.FailureInfo{ProducerID: first.ProducerID, CollectionDone: true})
	late := crashTestEvidence("replacement-session")
	late.ProducerID = "recovery-1"
	late.Native.ProducerID = "replacement-native"
	late.Native.Causes[0].ClassName = "java.lang.NumberFormatException"
	recovery.set(late)
	final := nextCrashReport(t, members[0], 2)
	if final.ReportID != initial.ReportID || final.CollectionState != "complete" || final.RecoveryFailure == nil || len(final.RecoveryFailure.Causes) != 1 || final.RecoveryFailure.Causes[0].ClassName != "java.lang.NumberFormatException" || final.RecoveryFailure.Code != "reconstruction_failed" {
		t.Fatalf("recovery evidence missing: %+v", final)
	}
	if len(final.Failure.Causes) != 1 || final.Failure.Causes[0].ClassName != "java.lang.IllegalStateException" || final.Failure.RequestFamily != "submitAction" || final.Failure.ExitCode == nil {
		t.Fatal("late recovery/cleanup replaced primary evidence")
	}
}

func TestForgeCrashSourceLimitKeepsDeepestFailure(t *testing.T) {
	info := crashTestEvidence("session")
	info.Native.Spans = nil
	for i := 0; i < 8; i++ {
		name := "Lightning Bolt"
		if i == 7 {
			name = "Counterspell"
		}
		info.Native.Spans = append(info.Native.Spans, forgediag.Span{ID: uint64(i + 1), ParentID: uint64(i), Stage: "effect", API: "Draw", Source: &forgediag.Source{ObjectID: fmt.Sprintf("card-%d", i), Incarnation: "1", ObservationSequence: uint64(i + 1), Zone: "stack", Disclosure: "public_zone", Card: &forgediag.CardReference{Name: name}}})
	}
	report := completeForgeCrashReport(protocol.RulesCrashReport{Context: protocol.RulesCrashContext{Events: []protocol.RulesCrashEvent{}}}, info, true)
	if len(report.Context.Sources) != 4 || report.Context.Sources[0].Identity.Name != "Counterspell" || report.Context.Spans[7].SourceID == "" || report.Completeness.OmittedSources != 4 {
		t.Fatalf("truncation removed deepest source: %+v", report.Context)
	}
}

func TestForgeCrashActualExitDoesNotHideSupervisorProtocolFailure(t *testing.T) {
	code := -1
	info := forgediag.FailureInfo{Boundary: &forgediag.Boundary{Code: "protocol_eof"}, Exit: &forgediag.Exit{Code: &code, Signal: "killed", SupervisorKilled: true}}
	if got := forgeCrashFailure(info, "", protocol.HostingModeServer); got.Kind != "protocol_failure" {
		t.Fatalf("our cleanup kill overwrote protocol failure: %+v", got)
	}
	info.Exit.SupervisorKilled = false
	if got := forgeCrashFailure(info, "", protocol.HostingModeServer); got.Kind != "process_exit" {
		t.Fatal("natural process exit not distinguished")
	}
	info.Boundary.Code = "process_exited"
	if got := forgeCrashFailure(info, "", protocol.HostingModePlayer); got.Kind != "process_exit" {
		t.Fatal("confirmed hosted engine death described as connection loss")
	}
}

func TestForgeCrashCollectorCapacityFinalizesInitialReport(t *testing.T) {
	h, _ := newSupervisedForgeHandler(t)
	for i := 0; i < maxForgeCrashReports; i++ {
		if !h.forgeCrashes.collect(func(done <-chan struct{}) { <-done }) {
			t.Fatal("collector capacity smaller than contract")
		}
	}
	if h.forgeCrashes.collect(func(<-chan struct{}) { t.Error("overflow collector started") }) {
		t.Fatal("collector concurrency unbounded")
	}
	r, members := newSupervisedRoom(t, h, "crash-capacity", protocol.RulesModeForge)
	members[0].rulesCrashReports.Store(true)
	game, _ := h.forgeGame(r.ID)
	game.client = &crashTestRuntime{Runtime: game.client, info: forgediag.FailureInfo{ProducerID: "pending"}}
	op, _ := h.hub.lockRoomOperation(r.ID)
	h.forgeMu.Lock()
	h.forgeGames[r.ID] = game
	h.forgeMu.Unlock()
	h.terminateForgeGame(r, game)
	op.opMu.Unlock()
	report := nextCrashReport(t, members[0], 1)
	if report.CollectionState != "partial" || !containsCrashReason(report.Completeness.Missing, "collection_capacity_reached") {
		t.Fatalf("overflow left an indefinitely collecting report: %+v", report.Completeness)
	}
}

func containsCrashReason(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}

func TestForgeCrashResumeSendsOnlyEightNewestIncidents(t *testing.T) {
	h, _ := newSupervisedForgeHandler(t)
	r, members := newSupervisedRoom(t, h, "crash-resume-limit", protocol.RulesModeForge)
	now := time.Now().UTC().Truncate(time.Second)
	for i := 0; i < 12; i++ {
		at := now.Add(time.Duration(i) * time.Millisecond)
		report := protocol.RulesCrashReport{ReportID: fmt.Sprintf("%032x", i), Revision: 1, OccurredAt: at.Format(time.RFC3339Nano)}
		if !h.forgeCrashes.put(report, r.ID, []string{members[0].ConnectionID}, at) {
			t.Fatal("put")
		}
	}
	sess := &Session{ConnectionID: members[0].ConnectionID, Send: make(chan []byte, 16)}
	sess.rulesCrashReports.Store(true)
	h.sendResumedForgeCrashReports(sess, r)
	if len(sess.Send) != 8 {
		t.Fatalf("resume burst=%d", len(sess.Send))
	}
	for i := 4; i < 12; i++ {
		report := nextCrashReport(t, sess, 1)
		if report.ReportID != fmt.Sprintf("%032x", i) {
			t.Fatal("latest reports sorted by timestamp string instead of occurrence")
		}
	}
}

func TestForgeCrashContextSnapshotIsIndependent(t *testing.T) {
	d := &forgeGameDiagnostics{}
	d.action("chooseAction", 2, false)
	a, _, _ := d.snapshot(time.Now())
	*a.Events[0].Seat = 9
	b, _, _ := d.snapshot(time.Now())
	if *b.Events[0].Seat != 2 {
		t.Fatal("public context snapshot shared mutable event scalars")
	}
	d.observe(protocol.RulesGameSnapshot{ActiveSeat: -1}, 1)
	c, _, _ := d.snapshot(time.Now())
	if c.ActiveSeat != nil {
		t.Fatal("unknown active seat invalidated the crash report")
	}
}

func TestForgeCrashCloseStopsMaintenanceAndReleasesCollectors(t *testing.T) {
	store := newForgeCrashStore("")
	if !store.put(protocol.RulesCrashReport{ReportID: "incident", Revision: 1}, "room", []string{"member"}, time.Now()) {
		t.Fatal("put")
	}
	store.mu.Lock()
	maintenance := store.maintenance
	store.mu.Unlock()
	if !maintenance {
		t.Fatal("first incident did not start periodic expiry maintenance")
	}
	if !store.collect(func(done <-chan struct{}) { <-done; _ = store.forMember("room", "member", time.Now()) }) {
		t.Fatal("collector not admitted")
	}
	closed := make(chan struct{})
	go func() { store.close(); close(closed) }()
	select {
	case <-closed:
	case <-time.After(time.Second):
		t.Fatal("close held a store lock while waiting for its collector")
	}
	if store.collect(func(<-chan struct{}) {}) {
		t.Fatal("closed store admitted new collector")
	}
	store.mu.Lock()
	count := store.collectors
	store.mu.Unlock()
	if count != 0 {
		t.Fatal("collector reservation leaked after close")
	}
}

func TestForgeCrashRevisionCannotChangeRoomOrOccurrence(t *testing.T) {
	store := newForgeCrashStore("")
	defer store.close()
	now := time.Now()
	report := protocol.RulesCrashReport{ReportID: "incident", Revision: 1, OccurredAt: now.UTC().Format(time.RFC3339Nano)}
	if !store.put(report, "original", []string{"member"}, now) {
		t.Fatal("put")
	}
	report.Revision = 2
	if store.put(report, "replacement", nil, now) {
		t.Fatal("revision crossed room ownership")
	}
	report.OccurredAt = now.Add(time.Hour).UTC().Format(time.RFC3339Nano)
	if store.put(report, "original", nil, now) {
		t.Fatal("revision rewrote occurrence time")
	}
}
