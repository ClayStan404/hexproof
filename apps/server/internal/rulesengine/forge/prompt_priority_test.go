// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"encoding/json"
	"fmt"
	"testing"
)

func TestPriorityAutomaticPassRequiresExplicitNativeHint(t *testing.T) {
	for _, test := range []struct {
		name, field string
		eligible    bool
		invalid     bool
	}{
		{"old runtime", "", false, false},
		{"eligible", `,"autoPassEligible":true`, true, false},
		{"unavailable", `,"autoPassEligible":false`, false, false},
		{"unknown", `,"autoPassEligible":null`, false, false},
		{"malformed", `,"autoPassEligible":"true"`, false, true},
	} {
		t.Run(test.name, func(t *testing.T) {
			raw := json.RawMessage(fmt.Sprintf(`{"promptId":7,"decidingPlayerId":"player-0","input":{"type":"chooseAction","actions":[]%s}}`, test.field))
			view, err := NormalizePrompt(raw)
			if (err != nil) != test.invalid {
				t.Fatalf("NormalizePrompt error = %v, invalid = %v", err, test.invalid)
			}
			if err == nil && view.AutoPassEligible != test.eligible {
				t.Fatalf("AutoPassEligible = %v, want %v", view.AutoPassEligible, test.eligible)
			}
		})
	}
	raw := json.RawMessage(`{"promptId":7,"decidingPlayerId":"player-0","input":{"type":"mulligan","autoPassEligible":true}}`)
	view, err := NormalizePrompt(raw)
	if err != nil || view.AutoPassEligible {
		t.Fatalf("Non-priority hint was accepted: %+v, %v", view, err)
	}
}
