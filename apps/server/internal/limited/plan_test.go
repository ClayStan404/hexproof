// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import (
	"encoding/json"
	"fmt"
	"math"
	"math/rand"
	"os"
	"reflect"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
)

func planProduct(set string, size int) protocol.LimitedProductDefinition {
	p := testProduct(size, 60)
	p.ID, p.SetCode, p.Name = set+"-draft", set, set+" Draft Booster"
	for i := range p.Sheets[0].Cards {
		p.Sheets[0].Cards[i].SetCode = set
	}
	return p
}

func planDefinition(entries ...protocol.LimitedPackPlanEntry) *protocol.LimitedPackPlanDefinition {
	return &protocol.LimitedPackPlanDefinition{Products: []protocol.LimitedProductDefinition{
		planProduct("AAA", 14), planProduct("BBB", 15), planProduct("CCC", 14)}, Entries: entries}
}

func TestMixedSealedCanonicalGroupsConservationAndPrivacy(t *testing.T) {
	definition := planDefinition(protocol.LimitedPackPlanEntry{ProductID: "AAA-draft", Count: 1},
		protocol.LimitedPackPlanEntry{ProductID: "BBB-draft", Count: 2},
		protocol.LimitedPackPlanEntry{ProductID: "AAA-draft", Count: 1},
		protocol.LimitedPackPlanEntry{ProductID: "CCC-draft", Count: 2})
	plan, err := NewPackPlan(protocol.LimitedEventSetSealed, nil, definition)
	if err != nil {
		t.Fatal(err)
	}
	wantEntries := []protocol.LimitedPackPlanEntry{{ProductID: "AAA-draft", Count: 2}, {ProductID: "BBB-draft", Count: 2}, {ProductID: "CCC-draft", Count: 2}}
	if !reflect.DeepEqual(plan.View().Entries, wantEntries) {
		t.Fatal(plan.View())
	}
	definition.Products[0].Sheets[0].Cards[0].Name = "caller mutation"
	definition.Entries[0].Count = 12
	copy := plan.View()
	copy.Entries[0].Count = 99
	copy.Products[0].Name = "mutated view"
	if !reflect.DeepEqual(plan.View().Entries, wantEntries) || plan.View().Products[0].Name == "mutated view" {
		t.Fatal("plan aliases caller memory")
	}
	event, err := New(Config{TournamentID: "mixed", EventType: protocol.LimitedEventSetSealed, Plan: plan, Participants: testParticipants(64)}, 7)
	if err != nil {
		t.Fatal(err)
	}
	seen := map[string]bool{}
	packIDs := map[string]bool{}
	for _, player := range event.Players {
		view := event.Snapshot(player.ID)
		if len(view.Pool) != 86 || len(view.ReceivedPacks) != 6 {
			t.Fatalf("pool/groups: %d/%d", len(view.Pool), len(view.ReceivedPacks))
		}
		pool := map[string]protocol.LimitedCardView{}
		for _, card := range view.Pool {
			if seen[card.InstanceID] {
				t.Fatal("duplicate physical instance")
			}
			seen[card.InstanceID] = true
			pool[card.InstanceID] = card
		}
		grouped := map[string]bool{}
		for index, pack := range view.ReceivedPacks {
			if packIDs[pack.PackID] {
				t.Fatal("duplicate pack identity")
			}
			packIDs[pack.PackID] = true
			want := wantEntries[index/2].ProductID
			if pack.ProductID != want {
				t.Fatalf("pack %d product %s", index, pack.ProductID)
			}
			for _, id := range pack.InstanceIDs {
				if grouped[id] || pool[id].InstanceID == "" {
					t.Fatal("pack grouping is not a pool partition")
				}
				grouped[id] = true
			}
		}
		if len(grouped) != len(pool) {
			t.Fatal("ungrouped pool cards")
		}
	}
	viewer := event.Snapshot("")
	if len(viewer.Pool)+len(viewer.CurrentPacks)+len(viewer.ReceivedPacks) != 0 || viewer.Plan.PlanHash == "" {
		t.Fatal("public projection privacy/composition")
	}
}

