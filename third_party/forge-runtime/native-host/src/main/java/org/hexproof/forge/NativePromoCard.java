// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import forge.item.PaperCard;
import java.util.Objects;

/** A catalog printing alias keeps the native parent edition for rules and its own display identity. */
final class NativePromoCard extends PaperCard {
    final String catalogSet;
    final String catalogName;

    NativePromoCard(PaperCard parent, String set, String number) {
        this(parent, parent instanceof NativePromoCard alias ? alias.catalogName : parent.getName(), set, number);
    }

    NativePromoCard(PaperCard parent, String name, String set, String number) {
        // Keep the suffix in PaperCard's identity so deck pools do not merge
        // promo, special-treatment and regular copies of the same card.
        super(parent.getRules(), parent.getEdition(), parent.getRarity(), parent.getArtIndex(),
                parent.isFoil(), number, parent.getArtist(), parent.getFunctionalVariant());
        catalogSet = set;
        catalogName = name;
    }

    @Override public boolean equals(Object other) {
        return super.equals(other) && other instanceof NativePromoCard alias
                && catalogSet.equals(alias.catalogSet) && catalogName.equals(alias.catalogName);
    }
    @Override public int hashCode() { return Objects.hash(super.hashCode(), catalogSet, catalogName); }
    @Override public PaperCard getFoiled() {
        return isFoil() ? this : new NativePromoCard(super.getFoiled(), catalogName, catalogSet, getCollectorNumber());
    }
    @Override public PaperCard getUnFoiled() {
        return !isFoil() ? this : new NativePromoCard(super.getUnFoiled(), catalogName, catalogSet, getCollectorNumber());
    }
}
