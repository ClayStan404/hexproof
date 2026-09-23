// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import forge.item.PaperCard;

/** A catalog printing alias keeps the native parent edition for rules and its own display identity. */
final class NativePromoCard extends PaperCard {
    final String catalogSet;

    NativePromoCard(PaperCard parent, String set, String number) {
        // Keep the suffix in PaperCard's identity so deck pools do not merge
        // promo, special-treatment and regular copies of the same card.
        super(parent.getRules(), parent.getEdition(), parent.getRarity(), parent.getArtIndex(),
                parent.isFoil(), number, parent.getArtist(), parent.getFunctionalVariant());
        catalogSet = set;
    }
}