func TestMixedDraftOrderedVariableRoundsAndFinalConfirmation(t *testing.T) {
	for _, seats := range []int{2, 8} {
		t.Run(fmt.Sprint(seats), func(t *testing.T) {
			d := planDefinition(protocol.LimitedPackPlanEntry{ProductID: "AAA-draft", Count: 1}, protocol.LimitedPackPlanEntry{ProductID: "BBB-draft", Count: 1}, protocol.LimitedPackPlanEntry{ProductID: "AAA-draft", Count: 1})
			d.Products = d.Products[:2]
			plan, err := NewPackPlan(protocol.LimitedEventSetDraft, nil, d)
			if err != nil {
				t.Fatal(err)
			}
			e, err := New(Config{TournamentID: "draft", EventType: protocol.LimitedEventSetDraft, Plan: plan, Participants: testParticipants(seats)}, 29)
			if err != nil {
				t.Fatal(err)
			}
			for step := 0; e.Stage == protocol.LimitedStageDraft && step < 1000; step++ {
				round := e.packRound
				wantProduct, wantSize, wantDirection := "AAA-draft", 14, 1
				if round == 2 {
					wantProduct, wantSize, wantDirection = "BBB-draft", 15, -1
				}
				if e.Product.Definition.ID != wantProduct || e.Direction() != wantDirection {
					t.Fatalf("round %d product/direction", round)
				}
				if step == 0 && len(e.futurePacks) != 3 {
					t.Fatal("future rounds were not pre-generated")
				}
				for _, p := range e.Players {
					if e.packRound != round {
						break
					}
					v := e.Snapshot(p.ID)
					if len(v.CurrentPacks) == 0 {
						continue
					}
					pack := v.CurrentPacks[0]
					if pack.ProductID != wantProduct || len(pack.Cards) > wantSize || len(pack.Cards) == 0 {
						t.Fatal("wrong held product/pack size")
					}
					id := pack.Cards[0].InstanceID
					before := len(p.Pool)
					if _, err := e.Pick(p.ID, id); err != nil {
						t.Fatal(err)
					}
					if len(p.Pool) != before+1 {
						t.Fatal("pick did not move exactly one card")
					}
					if _, err := e.Pick(p.ID, id); err == nil {
						t.Fatal("repeated physical pick accepted")
					}
				}
			}
			seen := map[string]bool{}
			if e.Stage != protocol.LimitedStageDeckBuilding {
				t.Fatal("draft did not finish")
			}
			for _, p := range e.Players {
				if len(p.Pool) != 43 {
					t.Fatalf("picked %d", len(p.Pool))
				}
				for _, c := range p.Pool {
					if seen[c.ID] {
						t.Fatal("duplicate physical card")
					}
					seen[c.ID] = true
				}
			}
			if len(seen) != seats*43 {
				t.Fatal("cards lost")
			}
		})
	}
}

