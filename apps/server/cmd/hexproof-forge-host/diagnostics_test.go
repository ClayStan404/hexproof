// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"hexproof/server/internal/rulesengine/forge"
	"hexproof/server/internal/runtimepkg"
)

func TestConcurrentDiagnosticsKeepStandaloneJSONLEnvelopes(t *testing.T) {
	var output bytes.Buffer
	var workers sync.WaitGroup
	for range 32 {
		workers.Add(1)
		go func() {
			defer workers.Done()
			writeDiagnostic(&output, runtimepkg.Diagnostic{Stage: "jvm_probe", Component: "java", Code: "completed"})
		}()
	}
	workers.Wait()
	scanner := bufio.NewScanner(&output)
	count := 0
	for scanner.Scan() {
		var envelope map[string]json.RawMessage
		if json.Unmarshal(scanner.Bytes(), &envelope) != nil || len(envelope) != 1 || envelope["diagnostic"] == nil {
			t.Fatalf("malformed or state-changing envelope: %s", scanner.Bytes())
		}
		count++
	}
	if scanner.Err() != nil || count != 32 {
		t.Fatalf("diagnostic count = %d, error = %v", count, scanner.Err())
	}
}

func TestRuntimeStartDiagnosticDropsRawErrorDetails(t *testing.T) {
	base := t.TempDir()
	_, err := forge.Start(context.Background(), forge.ProcessConfig{Command: filepath.Join(base, "private-command-token-secret")})
	event := runtimeStartDiagnostic(err, "jvm_start")
	if event.Code != "executable_missing" || event.Stage != "jvm_start" || event.Component != "java" {
		t.Fatalf("startup diagnostic = %+v", event)
	}
	var output bytes.Buffer
	writeDiagnostic(&output, event)
	for _, secret := range []string{"private-command", "token", "secret", base} {
		if strings.Contains(output.String(), secret) {
			t.Fatalf("diagnostic exposed a path or error: %s", output.String())
		}
	}
}

func TestImportFailureEmitsDiagnosticAndCompatibleState(t *testing.T) {
	base := t.TempDir()
	command := exec.Command(os.Args[0], "-test.run=TestForgeHostDiagnosticHelper")
	command.Env = append(os.Environ(), "HEXPROOF_HOST_DIAGNOSTIC_TEST="+base)
	output, err := command.Output()
	if exit, ok := err.(*exec.ExitError); !ok || exit.ExitCode() != 1 {
		t.Fatalf("helper error = %v, output = %s", err, output)
	}
	if bytes.Contains(output, []byte(base)) || bytes.Contains(output, []byte("private-pack-token-secret")) {
		t.Fatalf("helper leaked filesystem details: %s", output)
	}
	foundState, foundDiagnostic := false, false
	scanner := bufio.NewScanner(bytes.NewReader(output))
	for scanner.Scan() {
		var envelope struct {
			State      string                `json:"state"`
			Diagnostic runtimepkg.Diagnostic `json:"diagnostic"`
		}
		if err := json.Unmarshal(scanner.Bytes(), &envelope); err != nil {
			t.Fatal(err)
		}
		foundState = foundState || envelope.State == "import_failed"
		foundDiagnostic = foundDiagnostic || (envelope.Diagnostic.Code == "file_missing" && envelope.Diagnostic.Stage == "import")
	}
	if scanner.Err() != nil || !foundState || !foundDiagnostic {
		t.Fatalf("helper did not preserve state and detailed failure: %s", output)
	}
}

func TestForgeHostDiagnosticHelper(t *testing.T) {
	base := os.Getenv("HEXPROOF_HOST_DIAGNOSTIC_TEST")
	if base == "" {
		return
	}
	os.Args = []string{os.Args[0], "--runtime-dir", base, "--import-pack", filepath.Join(base, "private-pack-token-secret.hexproof-forgepack")}
	flag.CommandLine = flag.NewFlagSet(os.Args[0], flag.ExitOnError)
	os.Exit(run())
}
