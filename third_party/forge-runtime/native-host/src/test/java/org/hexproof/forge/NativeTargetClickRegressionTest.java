// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.game.GameStage;
import forge.game.ability.AbilityUtils;
import forge.game.card.Card;
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.spellability.SpellAbility;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import forge.player.PlayerControllerHuman;
import java.util.concurrent.atomic.AtomicInteger;
import static org.hexproof.forge.NativeCallbackRegressionTest.*;

/** Native cross-target restrictions reject clicks without terminating the game. */
public final class NativeTargetClickRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                prefs.setPref(FPref.UI_SELECT_FROM_CARD_DISPLAYS, false);
                return null;
            });
            JsonObject config = JsonParser.parseString("{\"gameId\":\"target-click\",\"seed\":42,\"variant\":\"constructed\",\"startingLife\":20,\"players\":[{\"name\":\"Target A\",\"deck\":[{\"name\":\"Swamp\"}]},{\"name\":\"Target B\",\"deck\":[{\"name\":\"Forest\"}]}]}").getAsJsonObject();
            try (NativeSession session = new NativeSession(config, base); var scope = session.context.enter()) {
                base.setTestSession(session);
                Player owner = session.game.getPlayers().get(0);
                PlayerControllerHuman human = (PlayerControllerHuman) owner.getController();
                session.game.setAge(GameStage.Play);
                session.game.setStartingPlayer(owner);
                session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, owner, false, 33);
                Card bear = card(session.game, owner, "Grizzly Bears", ZoneType.Graveyard);
                Card lion = card(session.game, owner, "Silvercoat Lion", ZoneType.Graveyard);
                Card giant = card(session.game, owner, "Hill Giant", ZoneType.Graveyard);
                Card source = card(session.game, owner, "Agadeem's Awakening", ZoneType.Hand);
                SpellAbility ability = source.getSpellAbilities().get(0);
                ability.setXManaCostPaid(4);
                ability.setActivatingPlayer(owner);
                AtomicInteger clicks = new AtomicInteger();
                drive(session, owner, () -> {
                    require(human.chooseTargetsFor(ability), "Target selection did not complete");
                    require(ability.getTargets().getTargetCards().size() == 2
                            && ability.getTargets().getTargetCards().contains(bear)
                            && ability.getTargets().getTargetCards().contains(giant)
                            && !ability.getTargets().getTargetCards().contains(lion),
                            "Explicit graveyard targets changed");
                    AbilityUtils.resolve(ability);
                    require(owner.getCardsIn(ZoneType.Battlefield).stream().anyMatch(c -> c.getId() == bear.getId())
                            && owner.getCardsIn(ZoneType.Battlefield).stream().anyMatch(c -> c.getId() == giant.getId())
                            && lion.isInZone(ZoneType.Graveyard), "Native reanimation moved the wrong cards");
                }, input -> {
                    require(input.get("type").getAsString().equals("chooseBoardTargets"), "Unexpected target input: " + input);
                    int click = clicks.getAndIncrement();
                    require(click < 4, "Rejected click did not preserve a usable target input");
                    require(ability.getTargets().getTargetCards().size() == (click == 0 ? 0 : click == 3 ? 2 : 1),
                            "Rejected equal-mana-value target changed the native target set");
                    if (click == 0) {
                        JsonObject invalid = NativeSession.object("kind", "card"); invalid.addProperty("id", "card-unavailable");
                        reject(session, answer(invalid));
                        JsonObject candidate = input.getAsJsonArray("candidates").get(0).getAsJsonObject();
                        reject(session, answer(candidate, candidate));
                    }
                    if (click == 2)
                        require(input.getAsJsonObject("presentation").get("description").getAsString()
                                .contains("different mana values"), "Native rejection message was lost");
                    if (click == 3) return answer();
                    Card selected = click == 0 ? bear : click == 1 ? lion : giant;
                    JsonObject candidate = input.getAsJsonArray("candidates").asList().stream()
                            .map(JsonElement::getAsJsonObject)
                            .filter(value -> value.get("id").getAsString().equals(NativeSession.cardId(selected)))
                            .findFirst().orElseThrow();
                    return answer(candidate);
                });
                require(clicks.get() == 4 && !session.hasFailed(), "Target rejection failed the native session");
            }
        }
        System.out.println("PASS native graveyard target rejection and continuation");
    }

    private static JsonObject answer(JsonObject... candidates) {
        JsonObject answer = NativeSession.object("type", "boardTargets");
        JsonArray chosen = new JsonArray();
        for (JsonObject candidate : candidates) chosen.add(candidate);
        answer.add("chosen", chosen);
        return answer;
    }

    private static void reject(NativeSession session, JsonObject output) {
        String before = session.prompt(0);
        JsonObject envelope = NativeSession.object("type", "chooseBoardTargets"); envelope.add("output", output);
        boolean rejected = false;
        try { session.submit(envelope); } catch (IllegalArgumentException expected) { rejected = true; }
        require(rejected && before.equals(session.prompt(0)) && !session.hasFailed(),
                "Invalid target response consumed or failed the native prompt");
    }
}
