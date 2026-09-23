// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.JsonObject;
import forge.card.MagicColor;
import forge.game.GameStage;
import forge.game.card.Card;
import forge.game.mana.Mana;
import forge.game.phase.PhaseType;
import forge.game.player.PlaySpellAbility;
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

/** Real human auto-payment with conditional multi-mana lands and cost floors. */
public final class NativeAutoPayRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                prefs.setPref(FPref.UI_SELECT_FROM_CARD_DISPLAYS, false);
                return null;
            });
            for (String scenario : List.of("tron-tax", "missing-tron", "tapped-tower", "damping",
                    "colored", "two-mana", "floating", "manual")) {
                try (NativeSession session = new NativeSession(NativeIsolationRegressionTest.setup("tron-auto-pay", 42), base);
                        var scope = session.context.enter()) {
                    base.setTestSession(session);
                    Player owner = session.game.getPlayers().get(0);
                    session.game.setAge(GameStage.Play);
                    session.game.setStartingPlayer(owner);
                    session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, owner, false, 14);
                    run(session, owner, scenario);
                }
            }
        }
        System.out.println("PASS native auto-pay: Trinisphere and Tron");
    }

    private static void run(NativeSession session, Player owner, String scenario) throws Exception {
        List<Card> lands = new ArrayList<>();
        for (String name : List.of("Eldrazi Temple", "Forest", "Urza's Mine", "Urza's Power Plant",
                "Urza's Power Plant", "Urza's Tower"))
            if (!scenario.equals("missing-tron") || !name.equals("Urza's Power Plant"))
                lands.add(card(session.game, owner, name, ZoneType.Battlefield));
        Card tower = lands.get(lands.size() - 1);
        if (scenario.equals("floating")) owner.getManaPool().addMana(new Mana(MagicColor.COLORLESS, tower, null, owner));
        if (scenario.equals("tapped-tower")) tower.setTapped(true);
        if (!scenario.equals("two-mana")) card(session.game, owner, "Trinisphere", ZoneType.Battlefield);
        if (scenario.equals("damping")) card(session.game, owner, "Damping Sphere", ZoneType.Battlefield);
        Card spell = card(session.game, owner, scenario.equals("colored") ? "Llanowar Elves"
                : scenario.equals("two-mana") ? "Mind Stone" : "Expedition Map", ZoneType.Hand);
        AtomicInteger decisions = new AtomicInteger();
        drive(session, owner, () -> {
            require(PlaySpellAbility.playSpellAbility((PlayerControllerHuman) owner.getController(), owner,
                    spell.getSpellAbilities().get(0)), "Spell could not be cast");
            List<String> tapped = lands.stream().filter(Card::isTapped).map(Card::getName).toList();
            System.out.println(scenario + " tapped: " + tapped + "; floating: " + owner.getManaPool().totalMana());
            if (scenario.equals("tron-tax") || scenario.equals("manual")) {
                require(tapped.equals(List.of("Urza's Tower")), "Expected only the three-mana Tower: " + tapped);
                require(owner.getManaPool().isEmpty(), "Three-mana cost left unexpected floating mana");
            } else if (scenario.equals("missing-tron") || scenario.equals("damping")) {
                require(tapped.size() == 3 && owner.getManaPool().isEmpty(), "Counted inactive or replaced Tron mana");
            } else if (scenario.equals("tapped-tower")) {
                require(tower.isTapped() && tapped.size() == 3, "Reused an already tapped Tower");
            } else if (scenario.equals("colored")) {
                require(tapped.contains("Forest") && tapped.size() == 2 && owner.getManaPool().isEmpty(),
                        "Colorless mana replaced required green or over-tapped: " + tapped);
            } else if (scenario.equals("two-mana") || scenario.equals("floating")) {
                require(tapped.size() == 1 && !tower.isTapped() && owner.getManaPool().isEmpty(),
                        "Did not prefer exact two mana to three: " + tapped);
            }
            require(spell.isInZone(ZoneType.Stack), "Casting did not put the spell on the stack");
        }, input -> {
            require(input.get("type").getAsString().equals("payManaCost"), "Unexpected casting decision: " + input);
            require(decisions.incrementAndGet() == 1, "Auto-pay did not complete the cost");
            String expectedCost = scenario.equals("colored") ? "{2}{G}" : scenario.equals("two-mana") ? "{2}" : "{3}";
            require(input.get("manaCost").getAsString().equals(expectedCost), "Wrong native cost: " + input);
            require(input.get("canAutoPay").getAsBoolean(), "Auto-pay not offered");
            if (scenario.equals("manual")) {
                JsonObject choice = NativeSession.object("type", "act");
                choice.addProperty("actionId", "card:" + tower.getId());
                return choice;
            }
            return NativeSession.object("type", "pay");
        });
    }
}
