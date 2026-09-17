// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.game.card.Card;
import forge.game.zone.ZoneType;
import forge.util.MyRandom;
import java.io.PrintStream;
import java.util.*;
import java.util.concurrent.*;

/** Local negative controls: a PASS means the named sharing hazard was reproduced. */
public final class SharedJvmIsolationProbe {
    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    private static JsonObject setup(String id, long seed) {
        JsonObject config = NativeSession.object("gameId", id);
        config.addProperty("seed", seed);
        config.addProperty("variant", "constructed");
        config.addProperty("startingLife", 20);
        config.addProperty("startingPlayerIndex", 0);
        JsonArray players = new JsonArray();
        for (int seat = 0; seat < 2; seat++) {
            JsonObject player = NativeSession.object("name", id + "-seat-" + seat);
            JsonArray deck = new JsonArray();
            for (int count = 0; count < 60; count++)
                deck.add(NativeSession.object("name", count < 24 ? "Forest" : "Elvish Visionary"));
            player.add("deck", deck);
            players.add(player);
        }
        config.add("players", players);
        return config;
    }

    private static void answer(NativeSession session, String kind, JsonObject output) {
        JsonObject envelope = NativeSession.object("type", kind);
        envelope.add("output", output);
        session.submit(envelope);
    }

    private static void keep(NativeSession session) {
        JsonObject output = NativeSession.object("type", "mulliganDecision");
        output.addProperty("keep", true);
        answer(session, "mulligan", output);
    }

    private static String kind(NativeSession session) {
        return JsonParser.parseString(session.prompt(0)).getAsJsonObject()
                .getAsJsonObject("input").get("type").getAsString();
    }

    private static List<Integer> library(NativeSession session) {
        List<Integer> ids = new ArrayList<>();
        for (Card card : session.game.getRegisteredPlayers().get(0).getCardsIn(ZoneType.Library)) ids.add(card.getId());
        return ids;
    }

    private static void random(NativeGuiBase base, NativeSession first, NativeSession second, JsonObject result) throws Exception {
        first.start();
        var owner = first.game.getRegisteredPlayers().get(0);
        List<Card> original = new ArrayList<>(owner.getCardsIn(ZoneType.Library));
        base.andWait(() -> { MyRandom.setRandom(new Random(987)); owner.shuffle(null); });
        List<Integer> control = library(first);
        base.andWait(() -> {
            owner.getZone(ZoneType.Library).setCards(original);
            MyRandom.setRandom(new Random(987));
            owner.shuffle(null);
        });
        require(control.equals(library(first)), "Same seed/order did not reproduce the control shuffle");
        Random firstRandom = new Random(987);
        base.andWait(() -> { owner.getZone(ZoneType.Library).setCards(original); MyRandom.setRandom(firstRandom); });
        second.start();
        require(MyRandom.getRandom() != firstRandom, "Second session no longer replaces the shared RNG");
        base.andWait(() -> owner.shuffle(null));
        require(!control.equals(library(first)), "Second session did not affect first session's actual shuffle");
        result.addProperty("controlShuffleReproduced", true);
        result.addProperty("otherGameChangedShuffle", true);
    }

    private static void blocked(NativeGuiBase base, NativeSession first, NativeSession second, JsonObject result) throws Exception {
        first.start(() -> {
            try { base.andWait(() -> first.guis.get(0).proxy().getInteger("Isolation probe", 1, 10, false)); }
            catch (Exception error) { throw new CompletionException(error); }
        });
        second.start();
        while (kind(first).equals("mulligan")) keep(first);
        require(kind(first).equals("chooseNumber"), "First session did not reach the real synchronous GUI callback");
        require(kind(second).equals("mulligan"), "Second session lost its independent opening prompt");
        ExecutorService rpc = Executors.newSingleThreadExecutor();
        try {
            long started = System.nanoTime();
            Future<?> other = rpc.submit(() -> keep(second));
            boolean waiting = false;
            try { other.get(750, TimeUnit.MILLISECONDS); }
            catch (TimeoutException expected) { waiting = true; }
            require(waiting && second.prompt(0).isEmpty(), "Second session was not stalled behind the other game's input");
            result.addProperty("otherGameBlockedAtLeastMs", TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started));
            JsonObject output = NativeSession.object("type", "numberDecision");
            output.addProperty("chosenNumber", 7);
            answer(first, "chooseNumber", output);
            other.get(3, TimeUnit.SECONDS);
            require(!second.prompt(0).isEmpty(), "Second session failed to recover after the first menu answered");
            result.addProperty("otherGameRecoveredAfterAnswer", true);
        } finally { rpc.shutdownNow(); }
    }

    private static void failure(NativeGuiBase base, NativeSession first, NativeSession second, JsonObject result) throws Exception {
        first.start();
        second.start();
        CountDownLatch routed = new CountDownLatch(1);
        base.setFailureHandler(error -> { second.fail(error); routed.countDown(); });
        // This callback belongs to the first game, but the latest configured
        // handler belongs to the second game, exactly as in the naive host.
        base.later(() -> { throw new IllegalStateException("Injected callback failure in " + first.id); });
        require(routed.await(2, TimeUnit.SECONDS), "Injected callback did not reach the failure handler");
        require(!first.hasFailed() && second.hasFailed(), "Failure routing no longer reproduces the last-session hazard");
        result.addProperty("originGameMarkedFailed", first.hasFailed());
        result.addProperty("unrelatedGameMarkedFailed", second.hasFailed());
    }

    public static void main(String[] args) throws Exception {
        PrintStream output = System.out;
        System.setOut(System.err);
        SharedJvmHost host = new SharedJvmHost(args[0]);
        JsonObject result = NativeSession.object("scenario", args[1]);
        try (NativeGuiBase base = host.base;
             NativeSession first = new NativeSession(setup("isolation-A", 42), base);
             NativeSession second = new NativeSession(setup("isolation-B", 99), base)) {
            base.setFailureHandler(second::fail);
            switch (args[1]) {
                case "random" -> random(base, first, second, result);
                case "blocked-menu" -> blocked(base, first, second, result);
                case "failure-routing" -> failure(base, first, second, result);
                default -> throw new IllegalArgumentException("Unknown isolation probe");
            }
            result.addProperty("hazardReproduced", true);
            output.println(result);
        }
        System.exit(0);
    }
}
