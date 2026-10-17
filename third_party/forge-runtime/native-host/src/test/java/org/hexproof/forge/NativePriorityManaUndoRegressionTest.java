// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import forge.card.MagicColor;
import forge.game.GameStage;
import forge.game.card.Card;
import forge.game.mana.Mana;
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.spellability.SpellAbility;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.gamemodes.match.input.InputPassPriority;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import forge.player.PlayerControllerHuman;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import static org.hexproof.forge.NativeCallbackRegressionTest.*;

/** Actual native priority inputs and source refunds on isolated constructed boards. */
public final class NativePriorityManaUndoRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                prefs.setPref(FPref.UI_SELECT_FROM_CARD_DISPLAYS, false);
                prefs.setPref(FPref.YIELD_AUTO_PASS_NO_ACTIONS, false);
                prefs.setPref(FPref.UI_SHOW_ACTIONABLE_HIGHLIGHTS, false);
                return null;
            });
            for (String scenario : List.of("two-sources", "multiple-mana", "spent-identity", "spent-multiplicity",
                    "irreversible", "repeated-ability", "nested-fee", "completed-cast", "land", "priority-phase", "queued-history-change", "queued-input-change")) {
                try (NativeSession session = new NativeSession(NativeIsolationRegressionTest.setup("priority-undo-" + scenario, 42), base);
                        var scope = session.context.enter()) {
                    base.setTestSession(session);
                    Player owner = session.game.getPlayers().getFirst();
                    session.game.setAge(GameStage.Play);
                    session.game.setStartingPlayer(owner);
                    session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, owner, false, 2);
                    switch (scenario) {
                        case "two-sources" -> twoSources(session, owner);
                        case "multiple-mana" -> multipleMana(session, owner);
                        case "queued-history-change", "queued-input-change" -> queuedHistoryChange(session, owner, scenario);
                        case "spent-identity", "spent-multiplicity" -> spent(session, owner, scenario);
                        case "irreversible", "repeated-ability", "nested-fee" -> special(session, owner, scenario);
                        case "completed-cast", "land", "priority-phase" -> changedState(session, owner, scenario);
                        default -> throw new AssertionError(scenario);
                    }
                    require(!session.hasFailed(), scenario + " failed the native session");
                }
                System.out.println("PASS native priority mana undo " + scenario);
            }
        }
    }

    private static JsonObject action(String id) {
        JsonObject output = NativeSession.object("type", "act");
        output.addProperty("actionId", id);
        return output;
    }

    private static List<String> undos(JsonObject input) {
        require(input.get("type").getAsString().equals("chooseAction"), "Expected native priority: " + input);
        List<String> result = new ArrayList<>();
        for (var value : input.getAsJsonArray("actions")) {
            JsonObject option = value.getAsJsonObject();
            if (option.get("type").getAsString().equals("undoMana")) result.add(option.get("id").getAsString());
        }
        return result;
    }

    private static void reject(NativeSession session, String id) {
        String before = session.prompt(0);
        JsonObject invalid = NativeSession.object("type", "chooseAction");
        invalid.add("output", action(id));
        try {
            session.submit(invalid);
            throw new AssertionError("Unavailable undo accepted: " + id);
        } catch (IllegalArgumentException expected) {
            require(session.prompt(0).equals(before) && !session.hasFailed(), "Rejected undo consumed the priority prompt");
        }
    }

    private static void activate(Player owner, SpellAbility ability) {
        require(owner.getController().playChosenSpellAbility(ability), "Native activation/cast failed");
    }

    private static void twoSources(NativeSession session, Player owner) throws Exception {
        Card first = card(session.game, owner, "Forest", ZoneType.Battlefield);
        Card second = card(session.game, owner, "Forest", ZoneType.Battlefield);
        var human = (PlayerControllerHuman) owner.getController();
        AtomicInteger decisions = new AtomicInteger();
        Mana[] kept = new Mana[1];
        drive(session, owner, () -> {
            for (Card expected : List.of(first, second)) {
                List<SpellAbility> chosen = human.chooseSpellAbilityToPlay();
                require(chosen != null && chosen.size() == 1 && chosen.getFirst().getHostCard() == expected,
                        "Priority click selected a different source");
                activate(owner, chosen.getFirst());
            }
            require(human.chooseSpellAbilityToPlay() == null, "Undo turned into a selected ability");
            require(!first.isTapped() && !second.isTapped() && owner.getManaPool().isEmpty()
                    && session.game.getStack().getUndoStackSize() == 0, "Both native activations were not refunded");
        }, input -> {
            int step = decisions.getAndIncrement();
            List<String> undo = undos(input);
            if (step == 0) { require(undo.isEmpty(), "Offered undo before producing mana"); return action("card:" + first.getId()); }
            if (step == 1) {
                require(undo.equals(List.of("undo:" + first.getId())), "First source undo missing");
                kept[0] = owner.getManaPool().iterator().next();
                return action("card:" + second.getId());
            }
            if (step == 2) {
                require(undo.equals(List.of("undo:" + second.getId())), "Undo did not preserve native last-action order");
                reject(session, "undo:" + first.getId());
                return action("undo:" + second.getId());
            }
            if (step == 3) {
                require(undo.equals(List.of("undo:" + first.getId())) && first.isTapped() && !second.isTapped()
                        && owner.getManaPool().totalMana() == 1 && owner.getManaPool().iterator().next() == kept[0]
                        && session.game.getStack().getUndoStackSize() == 1,
                        "Undo changed the retained equal-color source or mana identity");
                return action("undo:" + first.getId());
            }
            require(step == 4 && undo.isEmpty(), "Undo did not finish at the same priority input");
            reject(session, "undo:" + second.getId());
            return NativeSession.object("type", "pass");
        });
        require(decisions.get() == 5, "Missing priority source/undo prompts");
    }

    private static void multipleMana(NativeSession session, Player owner) throws Exception {
        Card ring = card(session.game, owner, "Sol Ring", ZoneType.Battlefield);
        AtomicInteger decisions = new AtomicInteger();
        drive(session, owner, () -> {
            activate(owner, ring.getManaAbilities().getFirst());
            require(owner.getController().chooseSpellAbilityToPlay() == null, "Multiple-mana undo selected another action");
            require(!ring.isTapped() && owner.getManaPool().isEmpty() && session.game.getStack().getUndoStackSize() == 0,
                    "Two-mana refund lost a native globe or left stale history");
        }, input -> {
            int step = decisions.getAndIncrement();
            if (step == 0) {
                require(owner.getManaPool().totalMana() == 2 && undos(input).equals(List.of("undo:" + ring.getId())), "Two-globe source missing");
                return action("undo:" + ring.getId());
            }
            require(step == 1 && undos(input).isEmpty(), "Two-globe source remained undoable");
            return NativeSession.object("type", "pass");
        });
    }

    private static void spent(NativeSession session, Player owner, String scenario) throws Exception {
        Card source = card(session.game, owner, scenario.equals("spent-multiplicity") ? "Sol Ring" : "Forest", ZoneType.Battlefield);
        Card other = card(session.game, owner, "Forest", ZoneType.Battlefield);
        drive(session, owner, () -> {
            activate(owner, source.getManaAbilities().getFirst());
            Mana produced = owner.getManaPool().iterator().next();
            require(owner.getManaPool().removeMana(produced), "Constructed spent-mana fixture could not consume one exact globe");
            // Keep an equal-looking resource to distinguish identity/multiplicity
            // qualification from a mere nonempty-pool or color-count check.
            if (scenario.equals("spent-identity"))
                owner.getManaPool().addMana(new Mana(MagicColor.GREEN, other, other.getManaAbilities().getFirst().getManaPart(), owner));
            require(owner.getManaPool().totalMana() == 1 && NativePriorityManaUndo.source(owner) == null,
                    "Spent source was substituted by an equal or remaining globe");
            require(owner.getController().chooseSpellAbilityToPlay() == null, "Spent-source guard selected an action");
            require(source.isTapped() && owner.getManaPool().totalMana() == 1, "Rejected undo changed spent-source resources");
        }, input -> {
            require(undos(input).isEmpty(), "Spent mana offered a source undo");
            reject(session, "undo:" + source.getId());
            return NativeSession.object("type", "pass");
        });
    }

    private static void special(NativeSession session, Player owner, String scenario) throws Exception {
        Card source = card(session.game, owner, scenario.equals("irreversible") ? "Lotus Bloom" : "Prismite", ZoneType.Battlefield);
        Card ring = card(session.game, owner, "Sol Ring", ZoneType.Battlefield);
        AtomicInteger priorities = new AtomicInteger();
        drive(session, owner, () -> {
            if (scenario.equals("repeated-ability")) {
                // Native repeated filter activations reuse their ability ledger;
                // the initial pool is an explicit synthetic resource fixture.
                for (int i = 0; i < 6; ++i) owner.getManaPool().addMana(new Mana(MagicColor.COLORLESS, ring, null, owner));
            }
            activate(owner, source.getManaAbilities().getFirst());
            if (scenario.equals("repeated-ability")) activate(owner, source.getManaAbilities().getFirst());
            require(owner.getController().chooseSpellAbilityToPlay() == null, "Special source undo selected an unrelated action");
            if (scenario.equals("nested-fee"))
                require(!ring.isTapped() && owner.getManaPool().isEmpty() && session.game.getStack().getUndoStackSize() == 0
                        && source.getManaAbilities().getFirst().getPayingMana().isEmpty(),
                        "Recursive native refund lost the activation fee or retained its ledger");
            if (scenario.equals("irreversible")) require(source.isInZone(ZoneType.Graveyard), "Undo restored a sacrificed source");
        }, input -> {
            String kind = input.get("type").getAsString();
            if (kind.equals("chooseBoolean")) {
                JsonObject output = NativeSession.object("type", "decision"); output.addProperty("value", true); return output;
            }
            if (kind.equals("chooseFromSelection")) {
                JsonObject output = NativeSession.object("type", "selectionDecision");
                JsonArray chosen = new JsonArray(); chosen.add(4); output.add("chosenIndices", chosen); return output;
            }
            if (kind.equals("payManaCost")) return scenario.equals("nested-fee") ? action("card:" + ring.getId()) : NativeSession.object("type", "pay");
            int step = priorities.getAndIncrement();
            if (scenario.equals("nested-fee") && step == 0) {
                require(undos(input).equals(List.of("undo:" + source.getId())), "Safe filter activation was not retractable");
                return action("undo:" + source.getId());
            }
            require(undos(input).isEmpty(), "Irreversible/reused source or cleared filter still offered undo");
            reject(session, "undo:" + source.getId());
            return NativeSession.object("type", "pass");
        });
    }

    private static void queuedHistoryChange(NativeSession session, Player owner, String scenario) throws Exception {
        boolean replaceInput = scenario.equals("queued-input-change");
        Card first = card(session.game, owner, "Forest", ZoneType.Battlefield);
        Card second = card(session.game, owner, "Forest", ZoneType.Battlefield);
        AtomicInteger decisions = new AtomicInteger();
        drive(session, owner, () -> {
            activate(owner, first.getManaAbilities().getFirst());
            if (replaceInput) require(owner.getController().chooseSpellAbilityToPlay() == null, "Fixture priority pass failed");
            require(owner.getController().chooseSpellAbilityToPlay() == null, "Stale undo selected or passed another action");
            require(!first.isTapped() && !second.isTapped() && owner.getManaPool().isEmpty(), "Fresh source undo did not recover");
        }, input -> {
            int step = decisions.getAndIncrement();
            if (step == 0) {
                require(undos(input).equals(List.of("undo:" + first.getId())), "Initial undo missing");
                var human = (PlayerControllerHuman) owner.getController();
                InputPassPriority original = (InputPassPriority) human.getInputProxy().getInput();
                CountDownLatch entered = new CountDownLatch(1), release = new CountDownLatch(1);
                session.context.later(() -> {
                    entered.countDown();
                    try { require(release.await(5, TimeUnit.SECONDS), "Queued-action test was not released"); }
                    catch (InterruptedException error) { throw new AssertionError(error); }
                });
                try {
                    require(entered.await(5, TimeUnit.SECONDS), "Could not hold the native UI queue");
                    CompletableFuture<Void> submission = CompletableFuture.runAsync(() -> {
                        try (var scope = session.context.enter()) {
                            JsonObject response = NativeSession.object("type", "chooseAction");
                            response.add("output", action("undo:" + first.getId()));
                            session.submit(response);
                        }
                    });
                    long until = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
                    while (!session.prompt(0).isEmpty() && System.nanoTime() < until) Thread.sleep(1);
                    require(session.prompt(0).isEmpty(), "Response did not reach its prepared/queued boundary");
                    CompletableFuture<Void> changed = new CompletableFuture<>();
                    session.game.getAction().invoke(() -> {
                        try {
                            if (replaceInput) original.passPriority();
                            else activate(owner, second.getManaAbilities().getFirst());
                            changed.complete(null);
                        }
                        catch (Throwable error) { changed.completeExceptionally(error); }
                    });
                    changed.get(5, TimeUnit.SECONDS);
                    if (replaceInput) {
                        until = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
                        while ((human.getInputProxy().getInput() == original
                                || !(human.getInputProxy().getInput() instanceof InputPassPriority))
                                && System.nanoTime() < until) Thread.sleep(1);
                        require(human.getInputProxy().getInput() instanceof InputPassPriority
                                && human.getInputProxy().getInput() != original, "Fixture did not replace the original native input");
                    }
                    release.countDown();
                    submission.get(5, TimeUnit.SECONDS);
                    JsonObject fresh = JsonParser.parseString(session.prompt(0)).getAsJsonObject().getAsJsonObject("input");
                    require(first.isTapped() && second.isTapped() != replaceInput
                            && owner.getManaPool().totalMana() == (replaceInput ? 1 : 2)
                            && undos(fresh).equals(List.of("undo:" + (replaceInput ? first : second).getId())),
                            "Queued stale undo mutated newer history, passed priority, or left input pending");
                    return action("undo:" + (replaceInput ? first : second).getId());
                } catch (Exception error) { throw new AssertionError(error); }
                finally { release.countDown(); }
            }
            if (step == 1 && !replaceInput) {
                require(undos(input).equals(List.of("undo:" + first.getId())) && first.isTapped() && !second.isTapped(),
                        "New history did not remain retractable after stale response");
                return action("undo:" + first.getId());
            }
            require(step == (replaceInput ? 1 : 2) && undos(input).isEmpty(), "Queued-undo recovery did not finish");
            return NativeSession.object("type", "pass");
        });
    }

    private static void changedState(NativeSession session, Player owner, String scenario) throws Exception {
        Card first = card(session.game, owner, "Forest", ZoneType.Battlefield);
        Card second = card(session.game, owner, "Forest", ZoneType.Battlefield);
        Card spell = card(session.game, owner, scenario.equals("land") ? "Mountain" : "Grizzly Bears", ZoneType.Hand);
        AtomicInteger decisions = new AtomicInteger();
        drive(session, owner, () -> {
            activate(owner, first.getManaAbilities().getFirst());
            if (scenario.equals("completed-cast")) {
                activate(owner, second.getManaAbilities().getFirst());
                activate(owner, spell.getSpellAbilities().getFirst());
                require(spell.isInZone(ZoneType.Stack), "Completed-cast fixture did not finish payment");
            } else if (scenario.equals("land")) {
                activate(owner, spell.getAllPossibleAbilities(owner, true).getFirst());
                require(spell.isInPlay(), "Land fixture did not play its native land action");
            } else {
                Player opponent = session.game.getPlayers().get(1);
                session.game.getPhaseHandler().setPriority(opponent);
                require(NativePriorityManaUndo.source(owner) == null && NativePriorityManaUndo.source(opponent) == null,
                        "Priority/ownership switch retained a foreign undo");
                session.game.getPhaseHandler().setPriority(owner);
                require(NativePriorityManaUndo.source(owner) != null, "Native owner could not undo its still-valid same-phase mana");
                require(session.game.getPhaseHandler().devAdvanceToPhase(PhaseType.COMBAT_BEGIN), "Native phase advance failed");
                require(NativePriorityManaUndo.source(owner) == null, "Undo crossed the native phase-history boundary");
            }
            require(owner.getController().chooseSpellAbilityToPlay() == null, "Changed-state guard selected another action");
            if (scenario.equals("land")) {
                require(!first.isTapped() && owner.getManaPool().isEmpty(), "Mana source did not retract after land play");
                require(spell.isInPlay() && owner.getLandsPlayedThisTurn() == 1, "Mana undo rolled back a land play");
            } else require(first.isTapped(), "Guard undid a source across an unrelated action/boundary");
        }, input -> {
            if (input.get("type").getAsString().equals("payManaCost")) return NativeSession.object("type", "pay");
            if (scenario.equals("land") && decisions.getAndIncrement() == 0) {
                // Native land play leaves earlier mana history intact. Undo the
                // mana only, preserving both the land and its turn allowance.
                require(undos(input).equals(List.of("undo:" + first.getId())), "Native retained mana history unavailable");
                reject(session, "undo:" + spell.getId());
                return action("undo:" + first.getId());
            }
            require(undos(input).isEmpty(), "Completed/boundary action exposed undoMana");
            reject(session, "undo:" + first.getId());
            return NativeSession.object("type", "pass");
        });
    }
}
