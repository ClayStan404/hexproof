// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forgediag

import (
	"bytes"
	"crypto/sha256"
	_ "embed"
	"encoding/hex"
	"encoding/json"
	"io"
	"unicode"
)

//go:embed diagnostic-symbols.json
var symbolData []byte

var symbols = readSymbols()

var cardNames = func() map[string]bool {
	values := make(map[string]bool, len(symbols.CardNames))
	for _, name := range symbols.CardNames {
		values[name] = true
	}
	return values
}()

type symbolIndex struct {
	ID            string
	SchemaVersion int                 `json:"schemaVersion"`
	RuntimeID     string              `json:"runtimeId"`
	Classes       map[string][]string `json:"classes"`
	APIs          []string            `json:"apis"`
	CardNames     []string            `json:"cardNames"`
}

func readSymbols() symbolIndex {
	var index symbolIndex
	if json.Unmarshal(symbolData, &index) != nil || index.SchemaVersion != 1 {
		return symbolIndex{}
	}
	hash := sha256.Sum256(symbolData)
	index.ID = hex.EncodeToString(hash[:])
	return index
}

func SymbolIndexID() string { return symbols.ID }

// SymbolRuntimeID is the pinned source revision/adapter declaration bound to
// the embedded code-symbol index. It is not a distribution package checksum.
func SymbolRuntimeID() string { return symbols.RuntimeID }

func oneOf(value string, values ...string) bool {
	for _, candidate := range values {
		if candidate == value {
			return true
		}
	}
	return false
}

func boundedText(value string, limit int) bool {
	if len(value) > limit {
		return false
	}
	for _, r := range value {
		if unicode.IsControl(r) {
			return false
		}
	}
	return true
}

func identity(value string) bool {
	if len(value) == 0 || len(value) > 128 {
		return false
	}
	for _, r := range value {
		if !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '-' || r == '_' || r == ':' || r == '.') {
			return false
		}
	}
	return true
}