func TestPackPlanBoundsConflictsAndHash(t *testing.T) {
	base := planProduct("AAA", 30)
	for _, total := range []int{1, 12} {
		d := &protocol.LimitedPackPlanDefinition{Products: []protocol.LimitedProductDefinition{base}, Entries: []protocol.LimitedPackPlanEntry{{ProductID: base.ID, Count: total}}}
		p, err := NewPackPlan(protocol.LimitedEventSetSealed, nil, d)
		if err != nil || p.View().CardsPerPlayer != total*30 {
			t.Fatal(p, err)
		}
	}
	for _, count := range []int{0, -1, 13, math.MaxInt} {
		if _, err := NewPackPlan(protocol.LimitedEventSetSealed, nil, &protocol.LimitedPackPlanDefinition{Products: []protocol.LimitedProductDefinition{base}, Entries: []protocol.LimitedPackPlanEntry{{ProductID: base.ID, Count: count}}}); err == nil {
			t.Fatalf("count %d accepted", count)
		}
	}
	valid := func() *protocol.LimitedPackPlanDefinition {
		return &protocol.LimitedPackPlanDefinition{Products: []protocol.LimitedProductDefinition{base}, Entries: []protocol.LimitedPackPlanEntry{{ProductID: base.ID, Count: 6}}}
	}
	for name, edit := range map[string]func(*protocol.LimitedPackPlanDefinition){
		"unknown":   func(d *protocol.LimitedPackPlanDefinition) { d.Entries[0].ProductID = "missing" },
		"unused":    func(d *protocol.LimitedPackPlanDefinition) { d.Products = append(d.Products, planProduct("BBB", 14)) },
		"duplicate": func(d *protocol.LimitedPackPlanDefinition) { d.Products = append(d.Products, base) },
		"set conflict": func(d *protocol.LimitedPackPlanDefinition) {
			p := cloneProduct(base)
			p.ID = "other"
			d.Products = append(d.Products, p)
		},
		"cube":  func(d *protocol.LimitedPackPlanDefinition) { d.Products[0].ProductType = ProductTypeCube },
		"empty": func(d *protocol.LimitedPackPlanDefinition) { d.Entries = nil },
	} {
		t.Run(name, func(t *testing.T) {
			d := valid()
			edit(d)
			if _, err := NewPackPlan(protocol.LimitedEventSetSealed, nil, d); err == nil {
				t.Fatal("invalid plan accepted")
			}
		})
	}
	if _, err := NewPackPlan(protocol.LimitedEventSetSealed, &base, valid()); err == nil {
		t.Fatal("product+plan accepted")
	}
	if _, err := NewPackPlan(protocol.LimitedEventSetDraft, nil, valid()); err == nil {
		t.Fatal("invalid draft rounds accepted")
	}
	// Definition table order is not semantic; Sealed entry first appearance is.
	d := planDefinition(protocol.LimitedPackPlanEntry{ProductID: "AAA-draft", Count: 2}, protocol.LimitedPackPlanEntry{ProductID: "BBB-draft", Count: 2}, protocol.LimitedPackPlanEntry{ProductID: "CCC-draft", Count: 2})
	p, _ := NewPackPlan(protocol.LimitedEventSetSealed, nil, d)
	d.Products[0], d.Products[2] = d.Products[2], d.Products[0]
	q, _ := NewPackPlan(protocol.LimitedEventSetSealed, nil, d)
	if p.View().PlanHash != q.View().PlanHash {
		t.Fatal("dictionary order changes identity")
	}
	d.Entries[0], d.Entries[2] = d.Entries[2], d.Entries[0]
	r, _ := NewPackPlan(protocol.LimitedEventSetSealed, nil, d)
	if p.View().PlanHash == r.View().PlanHash {
		t.Fatal("pack order missing from identity")
	}
}

func TestLegacyGenerationSequenceAndDeterminism(t *testing.T) {
	for _, mode := range []string{protocol.LimitedEventSetSealed, protocol.LimitedEventSetDraft} {
		p := testProduct(15, 60)
		e, err := New(Config{TournamentID: "legacy", EventType: mode, Product: p, Participants: testParticipants(2)}, 31)
		if err != nil {
			t.Fatal(err)
		}
		product, _ := NewProduct(p)
		rng := rand.New(rand.NewSource(31))
		seq := 0
		packCount := 12
		if mode == protocol.LimitedEventSetDraft {
			packCount = 6
		}
		var expected []*CardInstance
		for i := 0; i < packCount; i++ {
			cards, err := product.generatePack(rng, func() string { seq++; return "limited-" + itoa(seq) })
			if err != nil {
				t.Fatal(err)
			}
			expected = append(expected, cards...)
		}
		var actual []*CardInstance
		if mode == protocol.LimitedEventSetSealed {
			for _, p := range e.Players {
				actual = append(actual, p.Pool...)
			}
		} else {
			for round := 0; round < 3; round++ {
				for seat, p := range e.Players {
					pack := e.futurePacks[round]
					if round == 0 {
						actual = append(actual, p.Inbox[0].Cards...)
					} else {
						actual = append(actual, pack[seat].Cards...)
					}
				}
			}
		}
		if !reflect.DeepEqual(actual, expected) {
			t.Fatalf("legacy %s random traversal changed", mode)
		}
		again, _ := New(Config{TournamentID: "legacy", EventType: mode, Product: p, Participants: testParticipants(2)}, 31)
		if !reflect.DeepEqual(e.Snapshot("p-1"), again.Snapshot("p-1")) {
			t.Fatal("fixed seed unstable")
		}
		other, _ := New(Config{TournamentID: "legacy", EventType: mode, Product: p, Participants: testParticipants(2)}, 32)
		if reflect.DeepEqual(e.Snapshot("p-1"), other.Snapshot("p-1")) {
			t.Fatal("seed has no effect")
		}
	}
}

