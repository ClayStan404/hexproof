// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.card.MagicColor;
import forge.game.card.Card;
import forge.game.card.CardCollection;
import forge.game.mana.Mana;
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.player.PlaySpellAbility;
import forge.game.zone.ZoneType;
import forge.gamemodes.match.input.InputPassPriority;
import forge.gamemodes.match.input.InputSyncronizedBase;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import forge.player.PlayerControllerHuman;
import java.util.List;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import static org.hexproof.forge.NativeCallbackRegressionTest.*;

/** Casts actual Emrakul, then concedes while her controlled turn has a live input. */
public final class NativeControlledConcedeRegressionTest {
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
            for (String scenario : args.length > 1 ? List.of(args[1])
                    : List.of("controlled-priority", "controller-priority", "controlled-menu", "controller-menu")) {
                for (int masterSeat : List.of(0, 1)) run(base, scenario, masterSeat);
            }
        }
    }

    private static void run(NativeGuiBase base, String scenario, int masterSeat) throws Exception {
        JsonObject setup = NativeIsolationRegressionTest.setup("emrakul-concede-" + scenario + "-" + masterSeat, 42);
        setup.addProperty("startingPlayerIndex", masterSeat);
        ExecutorService rpc = Executors.newSingleThreadExecutor();
        try (NativeSession session = new NativeSession(setup, base); var scope = session.context.enter()) {
            base.setTestSession(session);
            Player master = session.game.getRegisteredPlayers().get(masterSeat);
            Player controlled = session.game.getRegisteredPlayers().get(1 - masterSeat);
            session.start(() -> {
                session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, master, false, 1);
                Card emrakul = card(session.game, master, "Emrakul, the Promised End", ZoneType.Hand);
                for (int i = 0; i < 13; i++)
                    master.getManaPool().addMana(new Mana(MagicColor.COLORLESS, emrakul, null, master));
                require(PlaySpellAbility.playSpellAbility((PlayerControllerHuman) master.getController(), master,
                        emrakul.getSpellAbilities().get(0)), "Actual Emrakul cast failed");
            });
            for (int decisions = 0; ; decisions++) {
                require(decisions < 100 && !session.game.isGameOver(), "Emrakul did not reach the controlled turn");
                JsonObject envelope = prompt(session);
                JsonObject input = envelope.getAsJsonObject("input");
                if (controlled.isControlled() && session.game.getPhaseHandler().getPlayerTurn() == controlled
                        && session.game.getPhaseHandler().getPriorityPlayer() == controlled
                        && input.get("type").getAsString().equals("chooseAction")) {
                    require(controlled.getControllingPlayer() == master, "Emrakul chose the wrong controller");
                    require(envelope.get("decidingPlayerId").getAsString().equals(session.playerId(master)),
                            "Controlled turn decision was not routed to its controller");
                    break;
                }
                answer(session, input, controlled);
            }

            PlayerControllerHuman temporary = (PlayerControllerHuman) controlled.getController();
            var waiting = temporary.getInputProxy().getInput();
            require(waiting instanceof InputPassPriority && ((InputSyncronizedBase) waiting).isAwaitingInput(),
                    "Controlled priority was not suspended in its temporary input queue");
            AtomicBoolean menuReturned = new AtomicBoolean();
            CountDownLatch menuUnwound = new CountDownLatch(1);
            if (scenario.endsWith("-menu")) {
                // An actual synchronous GUI callback can sit above the native
                // priority queue. Terminal concession must release both waits.
                long prior = prompt(session).get("promptId").getAsLong();
                session.later(() -> {
                    try {
                        temporary.arrangeForScry(new CardCollection(List.of(
                                controlled.getCardsIn(ZoneType.Library).get(0))));
                        menuReturned.set(true);
                    } finally { menuUnwound.countDown(); }
                });
                long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2);
                while (prompt(session).get("promptId").getAsLong() == prior) {
                    require(System.nanoTime() < deadline, "Controlled synchronous menu did not open");
                    Thread.sleep(1);
                }
                require(prompt(session).getAsJsonObject("input").get("type").getAsString().equals("scry"),
                        "Controlled synchronous callback did not publish scry");
            }
            int departing = scenario.startsWith("controlled-") ? session.index(controlled) : masterSeat;
            JsonObject concede = NativeSession.object("type", "directive");
            concede.addProperty("player", departing);
            concede.add("directive", NativeSession.object("type", "concede"));
            try {
                rpc.submit(() -> session.submit(concede)).get(2, TimeUnit.SECONDS);
            } catch (TimeoutException error) {
                throw new AssertionError("Concession left controlled input blocked: gameOver=" + session.game.isGameOver()
                        + ", waiting=" + ((InputSyncronizedBase) waiting).isAwaitingInput(), error);
            }
            require(session.gameOver() && !session.hasFailed(), "Concession failed instead of publishing the native result");
            require(!((InputSyncronizedBase) waiting).isAwaitingInput(), "Temporary controller input survived game over");
            require(!controlled.isControlled(), "Native game over retained player control");
            if (scenario.endsWith("-menu")) {
                require(menuUnwound.await(2, TimeUnit.SECONDS) && !menuReturned.get(),
                        "Concession did not cancel the controlled menu without inventing an answer");
            }
            for (int viewer : List.of(-1, 0, 1)) {
                JsonObject snapshot = JsonParser.parseString(session.snapshot(viewer)).getAsJsonObject();
                require(snapshot.get("gameOver").getAsBoolean(), "Terminal snapshot not published to every viewer");
                require(snapshot.getAsJsonArray("players").get(departing).getAsJsonObject()
                        .get("status").getAsString().equals("conceded"), "Concession was applied to the wrong seat");
                require(snapshot.get("winnerId").getAsString().equals("player-" + (1 - departing)), "Wrong native winner");
            }
            require(session.prompt(0).isEmpty() && session.prompt(1).isEmpty(), "A decision survived terminal concession");
            System.out.println("PASS controlled concession " + scenario + " controller-seat=" + masterSeat);
        } finally {
            rpc.shutdownNow();
            require(rpc.awaitTermination(2, TimeUnit.SECONDS), "Concession RPC survived session teardown");
        }
    }

    private static JsonObject prompt(NativeSession session) {
        String raw = session.prompt(0);
        require(!raw.isEmpty(), "Stable native boundary has no prompt");
        return JsonParser.parseString(raw).getAsJsonObject();
    }

    private static void answer(NativeSession session, JsonObject input, Player target) {
        String type = input.get("type").getAsString();
        JsonObject output;
        switch (type) {
            case "mulligan" -> {
                output = NativeSession.object("type", "mulliganDecision"); output.addProperty("keep", true);
            }
            case "payManaCost" -> output = NativeSession.object("type", "pay");
            case "chooseBoardTargets" -> {
                output = NativeSession.object("type", "boardTargets");
                JsonObject chosen = NativeSession.object("kind", "player"); chosen.addProperty("id", session.playerId(target));
                JsonArray targets = new JsonArray(); targets.add(chosen); output.add("chosen", targets);
            }
            case "chooseAction" -> output = NativeSession.object("type", "pass");
            case "chooseAttackers" -> {
                output = NativeSession.object("type", "declareAttackers"); output.add("assignments", new JsonArray());
            }
            default -> throw new AssertionError("Unexpected Emrakul input: " + input);
        }
        JsonObject response = NativeSession.object("type", type); response.add("output", output);
        session.submit(response);
    }
}
