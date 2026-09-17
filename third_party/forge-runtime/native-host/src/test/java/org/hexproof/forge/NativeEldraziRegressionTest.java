// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.StaticData;
import forge.deck.DeckSection;
import forge.game.GameStage;
import forge.game.ability.AbilityUtils;
import forge.game.card.*;
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import static org.hexproof.forge.NativeCallbackRegressionTest.*;

/** Real card scripts and real opening-hand procedure; synthetic boards are explicit. */
public final class NativeEldraziRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                prefs.setPref(FPref.UI_SELECT_FROM_CARD_DISPLAYS, false);
                prefs.setPref(FPref.YIELD_AUTO_PASS_NO_ACTIONS, false);
                return null;
            });
            board(base);
            cleanup(base);
            nestedMana(base, false);
            nestedMana(base, true);
            opening(base, true);
            opening(base, false);
        }
        System.out.println("PASS native Eldrazi: sideboard wish, token printing, linked exile, cleanup discard, nested mana, Karn restrictions, opening reveal/decline and first upkeep");
    }

    private static JsonObject config(boolean devourer) {
        JsonObject request = NativeSession.object("gameId", "eldrazi-regression");
        request.addProperty("seed", 42); request.addProperty("variant", "constructed");
        request.addProperty("startingLife", 20); request.addProperty("startingPlayerIndex", 0);
        JsonArray players = new JsonArray();
        for (int seat = 0; seat < 2; seat++) {
            JsonObject player = NativeSession.object("name", "Eldrazi seat " + seat);
            JsonArray deck = new JsonArray(), side = new JsonArray();
            // Mechanism fixture guarantees an opening ability. The GUI suite
            // separately imports the owner's unchanged format-legal 60/15 list.
            for (int i = 0; i < 60; i++) deck.add(NativeSession.object("name",
                    devourer && seat == 0 ? "Devourer of Destiny" : "Forest"));
            if (seat == 0) side.add(NativeSession.object("name", "Walking Ballista"));
            player.add("deck", deck); player.add("sideboard", side); players.add(player);
        }
        request.add("players", players); return request;
    }

    private static void board(NativeGuiBase base) throws Exception {
        try (NativeSession session = new NativeSession(config(false), base); var scope = session.context.enter()) {
            base.setTestSession(session);
            session.game.setAge(GameStage.Play);
            Player owner = session.game.getPlayers().get(0);
            session.game.setStartingPlayer(owner);
            session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, owner, false, 2);
            var side = owner.getRegisteredPlayer().getDeck().get(DeckSection.Sideboard);
            require(side != null && side.countAll() == 1, "Native deck registration dropped the sideboard");
            Card wish = card(session.game, owner, side.toFlatList().get(0).getName(), ZoneType.Sideboard);
            Card karn = card(session.game, owner, "Karn, the Great Creator", ZoneType.Battlefield);
            var ability = karn.getSpellAbilities().stream().filter(sa -> sa.hasParam("Origin")
                    && sa.getParam("Origin").contains("Sideboard")).findFirst().orElseThrow();
            ability.setActivatingPlayer(owner);
            AtomicInteger choices = new AtomicInteger();
            drive(session, owner, () -> {
                AbilityUtils.resolve(ability);
                require(wish.isInZone(ZoneType.Hand), "Karn did not move the chosen sideboard artifact to hand");
            }, input -> {
                String type = input.get("type").getAsString();
                if (type.equals("chooseCards")) {
                    require(!session.snapshot(1).contains("Walking Ballista")
                            && !session.snapshot(-1).contains("Walking Ballista"), "Unchosen sideboard leaked: " + input);
                    require(input.toString().contains("Walking Ballista"), "Karn candidates omit the sideboard artifact");
                    choices.incrementAndGet();
                    JsonObject response = NativeSession.object("type", "chooseCardsDecision");
                    JsonArray ids = new JsonArray(); ids.add(NativeSession.cardId(wish));
                    response.add("chosenCardIds", ids); return response;
                }
                if (type.equals("revealCards")) return NativeSession.object("type", "revealCardsAcknowledged");
                throw new AssertionError("Unexpected Karn prompt: " + input);
            });
            require(choices.get() == 1, "Karn must offer an explicit artifact choice");

            Card first = card(session.game, owner, "Ugin's Labyrinth", ZoneType.Battlefield);
            Card second = card(session.game, owner, "Ugin's Labyrinth", ZoneType.Battlefield);
            Card imprinted = card(session.game, owner, "Devourer of Destiny", ZoneType.Exile);
            imprinted.setExiledWith(first); first.addExiledCard(imprinted);
            var tokenPaper = StaticData.instance().getAllTokens().getToken("c_1_1_a_drone_flying_blockflying", "EOE");
            Card token = CardFactory.getCard(tokenPaper, owner, session.game);
            owner.getZone(ZoneType.Battlefield).add(token);
            for (int viewer : List.of(-1, 0, 1)) {
                JsonObject snapshot = NativeSnapshot.capture(session.game, session.id, viewer, owner);
                JsonObject firstView = find(snapshot, first), secondView = find(snapshot, second);
                require(firstView.get("exiledCardCount").getAsInt() == 1
                        && firstView.getAsJsonArray("exiledCardIds").get(0).getAsString().equals(NativeSession.cardId(imprinted)),
                        "Labyrinth lost its exact public exile relationship");
                require(!secondView.has("exiledCardCount"), "Another copy borrowed the imprint");
                JsonObject identity = find(snapshot, token).getAsJsonObject("identity");
                require(identity.get("setCode").getAsString().equals("TEOE")
                        && identity.get("cardNumber").getAsString().equals("3")
                        && identity.get("name").getAsString().equals("Drone"), "Token points to a normal card printing: " + identity);
            }
            imprinted.turnFaceDown(true);
            JsonObject hidden = find(NativeSnapshot.capture(session.game, session.id, -1, owner), first);
            require(hidden.get("exiledCardCount").getAsInt() == 1
                    && hidden.getAsJsonArray("exiledCardIds").isEmpty(), "Linked exile revealed a hidden card ID");
            owner.getZone(ZoneType.Exile).remove(imprinted); owner.getZone(ZoneType.Hand).add(imprinted);
            require(!find(NativeSnapshot.capture(session.game, session.id, 0, owner), first).has("exiledCardCount"),
                    "Returning the exiled card left a stale imprint badge");
        }
    }

    private static void cleanup(NativeGuiBase base) throws Exception {
        try (NativeSession session = new NativeSession(config(false), base); var scope = session.context.enter()) {
            base.setTestSession(session);
            session.game.setAge(GameStage.Play);
            Player owner = session.game.getPlayers().get(0);
            session.game.setStartingPlayer(owner);
            session.game.getPhaseHandler().devModeSet(PhaseType.CLEANUP, owner, false, 2);
            var hand = new ArrayList<Card>();
            for (int i = 0; i < 9; i++) hand.add(card(session.game, owner, "Island", ZoneType.Hand));
            drive(session, owner, () -> {
                var chosen = owner.getController().chooseCardsToDiscardToMaximumHandSize(2);
                require(chosen.size() == 2 && chosen.contains(hand.get(0)) && chosen.contains(hand.get(1)),
                        "Cleanup lost the complete discard selection");
            }, input -> {
                if (input.get("type").getAsString().equals("reorder")) {
                    var output = NativeSession.object("type", "reorderDecision");
                    var ids = new JsonArray();
                    for (var item : input.getAsJsonArray("items")) ids.add(item.getAsJsonObject().get("id"));
                    output.add("orderedIds", ids); return output;
                }
                require(input.get("type").getAsString().equals("chooseCards")
                        && input.get("min").getAsInt() == 2 && input.get("max").getAsInt() == 2,
                        "Cleanup exposed an incremental one-card choice: " + input);
                require(JsonParser.parseString(session.prompt(0)).getAsJsonObject()
                        .get("decidingPlayerId").getAsString().equals(session.playerId(owner))
                        && !session.snapshot(1).contains("Island"), "Cleanup lost owner privacy");
                var output = NativeSession.object("type", "chooseCardsDecision");
                var ids = new JsonArray(); ids.add(NativeSession.cardId(hand.get(0))); ids.add(NativeSession.cardId(hand.get(1)));
                output.add("chosenCardIds", ids); return output;
            });
        }
    }

    private static JsonObject find(JsonObject snapshot, Card target) {
        for (var zone : snapshot.getAsJsonArray("zones"))
            for (var card : zone.getAsJsonObject().getAsJsonArray("cards"))
                if (card.getAsJsonObject().get("id").getAsString().equals(NativeSession.cardId(target)))
                    return card.getAsJsonObject();
        throw new AssertionError("Missing visible object " + target);
    }

    private static void nestedMana(NativeGuiBase base, boolean karnLock) throws Exception {
        try (NativeSession session = new NativeSession(config(false), base); var scope = session.context.enter()) {
            base.setTestSession(session);
            session.game.setAge(GameStage.Play);
            Player owner = session.game.getPlayers().get(0);
            session.game.setStartingPlayer(owner);
            session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, owner, false, 2);
            Card source = card(session.game, owner, "Sowing Mycospawn", ZoneType.Hand);
            Card boulder = card(session.game, owner, "Giant's Boulder", ZoneType.Battlefield);
            card(session.game, owner, "Eldrazi Temple", ZoneType.Battlefield);
            card(session.game, owner, "Ugin's Labyrinth", ZoneType.Battlefield);
            card(session.game, owner, "Urza's Power Plant", ZoneType.Battlefield);
            for (int i = 0; i < 3; i++) card(session.game, owner, "Wastes", ZoneType.Battlefield);
            if (karnLock) {
                card(session.game, session.game.getPlayers().get(1), "Karn, the Great Creator", ZoneType.Battlefield);
                card(session.game, owner, "Forest", ZoneType.Battlefield);
            }
            var ability = source.getSpellAbilities().get(0); ability.setActivatingPlayer(owner);
            AtomicInteger payments = new AtomicInteger();
            drive(session, owner, () -> {
                require(forge.game.player.PlaySpellAbility.playSpellAbility(owner.getController(), owner, ability),
                        "Nested mana failed to cast the creature");
            }, input -> {
                String before = session.prompt(0);
                try { Thread.sleep(150); } catch (InterruptedException e) { throw new AssertionError(e); }
                require(before.equals(session.prompt(0)), "Native choice changed without a response: " + before + " -> " + session.prompt(0));
                String type = input.get("type").getAsString();
                if (type.equals("chooseBoardTargets")) {
                    JsonObject result = NativeSession.object("type", "boardTargets");
                    JsonArray chosen = new JsonArray(); chosen.add(input.getAsJsonArray("candidates").get(0));
                    result.add("chosen", chosen); return result;
                }
                if (type.equals("chooseFromSelection")) {
                    JsonObject result = NativeSession.object("type", "selectionDecision");
                    JsonArray indices = new JsonArray();
                    for (int index = 0; index < input.getAsJsonArray("options").size(); index++) {
                        if (input.getAsJsonArray("options").get(index).getAsJsonObject().get("label").getAsString().contains("{C}{C}")) {
                            indices.add(index); break;
                        }
                    }
                    if (indices.isEmpty()) indices.add(0);
                    result.add("chosenIndices", indices); return result;
                }
                require(type.equals("payManaCost"), "Unexpected nested mana choice " + input);
                if (karnLock) require(!input.getAsJsonArray("actions").toString().contains("card:" + boulder.getId() + "\""),
                        "Karn-disabled artifact is still offered as a usable mana source");
                if (payments.getAndIncrement() == 0 && !karnLock) {
                    JsonObject result = NativeSession.object("type", "act"); result.addProperty("actionId", "card:" + boulder.getId()); return result;
                }
                if (input.get("canAutoPay").getAsBoolean()) {
                    JsonObject result = NativeSession.object("type", "pay"); result.addProperty("auto", true); return result;
                }
                throw new AssertionError("Nested mana unexpectedly cannot finish: " + input);
            });
            require(payments.get() >= (karnLock ? 1 : 2), "Native payment was not exercised");
        }
    }

    private static void opening(NativeGuiBase base, boolean reveal) {
        try (NativeSession session = new NativeSession(config(true), base); var scope = session.context.enter()) {
            base.setTestSession(session);
            session.start();
            int reveals = 0, digs = 0;
            for (int decision = 0; decision < 120; decision++) {
                JsonObject envelope = JsonParser.parseString(session.prompt(0)).getAsJsonObject();
                JsonObject input = envelope.getAsJsonObject("input");
                String type = input.get("type").getAsString();
                JsonObject output;
                if (type.equals("mulligan")) {
                    output = NativeSession.object("type", "mulliganDecision"); output.addProperty("keep", true);
                } else if (type.equals("chooseCards")) {
                    JsonArray cards = input.getAsJsonArray("cards"), ids = new JsonArray();
                    boolean opening = cards.size() == 7;
                    if (opening) {
                        require(input.get("min").getAsInt() == 0, "Opening reveal must be optional");
                        reveals++;
                        if (reveal) ids.add(cards.get(0).getAsJsonObject().get("id"));
                    } else {
                        require(reveal && cards.size() == 4, "First upkeep did not offer the four looked-at cards: " + input);
                        require(input.get("min").getAsInt() == 0 && input.get("max").getAsInt() == 1,
                                "Devourer must permit keeping zero or one card");
                        digs++; ids.add(cards.get(2).getAsJsonObject().get("id"));
                    }
                    output = NativeSession.object("type", "chooseCardsDecision"); output.add("chosenCardIds", ids);
                } else if (type.equals("revealCards")) {
                    output = NativeSession.object("type", "revealCardsAcknowledged");
                } else if (type.equals("chooseBoolean")) {
                    output = NativeSession.object("type", "decision"); output.addProperty("value", true);
                } else if (type.equals("chooseAction")) {
                    if (session.game.getPhaseHandler().getPhase() == PhaseType.MAIN1) break;
                    output = NativeSession.object("type", "pass");
                } else throw new AssertionError("Unexpected Devourer prompt: " + input);
                JsonObject response = NativeSession.object("type", type); response.add("output", output); session.submit(response);
            }
            require(reveals == 1 && digs == (reveal ? 1 : 0), "Opening action or first-upkeep trigger was skipped");
            Player owner = session.game.getPlayers().get(0);
            require(owner.getCardsIn(ZoneType.Exile).size() == (reveal ? 3 : 0), "Devourer exiled the wrong number of cards");
            require(owner.getCardsIn(ZoneType.Library).size() == (reveal ? 50 : 53), "First-player library count drifted after opening effect");
        }
    }
}
