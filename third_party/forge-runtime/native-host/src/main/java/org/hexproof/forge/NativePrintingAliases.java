// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import forge.card.CardDb;
import forge.card.ICardFace;
import forge.item.PaperCard;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

/** Reviewed catalog identities mapped to an exact native printing of the same Oracle card. */
final class NativePrintingAliases {
    private record Key(String name, String set, String number) {
        static Key of(String name, String set, String number) {
            return new Key(name.toLowerCase(Locale.ROOT), set.toUpperCase(Locale.ROOT), number);
        }
    }
    private record Parent(String set, String number) {}
    private static final Map<Key, Parent> INDEX = load();
    private static final Map<Key, String> UNAVAILABLE = loadUnavailable();

    private static Map<Key, String> loadUnavailable() {
        Map<Key, String> result = new HashMap<>();
        Set<String> reasons = Set.of("native_rules_missing", "native_variant_missing", "different_rules_same_name",
                "meld_result", "not_a_playing_card", "unsupported_game_piece");
        var stream = NativePrintingAliases.class.getResourceAsStream("/org/hexproof/forge/printing-unavailable.tsv");
        if (stream == null) throw new IllegalStateException("Missing catalog availability index");
        try (var reader = new BufferedReader(new InputStreamReader(stream, StandardCharsets.UTF_8))) {
            for (String line; (line = reader.readLine()) != null;) {
                if (line.startsWith("#") || line.isBlank()) continue;
                String[] fields = line.split("\t", -1);
                if (fields.length != 4 || !reasons.contains(fields[3]))
                    throw new IllegalStateException("Invalid catalog availability index");
                Key key = Key.of(fields[0], fields[1], fields[2]);
                if (INDEX.containsKey(key) || result.put(key, fields[3]) != null)
                    throw new IllegalStateException("Conflicting catalog availability index");
            }
        } catch (java.io.IOException error) {
            throw new IllegalStateException("Unreadable catalog availability index", error);
        }
        return Map.copyOf(result);
    }

    static String unavailableReason(String name, String set, String number) {
        return UNAVAILABLE.get(Key.of(name, set, number));
    }

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
        if (!canAlias(card)) return null;
        boolean foil = number.endsWith("z") || number.endsWith("★") || number.matches("[0-9]+s");
        return new NativePromoCard(foil ? card.getFoiled() : card, name, set.toUpperCase(Locale.ROOT), number);
    }

    // Forge stores cosmetic flavor names in the same registry as rules variants.
    // Judge the selected printing, not whether any other printing has a variant.
    static boolean canAlias(PaperCard card) {
        if (card == null || card.getRules().isUnsupported()) return false;
        String variant = card.getFunctionalVariant();
        if (variant == null || variant.isEmpty()) return true;
        if (!variant.startsWith("FlavorName") && !variant.equals("UniversesWithin")) return false;
        boolean found = false;
        for (ICardFace face : card.getRules().getAllFaces()) {
            ICardFace alternate = face.getFunctionalVariant(variant);
            if (alternate == null) continue;
            found = true;
            if (!sameRules(face, alternate)) return false;
        }
        return found;
    }

    private static boolean sameRules(ICardFace base, ICardFace alternate) {
        return Objects.equals(base.getName(), alternate.getName())
                && Objects.equals(base.getType().toString(), alternate.getType().toString())
                && Objects.equals(base.getManaCost(), alternate.getManaCost())
                && Objects.equals(base.getColor(), alternate.getColor())
                && Objects.equals(base.getPower(), alternate.getPower())
                && Objects.equals(base.getToughness(), alternate.getToughness())
                && Objects.equals(base.getInitialLoyalty(), alternate.getInitialLoyalty())
                && Objects.equals(base.getDefense(), alternate.getDefense())
                && Objects.equals(base.getAttractionLights(), alternate.getAttractionLights())
                // Forge rewrites Oracle display text with the flavor name.
                // Executable abilities and characteristics must stay identical.
                && Objects.equals(base.getNonAbilityText(), alternate.getNonAbilityText())
                && entries(base.getKeywords()).equals(entries(alternate.getKeywords()))
                && entries(base.getDeckRules()).equals(entries(alternate.getDeckRules()))
                && entries(base.getReplacements()).equals(entries(alternate.getReplacements()))
                && entries(base.getTriggers()).equals(entries(alternate.getTriggers()))
                && entries(base.getDraftActions()).equals(entries(alternate.getDraftActions()))
                && entries(base.getStaticAbilities()).equals(entries(alternate.getStaticAbilities()))
                && entries(base.getAbilities()).equals(entries(alternate.getAbilities()))
                && entries(base.getVariables()).equals(entries(alternate.getVariables()));
    }

    private static List<?> entries(Iterable<?> values) {
        List<Object> result = new ArrayList<>();
        if (values != null) values.forEach(result::add);
        return result;
    }
}
