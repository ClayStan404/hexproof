// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import forge.game.GameStage;
import forge.game.card.Card;
import forge.game.card.CardCollection;
import forge.game.combat.CombatUtil;
import forge.game.cost.CostExert;
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import forge.player.PlayerControllerHuman;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import static org.hexproof.forge.NativeCallbackRegressionTest.*;

/** Synthetic fixtures exercise native Human callbacks, not a complete combat or game. */
public final class NativeOrderingRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                return null;
            });
            for (String scenario : List.of("exert", "destination", "unbounded", "insert")) {
                JsonObject config = JsonParser.parseString("{\"gameId\":\"native-order-test\",\"seed\":42,\"variant\":\"constructed\",\"startingLife\":20,\"players\":[{\"name\":\"Ordering A\",\"deck\":[{\"name\":\"Forest\"}]},{\"name\":\"Ordering B\",\"deck\":[{\"name\":\"Forest\"}]}]}").getAsJsonObject();
                try (NativeSession session = new NativeSession(config, base)) {
                    base.setFailureHandler(session::fail);
                    session.game.setAge(GameStage.Play);
                    Player owner = session.game.getPlayers().get(0);
                    session.game.setStartingPlayer(owner);
                    session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, owner, false, 1);
                    switch (scenario) {
                        case "exert" -> exert(session, owner);
                        case "destination" -> destination(session, owner);
                        case "unbounded" -> unbounded(session, owner);
                        case "insert" -> insert(session, owner);
                        default -> throw new AssertionError(scenario);
                    }
                }
                System.out.println("PASS native ordering " + scenario);
            }
        }
    }

    private static void exert(NativeSession session, Player owner) throws Exception {
        Card first = card(session.game, owner, "Glorybringer", ZoneType.Battlefield);
        Card second = card(session.game, owner, "Glorybringer", ZoneType.Battlefield);
        Card enlistFirst = card(session.game, owner, "Guardian of New Benalia", ZoneType.Battlefield);
        Card enlistSecond = card(session.game, owner, "Guardian of New Benalia", ZoneType.Battlefield);
        card(session.game, session.game.getPlayers().get(1), "Black Lotus", ZoneType.Hand);
        require(CombatUtil.getOptionalAttackCostCreatures(new CardCollection(List.of(first, second)), CostExert.class).size() == 2,
                "Fixture did not load Glorybringer's real optional attack cost");
        PlayerControllerHuman human = (PlayerControllerHuman) owner.getController();
        AtomicInteger decisions = new AtomicInteger();
        drive(session, owner, () -> {
            require(sameObjects(human.exertAttackers(List.of(first, second)), second), "Human exert selected the wrong original card");
            require(human.exertAttackers(List.of(first)).isEmpty(), "Human could not decline exert");
            require(sameObjects(human.exertAttackers(List.of(first, second)), second, first), "Human exert order was lost");
            require(sameObjects(human.enlistAttackers(List.of(enlistFirst, enlistSecond)), enlistSecond), "Human enlist selected the wrong original card");
        }, input -> {
            require(!input.toString().contains("Black Lotus"), "Ordering enumerated a hidden zone outside native candidates");
            int decision = decisions.getAndIncrement();
            if (decision == 3) {
                require(input.get("type").getAsString().equals("reorder"), "Multiple exert choices skipped ordering");
                reject(session, input, order("order-0", "order-0"));
                return order("order-1", "order-0");
            }
            require(input.get("type").getAsString().equals("chooseCards"), "Human optional attack cost did not ask for cards");
            require(input.get("min").getAsInt() == 0 && input.get("max").getAsInt() == (decision == 1 ? 1 : 2), "Native optional bounds changed");
            if (decision == 0) {
                reject(session, input, cards("card-999999999"));
                reject(session, input, cards(NativeSession.cardId(first), NativeSession.cardId(first)));
                return cards(NativeSession.cardId(second));
            }
            if (decision == 1) return cards();
            if (decision == 2) return cards(NativeSession.cardId(first), NativeSession.cardId(second));
            require(decision == 4, "Unexpected extra attack-cost choice");
            return cards(NativeSession.cardId(enlistSecond));
        });
        require(decisions.get() == 5, "Human attack-cost choices were silently decided");
    }

    private static void destination(NativeSession session, Player owner) throws Exception {
        Object first = new String("Identical label"), second = new String("Identical label"), initiallySelected = new String("Initial destination");
        AtomicInteger decisions = new AtomicInteger();
        drive(session, owner, () -> {
            List<?> result = ((PlayerControllerHuman) owner.getController()).getGui().order("Destination selection", "First", 1, 2,
                    List.of(first, second), List.of(initiallySelected), null, false);
            require(result.size() == 2 && result.get(0) == first && result.get(1) == second,
                    "Ordering forced the initial destination or collapsed equal labels");
        }, input -> {
            if (decisions.getAndIncrement() == 0) {
                require(input.get("type").getAsString().equals("chooseFromSelection"), "Generic split-list selection missing");
                require(input.get("minTotal").getAsInt() == 1 && input.get("maxTotal").getAsInt() == 2,
                        "Remaining bounds excluded initial destination from total");
                reject(session, input, indices());
                reject(session, input, indices(0, 1, 2));
                return indices(1, 0);
            }
            require(input.get("type").getAsString().equals("reorder"), "Generic selected objects were not ordered");
            return order("order-1", "order-0");
        });
        require(decisions.get() == 2, "Destination selection did not cross both explicit choices");
    }

    private static void unbounded(NativeSession session, Player owner) throws Exception {
        AtomicInteger decisions = new AtomicInteger();
        drive(session, owner, () -> {
            List<?> result = NativeOrdering.order(session, owner, "Any number", -1, -1, List.of("A", "B"), List.of("C")).ordered();
            require(result.isEmpty(), "Native unbounded ordering could not select none");
            List<?> minimumOnly = NativeOrdering.order(session, owner, "At least one", -1, 2, List.of("A", "B", "C"), null).ordered();
            require(sameObjects(minimumOnly, "C"), "Native ordering lost its unbounded maximum with a minimum choice count");
        }, input -> {
            int decision = decisions.getAndIncrement();
            require(input.get("minTotal").getAsInt() == decision && input.get("maxTotal").getAsInt() == 3, "Unbounded source/destination limits changed");
            return decision == 0 ? indices() : indices(2);
        });
        require(decisions.get() == 2, "Unbounded selection skipped a choice or asked for an impossible reorder");
    }

    private static void insert(NativeSession session, Player owner) throws Exception {
        Object first = new String("Same"), second = new String("Same"), added = new String("New");
        AtomicInteger decisions = new AtomicInteger();
        drive(session, owner, () -> {
            List<?> result = ((PlayerControllerHuman) owner.getController()).getGui().insertInList("Insert item", added, List.of(first, second));
            require(result.size() == 3 && result.get(0) == first && result.get(1) == added && result.get(2) == second,
                    "Insertion changed the old relative order or original references");
        }, input -> {
            decisions.incrementAndGet();
            require(input.getAsJsonArray("options").size() == 3, "Insertion omitted an endpoint");
            reject(session, input, indices(3));
            return indices(1);
        });
        require(decisions.get() == 1, "Insertion position was not chosen explicitly");
    }

    private static JsonObject cards(String... ids) {
        JsonObject result = NativeSession.object("type", "chooseCardsDecision");
        JsonArray selected = new JsonArray(); for (String id : ids) selected.add(id);
        result.add("chosenCardIds", selected); return result;
    }
    private static boolean sameObjects(List<?> actual, Object... expected) {
        if (actual.size() != expected.length) return false;
        for (int i = 0; i < expected.length; i++) if (actual.get(i) != expected[i]) return false;
        return true;
    }
    private static JsonObject indices(int... indices) {
        JsonObject result = NativeSession.object("type", "selectionDecision");
        JsonArray selected = new JsonArray(); for (int index : indices) selected.add(index);
        result.add("chosenIndices", selected); return result;
    }
    private static JsonObject order(String... ids) {
        JsonObject result = NativeSession.object("type", "reorderDecision");
        JsonArray selected = new JsonArray(); for (String id : ids) selected.add(id);
        result.add("orderedIds", selected); return result;
    }
    private static void reject(NativeSession session, JsonObject input, JsonObject output) {
        String original = session.prompt(0);
        JsonObject envelope = NativeSession.object("type", input.get("type").getAsString()); envelope.add("output", output);
        boolean rejected = false;
        try { session.submit(envelope); } catch (IllegalArgumentException expected) { rejected = true; }
        require(rejected && original.equals(session.prompt(0)), "Invalid ordering response consumed the pending decision");
    }
}
