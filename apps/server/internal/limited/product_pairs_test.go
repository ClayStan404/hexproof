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
	data, err := os.ReadFile("../../../../testdata/protocol/v1/tournament-create-paired-product.json")
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

// Run against the actual freshly built FRA recipe as well as the small wire fixture.
func TestBuiltFRAProduct(t *testing.T) {
	path := os.Getenv("HEXPROOF_FRA_PRODUCT")
	if path == "" {
		t.Skip("set HEXPROOF_FRA_PRODUCT to validate a built catalog recipe")
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
		seen := map[string]bool{}
		for _, c := range pack {
			key := c.SetCode + "/" + c.CollectorNumber + "/" + c.Finish
			if seen[key] {
				t.Fatal("duplicate printing", key)
			}
			seen[key] = true
			if c.SetCode == "SPG" {
				guests++
			}
		}
		offset := 9
		if pack[len(pack)-1].SetCode == "SPG" {
			offset = 8
		}
		first := pack[offset]
		partner := pairedCard(protocol.LimitedCardDefinition{SetCode: first.SetCode, CollectorNumber: first.CollectorNumber, Finish: first.Finish, PairCollectorNumber: pack[offset+1].CollectorNumber}, p.sheets["echo-pair"].Cards)
		if partner.PairCollectorNumber != first.CollectorNumber {
			t.Fatal("FRA pair not reciprocal")
		}
	}
	if guests < 65 || guests > 135 {
		t.Fatalf("unexpected SPG frequency: %d/5500", guests)
	}
}
