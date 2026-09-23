// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package main

import (
	"encoding/json"
	"errors"
	"io"
	"os"

	"hexproof/server/internal/rulesengine/forge"
	"hexproof/server/internal/runtimepkg"
)

func emitDiagnostic(event runtimepkg.Diagnostic) {
	writeDiagnostic(os.Stdout, event)
}

// Diagnostic envelopes never contain the UI state key or raw errors. They
// share stdout's mutex with state and peer messages so concurrent JVM startup
// diagnostics cannot corrupt the parent pipe's JSONL framing.
func writeDiagnostic(output io.Writer, event runtimepkg.Diagnostic) {
	outputMu.Lock()
	defer outputMu.Unlock()
	_ = json.NewEncoder(output).Encode(struct {
		Diagnostic runtimepkg.Diagnostic `json:"diagnostic"`
	}{event})
}

func runtimeStartDiagnostic(err error, stage string) runtimepkg.Diagnostic {
	var process *forge.ProcessError
	if errors.As(err, &process) {
		return runtimepkg.Diagnostic{Stage: stage, Component: "java", Code: process.Code, ExitCode: process.ExitCode}
	}
	return runtimepkg.ErrorDiagnostic(err, stage, "java")
}

func reportStep(stage, component, code string) {
	emitDiagnostic(runtimepkg.Diagnostic{Stage: stage, Component: component, Code: code})
}
