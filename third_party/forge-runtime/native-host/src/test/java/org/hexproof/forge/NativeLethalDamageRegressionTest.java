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
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import static org.hexproof.forge.NativeCallbackRegressionTest.*;

/** Real combat assignment and damage on synthetic boards, not whole-game coverage. */
public final class NativeLethalDamageRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                return null;
            });
            for (boolean byPower : List.of(false, true)) {
                JsonObject config = JsonParser.parseString("{\"gameId\":\"native-lethal-test\",\"seed\":42,\"variant\":\"constructed\",\"startingLife\":20,\"players\":[{\"name\":\"Attacker\",\"deck\":[{\"name\":\"Forest\"}]},{\"name\":\"Defender\",\"deck\":[{\"name\":\"Forest\"}]}]}").getAsJsonObject();
                try (NativeSession session = new NativeSession(config, base); var scope = session.context.enter()) {
                    base.setTestSession(session);
                    session.game.setAge(GameStage.Play);
                    Player owner = session.game.getPlayers().get(0);
                    session.game.setStartingPlayer(owner);
                    session.game.getPhaseHandler().devModeSet(PhaseType.COMBAT_DAMAGE, owner, false, 1);
                    combat(session, owner, byPower);
                }
                System.out.println("PASS native lethal damage " + (byPower ? "Zilortha power threshold" : "shared blocker assigned damage"));
            }
        }
    }

    private static void combat(NativeSession session, Player owner, boolean byPower) throws Exception {
        Player opponent = session.game.getPlayers().get(1);
        Card first = card(session.game, owner, "Colossal Dreadmaw", ZoneType.Battlefield);
        Card second = byPower ? null : card(session.game, owner, "Colossal Dreadmaw", ZoneType.Battlefield);
        Card blocker = card(session.game, opponent, "Watcher in the Web", ZoneType.Battlefield);
        if (byPower) card(session.game, opponent, "Zilortha, Strength Incarnate", ZoneType.Battlefield);
        card(session.game, opponent, "Black Lotus", ZoneType.Hand);
        AtomicInteger attackerDecisions = new AtomicInteger();
        AtomicInteger blockerDecisions = new AtomicInteger();
        drive(session, owner, () -> {
            session.game.getAction().checkStaticAbilities();
            require(blocker.getView().getCurrentState().getToughness() == 5, "Watcher fixture lost its printed toughness");
            require(blocker.getView().getLethalDamage() == (byPower ? 2 : 5), "Native static lethal threshold was not applied");
            require(blocker.isLethalDamageByPower() == byPower, "Zilortha's real continuous script was not applied");
            Combat combat = new Combat(owner);
            session.game.getPhaseHandler().setCombat(combat);
            combat.addAttacker(first, opponent);
            combat.addBlocker(first, blocker);
            combat.setBlocked(first, true);
            if (second != null) {
                combat.addAttacker(second, opponent);
                combat.addBlocker(second, blocker);
                combat.setBlocked(second, true);
                require(combat.getAttackersBlockedBy(blocker).size() == 2, "Fixture did not share one blocker");
            }
            combat.orderBlockersForDamageAssignment();
            combat.orderAttackersForDamageAssignment();
            int lifeBefore = opponent.getLife();
            require(combat.assignCombatDamage(false), "Native combat did not assign damage");
            require(blocker.getTotalAssignedDamage() == (byPower ? 2 : 5), "Native combat lost the first assignment before resolving damage");
            combat.dealAssignedDamage();
            require(opponent.getLife() == lifeBefore - (byPower ? 4 : 7), "Trample damage did not use the native lethal threshold");
        }, input -> {
            require(!input.toString().contains("Black Lotus"), "Damage hints disclosed a noncandidate hidden card");
            String type = input.get("type").getAsString();
            if (type.equals("chooseBoolean")) {
                JsonObject output = NativeSession.object("type", "decision");
                output.addProperty("value", true); // Explicitly assign this attacker now.
                return output;
            }
            require(type.equals("chooseCombatDamageAssignment"), "Unexpected combat callback: " + type);
            JsonArray hints = input.getAsJsonArray("blockerDamageHints");
            JsonArray candidates = input.getAsJsonArray("blockerIds");
            require(hints != null && hints.size() == candidates.size(), "Native hints do not cover the supplied candidates");
            String source = input.get("attackerId").getAsString();
            boolean assigningAttacker = !source.equals(NativeSession.cardId(blocker));
            int lethal = byPower ? 2 : attackerDecisions.get() == 0 ? 5 : 0;
            if (assigningAttacker) {
                require(candidates.size() == 1 && candidates.get(0).getAsString().equals(NativeSession.cardId(blocker)), "Wrong native shared blocker candidate");
                JsonObject hint = hints.get(0).getAsJsonObject();
                require(hint.get("id").getAsString().equals(NativeSession.cardId(blocker)) && hint.get("lethalDamage").getAsInt() == lethal,
                        "Published lethal threshold ignored native assigned damage or power substitution: " + hint);
                if (!byPower && attackerDecisions.get() == 1) {
                    require(blocker.getDamage() == 0 && blocker.getTotalAssignedDamage() == 5,
                            "Regression must distinguish assigned damage from already dealt damage");
                }
                attackerDecisions.incrementAndGet();
            } else blockerDecisions.incrementAndGet();
            JsonObject output = NativeSession.object("type", "combatDamageAssignmentDecision");
            JsonArray assignments = new JsonArray();
            int remaining = input.get("totalDamage").getAsInt();
            for (int index = 0; index < candidates.size(); index++) {
                JsonElement id = candidates.get(index);
                int amount = assigningAttacker ? lethal : index == 0 ? remaining : 0;
                JsonObject assignment = NativeSession.object("assigneeId", id.getAsString());
                assignment.addProperty("damage", amount); assignments.add(assignment); remaining -= amount;
            }
            if (input.has("defenderId")) {
                JsonObject assignment = NativeSession.object("assigneeId", input.get("defenderId").getAsString());
                assignment.addProperty("damage", remaining); assignments.add(assignment); remaining = 0;
            }
            require(remaining == 0, "Explicit human allocation did not use all combat damage");
            output.add("assignments", assignments);
            return output;
        });
        require(attackerDecisions.get() == (byPower ? 1 : 2), "An attacker allocation was silently decided");
        require(blockerDecisions.get() == (byPower ? 0 : 1), "Shared blocker allocation did not use the native human callback");
    }
}
