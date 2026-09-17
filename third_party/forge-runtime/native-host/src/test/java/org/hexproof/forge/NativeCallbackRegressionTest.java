// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.card.ColorSet;
import forge.card.MagicColor;
import forge.game.*;
import forge.game.card.*;
import forge.game.combat.Combat;
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.player.PlaySpellAbility;
import forge.game.spellability.SpellAbility;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import forge.player.PlayerControllerHuman;
import forge.util.ThreadUtil;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Function;

/** Actual native callbacks on synthetic boards; this is not full-game coverage. */
public final class NativeCallbackRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                prefs.setPref(FPref.UI_SELECT_FROM_CARD_DISPLAYS, false);
                return null;
            });
            JsonObject config = JsonParser.parseString("{\"gameId\":\"native-callback-test\",\"seed\":42,\"variant\":\"constructed\",\"startingLife\":20,\"players\":[{\"name\":\"Callback A\",\"deck\":[{\"name\":\"Forest\"}]},{\"name\":\"Callback B\",\"deck\":[{\"name\":\"Forest\"}]}]}").getAsJsonObject();
            try (NativeSession session = new NativeSession(config, base); var scope = session.context.enter()) {
                base.setTestSession(session);
                session.game.setAge(GameStage.Play);
                Player owner = session.game.getPlayers().get(0);
                session.game.setStartingPlayer(owner);
                session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, owner, false, 1);
                switch (args[1]) {
                    case "scry" -> scry(session, owner);
                    case "generic" -> generic(session, owner);
                    case "damage" -> damage(session, owner, false);
                    case "damage_unordered" -> damage(session, owner, true);
                    case "damage_single_defender" -> damageOnlyDefender(session, owner);
                    case "damage_deathtouch" -> deathtouch(session, owner);
                    case "damage_skip" -> skipDamage(session, owner);
                    case "phyrexian" -> phyrexian(session, owner);
                    default -> throw new IllegalArgumentException("Unknown callback scenario");
                }
            }
        }
        System.out.println("PASS native callback " + args[1]);
    }

    private static void scry(NativeSession session, Player owner) throws Exception {
        Card bolt = card(session.game, owner, "Lightning Bolt", ZoneType.Library);
        Card forest = card(session.game, owner, "Forest", ZoneType.Library);
        Card island = card(session.game, owner, "Island", ZoneType.Library);
        Card mountain = card(session.game, owner, "Mountain", ZoneType.Library);
        Card cause = card(session.game, owner, "Opt", ZoneType.Hand);
        SpellAbility ability = cause.getSpellAbilities().get(0);
        ability.setActivatingPlayer(owner);
        AtomicInteger decisions = new AtomicInteger();
        drive(session, owner, () -> {
            session.game.getAction().scry(List.of(owner), 3, ability);
            require(new ArrayList<>(owner.getCardsIn(ZoneType.Library)).equals(List.of(island, forest, mountain, bolt)), "GameAction.scry did not apply chosen top/bottom order");
        }, input -> {
            String type = input.get("type").getAsString();
            require(!input.toString().contains("Mountain"), "scry disclosed an unlooked library card");
            require(!session.snapshot(-1).contains("Lightning Bolt") && !session.snapshot(1).contains("Lightning Bolt"), "scry lookup leaked to another viewer");
            decisions.incrementAndGet();
            require(type.equals("scry"), "Expected one complete scry decision");
            JsonObject output = NativeSession.object("type", "scryDecision");
            JsonArray top = new JsonArray(), bottom = new JsonArray(), piles = new JsonArray();
            top.add(NativeSession.cardId(island)); top.add(NativeSession.cardId(forest));
            bottom.add(NativeSession.cardId(bolt)); piles.add(top); piles.add(bottom);
            output.add("zoneCardIds", piles); return output;
        });
        require(decisions.get() == 1, "Scry must expose both ordered piles together");
    }

    private static void generic(NativeSession session, Player owner) throws Exception {
        Card source = card(session.game, owner, "Forest", ZoneType.Battlefield);
        SpellAbility ability = source.getManaAbilities().get(0);
        ability.setActivatingPlayer(owner);
        PlayerControllerHuman human = (PlayerControllerHuman) owner.getController();
        AtomicInteger decisions = new AtomicInteger();
        drive(session, owner, () -> {
            Map<Byte, Integer> result = human.specifyManaCombo(ability,
                    ColorSet.fromMask(MagicColor.WHITE | MagicColor.BLUE | MagicColor.GREEN), 3, false);
            var colors = new ArrayList<>(ColorSet.fromMask(MagicColor.WHITE | MagicColor.BLUE | MagicColor.GREEN).getOrderedColors());
            require(result.get(colors.get(0).getColorMask()) == 1 && result.get(colors.get(1).getColorMask()) == 2 && result.get(colors.get(2).getColorMask()) == 0,
                    "Native mana color map did not preserve explicit allocations: " + result);
        }, input -> {
            require(input.get("type").getAsString().equals("chooseNumber"), "Generic allocation skipped native number choices");
            int index = decisions.getAndIncrement();
            if (index == 0) {
                JsonObject invalid = NativeSession.object("type", "numberDecision");
                invalid.addProperty("chosenNumber", input.get("max").getAsInt() + 1);
                rejectPreservingPrompt(session, "chooseNumber", invalid);
            }
            JsonObject output = NativeSession.object("type", "numberDecision");
            output.addProperty("chosenNumber", index == 0 ? 1 : index == 1 ? 2 : 0);
            return output;
        });
        require(decisions.get() == 3, "Missing generic allocation choices");
    }

    private static void damage(NativeSession session, Player owner, boolean uneven) throws Exception {
        Player opponent = session.game.getPlayers().get(1);
        Card attacker = card(session.game, owner, "Colossal Dreadmaw", ZoneType.Battlefield);
        Card first = card(session.game, opponent, "Grizzly Bears", ZoneType.Battlefield);
        Card second = card(session.game, opponent, "Grizzly Bears", ZoneType.Battlefield);
        PlayerControllerHuman human = (PlayerControllerHuman) owner.getController();
        AtomicInteger decisions = new AtomicInteger();
        drive(session, owner, () -> {
            Map<Card, Integer> result = human.assignCombatDamage(attacker, new CardCollection(List.of(first, second)), null, 6, opponent, true);
            require(result.get(first) == (uneven ? 1 : 2) && result.get(second) == (uneven ? 5 : 2) && result.get(null) == (uneven ? 0 : 2), "Native combat result lost assignee objects or defender null key");
        }, input -> {
            require(input.get("type").getAsString().equals("chooseCombatDamageAssignment"), "Native combat allocation callback bypassed");
            require(input.get("damageAssignmentMode").getAsString().equals("unordered"), "Native unordered metadata lost");
            decisions.incrementAndGet();
            JsonObject invalid = damageOutput(first, second, 1, 1, 4);
            String original = session.prompt(0);
            JsonObject envelope = NativeSession.object("type", "chooseCombatDamageAssignment"); envelope.add("output", invalid);
            boolean rejected = false;
            try { session.submit(envelope); } catch (IllegalArgumentException expected) { rejected = true; }
            require(rejected && session.prompt(0).equals(original), "Nonlethal trample allocation did not preserve pending prompt on rejection");
            return uneven ? damageOutput(first, second, 1, 5, 0) : damageOutput(first, second, 2, 2, 2);
        });
        require(decisions.get() == 1, "Combat assignment was not explicit");
    }

    private static JsonObject damageOutput(Card first, Card second, int a, int b, int defender) {
        JsonObject output = NativeSession.object("type", "combatDamageAssignmentDecision");
        JsonArray amounts = new JsonArray();
        for (Map.Entry<String, Integer> amount : Map.of(NativeSession.cardId(first), a, NativeSession.cardId(second), b, "player-1", defender).entrySet()) {
            JsonObject value = NativeSession.object("assigneeId", amount.getKey()); value.addProperty("damage", amount.getValue()); amounts.add(value);
        }
        output.add("assignments", amounts); return output;
    }

    private static void damageOnlyDefender(NativeSession session, Player owner) throws Exception {
        Player defender = session.game.getPlayers().get(1);
        Card attacker = card(session.game, owner, "Colossal Dreadmaw", ZoneType.Battlefield);
        drive(session, owner, () -> {
            Map<Card, Integer> result = ((PlayerControllerHuman) owner.getController()).assignCombatDamage(
                    attacker, new CardCollection(), null, 6, defender, true);
            require(result.size() == 1 && result.get(null) == 6, "Native defender-only damage map changed");
        }, input -> {
            require(input.get("type").getAsString().equals("chooseCombatDamageAssignment")
                    && input.getAsJsonArray("blockerIds").isEmpty(), "Defender-only allocation was not an explicit native prompt");
            JsonObject output = NativeSession.object("type", "combatDamageAssignmentDecision");
            JsonObject value = NativeSession.object("assigneeId", "player-1"); value.addProperty("damage", 6);
            JsonArray amounts = new JsonArray(); amounts.add(value); output.add("assignments", amounts); return output;
        });
    }

    private static void deathtouch(NativeSession session, Player owner) throws Exception {
        Player defender = session.game.getPlayers().get(1);
        Card attacker = card(session.game, owner, "Glissa Sunslayer", ZoneType.Battlefield);
        Card first = card(session.game, defender, "Grizzly Bears", ZoneType.Battlefield);
        Card second = card(session.game, defender, "Grizzly Bears", ZoneType.Battlefield);
        drive(session, owner, () -> {
            Map<Card, Integer> result = ((PlayerControllerHuman) owner.getController()).assignCombatDamage(
                    attacker, new CardCollection(List.of(first, second)), null, 3, defender, false);
            require(result.size() == 2 && result.get(first) == 1 && result.get(second) == 2, "Native deathtouch lethal threshold lost");
        }, input -> {
            require(input.get("attackerHasDeathtouch").getAsBoolean() && !input.has("defenderId"), "Native deathtouch/trample metadata changed");
            JsonObject output = NativeSession.object("type", "combatDamageAssignmentDecision");
            JsonArray values = new JsonArray();
            for (Map.Entry<Card, Integer> entry : Map.of(first, 1, second, 2).entrySet()) {
                JsonObject value = NativeSession.object("assigneeId", NativeSession.cardId(entry.getKey())); value.addProperty("damage", entry.getValue()); values.add(value);
            }
            output.add("assignments", values); return output;
        });
    }

    private static void skipDamage(NativeSession session, Player owner) throws Exception {
        Player defender = session.game.getPlayers().get(1);
        Card attacker = card(session.game, owner, "Colossal Dreadmaw", ZoneType.Battlefield);
        Card next = card(session.game, owner, "Colossal Dreadmaw", ZoneType.Battlefield);
        Card blocker = card(session.game, defender, "Grizzly Bears", ZoneType.Battlefield);
        Combat combat = new Combat(owner);
        session.game.getPhaseHandler().setCombat(combat);
        combat.addAttacker(attacker, defender); combat.addAttacker(next, defender);
        drive(session, owner, () -> {
            Map<Card, Integer> result = ((PlayerControllerHuman) owner.getController()).assignCombatDamage(attacker,
                    new CardCollection(List.of(blocker)), new CardCollection(List.of(attacker, next)), 6, defender, true);
            require(result == null, "Native deferred assignment must return the native skip sentinel");
        }, input -> {
            require(input.get("type").getAsString().equals("chooseBoolean"), "Native maySkip choice missing");
            JsonObject output = NativeSession.object("type", "decision"); output.addProperty("value", false); return output;
        });
    }

    private static void rejectPreservingPrompt(NativeSession session, String type, JsonObject output) {
        String original = session.prompt(0);
        JsonObject envelope = NativeSession.object("type", type); envelope.add("output", output);
        boolean rejected = false;
        try { session.submit(envelope); } catch (IllegalArgumentException expected) { rejected = true; }
        require(rejected && session.prompt(0).equals(original), "Invalid allocation did not preserve the pending prompt");
    }

    private static void phyrexian(NativeSession session, Player owner) throws Exception {
        Card target = card(session.game, owner, "Grizzly Bears", ZoneType.Battlefield);
        Card growth = card(session.game, owner, "Mutagenic Growth", ZoneType.Hand);
        SpellAbility ability = growth.getSpellAbilities().get(0);
        int beforeLife = owner.getLife();
        AtomicInteger lifeChoices = new AtomicInteger();
        drive(session, owner, () -> {
            require(PlaySpellAbility.playSpellAbility((PlayerControllerHuman) owner.getController(), owner, ability), "Native Phyrexian cast was not completed");
            require(owner.getLife() == beforeLife - 2, "Native Phyrexian payment did not deduct exactly two life");
            require(session.game.getStack().size() == 1 && growth.isInZone(ZoneType.Stack), "Actual Phyrexian spell was not put on the stack");
        }, input -> {
            String type = input.get("type").getAsString();
            if (type.equals("chooseBoardTargets")) {
                JsonObject response = NativeSession.object("type", "boardTargets");
                JsonArray chosen = new JsonArray();
                if (input.get("minTargets").getAsInt() > 0) {
                    JsonObject card = NativeSession.object("kind", "card"); card.addProperty("id", NativeSession.cardId(target)); chosen.add(card);
                }
                response.add("chosen", chosen); return response;
            }
            require(type.equals("payManaCost"), "Unexpected Phyrexian callback: " + type);
            boolean available = false;
            for (JsonElement action : input.getAsJsonArray("actions")) {
                if (action.getAsJsonObject().get("id").getAsString().equals("life:2")) available = true;
            }
            require(available, "Native Phyrexian life-total action is missing");
            lifeChoices.incrementAndGet();
            JsonObject response = NativeSession.object("type", "act"); response.addProperty("actionId", "life:2"); return response;
        });
        require(lifeChoices.get() == 1, "Phyrexian payment did not use one explicit life action");
    }

    static void drive(NativeSession session, Player owner, Runnable work, Function<JsonObject, JsonObject> policy) throws Exception {
        session.context.gameExecutor().execute(() -> {
            try {
                work.run();
                session.publish(owner, NativeSession.object("type", "testComplete"), ignored -> () -> { }, false);
            } catch (Throwable error) { session.fail(error); }
        });
        long deadline = System.nanoTime() + 30_000_000_000L;
        while (System.nanoTime() < deadline) {
            String raw = session.prompt(0);
            if (raw.isEmpty()) { Thread.sleep(5); continue; }
            JsonObject input = JsonParser.parseString(raw).getAsJsonObject().getAsJsonObject("input");
            String type = input.get("type").getAsString();
            if (type.equals("testComplete")) return;
            JsonObject response = NativeSession.object("type", type); response.add("output", policy.apply(input));
            session.submit(response);
        }
        throw new AssertionError("Native callback did not reach completion");
    }

    static Card card(Game game, Player owner, String name, ZoneType zone) {
        Card card = CardFactory.getCard(FModel.getMagicDb().getCommonCards().getCard(name), owner, game);
        if (zone == ZoneType.Stack) game.getStackZone().add(card);
        else owner.getZone(zone).add(card);
        return card;
    }
    static void require(boolean condition, String message) { if (!condition) throw new AssertionError(message); }
}
