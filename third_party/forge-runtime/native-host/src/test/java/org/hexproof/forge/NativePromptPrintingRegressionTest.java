// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.StaticData;
import forge.card.CardStateName;
import forge.game.GameStage;
import forge.game.card.*;
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import forge.player.PlayerControllerHuman;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import static org.hexproof.forge.NativeCallbackRegressionTest.*;

/** Actual private native callbacks on synthetic boards, including exact physical printings. */
public final class NativePromptPrintingRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                prefs.setPref(FPref.UI_SELECT_FROM_CARD_DISPLAYS, false);
                return null;
            });
            List<String> scenarios = args.length > 1 ? List.of(args[1]) : List.of("printings", "promos", "privacy", "appearances");
            for (String scenario : scenarios) {
                JsonObject config = JsonParser.parseString("{\"gameId\":\"native-prompt-printing-test\",\"seed\":42,\"variant\":\"constructed\",\"startingLife\":20,\"players\":[{\"name\":\"Printing A\",\"deck\":[{\"name\":\"Forest\"}]},{\"name\":\"Printing B\",\"deck\":[{\"name\":\"Forest\"}]}]}").getAsJsonObject();
                if (scenario.equals("promos")) {
                    JsonArray deck = config.getAsJsonArray("players").get(0).getAsJsonObject().getAsJsonArray("deck");
                    for (String number : List.of("199s", "199p")) {
                        JsonObject card = NativeSession.object("name", "Psychic Frog");
                        card.addProperty("setCode", "PMH3");
                        card.addProperty("collectorNumber", number);
                        deck.add(card);
                    }
                }
                try (NativeSession session = new NativeSession(config, base); var scope = session.context.enter()) {
                    base.setTestSession(session);
                    session.game.setAge(GameStage.Play);
                    Player owner = session.game.getPlayers().get(0);
                    session.game.setStartingPlayer(owner);
                    session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, owner, false, 1);
                    switch (scenario) {
                        case "printings", "promos" -> printings(session, owner, scenario.equals("promos"));
                        case "privacy" -> privacy(session, owner);
                        case "appearances" -> appearances(session, owner);
                        default -> throw new IllegalArgumentException("Unknown printing scenario: " + scenario);
                    }
                }
                System.out.println("PASS native prompt printing " + scenario);
            }
        }
    }

    private static void printings(NativeSession session, Player owner, boolean promos) throws Exception {
        Card first = promos ? registeredPromo(session, owner, "199s")
                : printed(session, owner, "Grizzly Bears", "LEA", "199", ZoneType.Library);
        Card second = promos ? registeredPromo(session, owner, "199p")
                : printed(session, owner, "Grizzly Bears", "10E", "268", ZoneType.Library);
        card(session.game, owner, "Lightning Bolt", ZoneType.Library);
        var gui = ((PlayerControllerHuman) owner.getController()).getGui();
        List<CardView> views = List.of(first.getView(), second.getView());
        Map<String, JsonObject> expected = Map.of(NativeSession.cardId(first), NativeSnapshot.identity(first),
                NativeSession.cardId(second), NativeSnapshot.identity(second));
        AtomicInteger decisions = new AtomicInteger();
        drive(session, owner, () -> {
            require(gui.one("Choose printing", views) == second.getView(), "Selection changed physical candidate");
            gui.reveal("Inspect printings", views);
            require(gui.many("Choose and order printings", "Cards", 0, 2, views, null)
                    .equals(List.of(second.getView(), first.getView())), "Ordering changed physical candidates");
            Card hand = session.game.getAction().moveToHand(first, null);
            Card battlefield = session.game.getAction().moveToPlay(second, null, Map.of());
            require(hand.isInZone(ZoneType.Hand) && battlefield.isInZone(ZoneType.Battlefield), "Fixture zone moves failed");
            JsonObject snapshot = NativeSnapshot.capture(session.game, session.id, 0, owner);
            require(find(snapshot, hand).getAsJsonObject("identity").equals(expected.get(NativeSession.cardId(first))),
                    "Hand identity differs from the chosen printing");
            require(find(snapshot, battlefield).getAsJsonObject("identity").equals(expected.get(NativeSession.cardId(second))),
                    "Battlefield identity differs from the chosen printing");
        }, input -> {
            int index = decisions.getAndIncrement();
            String type = input.get("type").getAsString();
            require(!input.toString().contains("Lightning Bolt"), "Prompt disclosed a noncandidate library card");
            for (int viewer : new int[]{-1, 1}) {
                require(!session.snapshot(viewer).contains(first.getName()), "Private candidates leaked to another viewer");
            }
            JsonArray cards = input.getAsJsonArray(type.equals("reorder") ? "items" : "cards");
            require(cards.size() == 2, "Missing same-name printing candidate");
            for (JsonElement entry : cards) {
                JsonObject value = entry.getAsJsonObject();
                if (type.equals("reorder")) value = value.getAsJsonObject("card");
                JsonObject identity = value.getAsJsonObject("identity");
                require(identity.equals(expected.get(value.get("id").getAsString())),
                        "Prompt lost exact printing in " + type + ": " + value);
            }
            if (index == 0 || index == 2) {
                require(type.equals("chooseCards"), "Missing choose/select callback");
                return choose(index == 0 ? List.of(second) : List.of(first, second));
            }
            if (index == 1) {
                require(type.equals("revealCards"), "Missing reveal callback");
                return NativeSession.object("type", "revealCardsAcknowledged");
            }
            require(index == 3 && type.equals("reorder"), "Missing order callback");
            JsonObject response = NativeSession.object("type", "reorderDecision");
            JsonArray ids = new JsonArray(); ids.add("order-1"); ids.add("order-0");
            response.add("orderedIds", ids); return response;
        });
        require(decisions.get() == 4, "Not all printing callbacks ran");
    }

    private static void privacy(NativeSession session, Player owner) throws Exception {
        Card own = printed(session, owner, "Willbender", "TSB", "36", ZoneType.Battlefield);
        Card hidden = card(session.game, session.game.getPlayers().get(1), "Den Protector", ZoneType.Battlefield);
        own.turnFaceDown(true); hidden.turnFaceDown(true);
        require(own.getView().canFaceDownBeShownTo(owner.getView())
                && !hidden.getView().canFaceDownBeShownTo(owner.getView()), "Face-down fixture permissions are wrong");
        CardView detached = new CardView(hidden.getId(), null, "Detached choice");
        var gui = ((PlayerControllerHuman) owner.getController()).getGui();
        drive(session, owner, () -> gui.reveal("Permitted candidates", List.of(own.getView(), hidden.getView(), detached)), input -> {
            require(input.get("type").getAsString().equals("revealCards"), "Missing privacy reveal callback");
            JsonArray cards = input.getAsJsonArray("cards");
            require(cards.get(0).getAsJsonObject().getAsJsonObject("identity").equals(NativeSnapshot.identity(own)),
                    "Permitted owner face-down lookup lost its original printing");
            require(cards.get(1).getAsJsonObject().getAsJsonObject("identity").equals(NativeSession.object("name", "Face-down card")),
                    "Opponent face-down identity leaked");
            require(cards.get(2).getAsJsonObject().getAsJsonObject("identity").equals(NativeSession.object("name", "Detached choice")),
                    "Detached view borrowed a physical card identity");
            require(!input.toString().contains("Den Protector"), "Hidden physical card leaked through candidate lookup");
            for (int viewer : new int[]{-1, 1})
                require(!session.snapshot(viewer).contains("Willbender"), "Owner-only face-down identity leaked");
            return NativeSession.object("type", "revealCardsAcknowledged");
        });
    }

    private static void appearances(NativeSession session, Player owner) throws Exception {
        Card transformed = card(session.game, owner, "Delver of Secrets", ZoneType.Battlefield);
        transformed.setState(CardStateName.Backside, true);
        Card target = card(session.game, owner, "Grizzly Bears", ZoneType.Battlefield);
        Card clone = card(session.game, owner, "Clone", ZoneType.Battlefield);
        clone.addCloneState(CardFactory.getCloneStates(target, clone, clone.getSpellAbilities().get(0)), session.game.getNextTimestamp());
        var tokenPaper = StaticData.instance().getAllTokens().getToken("c_1_1_a_drone_flying_blockflying", "EOE");
        Card token = CardFactory.getCard(tokenPaper, owner, session.game);
        owner.getZone(ZoneType.Battlefield).add(token);
        require(transformed.getName().equals("Insectile Aberration") && clone.getName().equals("Grizzly Bears"), "Current face/copy fixtures failed");
        JsonObject tokenIdentity = NativeSnapshot.identity(token);
        require(tokenIdentity.get("name").getAsString().equals("Drone") && tokenIdentity.get("setCode").getAsString().equals("TEOE")
                && tokenIdentity.get("cardNumber").getAsString().equals("3") && tokenIdentity.get("isToken").getAsBoolean(), "Token fixture changed");
        List<Card> physical = List.of(transformed, clone, token);
        var gui = ((PlayerControllerHuman) owner.getController()).getGui();
        drive(session, owner, () -> gui.reveal("Current appearances", physical.stream().map(Card::getView).toList()), input -> {
            JsonArray cards = input.getAsJsonArray("cards");
            for (int index = 0; index < physical.size(); index++) {
                JsonObject identity = cards.get(index).getAsJsonObject().getAsJsonObject("identity");
                require(identity.equals(NativeSnapshot.identity(physical.get(index))), "Prompt differs from current appearance: " + identity);
                if (index < 2) require(identity.get("setCode").getAsString().isEmpty() && identity.get("cardNumber").getAsString().isEmpty(),
                        "Current face/copy borrowed its original printing");
            }
            return NativeSession.object("type", "revealCardsAcknowledged");
        });
    }

    private static Card printed(NativeSession session, Player owner, String name, String set, String number, ZoneType zone) {
        var paper = FModel.getMagicDb().getCommonCards().getCard(name, set, number);
        require(paper != null && paper.getEdition().equals(set) && paper.getCollectorNumber().equals(number), "Exact printing fixture unavailable: " + name);
        Card card = CardFactory.getCard(paper, owner, session.game);
        owner.getZone(zone).add(card); return card;
    }

    private static Card registeredPromo(NativeSession session, Player owner, String number) {
        var paper = owner.getRegisteredPlayer().getDeck().getMain().toFlatList().stream()
                .filter(card -> card.getCollectorNumber().equals(number)).findFirst().orElseThrow();
        Card card = CardFactory.getCard(paper, owner, session.game);
        owner.getZone(ZoneType.Library).add(card);
        JsonObject identity = NativeSnapshot.identity(card);
        require(identity.get("setCode").getAsString().equals("PMH3")
                && identity.get("cardNumber").getAsString().equals(number), "Lost registered promo identity");
        return card;
    }

    private static JsonObject choose(List<Card> cards) {
        JsonObject response = NativeSession.object("type", "chooseCardsDecision");
        JsonArray ids = new JsonArray(); cards.forEach(card -> ids.add(NativeSession.cardId(card)));
        response.add("chosenCardIds", ids); return response;
    }

    private static JsonObject find(JsonObject snapshot, Card target) {
        for (JsonElement zone : snapshot.getAsJsonArray("zones"))
            for (JsonElement card : zone.getAsJsonObject().getAsJsonArray("cards"))
                if (card.getAsJsonObject().get("id").getAsString().equals(NativeSession.cardId(target))) return card.getAsJsonObject();
        throw new AssertionError("Missing snapshot card " + target);
    }
}
