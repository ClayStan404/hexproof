// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import forge.card.MagicColor;
import forge.game.GameStage;
import forge.game.ability.AbilityFactory;
import forge.game.card.Card;
import forge.game.cost.CostExile;
import forge.game.mana.Mana;
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.player.PlaySpellAbility;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import forge.player.PlayerControllerHuman;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import static org.hexproof.forge.NativeCallbackRegressionTest.*;

/** Checks automatic-pass metadata against actual native priority inputs and card scripts. */
public final class NativePriorityRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                prefs.setPref(FPref.YIELD_AUTO_PASS_NO_ACTIONS, false);
                prefs.setPref(FPref.UI_SHOW_ACTIONABLE_HIGHLIGHTS, false);
                return null;
            });
            for (String scenario : List.of("empty", "mana", "land", "unaffordable", "affordable",
                    "zero-cost", "mixed-abilities", "exile", "command", "optional-payment",
                    "sacrifice-mana", "floating-mana", "phyrexian")) run(base, scenario);
            for (String scenario : List.of("payable-instant", "alternative-cost", "no-action"))
                necrodominance(base, scenario);
        }
    }

    private static void necrodominance(NativeGuiBase base, String scenario) throws Exception {
        JsonObject config = JsonParser.parseString("{\"gameId\":\"native-necro-priority-test\",\"seed\":42,\"variant\":\"constructed\",\"startingLife\":20,\"players\":[{\"name\":\"Necro A\",\"deck\":[{\"name\":\"Forest\"}]},{\"name\":\"Necro B\",\"deck\":[{\"name\":\"Forest\"}]}]}").getAsJsonObject();
        try (NativeSession session = new NativeSession(config, base); var scope = session.context.enter()) {
            base.setTestSession(session);
            session.game.setAge(GameStage.Play);
            Player owner = session.game.getPlayers().get(0);
            session.game.setStartingPlayer(owner);
            session.game.getPhaseHandler().devModeSet(PhaseType.END_OF_TURN, owner, false, 1);
            Card necro = card(session.game, owner, "Necrodominance", ZoneType.Battlefield);
            List<Card> drawn = new ArrayList<>();
            String spellName = scenario.equals("payable-instant") ? "Lightning Bolt" : "Soul Spike";
            if (!scenario.equals("no-action")) drawn.add(card(session.game, owner, spellName, ZoneType.Library));
            if (scenario.equals("alternative-cost")) {
                drawn.add(card(session.game, owner, "Duress", ZoneType.Library));
                drawn.add(card(session.game, owner, "Duress", ZoneType.Library));
            }
            while (drawn.size() < 7) drawn.add(card(session.game, owner, "Forest", ZoneType.Library));
            if (scenario.equals("payable-instant")) card(session.game, owner, "Mountain", ZoneType.Battlefield);
            session.game.getAction().checkStaticAbilities();
            session.game.copyLastState();
            require(owner.getMaxHandSize() == 5, "Necrodominance did not apply its real maximum hand size");
            var draw = AbilityFactory.getAbility(necro.getSVar("TrigDraw"), necro);
            draw.setActivatingPlayer(owner);
            draw.setTrigger(necro.getTriggers().getFirst());
            var human = (PlayerControllerHuman) owner.getController();
            AtomicInteger priority = new AtomicInteger(), discards = new AtomicInteger(), discardOrders = new AtomicInteger();
            drive(session, owner, () -> {
                // Resolve the published trigger's actual life cost and draw effect;
                // the priority window remains in the same own end step afterward.
                require(PlaySpellAbility.playSpellAbilityNoStack(human, owner, draw, false),
                        "Native Necrodominance life payment was declined");
                require(owner.getLife() == 13 && owner.getCardsIn(ZoneType.Hand).containsAll(drawn)
                        && owner.getCardsIn(ZoneType.Hand).size() == 7,
                        "Necrodominance did not pay seven life and draw the exact new hand");
                require(session.game.getStack().isEmpty()
                        && session.game.getPhaseHandler().is(PhaseType.END_OF_TURN, owner),
                        "Necrodominance fixture lost its post-resolution own end-step window");
                if (scenario.equals("alternative-cost")) require(drawn.getFirst().getAllPossibleAbilities(owner, true)
                        .stream().anyMatch(ability -> ability.getPayCosts() != null
                                && ability.getPayCosts().getTotalMana().isZero()
                                && ability.getPayCosts().getCostParts().stream().anyMatch(CostExile.class::isInstance)),
                        "Actual Soul Spike candidate omitted its two-black-card alternative cost");
                require(human.chooseSpellAbilityToPlay() == null, "Native priority ignored an explicit pass");
                require(owner.getCardsIn(ZoneType.Hand).size() == 7 && owner.getLife() == 13,
                        "Priority prediction mutated the newly drawn hand or life");
                require(session.game.getPhaseHandler().devAdvanceToPhase(PhaseType.CLEANUP),
                        "Native cleanup could not follow the retained priority window");
                require(owner.getCardsIn(ZoneType.Hand).size() == 5
                        && owner.getCardsIn(ZoneType.Exile).size() == 2
                        && owner.getCardsIn(ZoneType.Graveyard).isEmpty(),
                        "Necrodominance cleanup did not discard to five through its exile replacement: hand="
                                + owner.getCardsIn(ZoneType.Hand).size() + " exile=" + owner.getCardsIn(ZoneType.Exile).size()
                                + " graveyard=" + owner.getCardsIn(ZoneType.Graveyard).size());
            }, input -> {
                String type = input.get("type").getAsString();
                if (type.equals("chooseNumber")) {
                    JsonObject output = NativeSession.object("type", "numberDecision");
                    output.addProperty("chosenNumber", 7); return output;
                }
                if (type.equals("chooseBoolean")) {
                    JsonObject output = NativeSession.object("type", "decision");
                    output.addProperty("value", true); return output;
                }
                if (type.equals("chooseAction")) {
                    priority.incrementAndGet();
                    require(input.get("autoPassEligible").getAsBoolean() == scenario.equals("no-action"),
                            "Wrong post-Necrodominance automatic-pass hint for " + scenario + ": " + input);
                    if (!scenario.equals("no-action")) require(input.getAsJsonArray("actions").asList().stream()
                            .anyMatch(value -> value.getAsJsonObject().get("cardId").getAsString()
                                    .equals(NativeSession.cardId(drawn.getFirst()))),
                            "Newly drawn instant was absent from native own end-step actions");
                    return NativeSession.object("type", "pass");
                }
                if (type.equals("reorder")) {
                    require(discards.get() == 1 && input.getAsJsonArray("items").size() == 2,
                            "Cleanup ordered cards outside its explicit discard pair");
                    discardOrders.incrementAndGet();
                    JsonObject output = NativeSession.object("type", "reorderDecision");
                    JsonArray ordered = new JsonArray();
                    input.getAsJsonArray("items").forEach(item -> ordered.add(item.getAsJsonObject().get("id")));
                    output.add("orderedIds", ordered); return output;
                }
                require(type.equals("chooseCards") && input.get("min").getAsInt() == 2
                        && input.get("max").getAsInt() == 2 && priority.get() == 1,
                        "Cleanup preceded priority or asked for an incorrect discard count: " + input);
                discards.incrementAndGet();
                JsonObject output = NativeSession.object("type", "chooseCardsDecision");
                JsonArray selected = new JsonArray();
                selected.add(NativeSession.cardId(drawn.get(drawn.size() - 1)));
                selected.add(NativeSession.cardId(drawn.get(drawn.size() - 2)));
                output.add("chosenCardIds", selected); return output;
            });
            require(priority.get() == 1 && discards.get() == 1 && discardOrders.get() == 1,
                    "Missing post-Necrodominance priority or cleanup decision");
            System.out.println("PASS native Necrodominance " + scenario + " end-step priority before cleanup to five");
        }
    }

    private static void run(NativeGuiBase base, String scenario) throws Exception {
        JsonObject config = JsonParser.parseString("{\"gameId\":\"native-priority-test\",\"seed\":42,\"variant\":\"constructed\",\"startingLife\":20,\"players\":[{\"name\":\"Priority A\",\"deck\":[{\"name\":\"Forest\"}]},{\"name\":\"Priority B\",\"deck\":[{\"name\":\"Forest\"}]}]}").getAsJsonObject();
        try (NativeSession session = new NativeSession(config, base); var scope = session.context.enter()) {
            base.setTestSession(session);
            session.game.setAge(GameStage.Play);
            Player owner = session.game.getPlayers().get(0);
            session.game.setStartingPlayer(owner);
            session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, owner, false, 1);
            boolean expected;
            String candidate = "";
            switch (scenario) {
                case "empty" -> expected = true;
                case "mana" -> {
                    card(session.game, owner, "Mountain", ZoneType.Battlefield);
                    expected = true;
                }
                case "land" -> {
                    candidate = NativeSession.cardId(card(session.game, owner, "Forest", ZoneType.Hand));
                    expected = false;
                }
                case "unaffordable", "affordable" -> {
                    candidate = NativeSession.cardId(card(session.game, owner, "Lightning Bolt", ZoneType.Hand));
                    if (scenario.equals("affordable")) card(session.game, owner, "Mountain", ZoneType.Battlefield);
                    expected = scenario.equals("unaffordable");
                }
                case "mixed-abilities" -> {
                    Card factory = card(session.game, owner, "Mishra's Factory", ZoneType.Battlefield);
                    card(session.game, owner, "Forest", ZoneType.Battlefield);
                    candidate = NativeSession.cardId(factory);
                    require(factory.getAllPossibleAbilities(owner, true).stream().anyMatch(a -> a.isManaAbility())
                            && factory.getAllPossibleAbilities(owner, true).stream().anyMatch(a -> !a.isManaAbility()),
                            "Mixed source fixture lacks both native ability types");
                    expected = false;
                }
                case "exile", "command" -> {
                    Card squee = card(session.game, owner, "Squee, the Immortal",
                            scenario.equals("exile") ? ZoneType.Exile : ZoneType.Command);
                    if (scenario.equals("command")) owner.addCommander(squee);
                    candidate = NativeSession.cardId(squee);
                    for (int i = 0; i < 3; i++) card(session.game, owner, "Mountain", ZoneType.Battlefield);
                    expected = false;
                }
                case "zero-cost" -> {
                    candidate = NativeSession.cardId(card(session.game, owner, "Ornithopter", ZoneType.Hand));
                    expected = false;
                }
                case "sacrifice-mana" -> {
                    card(session.game, owner, "Lion's Eye Diamond", ZoneType.Battlefield);
                    candidate = NativeSession.cardId(card(session.game, owner, "Lightning Bolt", ZoneType.Hand));
                    expected = false;
                }
                case "floating-mana" -> {
                    Card source = card(session.game, owner, "Mountain", ZoneType.Battlefield);
                    owner.getManaPool().addMana(new Mana(MagicColor.RED, source, null, owner));
                    expected = false;
                }
                case "phyrexian" -> {
                    candidate = NativeSession.cardId(card(session.game, owner, "Gut Shot", ZoneType.Hand));
                    expected = false;
                }
                case "optional-payment" -> {
                    candidate = NativeSession.cardId(card(session.game, owner, "Into the Roil", ZoneType.Hand));
                    card(session.game, owner, "Forest", ZoneType.Battlefield);
                    expected = false;
                }
                default -> throw new IllegalArgumentException("Unknown priority scenario");
            }
            final boolean eligible = expected;
            final String expectedCandidate = candidate;
            AtomicInteger prompts = new AtomicInteger();
            session.game.getAction().checkStaticAbilities();
            drive(session, owner, () -> session.guis.get(0).human.chooseSpellAbilityToPlay(), input -> {
                require(input.get("type").getAsString().equals("chooseAction"), "Did not receive actual priority input");
                require(input.has("autoPassEligible") && input.get("autoPassEligible").getAsBoolean() == eligible,
                        "Wrong automatic-pass hint for " + scenario + ": " + input);
                if (!expectedCandidate.isEmpty()) require(input.getAsJsonArray("actions").asList().stream()
                        .anyMatch(a -> expectedCandidate.equals(a.getAsJsonObject().get("cardId").getAsString())),
                        "Expected source absent from native priority options: " + scenario);
                prompts.incrementAndGet();
                return NativeSession.object("type", "pass");
            });
            require(prompts.get() == 1, "Priority scenario bypassed its explicit native input");
            require(owner.getCardsIn(ZoneType.Battlefield).stream().noneMatch(Card::isTapped),
                    "Priority prediction spent a battlefield mana source");
            require(owner.getManaPool().isEmpty() != scenario.equals("floating-mana"),
                    "Priority prediction changed floating mana");
            require(owner.getLife() == 20, "Priority prediction paid life");
            System.out.println("PASS native priority " + scenario);
        }
    }
}
