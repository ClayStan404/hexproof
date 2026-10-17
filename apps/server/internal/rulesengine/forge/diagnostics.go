// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"bufio"
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"io"
	"os/exec"
	"sync"
	"time"

	"hexproof/server/internal/forgediag"
)

type diagnosticCollector struct {
	mu             sync.Mutex
	info           forgediag.FailureInfo
	sessionID      string
	nativeProducer string
	request        string
	started        time.Time
	stderrDone     bool
	reaped         bool
	forced         bool
}

func newDiagnosticCollector() *diagnosticCollector {
	var id [16]byte
	_, _ = rand.Read(id[:])
	return &diagnosticCollector{info: forgediag.FailureInfo{ProducerID: hex.EncodeToString(id[:])}}
}

func (d *diagnosticCollector) snapshot() forgediag.FailureInfo {
	if d == nil {
		return forgediag.FailureInfo{}
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	value := forgediag.SanitizeFailure(d.info)
	value.CollectionDone = d.reaped && d.stderrDone
	return value
}

func (d *diagnosticCollector) begin(request string) {
	if d == nil {
		return
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	d.request, d.started = forgediag.RequestFamily(request), time.Now()
}

func (d *diagnosticCollector) boundary(code string) {
	if d == nil {
		return
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.info.Boundary != nil {
		return
	}
	elapsed := int64(0)
	if !d.started.IsZero() {
		elapsed = time.Since(d.started).Milliseconds()
	}
	d.info.Boundary = &forgediag.Boundary{Code: code, RequestFamily: d.request, Dispatched: !d.started.IsZero(), ElapsedMillis: elapsed}
}

func (d *diagnosticCollector) accept(capsule *forgediag.Capsule) {
	if d == nil || capsule == nil {
		return
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.sessionID != "" && capsule.SessionID != d.sessionID {
		return
	}
	if d.nativeProducer != "" && capsule.ProducerID != d.nativeProducer {
		return
	}
	old := d.info.Native
	if old != nil && (old.ProducerID != capsule.ProducerID || old.Kind != "context" || capsule.Kind == "context" && capsule.Sequence <= old.Sequence) {
		return
	}
	d.info.Native = capsule
	if capsule.SymbolIndexID != "" && capsule.SymbolIndexID == forgediag.SymbolIndexID() {
		d.info.RuntimeID = forgediag.SymbolRuntimeID()
	}
}

func (d *diagnosticCollector) bind(session, producer string, adapter int) {
	if d == nil {
		return
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	d.sessionID = session
	d.nativeProducer = producer
	d.info.AdapterRevision = adapter
	if d.info.Native != nil && (d.info.Native.SessionID != session || producer != "" && d.info.Native.ProducerID != producer) {
		d.info.Native = nil
	}
}

func (d *diagnosticCollector) streamAccept(capsule *forgediag.Capsule) {
	if d == nil {
		return
	}
	d.mu.Lock()
	bound := d.nativeProducer != ""
	d.mu.Unlock()
	if bound {
		d.accept(capsule)
	}
}

func (d *diagnosticCollector) exit(err error) {
	if d == nil {
		return
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	code := 0
	exit := &forgediag.Exit{Code: &code, SupervisorKilled: d.forced}
	var status *exec.ExitError
	if errors.As(err, &status) {
		code = status.ExitCode()
		if code < 0 {
			exit.Signal = processSignal(status)
		}
	}
	d.info.Exit = exit
	d.reaped = true
}

func (d *diagnosticCollector) kill() {
	if d == nil {
		return
	}
	d.mu.Lock()
	d.forced = !d.reaped
	d.mu.Unlock()
}

func (d *diagnosticCollector) drained() {
	if d == nil {
		return
	}
	d.mu.Lock()
	d.stderrDone = true
	d.mu.Unlock()
}

// Drain every line independently. ReadSlice limits memory and resynchronizes
// after malformed or oversized lines instead of permanently blinding capture.
// Ordinary output is deliberately discarded; a configured slow logger cannot
// block the child's diagnostic pipe or receive unsanitized engine text.
func drainDiagnostics(reader io.Reader, accept func(*forgediag.Capsule)) {
	buffer := bufio.NewReaderSize(reader, forgediag.MaxCapsuleBytes+len(forgediag.StreamPrefix)+2)
	window, records := time.Now(), 0
	dropping := false
	for {
		line, err := buffer.ReadSlice('\n')
		if !dropping && err != bufio.ErrBufferFull {
			if time.Since(window) >= time.Second {
				window, records = time.Now(), 0
			}
			if records < 256 {
				if bytes.HasPrefix(line, []byte(forgediag.StreamPrefix)) {
					records++
				}
				if capsule := forgediag.StreamRecord(line); capsule != nil {
					accept(capsule)
				}
			}
		}
		if err == bufio.ErrBufferFull {
			dropping = true
			continue
		}
		dropping = false
		if err != nil {
			return
		}
	}
}

func (client *Client) FailureInfo() forgediag.FailureInfo {
	value := client.diagnostics.snapshot()
	if client.shared != nil {
		worker := client.shared.worker.diagnostics.snapshot()
		if value.Exit == nil {
			value.Exit = worker.Exit
		}
		if value.Boundary == nil {
			value.Boundary = worker.Boundary
		}
		select {
		case <-client.done:
			if worker.Exit != nil || !client.shared.worker.healthy() {
				value.CollectionDone = worker.CollectionDone
			} else {
				value.CollectionDone = true
			}
		default:
		}
	}
	return value
}

func SnapshotFailure(runtime Runtime) forgediag.FailureInfo {
	if source, ok := runtime.(FailureSource); ok {
		return forgediag.SanitizeFailure(source.FailureInfo())
	}
	return forgediag.FailureInfo{}
}
