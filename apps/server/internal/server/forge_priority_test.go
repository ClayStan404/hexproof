// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"testing"

	"hexproof/server/internal/rulesengine/forge"
)

func TestPriorityProjectionScopesAutomaticPassHint(t *testing.T) {
	for _, test := range []struct {
		kind                    string
		supported, hint, result bool
	}{
		{"chooseAction", true, true, true},
		{"chooseAction", true, false, false},
		{"chooseAction", false, true, false},
		{"chooseBoolean", true, true, false},
		{"payManaCost", true, true, false},
	} {
		prompt, err := projectedRulesPrompt("ROOM", "game-1", forge.PromptView{
			PromptID: 1, Kind: test.kind, Supported: test.supported, AutoPassEligible: test.hint,
		}, forgeRoomGame{}, nil)
		if err != nil || prompt.AutoPassEligible != test.result {
			t.Fatalf("projection for %+v = %+v, %v", test, prompt, err)
		}
	}
	if emptyRulesPrompt("ROOM", "game-1").AutoPassEligible {
		t.Fatal("Cleared prompt retained automatic pass eligibility")
	}
}
