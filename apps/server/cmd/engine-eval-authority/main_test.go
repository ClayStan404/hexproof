// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package main

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestAuthorityUsesProductionActorAndPromptValidation(t *testing.T) {
	// The pinned host represents land plays as type=cast, label=Play Plains.
	prompt := json.RawMessage(`{"promptId":4,"decidingPlayerId":"player-0","input":{"type":"chooseAction","actions":[{"type":"cast","id":"land-1","cardId":"card-1","label":"Play Plains","castOption":{"type":"normal"}}]}}`)
	for _, tc := range []struct {
		name     string
		actor    int
		id       int64
		label    string
		accepted bool
	}{
		{"owner", 0, 4, "Play Plains", true},
		{"wrong actor", 1, 4, "Play Plains", false},
		{"stale", 0, 3, "Play Plains", false},
		{"missing land", 0, 4, "Play Mountain", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := evaluate(request{Prompt: prompt, Actor: tc.actor, PromptID: tc.id, Label: tc.label})
			if got.Accepted != tc.accepted {
				t.Fatalf("response=%+v, expected accepted=%v", got, tc.accepted)
			}
			if tc.accepted && !strings.Contains(string(got.Response), "land-1") {
				t.Fatalf("accepted response lost the actual engine action: %s", got.Response)
			}
			if !tc.accepted && len(got.Response) != 0 {
				t.Fatal("rejected response must not contain a forwardable action")
			}
		})
	}
}
