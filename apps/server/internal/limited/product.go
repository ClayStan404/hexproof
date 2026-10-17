// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"math"
	"math/rand"
	"strings"
	"unicode"
	"unicode/utf8"

	"hexproof/server/internal/protocol"
)

const (
	ProductTypeOfficial    = "official"
	ProductTypeApproximate = "approximate"
	ProductTypeCube        = "cube"
	maxProductText         = 128
	// JSON numbers stay exact only through 2^53-1. MTGJSON Play sheets such as
	// FIN can exceed 1e9 while remaining inside that bound.
	maxProductWeight       = 9007199254740991
	maxCubePhysicalCards   = 10_000
	maxCubeCardEntries     = 5000
	maxEncodedProductBytes = 800 * 1024
)

type Product struct {
	Definition protocol.LimitedProductDefinition
	sheets     map[string]protocol.LimitedSheetDefinition
	hash       string
	cardCount  int
	typeLines  map[printingIdentity]string
}

type printingIdentity struct {
	setCode, collectorNumber string
}

func NewProduct(definition protocol.LimitedProductDefinition) (*Product, error) {
	definition.ID = strings.TrimSpace(definition.ID)
	definition.Name = strings.TrimSpace(definition.Name)
	definition.SetCode = strings.ToUpper(strings.TrimSpace(definition.SetCode))
	definition.ProductType = strings.ToLower(strings.TrimSpace(definition.ProductType))
	validProductType := definition.ProductType == ProductTypeOfficial ||
		definition.ProductType == ProductTypeApproximate ||
		definition.ProductType == ProductTypeCube
	if !validText(definition.ID, maxProductText) || !validText(definition.Name, maxProductText) ||
		!validProductType ||
		(definition.ProductType != ProductTypeCube &&
			!validText(definition.SetCode, protocol.MaxSetCodeRunes)) ||
		(definition.ProductType == ProductTypeOfficial) != definition.Authentic ||
		(definition.ProductType == ProductTypeCube && definition.CardsPerPack != 0) ||
		(definition.ProductType != ProductTypeCube &&
			(definition.CardsPerPack < 1 || definition.CardsPerPack > 30)) ||
		len(definition.Sheets) < 1 ||
		len(definition.Sheets) > protocol.MaxLimitedProductSheets ||
		len(definition.Variants) > protocol.MaxLimitedVariants {
		return nil, fail(ErrInvalid, "invalid limited product")
	}

	resolvedSheets, err := resolveProductSheets(&definition)
	if err != nil {
		return nil, err
	}
	sheets := make(map[string]protocol.LimitedSheetDefinition, len(definition.Sheets))
	cardCount := 0
	cubeCardCount := int64(0)
	typeLines := make(map[printingIdentity]string)
	for sheetIndex := range resolvedSheets {
		sheet := &resolvedSheets[sheetIndex]
		sheet.Name = strings.TrimSpace(sheet.Name)
		definition.Sheets[sheetIndex].Name = sheet.Name
		if !validText(sheet.Name, maxProductText) || len(sheet.Cards) == 0 {
			return nil, fail(ErrInvalid, "invalid product sheet")
		}
		if _, duplicate := sheets[sheet.Name]; duplicate {
			return nil, fail(ErrInvalid, "duplicate product sheet")
		}
		totalWeight := int64(0)
		for cardIndex := range sheet.Cards {
			card := &sheet.Cards[cardIndex]
			if err := normalizeProductCard(card); err != nil {
				return nil, err
			}
			if int64(card.Weight) > math.MaxInt64-totalWeight {
				return nil, fail(ErrInvalid, "product sheet total weight is too large")
			}
			if card.TypeLine != "" {
				key := printingIdentity{card.SetCode, card.CollectorNumber}
				if existing := typeLines[key]; existing != "" && existing != card.TypeLine {
					return nil, fail(ErrInvalid, "conflicting printing type lines")
				}
				typeLines[key] = card.TypeLine
			}
			totalWeight += int64(card.Weight)
			cardCount++
			if definition.ProductType == ProductTypeCube {
				cubeCardCount += int64(card.Weight)
				if cubeCardCount > maxCubePhysicalCards {
					return nil, fail(ErrInvalid, "Cube contains too many physical cards")
				}
			}
			if cardCount > protocol.MaxLimitedProductCards ||
				(definition.ProductType == ProductTypeCube && cardCount > maxCubeCardEntries) {
				return nil, fail(ErrInvalid, "limited product has too many cards")
			}
		}
		if err := validatePairedSheet(*sheet, definition.ProductType == ProductTypeCube); err != nil {
			return nil, err
		}
		sheets[sheet.Name] = *sheet
	}

	if definition.ProductType != ProductTypeCube {
		if len(definition.Variants) == 0 {
			return nil, fail(ErrInvalid, "product has no pack variants")
		}
		for variantIndex := range definition.Variants {
			variant := &definition.Variants[variantIndex]
			if variant.Weight < 1 || variant.Weight > maxProductWeight ||
				len(variant.Slots) < 1 ||
				len(variant.Slots) > protocol.MaxLimitedSlots {
				return nil, fail(ErrInvalid, "invalid pack variant")
			}
			slotCards := 0
			usedSheets := make(map[string]bool, len(variant.Slots))
			for slotIndex := range variant.Slots {
				slot := &variant.Slots[slotIndex]
				slot.Sheet = strings.TrimSpace(slot.Sheet)
				sheet, ok := sheets[slot.Sheet]
				if !ok || usedSheets[slot.Sheet] || slot.Count < 1 || slot.Count > 30 ||
					(!sheet.WithReplacement && slot.Count*sheetDrawSize(sheet) > len(sheet.Cards)) {
					return nil, fail(ErrInvalid, "invalid pack slot")
				}
				usedSheets[slot.Sheet] = true
				slotCards += slot.Count * sheetDrawSize(sheet)
			}
			if slotCards != definition.CardsPerPack {
				return nil, fail(ErrInvalid, "pack variant size does not match product")
			}
		}
	}

	encoded, err := json.Marshal(definition)
	if err != nil {
		return nil, fail(ErrInvalid, "product could not be encoded")
	}
	if len(encoded) > maxEncodedProductBytes {
		return nil, fail(ErrInvalid, "limited product definition is too large")
	}
	digest := sha256.Sum256(encoded)
	if definition.ProductType == ProductTypeCube {
		cardCount = int(cubeCardCount)
	}
	return &Product{
		Definition: definition,
		sheets:     sheets,
		hash:       hex.EncodeToString(digest[:]),
		cardCount:  cardCount,
		typeLines:  typeLines,
	}, nil
}