func TestMaximumSealedProjectionBudget(t *testing.T) {
	p := planProduct("MAX", 30)
	// Exercise the maximum allowed wire text as well as the physical count.
	for i := range p.Sheets[0].Cards {
		c := &p.Sheets[0].Cards[i]
		c.Name = strings.Repeat("界", protocol.MaxCardNameRunes)
		c.TypeLine = strings.Repeat("类", protocol.MaxTypeLineRunes)
		c.CollectorNumber = strings.Repeat("号", 30) + fmt.Sprintf("%02d", i)
		c.SetCode = strings.Repeat("集", protocol.MaxSetCodeRunes)
		c.Rarity = strings.Repeat("稀", 32)
		c.Finish = strings.Repeat("面", 32)
	}
	plan, err := NewPackPlan(protocol.LimitedEventSetSealed, nil, &protocol.LimitedPackPlanDefinition{Products: []protocol.LimitedProductDefinition{p}, Entries: []protocol.LimitedPackPlanEntry{{ProductID: p.ID, Count: 12}}})
	if err != nil {
		t.Fatal(err)
	}
	participants := testParticipants(64)
	for i := range participants {
		participants[i].DisplayName = strings.Repeat("名", protocol.MaxDisplayNameRunes)
	}
	start := time.Now()
	e, err := New(Config{TournamentID: "budget", EventType: protocol.LimitedEventSetSealed, Plan: plan, Participants: participants}, 91)
	if err != nil {
		t.Fatal(err)
	}
	generation := time.Since(start)
	start = time.Now()
	maximum, fanout := 0, 0
	for _, player := range e.Players {
		env, _ := protocol.NewEnvelope(protocol.TypeLimitedSnapshot, e.Snapshot(player.ID))
		b, _ := json.Marshal(env)
		maximum = max(maximum, len(b))
		fanout += len(b)
	}
	public, _ := json.Marshal(e.Snapshot(""))
	fanout += 9 * len(public)
	if maximum > 1024*1024 {
		t.Fatalf("owner message %d exceeds default inbound client's matching limit", maximum)
	}
	t.Logf("768 packs / 23040 instances; generation=%s; max owner envelope=%d bytes; public=%d bytes; 64 owners + organizer/8 viewers fanout=%d bytes; projection encode=%s", generation, maximum, len(public), fanout, time.Since(start))
}

func TestCombinedProductBudgetsBeforeExpansion(t *testing.T) {
	for _, kind := range []string{"pool", "sheet", "bytes"} {
		t.Run(kind, func(t *testing.T) {
			a, b := planProduct("AAA", 14), planProduct("BBB", 15)
			if kind == "pool" {
				a.CardPool = make([]protocol.LimitedCardDefinition, 5001)
				b.CardPool = make([]protocol.LimitedCardDefinition, 5000)
			}
			if kind == "sheet" {
				a.Sheets[0].Cards = make([]protocol.LimitedCardDefinition, 5001)
				b.Sheets[0].Cards = make([]protocol.LimitedCardDefinition, 5000)
			}
			if kind == "bytes" {
				a.Name = strings.Repeat("x", 800*1024)
			}
			_, err := NewPackPlan(protocol.LimitedEventSetSealed, nil, &protocol.LimitedPackPlanDefinition{Products: []protocol.LimitedProductDefinition{a, b}, Entries: []protocol.LimitedPackPlanEntry{{ProductID: a.ID, Count: 1}, {ProductID: b.ID, Count: 1}}})
			if err == nil || !strings.Contains(err.Error(), "combined products too large") {
				t.Fatalf("combined budget not checked before expansion: %v", err)
			}
		})
	}
}

