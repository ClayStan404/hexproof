// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

// RulesCrashReport is a bounded, public-safe diagnostic, independent of live
// room projections and private replay permissions. No engine strings are copied
// here without the native diagnostic sanitizer and public-source validation.
type RulesCrashReport struct {
	SchemaVersion      int                    `json:"schemaVersion"`
	ReportID           string                 `json:"reportId"`
	Revision           int                    `json:"revision"`
	CollectionState    string                 `json:"collectionState"`
	OccurredAt         string                 `json:"occurredAt"`
	FingerprintVersion int                    `json:"fingerprintVersion"`
	Fingerprint        string                 `json:"fingerprint"`
	Versions           RulesCrashVersions     `json:"versions"`
	Environment        RulesCrashEnvironment  `json:"environment"`
	Failure            RulesCrashFailure      `json:"failure"`
	RecoveryFailure    *RulesCrashFailure     `json:"recoveryFailure,omitempty"`
	Context            RulesCrashContext      `json:"context"`
	Completeness       RulesCrashCompleteness `json:"completeness"`
}

type RulesCrashVersions struct {
	Hexproof string `json:"hexproof"`
	Runtime  string `json:"runtime"`
	Forge    string `json:"forge"`
	Adapter  int    `json:"adapter"`
}

type RulesCrashEnvironment struct {
	HostingMode  string `json:"hostingMode"`
	Format       string `json:"format"`
	Participants int    `json:"participants"`
	GameNumber   int    `json:"gameNumber"`
}

type RulesCrashFailure struct {
	Kind          string            `json:"kind"`
	Code          string            `json:"code"`
	Stage         string            `json:"stage"`
	RequestFamily string            `json:"requestFamily,omitempty"`
	ExitCode      *int              `json:"exitCode,omitempty"`
	ExitSignal    string            `json:"exitSignal,omitempty"`
	Causes        []RulesCrashCause `json:"causes"`
}

type RulesCrashCause struct {
	ClassName string            `json:"className"`
	Frames    []RulesCrashFrame `json:"frames"`
}

type RulesCrashFrame struct {
	ClassName  string `json:"className"`
	MethodName string `json:"methodName"`
	Line       int    `json:"line"`
}

type RulesCrashContext struct {
	Attribution      string             `json:"attribution"`
	Turn             int                `json:"turn"`
	Step             string             `json:"step"`
	ActiveSeat       *int               `json:"activeSeat,omitempty"`
	PublicSequence   int64              `json:"publicSequence"`
	ObservationAgeMs *int64             `json:"observationAgeMs,omitempty"`
	Spans            []RulesCrashSpan   `json:"spans"`
	Sources          []RulesCrashSource `json:"sources"`
	Events           []RulesCrashEvent  `json:"events"`
}

type RulesCrashSpan struct {
	ID       int64  `json:"id"`
	ParentID int64  `json:"parentId"`
	Stage    string `json:"stage"`
	API      string `json:"api,omitempty"`
	SourceID string `json:"sourceId,omitempty"`
}

type RulesCrashSource struct {
	ID       string            `json:"id"`
	Zone     string            `json:"zone"`
	Identity RulesCardIdentity `json:"identity"`
}

type RulesCrashEvent struct {
	Origin    string `json:"origin"`
	Sequence  int64  `json:"sequence"`
	Kind      string `json:"kind"`
	Stage     string `json:"stage,omitempty"`
	API       string `json:"api,omitempty"`
	SpanID    int64  `json:"spanId,omitempty"`
	Seat      *int   `json:"seat,omitempty"`
	Turn      int    `json:"turn,omitempty"`
	Step      string `json:"step,omitempty"`
	Automatic bool   `json:"automatic,omitempty"`
}

type RulesCrashCompleteness struct {
	NativeEvidence bool     `json:"nativeEvidence"`
	ExitEvidence   bool     `json:"exitEvidence"`
	OmittedFrames  int      `json:"omittedFrames"`
	OmittedCauses  int      `json:"omittedCauses"`
	OmittedSpans   int      `json:"omittedSpans"`
	OmittedSources int      `json:"omittedSources"`
	DroppedEvents  int      `json:"droppedEvents"`
	Missing        []string `json:"missing"`
}
