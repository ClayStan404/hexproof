// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.game.ability.AbilityFactory;
import forge.game.card.Card;
import forge.game.spellability.AbilitySub;
import forge.game.spellability.SpellAbility;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import java.util.List;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import static org.hexproof.forge.NativeCallbackRegressionTest.require;

/** Resolves actual native stack effects while their controller or source owner departs. */
public final class NativeObjectDepartureRegressionTest {
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
            List<String> scenarios = args.length > 1 ? List.of(args[1]) : List.of(
                    "controller-number", "controller-name-edt",
                    "nested-controller-number", "nested-controller-name-edt",
                    "owner-spell-number", "owner-ability-number",
                    "controller-repeat-number", "stale-candidate-number", "stale-candidate-number-edt");
            for (String scenario : scenarios) try (NativeGuiBase scenarioBase = new NativeGuiBase(args[0])) {
                GuiBase.setInterface(scenarioBase.proxy());
                run(scenarioBase, scenario);
            }
        }
    }

    private static void run(NativeGuiBase base, String scenario) throws Exception {
        boolean naming = scenario.contains("name");
        boolean edt = scenario.endsWith("-edt");
        boolean nested = scenario.startsWith("nested");
        boolean ownerDeparture = scenario.startsWith("owner");
        boolean spell = scenario.contains("-spell-");
        boolean surviving = scenario.equals("owner-ability-number");
        boolean repeated = scenario.contains("-repeat-");
        boolean stale = scenario.startsWith("stale");
        JsonObject config = NativeSession.object("gameId", "object-departure-" + scenario);
        config.addProperty("seed", 42);
        config.addProperty("variant", "constructed");
        config.addProperty("startingLife", 20);
        config.addProperty("startingPlayerIndex", 0);
        JsonArray players = new JsonArray();
        for (int seat = 0; seat < 4; seat++) {
            JsonObject player = NativeSession.object("name", "Object seat " + seat);
            JsonArray deck = new JsonArray();
            for (int card = 0; card < 60; card++) deck.add(NativeSession.object("name", "Forest"));
            player.add("deck", deck);
            players.add(player);
        }
        config.add("players", players);
        AtomicBoolean resolved = new AtomicBoolean();
        CountDownLatch unwound = new CountDownLatch(1);
        ExecutorService rpc = Executors.newSingleThreadExecutor();
        try (NativeSession session = new NativeSession(config, base)) {
            base.setFailureHandler(session::fail);
            Runnable resolve = () -> {
                try {
                    var owner = session.game.getRegisteredPlayers().get(2);
                    var controller = session.game.getRegisteredPlayers().get(ownerDeparture ? 3 : 2);
                    var target = session.game.getRegisteredPlayers().get(0);
                    Card source = NativeCallbackRegressionTest.card(session.game, owner,
                            spell ? "Lightning Bolt" : "Pithing Needle", spell ? ZoneType.Hand : ZoneType.Battlefield);
                    if (spell) source = session.game.getAction().moveToStack(source, null);
                    source.setController(controller, session.game.getNextTimestamp());
                    String effect = naming ? "NameCard | ChooseFromList$ Pithing Needle,Lightning Bolt"
                            : "ChooseNumber | Min$ 1 | Max$ 2147483647";
                    if (repeated) source.setSVar("RepeatDecision", "DB$ " + effect + " | Defined$ Targeted");
                    SpellAbility ability = AbilityFactory.getAbility((spell ? "SP$ " : "AB$ ")
                            + (repeated ? "Repeat | MaxRepeat$ 2 | RepeatSubAbility$ RepeatDecision" : effect)
                            + " | Cost$ 0 | ValidTgts$ Player", source);
                    ability.setActivatingPlayer(controller);
                    ability.getTargets().add(target);
                    AbilitySub followup = (AbilitySub) AbilityFactory.getAbility(
                            "DB$ GainLife | Defined$ Targeted | LifeAmount$ 3", source);
                    ability.setSubAbility(followup);
                    session.game.getStack().add(ability);
                    session.game.getStack().resolveStack();
                    require(session.game.getStack().isEmpty() && !session.game.getStack().isResolving()
                            && !session.game.getStack().isFrozen(), "Departure retained native stack transaction state");
                    if (surviving || stale) {
                        require(source.hasChosenNumber() && source.getChosenNumber() == 7,
                                "Surviving ability did not receive the explicit replacement answer");
                        require(target.getLife() == (stale ? 20 : 23), "Surviving ability applied its followup to the wrong players");
                    } else {
                        require(!source.hasChosenNumber() && source.getNamedCards().isEmpty(),
                                "Removed stack object received a fabricated choice or continued its effect");
                        require(target.getLife() == 20, "Removed stack object's followup effect resolved");
                    }
                    resolved.set(true);
                } finally { unwound.countDown(); }
            };
            Future<?> opening = rpc.submit(() -> session.start(() -> {
                if (!edt) resolve.run();
                else {
                    try { base.andWait(resolve); }
                    catch (Exception error) { throw new CompletionException(error); }
                }
            }));
            String expected = naming ? "chooseCardName" : "chooseNumber";
            JsonObject prompt = awaitPrompt(session);
            while (!inputType(prompt).equals(expected)) {
                require(inputType(prompt).equals("mulligan"), "Unexpected opening input: " + inputType(prompt));
                JsonObject keep = NativeSession.object("type", "mulliganDecision");
                keep.addProperty("keep", true);
                answer(session, "mulligan", keep);
                prompt = awaitPrompt(session);
            }
            opening.get(2, TimeUnit.SECONDS);
            require(prompt.get("decidingPlayerId").getAsString().equals("player-0"), "Effect skipped its target's decision");
            if (nested || stale) {
                rpc.submit(() -> concede(session, 0)).get(2, TimeUnit.SECONDS);
                prompt = awaitPrompt(session);
                require(prompt.get("decidingPlayerId").getAsString().equals("player-2"),
                        "Original object's controller did not choose a replacement player");
                require(inputType(prompt).equals(edt ? "chooseFromSelection" : "chooseBoardTargets"),
                        "Nested test did not cross the intended native input dispatcher");
            }
            String beforeDeparture = prompt.toString();
            if (stale) {
                JsonObject originalChooser = prompt;
                rpc.submit(() -> concede(session, 1)).get(2, TimeUnit.SECONDS);
                require(session.prompt(0).equals(beforeDeparture), "Candidate departure silently chose a replacement");
                selectDepartedCandidate(session, originalChooser);
                JsonObject handoff = awaitPrompt(session);
                require(handoff.get("decidingPlayerId").getAsString().equals("player-3")
                                && inputType(handoff).equals(expected),
                        "Selecting a departed candidate did not rebuild the native replacement set");
                require(handoff.get("promptId").getAsLong() > originalChooser.get("promptId").getAsLong(),
                        "Rebuilt replacement decision reused a stale prompt id");
                require(!resolved.get(), "Native replacement chose a default number");
            } else {
                rpc.submit(() -> concede(session, 2)).get(2, TimeUnit.SECONDS);
            }
            if (surviving) {
                require(session.prompt(0).equals(beforeDeparture), "Source owner's departure cancelled an independently controlled ability");
            }
            if (surviving || stale) {
                JsonObject chosen = NativeSession.object("type", "numberDecision");
                chosen.addProperty("chosenNumber", 7);
                answer(session, expected, chosen);
            }
            require(unwound.await(2, TimeUnit.SECONDS) && resolved.get(), "Removed object or nested chooser retained the synchronous effect");
            require(!session.hasFailed() && !session.game.isGameOver(), "Nonterminal departure failed the native game");
            JsonObject priority = awaitPrompt(session);
            require(inputType(priority).equals("chooseAction"), "Remaining native game did not reach priority");
            require(session.player(priority.get("decidingPlayerId").getAsString()).isInGame(), "Native game published priority for a departed player");
            for (int seat : List.of(0, 1, 2)) if (session.game.getRegisteredPlayers().get(seat).isInGame()) {
                int departing = seat;
                rpc.submit(() -> concede(session, departing)).get(2, TimeUnit.SECONDS);
            }
            require(session.gameOver(), "Native object regression did not finish its cleanup game");
            System.out.println("PASS native object departure " + scenario);
        } finally {
            rpc.shutdownNow();
            require(rpc.awaitTermination(2, TimeUnit.SECONDS), "Object regression RPC survived teardown");
            require(unwound.await(2, TimeUnit.SECONDS), "Object regression callback survived teardown");
        }
    }

    private static String inputType(JsonObject envelope) {
        return envelope.getAsJsonObject("input").get("type").getAsString();
    }
    private static void selectDepartedCandidate(NativeSession session, JsonObject prompt) {
        JsonObject input = prompt.getAsJsonObject("input");
        if (inputType(prompt).equals("chooseBoardTargets")) {
            JsonObject output = NativeSession.object("type", "boardTargets");
            JsonArray selected = new JsonArray();
            JsonObject player = NativeSession.object("kind", "player");
            player.addProperty("id", "player-1");
            selected.add(player);
            output.add("chosen", selected);
            answer(session, "chooseBoardTargets", output);
        } else {
            int choice = -1;
            JsonArray options = input.getAsJsonArray("options");
            for (int index = 0; index < options.size(); index++) {
                if (options.get(index).getAsJsonObject().get("label").getAsString().contains("seat 1")) choice = index;
            }
            require(choice >= 0, "Stale candidate was absent from the original native menu");
            JsonObject output = NativeSession.object("type", "selectionDecision");
            JsonArray indices = new JsonArray();
            indices.add(choice);
            output.add("chosenIndices", indices);
            answer(session, "chooseFromSelection", output);
        }
    }
    private static JsonObject awaitPrompt(NativeSession session) throws Exception {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10);
        String prompt;
        while ((prompt = session.prompt(0)).isEmpty()) {
            if (System.nanoTime() > deadline) throw new AssertionError("Native object decision did not appear");
            Thread.sleep(5);
        }
        return JsonParser.parseString(prompt).getAsJsonObject();
    }
    private static void answer(NativeSession session, String type, JsonObject output) {
        JsonObject response = NativeSession.object("type", type);
        response.add("output", output);
        session.submit(response);
    }
    private static void concede(NativeSession session, int player) {
        JsonObject response = NativeSession.object("type", "directive");
        response.addProperty("player", player);
        response.add("directive", NativeSession.object("type", "concede"));
        session.submit(response);
    }
}
