// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import forge.deck.Deck;
import forge.game.*;
import forge.game.player.RegisteredPlayer;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicReference;
import static org.hexproof.forge.NativeCallbackRegressionTest.require;

/** Offline paired-deck measurements; this is deliberately not a production two-AI API. */
public final class NativeAiCalibration {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        JsonArray results = new JsonArray();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                prefs.setPref(FPref.UI_ENABLE_AI_CHEATS, false);
                return null;
            });
            for (String deck : List.of("green", "red"))
                for (var pair : List.of(List.of("easy", "normal"), List.of("easy", "hard"), List.of("normal", "hard")))
                    for (var seats : List.of(pair, List.of(pair.get(1), pair.get(0))))
                        for (long seed : List.of(42L, 43L))
                            for (int starts = 0; starts < 2; starts++) {
                                results.add(play(deck, seats, seed, starts));
                                Files.writeString(Path.of(args[1]), NativeHost.JSON.toJson(results) + "\n");
                            }
        }
        Files.writeString(Path.of(args[1]), NativeHost.JSON.toJson(results) + "\n");
        System.out.println("PASS native AI calibration: " + results.size() + " completed paired games");
    }

    private static JsonObject play(String deckName, List<String> tiers, long seed, int starts) throws Exception {
        long started = System.nanoTime();
        JsonObject result = new JsonObject();
        try (NativeExecution context = new NativeExecution(seed, error -> { throw new IllegalStateException(error); });
             var scope = context.enter()) {
            List<RegisteredPlayer> players = new ArrayList<>();
            for (int seat = 0; seat < 2; seat++) {
                Deck deck = new Deck(deckName);
                String[] names = deckName.equals("green")
                        ? new String[]{"Forest", "Llanowar Elves", "Elvish Visionary", "Grizzly Bears", "Runeclaw Bear",
                            "Centaur Courser", "Giant Growth", "Colossal Dreadmaw", "Titanic Growth", "Snakeskin Veil"}
                        : new String[]{"Mountain", "Lightning Bolt", "Shock", "Goblin Arsonist", "Raging Goblin",
                            "Goblin Piker", "Goblin Instigator", "Lightning Strike", "Fireball", "Hill Giant"};
                for (int i = 0; i < names.length; i++) {
                    var card = FModel.getMagicDb().getCommonCards().getCard(names[i]);
                    require(card != null, "Missing benchmark card: " + names[i]);
                    deck.getMain().add(card, i == 0 ? 24 : 4);
                }
                players.add(new RegisteredPlayer(deck).setPlayer(new NativeAiLobby(tiers.get(seat), tiers.get(seat), starts)));
            }
            Match match = new Match(new GameRules(GameType.Constructed), players, "Hexproof AI calibration");
            Game game = match.createGame();
            AtomicReference<Thread> gameThread = new AtomicReference<>();
            var running = context.gameExecutor().submit(() -> {
                gameThread.set(Thread.currentThread());
                match.startGame(game);
            });
            try { running.get(120, TimeUnit.SECONDS); }
            catch (TimeoutException error) {
                System.err.println("Calibration timeout: " + deckName + " " + tiers + " " + seed + "/" + starts
                        + " at turn " + game.getPhaseHandler().getTurn() + " " + game.getPhaseHandler().getPhase());
                if (gameThread.get() != null) for (var frame : gameThread.get().getStackTrace()) System.err.println(frame);
                throw error;
            }
            require(game.isGameOver() && game.getOutcome() != null, "Benchmark did not reach a native outcome");
            int winner = players.indexOf(game.getOutcome().getWinningPlayer());
            result.addProperty("deck", deckName);
            result.add("tiers", NativeHost.JSON.toJsonTree(tiers));
            result.addProperty("seed", seed);
            result.addProperty("startingSeat", starts);
            result.addProperty("winnerSeat", winner);
            result.addProperty("turns", game.getPhaseHandler().getTurn());
            result.addProperty("milliseconds", TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started));
            System.out.println(result);
            context.close();
            require(context.awaitClosed(2000), "Benchmark AI workers did not stop");
        }
        return result;
    }
}