func decode(raw []byte, value any, limit int) bool {
	if len(raw) == 0 || len(raw) > limit {
		return false
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	return decoder.Decode(value) == nil && decoder.Decode(new(any)) == io.EOF
}

// ParseCapsule drops unverified symbols and malformed optional observations.
// Its required envelope must be valid; untrusted fields are never reserialized.
func ParseCapsule(raw []byte) *Capsule {
	var capsule Capsule
	if !decode(raw, &capsule, MaxCapsuleBytes) {
		return nil
	}
	return SanitizeCapsule(&capsule)
}

func SanitizeCapsule(input *Capsule) *Capsule {
	if input == nil || input.SchemaVersion != SchemaVersion || !identity(input.ProducerID) ||
		(input.SessionID != "" && !identity(input.SessionID)) || input.Sequence == 0 || input.Sequence > MaxSafeInteger ||
		!oneOf(input.Kind, "engine_exception", "resource_exhausted", "execution_timeout", "context") ||
		!oneOf(input.Boundary, "effect", "decision", "game_callback", "edt_callback", "delayed_callback", "submitted_task", "rpc", "bootstrap", "input_boundary_timeout") ||
		!oneOf(input.Attribution, "execution_site", "resolution_context", "recent_context", "unknown") {
		return nil
	}
	output := *input
	output.Causes = nil
	output.Spans = nil
	output.Events = nil
	output.ElapsedMs = boundedCount64(input.ElapsedMs)
	output.OmittedCauses = boundedCount(input.OmittedCauses)
	output.OmittedFrames = boundedCount(input.OmittedFrames)
	output.OmittedSpans = boundedCount(input.OmittedSpans)
	output.DroppedEvents = boundedCount(input.DroppedEvents)
	verified := input.SymbolIndexID != "" && input.SymbolIndexID == symbols.ID
	if !verified {
		output.SymbolIndexID = ""
	}
	frames := 0
	for i, cause := range input.Causes {
		if i >= 4 {
			output.OmittedCauses++
			continue
		}
		value := Cause{ClassName: safeClass(cause.ClassName, verified)}
		for _, frame := range cause.Frames {
			if frames >= 32 {
				output.OmittedFrames++
				continue
			}
			if !safeFrame(frame, verified) {
				output.OmittedFrames++
				continue
			}
			if frame.Line < 0 || frame.Line > 10000000 {
				frame.Line = 0
			}
			value.Frames = append(value.Frames, frame)
			frames++
		}
		output.Causes = append(output.Causes, value)
	}
	for i, span := range input.Spans {
		if i >= 8 {
			output.OmittedSpans++
			continue
		}
		if span.ID == 0 || span.ID > MaxSafeInteger || span.ParentID > MaxSafeInteger || !oneOf(span.Stage, "effect", "decision", "game_callback", "edt_callback", "delayed_callback", "submitted_task", "rpc", "bootstrap") {
			output.OmittedSpans++
			continue
		}
		if span.API != "" && (!verified || !oneOf(span.API, symbols.APIs...)) {
			span.API = ""
		}
		span.Source = sanitizeSource(span.Source)
		output.Spans = append(output.Spans, span)
	}
	var previous uint64
	for i, event := range input.Events {
		if i >= 128 {
			output.DroppedEvents++
			continue
		}
		if event.Sequence <= previous || event.Sequence > MaxSafeInteger || event.SpanID == 0 || event.SpanID > MaxSafeInteger || !oneOf(event.Kind, "effect_enter", "effect_exit", "decision", "callback") || !oneOf(event.Stage, "effect", "decision", "game_callback", "edt_callback", "delayed_callback", "submitted_task", "rpc", "bootstrap") {
			output.DroppedEvents++
			continue
		}
		previous = event.Sequence
		if event.API != "" && (!verified || !oneOf(event.API, symbols.APIs...)) {
			event.API = ""
		}
		output.Events = append(output.Events, event)
	}
	if raw, err := json.Marshal(output); err != nil || len(raw) > MaxCapsuleBytes {
		return nil
	}
	return &output
}

func safeClass(value string, verified bool) string {
	if oneOf(value, "unknown", "jdk", "dependency",
		"java.lang.NullPointerException", "java.lang.IllegalArgumentException", "java.lang.IllegalStateException", "java.lang.UnsupportedOperationException", "java.lang.AssertionError", "java.lang.OutOfMemoryError", "java.lang.StackOverflowError", "java.lang.IndexOutOfBoundsException", "java.lang.ArrayIndexOutOfBoundsException", "java.lang.ArithmeticException", "java.lang.ClassCastException", "java.lang.RuntimeException", "java.lang.Error", "java.lang.Exception", "java.util.concurrent.ExecutionException", "java.util.concurrent.CancellationException", "java.util.concurrent.TimeoutException", "java.lang.NumberFormatException", "java.util.NoSuchElementException", "java.util.ConcurrentModificationException", "java.lang.IllegalMonitorStateException", "java.util.concurrent.RejectedExecutionException") {
		return value
	}
	if verified {
		if _, exists := symbols.Classes[value]; exists {
			return value
		}
	}
	return "unknown"
}

func safeFrame(frame Frame, verified bool) bool {
	if oneOf(frame.ClassName, "jdk", "dependency", "unknown") {
		return frame.MethodName == "omitted"
	}
	return verified && oneOf(frame.MethodName, symbols.Classes[frame.ClassName]...)
}

func sanitizeSource(input *Source) *Source {
	if input == nil || !identity(input.ObjectID) || !identity(input.Incarnation) || input.ObservationSequence == 0 || input.ObservationSequence > MaxSafeInteger ||
		input.Disclosure != "public_zone" || !oneOf(input.Zone, "battlefield", "stack", "graveyard", "exile", "command") {
		return nil
	}
	output := *input
	output.Card = nil
	if input.Card != nil && KnownCardName(input.Card.Name) && boundedText(input.Card.Name, 256) && boundedText(input.Card.SetCode, 32) && boundedText(input.Card.CardNumber, 32) {
		card := *input.Card
		output.Card = &card
	}
	return &output
}

func boundedCount(value int) int {
	if value < 0 {
		return 0
	}
	if value > 1000000 {
		return 1000000
	}
	return value
}
func boundedCount64(value int64) int64 {
	if value < 0 {
		return 0
	}
	if value > 365*24*60*60*1000 {
		return 365 * 24 * 60 * 60 * 1000
	}
	return value
}

func SanitizeFailure(input FailureInfo) FailureInfo {
	output := FailureInfo{CollectionDone: input.CollectionDone}
	if identity(input.ProducerID) {
		output.ProducerID = input.ProducerID
	}
	if input.AdapterRevision > 0 && input.AdapterRevision < 10000 {
		output.AdapterRevision = input.AdapterRevision
	}
	if input.RuntimeID != "" && input.RuntimeID == symbols.RuntimeID {
		output.RuntimeID = input.RuntimeID
	}
	if input.Boundary != nil && oneOf(input.Boundary.Code, "native_failure", "execution_timeout", "protocol_invalid", "protocol_eof", "response_too_large", "pipe_write_failed", "publication_invalid", "process_exited", "host_connection_lost", "reconstruction_failed") {
		boundary := *input.Boundary
		boundary.ElapsedMillis = boundedCount64(boundary.ElapsedMillis)
		boundary.RequestFamily = RequestFamily(boundary.RequestFamily)
		output.Boundary = &boundary
	}
	output.Native = SanitizeCapsule(input.Native)
	if input.Exit != nil {
		exit := *input.Exit
		if exit.Code != nil {
			code := *exit.Code
			if code >= -1 && code <= 65535 {
				exit.Code = &code
			} else {
				exit.Code = nil
			}
		}
		if !oneOf(exit.Signal, "", "killed", "terminated", "aborted", "segmentation_fault", "other") {
			exit.Signal = "other"
		}
		output.Exit = &exit
	}
	return output
}

func RequestFamily(value string) string {
	if oneOf(value, "reset", "startGame", "submitAction", "getSnapshot", "getSnapshots", "getPrompt", "awaitPrompt", "getGameOver", "endGame", "abortGame", "getReplay", "start", "action", "restore", "stop", "publication", "peer_action") {
		return value
	}
	return ""
}

func ParseFailure(raw []byte) *FailureInfo {
	var value FailureInfo
	if !decode(raw, &value, MaxFailureBytes) {
		return nil
	}
	value = SanitizeFailure(value)
	if value.ProducerID == "" {
		return nil
	}
	return &value
}

func StreamRecord(line []byte) *Capsule {
	if !bytes.HasPrefix(line, []byte(StreamPrefix)) {
		return nil
	}
	return ParseCapsule(bytes.TrimSpace(line[len(StreamPrefix):]))
}

// These checks intentionally do not accept Java-looking unverified symbols.
func HasNativeEvidence(value FailureInfo) bool { return value.Native != nil }

func KnownCardName(name string) bool { return name != "" && cardNames[name] }

func Equal(a, b FailureInfo) bool {
	left, _ := json.Marshal(a)
	right, _ := json.Marshal(b)
	return bytes.Equal(left, right)
}
