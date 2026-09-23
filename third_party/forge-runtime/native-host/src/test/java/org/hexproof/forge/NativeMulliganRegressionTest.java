// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.game.card.Card;
import forge.game.player.Player;
import forge.game.zone.ZoneType;
import forge.gamemodes.match.input.InputLondonMulligan;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import java.util.*;
import static org.hexproof.forge.NativeCallbackRegressionTest.require;

/** Real London mulligan decisions retain seven cards until the player keeps. */
public final class NativeMulliganRegressionTest {
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
            for (int[] scenario : List.of(new int[]{2, 1}, new int[]{2, 2}, new int[]{2, 0},
                    new int[]{2, 7}, new int[]{3, 1}, new int[]{3, 2}, new int[]{3, 8}))
                run(base, scenario[0], scenario[1]);
        }
        System.out.println("PASS native London mulligan: keep before bottom, repeated/free mulligans, forced keep, exact private selections");
    }

    private static void run(NativeGuiBase base, int playerCount, int mulligans) {
        JsonObject config = NativeSession.object("gameId", "mulligan-" + playerCount + "-" + mulligans);
        config.addProperty("seed", 42); config.addProperty("variant", "constructed");
        config.addProperty("startingLife", 20); config.addProperty("startingPlayerIndex", 0);
        JsonArray players = new JsonArray();
        String[] names = {"Forest", "Island", "Mountain", "Plains", "Swamp", "Lightning Bolt", "Grizzly Bears", "Opt"};
        for (int seat = 0; seat < playerCount; seat++) {
            JsonObject player = NativeSession.object("name", "Mulligan seat " + seat);
            JsonArray deck = new JsonArray();
            for (int count = 0; count < 60; count++)
                deck.add(NativeSession.object("name", seat == 0 ? names[count % names.length] : "Wastes"));
            player.add("deck", deck); players.add(player);
        }
        config.add("players", players);
        try (NativeSession session = new NativeSession(config, base); var scope = session.context.enter()) {
            base.setTestSession(session);
            Player owner = session.game.getRegisteredPlayers().get(0);
            session.start();
            int free = playerCount > 2 ? 1 : 0;
            int required = Math.max(0, mulligans - free);
            int taken = 0, keepPrompts = 0, bottomPrompts = 0;
            boolean kept = false, reachedPriority = false;
            List<Card> finalHand = List.of(), selected = List.of();
            long previousPrompt = -1;
            for (int decisions = 0; decisions < 40; decisions++) {
                JsonObject envelope = JsonParser.parseString(session.prompt(0)).getAsJsonObject();
                JsonObject input = envelope.getAsJsonObject("input");
                String kind = input.get("type").getAsString();
                int seat = Integer.parseInt(envelope.get("decidingPlayerId").getAsString().substring("player-".length()));
                require(envelope.get("promptId").getAsLong() > previousPrompt, "Mulligan retained a stale response prompt");
                previousPrompt = envelope.get("promptId").getAsLong();
                if (kind.equals("chooseAction")) {
                    reachedPriority = true;
                    break;
                }
                require(kind.equals("mulligan") || kind.equals("mulliganPutBack"),
                        "Unexpected decision before keep/bottom: " + kind + " after " + taken + " mulligans");
                if (seat != 0) {
                    require(kind.equals("mulligan"), "Another player received a put-back prompt without taking a mulligan");
                    submitKeep(session, true);
                    continue;
                }
                require(owner.getCardsIn(ZoneType.Hand).size() == 7
                                && owner.getCardsIn(ZoneType.Library).size() == 53,
                        "Mulligan shortened the replacement hand before its keep decision");
                verifyPrivacy(session, owner, 7, playerCount);
                if (kind.equals("mulligan")) {
                    require(!kept && bottomPrompts == 0, "Mulligan asked whether to keep after putting cards back");
                    require(input.get("mulliganCount").getAsInt() == taken, "Mulligan count lost a native redraw");
                    require(taken < 7 + free, "An empty kept hand still offered an extra mulligan");
                    keepPrompts++;
                    if (taken < mulligans) {
                        taken++;
                        submitKeep(session, false);
                    } else {
                        finalHand = new ArrayList<>(owner.getCardsIn(ZoneType.Hand));
                        kept = true;
                        submitKeep(session, true);
                    }
                } else {
                    boolean forcedKeep = mulligans == 7 + free && taken == mulligans;
                    require(kept || forcedKeep, "Cards were put back before the player chose to keep the replacement hand");
                    require(required > 0 && input.get("count").getAsInt() == required,
                            "Initial/free mulligan requested cards or paid mulligan used the wrong count");
                    require(session.guis.get(0).human.getInputProxy().getInput() instanceof InputLondonMulligan,
                            "Put-back bypassed the actual native London mulligan input");
                    require(!input.has("cancellable") || !input.get("cancellable").getAsBoolean(),
                            "Native automatic card choice was exposed as cancellation");
                    require(++bottomPrompts == 1, "A kept hand requested multiple bottom selections");
                    if (forcedKeep) finalHand = new ArrayList<>(owner.getCardsIn(ZoneType.Hand));
                    verifyCandidates(input, finalHand);
                    selected = new ArrayList<>(finalHand.subList(finalHand.size() - required, finalHand.size()));
                    Collections.reverse(selected);
                    verifyRejectedSelections(session, owner, selected, playerCount);
                    submitBottom(session, selected);
                    List<Card> expectedHand = new ArrayList<>(finalHand); expectedHand.removeAll(selected);
                    require(new HashSet<>(owner.getCardsIn(ZoneType.Hand)).equals(new HashSet<>(expectedHand)),
                            "Put-back removed a card other than the explicit selection");
                    List<Card> library = new ArrayList<>(owner.getCardsIn(ZoneType.Library));
                    require(library.size() == 53 + required
                                    && library.subList(library.size() - required, library.size()).equals(selected),
                            "Selected cards did not reach the library bottom in response order");
                    verifyPrivacy(session, owner, 7 - required, playerCount);
                }
            }
            require(reachedPriority, "Mulligan procedure did not finish within its bounded decision count");
            require(taken == mulligans && keepPrompts == mulligans + (required == 7 ? 0 : 1),
                    "Replacement hands did not receive exactly one keep/mulligan decision each");
            require(bottomPrompts == (required == 0 ? 0 : 1), "Initial or free mulligan opened an unnecessary put-back decision");
            require(owner.getCardsIn(ZoneType.Hand).size() == 7 - required,
                    "Native mulligan procedure finished with the wrong hand size");
            for (int seat = playerCount - 1; seat > 0; seat--) {
                JsonObject concede = NativeSession.object("type", "directive"); concede.addProperty("player", seat);
                concede.add("directive", NativeSession.object("type", "concede")); session.submit(concede);
            }
            require(session.gameOver(), "Mulligan regression left the native game running");
            System.out.println("PASS native mulligan players=" + playerCount + " redraws=" + mulligans + " bottom=" + required);
        }
    }

    private static void verifyCandidates(JsonObject input, List<Card> hand) {
        Set<String> expected = new HashSet<>();
        for (Card card : hand) expected.add(NativeSession.cardId(card));
        Set<String> ids = new HashSet<>();
        for (JsonElement element : input.getAsJsonArray("handCardIds")) ids.add(element.getAsString());
        require(ids.equals(expected), "Put-back candidates differ from the current private seven-card hand");
        Set<String> identities = new HashSet<>();
        for (JsonElement element : input.getAsJsonArray("cards")) {
            JsonObject card = element.getAsJsonObject();
            require(card.getAsJsonObject("identity").has("name"), "Put-back candidate lacks its printable identity");
            identities.add(card.get("id").getAsString());
        }
        require(identities.equals(expected), "Put-back identities differ from the private candidate IDs");
    }

    private static void verifyRejectedSelections(NativeSession session, Player owner, List<Card> selected, int playerCount) {
        List<String> valid = selected.stream().map(NativeSession::cardId).toList();
        List<List<String>> invalid = new ArrayList<>();
        invalid.add(valid.subList(0, valid.size() - 1));
        List<String> tooMany = new ArrayList<>(valid); tooMany.add(valid.get(0)); invalid.add(tooMany);
        List<String> foreign = new ArrayList<>(valid);
        foreign.set(0, NativeSession.cardId(session.game.getRegisteredPlayers().get(1).getCardsIn(ZoneType.Hand).getFirst()));
        invalid.add(foreign);
        if (valid.size() > 1) {
            List<String> duplicate = new ArrayList<>(valid); duplicate.set(1, duplicate.get(0)); invalid.add(duplicate);
        }
        for (List<String> ids : invalid) {
            JsonObject output = NativeSession.object("type", "mulliganPutBackDecision");
            JsonArray cards = new JsonArray(); ids.forEach(cards::add); output.add("cardIds", cards);
            reject(session, owner, output, playerCount);
        }
        reject(session, owner, NativeSession.object("type", "cancel"), playerCount);
    }

    private static void reject(NativeSession session, Player owner, JsonObject output, int playerCount) {
        String before = session.prompt(0);
        List<Card> hand = new ArrayList<>(owner.getCardsIn(ZoneType.Hand));
        List<Card> library = new ArrayList<>(owner.getCardsIn(ZoneType.Library));
        List<String> snapshots = new ArrayList<>();
        for (int viewer = -1; viewer < playerCount; viewer++) snapshots.add(session.snapshot(viewer));
        JsonObject response = NativeSession.object("type", "mulliganPutBack"); response.add("output", output);
        boolean rejected = false;
        try { session.submit(response); } catch (IllegalArgumentException expected) { rejected = true; }
        require(rejected && before.equals(session.prompt(0)), "Invalid put-back response advanced the native decision");
        require(hand.equals(new ArrayList<>(owner.getCardsIn(ZoneType.Hand)))
                        && library.equals(new ArrayList<>(owner.getCardsIn(ZoneType.Library))),
                "Invalid put-back response mutated the native hand or library");
        for (int viewer = -1; viewer < playerCount; viewer++)
            require(snapshots.get(viewer + 1).equals(session.snapshot(viewer)), "Invalid put-back response changed a private snapshot");
    }

    private static void verifyPrivacy(NativeSession session, Player owner, int handSize, int playerCount) {
        Set<String> expected = new HashSet<>();
        for (Card card : owner.getCardsIn(ZoneType.Hand)) expected.add(NativeSession.cardId(card));
        Set<String> visible = new HashSet<>();
        JsonObject own = JsonParser.parseString(session.snapshot(0)).getAsJsonObject();
        for (JsonElement element : own.getAsJsonArray("zones")) {
            JsonObject zone = element.getAsJsonObject();
            if (!zone.get("ownerId").getAsString().equals("player-0") || !zone.get("zone").getAsString().equals("hand")) continue;
            require(zone.get("count").getAsInt() == handSize, "Owner snapshot lost the current mulligan hand count");
            for (JsonElement entry : zone.getAsJsonArray("cards")) {
                JsonObject card = entry.getAsJsonObject();
                require(card.getAsJsonObject("identity").has("name"), "Owner cannot inspect the replacement hand");
                visible.add(card.get("id").getAsString());
            }
        }
        require(visible.equals(expected), "Owner snapshot does not expose exactly the current hand");
        for (int viewer = -1; viewer < playerCount; viewer++) {
            String snapshot = session.snapshot(viewer);
            for (Card card : owner.getCardsIn(ZoneType.Library))
                require(!snapshot.contains("\"" + NativeSession.cardId(card) + "\""), "Library card ID escaped the hidden zone");
            if (viewer == 0) continue;
            for (Card card : owner.getCardsIn(ZoneType.Hand)) {
                require(!snapshot.contains("\"" + NativeSession.cardId(card) + "\""), "Replacement hand ID escaped to another viewer");
                require(!snapshot.contains("\"name\":\"" + card.getName() + "\""), "Replacement hand identity escaped to another viewer");
            }
        }
    }

    private static void submitKeep(NativeSession session, boolean keep) {
        JsonObject output = NativeSession.object("type", "mulliganDecision"); output.addProperty("keep", keep);
        JsonObject response = NativeSession.object("type", "mulligan"); response.add("output", output);
        session.submit(response);
    }

    private static void submitBottom(NativeSession session, List<Card> selected) {
        JsonObject output = NativeSession.object("type", "mulliganPutBackDecision");
        JsonArray cards = new JsonArray(); selected.forEach(card -> cards.add(NativeSession.cardId(card)));
        output.add("cardIds", cards);
        JsonObject response = NativeSession.object("type", "mulliganPutBack"); response.add("output", output);
        session.submit(response);
    }
}
