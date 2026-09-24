// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import forge.card.CardDb;
import forge.item.PaperCard;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/** Reviewed catalog identities mapped to an exact native printing of the same Oracle card. */
final class NativePrintingAliases {
    private record Key(String name, String set, String number) {
        static Key of(String name, String set, String number) {
            return new Key(name.toLowerCase(Locale.ROOT), set.toUpperCase(Locale.ROOT), number);
        }
    }
    private record Parent(String set, String number) {}
    private static final Map<Key, Parent> INDEX = load();

    private static Map<Key, Parent> load() {
        Map<Key, Parent> result = new HashMap<>();
        var stream = NativePrintingAliases.class.getResourceAsStream("/org/hexproof/forge/printing-aliases.tsv");
        if (stream == null) throw new IllegalStateException("Missing catalog printing index");
        try (var reader = new BufferedReader(new InputStreamReader(stream, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.startsWith("#") || line.isBlank()) continue;
                String[] fields = line.split("\t", -1);
                if (fields.length != 5 || result.put(Key.of(fields[0], fields[1], fields[2]),
                        new Parent(fields[3], fields[4])) != null)
                    throw new IllegalStateException("Invalid catalog printing index");
            }
        } catch (java.io.IOException error) {
            throw new IllegalStateException("Unreadable catalog printing index", error);
        }
        return Map.copyOf(result);
    }

    static PaperCard find(CardDb database, String name, String set, String number) {
        Parent parent = INDEX.get(Key.of(name, set, number));
        if (parent == null) return null;
        PaperCard card = NativeSession.findExactCard(database, name, parent.set(), parent.number());
        if (card == null || card.getRules().isUnsupported() || card.getRules().hasFunctionalVariants()) return null;
        boolean foil = number.endsWith("z") || number.endsWith("★") || number.matches("[0-9]+s");
        return new NativePromoCard(foil ? card.getFoiled() : card, set.toUpperCase(Locale.ROOT), number);
    }
}