func validText(value string, maximum int) bool {
	if value == "" || utf8.RuneCountInString(value) > maximum {
		return false
	}
	for _, character := range value {
		if unicode.IsControl(character) {
			return false
		}
	}
	return true
}

func validOptionalText(value string, maximum int) bool {
	return value == "" || validText(value, maximum)
}

func (p *Product) View() protocol.LimitedProductView {
	return protocol.LimitedProductView{
		ID: p.Definition.ID, Name: p.Definition.Name, SetCode: p.Definition.SetCode,
		ProductType: p.Definition.ProductType, Authentic: p.Definition.Authentic,
		CardsPerPack: p.Definition.CardsPerPack, CardCount: p.cardCount,
		ProductHash: p.hash,
	}
}

func chooseWeight(random *rand.Rand, weights []int) int {
	total := int64(0)
	for _, weight := range weights {
		if weight < 0 || int64(weight) > math.MaxInt64-total {
			return -1
		}
		total += int64(weight)
	}
	if total <= 0 {
		return -1
	}
	value := random.Int63n(total)
	for index, weight := range weights {
		if value < int64(weight) {
			return index
		}
		value -= int64(weight)
	}
	return len(weights) - 1
}

func (p *Product) generatePack(random *rand.Rand, nextID func() string) ([]*CardInstance, error) {
	variantWeights := make([]int, len(p.Definition.Variants))
	for index, variant := range p.Definition.Variants {
		variantWeights[index] = variant.Weight
	}
	variantIndex := chooseWeight(random, variantWeights)
	if variantIndex < 0 {
		return nil, fail(ErrInvalid, "product has no weighted pack variant")
	}
	variant := p.Definition.Variants[variantIndex]
	result := make([]*CardInstance, 0, p.Definition.CardsPerPack)
	for _, slot := range variant.Slots {
		sheet := p.sheets[slot.Sheet]
		available := append([]protocol.LimitedCardDefinition(nil), sheet.Cards...)
		for count := 0; count < slot.Count; count++ {
			eligible := make([]protocol.LimitedCardDefinition, 0, len(available))
			for _, card := range available {
				if !sheet.ExcludePrevious || !alreadyDrawn(card, result) {
					if card.PairCollectorNumber == "" || !sheet.ExcludePrevious || !alreadyDrawn(pairedCard(card, sheet.Cards), result) {
						eligible = append(eligible, card)
					}
				}
			}
			weights := make([]int, len(eligible))
			for index, card := range eligible {
				weights[index] = card.Weight
			}
			cardIndex := chooseWeight(random, weights)
			if cardIndex < 0 {
				return nil, fail(ErrInvalid, "product sheet cannot fill pack slot")
			}
			selected := []protocol.LimitedCardDefinition{eligible[cardIndex]}
			if selected[0].PairCollectorNumber != "" {
				selected = append(selected, pairedCard(selected[0], sheet.Cards))
				if random.Intn(2) == 0 {
					selected[0], selected[1] = selected[1], selected[0]
				}
			}
			for _, card := range selected {
				result = append(result, p.newCardInstance(nextID(), card))
				if !sheet.WithReplacement {
					for index := 0; index < len(available); index++ {
						if available[index] == card {
							available = append(available[:index], available[index+1:]...)
							break
						}
					}
				}
			}
		}
	}
	return result, nil
}

func (p *Product) cubeStock() []*CardInstance {
	stock := make([]*CardInstance, 0)
	sequence := 0
	for _, definition := range p.Definition.Sheets {
		sheet := p.sheets[definition.Name]
		for _, card := range sheet.Cards {
			for copyIndex := 0; copyIndex < card.Weight; copyIndex++ {
				sequence++
				stock = append(stock, p.newCardInstance("cube-"+itoa(sequence), card))
			}
		}
	}
	return stock
}

func (p *Product) newCardInstance(id string, card protocol.LimitedCardDefinition) *CardInstance {
	if card.TypeLine == "" {
		card.TypeLine = p.typeLines[printingIdentity{card.SetCode, card.CollectorNumber}]
	}
	return newCardInstance(id, card)
}

func itoa(value int) string {
	const digits = "0123456789"
	if value == 0 {
		return "0"
	}
	var buffer [20]byte
	position := len(buffer)
	for value > 0 {
		position--
		buffer[position] = digits[value%10]
		value /= 10
	}
	return string(buffer[position:])
}
