// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
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
	maxProductWeight       = 1_000_000_000
	maxCubePhysicalCards   = 10_000
	maxEncodedProductBytes = 800 * 1024
)

type Product struct {
	Definition protocol.LimitedProductDefinition
	sheets     map[string]protocol.LimitedSheetDefinition
	hash       string
	cardCount  int
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

	sheets := make(map[string]protocol.LimitedSheetDefinition, len(definition.Sheets))
	cardCount := 0
	cubeCardCount := int64(0)
	for sheetIndex := range definition.Sheets {
		sheet := &definition.Sheets[sheetIndex]
		sheet.Name = strings.TrimSpace(sheet.Name)
		if !validText(sheet.Name, maxProductText) || len(sheet.Cards) == 0 {
			return nil, fail(ErrInvalid, "invalid product sheet")
		}
		if _, duplicate := sheets[sheet.Name]; duplicate {
			return nil, fail(ErrInvalid, "duplicate product sheet")
		}
		for cardIndex := range sheet.Cards {
			card := &sheet.Cards[cardIndex]
			card.Name = strings.TrimSpace(card.Name)
			card.SetCode = strings.ToUpper(strings.TrimSpace(card.SetCode))
			card.CollectorNumber = strings.TrimSpace(card.CollectorNumber)
			card.TypeLine = strings.TrimSpace(card.TypeLine)
			card.Rarity = strings.ToLower(strings.TrimSpace(card.Rarity))
			card.Finish = strings.ToLower(strings.TrimSpace(card.Finish))
			if !validText(card.Name, protocol.MaxCardNameRunes) ||
				!validText(card.SetCode, protocol.MaxSetCodeRunes) ||
				!validText(card.CollectorNumber, protocol.MaxCollectorNumberRunes) ||
				!validOptionalText(card.TypeLine, protocol.MaxTypeLineRunes) ||
				!validOptionalText(card.Rarity, 32) ||
				!validOptionalText(card.Finish, 32) ||
				card.Weight < 1 || card.Weight > maxProductWeight {
				return nil, fail(ErrInvalid, "invalid product card")
			}
			cardCount++
			if definition.ProductType == ProductTypeCube {
				cubeCardCount += int64(card.Weight)
				if cubeCardCount > maxCubePhysicalCards {
					return nil, fail(ErrInvalid, "Cube contains too many physical cards")
				}
			}
			if cardCount > protocol.MaxLimitedProductCards {
				return nil, fail(ErrInvalid, "limited product has too many cards")
			}
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
					(!sheet.WithReplacement && slot.Count > len(sheet.Cards)) {
					return nil, fail(ErrInvalid, "invalid pack slot")
				}
				usedSheets[slot.Sheet] = true
				slotCards += slot.Count
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
			weights := make([]int, len(available))
			for index, card := range available {
				weights[index] = card.Weight
			}
			cardIndex := chooseWeight(random, weights)
			if cardIndex < 0 {
				return nil, fail(ErrInvalid, "product sheet cannot fill pack slot")
			}
			result = append(result, newCardInstance(nextID(), available[cardIndex]))
			if !sheet.WithReplacement {
				available = append(available[:cardIndex], available[cardIndex+1:]...)
			}
		}
	}
	return result, nil
}

func (p *Product) cubeStock() []*CardInstance {
	stock := make([]*CardInstance, 0)
	sequence := 0
	for _, sheet := range p.Definition.Sheets {
		for _, card := range sheet.Cards {
			for copyIndex := 0; copyIndex < card.Weight; copyIndex++ {
				sequence++
				stock = append(stock, newCardInstance("cube-"+itoa(sequence), card))
			}
		}
	}
	return stock
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
