// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import forge.game.GameStage;
import forge.card.MagicColor;
import forge.game.card.Card;
import forge.game.mana.Mana;
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
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
        }
    }

    private static void run(NativeGuiBase base, String scenario) throws Exception {
        JsonObject config = JsonParser.parseString("{\"gameId\":\"native-priority-test\",\"seed\":42,\"variant\":\"constructed\",\"startingLife\":20,\"players\":[{\"name\":\"Priority A\",\"deck\":[{\"name\":\"Forest\"}]},{\"name\":\"Priority B\",\"deck\":[{\"name\":\"Forest\"}]}]}").getAsJsonObject();
        try (NativeSession session = new NativeSession(config, base)) {
            base.setFailureHandler(session::fail);
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
