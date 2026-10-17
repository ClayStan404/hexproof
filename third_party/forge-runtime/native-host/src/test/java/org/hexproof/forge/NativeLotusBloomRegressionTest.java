// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import forge.card.MagicColor;
import forge.game.GameStage;
import forge.game.card.Card;
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import static org.hexproof.forge.NativeCallbackRegressionTest.*;

/** Actual Lotus Bloom costs, color decisions and automatic human payments. */
public final class NativeLotusBloomRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                prefs.setPref(FPref.UI_SELECT_FROM_CARD_DISPLAYS, false);
                return null;
            });
            List<String> scenarios = args.length > 1 ? List.of(args[1]) : List.of(
                    "standalone-white", "standalone-blue", "standalone-black", "standalone-red", "standalone-green",
                    "standalone-preview", "manual-blue", "manual-other", "manual-decline", "auto-blue", "auto-generic");
            for (String scenario : scenarios) {
                try (NativeSession session = new NativeSession(NativeIsolationRegressionTest.setup("lotus-bloom", 42), base);
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
        System.out.println("PASS native Lotus Bloom: explicit colors and automatic payment");
    }

    private static void run(NativeSession session, Player owner, String scenario) throws Exception {
        boolean standalone = scenario.startsWith("standalone-");
        boolean automatic = scenario.startsWith("auto-");
        Card lotus = card(session.game, owner, "Lotus Bloom", ZoneType.Battlefield);
        Card island = scenario.equals("manual-other") || scenario.equals("manual-decline")
                ? card(session.game, owner, "Island", ZoneType.Battlefield) : null;
        Card spell = standalone ? null : card(session.game, owner,
                scenario.equals("auto-generic") ? "Basalt Monolith" : scenario.equals("auto-blue") ? "Divination" : "Opt",
                ZoneType.Hand);
        Card previewSpell = scenario.equals("standalone-preview")
                ? card(session.game, owner, "Spiketail Drakeling", ZoneType.Hand) : null;
        if (previewSpell != null) for (int i = 0; i < 3; i++) card(session.game, owner, "Plains", ZoneType.Battlefield);
        AtomicInteger payments = new AtomicInteger(), colors = new AtomicInteger(), confirmations = new AtomicInteger();
        AtomicReference<String> paymentId = new AtomicReference<>();
        int colorIndex = previewSpell != null ? 4
                : standalone ? List.of("white", "blue", "black", "red", "green").indexOf(scenario.substring(11))
                : scenario.equals("manual-other") ? 4 : 1;
        byte selectedColor = new byte[] { MagicColor.WHITE, MagicColor.BLUE, MagicColor.BLACK, MagicColor.RED, MagicColor.GREEN }[colorIndex];
        drive(session, owner, () -> {
            var ability = standalone ? lotus.getManaAbilities().get(0) : spell.getSpellAbilities().get(0);
            if (previewSpell != null) {
                // Smart priority checks native candidates before the player clicks Bloom.
                // The AI planner rejects sacrificing it for this cost with three other
                // sources, but may leave a blue expression on the reusable mana ability.
                var controller = owner.getController();
                require(!NativePriority.autoPassEligible(owner, List.of(
                        previewSpell.getAllPossibleAbilities(owner, true).get(0), ability)),
                        "Priority preview passed with an uncertain Lotus Bloom source");
                require(owner.getController() == controller && lotus.isInPlay() && owner.getManaPool().isEmpty(),
                        "Priority preview changed the controller or consumed resources");
            }
            require(owner.getController().playChosenSpellAbility(ability),
                    scenario + ": activation failed");
            if (scenario.equals("manual-decline")) {
                require(lotus.isInPlay() && !lotus.isTapped() && owner.getManaPool().isEmpty(),
                        "Declining sacrifice did not restore Lotus Bloom");
                require(colors.get() == 0 && confirmations.get() == 1 && payments.get() == 2,
                        "Declining sacrifice did not resume the original payment");
            } else {
                require(lotus.isInZone(ZoneType.Graveyard), scenario + ": Lotus Bloom was not sacrificed");
                int expected = standalone || scenario.equals("manual-other") ? 3 : automatic ? 0 : 2;
                require(owner.getManaPool().totalMana() == expected, scenario + ": wrong remaining mana");
                if (expected > 0)
                    require(owner.getManaPool().getAmountOfColor(selectedColor) == expected,
                            scenario + ": color choice was replaced by the payment color");
                require(colors.get() == (automatic ? 0 : 1), scenario + ": missing or repeated color choice");
                require(confirmations.get() == (automatic ? 0 : 1), scenario + ": missing or repeated sacrifice confirmation");
            }
            if (spell != null) require(spell.isInZone(ZoneType.Stack), scenario + ": spell was not cast");
            if (island != null) require(island.isTapped(), scenario + ": follow-up mana source was not used");
        }, input -> {
            String type = input.get("type").getAsString();
            if (type.equals("payManaCost")) {
                int count = payments.incrementAndGet();
                String id = input.get("paymentId").getAsString();
                if (count == 1) paymentId.set(id);
                else require(paymentId.get().equals(id), "Nested Lotus decision replaced the payment identity");
                if (automatic) {
                    require(count == 1 && input.get("canAutoPay").getAsBoolean(), "Automatic payment unavailable or repeated");
                    return NativeSession.object("type", "pay");
                }
                require(count <= 2, "Manual payment did not complete");
                if (count == 2) {
                    require(island != null && lotus.isInPlay() == scenario.equals("manual-decline"),
                            "Returned payment has the wrong Lotus state");
                    require(input.get("manaCost").getAsString().equals("{U}"), "Non-required color paid a blue symbol");
                }
                JsonObject output = NativeSession.object("type", "act");
                output.addProperty("actionId", "card:" + (count == 1 ? lotus.getId() : island.getId()));
                return output;
            }
            if (type.equals("chooseBoolean")) {
                require(confirmations.incrementAndGet() == 1, "Repeated sacrifice confirmation");
                JsonObject output = NativeSession.object("type", "decision");
                output.addProperty("value", !scenario.equals("manual-decline"));
                return output;
            }
            require(type.equals("chooseFromSelection") && colors.incrementAndGet() == 1,
                    "Unexpected Lotus decision: " + input);
            JsonArray options = input.getAsJsonArray("options");
            require(options.size() == 5 && input.get("minTotal").getAsInt() == 1 && input.get("maxTotal").getAsInt() == 1,
                    "Lotus Bloom did not offer all five colors");
            for (int i = 0; i < 5; i++)
                require(options.get(i).getAsJsonObject().get("label").getAsString().equals(
                        List.of("WHITE", "BLUE", "BLACK", "RED", "GREEN").get(i)), "Native color option changed");
            JsonObject output = NativeSession.object("type", "selectionDecision");
            JsonArray indices = new JsonArray(); indices.add(colorIndex); output.add("chosenIndices", indices);
            return output;
        });
        System.out.println("PASS Lotus Bloom " + scenario);
    }
}
