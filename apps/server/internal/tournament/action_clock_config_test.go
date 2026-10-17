// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package tournament

import (
	"testing"

	"hexproof/server/internal/protocol"
)

func TestActionClockConfigurationDefaultsAndOverrides(t *testing.T) {
	on, off := true, false
	for _, test := range []struct {
		name      string
		eventType string
		mode      string
		clock     *bool
		want      bool
		invalid   bool
	}{
		{"manual default", protocol.LimitedEventConstructed, protocol.RulesModeManual, nil, false, false},
		{"constructed compatibility", protocol.LimitedEventConstructed, protocol.RulesModeForge, nil, true, false},
		{"constructed disabled", protocol.LimitedEventConstructed, protocol.RulesModeForge, &off, false, false},
		{"constructed enabled", protocol.LimitedEventConstructed, protocol.RulesModeForge, &on, true, false},
		{"manual rejected", protocol.LimitedEventConstructed, protocol.RulesModeManual, &on, false, true},
		{"sealed default", protocol.LimitedEventSetSealed, protocol.RulesModeForge, nil, false, false},
		{"sealed enabled", protocol.LimitedEventSetSealed, protocol.RulesModeForge, &on, true, false},
		{"draft enabled", protocol.LimitedEventSetDraft, protocol.RulesModeForge, &on, true, false},
		{"cube default", protocol.LimitedEventCubeDraft, protocol.RulesModeForge, nil, false, false},
		{"cube enabled", protocol.LimitedEventCubeDraft, protocol.RulesModeForge, &on, true, false},
		{"commander rejected", protocol.LimitedEventCommanderCube, protocol.RulesModeManual, &on, false, true},
	} {
		t.Run(test.name, func(t *testing.T) {
			product := tournamentLimitedProduct()
			capacity := 4
			coordinator := protocol.LimitedCoordinatorSwiss
			if test.eventType == protocol.LimitedEventCubeDraft {
				product.ProductType, product.Authentic = "cube", false
				product.CardsPerPack, product.Variants = 0, nil
				capacity = 2
				coordinator = protocol.LimitedCoordinatorCasual
				for index := range product.Sheets[0].Cards {
					product.Sheets[0].Cards[index].Weight = 2
				}
			}
			if test.eventType == protocol.LimitedEventCommanderCube {
				coordinator = protocol.LimitedCoordinatorCasual
			}
			event, err := New("CLOCK", Config{
				Name: "Clock choices", Format: "Modern", EventType: test.eventType,
				Coordinator: coordinator, MatchMode: protocol.MatchBO3, RulesMode: test.mode,
				ActionClockEnabled: test.clock, MaxPlayers: capacity, Product: &product,
			}, "Judge", "owner", CredentialHash("token"), testNow)
			if test.invalid {
				if ErrorCode(err) != ErrInvalid {
					t.Fatalf("unsupported action clock accepted: %v", err)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if event.ActionClockEnabled != test.want {
				t.Fatalf("action clock = %v, want %v", event.ActionClockEnabled, test.want)
			}
		})
	}
}
