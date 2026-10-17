// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"strconv"
	"strings"
	"time"

	"hexproof/server/internal/buildinfo"
	"hexproof/server/internal/forgediag"
	"hexproof/server/internal/forgehost"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
)

func forgeFailureInformation(runtime forge.Runtime) forgediag.FailureInfo {
	if source, ok := runtime.(forge.FailureSource); ok {
		info := forgediag.SanitizeFailure(source.FailureInfo())
		if remote, ok := runtime.(*forgehost.Runtime); ok {
			if admitted := remote.DiagnosticRuntimeID(); admitted == forgehost.RuntimeID {
				info.RuntimeID = admitted
			}
		}
		return info
	}
	return forgediag.FailureInfo{CollectionDone: true}
}

func forgeCrashFailure(info forgediag.FailureInfo, code, hosting string) protocol.RulesCrashFailure {
	failure := protocol.RulesCrashFailure{Kind: "process_exit", Code: "process_exited", Stage: "process", Causes: []protocol.RulesCrashCause{}}
	if hosting == protocol.HostingModePlayer {
		failure.Kind, failure.Code, failure.Stage = "host_connection_lost", "host_connection_lost", "hosting"
	}
	if info.Boundary != nil {
		failure.Code, failure.RequestFamily = info.Boundary.Code, info.Boundary.RequestFamily
	}
	if code != "" {
		failure.Code = code
	}
	switch failure.Code {
	case "process_exited":
		failure.Kind, failure.Stage = "process_exit", "process"
	case "native_failure":
		failure.Kind, failure.Stage = "engine_exception", "rpc"
	case "execution_timeout":
		failure.Kind, failure.Stage = "execution_timeout", "request"
	case "protocol_invalid", "protocol_eof", "response_too_large", "pipe_write_failed", "publication_invalid", "reconstruction_failed":
		failure.Kind, failure.Stage = "protocol_failure", "publication"
	}
	if info.Native != nil && info.Native.Kind != "context" {
		failure.Kind, failure.Stage = info.Native.Kind, info.Native.Boundary
		for _, cause := range info.Native.Causes {
			value := protocol.RulesCrashCause{ClassName: cause.ClassName, Frames: []protocol.RulesCrashFrame{}}
			for _, frame := range cause.Frames {
				value.Frames = append(value.Frames, protocol.RulesCrashFrame{ClassName: frame.ClassName, MethodName: frame.MethodName, Line: frame.Line})
			}
			failure.Causes = append(failure.Causes, value)
		}
	}
	if info.Exit != nil {
		failure.ExitCode, failure.ExitSignal = info.Exit.Code, info.Exit.Signal
		if (failure.Code == "protocol_eof" || failure.Code == "host_connection_lost") && !info.Exit.SupervisorKilled && (info.Native == nil || info.Native.Kind == "context") {
			failure.Kind, failure.Stage = "process_exit", "process"
		}
	}
	return failure
}

