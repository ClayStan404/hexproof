// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.card.MagicColor;
import forge.game.GameStage;
import forge.game.card.Card;
import forge.game.mana.Mana;
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.player.PlaySpellAbility;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import forge.player.PlayerControllerHuman;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import static org.hexproof.forge.NativeCallbackRegressionTest.*;

/** Real native decisions, look permissions and turn sequencing on isolated boards. */
public final class NativeTurnAccessRegressionTest {
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
            List<String> scenarios = args.length > 1 ? List.of(args[1])
                    : List.of("control-human", "control-ai", "chocobo", "promised-turns", "aeons-turns", "arrival");
            for (String scenario : scenarios) {
                JsonObject setup = scenario.equals("control-ai") ? NativeAiRegressionTest.setup("normal", 1)
                        : NativeIsolationRegressionTest.setup("turn-access", 42);
                try (NativeSession session = new NativeSession(setup, base); var scope = session.context.enter()) {
                    base.setTestSession(session);
                    Player owner = session.game.getPlayers().get(0);
                    session.game.setAge(GameStage.Play);
                    session.game.setStartingPlayer(owner);
                    if (!scenario.endsWith("-turns")) {
                        session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, owner, false, 1);
                        session.game.getPhaseHandler().setPriority(owner);
                    }
                    switch (scenario) {
                        case "control-human", "control-ai" -> controlled(session, owner);
                        case "chocobo" -> chocobo(session, owner);
                        case "promised-turns", "aeons-turns" -> turns(session, owner, scenario.equals("promised-turns"));
                        case "arrival" -> arrivals(session, owner);
                        default -> throw new IllegalArgumentException(scenario);
                    }
                }
                System.out.println("PASS native turn access " + scenario);
            }
        }
    }

    private static JsonArray zone(NativeSession session, int viewer, int owner, String name) {
        JsonObject view = NativeSnapshot.capture(session.game, session.id, viewer, null);
        for (JsonElement value : view.getAsJsonArray("zones")) {
            JsonObject zone = value.getAsJsonObject();
            if (zone.get("ownerId").getAsString().equals("player-" + owner)
                    && zone.get("zone").getAsString().equals(name)) return zone.getAsJsonArray("cards");
        }
        throw new AssertionError("Missing zone");
    }

    private static void controlled(NativeSession session, Player master) throws Exception {
        Player slave = session.game.getPlayers().get(1);
        Card land = card(session.game, slave, "Forest", ZoneType.Hand);
        card(session.game, master, "Island", ZoneType.Hand);
        var original = slave.getController();
        long timestamp = session.game.getNextTimestamp();
        slave.addController(timestamp, master);
        session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, slave, false, 2);
        session.game.getAction().checkStaticAbilities();
        require(zone(session, 0, 1, "hand").size() == 1 && zone(session, -1, 1, "hand").isEmpty(),
                "Controller's permitted hand missing or leaked to spectator");
        require(zone(session, 1, 0, "hand").isEmpty(), "Controlled player learned the master's hand");
        require(NativeSnapshot.capture(session.game, session.id, -1, slave).getAsJsonArray("players")
                .get(1).getAsJsonObject().get("controllingPlayerId").getAsString().equals("player-0"),
                "Public control status lost the controlling player");
        var human = (PlayerControllerHuman) slave.getController();
        AtomicInteger prompts = new AtomicInteger();
        drive(session, slave, () -> {
            var chosen = human.chooseSpellAbilityToPlay();
            require(chosen != null && chosen.size() == 1 && chosen.get(0).isLandAbility(), "Controlled land was not selectable");
            require(human.playChosenSpellAbility(chosen.get(0)), "Controlled land play failed");
            require(land.isInZone(ZoneType.Battlefield) && land.getController() == slave,
                    "Controlling a player changed the permanent's controller");
            human.arrangeForScry(new forge.game.card.CardCollection(List.of(
                    card(session.game, slave, "Mountain", ZoneType.Library))));
        }, input -> {
            JsonObject envelope = JsonParser.parseString(session.prompt(0)).getAsJsonObject();
            require(envelope.get("decidingPlayerId").getAsString().equals("player-0"), "Decision sent to controlled seat");
            prompts.incrementAndGet();
            if (input.get("type").getAsString().equals("scry")) {
                JsonObject output = NativeSession.object("type", "scryDecision");
                JsonArray top = new JsonArray(); top.add(input.getAsJsonArray("cards").get(0).getAsJsonObject().get("id"));
                JsonArray piles = new JsonArray(); piles.add(top); piles.add(new JsonArray());
                output.add("zoneCardIds", piles); return output;
            }
            require(input.getAsJsonArray("actions").asList().stream().anyMatch(value ->
                    NativeSession.cardId(land).equals(value.getAsJsonObject().get("cardId").getAsString())),
                    "Controlled player's land absent from actions");
            JsonObject output = NativeSession.object("type", "act");
            output.addProperty("actionId", "card:" + land.getId()); return output;
        });
        require(prompts.get() == 2, "Controlled priority or synchronous choice was skipped");
        slave.removeController(timestamp);
        require(slave.getController() == original, "Original human/AI controller did not return");
        card(session.game, slave, "Plains", ZoneType.Hand);
        require(zone(session, 0, 1, "hand").isEmpty(), "Private hand permission survived control ending");
        require(!NativeSnapshot.capture(session.game, session.id, 0, slave).getAsJsonArray("players")
                .get(1).getAsJsonObject().has("controllingPlayerId"), "Control status survived control ending");
    }

    private static void chocobo(NativeSession session, Player owner) throws Exception {
        Card bird = card(session.game, owner, "Traveling Chocobo", ZoneType.Battlefield);
        Card top = card(session.game, owner, "Forest", ZoneType.Library);
        Card nextBird = card(session.game, owner, "Birds of Paradise", ZoneType.Library);
        Card nextLand = card(session.game, owner, "Island", ZoneType.Library);
        session.game.getAction().checkStaticAbilities();
        require(zone(session, 0, 0, "library").size() == 1, "Chocobo top look unavailable");
        require(zone(session, 1, 0, "library").isEmpty() && zone(session, -1, 0, "library").isEmpty(),
                "Chocobo private look leaked");
        var human = (PlayerControllerHuman) owner.getController();
        AtomicInteger prompts = new AtomicInteger();
        drive(session, owner, () -> {
            var chosen = human.chooseSpellAbilityToPlay();
            require(chosen != null && human.playChosenSpellAbility(chosen.get(0)), "Library land play failed");
            require(top.isInZone(ZoneType.Battlefield), "Top land did not enter battlefield");
            session.game.getAction().checkStaticAbilities();
            chosen = human.chooseSpellAbilityToPlay();
            require(chosen != null && human.playChosenSpellAbility(chosen.get(0)), "Library Bird cast failed");
            require(nextBird.isInZone(ZoneType.Stack), "Library Bird did not reach the stack");
            session.game.getStack().resolveStack();
            require(human.chooseSpellAbilityToPlay() == null, "Second land was playable in the same turn");
        }, input -> {
            if (input.get("type").getAsString().equals("payManaCost")) return NativeSession.object("type", "pay");
            int n = prompts.incrementAndGet();
            if (n == 2) {
                require(input.getAsJsonArray("actions").asList().stream().anyMatch(value ->
                        value.getAsJsonObject().get("label").getAsString().contains("Birds of Paradise")),
                        "Chocobo cannot cast the next Bird");
                JsonObject output = NativeSession.object("type", "act");
                output.addProperty("actionId", "card:" + nextBird.getId()); return output;
            }
            if (n == 3) {
                require(input.getAsJsonArray("actions").asList().stream().noneMatch(value ->
                        NativeSession.cardId(nextLand).equals(value.getAsJsonObject().get("cardId").getAsString())),
                        "Chocobo bypassed the land-per-turn limit");
                return NativeSession.object("type", "pass");
            }
            require(input.getAsJsonArray("actions").asList().stream().anyMatch(value ->
                    value.getAsJsonObject().get("type").getAsString().equals("playLand")), "No legal top-land action");
            JsonObject output = NativeSession.object("type", "act");
            output.addProperty("actionId", "card:" + top.getId()); return output;
        });
        require(prompts.get() == 3, "Library actions were not executed");
        session.game.getAction().moveToGraveyard(bird, null);
        session.game.getAction().checkStaticAbilities();
        require(zone(session, 0, 0, "library").isEmpty(), "Top look persisted after Chocobo left");
    }

    private static void turns(NativeSession session, Player owner, boolean promised) throws Exception {
        Player opponent = session.game.getPlayers().get(1);
        for (Player player : List.of(owner, opponent))
            for (int i = 0; i < 8; i++) card(session.game, player, "Forest", ZoneType.Library);
        Card emrakul = card(session.game, owner, promised ? "Emrakul, the Promised End" : "Emrakul, the Aeons Torn", ZoneType.Hand);
        List<Integer> turns = new ArrayList<>();
        List<Integer> controllers = new ArrayList<>();
        AtomicInteger lastTurn = new AtomicInteger(1);
        drive(session, owner, () -> {
            var phases = session.game.getPhaseHandler();
            phases.setupFirstTurn(owner, null);
            while (phases.getPhase() != PhaseType.MAIN1) phases.mainLoopStep();
            for (int i = 0; i < (promised ? 13 : 15); i++)
                owner.getManaPool().addMana(new Mana(MagicColor.COLORLESS, emrakul, null, owner));
            require(PlaySpellAbility.playSpellAbility((PlayerControllerHuman) owner.getController(), owner,
                    emrakul.getSpellAbilities().get(0)), "Emrakul cast failed");
            int end = promised ? 4 : 3;
            int steps = 0;
            while (phases.getTurn() < end || !phases.getPhase().isMain()) {
                require(++steps < 200 && !session.game.isGameOver(), "Native turns failed to advance: turn="
                        + phases.getTurn() + ", phase=" + phases.getPhase() + ", steps=" + steps
                        + ", gameOver=" + session.game.isGameOver() + ", observed=" + turns);
                phases.mainLoopStep();
            }
        }, input -> {
            int turn = session.game.getPhaseHandler().getTurn();
            if (turn != lastTurn.get()) {
                lastTurn.set(turn);
                Player active = session.game.getPhaseHandler().getPlayerTurn();
                turns.add(session.index(active));
                controllers.add(active.isControlled() ? session.index(active.getControllingPlayer()) : session.index(active));
            }
            String kind = input.get("type").getAsString();
            if (kind.equals("payManaCost")) return NativeSession.object("type", "pay");
            if (kind.equals("chooseBoardTargets")) {
                JsonObject output = NativeSession.object("type", "boardTargets");
                JsonArray chosen = new JsonArray();
                JsonObject target = NativeSession.object("kind", "player");
                target.addProperty("id", "player-1"); chosen.add(target); output.add("chosen", chosen); return output;
            }
            if (kind.equals("chooseAction")) return NativeSession.object("type", "pass");
            if (kind.equals("chooseAttackers")) {
                JsonObject output = NativeSession.object("type", "declareAttackers");
                output.add("assignments", new JsonArray()); return output;
            }
            throw new AssertionError("Unexpected turn input: " + input);
        });
        System.out.println("Turn seats: " + turns + "; controllers: " + controllers);
        require(turns.equals(promised ? List.of(1, 1, 0) : List.of(0, 1)), "Extra turn order was wrong: " + turns);
        require(controllers.equals(promised ? List.of(0, 1, 0) : List.of(0, 1)), "Control did not end before extra turn: " + controllers);
    }

    private static void arrivals(NativeSession session, Player owner) {
        Card old = card(session.game, owner, "Grizzly Bears", ZoneType.Battlefield);
        old.setTurnInZone(0); old.setSickness(false);
        Card fresh = card(session.game, owner, "Grizzly Bears", ZoneType.Battlefield);
        fresh.setTurnInZone(1); fresh.setSickness(true);
        Card hasty = card(session.game, owner, "Raging Goblin", ZoneType.Battlefield);
        hasty.setTurnInZone(1); hasty.setSickness(true);
        JsonArray cards = zone(session, 0, 0, "battlefield");
        require(!cards.get(0).getAsJsonObject().get("enteredThisTurn").getAsBoolean()
                && cards.get(1).getAsJsonObject().get("enteredThisTurn").getAsBoolean(), "Entry timing lost");
        require(!cards.get(0).getAsJsonObject().get("summoningSick").getAsBoolean()
                && cards.get(1).getAsJsonObject().get("summoningSick").getAsBoolean(), "Sickness lost");
        require(cards.get(2).getAsJsonObject().get("enteredThisTurn").getAsBoolean()
                && !cards.get(2).getAsJsonObject().get("summoningSick").getAsBoolean(), "Haste ignored in sickness marker");
        session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, owner, false, 2);
        require(!zone(session, 0, 0, "battlefield").get(1).getAsJsonObject().get("enteredThisTurn").getAsBoolean(),
                "Entry marker survived the turn boundary");
    }
}
