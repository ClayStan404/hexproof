// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.card.CardRarity;
import forge.card.CardRules;
import forge.deck.DeckSection;
import forge.gui.GuiBase;
import forge.item.PaperCard;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Exhaustive indexed lookup plus actual startup of reported and collision-prone printings. */
public final class NativePrintingAliasRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> { prefs.setPref(FPref.DECKGEN_CARDBASED, false); return null; });
            variantBoundary();
            int checked = 0;
            try (var reader = new BufferedReader(new InputStreamReader(
                    NativePrintingAliases.class.getResourceAsStream("/org/hexproof/forge/printing-aliases.tsv"), StandardCharsets.UTF_8))) {
                for (String line; (line = reader.readLine()) != null;) {
                    if (line.startsWith("#") || line.isBlank()) continue;
                    var fields = line.split("\t");
                    PaperCard card = NativePrintingAliases.find(FModel.getMagicDb().getCommonCards(), fields[0], fields[1], fields[2]);
                    if (card == null) card = NativePrintingAliases.find(FModel.getMagicDb().getVariantCards(), fields[0], fields[1], fields[2]);
                    check(card instanceof NativePromoCard && ((NativePromoCard) card).catalogSet.equals(fields[1])
                            && card.getCollectorNumber().equals(fields[2]), "Indexed identity unavailable: " + line);
                    check(NativePrintingAliases.canAlias(card), "Unsafe rules alias: " + line);
                    check(card.getFoiled() instanceof NativePromoCard && card.getUnFoiled() instanceof NativePromoCard,
                            "Foil conversion discarded display identity");
                    checked++;
                }
            }
            try (var metadata = new InputStreamReader(NativePrintingAliases.class.getResourceAsStream(
                    "/org/hexproof/forge/printing-aliases.json"), StandardCharsets.UTF_8)) {
                check(checked > 0 && checked == JsonParser.parseReader(metadata).getAsJsonObject()
                        .get("aliasedPrintings").getAsInt(), "Printing census differs from its provenance");
            }
            unavailableCensus();
            catalogNames(base);
            reportedDeck(base);
            System.out.println("PASS native catalog aliases: " + checked + " exact identities; reported deck startup and privacy");
        }
        System.exit(0);
    }

    private static void unavailableCensus() throws Exception {
        int checked = 0;
        try (var reader = new BufferedReader(new InputStreamReader(NativePrintingAliases.class.getResourceAsStream(
                "/org/hexproof/forge/printing-unavailable.tsv"), StandardCharsets.UTF_8))) {
            for (String line; (line = reader.readLine()) != null;) {
                if (line.startsWith("#") || line.isBlank()) continue;
                var fields = line.split("\t");
                PaperCard card = NativeSession.findCard(FModel.getMagicDb().getCommonCards(), fields[0], fields[1], fields[2]);
                PaperCard variant = NativeSession.findCard(FModel.getMagicDb().getVariantCards(), fields[0], fields[1], fields[2]);
                check(card == null && (variant == null || !variant.getRules().getType().isConspiracy()),
                        "Previously unavailable printing now resolves; refresh full-catalog coverage: " + line);
                check(fields[3].equals(NativePrintingAliases.unavailableReason(fields[0], fields[1], fields[2])),
                        "Unavailable printing lost its reason");
                checked++;
            }
        }
        try (var metadata = new InputStreamReader(NativePrintingAliases.class.getResourceAsStream(
                "/org/hexproof/forge/printing-aliases.json"), StandardCharsets.UTF_8)) {
            var census = JsonParser.parseReader(metadata).getAsJsonObject();
            check(checked == census.get("unresolvedPrintings").getAsInt()
                    && census.get("actionableUnresolvedPrintings").getAsInt() == 0, "Incomplete availability census");
        }
        System.out.println("PASS native catalog exclusions: " + checked + " explicit reasons; no unexplained printing gaps");
    }

    private static void catalogNames(NativeGuiBase base) {
        var database = FModel.getMagicDb().getCommonCards();
        for (String[] printing : new String[][] {{"Sophina, Spearsage Deserter", "SLX", "7"},
                {"Sophina, Spearsage Deserter", "SLD", "341"}, {"Ratonhnhaké꞉ton", "ACR", "62"},
                {"Nearby Planet", "UNF", "198"}, {"Nearby Planet", "UNF", "484"}, {"Aswan Jaguar", "PMIC", "1"}}) {
            var card = NativeSession.findCard(database, printing[0], printing[1], printing[2]);
            check(card instanceof NativePromoCard && ((NativePromoCard) card).catalogName.equals(printing[0]),
                    "Catalog name was not retained: " + Arrays.toString(printing));
            for (var foil : List.of(card.getFoiled(), card.getUnFoiled()))
                check(((NativePromoCard) foil).catalogName.equals(printing[0]), "Foil conversion discarded catalog name");
        }
        for (String[] wrong : new String[][] {{"Forest", "PMIC", "1"}, {"Aswan Jaguar", "PMIC", "99999"},
                {"Forest", "UNF", "198"}, {"Nearby Planet", "UNF", "999999"},
                {"Sophina, Spearsage Deserter", "SLX", "8"}, {"Ratonhnhaké꞉ton", "ACR", "61"},
                {"Havengul Laboratory // The Upside Down", "SLX", "9"},
                {"Havengul Laboratory // Forest", "SLX", "9"}, {"Red Herring", "CMB1", "62"},
                {"Everythingamajig", "UST", "147a"}})
            check(NativeSession.findCard(database, wrong[0], wrong[1], wrong[2]) == null,
                    "Unrelated name, face or rules variant was substituted: " + Arrays.toString(wrong));

        var request = NativeSession.object("gameId", "catalog-face-regression");
        request.addProperty("variant", "constructed"); request.addProperty("seed", 93);
        request.addProperty("startingLife", 20); request.addProperty("startingPlayerIndex", 0);
        var players = new JsonArray();
        for (int seat = 0; seat < 2; seat++) {
            var player = NativeSession.object("name", "Catalog names " + seat);
            var deck = new JsonArray();
            for (int i = 0; i < 60; i++) deck.add(NativeSession.object("name", "Forest"));
            player.add("deck", deck); players.add(player);
        }
        request.add("players", players);
        try (NativeSession session = new NativeSession(request, base); var scope = session.context.enter()) {
            var owner = session.game.getRegisteredPlayers().get(0);
            PaperCard paper = NativeSession.findCard(database, "Havengul Laboratory // Havengul Mystery", "SLD", "609");
            var card = forge.game.card.Card.fromPaperCard(paper, owner);
            check(NativeSnapshot.identity(card).get("name").getAsString().equals("Havengul Laboratory"), "Wrong front face name");
            card.setState(forge.card.CardStateName.Backside, false);
            var back = NativeSnapshot.identity(card);
            check(back.get("name").getAsString().equals("Havengul Mystery") && back.get("setCode").getAsString().isEmpty(),
                    "Transformed face retained the wrong printing/name");
        }
    }

    private static void variantBoundary() {
        var database = FModel.getMagicDb().getCommonCards();
        PaperCard regular = NativeSession.findExactCard(database, "Ancient Tomb", "TMP", "315");
        PaperCard flavored = NativeSession.findExactCard(database, "Ancient Tomb", "LTC", "387");
        check(regular != null && regular.getRules().hasFunctionalVariants()
                && NativePrintingAliases.canAlias(regular), "Unrelated variants excluded the ordinary printing");
        check(flavored != null && flavored.getFunctionalVariant().startsWith("FlavorName")
                && NativePrintingAliases.canAlias(flavored), "Cosmetic flavor name excluded the exact parent");
        PaperCard serialized = NativeSession.findCard(database, "Ancient Tomb", "LTC", "387z");
        check(serialized instanceof NativePromoCard && serialized.isFoil()
                && serialized.getFunctionalVariant().equals(flavored.getFunctionalVariant()),
                "Serialized printing must preserve the verified parent and its cosmetic variant");
        for (String[] wrong : new String[][] {{"Forest", "LTC", "387z"}, {"Ancient Tomb", "LTC", "999999z"}})
            check(NativeSession.findCard(database, wrong[0], wrong[1], wrong[2]) == null,
                    "Invented or mismatched printing gained an alias");

        // A flavor-looking label alone cannot authorize changed executable rules.
        var script = new ArrayList<>(List.of("Name:Printing boundary", "ManaCost:1", "Types:Artifact",
                "Oracle:Test printing.", "A:AB$ Mana | Cost$ T | Produced$ C | Amount$ 1",
                "Variant:FlavorNameCosmetic:FlavorName:Cosmetic printing",
                "Variant:UniversesWithin:FlavorName:Equivalent printing",
                "Variant:Mechanical:Oracle:Test printing."));
        String[] changes = {"A:AB$ Mana | Cost$ T | Produced$ C | Amount$ 2", "ManaCost:2",
                "Types:Artifact Creature", "PT:2/2", "K:Indestructible", "SVar:Test:Changed"};
        for (int i = 0; i < changes.length; i++) script.add("Variant:FlavorNameChanged" + i + ":" + changes[i]);
        CardRules rules = new CardRules.Reader().readCard(script);
        check(NativePrintingAliases.canAlias(printing(rules, "FlavorNameCosmetic")), "Unchanged cosmetic variant rejected");
        check(NativePrintingAliases.canAlias(printing(rules, "UniversesWithin")), "Equivalent Universes Within printing rejected");
        check(!NativePrintingAliases.canAlias(printing(rules, "Mechanical")), "Named rules variant accepted");
        for (int i = 0; i < changes.length; i++)
            check(!NativePrintingAliases.canAlias(printing(rules, "FlavorNameChanged" + i)),
                    "Changed rules accepted through cosmetic prefix: " + changes[i]);
    }

    private static PaperCard printing(CardRules rules, String variant) {
        return new PaperCard(rules, "TST", CardRarity.Common, 1, false, "1", "", variant);
    }

    private static void reportedDeck(NativeGuiBase base) {
        String[][] printings = {{"Blood Crypt", "RVR", "397z"}, {"Overgrown Tomb", "RVR", "407z"},
                {"Fyndhorn Elves", "PTC", "bl244"}, {"Windswept Heath", "WC04", "jn328"},
                {"Ancestral Recall", "CED", "48"}, {"Ancestral Recall", "CEI", "48"},
                {"Ancestral Recall", "2ED", "48"}, {"Ancient Tomb", "LTC", "387z"},
                {"Ancient Tomb", "LTC", "387"}, {"Ancient Tomb", "TMP", "315"},
                {"Sophina, Spearsage Deserter", "SLD", "341"}, {"Sophina, Spearsage Deserter", "SLX", "7"},
                {"Ratonhnhaké꞉ton", "ACR", "150"}, {"Ratonhnhaké꞉ton", "ACR", "244"},
                {"Havengul Laboratory // Havengul Mystery", "SLD", "609"},
                {"Havengul Laboratory // Havengul Mystery", "SLX", "9"},
                {"Casal, Lurkwood Pathfinder // Casal, Pathbreaker Owlbear", "SLX", "29"},
                {"Nearby Planet", "UNF", "198"}, {"Nearby Planet", "UNF", "484"},
                {"Aswan Jaguar", "PMIC", "1"}, {"Abomination", "4BB", "117"},
                {"Aether Shockwave", "PSAL", "C26"}, {"Pteramander", "PWCS", "2019-1"}};
        var request = NativeSession.object("gameId", "printing-regression");
        request.addProperty("variant", "constructed");
        request.addProperty("seed", 91);
        request.addProperty("startingLife", 20);
        request.addProperty("startingPlayerIndex", 0);
        JsonArray players = new JsonArray();
        for (int seat = 0; seat < 2; seat++) {
            var player = NativeSession.object("name", "Printing seat " + seat);
            JsonArray main = new JsonArray(), side = new JsonArray();
            for (String[] printing : seat == 0 ? printings : new String[0][]) {
                var card = NativeSession.object("name", printing[0]);
                card.addProperty("setCode", printing[1]); card.addProperty("collectorNumber", printing[2]);
                main.add(card); side.add(card.deepCopy());
            }
            while (main.size() < 60) main.add(NativeSession.object("name", "Forest"));
            player.add("deck", main); player.add("sideboard", side); players.add(player);
        }
        request.add("players", players);
        try (NativeSession session = new NativeSession(request, base); var scope = session.context.enter()) {
            base.setTestSession(session);
            var player = session.game.getRegisteredPlayers().get(0);
            var deck = player.getRegisteredPlayer().getDeck();
            for (var section : List.of(DeckSection.Main, DeckSection.Sideboard)) {
                var papers = deck.get(section).toFlatList();
                check(papers.stream().filter(paper -> paper.getName().equals("Ancestral Recall")).distinct().count() == 3,
                        "Different catalog sets merged despite identical native rules and numbers");
                for (String[] expected : printings) {
                    check(papers.stream().anyMatch(paper -> {
                        var identity = NativeSnapshot.identity(forge.game.card.Card.fromPaperCard(paper, player));
                        return identity.get("name").getAsString().equals(NativeCardNames.front(paper, expected[0]))
                                && identity.get("setCode").getAsString().equals(expected[1])
                                && identity.get("cardNumber").getAsString().equals(expected[2]);
                    }), "Submitted display printing changed: " + Arrays.toString(expected));
                }
            }
            session.start();
            check(!session.prompt(0).isEmpty(), "Reported deck failed to reach a native decision");
            check(!session.snapshot(1).contains("Blood Crypt") && !session.snapshot(-1).contains("Windswept Heath"),
                    "Printing index disclosed another player's private deck");
        }
    }

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
