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
            registerAndStart(base);
            commanders(base);
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

    private static void checkPrinting(List<PaperCard> cards, String name, String set, String number) {
        check(cards.stream().anyMatch(card -> card.getName().equals(name)
                && card.getEdition().equals(set) && card.getCollectorNumber().equals(number)),
                "Lost requested printing: " + name);
    }

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
