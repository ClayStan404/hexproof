// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import (
	"strings"

	"hexproof/server/internal/protocol"
)

func normalizeProductCard(card *protocol.LimitedCardDefinition) error {
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
		!validOptionalText(card.Rarity, 32) || !validOptionalText(card.Finish, 32) ||
		card.Weight < 1 || card.Weight > maxProductWeight {
		return fail(ErrInvalid, "invalid product card")
	}
	return nil
}

// Expansion is runtime-only. The locked definition and its hash retain the
// compact references, and the ordinary sheet/card/byte limits still apply.
func resolveProductSheets(definition *protocol.LimitedProductDefinition) ([]protocol.LimitedSheetDefinition, error) {
	if len(definition.CardPool) > protocol.MaxLimitedProductCards {
		return nil, fail(ErrInvalid, "limited card pool is too large")
	}
	for i := range definition.CardPool {
		card := &definition.CardPool[i]
		if err := normalizeProductCard(card); err != nil {
			return nil, err
		}
		if card.Weight != 1 {
			return nil, fail(ErrInvalid, "pool identities must have unit weight")
		}
	}
	resolved := append([]protocol.LimitedSheetDefinition(nil), definition.Sheets...)
	total := 0
	for i := range resolved {
		sheet := &resolved[i]
		count := len(sheet.Cards) + len(sheet.CardRefs)
		if count > protocol.MaxLimitedProductCards-total {
			return nil, fail(ErrInvalid, "limited product has too many cards")
		}
		total += count
		if len(sheet.CardRefs) == 0 {
			continue
		}
		if len(sheet.Cards) != 0 {
			return nil, fail(ErrInvalid, "sheet cannot mix cards and references")
		}
		sheet.Cards = make([]protocol.LimitedCardDefinition, len(sheet.CardRefs))
		for j, ref := range sheet.CardRefs {
			if ref.CardIndex < 1 || ref.CardIndex > len(definition.CardPool) ||
				ref.Weight < 1 || ref.Weight > maxProductWeight {
				return nil, fail(ErrInvalid, "invalid product card reference")
			}
			sheet.Cards[j] = definition.CardPool[ref.CardIndex-1]
			sheet.Cards[j].Weight = ref.Weight
		}
	}
	return resolved, nil
}
