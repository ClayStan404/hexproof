// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Package forgediag defines the bounded, private diagnostic boundary between
// the native engine, its supervisor and the authenticated hosting relay.
package forgediag

const (
	SchemaVersion   = 1
	MaxCapsuleBytes = 16 << 10
	MaxFailureBytes = 20 << 10
	StreamPrefix    = "HEXPROOF_DIAG_V1 "
	MaxSafeInteger  = uint64(1<<53 - 1)
)

type Frame struct {
	ClassName  string `json:"className"`
	MethodName string `json:"methodName"`
	Line       int    `json:"line,omitempty"`
}

type Cause struct {
	ClassName string  `json:"className"`
	Frames    []Frame `json:"frames,omitempty"`
}

// CardReference is never a display name. The hub resolves it against its
// trusted catalog before using any identity in a public report.
type CardReference struct {
	Name       string `json:"name,omitempty"`
	SetCode    string `json:"setCode,omitempty"`
	CardNumber string `json:"cardNumber,omitempty"`
	IsToken    bool   `json:"isToken,omitempty"`
}

type Source struct {
	ObjectID            string         `json:"objectId"`
	Incarnation         string         `json:"incarnation"`
	ObservationSequence uint64         `json:"observationSequence"`
	Zone                string         `json:"zone"`
	Disclosure          string         `json:"disclosure"`
	Card                *CardReference `json:"card,omitempty"`
}

type Span struct {
	ID       uint64  `json:"id"`
	ParentID uint64  `json:"parentId,omitempty"`
	Stage    string  `json:"stage"`
	API      string  `json:"api,omitempty"`
	Source   *Source `json:"source,omitempty"`
}

type Event struct {
	Sequence uint64 `json:"sequence"`
	Kind     string `json:"kind"`
	SpanID   uint64 `json:"spanId"`
	Stage    string `json:"stage"`
	API      string `json:"api,omitempty"`
}

type Capsule struct {
	SchemaVersion int     `json:"schemaVersion"`
	ProducerID    string  `json:"producerId"`
	SessionID     string  `json:"sessionId,omitempty"`
	Sequence      uint64  `json:"sequence"`
	ElapsedMs     int64   `json:"elapsedMs,omitempty"`
	Kind          string  `json:"kind"`
	Boundary      string  `json:"boundary"`
	Attribution   string  `json:"attribution"`
	SymbolIndexID string  `json:"symbolIndexId,omitempty"`
	Causes        []Cause `json:"causes,omitempty"`
	Spans         []Span  `json:"spans,omitempty"`
	Events        []Event `json:"events,omitempty"`
	OmittedCauses int     `json:"omittedCauses,omitempty"`
	OmittedFrames int     `json:"omittedFrames,omitempty"`
	OmittedSpans  int     `json:"omittedSpans,omitempty"`
	DroppedEvents int     `json:"droppedEvents,omitempty"`
}

type Boundary struct {
	Code          string `json:"code"`
	RequestFamily string `json:"requestFamily,omitempty"`
	Dispatched    bool   `json:"dispatched"`
	ElapsedMillis int64  `json:"elapsedMillis,omitempty"`
}

type Exit struct {
	Code             *int   `json:"code,omitempty"`
	Signal           string `json:"signal,omitempty"`
	SupervisorKilled bool   `json:"supervisorKilled,omitempty"`
}

// FailureInfo has no error strings or private snapshots. It is safe to relay
// after sanitizing, but card references still require hub catalog resolution.
type FailureInfo struct {
	ProducerID      string    `json:"producerId"`
	AdapterRevision int       `json:"adapterRevision,omitempty"`
	RuntimeID       string    `json:"runtimeId,omitempty"`
	Boundary        *Boundary `json:"boundary,omitempty"`
	Native          *Capsule  `json:"native,omitempty"`
	Exit            *Exit     `json:"exit,omitempty"`
	CollectionDone  bool      `json:"collectionDone"`
}