// The normal suite measures checked-in upstream products. A qualification run
// can additionally supply extracted installed definitions without committing a
// full card database or coupling tests to a developer's catalog installation.
func TestCatalogMixedPlanBudgets(t *testing.T) {
	var products []protocol.LimitedProductDefinition
	if path := os.Getenv("HEXPROOF_TEST_LIMITED_PRODUCTS"); path != "" {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		if err = json.Unmarshal(raw, &products); err != nil {
			t.Fatal(err)
		}
	} else {
		for _, name := range []string{"trk-estimated-product.json", "fra-upstream-product.json"} {
			raw, err := os.ReadFile("../../../../testdata/limited/" + name)
			if err != nil {
				t.Fatal(err)
			}
			var p protocol.LimitedProductDefinition
			if err = json.Unmarshal(raw, &p); err != nil {
				t.Fatal(err)
			}
			products = append(products, p)
		}
	}
	byID := map[string]protocol.LimitedProductDefinition{}
	for _, p := range products {
		byID[p.ID] = p
	}
	groups := [][]string{}
	if byID["mtgjson-nph-draft"].ID != "" {
		groups = append(groups, []string{"mtgjson-nph-draft", "mtgjson-mbs-draft", "mtgjson-som-draft"}, []string{"hexproof-trk-play", "mtgjson-som-draft", "hexproof-trk-play"})
	} else {
		groups = append(groups, []string{products[0].ID, products[1].ID, products[0].ID})
	}
	for _, ids := range groups {
		for _, mode := range []string{protocol.LimitedEventSetSealed, protocol.LimitedEventSetDraft} {
			d := &protocol.LimitedPackPlanDefinition{}
			used := map[string]bool{}
			for _, id := range ids {
				p := byID[id]
				if p.ID == "" {
					t.Fatalf("catalog product missing: %s", id)
				}
				if !used[id] {
					d.Products = append(d.Products, p)
					used[id] = true
				}
				count := 1
				if mode == protocol.LimitedEventSetSealed {
					count = 2
				}
				d.Entries = append(d.Entries, protocol.LimitedPackPlanEntry{ProductID: id, Count: count})
			}
			start := time.Now()
			plan, err := NewPackPlan(mode, nil, d)
			if err != nil {
				t.Fatal(ids, err)
			}
			seats := 8
			if mode == protocol.LimitedEventSetSealed {
				seats = 64
			}
			e, err := New(Config{TournamentID: "catalog-budget", EventType: mode, Plan: plan, Participants: testParticipants(seats)}, 101)
			if err != nil {
				t.Fatal(err)
			}
			envelope, _ := protocol.NewEnvelope(protocol.TypeTournamentCreate, protocol.TournamentCreate{Name: "Budget", Format: "Limited", EventType: mode, OperationID: "budget", Plan: d, MaxPlayers: seats, MatchMode: protocol.MatchBO1})
			raw, _ := json.Marshal(envelope)
			owner, _ := json.Marshal(e.Snapshot("p-1"))
			public, _ := json.Marshal(e.Snapshot(""))
			if len(raw) > 1024*1024 {
				t.Fatal("combined plan broke default envelope limit")
			}
			t.Logf("catalog %v %s: create=%dB owner=%dB public=%dB seats=%d packs/player=%d cards/player=%d validation+generation=%s", ids, mode, len(raw), len(owner), len(public), seats, plan.View().PacksPerPlayer, plan.View().CardsPerPlayer, time.Since(start))
		}
	}
}
