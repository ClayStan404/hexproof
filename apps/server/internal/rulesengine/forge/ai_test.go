// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func TestAIRequiresExplicitCapabilityDedicatedProcessAndValidDifficulty(t *testing.T) {
	request := validStartRequest()
	request.Players[1].AI, request.Players[1].AIDifficulty = true, "normal"
	old := newHelperClient(t, "normal")
	defer old.Close()
	if old.SupportsAI() {
		t.Fatal("old runtime advertised AI")
	}
	if _, err := old.StartGame(t.Context(), request); err == nil {
		t.Fatal("AI accepted by legacy runtime")
	}
	if !old.Healthy() {
		t.Fatal("rejected configuration killed legacy runtime")
	}
	capable := newHelperClient(t, "ai-capable")
	defer capable.Close()
	if !capable.SupportsAI() {
		t.Fatal("AI capability missing")
	}
	if _, err := capable.StartGame(t.Context(), request); err != nil {
		t.Fatal(err)
	}
	if capable.RequestTimeout() != 35*time.Second {
		t.Fatal("AI computation has human timeout")
	}
	request.Players[1].AIDifficulty = "unknown"
	if err := request.validate(); err == nil {
		t.Fatal("unknown difficulty accepted")
	}
	request.Players[1].AIDifficulty, request.Players[1].AI = "easy", false
	if err := request.validate(); err == nil {
		t.Fatal("human difficulty accepted")
	}
	shared := &Client{supportsAI: true, shared: &sharedLease{}}
	request.Players[1].AI = true
	if _, err := shared.StartGame(t.Context(), request); err == nil {
		t.Fatal("shared lease accepted AI")
	}
}

func TestNativeFatalActionRetiresRuntimeWithoutDisclosingDetails(t *testing.T) {
	client := newHelperClient(t, "action-failed")
	defer client.Close()
	err := client.SubmitAction(t.Context(), "session", json.RawMessage(`{"type":"fixture"}`))
	if err == nil || client.Healthy() || strings.Contains(err.Error(), "private engine detail") {
		t.Fatalf("fatal action remained usable or exposed diagnostics: %v", err)
	}
}

func TestDuelAIRequiresSeparateCapabilityAndTwentyLife(t *testing.T) {
	request := validStartRequest()
	request.Variant, request.StartingLife = "Commander", 20
	request.Players[1].AI, request.Players[1].AIDifficulty = true, "normal"
	old := newHelperClient(t, "ai-capable")
	defer old.Close()
	if old.SupportsDuelAI() {
		t.Fatal("constructed-only runtime advertised Duel AI")
	}
	if _, err := old.StartGame(t.Context(), request); err == nil || !old.Healthy() {
		t.Fatal("legacy Duel AI admission did not reject cleanly")
	}
	capable := newHelperClient(t, "duel-ai-capable")
	defer capable.Close()
	if !capable.SupportsDuelAI() {
		t.Fatal("Duel AI capability missing")
	}
	if _, err := capable.StartGame(t.Context(), request); err != nil {
		t.Fatal(err)
	}
	request.StartingLife = 40
	if err := request.validate(); err == nil {
		t.Fatal("EDH AI accepted")
	}
	request.StartingLife = 20
	request.Players[0].AI, request.Players[0].AIDifficulty = true, "hard"
	if err := request.validate(); err == nil {
		t.Fatal("two AI seats accepted")
	}
}
