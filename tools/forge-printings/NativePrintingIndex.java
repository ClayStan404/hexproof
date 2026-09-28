// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.card.CardDb;
import forge.gui.GuiBase;
import forge.item.PaperCard;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import java.nio.file.*;
import java.util.*;

/** Offline census; candidates may share rules only within one catalog Oracle identity. */
public final class NativePrintingIndex {
    private record Printing(String oracle, String name, String set, String number, String layout,
                            PaperCard nativeCard, boolean exact, boolean anchorOnly, boolean english) {}
    private record RulesIdentity(String name, String variant) {
        static RulesIdentity of(PaperCard card) {
            return new RulesIdentity(card.getRules().getName(), card.getFunctionalVariant());
        }
    }
    private static String baseNumber(String number) {
        return number.replaceFirst("^[a-z]+", "").replaceFirst("[psz★]$", "");
    }

    private static PaperCard exact(String name, String set, String number) {
        PaperCard card = NativeSession.findExactCard(FModel.getMagicDb().getCommonCards(), name, set, number);
        if (card == null) {
            var variant = NativeSession.findExactCard(FModel.getMagicDb().getVariantCards(), name, set, number);
            if (variant != null && variant.getRules().getType().isConspiracy()) card = variant;
        }
        return card;
    }

    private static List<PaperCard> named(CardDb database, String name) {
        String lookup = NativeCardNames.lookup(name);
        var cards = database.getAllCards(lookup);
        if (cards.isEmpty() && lookup.contains(" // ")) cards = database.getAllCards(lookup.split(" // ")[0]);
        return cards;
    }

