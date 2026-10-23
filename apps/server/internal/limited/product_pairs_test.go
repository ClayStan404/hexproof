// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import (
	"encoding/json"
	"hexproof/server/internal/protocol"
	"math/rand"
	"os"
	"testing"
)

func pairedFixture(t *testing.T) protocol.LimitedProductDefinition {
	t.Helper()
	data, err := os.ReadFile("../../../../testdata/protocol/v2/tournament-create-paired-product.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		Payload protocol.TournamentCreate `json:"payload"`
	}
	if err := json.Unmarshal(data, &fixture); err != nil {
		t.Fatal(err)
	}
	return *fixture.Payload.Product
}

func TestPairedProduct(t *testing.T) {
	p, err := NewProduct(pairedFixture(t))
	if err != nil {
		t.Fatal(err)
	}
	rng := rand.New(rand.NewSource(17))
	for i := 0; i < 1000; i++ {
		pack, err := p.generatePack(rng, func() string { return "test" })
		if err != nil {
			t.Fatal(err)
		}
		if len(pack) != 3 {
			t.Fatal("wrong pack size")
		}
		a, b := pack[0].CollectorNumber, pack[1].CollectorNumber
		if !((a == "1" && b == "2") || (a == "2" && b == "1") || (a == "3" && b == "4") || (a == "4" && b == "3")) {
			t.Fatal("pair split", pack)
		}
		if pack[2].CollectorNumber == a || pack[2].CollectorNumber == b {
			t.Fatal("duplicate across sheets")
		}
	}
}

func TestRejectMalformedPairedProduct(t *testing.T) {
	cases := map[string]func(*protocol.LimitedProductDefinition){
		"missing partner": func(p *protocol.LimitedProductDefinition) { p.Sheets[0].Cards[0].PairCollectorNumber = "99" },
		"self pair":       func(p *protocol.LimitedProductDefinition) { p.Sheets[0].Cards[0].PairCollectorNumber = "1" },
		"nonreciprocal":   func(p *protocol.LimitedProductDefinition) { p.Sheets[0].Cards[1].PairCollectorNumber = "3" },
		"mixed sheet":     func(p *protocol.LimitedProductDefinition) { p.Sheets[0].Cards[0].PairCollectorNumber = "" },
		"unequal weights": func(p *protocol.LimitedProductDefinition) { p.Sheets[0].Cards[0].Weight = 2 },
		"unequal rarity":  func(p *protocol.LimitedProductDefinition) { p.Sheets[0].Cards[0].Rarity = "rare" },
		"duplicate identity": func(p *protocol.LimitedProductDefinition) {
			p.Sheets[0].Cards = append(p.Sheets[0].Cards, p.Sheets[0].Cards[0])
		},
		"wrong size":     func(p *protocol.LimitedProductDefinition) { p.CardsPerPack = 2 },
		"too many draws": func(p *protocol.LimitedProductDefinition) { p.Variants[0].Slots[0].Count = 3; p.CardsPerPack = 7 },
		"cube":           func(p *protocol.LimitedProductDefinition) { p.ProductType = "cube"; p.CardsPerPack = 0 },
	}
	for name, mutate := range cases {
		t.Run(name, func(t *testing.T) {
			p := pairedFixture(t)
			mutate(&p)
			if _, err := NewProduct(p); err == nil {
				t.Fatal("accepted invalid pair")
			}
		})
	}
}

func TestProductInheritsTypesWithoutExpandingDefinition(t *testing.T) {
	definition := pairedFixture(t)
	definition.Sheets[0].Cards[0].TypeLine = "Creature"
	card := definition.Sheets[0].Cards[0]
	card.PairCollectorNumber = ""
	card.Finish = "foil"
	card.TypeLine = ""
	definition.Sheets = append(definition.Sheets, protocol.LimitedSheetDefinition{
		Name: "foil-copy", Cards: []protocol.LimitedCardDefinition{card},
	})
	definition.CardsPerPack = 1
	definition.Variants = []protocol.LimitedPackVariantDefinition{{Weight: 1,
		Slots: []protocol.LimitedSlotDefinition{{Sheet: "foil-copy", Count: 1}},
	}}
	p, err := NewProduct(definition)
	if err != nil {
		t.Fatal(err)
	}
	pack, err := p.generatePack(rand.New(rand.NewSource(1)), func() string { return "test" })
	if err != nil || len(pack) != 1 || pack[0].TypeLine != "Creature" {
		t.Fatal("missing inherited type", err)
	}
	if p.Definition.Sheets[len(p.Definition.Sheets)-1].Cards[0].TypeLine != "" {
		t.Fatal("expanded locked definition")
	}
	definition.Sheets[len(definition.Sheets)-1].Cards[0].TypeLine = "Conflicting type"
	if _, err := NewProduct(definition); err == nil {
		t.Fatal("accepted conflicting printing types")
	}
}

