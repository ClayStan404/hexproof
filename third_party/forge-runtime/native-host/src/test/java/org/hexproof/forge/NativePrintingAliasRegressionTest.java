// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
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
                    check(!card.getRules().isUnsupported() && !card.getRules().hasFunctionalVariants(), "Unsafe rules alias: " + line);
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
            reportedDeck(base);
            System.out.println("PASS native catalog aliases: " + checked + " exact identities; reported deck startup and privacy");
        }
        System.exit(0);
    }

    private static void reportedDeck(NativeGuiBase base) {
        String[][] printings = {{"Blood Crypt", "RVR", "397z"}, {"Overgrown Tomb", "RVR", "407z"},
                {"Fyndhorn Elves", "PTC", "bl244"}, {"Windswept Heath", "WC04", "jn328"},
                {"Ancestral Recall", "CED", "48"}, {"Ancestral Recall", "CEI", "48"},
                {"Ancestral Recall", "2ED", "48"}};
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
                        return identity.get("name").getAsString().equals(expected[0])
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