    private static String unavailable(Printing printing, Map<RulesIdentity, Set<String>> identities) {
        if (printing.layout().equals("front_card")) return "not_a_playing_card";
        if (Set.of("planar", "scheme", "vanguard").contains(printing.layout())) return "unsupported_game_piece";
        var cards = named(FModel.getMagicDb().getCommonCards(), printing.name());
        if (printing.layout().equals("meld") && cards.stream().anyMatch(card -> card.getOtherFace() != null
                && NativeCardNames.equal(card.getOtherFace().getName(), printing.name()))) return "meld_result";
        var matching = cards.stream().filter(card -> NativeCardNames.matches(card, printing.name())).toList();
        if (!matching.isEmpty()) {
            var edition = FModel.getMagicDb().getEditions().get(printing.set());
            if (edition != null) {
                for (var card : matching) {
                    for (var entry : edition.getCardInSet(card.getName())) {
                        String variant = entry.getFunctionalVariantName();
                        if (printing.number().equals(entry.collectorNumber()) && variant != null
                                && (card.getRules().getSupportedFunctionalVariants() == null
                                    || !card.getRules().getSupportedFunctionalVariants().contains(variant)))
                            return "native_variant_missing";
                    }
                }
            }
            // Same-name cards can have different Oracle identities (e.g. playtest
            // Red Herring and the later normal card). Name-only lookup is no proof.
            if (matching.stream().allMatch(card -> identities.containsKey(RulesIdentity.of(card))
                    && !identities.get(RulesIdentity.of(card)).contains(printing.oracle())))
                return "different_rules_same_name";
            return "unmatched_native_printing";
        }
        if (named(FModel.getMagicDb().getVariantCards(), printing.name()).stream()
                .anyMatch(card -> NativeCardNames.matches(card, printing.name()) && !card.getRules().getType().isConspiracy()))
            return "unsupported_game_piece";
        return "native_rules_missing";
    }

    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> { prefs.setPref(FPref.DECKGEN_CARDBASED, false); return null; });
            Map<String, List<Printing>> groups = new TreeMap<>();
            Map<RulesIdentity, Set<String>> identities = new HashMap<>();
            List<Path> catalogs = new ArrayList<>(List.of(Path.of(args[1])));
            if (args.length > 5) catalogs.add(Path.of(args[5]));
            for (int source = 0; source < catalogs.size(); source++) {
                for (var element : JsonParser.parseString(Files.readString(catalogs.get(source))).getAsJsonArray()) {
                    var row = element.getAsJsonArray();
                    String oracle = row.get(0).getAsString(), name = row.get(1).getAsString();
                    String set = row.get(2).getAsString(), number = row.get(3).getAsString();
                    String layout = row.get(4).getAsString();
                    PaperCard card = exact(name, set, number);
                    boolean direct = card != null;
                    // Forge marks some funny/playtest collector numbers with F.
                    // This is only an offline anchor for an enumerated catalog row;
                    // the runtime must not accept arbitrary prefixed/stripped numbers.
                    if (card == null && number.matches("[0-9]+")) card = exact(name, set, "F" + number);
                    groups.computeIfAbsent(oracle, key -> new ArrayList<>())
                            .add(new Printing(oracle, name, set, number, layout, card, direct, source > 0,
                                    row.get(5).getAsInt() == 1));
                    if (card != null) identities.computeIfAbsent(RulesIdentity.of(card), key -> new HashSet<>()).add(oracle);
                }
            }
            List<String> aliases = new ArrayList<>();
            JsonArray unresolved = new JsonArray();
            List<String> unavailableRows = new ArrayList<>();
            Map<String, Integer> reasons = new TreeMap<>();
            int exact = 0;
            for (var group : groups.values()) {
                for (var printing : group) {
                    if (printing.anchorOnly()) continue;
                    if (printing.exact()) { exact++; continue; }
                    var parents = group.stream().filter(parent -> parent.name().equals(printing.name())
                            && NativePrintingAliases.canAlias(parent.nativeCard())).sorted(Comparator
                            .comparing(Printing::anchorOnly)
                            .thenComparing(parent -> !parent.english())
                            .thenComparing(parent -> !parent.exact())
                            .thenComparing((Printing parent) -> !parent.set().equals(printing.set()))
                            .thenComparing(parent -> !(printing.set().matches("P[A-Z0-9]{3}")
                                && parent.set().equals(printing.set().substring(1))))
                            .thenComparing(parent -> !baseNumber(printing.number()).equals(parent.number()))
                            .thenComparing(Printing::set).thenComparing(Printing::number)).toList();
                    if (parents.isEmpty()) {
                        String reason = unavailable(printing, identities);
                        JsonArray row = new JsonArray();
                        for (String field : List.of(printing.name(), printing.set(), printing.number(), reason)) row.add(field);
                        unresolved.add(row);
                        unavailableRows.add(String.join("\t", printing.name(), printing.set(), printing.number(), reason));
                        reasons.merge(reason, 1, Integer::sum);
                        continue;
                    }
                    PaperCard parent = parents.get(0).nativeCard();
                    aliases.add(String.join("\t", printing.name(), printing.set(), printing.number(),
                            parent.getEdition(), parent.getCollectorNumber()));
                }
            }
            Collections.sort(aliases);
            Collections.sort(unavailableRows);
            Files.writeString(Path.of(args[2]), "# SPDX-License-Identifier: GPL-3.0-or-later\n"
                    + "# SPDX-FileCopyrightText: 2026 Hexproof contributors\n"
                    + "# Generated by tools/forge-printings/generate.py; see printing-aliases.json.\n"
                    + "# name\tcatalog set\tcatalog number\tnative set\tnative number\n"
                    + String.join("\n", aliases) + "\n");
            Files.writeString(Path.of(args[4]), "# SPDX-License-Identifier: GPL-3.0-or-later\n"
                    + "# SPDX-FileCopyrightText: 2026 Hexproof contributors\n"
                    + "# Generated by tools/forge-printings/generate.py; see README.md for reason codes.\n"
                    + "# name\tcatalog set\tcatalog number\treason\n"
                    + String.join("\n", unavailableRows) + "\n");
            JsonObject report = new JsonObject();
            report.addProperty("exactPrintings", exact);
            report.addProperty("aliasedPrintings", aliases.size());
            report.addProperty("unresolvedPrintings", unresolved.size());
            report.add("unresolvedReasons", new Gson().toJsonTree(reasons));
            report.addProperty("actionableUnresolvedPrintings", reasons.getOrDefault("unmatched_native_printing", 0));
            report.add("unresolved", unresolved);
            Files.writeString(Path.of(args[3]), new GsonBuilder().setPrettyPrinting().create().toJson(report) + "\n");
        }
        System.exit(0);
    }
}
