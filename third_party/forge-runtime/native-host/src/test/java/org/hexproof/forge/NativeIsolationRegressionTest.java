// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.gui.GuiBase;
import forge.model.FModel;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.game.card.Card;
import forge.game.zone.ZoneType;
import forge.game.card.CounterCustomType;
import forge.util.MyRandom;
import java.lang.ref.WeakReference;
import java.util.*;
import java.util.concurrent.*;
import static org.hexproof.forge.NativeCallbackRegressionTest.require;

/** Positive replacements for the earlier shared-JVM interference probes. */
public final class NativeIsolationRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                prefs.setPref(FPref.UI_SELECT_FROM_CARD_DISPLAYS, false);
                prefs.setPref(FPref.YIELD_AUTO_PASS_NO_ACTIONS, false);
                return null;
            });
            randomAndCaches(base);
            blockedMenu(base);
            waitingRefreshes(base);
            failureAndCleanup(base);
        }
        System.out.println("PASS native shared isolation: RNG, IDs, custom counters, blocked menus, failure ownership, cancellation and collection");
    }

    static JsonObject setup(String id, long seed) {
        JsonObject config = NativeSession.object("gameId", id);
        config.addProperty("seed", seed); config.addProperty("variant", "constructed");
        config.addProperty("startingLife", 20); config.addProperty("startingPlayerIndex", 0);
        JsonArray players = new JsonArray();
        for (int seat = 0; seat < 2; seat++) {
            JsonObject player = NativeSession.object("name", id + "-" + seat);
            JsonArray deck = new JsonArray();
            for (int i = 0; i < 60; i++) deck.add(NativeSession.object("name", i < 24 ? "Forest" : "Elvish Visionary"));
            player.add("deck", deck); players.add(player);
        }
        config.add("players", players); return config;
    }
    private static String kind(NativeSession session) {
        return JsonParser.parseString(session.prompt(0)).getAsJsonObject().getAsJsonObject("input").get("type").getAsString();
    }
    private static void answer(NativeSession session, String type, JsonObject output) {
        JsonObject response = NativeSession.object("type", type); response.add("output", output); session.submit(response);
    }
    private static void keep(NativeSession session) {
        JsonObject output = NativeSession.object("type", "mulliganDecision"); output.addProperty("keep", true);
        answer(session, "mulligan", output);
    }
    private static List<Integer> library(NativeSession session) {
        return session.game.getPlayers().get(0).getCardsIn(ZoneType.Library).stream().map(Card::getId).toList();
    }

    private static void randomAndCaches(NativeGuiBase base) throws Exception {
        try (NativeSession first = new NativeSession(setup("random-A", 42), base);
             NativeSession second = new NativeSession(setup("random-B", 99), base)) {
            first.start();
            var owner = first.game.getPlayers().get(0);
            List<Card> original = new ArrayList<>(owner.getCardsIn(ZoneType.Library));
            first.context.andWait(() -> { MyRandom.setRandom(new Random(987)); owner.shuffle(null); });
            var control = library(first);
            Random random = new Random(987);
            first.context.andWait(() -> {
                owner.getZone(ZoneType.Library).setCards(original); MyRandom.setRandom(random);
                CounterCustomType.get("Isolation-A");
            });
            second.start();
            second.context.andWait(() -> {
                require(CounterCustomType.getValues().stream().noneMatch(c -> c.getName().equals("Isolation-A")),
                        "Another game's custom counter escaped its scope");
                require(second.context.nextId("probe") == 1, "Second game inherited another counter");
            });
            first.context.andWait(() -> {
                require(MyRandom.getRandom() == random, "Second game replaced the first RNG");
                require(first.context.nextId("probe") == 1, "Object IDs are process-global");
                owner.shuffle(null);
            });
            require(control.equals(library(first)), "Concurrent game changed an actual library shuffle");
        }
    }

    private static void blockedMenu(NativeGuiBase base) throws Exception {
        try (NativeSession first = new NativeSession(setup("blocked-A", 42), base);
             NativeSession second = new NativeSession(setup("blocked-B", 99), base)) {
            first.start(() -> {
                try { base.andWait(() -> first.guis.get(0).proxy().getInteger("Isolation menu", 1, 10, false)); }
                catch (Exception error) { throw new CompletionException(error); }
            });
            second.start();
            while (kind(first).equals("mulligan")) keep(first);
            require(kind(first).equals("chooseNumber"), "First game did not block inside a real GUI menu");
            CompletableFuture.runAsync(() -> keep(second)).get(2, TimeUnit.SECONDS);
            require(kind(first).equals("chooseNumber") && !second.prompt(0).isEmpty(), "One game's menu stalled another game");
            JsonObject output = NativeSession.object("type", "numberDecision"); output.addProperty("chosenNumber", 7);
            answer(first, "chooseNumber", output);
        }
    }

    private static void waitingRefreshes(NativeGuiBase base) throws Exception {
        try (NativeSession session = new NativeSession(setup("waiting-refreshes", 52), base);
             var scope = session.context.enter()) {
            for (int i = 0; i < 1000; i++) {
                for (NativeGuiGame gui : session.guis)
                    gui.human.getInputQueue().getActualInput(gui.human).showMessageInitial();
            }
            require(!session.hasFailed(), "Rapid waiting refreshes exhausted the game's timer queue");
        }
    }

    private static void failureAndCleanup(NativeGuiBase base) throws Exception {
        try (NativeSession first = new NativeSession(setup("failure-A", 42), base);
             NativeSession second = new NativeSession(setup("failure-B", 99), base)) {
            first.start(); second.start();
            first.context.later(() -> { throw new IllegalStateException("Injected owned callback failure"); });
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2);
            while (!first.hasFailed() && System.nanoTime() < deadline) Thread.sleep(5);
            require(first.hasFailed() && !second.hasFailed(), "Callback failure reached the wrong game");
            first.close(); require(first.context.awaitClosed(2000), "Failed game's tasks did not stop");
            keep(second);
            require(!second.hasFailed() && !second.prompt(0).isEmpty(), "Closed game poisoned its neighbor");
        }
        List<WeakReference<NativeSession>> references = new ArrayList<>();
        for (int i = 0; i < 8; i++) references.add(closedGame(base, i));
        for (int attempt = 0; attempt < 20 && references.stream().anyMatch(ref -> ref.get() != null); attempt++) {
            System.gc(); Thread.sleep(50);
        }
        require(references.stream().allMatch(ref -> ref.get() == null), "Closed sessions retained by worker callbacks or caches");
    }
    private static WeakReference<NativeSession> closedGame(NativeGuiBase base, int index) throws Exception {
        NativeSession session = new NativeSession(setup("closed-" + index, index), base);
        session.start(); session.close();
        require(session.context.awaitClosed(2000), "Opening-hand abort leaked a game thread");
        return new WeakReference<>(session);
    }
}