func completeForgeCrashReport(base protocol.RulesCrashReport, info forgediag.FailureInfo, final bool) protocol.RulesCrashReport {
	// Each revision owns its arrays, including the frozen hub event tail.
	raw, _ := json.Marshal(base)
	var report protocol.RulesCrashReport
	_ = json.Unmarshal(raw, &report)
	report.Failure = forgeCrashFailure(info, base.Failure.Code, base.Environment.HostingMode)
	report.Versions.Adapter = info.AdapterRevision
	if info.RuntimeID == forgehost.RuntimeID || info.RuntimeID == forgehost.BaseRuntimeID || info.RuntimeID != "" && info.RuntimeID == forgediag.SymbolRuntimeID() {
		report.Versions.Runtime = info.RuntimeID
		report.Versions.Forge = strings.SplitN(info.RuntimeID, "-adapter", 2)[0]
	}
	report.Completeness.NativeEvidence = info.Native != nil
	report.Completeness.ExitEvidence = info.Exit != nil
	report.Completeness.Missing = []string{}
	if info.Native == nil {
		report.Completeness.Missing = append(report.Completeness.Missing, "native_evidence_unavailable")
	}
	if info.Exit == nil {
		report.Completeness.Missing = append(report.Completeness.Missing, "exit_evidence_unavailable")
	}
	if final && !info.CollectionDone {
		report.Completeness.Missing = append(report.Completeness.Missing, "collection_incomplete")
	}
	if native := info.Native; native != nil {
		report.Context.Attribution = native.Attribution
		if native.Kind == "context" {
			report.Context.Attribution = "recent_context"
		}
		report.Completeness.OmittedCauses = native.OmittedCauses
		report.Completeness.OmittedFrames = native.OmittedFrames
		report.Completeness.OmittedSpans = native.OmittedSpans
		report.Completeness.DroppedEvents += native.DroppedEvents
		knownSources := make(map[string]string)
		omittedSources := make(map[string]bool)
		// Reserve the deepest captured execution source before its ancestors.
		// Truncating a large nested effect must not hide the failing operation.
		for index := len(native.Spans) - 1; index >= 0; index-- {
			span := native.Spans[index]
			if source := span.Source; source != nil && source.Card != nil && forgediag.KnownCardName(source.Card.Name) {
				key := source.ObjectID + "\x00" + source.Incarnation
				id := knownSources[key]
				if id == "" && len(report.Context.Sources) < 4 {
					id = "source-" + strconv.Itoa(len(report.Context.Sources)+1)
					knownSources[key] = id
					// Only catalog-verified canonical names are displayed; printing
					// coordinates are unnecessary and are not trusted for export.
					report.Context.Sources = append(report.Context.Sources, protocol.RulesCrashSource{ID: id, Zone: source.Zone,
						Identity: protocol.RulesCardIdentity{Name: source.Card.Name, Token: source.Card.IsToken}})
				} else if id == "" && !omittedSources[key] {
					report.Completeness.OmittedSources++
					omittedSources[key] = true
				}
			}
		}
		for _, span := range native.Spans {
			value := protocol.RulesCrashSpan{ID: int64(span.ID), ParentID: int64(span.ParentID), Stage: span.Stage, API: span.API}
			if source := span.Source; source != nil {
				value.SourceID = knownSources[source.ObjectID+"\x00"+source.Incarnation]
			}
			report.Context.Spans = append(report.Context.Spans, value)
		}
		// Keep the two producer timelines distinct; their sequences and clocks
		// cannot be compared. Reserve hub actions alongside native resolution.
		nativeLimit := 32 - min(8, len(report.Context.Events))
		events := native.Events
		if len(events) > nativeLimit {
			report.Completeness.DroppedEvents += len(events) - nativeLimit
			events = events[len(events)-nativeLimit:]
		}
		hubEvents := report.Context.Events
		if len(hubEvents) > 8 {
			report.Completeness.DroppedEvents += len(hubEvents) - 8
			hubEvents = hubEvents[len(hubEvents)-8:]
		}
		report.Context.Events = make([]protocol.RulesCrashEvent, 0, 32)
		for _, event := range events {
			report.Context.Events = append(report.Context.Events, protocol.RulesCrashEvent{Origin: "native", Sequence: int64(event.Sequence), Kind: event.Kind, Stage: event.Stage, API: event.API, SpanID: int64(event.SpanID)})
		}
		report.Context.Events = append(report.Context.Events, hubEvents...)
	}
	if final {
		report.CollectionState = "complete"
		if len(report.Completeness.Missing) > 0 {
			report.CollectionState = "partial"
		}
	} else {
		report.CollectionState = "collecting"
	}
	report.Fingerprint = forgeCrashFingerprint(report)
	return report
}

// Enrichment is monotonic. Cleanup may temporarily stop exposing information,
// but cannot erase an already observed boundary, terminal cause or exit.
func mergeForgeFailure(previous, candidate forgediag.FailureInfo) forgediag.FailureInfo {
	if previous.ProducerID != "" && candidate.ProducerID != previous.ProducerID {
		return previous
	}
	result := previous
	if result.ProducerID == "" {
		result.ProducerID = candidate.ProducerID
	}
	if result.Boundary == nil {
		result.Boundary = candidate.Boundary
	}
	if result.RuntimeID == "" {
		result.RuntimeID = candidate.RuntimeID
	}
	if result.AdapterRevision == 0 {
		result.AdapterRevision = candidate.AdapterRevision
	}
	if result.Exit == nil {
		result.Exit = candidate.Exit
	}
	if candidate.Native != nil {
		if result.Native == nil || result.Native.ProducerID == candidate.Native.ProducerID && result.Native.Kind == "context" && (candidate.Native.Kind != "context" || candidate.Native.Sequence > result.Native.Sequence) {
			result.Native = candidate.Native
		}
	}
	result.CollectionDone = result.CollectionDone || candidate.CollectionDone
	return result
}

