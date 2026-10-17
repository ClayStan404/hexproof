// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forgehost

import (
	"context"
	"encoding/json"
	"errors"

	"hexproof/server/internal/forgediag"
	"hexproof/server/internal/rulesengine/forge"
)

func publicationFailureCode(err error) string {
	if errors.Is(err, context.DeadlineExceeded) {
		return "execution_timeout"
	}
	return "publication_invalid"
}

func (e *Executor) captureFailure(runtime forge.Runtime, engineID, code, request string) {
	if runtime == nil {
		return
	}
	value := forge.SnapshotFailure(runtime)
	value.ProducerID = engineID
	if value.Boundary == nil {
		value.Boundary = &forgediag.Boundary{Code: code, RequestFamily: request, Dispatched: true}
	}
	e.stateMu.Lock()
	if e.engineID != engineID {
		e.stateMu.Unlock()
		return
	}
	first := e.failure == nil
	if first {
		e.failure = &value
		e.failedRuntime = runtime
	}
	e.stateMu.Unlock()
	if first && e.onFailure != nil {
		go e.onFailure(engineID)
	}
}

// RetainedFailure survives Cancel and reconnect. Late reap/native information
// can enrich only the same engine; a new start clears this retained ownership.
func (e *Executor) RetainedFailure(engineID string) *forgediag.FailureInfo {
	e.stateMu.Lock()
	if e.engineID != engineID || e.failure == nil {
		e.stateMu.Unlock()
		return nil
	}
	value := forgediag.SanitizeFailure(*e.failure)
	runtime := e.failedRuntime
	e.stateMu.Unlock()
	if runtime != nil {
		late := forge.SnapshotFailure(runtime)
		if late.ProducerID != "" {
			if late.Native != nil && (value.Native == nil || value.Native.Kind == "context") {
				value.Native = late.Native
			}
			if late.Exit != nil {
				value.Exit = late.Exit
			}
			value.CollectionDone = late.CollectionDone
		}
	}
	return &value
}

func sanitizeRelayFailure(input *forgediag.FailureInfo) *forgediag.FailureInfo {
	if input == nil {
		return nil
	}
	raw, err := json.Marshal(input)
	if err != nil {
		return nil
	}
	return forgediag.ParseFailure(raw)
}

func (r *Runtime) acceptFailure(input *forgediag.FailureInfo) {
	value := sanitizeRelayFailure(input)
	if value == nil {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.failure.ProducerID != "" && r.failure.ProducerID != value.ProducerID {
		return
	}
	if r.failure.Boundary != nil {
		value.Boundary = r.failure.Boundary
	}
	if r.failure.Native != nil && r.failure.Native.Kind != "context" {
		value.Native = r.failure.Native
	}
	r.failure = *value
}

func (r *Runtime) failureBoundary(code, request string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.failure.ProducerID == "" {
		r.failure.ProducerID = r.engineID
	}
	if r.failure.Boundary == nil {
		r.failure.Boundary = &forgediag.Boundary{Code: code, RequestFamily: request}
	}
}

func (r *Runtime) FailureInfo() forgediag.FailureInfo {
	r.mu.Lock()
	defer r.mu.Unlock()
	return forgediag.SanitizeFailure(r.failure)
}

// DiagnosticRuntimeID comes from an admitted authenticated helper handshake,
// never from a failure capsule or a runtime's arbitrary stdout metadata.
func (r *Runtime) DiagnosticRuntimeID() string {
	r.link.mu.Lock()
	defer r.link.mu.Unlock()
	return r.link.runtimeID
}

var _ forge.FailureSource = (*Runtime)(nil)
