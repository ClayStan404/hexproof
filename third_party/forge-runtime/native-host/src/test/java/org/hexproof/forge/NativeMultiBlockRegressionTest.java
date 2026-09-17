// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import forge.game.GameStage;
import forge.game.card.Card;
import forge.game.combat.Combat;
import forge.game.combat.CombatUtil;
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import forge.player.PlayerControllerHuman;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import static org.hexproof.forge.NativeCallbackRegressionTest.*;

/** Real InputBlock declarations on a constructed board, including rejection atomicity. */
public final class NativeMultiBlockRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                return null;
            });
            JsonObject config = JsonParser.parseString("{\"gameId\":\"native-multiple-blocks\",\"seed\":42,\"variant\":\"constructed\",\"startingLife\":20,\"players\":[{\"name\":\"Defender\",\"deck\":[{\"name\":\"Forest\"}]},{\"name\":\"Attacker\",\"deck\":[{\"name\":\"Forest\"}]}]}").getAsJsonObject();
            try (NativeSession session = new NativeSession(config, base); var scope = session.context.enter()) {
                base.setTestSession(session);
                session.game.setAge(GameStage.Play);
                Player defender = session.game.getPlayers().get(0);
                Player attacker = session.game.getPlayers().get(1);
                session.game.setStartingPlayer(attacker);
                session.game.getPhaseHandler().devModeSet(PhaseType.COMBAT_DECLARE_BLOCKERS, attacker, false, 1);
                Card watcher = card(session.game, defender, "Watcher in the Web", ZoneType.Battlefield);
                Card ordinary = card(session.game, defender, "Grizzly Bears", ZoneType.Battlefield);
                card(session.game, defender, "Black Lotus", ZoneType.Hand);
                List<Card> attackers = new ArrayList<>();
                for (int i = 0; i < 9; i++) attackers.add(card(session.game, attacker, "Grizzly Bears", ZoneType.Battlefield));
                Combat combat = new Combat(attacker);
                session.game.getPhaseHandler().setCombat(combat);
                for (Card creature : attackers) combat.addAttacker(creature, defender);
                AtomicInteger decisions = new AtomicInteger();
                drive(session, defender, () -> {
                    session.game.getAction().checkStaticAbilities();
                    require(watcher.canBlockAdditional() == 7, "Printed Watcher script did not grant seven additional blocks");
                    ((PlayerControllerHuman) defender.getController()).declareBlockers(defender, combat);
                    require(combat.getAttackersBlockedBy(watcher).size() == 8, "Native InputBlock did not retain all eight selected attackers");
                    require(combat.getAttackersBlockedBy(ordinary).size() == 1
                            && combat.isBlocking(ordinary, attackers.get(8)), "Ordinary blocker assignment changed");
                    require(CombatUtil.validateBlocks(combat, defender) == null, "Native engine rejected the completed declaration");
                }, input -> {
                    require(input.get("type").getAsString().equals("chooseBlockers"), "Unexpected declaration prompt: " + input);
                    require(decisions.incrementAndGet() == 1, "Declaration failed to leave InputBlock after a valid response");
                    require(!input.toString().contains("Black Lotus"), "Combat prompt disclosed a hidden noncandidate");
                    require(!session.snapshot(1).contains("Black Lotus") && !session.snapshot(-1).contains("Black Lotus"), "Block declaration leaked the defender's hand");
                    require(limit(input, watcher) == 8 && limit(input, ordinary) == 1, "Native blocker capacities missing or inferred incorrectly");
                    reject(session, combat, response(watcher, List.of(attackers.get(0), attackers.get(0))));
                    reject(session, combat, response(watcher, attackers));
                    reject(session, combat, response(ordinary, attackers.subList(0, 2)));
                    JsonObject answer = response(watcher, attackers.subList(0, 8));
                    add(answer.getAsJsonArray("assignments"), ordinary, attackers.get(8));
                    return answer;
                });
                require(decisions.get() == 1, "Native block declaration was bypassed");
            }
        }
        System.out.println("PASS native multi-block declaration: eight Watcher assignments, ordinary capacity, duplicates, atomic rejection and privacy");
    }

    private static int limit(JsonObject input, Card blocker) {
        for (JsonElement entry : input.getAsJsonArray("blockerAssignmentLimits")) {
            JsonObject value = entry.getAsJsonObject();
            if (value.get("blockerId").getAsString().equals(NativeSession.cardId(blocker))) return value.get("maxAssignments").getAsInt();
        }
        throw new AssertionError("Missing native blocker limit");
    }

    private static JsonObject response(Card blocker, List<Card> attackers) {
        JsonObject output = NativeSession.object("type", "declareBlockers");
        JsonArray assignments = new JsonArray();
        for (Card attacker : attackers) add(assignments, blocker, attacker);
        output.add("assignments", assignments);
        return output;
    }

    private static void add(JsonArray assignments, Card blocker, Card attacker) {
        JsonObject pair = NativeSession.object("blockerId", NativeSession.cardId(blocker));
        pair.addProperty("attackerId", NativeSession.cardId(attacker));
        assignments.add(pair);
    }

    private static void reject(NativeSession session, Combat combat, JsonObject output) {
        String before = session.prompt(0);
        JsonObject envelope = NativeSession.object("type", "chooseBlockers");
        envelope.add("output", output);
        boolean rejected = false;
        try { session.submit(envelope); } catch (IllegalArgumentException expected) { rejected = true; }
        require(rejected && before.equals(session.prompt(0)), "Invalid assignment did not preserve the exact prompt");
        require(combat.getAllBlockers().isEmpty(), "Invalid declaration partially mutated native combat");
    }
}
