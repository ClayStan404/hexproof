// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

const rejectedDeckJSON = `{"reason":"deck_rejected","issues":[{"playerIndex":0,"section":"mainboard","cardIndex":0,"code":"printing_unavailable"}]}`

func TestStartFailureReconstructsOnlyOriginalRegisteredIdentity(t *testing.T) {
	request := validStartRequest()
	detail := ParseStartFailure(json.RawMessage(rejectedDeckJSON), request)
	if detail == nil || detail.Reason() != "deck_rejected" || len(detail.Issues()) != 1 || detail.Issues()[0].Card != request.Players[0].Deck[0] {
		t.Fatal("registered identity was not reconstructed")
	}
	if strings.Contains(detail.Error(), "Forest") || strings.Contains(string(StartFailureJSON(detail)), "Forest") {
		t.Fatal("private identity escaped the safe error or relay reference")
	}
	issues := detail.Issues()
	issues[0].Card.Name = "mutated"
	if detail.Issues()[0].Card.Name != "Forest" {
		t.Fatal("caller mutated retained failure")
	}
	request.Players[1].Sideboard = []CardIdentity{{Name: "Private sideboard", SetCode: "M21", CollectorNumber: "272"}}
	request.Players[1].CommanderNames = []string{"Private commander"}
	for _, test := range []struct {
		section, code string
		index         int
		want          string
	}{
		{"sideboard", "card_unavailable", 0, "Private sideboard"}, {"commanders", "commander_missing", 0, "Private commander"},
	} {
		raw, _ := json.Marshal(StartFailure{Reason: "deck_rejected", Issues: []StartIssue{{1, test.section, test.index, test.code}}})
		got := ParseStartFailure(raw, request)
		if got == nil || got.Issues()[0].Card.Name != test.want {
			t.Fatal("section reference was not reconstructed")
		}
	}
}

func TestStartFailureRejectsUntrustedReferencesAndOversizedDetails(t *testing.T) {
	request := validStartRequest()
	for _, raw := range []string{
		`{}`, `null`, rejectedDeckJSON + `{}`, strings.Replace(rejectedDeckJSON, `"playerIndex":0`, `"playerIndex":8`, 1),
		strings.Replace(rejectedDeckJSON, `"playerIndex":0,`, ``, 1), strings.Replace(rejectedDeckJSON, `"cardIndex":0`, `"cardIndex":-1`, 1),
		strings.Replace(rejectedDeckJSON, `"cardIndex":0`, `"cardIndex":1`, 1), strings.Replace(rejectedDeckJSON, `"mainboard"`, `"library"`, 1),
		strings.Replace(rejectedDeckJSON, `"printing_unavailable"`, `"/private/token"`, 1),
		strings.Replace(rejectedDeckJSON, `"code":`, `"cardName":"forged identity","code":`, 1),
		strings.Replace(rejectedDeckJSON, `"deck_rejected"`, `"runtime_failed"`, 1),
		`{"reason":"runtime_failed","truncated":true}`, strings.Repeat(" ", 16<<10) + rejectedDeckJSON,
	} {
		if ParseStartFailure(json.RawMessage(raw), request) != nil {
			t.Fatal("invalid runtime detail accepted")
		}
	}
	value := StartFailure{Reason: "deck_rejected", Truncated: true}
	for range MaxStartIssues {
		value.Issues = append(value.Issues, StartIssue{0, "mainboard", 0, "printing_unavailable"})
	}
	raw, _ := json.Marshal(value)
	if got := ParseStartFailure(raw, request); got == nil || !got.Truncated() {
		t.Fatal("bounded truncated details rejected")
	}
	value.Issues = append(value.Issues, value.Issues[0])
	raw, _ = json.Marshal(value)
	if ParseStartFailure(raw, request) != nil {
		t.Fatal("oversized issue list accepted")
	}
	for _, reason := range []string{"runtime_unavailable", "runtime_timeout", "runtime_failed", "start_rejected"} {
		raw, _ := json.Marshal(StartFailure{Reason: reason})
		got := ParseStartFailure(raw, request)
		if got == nil || got.Reason() != reason || len(got.Issues()) != 0 {
			t.Fatal("safe reason rejected")
		}
	}
}

func TestClientCarriesValidatedDeckFailureAndOldRuntimeFallback(t *testing.T) {
	for _, mode := range []string{"deck-rejected", "deck-rejected-malformed", "start-rejected"} {
		t.Run(mode, func(t *testing.T) {
			client := newHelperClient(t, mode)
			defer client.Close()
			_, err := client.StartGame(t.Context(), validStartRequest())
			if !errors.Is(err, ErrStartRejected) || strings.Contains(err.Error(), "private") {
				t.Fatalf("unsafe start failure: %v", err)
			}
			var detail *StartError
			if errors.As(err, &detail) != (mode == "deck-rejected") {
				t.Fatal("runtime compatibility or detail validation failed")
			}
			if !client.Healthy() {
				t.Fatal("recoverable registration rejection invalidated process")
			}
		})
	}
}

func TestSharedClientDeckFailurePreservesOtherGame(t *testing.T) {
	pool := testSharedPool(t)
	neighbor := poolGame(t, pool, "neighbor")
	client, err := pool.Acquire(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	request := validStartRequest()
	request.GameID = "deck-rejected"
	_, err = client.StartGame(t.Context(), request)
	var detail *StartError
	if !errors.As(err, &detail) || detail.Issues()[0].Card.Name != "Forest" {
		t.Fatal("shared worker lost registration details")
	}
	if err := client.Close(); err != nil {
		t.Fatal(err)
	}
	if !neighbor.Healthy() {
		t.Fatal("registration failure killed a shared neighbor")
	}
	if _, err := neighbor.Snapshot(context.Background(), "neighbor", 0); err != nil {
		t.Fatal(err)
	}
}

func TestClientValidationKeepsDeckSizeFailuresActionable(t *testing.T) {
	client := newHelperClient(t, "normal")
	defer client.Close()
	for _, section := range []string{"mainboard", "sideboard"} {
		request := validStartRequest()
		if section == "mainboard" {
			request.Players[1].Deck = nil
		} else {
			request.Players[1].Sideboard = make([]CardIdentity, maxCardsPerPlayer+1)
		}
		_, err := client.StartGame(t.Context(), request)
		var detail *StartError
		if !errors.As(err, &detail) || detail.Reason() != "deck_rejected" || len(detail.Issues()) != 1 ||
			detail.Issues()[0].Section != section || detail.Issues()[0].PlayerIndex != 1 || detail.Issues()[0].Card.Name != "" {
			t.Fatal("early size validation lost the private deck issue")
		}
	}
	if !client.Healthy() {
		t.Fatal("local validation touched runtime health")
	}
}
