// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"hexproof/server/internal/forgediag"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
)

type crashTestRuntime struct {
	forge.Runtime
	mu   sync.Mutex
	info forgediag.FailureInfo
}

func (r *crashTestRuntime) FailureInfo() forgediag.FailureInfo {
	r.mu.Lock()
	defer r.mu.Unlock()
	return forgediag.SanitizeFailure(r.info)
}
func (r *crashTestRuntime) set(info forgediag.FailureInfo) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.info = info
}

func crashTestEvidence(session string) forgediag.FailureInfo {
	code := 23
	return forgediag.FailureInfo{ProducerID: "supervisor-1", AdapterRevision: 31, CollectionDone: true,
		Boundary: &forgediag.Boundary{Code: "native_failure", RequestFamily: "submitAction", Dispatched: true},
		Exit:     &forgediag.Exit{Code: &code}, Native: &forgediag.Capsule{SchemaVersion: 1, ProducerID: "jvm-1", SessionID: session, Sequence: 8,
			Kind: "engine_exception", Boundary: "effect", Attribution: "execution_site", SymbolIndexID: forgediag.SymbolIndexID(),
			Causes: []forgediag.Cause{{ClassName: "java.lang.IllegalStateException", Frames: []forgediag.Frame{{ClassName: "org.hexproof.forge.NativeSession", MethodName: "fail", Line: 551}}}},
			Spans: []forgediag.Span{{ID: 2, ParentID: 1, Stage: "effect", API: "Draw", Source: &forgediag.Source{ObjectID: "card-1", Incarnation: "1", ObservationSequence: 7, Zone: "battlefield", Disclosure: "public_zone", Card: &forgediag.CardReference{Name: "Rhystic Study", SetCode: "PRIVATE-PRINTING", CardNumber: "PRIVATE-PRINTING"}}},
				{ID: 1, Stage: "decision", Source: &forgediag.Source{ObjectID: "card-2", Incarnation: "1", ObservationSequence: 6, Zone: "hand", Disclosure: "public_zone", Card: &forgediag.CardReference{Name: "PRIVATE-HAND"}}}},
			Events: []forgediag.Event{{Sequence: 1, Kind: "effect_enter", SpanID: 2, Stage: "effect", API: "Draw"}},
		}}
}

func nextCrashReport(t *testing.T, member *Session, revision int) protocol.RulesCrashReport {
	t.Helper()
	timer := time.NewTimer(2 * time.Second)
	defer timer.Stop()
	for {
		select {
		case data := <-member.Send:
			var envelope protocol.Envelope
			if json.Unmarshal(data, &envelope) != nil || envelope.Type != protocol.TypeError {
				continue
			}
			var payload protocol.ErrorPayload
			if envelope.DecodePayload(&payload) != nil || payload.RulesCrashReport == nil {
				continue
			}
			if payload.RulesCrashReport.Revision == revision {
				return *payload.RulesCrashReport
			}
		case <-timer.C:
			t.Fatalf("no crash report revision %d", revision)
			return protocol.RulesCrashReport{}
		}
	}
}

func TestForgeCrashPublicEvidenceAndResumeEligibility(t *testing.T) {
	h, _ := newSupervisedForgeHandler(t)
	r, members := newSupervisedRoom(t, h, "crash-report", protocol.RulesModeForge)
	members[0].rulesCrashReports.Store(true)
	game, _ := h.forgeGame(r.ID)
	base := game.client
	game.client = &crashTestRuntime{Runtime: base, info: crashTestEvidence(game.sessionID)}
	game.diagnostics.observe(protocol.RulesGameSnapshot{Turn: 7, Step: "main1", ActiveSeat: 0}, 42)
	game.diagnostics.action("chooseAction", 0, true)
	op, _ := h.hub.lockRoomOperation(r.ID)
	h.forgeMu.Lock()
	h.forgeGames[r.ID] = game
	h.forgeMu.Unlock()
	h.terminateForgeGame(r, game)
	op.opMu.Unlock()
	report := nextCrashReport(t, members[0], 1)
	if report.Failure.Kind != "engine_exception" || report.Context.Attribution != "execution_site" || report.Context.PublicSequence != 42 || report.CollectionState != "complete" {
		t.Fatalf("wrong report: %+v", report)
	}
	if len(report.Context.Sources) != 1 || report.Context.Sources[0].Identity.Name != "Rhystic Study" || len(report.Failure.Causes[0].Frames) == 0 {
		t.Fatalf("public source/verified frame missing: %+v", report)
	}
	raw, _ := json.Marshal(report)
	if strings.Contains(string(raw), "PRIVATE-") {
		t.Fatalf("private data in report: %s", raw)
	}
	assertForgeTermination(t, members[1]) // No capability: the original generic error.
	assertSupervisedPhase(t, h, r, protocol.RoomPhaseWaiting)
	if len(h.forgeCrashes.forMember(r.ID, "replacement-seat-0", time.Now())) != 0 {
		t.Fatal("new occupant inherited report")
	}
	resumed := &Session{ConnectionID: "resumed-crash-member", Send: make(chan []byte, 8)}
	resumed.rulesCrashReports.Store(true)
	h.forgeCrashes.rebind(r.ID, members[0].ConnectionID, resumed.ConnectionID)
	h.sendResumedForgeCrashReports(resumed, r)
	if got := nextCrashReport(t, resumed, 1); got.ReportID != report.ReportID {
		t.Fatal("resume created a different incident")
	}
	if len(h.forgeCrashes.forMember(r.ID, members[0].ConnectionID, time.Now())) != 0 {
		t.Fatal("old connection retained eligibility after resume")
	}
}

