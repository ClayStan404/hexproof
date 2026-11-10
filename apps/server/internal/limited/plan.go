// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"strings"

	"hexproof/server/internal/protocol"
)

const MaxPlanProducts = 12

// PackPlan is immutable after validation. Only summaries and copies leave it;
// installed catalog updates and caller-owned slices cannot change a live event.
type PackPlan struct {
	products map[string]*Product
	order    []*Product
	entries  []protocol.LimitedPackPlanEntry
	packs    []*Product
	view     protocol.LimitedPackPlanView
}

func cloneProduct(product protocol.LimitedProductDefinition) protocol.LimitedProductDefinition {
	product.CardPool = append([]protocol.LimitedCardDefinition(nil), product.CardPool...)
	product.Sheets = append([]protocol.LimitedSheetDefinition(nil), product.Sheets...)
	for i := range product.Sheets {
		product.Sheets[i].Cards = append([]protocol.LimitedCardDefinition(nil), product.Sheets[i].Cards...)
		product.Sheets[i].CardRefs = append([]protocol.LimitedCardReference(nil), product.Sheets[i].CardRefs...)
	}
	product.Variants = append([]protocol.LimitedPackVariantDefinition(nil), product.Variants...)
	for i := range product.Variants {
		product.Variants[i].Slots = append([]protocol.LimitedSlotDefinition(nil), product.Variants[i].Slots...)
	}
	return product
}

func NewPackPlan(eventType string, legacy *protocol.LimitedProductDefinition, definition *protocol.LimitedPackPlanDefinition) (*PackPlan, error) {
	if eventType != protocol.LimitedEventSetSealed && eventType != protocol.LimitedEventSetDraft {
		return nil, fail(ErrInvalid, "pack plans require Set Sealed or Set Draft")
	}
	if (legacy == nil) == (definition == nil) {
		return nil, fail(ErrInvalid, "supply exactly one product or pack plan")
	}
	custom := definition != nil
	if !custom {
		count := setSealedPacksPerPlayer
		if eventType == protocol.LimitedEventSetDraft {
			count = draftPacksPerPlayer
		}
		definition = &protocol.LimitedPackPlanDefinition{Products: []protocol.LimitedProductDefinition{*legacy}}
		if eventType == protocol.LimitedEventSetDraft {
			for i := 0; i < count; i++ {
				definition.Entries = append(definition.Entries, protocol.LimitedPackPlanEntry{ProductID: legacy.ID, Count: 1})
			}
		} else {
			definition.Entries = []protocol.LimitedPackPlanEntry{{ProductID: legacy.ID, Count: count}}
		}
	}
	if len(definition.Products) < 1 || len(definition.Products) > MaxPlanProducts || len(definition.Entries) < 1 || len(definition.Entries) > MaxPlanProducts {
		return nil, fail(ErrInvalid, "a pack plan needs one to twelve products and entries")
	}
	// The legacy path retains its product byte limit; the internal wrapper must
	// not reject a formerly legal product near that boundary.
	if custom {
		encoded, err := json.Marshal(definition)
		if err != nil || len(encoded) > maxEncodedProductBytes {
			return nil, fail(ErrInvalid, "combined products too large: pack plan must fit 800 KiB; select fewer or smaller products")
		}
	}
	poolCount, sheetCount := 0, 0
	for _, product := range definition.Products {
		if len(product.CardPool) > protocol.MaxLimitedProductCards-poolCount {
			return nil, fail(ErrInvalid, "combined products too large: card pools exceed 10000 entries")
		}
		poolCount += len(product.CardPool)
		for _, sheet := range product.Sheets {
			for _, n := range []int{len(sheet.Cards), len(sheet.CardRefs)} {
				if n > protocol.MaxLimitedProductCards-sheetCount {
					return nil, fail(ErrInvalid, "combined products too large: sheets exceed 10000 entries")
				}
				sheetCount += n
			}
		}
	}
	plan := &PackPlan{products: make(map[string]*Product)}
	sets := make(map[string]string)
	for _, definition := range definition.Products {
		product, err := NewProduct(definition)
		if err != nil {
			return nil, err
		}
		id := product.Definition.ID
		if product.Definition.ProductType == ProductTypeCube {
			return nil, fail(ErrInvalid, "Set pack plans cannot contain Cube products")
		}
		if plan.products[id] != nil {
			return nil, fail(ErrInvalid, "duplicate product ID in pack plan")
		}
		if previous := sets[product.Definition.SetCode]; previous != "" && previous != id {
			return nil, fail(ErrInvalid, "conflicting products for the same set")
		}
		sets[product.Definition.SetCode] = id
		plan.products[id] = product
	}
	used := make(map[string]bool)
	entryIndex := make(map[string]int)
	totalPacks := 0
	for _, entry := range definition.Entries {
		entry.ProductID = strings.TrimSpace(entry.ProductID)
		product := plan.products[entry.ProductID]
		if product == nil {
			return nil, fail(ErrInvalid, "pack plan references an unknown product")
		}
		if entry.Count < 1 || entry.Count > MaxPlanProducts-totalPacks {
			return nil, fail(ErrInvalid, "Set Sealed requires one to twelve packs per player")
		}
		if eventType == protocol.LimitedEventSetDraft && (entry.Count != 1 || len(definition.Entries) != draftPacksPerPlayer) {
			return nil, fail(ErrInvalid, "Set Draft requires exactly three ordered rounds of one pack")
		}
		if !used[entry.ProductID] {
			plan.order = append(plan.order, product)
			used[entry.ProductID] = true
			entryIndex[entry.ProductID] = len(plan.entries)
			plan.entries = append(plan.entries, entry)
		} else if eventType == protocol.LimitedEventSetSealed {
			plan.entries[entryIndex[entry.ProductID]].Count += entry.Count
		} else {
			plan.entries = append(plan.entries, entry)
		}
		totalPacks += entry.Count
	}
	if len(used) != len(plan.products) {
		return nil, fail(ErrInvalid, "pack plan has unused product definitions")
	}
	plan.packs = make([]*Product, 0, totalPacks)
	views := make([]protocol.LimitedProductView, 0, len(plan.order))
	for _, product := range plan.order {
		views = append(views, product.View())
	}
	cards := 0
	for _, entry := range plan.entries {
		product := plan.products[entry.ProductID]
		cards += entry.Count * product.Definition.CardsPerPack // both already bounded by 12 and 30
		for i := 0; i < entry.Count; i++ {
			plan.packs = append(plan.packs, product)
		}
	}
	identity, _ := json.Marshal(struct {
		EventType string                          `json:"eventType"`
		Products  []protocol.LimitedProductView   `json:"products"`
		Entries   []protocol.LimitedPackPlanEntry `json:"entries"`
	}{eventType, views, plan.entries})
	digest := sha256.Sum256(identity)
	plan.view = protocol.LimitedPackPlanView{Products: views, Entries: plan.entries,
		PlanHash: hex.EncodeToString(digest[:]), PacksPerPlayer: len(plan.packs), CardsPerPlayer: cards,
		Custom: custom || (eventType == protocol.LimitedEventSetSealed && len(plan.packs) != setSealedPacksPerPlayer)}
	return plan, nil
}

func (p *PackPlan) View() *protocol.LimitedPackPlanView {
	if p == nil {
		return nil
	}
	view := p.view
	view.Products = append([]protocol.LimitedProductView(nil), p.view.Products...)
	view.Entries = append([]protocol.LimitedPackPlanEntry(nil), p.entries...)
	return &view
}
