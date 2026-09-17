// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.game.GameStage;
import forge.game.ability.AbilityFactory;
import forge.game.ability.AbilityUtils;
import forge.game.card.*;
import forge.game.cost.CostRemoveAnyCounter;
import forge.game.cost.CostExile;
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.spellability.SpellAbility;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import forge.game.player.PlaySpellAbility;
import forge.player.PlayerControllerHuman;
import forge.player.HumanCostDecision;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import static org.hexproof.forge.NativeCallbackRegressionTest.*;

/** Real costs and effects over synthetic boards, driven through the packaged host. */
public final class NativeMechanicsRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                prefs.setPref(FPref.UI_SELECT_FROM_CARD_DISPLAYS, false);
                return null;
            });
            JsonObject config = JsonParser.parseString("{\"gameId\":\"native-mechanics\",\"seed\":42,\"variant\":\"constructed\",\"startingLife\":20,\"players\":[{\"name\":\"Mechanics A\",\"deck\":[{\"name\":\"Forest\"}]},{\"name\":\"Mechanics B\",\"deck\":[{\"name\":\"Forest\"}]}]}").getAsJsonObject();
            try (NativeSession session = new NativeSession(config, base); var scope = session.context.enter()) {
                base.setTestSession(session);
                session.game.setAge(GameStage.Play);
                Player owner = session.game.getPlayers().get(0);
                session.game.setStartingPlayer(owner);
                session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, owner, false, 2);
                switch (args[1]) {
                    case "counter-first", "counter-second", "counter-cancel" -> counter(session, owner, args[1]);
                    case "chord" -> chord(session, owner);
                    case "discard-cancel" -> discardCancel(session, owner);
                    case "discard-two" -> discardTwo(session, owner);
                    case "optional-card-batch" -> optionalCardBatch(session, owner);
                    case "shared-type-incremental" -> sharedTypeIncremental(session, owner);
                    case "needle", "mage" -> naming(session, owner, args[1].equals("mage"));
                    case "bolt-resolution", "counterspell-resolution", "counter-counterspell" -> spellResolution(session, owner, args[1]);
                    default -> throw new IllegalArgumentException("Unknown mechanics scenario");
                }
            }
        }
        System.out.println("PASS native mechanics " + args[1]);
    }

    private static void spellResolution(NativeSession session, Player owner, String scenario) throws Exception {
        Player opponent = session.game.getPlayers().get(1);
        drive(session, owner, () -> {
            int initialLife = opponent.getLife();
            Card bolt = card(session.game, owner, "Lightning Bolt", ZoneType.Stack);
            SpellAbility burn = bolt.getSpellAbilities().get(0);
            burn.setActivatingPlayer(owner);
            burn.getTargets().add(opponent);
            session.game.getStack().add(burn);
            if (!scenario.equals("bolt-resolution")) {
                Card counter = card(session.game, opponent, "Counterspell", ZoneType.Stack);
                SpellAbility negate = counter.getSpellAbilities().get(0);
                negate.setActivatingPlayer(opponent);
                negate.getTargets().add(burn);
                session.game.getStack().add(negate);
                if (scenario.equals("counter-counterspell")) {
                    Card protection = card(session.game, owner, "Counterspell", ZoneType.Stack);
                    SpellAbility protect = protection.getSpellAbilities().get(0);
                    protect.setActivatingPlayer(owner);
                    protect.getTargets().add(negate);
                    session.game.getStack().add(protect);
                    session.game.getStack().resolveStack();
                    require(counter.isInZone(ZoneType.Graveyard) && protection.isInZone(ZoneType.Graveyard),
                            "The countered counterspell and its answer must both enter their graveyards");
                    require(session.game.getStack().size() == 1 && bolt.isInZone(ZoneType.Stack),
                            "Countering Counterspell must preserve the original Bolt on the stack");
                }
            }
            session.game.getStack().resolveStack();
            int damage = scenario.equals("counterspell-resolution") ? 0 : 3;
            require(opponent.getLife() == initialLife - damage, "Counterspell chain applied the wrong Bolt damage");
            require(bolt.isInZone(ZoneType.Graveyard) && session.game.getStack().isEmpty(),
                    "The resolved or countered Bolt must leave the stack for its owner's graveyard");
        }, input -> { throw new AssertionError("Unexpected choice during ordinary spell resolution: " + input); });
    }

    private static void counter(NativeSession session, Player owner, String scenario) throws Exception {
        Card first = card(session.game, owner, "Walking Ballista", ZoneType.Battlefield);
        Card second = card(session.game, owner, "Arcbound Worker", ZoneType.Battlefield);
        Card source = card(session.game, owner, "Soul Diviner", ZoneType.Battlefield);
        source.setSickness(false);
        first.setCounters(CounterEnumType.P1P1, 2);
        second.setCounters(CounterEnumType.P1P1, 2);
        card(session.game, owner, "Forest", ZoneType.Library);
        SpellAbility ability = source.getSpellAbilities().stream().filter(sa -> sa.getPayCosts() != null
                && sa.getPayCosts().getCostParts().stream().anyMatch(c -> c instanceof CostRemoveAnyCounter)).findFirst().orElseThrow();
        ability.setActivatingPlayer(owner);
        boolean cancel = scenario.endsWith("cancel"), chooseFirst = scenario.endsWith("first");
        AtomicInteger decisions = new AtomicInteger();
        drive(session, owner, () -> {
            boolean played = PlaySpellAbility.playSpellAbility((PlayerControllerHuman) owner.getController(), owner, ability);
            require(played != cancel, "Cancellation must abort activation");
            require(first.getCounters(CounterEnumType.P1P1) == ((!cancel && chooseFirst) ? 1 : 2), "First counter source changed incorrectly");
            require(second.getCounters(CounterEnumType.P1P1) == ((!cancel && !chooseFirst) ? 1 : 2), "Second counter source changed incorrectly");
            require(source.isTapped() != cancel, "Tap cost was not rolled back on cancellation");
        }, input -> {
            decisions.incrementAndGet();
            require(input.get("type").getAsString().equals("chooseBoardTargets"), "Counter source choice was bypassed");
            if (cancel) {
                require(input.get("cancellable").getAsBoolean(), "Native cost cancel was not exposed");
                return NativeSession.object("type", "cancel");
            }
            return boardChoice(input, NativeSession.cardId(chooseFirst ? first : second));
        });
        require(decisions.get() == 1, "Expected one explicit counter-source decision");
    }

    private static void naming(NativeSession session, Player owner, boolean nonland) throws Exception {
        Card source = card(session.game, owner, nonland ? "Meddling Mage" : "Pithing Needle", ZoneType.Battlefield);
        SpellAbility ability = AbilityFactory.getAbility(source.getSVar("DBNameCard"), source);
        ability.setActivatingPlayer(owner);
        AtomicInteger decisions = new AtomicInteger();
        drive(session, owner, () -> {
            AbilityUtils.resolve(ability);
            require(source.getNamedCard().equals("Black Lotus"), "Effect did not store public name absent from both decks");
        }, input -> {
            decisions.incrementAndGet();
            require(input.get("type").getAsString().equals("chooseCardName"), "Public naming was reduced to a finite menu");
            String previous = session.prompt(0);
            JsonObject invalid = NativeSession.object("type", "cardName");
            invalid.addProperty("name", nonland ? "Forest" : "Not A Real Card Name For Native Regression");
            JsonObject envelope = NativeSession.object("type", "chooseCardName"); envelope.add("output", invalid);
            boolean rejected = false;
            try { session.submit(envelope); } catch (IllegalArgumentException expected) { rejected = true; }
            require(rejected && session.prompt(0).equals(previous), "Invalid name changed the current native decision");
            JsonObject result = NativeSession.object("type", "cardName"); result.addProperty("name", "Black Lotus");
            return result;
        });
        require(decisions.get() == 1, "Naming effect required an unexpected decision");
    }

    private static void discardCancel(NativeSession session, Player owner) throws Exception {
        List<Card> lands = List.of(card(session.game, owner, "Mountain", ZoneType.Battlefield),
                card(session.game, owner, "Mountain", ZoneType.Battlefield));
        Card first = card(session.game, owner, "Grizzly Bears", ZoneType.Hand);
        Card second = card(session.game, owner, "Forest", ZoneType.Hand);
        Card spell = card(session.game, owner, "Cathartic Reunion", ZoneType.Hand);
        SpellAbility ability = spell.getSpellAbilities().get(0);
        AtomicInteger cancelled = new AtomicInteger(), paid = new AtomicInteger();
        drive(session, owner, () -> {
            require(!PlaySpellAbility.playSpellAbility((PlayerControllerHuman) owner.getController(), owner, ability),
                    "Cancelling additional discard cost still cast the spell");
            require(owner.getCardsIn(ZoneType.Hand).containsAll(List.of(first, second, spell)), "Cancelled discard removed hand cards");
            require(lands.stream().noneMatch(Card::isTapped), "Cancelled spell did not refund mana sources");
            require(session.game.getStack().isEmpty(), "Cancelled spell entered the stack");
        }, input -> {
            String type = input.get("type").getAsString();
            if (type.equals("payManaCost")) {
                JsonObject result = NativeSession.object("type", "act");
                result.addProperty("actionId", "card:" + lands.get(paid.getAndIncrement()).getId()); return result;
            }
            require(type.equals("chooseCards"), "Discard cost did not expose native card input: " + input);
            require(input.has("cancellable") && input.get("cancellable").getAsBoolean(), "Discard cost cancellation is missing");
            cancelled.incrementAndGet();
            return NativeSession.object("type", "cancel");
        });
        require(cancelled.get() == 1, "Native discard cancellation was not exercised");
    }

    private static void discardTwo(NativeSession session, Player owner) throws Exception {
        Card source = card(session.game, owner, "Seasoned Pyromancer", ZoneType.Battlefield);
        Card land = card(session.game, owner, "Forest", ZoneType.Hand);
        Card creature = card(session.game, owner, "Grizzly Bears", ZoneType.Hand);
        Card retained = card(session.game, owner, "Mountain", ZoneType.Hand);
        card(session.game, owner, "Forest", ZoneType.Library);
        card(session.game, owner, "Mountain", ZoneType.Library);
        SpellAbility ability = AbilityFactory.getAbility(source.getSVar("TrigDiscard"), source);
        ability.setActivatingPlayer(owner);
        AtomicInteger decisions = new AtomicInteger();
        drive(session, owner, () -> {
            AbilityUtils.resolve(ability);
            require(land.isInZone(ZoneType.Graveyard) && creature.isInZone(ZoneType.Graveyard), "Explicit discard pair was lost");
            require(retained.isInZone(ZoneType.Hand) && owner.getCardsIn(ZoneType.Hand).size() == 3, "Pyromancer did not draw exactly two after discard");
            require(owner.getCreaturesInPlay().stream().filter(Card::isToken).count() == 1, "Pyromancer did not create exactly one nonland-discard token");
        }, input -> {
            require(input.get("type").getAsString().equals("chooseCards"), "Unexpected Pyromancer decision: " + input);
            require(input.get("min").getAsInt() == 2 && input.get("max").getAsInt() == 2, "Native two-card selection was reduced to single clicks");
            decisions.incrementAndGet();
            JsonObject answer = NativeSession.object("type", "chooseCardsDecision");
            JsonArray chosen = new JsonArray(); chosen.add(NativeSession.cardId(land)); chosen.add(NativeSession.cardId(creature));
            answer.add("chosenCardIds", chosen); return answer;
        });
        require(decisions.get() == 1, "Discard two must be one complete remote card selection");
    }

    private static void optionalCardBatch(NativeSession session, Player owner) throws Exception {
        Card source = card(session.game, owner, "Forest", ZoneType.Battlefield);
        Card first = card(session.game, owner, "Grizzly Bears", ZoneType.Battlefield);
        Card second = card(session.game, owner, "Grizzly Bears", ZoneType.Battlefield);
        SpellAbility ability = AbilityFactory.getAbility("DB$ Sacrifice | SacValid$ Creature | Amount$ 2", source);
        ability.setActivatingPlayer(owner);
        AtomicInteger decisions = new AtomicInteger();
        drive(session, owner, () -> {
            var selected = ((PlayerControllerHuman) owner.getController()).choosePermanentsToSacrifice(
                    ability, 0, 2, new CardCollection(List.of(first, second)), "Choose up to two creatures");
            require(selected.size() == 1 && selected.getFirst() == second, "Optional native selection did not return the explicit subset");
        }, input -> {
            require(input.get("type").getAsString().equals("chooseCards"), "Optional native selection was not a card batch");
            require(input.get("min").getAsInt() == 0 && input.get("max").getAsInt() == 2, "Optional native bounds were changed");
            decisions.incrementAndGet();
            JsonObject answer = NativeSession.object("type", "chooseCardsDecision");
            JsonArray chosen = new JsonArray(); chosen.add(NativeSession.cardId(second));
            answer.add("chosenCardIds", chosen); return answer;
        });
        require(decisions.get() == 1, "Optional subset must commit without another hidden selection step");
    }

    private static void sharedTypeIncremental(NativeSession session, Player owner) throws Exception {
        Card source = card(session.game, owner, "Eye of Ojer Taq", ZoneType.Battlefield);
        Card first = card(session.game, owner, "Grizzly Bears", ZoneType.Graveyard);
        Card second = card(session.game, owner, "Glory Seeker", ZoneType.Graveyard);
        Card retained = card(session.game, owner, "Forest", ZoneType.Graveyard);
        SpellAbility ability = source.getSpellAbilities().stream().filter(sa -> sa.getPayCosts() != null
                && sa.getPayCosts().getCostParts().stream().anyMatch(c -> c instanceof CostExile exile
                && exile.getType().contains("withSharedCardType"))).findFirst().orElseThrow();
        ability.setActivatingPlayer(owner);
        CostExile cost = (CostExile) ability.getPayCosts().getCostParts().stream()
                .filter(c -> c instanceof CostExile exile && exile.getType().contains("withSharedCardType")).findFirst().orElseThrow();
        AtomicInteger decisions = new AtomicInteger();
        drive(session, owner, () -> {
            var chosen = new HumanCostDecision((PlayerControllerHuman) owner.getController(), owner, ability, false, null).visit(cost);
            require(chosen != null && chosen.cards.size() == 2 && chosen.cards.containsAll(List.of(first, second)),
                    "Shared-type cost was confirmed before the second explicit card");
            require(cost.payAsDecided(owner, chosen, ability, false), "Native shared-type cost payment failed");
            require(first.isInZone(ZoneType.Exile) && second.isInZone(ZoneType.Exile)
                    && retained.isInZone(ZoneType.Graveyard), "Shared-type payment lost the selected pair");
        }, input -> {
            require(input.get("type").getAsString().equals("chooseCards"), "Shared-type native input was bypassed");
            require(input.get("min").getAsInt() == 0 && input.get("max").getAsInt() == 1,
                    "Specialized input must preserve incremental native selection");
            int index = decisions.getAndIncrement();
            require(index < 2, "Shared-type cost asked for an unexpected third card");
            JsonObject answer = NativeSession.object("type", "chooseCardsDecision");
            JsonArray chosen = new JsonArray(); chosen.add(NativeSession.cardId(index == 0 ? first : second));
            answer.add("chosenCardIds", chosen); return answer;
        });
        require(decisions.get() == 2, "Optional shared-type cost must allow both explicit card clicks");
    }

    private static void chord(NativeSession session, Player owner) throws Exception {
        List<Card> forests = new ArrayList<>(), bears = new ArrayList<>();
        for (int i = 0; i < 3; i++) forests.add(card(session.game, owner, "Forest", ZoneType.Battlefield));
        for (int i = 0; i < 2; i++) bears.add(card(session.game, owner, "Grizzly Bears", ZoneType.Battlefield));
        card(session.game, owner, "Grizzly Bears", ZoneType.Library);
        Card source = card(session.game, owner, "Chord of Calling", ZoneType.Hand);
        SpellAbility ability = source.getSpellAbilities().get(0);
        AtomicInteger convoked = new AtomicInteger(), paid = new AtomicInteger();
        drive(session, owner, () -> {
            boolean played = PlaySpellAbility.playSpellAbility((PlayerControllerHuman) owner.getController(), owner, ability);
            require(played && ability.getXManaCostPaid() == 2, "Native human Chord X=2 payment failed");
            require(bears.stream().allMatch(Card::isTapped) && forests.stream().allMatch(Card::isTapped), "Explicit convoke or land payment was lost");
            require(session.game.getStack().size() == 1, "Paid Chord did not enter the stack");
        }, input -> {
            String type = input.get("type").getAsString();
            if (type.equals("chooseNumber")) {
                require(input.get("max").getAsInt() >= 2, "Human X was capped before convoke");
                JsonObject result = NativeSession.object("type", "numberDecision"); result.addProperty("chosenNumber", 2); return result;
            }
            if (type.equals("chooseBoardTargets")) {
                int next = convoked.getAndIncrement();
                return boardChoice(input, next < bears.size() ? NativeSession.cardId(bears.get(next)) : null);
            }
            if (type.equals("payManaCost")) {
                Card forest = forests.get(paid.getAndIncrement());
                JsonObject result = NativeSession.object("type", "act"); result.addProperty("actionId", "card:" + forest.getId()); return result;
            }
            throw new AssertionError("Unexpected Chord native choice: " + input);
        });
        require(convoked.get() >= 2 && paid.get() == 3, "Chord did not use two chosen convokers and three chosen lands");
    }

    private static JsonObject boardChoice(JsonObject input, String id) {
        JsonObject output = NativeSession.object("type", "boardTargets");
        JsonArray selected = new JsonArray();
        if (id != null) {
            JsonObject choice = input.getAsJsonArray("candidates").asList().stream().map(JsonElement::getAsJsonObject)
                    .filter(candidate -> candidate.get("id").getAsString().equals(id)).findFirst().orElseThrow();
            selected.add(choice);
        }
        output.add("chosen", selected); return output;
    }
}
