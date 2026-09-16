// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.game.GameStage;
import forge.game.ability.AbilityUtils;
import forge.game.card.Card;
import forge.game.card.CardCollection;
import forge.game.phase.PhaseType;
import forge.game.player.DelayedReveal;
import forge.game.player.Player;
import forge.game.spellability.SpellAbility;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import static org.hexproof.forge.NativeCallbackRegressionTest.*;

/** Real Collected Company resolution and native single-choice callbacks on synthetic boards. */
public final class NativeDelayedRevealRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                prefs.setPref(FPref.UI_SELECT_FROM_CARD_DISPLAYS, false);
                return null;
            });
            for (boolean single : List.of(false, true)) {
                JsonObject config = JsonParser.parseString("{\"gameId\":\"delayed-reveal-test\",\"seed\":42,\"variant\":\"constructed\",\"startingLife\":20,\"players\":[{\"name\":\"Reveal A\",\"deck\":[{\"name\":\"Forest\"}]},{\"name\":\"Reveal B\",\"deck\":[{\"name\":\"Forest\"}]}]}").getAsJsonObject();
                try (NativeSession session = new NativeSession(config, base)) {
                    base.setFailureHandler(session::fail);
                    session.game.setAge(GameStage.Play);
                    Player owner = session.game.getPlayers().get(0);
                    session.game.setStartingPlayer(owner);
                    session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, owner, false, 1);
                    run(session, owner, single);
                }
            }
        }
        System.out.println("PASS native delayed reveal: complete private look before Collected Company and single-card selection");
    }

    private static void run(NativeSession session, Player owner, boolean single) throws Exception {
        Card bears = card(session.game, owner, "Grizzly Bears", ZoneType.Library);
        Card elves = card(session.game, owner, "Llanowar Elves", ZoneType.Library);
        Card bolt = card(session.game, owner, "Lightning Bolt", ZoneType.Library);
        Card forest = card(session.game, owner, "Forest", ZoneType.Library);
        Card dreadmaw = card(session.game, owner, "Colossal Dreadmaw", ZoneType.Library);
        Card mountain = card(session.game, owner, "Mountain", ZoneType.Library);
        Card unlooked = card(session.game, owner, "Primeval Titan", ZoneType.Library);
        Card privateHand = card(session.game, owner, "Solitude", ZoneType.Hand);
        Card opposingHand = card(session.game, session.game.getPlayers().get(1), "Thoughtseize", ZoneType.Hand);
        Card company = card(session.game, owner, "Collected Company", ZoneType.Hand);
        List<Card> topSix = List.of(bears, elves, bolt, forest, dreadmaw, mountain);
        Set<String> lookedNames = new HashSet<>();
        for (Card c : topSix) lookedNames.add(c.getName());
        SpellAbility ability = company.getSpellAbilities().get(0);
        ability.setActivatingPlayer(owner);
        AtomicInteger decisions = new AtomicInteger();
        drive(session, owner, () -> {
            if (single) {
                Card chosen = owner.getController().chooseSingleEntityForEffect(
                        new CardCollection(List.of(bears, elves)),
                        new DelayedReveal(topSix, ZoneType.Library, owner.getView()),
                        ability, "Choose one of the eligible creatures", false, owner, null);
                require(chosen == bears, "Native single-choice callback changed the explicit selection");
            } else {
                // Choose zero creatures, a legal CoCo decision, so the policy can
                // focus on the owner's private look without another seat's reveal.
                AbilityUtils.resolve(ability);
                require(owner.getCardsIn(ZoneType.Battlefield).isEmpty(), "CoCo ignored the explicit empty selection");
                List<Card> library = new ArrayList<>(owner.getCardsIn(ZoneType.Library));
                require(library.size() == 7 && library.get(0) == unlooked,
                        "CoCo did not put the six inspected cards beneath the unlooked seventh card");
            }
        }, input -> {
            String type = input.get("type").getAsString();
            String raw = input.toString();
            for (Card secret : List.of(unlooked, privateHand, opposingHand)) {
                require(!raw.contains(secret.getName()), "Delayed reveal included an unrelated private identity");
                require(!raw.contains("\"" + NativeSession.cardId(secret) + "\""), "Delayed reveal included an unrelated private object ID");
            }
            for (int viewer : List.of(-1, 1)) {
                String snapshot = session.snapshot(viewer);
                for (Card looked : topSix) {
                    require(!snapshot.contains("\"name\":\"" + looked.getName() + "\""), "Private library look leaked into another viewer's snapshot");
                    require(!snapshot.contains("\"" + NativeSession.cardId(looked) + "\""), "Private library object ID leaked into another viewer's snapshot");
                }
            }
            JsonObject envelope = JsonParser.parseString(session.prompt(0)).getAsJsonObject();
            require(envelope.get("decidingPlayerId").getAsString().equals("player-0"),
                    "Private delayed reveal assigned the wrong deciding player");
            int decision = decisions.getAndIncrement();
            if (decision == 0) {
                require(type.equals("revealCards"), "Selection appeared before the complete delayed reveal");
                Set<String> names = new HashSet<>();
                for (JsonElement element : input.getAsJsonArray("cards"))
                    names.add(element.getAsJsonObject().getAsJsonObject("identity").get("name").getAsString());
                require(names.equals(lookedNames), "Delayed reveal omitted nonselectable cards from the top six");
                return NativeSession.object("type", "revealCardsAcknowledged");
            }
            if (decision == 1) {
                require(type.equals("chooseCards"), "Delayed reveal did not lead to a native card choice");
                require(input.getAsJsonArray("cards").size() == 2, "CoCo eligibility was expanded to noncreatures or high-cost creatures");
                JsonObject response = NativeSession.object("type", "chooseCardsDecision");
                JsonArray chosen = new JsonArray();
                if (single) chosen.add(NativeSession.cardId(bears));
                response.add("chosenCardIds", chosen);
                return response;
            }
            require(!single && decision == 2 && type.equals("reorder"), "Unexpected delayed-reveal callback");
            JsonObject response = NativeSession.object("type", "reorderDecision");
            JsonArray ordered = new JsonArray();
            for (JsonElement item : input.getAsJsonArray("items")) ordered.add(item.getAsJsonObject().get("id"));
            require(ordered.size() == 6, "CoCo omitted cards from the bottom-library ordering");
            response.add("orderedIds", ordered);
            return response;
        });
        require(decisions.get() == (single ? 2 : 3), "Missing native delayed-reveal decisions");
    }
}
