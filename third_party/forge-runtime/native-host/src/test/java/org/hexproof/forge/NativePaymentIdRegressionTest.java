// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package org.hexproof.forge;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import forge.game.GameStage;
import forge.game.card.Card;
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
import java.util.concurrent.atomic.AtomicReference;
import static org.hexproof.forge.NativeCallbackRegressionTest.card;
import static org.hexproof.forge.NativeCallbackRegressionTest.drive;
import static org.hexproof.forge.NativeCallbackRegressionTest.require;

/** One mana payment keeps its id across steps. The next spell gets another. */
public final class NativePaymentIdRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                prefs.setPref(FPref.UI_SELECT_FROM_CARD_DISPLAYS, false);
                return null;
            });
            JsonObject config = NativeIsolationRegressionTest.setup("payment-id", 42);
            try (NativeSession session = new NativeSession(config, base); var scope = session.context.enter()) {
                base.setTestSession(session);
                Player owner = session.game.getPlayers().get(0);
                session.game.setAge(GameStage.Play);
                session.game.setStartingPlayer(owner);
                session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, owner, false, 2);
                for (int i = 0; i < 4; i++)
                    card(session.game, owner, "Forest", ZoneType.Battlefield);
                List<String> bears = new ArrayList<>();
                List<String> elves = new ArrayList<>();
                AtomicReference<List<String>> current = new AtomicReference<>(bears);
                PlayerControllerHuman human = (PlayerControllerHuman) owner.getController();
                drive(session, owner, () -> {
                    Card bear = card(session.game, owner, "Grizzly Bears", ZoneType.Hand);
                    require(PlaySpellAbility.playSpellAbility(human, owner, bear.getSpellAbilities().get(0)),
                            "Grizzly Bears was not cast");
                    require(bear.isInZone(ZoneType.Stack), "Grizzly Bears did not reach the stack");
                    session.game.getStack().reset();
                    session.game.getAction().moveToGraveyard(bear, null);
                    current.set(elves);
                    Card elf = card(session.game, owner, "Llanowar Elves", ZoneType.Hand);
                    require(PlaySpellAbility.playSpellAbility(human, owner, elf.getSpellAbilities().get(0)),
                            "Llanowar Elves was not cast; phase " + session.game.getPhaseHandler().getPhase()
                                    + " stack " + session.game.getStack().size());
                    require(elf.isInZone(ZoneType.Stack), "Llanowar Elves did not reach the stack");
                }, input -> payOneForest(input, current.get()));
                require(bears.size() >= 2 && bears.stream().distinct().count() == 1,
                        "Grizzly Bears payment steps did not share one id: " + bears);
                require(elves.size() == 1, "Llanowar Elves did not take one payment step: " + elves);
                require(!bears.get(0).equals(elves.get(0)), "Two spells shared a payment id");
            }
        }
        System.out.println("PASS native paymentId");
    }

    private static JsonObject payOneForest(JsonObject input, List<String> ids) {
        require(input.get("type").getAsString().equals("payManaCost"), "Unexpected payment decision: " + input);
        require(!input.has("paymentId") || input.get("paymentId").isJsonPrimitive(), "paymentId is not text");
        require(input.has("paymentId"), "payManaCost omitted paymentId");
        String paymentId = input.get("paymentId").getAsString();
        require(paymentId.matches("sa:[1-9][0-9]*"), "Unexpected paymentId " + paymentId);
        ids.add(paymentId);
        String actionId = null;
        for (JsonElement element : input.getAsJsonArray("actions")) {
            JsonObject action = element.getAsJsonObject();
            String id = action.get("id").getAsString();
            String label = action.has("label") ? action.get("label").getAsString() : "";
            if (id.startsWith("card:") && label.startsWith("Forest")) {
                actionId = id;
                break;
            }
        }
        require(actionId != null, "Payment offered no land to tap");
        JsonObject act = NativeSession.object("type", "act");
        act.addProperty("actionId", actionId);
        return act;
    }
}
