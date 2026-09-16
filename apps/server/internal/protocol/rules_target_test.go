// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

import (
	"encoding/json"
	"testing"
)

func TestRulesTargetSeatPreservesZeroAndLegacyAbsence(t *testing.T) {
	for _, tc := range []struct {
		name string
		wire string
		seat *int
	}{
		{name: "legacy player", wire: `{"responseId":"target:0","kind":"player","label":"Alex"}`},
		{name: "first seat", wire: `{"responseId":"target:0","kind":"player","label":"Alex","seat":0}`, seat: new(int)},
		{name: "card", wire: `{"responseId":"target:1","kind":"card","label":"Face-down card","objectId":"card-a"}`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var target RulesPromptTarget
			if err := json.Unmarshal([]byte(tc.wire), &target); err != nil {
				t.Fatal(err)
			}
			if (target.Seat == nil) != (tc.seat == nil) ||
				(target.Seat != nil && *target.Seat != *tc.seat) {
				t.Fatalf("seat = %v, want %v", target.Seat, tc.seat)
			}
			encoded, err := json.Marshal(target)
			if err != nil {
				t.Fatal(err)
			}
			var fields map[string]json.RawMessage
			if err := json.Unmarshal(encoded, &fields); err != nil {
				t.Fatal(err)
			}
			if _, present := fields["seat"]; present != (tc.seat != nil) {
				t.Fatalf("seat presence changed: %s", encoded)
			}
		})
	}
}