func forgeCrashReportWithRecovery(base protocol.RulesCrashReport, primary forgediag.FailureInfo, recovery *forgediag.FailureInfo, final bool) protocol.RulesCrashReport {
	report := completeForgeCrashReport(base, primary, final)
	if recovery != nil {
		failure := forgeCrashFailure(*recovery, "reconstruction_failed", base.Environment.HostingMode)
		report.RecoveryFailure = &failure
		if recovery.Native == nil {
			report.Completeness.Missing = append(report.Completeness.Missing, "recovery_native_evidence_unavailable")
		}
		if recovery.Exit == nil {
			report.Completeness.Missing = append(report.Completeness.Missing, "recovery_exit_evidence_unavailable")
		}
		if final && !recovery.CollectionDone {
			report.Completeness.Missing = append(report.Completeness.Missing, "recovery_collection_incomplete")
		}
		if final && len(report.Completeness.Missing) > 0 {
			report.CollectionState = "partial"
		}
	}
	return report
}

func forgeCrashFingerprint(report protocol.RulesCrashReport) string {
	parts := []string{"1", report.Failure.Kind, report.Versions.Runtime, strconv.Itoa(report.Versions.Adapter)}
	for _, cause := range report.Failure.Causes {
		parts = append(parts, cause.ClassName)
		for _, frame := range cause.Frames {
			parts = append(parts, frame.ClassName, frame.MethodName)
		}
	}
	if len(report.Failure.Causes) == 0 {
		parts = append(parts, report.Failure.Code, report.Failure.RequestFamily, report.Failure.ExitSignal)
		if report.Failure.ExitCode != nil {
			parts = append(parts, strconv.Itoa(*report.Failure.ExitCode))
		}
	}
	hash := sha256.Sum256([]byte(strings.Join(parts, "\x00")))
	return hex.EncodeToString(hash[:])
}

