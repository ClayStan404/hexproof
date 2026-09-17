// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.gamemodes.match.input.InputPassPriority;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import java.util.List;
import java.util.concurrent.*;
import static org.hexproof.forge.NativeCallbackRegressionTest.require;

/** Orders a stale presentation before an accepted action using actual native priority inputs. */
public final class NativeQueuedInputRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                prefs.setPref(FPref.YIELD_AUTO_PASS_NO_ACTIONS, false);
                return null;
            });
            for (String scenario : args.length > 1 ? List.of(args[1]) : List.of("pass", "concede")) {
                try (NativeGuiBase scenarioBase = new NativeGuiBase(args[0])) {
                    GuiBase.setInterface(scenarioBase.proxy());
                    run(scenarioBase, scenario);
                }
            }
        }
    }

    private static void run(NativeGuiBase base, String scenario) throws Exception {
        JsonObject config = NativeSession.object("gameId", "queued-input-" + scenario);
        config.addProperty("seed", 42);
        config.addProperty("variant", "constructed");
        config.addProperty("startingLife", 20);
        config.addProperty("startingPlayerIndex", 0);
        JsonArray players = new JsonArray();
        for (int seat = 0; seat < 4; seat++) {
            JsonObject player = NativeSession.object("name", "Queued seat " + seat);
            JsonArray deck = new JsonArray();
            for (int card = 0; card < 60; card++) deck.add(NativeSession.object("name", "Forest"));
            player.add("deck", deck);
            players.add(player);
        }
        config.add("players", players);
        ExecutorService rpc = Executors.newSingleThreadExecutor();
        CountDownLatch firstEntered = new CountDownLatch(1), releaseFirst = new CountDownLatch(1);
        CountDownLatch secondEntered = new CountDownLatch(1), releaseSecond = new CountDownLatch(1);
        try (NativeSession session = new NativeSession(config, base); var scope = session.context.enter()) {
            base.setTestSession(session);
            try {
                session.start();
                JsonObject prompt = prompt(session);
                while (inputType(prompt).equals("mulligan")) {
                    JsonObject keep = NativeSession.object("type", "mulliganDecision");
                    keep.addProperty("keep", true);
                    JsonObject response = NativeSession.object("type", "mulligan");
                    response.add("output", keep);
                    session.submit(response);
                    prompt = prompt(session);
                }
                require(inputType(prompt).equals("chooseAction"), "Opening did not reach actual native priority");
                // Finish all previously scheduled presentation before adding the explicit interleaving.
                base.andWait(() -> { });
                base.andWait(() -> { });
                prompt = prompt(session);
                var owner = session.player(prompt.get("decidingPlayerId").getAsString());
                var gui = session.guis.get(session.index(owner));
                var original = gui.human.getInputProxy().getInput();
                require(original instanceof InputPassPriority, "Fixture did not suspend a real InputPassPriority");
                long originalPromptId = prompt.get("promptId").getAsLong();

                base.later(() -> awaitGate(firstEntered, releaseFirst));
                require(firstEntered.await(2, TimeUnit.SECONDS), "First EDT gate did not start");
                // This normal GUI presentation queues renderInput ahead of the response's action.
                gui.proxy().showPromptMessage(owner.getView(), "Queued input regression");
                base.later(() -> awaitGate(secondEntered, releaseSecond));

                JsonObject response;
                if (scenario.equals("pass")) {
                    response = NativeSession.object("type", "chooseAction");
                    response.add("output", NativeSession.object("type", "pass"));
                } else {
                    require(scenario.equals("concede"), "Unknown queued input scenario");
                    response = concession(session.index(owner));
                }
                Future<String> submitted = rpc.submit(() -> session.submit(response));
                awaitPendingConsumed(session);
                releaseFirst.countDown();
                require(secondEntered.await(2, TimeUnit.SECONDS), "Stale render did not reach the second EDT gate");
                require(gui.human.getInputProxy().getInput() == original && owner.isInGame(),
                        "Native action executed before the held action gate");
                require(session.prompt(0).isEmpty(),
                        "Stale render republished an input whose response was accepted but not executed");
                require(!submitted.isDone(), "RPC returned a false input boundary before executing its accepted action");
                System.out.println("PASS queued boundary held before action " + scenario);

                releaseSecond.countDown();
                submitted.get(2, TimeUnit.SECONDS);
                require(!session.hasFailed() && !session.game.isGameOver(), "Queued action failed the ongoing native game");
                require(gui.human.getInputProxy().getInput() != original,
                        "Accepted action did not release the original native priority input");
                require(owner.isInGame() == scenario.equals("pass"), "Native concession state did not match the accepted action");
                JsonObject next = prompt(session);
                require(next.get("promptId").getAsLong() > originalPromptId,
                        "Accepted action did not publish a fresh native decision");
                require(session.player(next.get("decidingPlayerId").getAsString()).isInGame(),
                        "Following native priority belongs to a departed player");
                for (int seat : List.of(0, 1, 2)) {
                    if (session.game.getRegisteredPlayers().get(seat).isInGame()) session.submit(concession(seat));
                }
                require(session.gameOver(), "Queued input regression did not finish its cleanup game");
                System.out.println("PASS queued native input " + scenario);
            } finally {
                releaseFirst.countDown();
                releaseSecond.countDown();
            }
        } finally {
            rpc.shutdownNow();
            require(rpc.awaitTermination(2, TimeUnit.SECONDS), "Queued input RPC survived teardown");
        }
    }

    private static void awaitGate(CountDownLatch entered, CountDownLatch release) {
        entered.countDown();
        try {
            require(release.await(10, TimeUnit.SECONDS), "EDT test gate was not released");
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
            throw new AssertionError("EDT test gate interrupted", error);
        }
    }
    private static void awaitPendingConsumed(NativeSession session) throws Exception {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2);
        while (!session.prompt(0).isEmpty()) {
            require(System.nanoTime() < deadline, "RPC did not accept the original pending decision");
            Thread.sleep(1);
        }
    }
    private static JsonObject prompt(NativeSession session) {
        String raw = session.prompt(0);
        require(!raw.isEmpty(), "Stable native input boundary has no prompt");
        return JsonParser.parseString(raw).getAsJsonObject();
    }
    private static String inputType(JsonObject prompt) {
        return prompt.getAsJsonObject("input").get("type").getAsString();
    }
    private static JsonObject concession(int seat) {
        JsonObject response = NativeSession.object("type", "directive");
        response.addProperty("player", seat);
        response.add("directive", NativeSession.object("type", "concede"));
        return response;
    }
}
