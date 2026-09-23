// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package tournament

import (
	"testing"

	"hexproof/server/internal/protocol"
)

func TestRulesModeDefaultsAndSupportedEvents(t *testing.T) {
	for _, eventType := range []string{protocol.LimitedEventConstructed,
		protocol.LimitedEventSetSealed, protocol.LimitedEventSetDraft, protocol.LimitedEventCubeDraft} {
		for _, mode := range []string{"", protocol.RulesModeManual, protocol.RulesModeForge, "unknown"} {
			t.Run(eventType+"/"+mode, func(t *testing.T) {
				product := tournamentLimitedProduct()
				capacity := 4
				if eventType == protocol.LimitedEventCubeDraft {
					product.ProductType, product.Authentic = "cube", false
					product.CardsPerPack, product.Variants = 0, nil
					capacity = 2
					for i := range product.Sheets[0].Cards {
						product.Sheets[0].Cards[i].Weight = 2
					}
				}
				event, err := New("RULES", Config{
					Name: "Rules event", Format: "Modern", EventType: eventType,
					MatchMode: protocol.MatchBO3, RulesMode: mode, MaxPlayers: capacity, Product: &product,
				}, "Judge", "owner", CredentialHash("token"), testNow)
				if mode == "unknown" {
					if ErrorCode(err) != ErrInvalid {
						t.Fatalf("invalid mode accepted: %v", err)
					}
					return
				}
				if err != nil {
					t.Fatal(err)
				}
				want := mode
				if want == "" {
					want = protocol.RulesModeManual
				}
				if event.RulesMode != want {
					t.Fatalf("mode = %q, want %q", event.RulesMode, want)
				}
			})
		}
	}
	for _, format := range []string{"Standard", "Pioneer", "Modern", "Legacy", "Vintage", "Pauper", "Duel Commander", "edh", "custom"} {
		_, err := New("FORMAT", Config{Name: "Format", Format: format,
			RulesMode: protocol.RulesModeForge, MatchMode: protocol.MatchBO1},
			"Judge", "owner", CredentialHash("token"), testNow)
		if (err == nil) != (format != "edh" && format != "custom") {
			t.Fatalf("Forge format %s: %v", format, err)
		}
	}
	_, err := New("COMMANDER", Config{Name: "Cube", Format: "edh",
		EventType: protocol.LimitedEventCommanderCube, Coordinator: protocol.LimitedCoordinatorCasual,
		RulesMode: protocol.RulesModeForge, MatchMode: protocol.MatchBO1},
		"Judge", "owner", CredentialHash("token"), testNow)
	if ErrorCode(err) != ErrInvalid {
		t.Fatalf("multiplayer Forge Cube accepted: %v", err)
	}
}