// Caller holds this room's opMu and invokes this before resetting the room.
func (h *Handler) captureForgeCrash(r *room.Room, game forgeRoomGame, recovery ...forge.Runtime) *protocol.RulesCrashReport {
	if h.forgeCrashes == nil {
		return nil
	}
	now := time.Now().UTC()
	var id [16]byte
	if _, err := rand.Read(id[:]); err != nil {
		return nil
	}
	context, dropped, code := game.diagnostics.snapshot(now)
	base := protocol.RulesCrashReport{SchemaVersion: 1, ReportID: hex.EncodeToString(id[:]), Revision: 1, OccurredAt: now.Format(time.RFC3339Nano),
		FingerprintVersion: 1, Versions: protocol.RulesCrashVersions{Hexproof: buildinfo.Version, Runtime: "unknown", Forge: "unknown"},
		Context: context, Completeness: protocol.RulesCrashCompleteness{DroppedEvents: dropped}, Failure: protocol.RulesCrashFailure{Code: code}}
	var recipients []string
	entry := h.hub.roomEntryFor(r.ID)
	if entry == nil {
		return nil
	}
	entry.mu.Lock()
	if entry.room != r || r.Phase != protocol.RoomPhaseStarted || r.Game != nil {
		entry.mu.Unlock()
		return nil
	}
	base.Environment = protocol.RulesCrashEnvironment{HostingMode: r.HostingMode, Format: r.Format, Participants: len(game.seatToPlayer), GameNumber: r.DrawnGames + 1}
	for _, wins := range r.Score {
		base.Environment.GameNumber += wins
	}
	for _, seat := range r.Seats {
		if seat.Occupied && seat.ConnectionID != "" {
			recipients = append(recipients, seat.ConnectionID)
		}
	}
	for _, spectator := range r.Spectators {
		recipients = append(recipients, spectator.ConnectionID)
	}
	entry.mu.Unlock()
	var recoveryRuntime forge.Runtime
	var recoveryInitial *forgediag.FailureInfo
	if len(recovery) > 0 {
		recoveryRuntime = recovery[0]
		value := forgeFailureInformation(recoveryRuntime)
		recoveryInitial = &value
	}
	initial := forgeFailureInformation(game.client)
	if initial.Native != nil && initial.Native.SessionID != game.sessionID {
		initial.Native = nil
	}
	if base.Failure.Code == "" && initial.Boundary != nil {
		base.Failure.Code = initial.Boundary.Code
	}
	needsCollection := !initial.CollectionDone || recoveryInitial != nil && !recoveryInitial.CollectionDone
	var begin chan bool
	if needsCollection {
		begin = make(chan bool, 1)
		gate := begin
		roomID, client, sessionID := r.ID, game.client, game.sessionID
		if !h.forgeCrashes.collect(func(done <-chan struct{}) {
			select {
			case ready := <-gate:
				if !ready {
					return
				}
			case <-done:
				return
			}
			deadline := now.Add(forgeCrashCollectionWindow)
			timer := time.NewTimer(max(time.Duration(0), time.Until(deadline)))
			ticker := time.NewTicker(50 * time.Millisecond)
			defer timer.Stop()
			defer ticker.Stop()
			info := initial
			recoveryInfo := recoveryInitial
			for {
				select {
				case <-done:
					return
				case <-ticker.C:
					if !time.Now().Before(deadline) {
						break
					}
					candidate := forgeFailureInformation(client)
					if candidate.Native != nil && candidate.Native.SessionID != sessionID {
						candidate.Native = nil
					}
					info = mergeForgeFailure(info, candidate)
					if recoveryInfo != nil {
						value := mergeForgeFailure(*recoveryInfo, forgeFailureInformation(recoveryRuntime))
						recoveryInfo = &value
					}
					if !info.CollectionDone || recoveryInfo != nil && !recoveryInfo.CollectionDone {
						continue
					}
				case <-timer.C:
				}
				final := forgeCrashReportWithRecovery(base, info, recoveryInfo, true)
				final.Revision = 2
				if h.forgeCrashes.put(final, roomID, nil, time.Now().UTC()) {
					h.sendForgeCrashRevision(final)
				}
				return
			}
		}) {
			begin = nil
		}
	}
	report := forgeCrashReportWithRecovery(base, initial, recoveryInitial, begin == nil)
	if needsCollection && begin == nil {
		report.CollectionState = "partial"
		report.Completeness.Missing = append(report.Completeness.Missing, "collection_capacity_reached")
	}
	if !h.forgeCrashes.put(report, r.ID, recipients, now) {
		if begin != nil {
			begin <- false
		}
		return nil
	}
	if begin != nil {
		begin <- true
	}
	return &report
}

func (h *Handler) sendForgeCrashReport(sess *Session, report protocol.RulesCrashReport) {
	if !sess.rulesCrashReports.Load() {
		return
	}
	code := protocol.ErrRulesUnavailable
	if report.Environment.HostingMode == protocol.HostingModePlayer {
		code = protocol.ErrPlayerHostLost
	}
	env, err := protocol.NewEnvelope(protocol.TypeError, protocol.ErrorPayload{Code: code, Message: "Forge stopped; a crash report is available", RulesCrashReport: &report})
	if err == nil {
		h.send(sess, env)
	}
}

func (h *Handler) sendForgeCrashRevision(report protocol.RulesCrashReport) {
	for _, id := range h.forgeCrashes.recipients(report.ReportID, time.Now()) {
		if sess := h.sessionByConn(id); sess != nil {
			h.sendForgeCrashReport(sess, report)
		}
	}
}

func (h *Handler) sendResumedForgeCrashReports(sess *Session, r *room.Room) {
	if !sess.rulesCrashReports.Load() {
		return
	}
	reports := h.forgeCrashes.forMember(r.ID, sess.ConnectionID, time.Now())
	if len(reports) > 8 {
		reports = reports[len(reports)-8:]
	}
	for _, report := range reports {
		h.sendForgeCrashReport(sess, report)
	}
}
