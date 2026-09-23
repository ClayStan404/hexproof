// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.game.GameStage;
import forge.game.ability.AbilityFactory;
import forge.game.ability.AbilityUtils;
import forge.game.card.Card;
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.player.PlaySpellAbility;
import forge.game.spellability.SpellAbility;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import forge.player.PlayerControllerHuman;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import static org.hexproof.forge.NativeCallbackRegressionTest.*;

/** Human payment and graveyard targeting text from actual published card scripts. */
public final class NativeCardTextRegressionTest {
    private static void readable(String text) {
        for (String token : List.of("Card.nonCreature", "Card.OppCtrl", "Remembered.sameName",
                "Creature.TopGraveyardCreature", "Creature.YouCtrl"))
            require(!text.contains(token), "Internal selector reached player text: " + text);
    }

    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                prefs.setPref(FPref.UI_SELECT_FROM_CARD_DISPLAYS, false);
                return null;
            });
            JsonObject config = JsonParser.parseString("{\"gameId\":\"card-text\",\"seed\":42,\"variant\":\"constructed\",\"startingLife\":20,\"players\":[{\"name\":\"Text A\",\"deck\":[{\"name\":\"Swamp\"}]},{\"name\":\"Text B\",\"deck\":[{\"name\":\"Forest\"}]}]}").getAsJsonObject();
            try (NativeSession session = new NativeSession(config, base); var scope = session.context.enter()) {
                base.setTestSession(session);
                Player owner = session.game.getPlayers().get(0);
                Player opponent = session.game.getPlayers().get(1);
                PlayerControllerHuman human = (PlayerControllerHuman) owner.getController();
                session.game.setAge(GameStage.Play);
                session.game.setStartingPlayer(owner);
                session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, owner, false, 2);
                for (int i = 0; i < 5; i++) card(session.game, owner, "Swamp", ZoneType.Battlefield);
                Card bear = card(session.game, owner, "Grizzly Bears", ZoneType.Graveyard);
                Card lion = card(session.game, owner, "Silvercoat Lion", ZoneType.Graveyard);
                Card giant = card(session.game, owner, "Hill Giant", ZoneType.Graveyard);
                AtomicReference<String> current = new AtomicReference<>();
                AtomicInteger payments = new AtomicInteger(), graveyardTargets = new AtomicInteger(), optionalCosts = new AtomicInteger();
                drive(session, owner, () -> {
                    for (String name : List.of("Duress", "Deadly Cover-Up", "Shallow Grave")) {
                        current.set(name);
                        Card spell = card(session.game, owner, name, ZoneType.Hand);
                        SpellAbility ability = spell.getSpellAbilities().get(0);
                        ability.setActivatingPlayer(owner);
                        readable(ability.getStackDescription());
                        require(!PlaySpellAbility.playSpellAbility(human, owner, ability),
                                "Payment cancellation cast " + name);
                        require(spell.isInZone(ZoneType.Hand) && session.game.getStack().isEmpty(),
                                "Payment cancellation changed zones for " + name);
                    }
                    current.set("Emptiness");
                    Card source = card(session.game, owner, "Emptiness", ZoneType.Battlefield);
                    SpellAbility ability = AbilityFactory.getAbility(source.getSVar("TrigReturn"), source);
                    ability.setActivatingPlayer(owner);
                    ability.getTargets().add(bear);
                    require(human.chooseNewTargetsFor(ability, value -> true, false) != null,
                            "Readable target prompt lost its choice");
                    require(ability.getTargets().getTargetCards().size() == 1
                            && ability.getTargets().getTargetCards().get(0).equalsWithGameTimestamp(lion),
                            "Emptiness selected a different graveyard card");
                    AbilityUtils.resolve(ability);
                    require(owner.getCardsIn(ZoneType.Battlefield).stream().anyMatch(c -> c.getId() == lion.getId())
                            && giant.isInZone(ZoneType.Graveyard) && bear.isInZone(ZoneType.Graveyard),
                            "Emptiness returned a different creature");
                }, input -> {
                    String type = input.get("type").getAsString();
                    String detail = input.getAsJsonObject("presentation").get("description").getAsString();
                    readable(detail);
                    if (type.equals("chooseFromSelection")) {
                        require(current.get().equals("Deadly Cover-Up")
                                && input.getAsJsonObject("presentation").get("title").getAsString().equals("Choose optional costs")
                                && detail.isEmpty(), "Optional cost reused the previous spell's payment text: " + input);
                        JsonObject answer = NativeSession.object("type", "selectionDecision");
                        answer.add("chosenIndices", new JsonArray());
                        optionalCosts.incrementAndGet();
                        return answer;
                    }
                    if (type.equals("payManaCost")) {
                        require(detail.contains("Pay Mana Cost:"), "Readable payment lost its live cost");
                        switch (current.get()) {
                            case "Duress" -> require(detail.contains("noncreature, nonland")
                                    && detail.contains(opponent.getName()), "Duress lost its restriction or actual target");
                            case "Deadly Cover-Up" -> require(detail.contains("If evidence was collected")
                                    && !detail.contains("up to zero"), "Conditional evidence text became misleading");
                            case "Shallow Grave" -> require(detail.contains("top creature card")
                                    && detail.split("gains haste", -1).length == 2, "Shallow Grave text is incomplete or duplicated");
                            default -> throw new AssertionError("Unexpected payment source");
                        }
                        payments.incrementAndGet();
                        return NativeSession.object("type", "cancel");
                    }
                    require(type.equals("chooseBoardTargets"), "Unexpected card text decision: " + input);
                    boolean emptiness = current.get().equals("Emptiness");
                    if (emptiness) {
                        graveyardTargets.incrementAndGet();
                        require(detail.contains("mana value 3 or less from your graveyard"), "Target prompt lost its rule and zone");
                        require(input.getAsJsonArray("candidates").asList().stream().noneMatch(value ->
                                value.getAsJsonObject().get("id").getAsString().equals(NativeSession.cardId(giant))),
                                "Text-only change widened the graveyard target restriction");
                    }
                    JsonObject selected = input.getAsJsonArray("candidates").asList().stream()
                            .map(JsonElement::getAsJsonObject).filter(value -> emptiness
                                    ? value.get("id").getAsString().equals(NativeSession.cardId(lion))
                                    : value.get("kind").getAsString().equals("player")).findFirst().orElseThrow();
                    JsonObject answer = NativeSession.object("type", "boardTargets");
                    JsonArray chosen = new JsonArray(); chosen.add(selected); answer.add("chosen", chosen);
                    return answer;
                });
                require(payments.get() == 3 && graveyardTargets.get() == 1 && optionalCosts.get() == 1,
                        "Missing payment, graveyard target or optional cost text coverage");
            }
        }
        System.out.println("PASS native readable card payment and target text");
    }
}
