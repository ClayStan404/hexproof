// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"testing"

	"hexproof/server/internal/rulesengine/forge"
)

func TestForgeRuntimeCapabilityProbe(t *testing.T) {
	if os.Getenv("HEXPROOF_FORGE_SERVER_TEST_HELPER") == "1" {
		runForgeProbeHelper(t)
		return
	}

	config := DefaultConfig()
	config.ForgeRuntime = &forge.ProcessConfig{
		Command: os.Args[0],
		Args:    []string{"-test.run=TestForgeRuntimeCapabilityProbe"},
		Env:     []string{"HEXPROOF_FORGE_SERVER_TEST_HELPER=1"},
	}
	handler, err := NewHandlerWithConfig(config)
	if err != nil {
		t.Fatalf("NewHandlerWithConfig: %v", err)
	}
	if !handler.forgeRulesAvailable() {
		t.Fatal("successfully probed Forge runtime was not advertised")
	}
}

func runForgeProbeHelper(t *testing.T) {
	t.Helper()
	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		var request struct {
			Command string `json:"command"`
		}
		if err := json.Unmarshal(scanner.Bytes(), &request); err != nil {
			t.Fatalf("decode helper request: %v", err)
		}
		if request.Command == "quit" {
			return
		}
		if _, err := fmt.Fprintln(os.Stdout, `{"ok":true,"result":""}`); err != nil {
			t.Fatalf("write helper response: %v", err)
		}
	}
	if err := scanner.Err(); err != nil {
		t.Fatalf("read helper request: %v", err)
	}
}