func TestForgeCrashLateEvidenceUpdatesSameIncident(t *testing.T) {
	h, _ := newSupervisedForgeHandler(t)
	r, members := newSupervisedRoom(t, h, "late-crash-report", protocol.RulesModeForge)
	members[0].rulesCrashReports.Store(true)
	game, _ := h.forgeGame(r.ID)
	runtime := &crashTestRuntime{Runtime: game.client, info: forgediag.FailureInfo{ProducerID: "supervisor-1", Boundary: &forgediag.Boundary{Code: "protocol_eof", RequestFamily: "submitAction", Dispatched: true}}}
	game.client = runtime
	op, _ := h.hub.lockRoomOperation(r.ID)
	h.forgeMu.Lock()
	h.forgeGames[r.ID] = game
	h.forgeMu.Unlock()
	h.terminateForgeGame(r, game)
	op.opMu.Unlock()
	initial := nextCrashReport(t, members[0], 1)
	if initial.CollectionState != "collecting" || initial.Completeness.NativeEvidence {
		t.Fatal("initial report invented evidence")
	}
	runtime.set(crashTestEvidence(game.sessionID))
	final := nextCrashReport(t, members[0], 2)
	if final.ReportID != initial.ReportID || final.Failure.Kind != "engine_exception" || final.Failure.Code != "protocol_eof" || final.CollectionState != "complete" {
		t.Fatalf("late evidence lost first boundary or incident: %+v", final)
	}
	if got := h.forgeCrashes.forMember(r.ID, members[0].ConnectionID, time.Now()); len(got) != 1 || got[0].Revision != 2 {
		t.Fatal("history did not replace the incident")
	}
}

func TestForgeCrashStoreExpiryRevisionAndBounds(t *testing.T) {
	store := newForgeCrashStore("")
	defer store.close()
	now := time.Now().UTC()
	report := protocol.RulesCrashReport{ReportID: strings.Repeat("a", 32), Revision: 1}
	if !store.put(report, "room", []string{"old"}, now) {
		t.Fatal("put")
	}
	store.rebind("room", "old", "new")
	report.Revision = 2
	if !store.put(report, "room", []string{"intruder"}, now.Add(time.Hour)) {
		t.Fatal("update")
	}
	if len(store.forMember("room", "intruder", now)) != 0 || len(store.forMember("room", "new", now)) != 1 {
		t.Fatal("revision replaced eligibility")
	}
	if store.put(report, "room", nil, now) {
		t.Fatal("duplicate revision accepted")
	}
	if len(store.forMember("room", "new", now.Add(forgeCrashTTL))) != 0 {
		t.Fatal("revision renewed expiry")
	}
	if store.put(report, "room", nil, now.Add(forgeCrashTTL)) {
		t.Fatal("final revision resurrected expired incident")
	}
	for i := 0; i < maxForgeCrashReports+3; i++ {
		value := report
		value.ReportID = fmt.Sprintf("%032x", i)
		value.Revision = 1
		store.put(value, "room", []string{"new"}, now.Add(time.Duration(i)*time.Second))
	}
	if got := store.forMember("room", "new", now.Add(time.Hour)); len(got) != maxForgeCrashReports {
		t.Fatalf("cap: %d", len(got))
	}
}

func TestForgeCrashFingerprintAndPublicPhase(t *testing.T) {
	base := protocol.RulesCrashReport{Failure: protocol.RulesCrashFailure{Code: "native_failure"}, Environment: protocol.RulesCrashEnvironment{HostingMode: "server"}, Context: protocol.RulesCrashContext{Attribution: "unknown", Events: []protocol.RulesCrashEvent{}}, Versions: protocol.RulesCrashVersions{Runtime: "unknown"}}
	info := crashTestEvidence("session")
	a := completeForgeCrashReport(base, info, true)
	info.Native.Causes[0].Frames[0].Line++
	b := completeForgeCrashReport(base, info, true)
	if a.Fingerprint != b.Fingerprint {
		t.Fatal("line number destabilized fingerprint")
	}
	d := &forgeGameDiagnostics{}
	d.observe(protocol.RulesGameSnapshot{Turn: 1, Step: "PRIVATE arbitrary engine text", ActiveSeat: 0}, 1)
	context, _, _ := d.snapshot(time.Now())
	if context.Step != "unknown" || context.Events[0].Step != "unknown" {
		t.Fatal("unverified phase entered public report")
	}
}
