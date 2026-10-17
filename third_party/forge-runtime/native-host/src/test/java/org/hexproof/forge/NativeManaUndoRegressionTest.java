// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.JsonObject;
import forge.card.MagicColor;
import forge.card.mana.ManaCost;
import forge.game.GameStage;
import forge.game.mana.Mana;
import forge.game.mana.ManaCostBeingPaid;
import forge.game.card.Card;
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import static org.hexproof.forge.NativeCallbackRegressionTest.*;

/** Real human mana payment, source undo, and immediate repeated activation. */
public final class NativeManaUndoRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                prefs.setPref(FPref.UI_SELECT_FROM_CARD_DISPLAYS, false);
                return null;
            });
            try (NativeSession session = new NativeSession(NativeIsolationRegressionTest.setup("mana-undo", 42), base);
                    var scope = session.context.enter()) {
                base.setTestSession(session);
                Player owner = session.game.getPlayers().get(0);
                session.game.setAge(GameStage.Play);
                session.game.setStartingPlayer(owner);
                session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, owner, false, 2);
                Card forest = card(session.game, owner, "Forest", ZoneType.Battlefield);
                Card second = card(session.game, owner, "Forest", ZoneType.Battlefield);
                Card bears = card(session.game, owner, "Grizzly Bears", ZoneType.Hand);
                AtomicInteger steps = new AtomicInteger();
                drive(session, owner, () -> {
                    require(owner.getController().playChosenSpellAbility(bears.getSpellAbilities().get(0)), "Final payment failed");
                    require(forest.isTapped() && second.isTapped() && bears.isInZone(ZoneType.Stack), "Final cast lost its sources");
                }, input -> {
                    require(input.get("type").getAsString().equals("payManaCost"), "Unexpected input: " + input);
                    int step = steps.getAndIncrement();
                    System.out.println("MANA_UNDO step=" + step + " cost=" + input.get("manaCost")
                            + " tapped=" + forest.isTapped() + " pool=" + owner.getManaPool().totalMana());
                    if (step < 20) {
                        if (step % 2 == 0) {
                            require(!forest.isTapped() && input.get("manaCost").getAsString().equals("{1}{G}"), "Undo did not restore the original cost");
                            return action("card:" + forest.getId());
                        }
                        require(forest.isTapped() && owner.getManaPool().isEmpty(), "Activation did not pay its green symbol");
                        return action("undo:" + forest.getId());
                    }
                    return action("card:" + (step == 20 ? forest.getId() : second.getId()));
                });
                require(steps.get() == 22 && !session.hasFailed(), "Rapid source undo failed the native session");
            }
            for (String scenario : List.of("other-source", "hybrid", "partial-floating", "preexisting", "life", "completed", "irreversible", "cost-ledger", "nested-fee"))
                extended(base, scenario);
        }
        System.out.println("PASS native mana payment undo");
    }

    private static JsonObject action(String id) {
        JsonObject output = NativeSession.object("type", "act");
        output.addProperty("actionId", id);
        return output;
    }

    private static void extended(NativeGuiBase base, String scenario) throws Exception {
        try (NativeSession session = new NativeSession(NativeIsolationRegressionTest.setup("mana-undo-" + scenario, 42), base);
                var scope = session.context.enter()) {
            base.setTestSession(session);
            Player owner = session.game.getPlayers().get(0);
            session.game.setAge(GameStage.Play);
            session.game.setStartingPlayer(owner);
            session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, owner, false, 2);
            switch (scenario) {
                case "other-source", "hybrid" -> mixedSources(session, owner, scenario.equals("hybrid"));
                case "partial-floating" -> partialFloating(session, owner);
                case "preexisting" -> preexisting(session, owner);
                case "life" -> lifePayment(session, owner);
                case "completed" -> completedPayment(session, owner);
                case "irreversible" -> irreversible(session, owner);
                case "cost-ledger" -> costLedger(session, owner);
                case "nested-fee" -> nestedFee(session, owner);
                default -> throw new AssertionError("Unknown source undo scenario");
            }
            require(!session.hasFailed(), scenario + " failed its native session");
        }
        System.out.println("PASS native mana undo " + scenario);
    }

    private static void mixedSources(NativeSession session, Player owner, boolean hybrid) throws Exception {
        Card first = card(session.game, owner, hybrid ? "Sol Ring" : "Forest", ZoneType.Battlefield);
        Card second = card(session.game, owner, hybrid ? "Sol Ring" : "Forest", ZoneType.Battlefield);
        Card third = card(session.game, owner, hybrid ? "Plains" : "Forest", ZoneType.Battlefield);
        Card fourth = hybrid ? card(session.game, owner, "Plains", ZoneType.Battlefield) : first;
        Card spell = card(session.game, owner, hybrid ? "Spectral Procession" : "Centaur Courser", ZoneType.Hand);
        String[] actions = {"card:" + first.getId(), "card:" + second.getId(), "undo:" + first.getId(),
                "card:" + (hybrid ? third : first).getId(), "card:" + (hybrid ? fourth : third).getId()};
        String[] costs = hybrid ? new String[]{"{2/W}{2/W}{2/W}", "{2/W}{2/W}", "{2/W}", "{2/W}{2/W}", "{2/W}"}
                : new String[]{"{2}{G}", "{2}", "{1}", "{2}", "{1}"};
        AtomicInteger steps = new AtomicInteger();
        drive(session, owner, () -> {
            require(owner.getController().playChosenSpellAbility(spell.getSpellAbilities().get(0)), "Mixed-source cast failed");
            require(second.isTapped() && third.isTapped() && first.isTapped() == !hybrid, "Undo disturbed another source");
        }, input -> {
            int step = steps.getAndIncrement();
            require(step < actions.length && input.get("manaCost").getAsString().equals(costs[step]), "Mixed-source restored cost changed: " + input);
            if (step == 3) {
                require(!first.isTapped() && second.isTapped(), "Source undo untapped its retained neighbor");
                require(owner.getManaPool().isEmpty(), "Source undo created floating mana");
                var paid = spell.getSpellAbilities().get(0).getPayingMana();
                require(!paid.isEmpty() && paid.stream().allMatch(mana -> mana.getSourceCard().getId() == second.getId()),
                        "Source undo kept the wrong physical mana provenance");
            }
            return action(actions[step]);
        });
        require(steps.get() == actions.length, "Mixed-source input was not completed");
    }

    private static void partialFloating(NativeSession session, Player owner) throws Exception {
        Card ring = card(session.game, owner, "Sol Ring", ZoneType.Battlefield);
        Card mountain = card(session.game, owner, "Mountain", ZoneType.Battlefield);
        Card spell = card(session.game, owner, "Desperate Ritual", ZoneType.Hand);
        AtomicInteger steps = new AtomicInteger();
        drive(session, owner, () -> {
            require(owner.getController().playChosenSpellAbility(spell.getSpellAbilities().get(0)), "Partial-floating cast failed");
            require(ring.isTapped() && mountain.isTapped() && owner.getManaPool().totalMana() == 1, "Surplus mana changed on the final payment");
        }, input -> {
            int step = steps.getAndIncrement();
            if (step == 1) require(ring.isTapped() && owner.getManaPool().totalMana() == 1
                    && input.get("manaCost").getAsString().equals("{R}"), "Two-mana source did not split paid and floating mana");
            if (step == 2) require(!ring.isTapped() && owner.getManaPool().isEmpty()
                    && input.get("manaCost").getAsString().equals("{1}{R}"), "Partial source undo lost mana or cost");
            require(step < 4, "Repeated partial source input");
            return action((step == 1 ? "undo:" : "card:") + (step == 3 ? mountain : ring).getId());
        });
    }

    private static void preexisting(NativeSession session, Player owner) throws Exception {
        Card previous = card(session.game, owner, "Forest", ZoneType.Battlefield);
        Card current = card(session.game, owner, "Forest", ZoneType.Battlefield);
        Card spell = card(session.game, owner, "Centaur Courser", ZoneType.Hand);
        AtomicInteger steps = new AtomicInteger();
        drive(session, owner, () -> {
            require(owner.getController().playChosenSpellAbility(previous.getManaAbilities().get(0)), "Previous floating activation failed");
            var original = previous.getManaAbilities().get(0).getManaPart().getLastManaProduced().iterator().next();
            require(!owner.getController().playChosenSpellAbility(spell.getSpellAbilities().get(0)), "Cancellation unexpectedly cast the spell");
            require(previous.isTapped() && !current.isTapped() && owner.getManaPool().totalMana() == 1,
                    "Cancel changed resources from before this payment");
            require(owner.getManaPool().iterator().next() == original, "Same-color source undo replaced an existing mana globe");
        }, input -> {
            int step = steps.getAndIncrement();
            if (step == 2) require(previous.isTapped() && !current.isTapped() && owner.getManaPool().totalMana() == 1
                    && input.get("manaCost").getAsString().equals("{2}{G}"), "Undo did not preserve preexisting mana");
            require(step < 3, "Repeated preexisting-mana input");
            return step == 2 ? NativeSession.object("type", "cancel")
                    : action((step == 1 ? "undo:" : "card:") + current.getId());
        });
    }

    private static void lifePayment(NativeSession session, Player owner) throws Exception {
        Card[] forests = new Card[4];
        for (int i = 0; i < forests.length; i++) forests[i] = card(session.game, owner, "Forest", ZoneType.Battlefield);
        Card spell = card(session.game, owner, "Moltensteel Dragon", ZoneType.Hand);
        AtomicInteger steps = new AtomicInteger();
        drive(session, owner, () -> {
            require(owner.getController().playChosenSpellAbility(spell.getSpellAbilities().get(0)), "Phyrexian-life cast failed");
            require(owner.getLife() == 16, "Source undo lost or duplicated a life payment");
        }, input -> {
            int step = steps.getAndIncrement();
            require(step < 8, "Repeated life-payment input");
            if (step == 3) require(input.get("manaCost").getAsString().equals("{4}{R/P}"), "Undo restored an already life-paid symbol");
            if (step == 1 || step == 7) return action("life:2");
            if (step == 2) return action("undo:" + forests[0].getId());
            return action("card:" + forests[step == 0 || step == 3 ? 0 : step - 3].getId());
        });
    }

    private static void completedPayment(NativeSession session, Player owner) throws Exception {
        Card first = card(session.game, owner, "Forest", ZoneType.Battlefield);
        Card second = card(session.game, owner, "Forest", ZoneType.Battlefield);
        Card spell = card(session.game, owner, "Grizzly Bears", ZoneType.Hand);
        AtomicInteger steps = new AtomicInteger();
        drive(session, owner, () -> {
            require(owner.getController().playChosenSpellAbility(spell.getSpellAbilities().get(0)), "Completed cast failed");
            session.game.getStack().reset();
            session.game.getAction().moveToGraveyard(spell, null);
            Card next = card(session.game, owner, "Grizzly Bears", ZoneType.Hand);
            require(!owner.getController().playChosenSpellAbility(next.getSpellAbilities().get(0)), "Unpaid second spell was cast");
            require(first.isTapped() && second.isTapped(), "Undo reached mana spent on a completed action");
        }, input -> {
            int step = steps.getAndIncrement();
            if (step < 2) return action("card:" + (step == 0 ? first : second).getId());
            require(step == 2 && input.getAsJsonArray("actions").asList().stream().noneMatch(value ->
                    value.getAsJsonObject().get("type").getAsString().equals("undoMana")), "Completed payment offered a source undo");
            String before = session.prompt(0);
            JsonObject invalid = NativeSession.object("type", "payManaCost");
            invalid.add("output", action("undo:" + first.getId()));
            try {
                session.submit(invalid);
                throw new AssertionError("Unavailable source undo was accepted");
            } catch (IllegalArgumentException expected) {
                require(!session.hasFailed() && session.prompt(0).equals(before), "Invalid undo destroyed its pending input");
            }
            return NativeSession.object("type", "cancel");
        });
    }

    private static void irreversible(NativeSession session, Player owner) throws Exception {
        Card lotus = card(session.game, owner, "Lotus Bloom", ZoneType.Battlefield);
        Card forest = card(session.game, owner, "Forest", ZoneType.Battlefield);
        Card spell = card(session.game, owner, "Harmonize", ZoneType.Hand);
        AtomicInteger payments = new AtomicInteger();
        drive(session, owner, () -> {
            require(owner.getController().playChosenSpellAbility(spell.getSpellAbilities().get(0)), "Irreversible-source cast failed");
            require(lotus.isInZone(ZoneType.Graveyard) && forest.isTapped(), "Irreversible source was restored");
        }, input -> {
            String kind = input.get("type").getAsString();
            if (kind.equals("chooseBoolean")) {
                JsonObject output = NativeSession.object("type", "decision"); output.addProperty("value", true); return output;
            }
            if (kind.equals("chooseFromSelection")) {
                JsonObject output = NativeSession.object("type", "selectionDecision");
                com.google.gson.JsonArray chosen = new com.google.gson.JsonArray(); chosen.add(4); output.add("chosenIndices", chosen); return output;
            }
            require(kind.equals("payManaCost"), "Unexpected irreversible input: " + input);
            int step = payments.getAndIncrement();
            if (step == 1) require(input.getAsJsonArray("actions").asList().stream().noneMatch(value ->
                    value.getAsJsonObject().get("id").getAsString().equals("undo:" + lotus.getId())), "Sacrifice was offered as reversible mana");
            require(step < 2, "Repeated irreversible payment");
            return action("card:" + (step == 0 ? lotus : forest).getId());
        });
    }
    private static void costLedger(NativeSession session, Player owner) {
        Card forest = card(session.game, owner, "Forest", ZoneType.Battlefield);
        Card island = card(session.game, owner, "Island", ZoneType.Battlefield);
        Mana green = new Mana(MagicColor.GREEN, forest, forest.getManaAbilities().get(0).getManaPart(), owner);
        Mana blue = new Mana(MagicColor.BLUE, island, island.getManaAbilities().get(0).getManaPart(), owner);
        ManaCostBeingPaid coloredX = new ManaCostBeingPaid(new ManaCost("X"));
        coloredX.setXManaCostPaid(2, "WUBRGX");
        coloredX.beginPaymentUndoTracking();
        require(coloredX.payMana(green, owner.getManaPool()) && coloredX.payMana(blue, owner.getManaPool())
                && coloredX.isPaid() && coloredX.getSunburst() == 2, "Colored X initial payment failed");
        ManaCostBeingPaid copied = new ManaCostBeingPaid(coloredX);
        require(!copied.canRefundManaPayments(List.of(green)), "Native copy inherited another cost's source refund ledger");
        require(!coloredX.canRefundManaPayments(List.of(green, green)), "Refund accepted too many globes for one paid mana");
        require(coloredX.refundManaPayments(List.of(green)) && !coloredX.isPaid() && coloredX.getSunburst() == 1
                && coloredX.getXManaCostPaidByColor().equals(java.util.Map.of("U", 1)), "Colored X undo lost its color/count metadata");
        require(!coloredX.isNeeded(blue, owner.getManaPool()) && coloredX.isNeeded(green, owner.getManaPool()),
                "Colored X undo stopped enforcing distinct paid colors");
        require(coloredX.payMana(green, owner.getManaPool()) && coloredX.isPaid() && coloredX.getSunburst() == 2
                && coloredX.getXManaCostPaidByColor().equals(java.util.Map.of("U", 1, "G", 1)), "Colored X repeat payment changed provenance counts");

        Card snowForest = card(session.game, owner, "Snow-Covered Forest", ZoneType.Battlefield);
        Mana snow = new Mana(MagicColor.GREEN, snowForest, snowForest.getManaAbilities().get(0).getManaPart(), owner);
        ManaCostBeingPaid snowCost = new ManaCostBeingPaid(new ManaCost("1 S"));
        snowCost.beginPaymentUndoTracking();
        require(snowCost.payMana(snow, owner.getManaPool()) && snowCost.payMana(green, owner.getManaPool()) && snowCost.isPaid(),
                "Snow source did not pay its actual native shard");
        require(snowCost.refundManaPayments(List.of(snow)) && snowCost.toString().equals("{S}")
                && !snowCost.isNeeded(green, owner.getManaPool()) && snowCost.isNeeded(snow, owner.getManaPool()),
                "Source undo let ordinary retained mana pay a snow shard");
        require(snowCost.payMana(snow, owner.getManaPool()) && snowCost.isPaid(), "Snow repeat payment failed");
    }

    private static void nestedFee(NativeSession session, Player owner) throws Exception {
        Card ring = card(session.game, owner, "Sol Ring", ZoneType.Battlefield);
        Card prismite = card(session.game, owner, "Prismite", ZoneType.Battlefield);
        Card spell = card(session.game, owner, "Grizzly Bears", ZoneType.Hand);
        AtomicInteger steps = new AtomicInteger();
        drive(session, owner, () -> {
            require(!owner.getController().playChosenSpellAbility(spell.getSpellAbilities().get(0)), "Nested cancellation unexpectedly cast the spell");
            require(!ring.isTapped() && owner.getManaPool().isEmpty() && spell.isInZone(ZoneType.Hand),
                    "Nested source undo/cancel duplicated or lost its activation fee");
            require(prismite.getManaAbilities().get(0).getPayingMana().isEmpty()
                    && spell.getSpellAbilities().get(0).getPayingMana().isEmpty(), "Nested refund kept a spent native mana ledger");
        }, input -> {
            String kind = input.get("type").getAsString();
            if (kind.equals("chooseFromSelection")) {
                JsonObject output = NativeSession.object("type", "selectionDecision");
                com.google.gson.JsonArray chosen = new com.google.gson.JsonArray(); chosen.add(4); output.add("chosenIndices", chosen); return output;
            }
            require(kind.equals("payManaCost"), "Unexpected nested-fee input: " + input);
            int step = steps.getAndIncrement();
            System.out.println("NESTED_UNDO step=" + step + " input=" + input);
            require(step < 4, "Repeated nested source input");
            if (step == 0) return action("card:" + prismite.getId());
            if (step == 1) return action("card:" + ring.getId());
            if (step == 2) return action("undo:" + prismite.getId());
            return NativeSession.object("type", "cancel");
        });
    }

}
