// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import "hexproof/server/internal/protocol"

func samePrinting(a, b protocol.LimitedCardDefinition) bool {
	return a.SetCode == b.SetCode && a.CollectorNumber == b.CollectorNumber && a.Finish == b.Finish
}

func pairedCard(card protocol.LimitedCardDefinition, cards []protocol.LimitedCardDefinition) protocol.LimitedCardDefinition {
	for _, partner := range cards {
		if partner.SetCode == card.SetCode && partner.CollectorNumber == card.PairCollectorNumber && partner.Finish == card.Finish {
			return partner
		}
	}
	return protocol.LimitedCardDefinition{}
}

func sheetDrawSize(sheet protocol.LimitedSheetDefinition) int {
	if len(sheet.Cards) > 0 && sheet.Cards[0].PairCollectorNumber != "" {
		return 2
	}
	return 1
}

func validatePairedSheet(sheet protocol.LimitedSheetDefinition, cube bool) error {
	paired := sheetDrawSize(sheet) == 2
	if cube && (paired || sheet.ExcludePrevious) {
		return fail(ErrInvalid, "Cube cannot contain paired or excluding sheets")
	}
	for _, card := range sheet.Cards {
		if (card.PairCollectorNumber != "") != paired {
			return fail(ErrInvalid, "mixed paired and ordinary sheet")
		}
		if !paired {
			continue
		}
		partner := pairedCard(card, sheet.Cards)
		if !validText(card.PairCollectorNumber, protocol.MaxCollectorNumberRunes) ||
			partner.PairCollectorNumber != card.CollectorNumber || samePrinting(card, partner) ||
			partner.Weight != card.Weight || partner.Rarity != card.Rarity {
			return fail(ErrInvalid, "invalid reciprocal card pair")
		}
		matches := 0
		for _, other := range sheet.Cards {
			if samePrinting(card, other) {
				matches++
			}
		}
		if matches != 1 {
			return fail(ErrInvalid, "duplicate paired printing")
		}
	}
	return nil
}

func alreadyDrawn(card protocol.LimitedCardDefinition, drawn []*CardInstance) bool {
	for _, previous := range drawn {
		if previous.SetCode == card.SetCode && previous.CollectorNumber == card.CollectorNumber && previous.Finish == card.Finish {
			return true
		}
	}
	return false
}
