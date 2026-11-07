// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import (
	"encoding/json"
	"math/rand"
	"os"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestBuiltTRKProduct(t *testing.T) {
	path := os.Getenv("HEXPROOF_TRK_PRODUCT")
	if path == "" {
		path = "../../../../testdata/limited/trk-estimated-product.json"
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var definition protocol.LimitedProductDefinition
	if err := json.Unmarshal(data, &definition); err != nil {
		t.Fatal(err)
	}
	if definition.ID != "hexproof-trk-play" || definition.ProductType != "approximate" || definition.Authentic || definition.CardsPerPack != 14 {
		t.Fatal("maintained recipe must retain its estimated identity")
	}
	product, err := NewProduct(definition)
	if err != nil {
		t.Fatal(err)
	}
	rng := rand.New(rand.NewSource(20261108))
	// Reach every uncommon treatment/common replacement combination directly.
	for _, variant := range definition.Variants {
		product.Definition.Variants = []protocol.LimitedPackVariantDefinition{variant}
		pack, err := product.generatePack(rng, func() string { return "test" })
		if err != nil || len(pack) != 14 {
			t.Fatalf("invalid TRK variant: %d cards, %v", len(pack), err)
		}
		offset := 0
		for _, slot := range variant.Slots {
			seen := map[string]bool{}
			for _, card := range pack[offset : offset+slot.Count] {
				found := false
				for _, candidate := range product.sheets[slot.Sheet].Cards {
					if card.SetCode == candidate.SetCode && card.CollectorNumber == candidate.CollectorNumber && card.Finish == candidate.Finish {
						found = true
					}
				}
				key := card.SetCode + "/" + card.CollectorNumber + "/" + card.Finish
				if !found || seen[key] || card.TypeLine == "" {
					t.Fatalf("invalid draw from %s: %s", slot.Sheet, key)
				}
				seen[key] = true
			}
			offset += slot.Count
		}
		if offset != 14 {
			t.Fatal("slot count does not conserve the pack")
		}
	}
	product.Definition.Variants = definition.Variants
	stardates := 0
	for i := 0; i < 5000; i++ {
		pack, err := product.generatePack(rng, func() string { return "test" })
		if err != nil || len(pack) != 14 {
			t.Fatalf("TRK pack generation: %d cards, %v", len(pack), err)
		}
		bonus, foils := 0, 0
		seen := map[string]bool{}
		for _, card := range pack {
			key := card.SetCode + "/" + card.CollectorNumber + "/" + card.Finish
			if seen[key] {
				t.Fatal("printing repeated across TRK pack slots", key)
			}
			seen[key] = true
			if card.SetCode != "TRK" && card.SetCode != "SDS" {
				t.Fatalf("unexpected set in Play booster: %s", card.SetCode)
			}
			if card.SetCode == "SDS" {
				bonus++
				if card.Finish != "nonfoil" {
					t.Fatal("foil Stardates is Collector-only")
				}
			}
			if card.Finish == "foil" {
				foils++
			}
		}
		if bonus > 1 || foils < 1 {
			t.Fatal("missing guaranteed foil or too many bonus replacements")
		}
		stardates += bonus
	}
	if stardates < 150 || stardates > 250 {
		t.Fatalf("unexpected 1-in-25 Stardates frequency: %d/5000", stardates)
	}
	for _, kind := range []string{protocol.LimitedEventSetSealed, protocol.LimitedEventSetDraft} {
		t.Run(kind, func(t *testing.T) {
			event, err := New(Config{TournamentID: "trk-test", EventType: kind, Product: definition, Participants: testParticipants(8)}, 20261108)
			if err != nil {
				t.Fatal(err)
			}
			for step := 0; event.Stage == protocol.LimitedStageDraft && step < 500; step++ {
				for _, player := range event.Players {
					if len(player.Inbox) > 0 && len(player.Inbox[0].Cards) > 0 {
						if _, err := event.Pick(player.ID, player.Inbox[0].Cards[0].ID); err != nil {
							t.Fatal(err)
						}
					}
				}
			}
			if event.Stage != protocol.LimitedStageDeckBuilding {
				t.Fatal("TRK event did not reach deck building")
			}
			expected := 84
			if kind == protocol.LimitedEventSetDraft {
				expected = 42
			}
			identities := map[string]bool{}
			for _, player := range event.Players {
				if len(player.Pool) != expected || len(event.Snapshot(player.ID).Pool) != expected {
					t.Fatalf("wrong private pool size: %d", len(player.Pool))
				}
				for _, card := range player.Pool {
					if card.ID == "" || identities[card.ID] {
						t.Fatal("physical card repeated between players")
					}
					identities[card.ID] = true
				}
			}
			spectator := event.Snapshot("")
			if len(spectator.Pool) != 0 || len(spectator.CurrentPack) != 0 {
				t.Fatal("spectator received private cards")
			}
		})
	}
}
