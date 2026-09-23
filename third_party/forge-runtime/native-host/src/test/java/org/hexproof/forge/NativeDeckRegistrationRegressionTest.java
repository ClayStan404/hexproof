// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.deck.Deck;
import forge.deck.DeckSection;
import forge.gui.GuiBase;
import forge.item.PaperCard;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import java.util.List;

/** Resolve catalog face names through real native deck registration and startup. */
public final class NativeDeckRegistrationRegressionTest {
    private static final String DISCIPLE = "Disciple of Freyalise // Garden of Freyalise";
    private static final String TURNTIMBER = "Turntimber Symbiosis // Turntimber, Serpentine Wood";
    private static final String ESIKA = "Esika, God of the Tree // The Prismatic Bridge";

    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                prefs.setPref(FPref.YIELD_AUTO_PASS_NO_ACTIONS, false);
                prefs.setPref(FPref.UI_SELECT_FROM_CARD_DISPLAYS, false);
                return null;
            });
            rejectUnavailablePrintings(base);
            promoPrintings(base);
            treatmentPrintings(base);
            registerAndStart(base);
            commanders(base);
            limited(base);
            limitedCompanion(base);
            rejectWrongFaces(base);
        }
        System.out.println("Native deck registration regression passed");
        System.exit(0);
    }

    private static JsonObject config() {
        JsonObject request = NativeSession.object("gameId", "multiface-deck");
        request.addProperty("variant", "constructed");
        request.addProperty("seed", 73);
        request.addProperty("startingLife", 20);
        request.addProperty("startingPlayerIndex", 0);
        JsonArray players = new JsonArray();
        for (int seat = 0; seat < 2; seat++) {
            JsonObject player = NativeSession.object("name", "Deck seat " + seat);
            JsonArray cards = new JsonArray();
            for (int i = 0; i < 60; i++) cards.add(NativeSession.object("name", "Forest"));
            player.add("deck", cards);
            player.add("sideboard", new JsonArray());
            players.add(player);
        }
        request.add("players", players);
        return request;
    }

    private static void promoPrintings(NativeGuiBase base) {
        JsonObject request = config();
        JsonObject owner = request.getAsJsonArray("players").get(0).getAsJsonObject();
        JsonArray cards = new JsonArray();
        for (String[] printing : new String[][] {
                {"Marsh Flats", "PMH2", "248s"}, {"Meticulous Archive", "PMKM", "264p"},
                {"Psychic Frog", "PMH3", "199s"}, {"Hedge Maze", "PMKM", "262s"},
                {"Superior Spider-Man", "PSPM", "155s"},
                {"Psychic Frog", "PMH3", "199p"}, {"Psychic Frog", "MH3", "199"},
                {DISCIPLE, "PMH3", "250s"}}) {
            JsonObject card = NativeSession.object("name", printing[0]);
            card.addProperty("setCode", printing[1]);
            card.addProperty("collectorNumber", printing[2]);
            cards.add(card);
        }
        for (int i = 0; i < cards.size(); i++) owner.getAsJsonArray("deck").set(i, cards.get(i));
        owner.add("sideboard", cards.deepCopy());
        try (NativeSession session = new NativeSession(request, base); var scope = session.context.enter()) {
            base.setTestSession(session);
            var player = session.game.getRegisteredPlayers().get(0);
            Deck deck = player.getRegisteredPlayer().getDeck();
            for (DeckSection section : List.of(DeckSection.Main, DeckSection.Sideboard)) {
                check(deck.get(section).countAll() == (section == DeckSection.Main ? 60 : cards.size()),
                        "Promo mapping changed deck counts");
                check(deck.get(section).toFlatList().stream()
                        .filter(card -> card.getName().equals("Psychic Frog")).distinct().count() == 3,
                        "Promo pack, prerelease and regular printings were merged");
                for (PaperCard paper : deck.get(section).toFlatList()) {
                    if (paper.getName().equals("Forest")) continue;
                    var physical = forge.game.card.Card.fromPaperCard(paper, player);
                    var identity = NativeSnapshot.identity(physical);
                    check(cards.asList().stream().map(JsonElement::getAsJsonObject).anyMatch(expected ->
                                    expected.get("name").getAsString().startsWith(identity.get("name").getAsString())
                                    && expected.get("setCode").equals(identity.get("setCode"))
                                    && expected.get("collectorNumber").equals(identity.get("cardNumber"))),
                            "Promo display identity changed: " + identity);
                }
            }
            session.start();
            check(!session.prompt(0).isEmpty(), "Promo deck did not reach its initial decision");
            check(!session.snapshot(1).contains("Psychic Frog") && !session.snapshot(-1).contains("Psychic Frog"),
                    "Private promo identities leaked during startup");
        }
    }

    private static void treatmentPrintings(NativeGuiBase base) {
        JsonObject request = config();
        JsonObject owner = request.getAsJsonArray("players").get(0).getAsJsonObject();
        JsonArray cards = new JsonArray();
        for (String[] printing : new String[][] {
                {"Ensnaring Bridge", "7ED", "294★"}, {"Ensnaring Bridge", "7ED", "294"},
                {"Liquimetal Coating", "BRR", "91z"}, {"Liquimetal Coating", "BRR", "91"}}) {
            JsonObject card = NativeSession.object("name", printing[0]);
            card.addProperty("setCode", printing[1]);
            card.addProperty("collectorNumber", printing[2]);
            cards.add(card);
        }
        for (int i = 0; i < cards.size(); i++) owner.getAsJsonArray("deck").set(i, cards.get(i));
        owner.add("sideboard", cards.deepCopy());
        try (NativeSession session = new NativeSession(request, base); var scope = session.context.enter()) {
            base.setTestSession(session);
            var player = session.game.getRegisteredPlayers().get(0);
            Deck deck = player.getRegisteredPlayer().getDeck();
            for (DeckSection section : List.of(DeckSection.Main, DeckSection.Sideboard)) {
                var registered = deck.get(section).toFlatList();
                for (JsonElement entry : cards) {
                    JsonObject expected = entry.getAsJsonObject();
                    String number = expected.get("collectorNumber").getAsString();
                    PaperCard paper = registered.stream().filter(card -> card.getName().equals(
                            expected.get("name").getAsString()) && card.getCollectorNumber().equals(number))
                            .findFirst().orElseThrow(() -> new AssertionError("Treatment merged or missing: " + expected));
                    boolean special = number.endsWith("★") || number.endsWith("z");
                    check(!special || paper.isFoil(), "Foil treatment lost native foil state");
                    var physical = forge.game.card.Card.fromPaperCard(paper, player);
                    var identity = NativeSnapshot.identity(physical);
                    check(expected.get("setCode").equals(identity.get("setCode"))
                            && expected.get("collectorNumber").equals(identity.get("cardNumber")),
                            "Special treatment display identity changed: " + identity);
                }
            }
            session.start();
            check(!session.prompt(0).isEmpty(), "Special-treatment deck did not start");
            check(!session.snapshot(1).contains("Ensnaring Bridge")
                    && !session.snapshot(-1).contains("Liquimetal Coating"), "Treatment identities leaked");
        }
    }

    private static void registerAndStart(NativeGuiBase base) {
        JsonObject request = config();
        JsonObject owner = request.getAsJsonArray("players").get(0).getAsJsonObject();
        JsonArray cards = new JsonArray();
        JsonObject disciple = NativeSession.object("name", DISCIPLE);
        disciple.addProperty("setCode", "MH3");
        disciple.addProperty("collectorNumber", "250");
        cards.add(disciple);
        JsonObject turntimber = NativeSession.object("name", TURNTIMBER);
        turntimber.addProperty("setCode", "ZNR");
        turntimber.addProperty("collectorNumber", "215");
        cards.add(turntimber);
        JsonObject setOnly = turntimber.deepCopy();
        setOnly.remove("collectorNumber");
        cards.add(setOnly);
        JsonObject forest = NativeSession.object("name", "Forest");
        forest.addProperty("setCode", "m21");
        forest.addProperty("collectorNumber", "272");
        cards.add(forest);
        JsonObject alias = NativeSession.object("name", "Forest");
        alias.addProperty("setCode", "te");
        alias.addProperty("collectorNumber", "347");
        cards.add(alias);
        for (String name : List.of("Fable of the Mirror-Breaker // Reflection of Kiki-Jiki",
                "Bonecrusher Giant // Stomp", "Fire // Ice", "Dusk // Dawn", "Forest"))
            cards.add(NativeSession.object("name", name));
        JsonArray main = owner.getAsJsonArray("deck");
        for (int i = 0; i < cards.size(); i++) main.set(i, cards.get(i).deepCopy());
        owner.add("sideboard", cards.deepCopy());
        try (NativeSession session = new NativeSession(request, base)) {
            base.setTestSession(session);
            Deck deck = session.game.getRegisteredPlayers().get(0).getRegisteredPlayer().getDeck();
            for (DeckSection section : List.of(DeckSection.Main, DeckSection.Sideboard)) {
                List<PaperCard> registered = deck.get(section).toFlatList();
                checkPrinting(registered, "Disciple of Freyalise", "MH3", "250");
                checkPrinting(registered, "Turntimber Symbiosis", "ZNR", "215");
                checkPrinting(registered, "Forest", "M21", "272");
                checkPrinting(registered, "Forest", "TMP", "347");
                for (String name : List.of("Fable of the Mirror-Breaker", "Bonecrusher Giant",
                        "Fire // Ice", "Dusk // Dawn", "Forest"))
                    check(registered.stream().anyMatch(card -> card.getName().equals(name)),
                            "Lost native card name in " + section + ": " + name);
                check(deck.get(section).countAll() == (section == DeckSection.Main ? 60 : cards.size()),
                        "Deck registration changed the section count");
            }
            session.start();
            check(!session.prompt(0).isEmpty(), "No initial decision after multiface deck startup");
            check(!session.snapshot(1).contains("Disciple of Freyalise")
                    && !session.snapshot(-1).contains("Disciple of Freyalise"),
                    "Private deck identity leaked during startup");
        }
    }

    private static void limited(NativeGuiBase base) {
        for (String variant : List.of("Limited", "Sealed", "Draft", "Cube")) {
            JsonObject request = config();
            request.addProperty("variant", variant);
            for (JsonElement element : request.getAsJsonArray("players")) {
                JsonObject player = element.getAsJsonObject();
                JsonArray main = new JsonArray();
                JsonArray side = new JsonArray();
                for (int i = 0; i < 40; i++) main.add(NativeSession.object("name", "Forest"));
                for (int i = 0; i < 44; i++) side.add(NativeSession.object("name", "Grizzly Bears"));
                player.add("deck", main);
                player.add("sideboard", side);
            }
            try (NativeSession session = new NativeSession(request, base)) {
                base.setTestSession(session);
                var type = session.game.getMatch().getRules().getGameType();
                check(type.isCardPoolLimited() && type.getDeckFormat().getMainRange().getMinimum() == 40,
                        "Limited match inherited Constructed deck rules");
                session.start();
                check(!session.prompt(0).isEmpty(), "Limited match did not reach human input");
                for (var player : session.game.getRegisteredPlayers()) {
                    check(player.getCardsIn(forge.game.zone.ZoneType.Sideboard).size() == 44,
                            "Limited sideboard was truncated or lost");
                    check(player.getCardsIn(forge.game.zone.ZoneType.Library).size()
                            + player.getCardsIn(forge.game.zone.ZoneType.Hand).size() == 40,
                            "Limited library and hand no longer conserve the submitted deck");
                }
                check(!session.snapshot(1).contains("Grizzly Bears")
                        && !session.snapshot(-1).contains("Grizzly Bears"),
                        "Limited sideboard identities leaked before a public game action");
            }
        }
    }

    private static void limitedCompanion(NativeGuiBase base) {
        for (String variant : List.of("Limited", "Constructed")) {
            JsonObject request = config();
            request.addProperty("variant", variant);
            request.getAsJsonArray("players").get(0).getAsJsonObject().getAsJsonArray("sideboard")
                    .add(NativeSession.object("name", "Yorion, Sky Nomad"));
            try (NativeSession session = new NativeSession(request, base)) {
                base.setTestSession(session);
                session.start();
                String initial = session.prompt(0);
                check(initial.contains("Yorion, Sky Nomad") == variant.equals("Limited"),
                        "Yorion must require 60 cards in Limited and 80 in Constructed: " + initial);
                check(!session.snapshot(1).contains("Yorion") && !session.snapshot(-1).contains("Yorion"),
                        "Unselected companion leaked from the private sideboard");
            }
        }
    }

    private static void commanders(NativeGuiBase base) {
        for (boolean fullDeckName : List.of(false, true)) {
            JsonObject request = config();
            request.addProperty("variant", "Commander");
            for (JsonElement element : request.getAsJsonArray("players")) {
                JsonObject player = element.getAsJsonObject();
                player.getAsJsonArray("deck").set(0, NativeSession.object("name",
                        fullDeckName ? ESIKA : "Esika, God of the Tree"));
                JsonArray commanders = new JsonArray();
                commanders.add(fullDeckName ? "Esika, God of the Tree" : ESIKA);
                player.add("commanderNames", commanders);
            }
            try (NativeSession session = new NativeSession(request, base)) {
                for (var player : session.game.getRegisteredPlayers()) {
                    Deck deck = player.getRegisteredPlayer().getDeck();
                    check(deck.getMain().countAll() == 59 && deck.get(DeckSection.Commander).countAll() == 1,
                            "Commander was not moved out of the main deck exactly once");
                    check(deck.get(DeckSection.Commander).toFlatList().get(0).getName().equals("Esika, God of the Tree"),
                            "Combined commander name resolved to a different card");
                }
            }
        }
    }

    private static void rejectWrongFaces(NativeGuiBase base) {
        for (String name : List.of("Disciple of Freyalise // Forest", "Forest // Island",
                "Missing native card // Garden of Freyalise")) {
            JsonObject request = config();
            request.getAsJsonArray("players").get(0).getAsJsonObject().getAsJsonArray("deck")
                    .set(0, NativeSession.object("name", name));
            try (NativeSession ignored = new NativeSession(request, base)) {
                throw new AssertionError("Accepted an unrelated or missing card face");
            } catch (IllegalArgumentException expected) {
                check(expected.getMessage().equals("Requested card printing is unavailable"),
                        "Unexpected rejection or private card name in error");
            }
        }
    }

    private static void rejectUnavailablePrintings(NativeGuiBase base) {
        for (String section : List.of("deck", "sideboard")) {
            for (String[] printing : new String[][] {
                    {"Forest", "M21", "999999"}, {"Forest", "ZZZZ", "272"},
                    {"Psychic Frog", "PMH3", "999999s"}, {"Forest", "PMH3", "199s"},
                    {"Psychic Frog", "PMH3", "199x"}, {"Psychic Frog", "PMH3", "199"},
                    {"Ensnaring Bridge", "7ED", "295★"}, {"Forest", "7ED", "294★"},
                    {"Ensnaring Bridge", "8ED", "300★"}, {"Ensnaring Bridge", "7ED", "294z"},
                    {"Liquimetal Coating", "BRR", "92z"}, {"Forest", "BRR", "91z"},
                    {"Liquimetal Coating", "SOM", "171z"}, {"Liquimetal Coating", "BRR", "91★"},
                    {TURNTIMBER, "ZNR", "999999"}}) {
                JsonObject request = config();
                JsonObject card = NativeSession.object("name", printing[0]);
                card.addProperty("setCode", printing[1]);
                card.addProperty("collectorNumber", printing[2]);
                JsonArray cards = request.getAsJsonArray("players").get(0).getAsJsonObject()
                        .getAsJsonArray(section);
                if (cards.isEmpty()) cards.add(card);
                else cards.set(0, card);
                try (NativeSession ignored = new NativeSession(request, base)) {
                    throw new AssertionError("Silently substituted an unavailable " + section
                            + " printing: " + String.join(" | ", printing));
                } catch (IllegalArgumentException expected) {
                    check(expected.getMessage().equals("Requested card printing is unavailable"),
                            "Unexpected printing rejection or private card name in error");
                }
            }
        }
    }

    private static void checkPrinting(List<PaperCard> cards, String name, String set, String number) {
        check(cards.stream().anyMatch(card -> card.getName().equals(name)
                && card.getEdition().equals(set) && card.getCollectorNumber().equals(number)),
                "Lost requested printing: " + name);
    }

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
