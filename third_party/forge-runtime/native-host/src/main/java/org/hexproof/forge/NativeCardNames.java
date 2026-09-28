// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import forge.card.CardSplitType;
import forge.item.PaperCard;
import java.text.Normalizer;

/** Catalog spelling and native face names share rules without changing game names. */
final class NativeCardNames {
    private NativeCardNames() {}

    static String lookup(String name) {
        // Scryfall uses MODIFIER LETTER COLON in Ratonhnhaké꞉ton; Forge uses ':'.
        return Normalizer.normalize(name, Normalizer.Form.NFC).replace('\ua789', ':');
    }

    static boolean equal(String first, String second) {
        return lookup(first).equalsIgnoreCase(lookup(second));
    }

    static boolean matches(PaperCard card, String name) {
        if (equal(card.getName(), name) || equal(card.getDisplayName(), name)) return true;
        String[] faces = name.split(" // ", -1);
        if (faces.length != 2 || card.getOtherFace() == null) return false;
        return (equal(card.getMainFace().getName(), faces[0].trim())
                    && equal(card.getOtherFace().getName(), faces[1].trim()))
                || (equal(card.getMainFace().getDisplayName(), faces[0].trim())
                    && equal(card.getOtherFace().getDisplayName(), faces[1].trim()));
    }

    static String front(PaperCard card, String catalogName) {
        return card.getRules().getSplitType().getAggregationMethod() == CardSplitType.FaceSelectionMethod.COMBINE
                ? catalogName : catalogName.split(" // ", -1)[0];
    }

    static PaperCard preserve(PaperCard card, String name, String set, String number) {
        if (card == null || set.isEmpty() || number.isEmpty()
                || card.getName().equals(front(card, name)) && !(card instanceof NativePromoCard)) return card;
        return new NativePromoCard(card, name, set.toUpperCase(java.util.Locale.ROOT), number);
    }
}