// Run the pinned upstream FRA recipe by default; allow a fresh build override.
func TestBuiltFRAProduct(t *testing.T) {
	path := os.Getenv("HEXPROOF_FRA_PRODUCT")
	if path == "" {
		path = "../../../../testdata/limited/fra-upstream-product.json"
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var definition protocol.LimitedProductDefinition
	if err = json.Unmarshal(data, &definition); err != nil {
		t.Fatal(err)
	}
	p, err := NewProduct(definition)
	if err != nil {
		t.Fatal(err)
	}
	rng := rand.New(rand.NewSource(1909))
	// Exercise every conditional variant, including each fixed pair and its
	// third-card exclusion table, rather than relying on random coverage.
	for _, variant := range definition.Variants {
		p.Definition.Variants = []protocol.LimitedPackVariantDefinition{variant}
		pack, err := p.generatePack(rng, func() string { return "test" })
		if err != nil {
			t.Fatal(err)
		}
		offset := 0
		for _, slot := range variant.Slots {
			sheet := p.sheets[slot.Sheet]
			seen := map[string]bool{}
			for _, card := range pack[offset : offset+slot.Count] {
				found := false
				for _, candidate := range sheet.Cards {
					if card.SetCode == candidate.SetCode && card.CollectorNumber == candidate.CollectorNumber && card.Finish == candidate.Finish {
						found = true
					}
				}
				key := card.SetCode + "/" + card.CollectorNumber + "/" + card.Finish
				if !found || seen[key] {
					t.Fatalf("wrong conditional draw from %s: %s", slot.Sheet, key)
				}
				seen[key] = true
			}
			offset += slot.Count
		}
		if offset != 14 {
			t.Fatal("wrong FRA variant size")
		}
	}
	p.Definition.Variants = definition.Variants
	for _, kind := range []string{protocol.LimitedEventSetSealed, protocol.LimitedEventSetDraft} {
		event, err := New(Config{TournamentID: "fra-test", EventType: kind, Product: definition, Participants: testParticipants(8)}, 1909)
		if err != nil {
			t.Fatal(err)
		}
		if kind == protocol.LimitedEventSetDraft {
			for step := 0; event.Stage == protocol.LimitedStageDraft && step < 500; step++ {
				for _, player := range event.Players {
					if len(player.Inbox) > 0 && len(player.Inbox[0].Cards) > 0 {
						if _, err := event.Pick(player.ID, player.Inbox[0].Cards[0].ID); err != nil {
							t.Fatal(err)
						}
					}
				}
			}
		}
		if event.Stage != protocol.LimitedStageDeckBuilding {
			t.Fatal("FRA draft did not complete")
		}
		expected := 84
		if kind == protocol.LimitedEventSetDraft {
			expected = 42
		}
		for _, player := range event.Players {
			if len(player.Pool) != expected {
				t.Fatalf("FRA pool size: %d", len(player.Pool))
			}
		}
		spectator := event.Snapshot("")
		if len(spectator.Pool) != 0 || len(spectator.CurrentPack) != 0 {
			t.Fatal("spectator received private cards")
		}
	}

	guests := 0
	for i := 0; i < 5500; i++ {
		pack, err := p.generatePack(rng, func() string { return "test" })
		if err != nil {
			t.Fatal(err)
		}
		if len(pack) != 14 {
			t.Fatal("wrong FRA pack size")
		}
		for _, c := range pack {
			if c.TypeLine == "" {
				t.Fatal("missing inherited printing type")
			}
			if c.SetCode == "SPG" {
				guests++
			}
		}
	}
	if guests < 65 || guests > 135 {
		t.Fatalf("unexpected SPG frequency: %d/5500", guests)
	}
}

func TestPooledProductRejectsInvalidReferences(t *testing.T) {
	data, err := os.ReadFile("../../../../testdata/protocol/v2/tournament-create-card-pool.json")
	if err != nil {
		t.Fatal(err)
	}
	for name, mutate := range map[string]func(*protocol.LimitedProductDefinition){
		"valid":         func(p *protocol.LimitedProductDefinition) {},
		"zero index":    func(p *protocol.LimitedProductDefinition) { p.Sheets[0].CardRefs[0].CardIndex = 0 },
		"missing pool":  func(p *protocol.LimitedProductDefinition) { p.CardPool = nil },
		"past pool":     func(p *protocol.LimitedProductDefinition) { p.Sheets[0].CardRefs[0].CardIndex = len(p.CardPool) + 1 },
		"zero weight":   func(p *protocol.LimitedProductDefinition) { p.Sheets[0].CardRefs[0].Weight = 0 },
		"unsafe weight": func(p *protocol.LimitedProductDefinition) { p.Sheets[0].CardRefs[0].Weight = maxProductWeight + 1 },
		"mixed cards":   func(p *protocol.LimitedProductDefinition) { p.Sheets[0].Cards = p.CardPool[:1] },
		"pool weight":   func(p *protocol.LimitedProductDefinition) { p.CardPool[0].Weight = 2 },
		"too many entries": func(p *protocol.LimitedProductDefinition) {
			p.Sheets[0].CardRefs = make([]protocol.LimitedCardReference, protocol.MaxLimitedProductCards+1)
		},
	} {
		t.Run(name, func(t *testing.T) {
			var fixture struct {
				Payload protocol.TournamentCreate `json:"payload"`
			}
			if err := json.Unmarshal(data, &fixture); err != nil {
				t.Fatal(err)
			}
			definition := fixture.Payload.Product
			mutate(definition)
			product, err := NewProduct(*definition)
			if name != "valid" {
				if err == nil {
					t.Fatal("accepted invalid reference")
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			pack, err := product.generatePack(rand.New(rand.NewSource(1)), func() string { return "test" })
			if err != nil || len(pack) != 3 {
				t.Fatal("pooled paired generation", err)
			}
			if len(product.Definition.Sheets[0].Cards) != 0 {
				t.Fatal("expanded locked definition")
			}
			if (pack[0].CollectorNumber == pack[1].CollectorNumber) || pack[2].CollectorNumber == pack[0].CollectorNumber || pack[2].CollectorNumber == pack[1].CollectorNumber {
				t.Fatal("pooled pairing/exclusion failed")
			}
		})
	}
}
