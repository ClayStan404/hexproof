// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.game.card.Card;
import forge.game.player.Player;
import forge.game.zone.ZoneType;
import forge.gamemodes.match.input.InputConfirmMulligan;
import forge.gamemodes.match.input.InputLondonMulligan;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import java.util.*;
import static org.hexproof.forge.NativeCallbackRegressionTest.require;

/** Actual Serum Powder input, asynchronous effect and paid London bookkeeping. */
public final class NativeSerumPowderRegressionTest {
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
            for (int[] scenario : List.of(new int[]{2, 0, 2, 0}, new int[]{2, 1, 2, 0},
                    new int[]{2, 1, 1, 1}, new int[]{2, 1, 1, 2},
                    new int[]{3, 1, 1, 0}, new int[]{3, 2, 1, 0}))
                run(base, scenario[0], scenario[1], scenario[2], scenario[3]);
            concedeDuringBottom(base);
        }
        System.out.println("PASS native Serum Powder: owner actions, confirmation decline, London debt, repeated/reset/free redraws, bottomed source, private snapshots, terminal cancellation");
    }

    private static JsonObject config(int players) {
        JsonObject config = NativeSession.object("gameId", "serum-powder-" + players);
        config.addProperty("seed", 42); config.addProperty("variant", "constructed");
        config.addProperty("startingLife", 20); config.addProperty("startingPlayerIndex", 0);
        JsonArray entries = new JsonArray();
        // Deliberately synthetic all-Powder hands isolate repeated native actions.
        for (int seat = 0; seat < players; seat++) {
            JsonObject entry = NativeSession.object("name", "Powder seat " + seat);
            JsonArray deck = new JsonArray();
            for (int i = 0; i < 60; i++) deck.add(NativeSession.object("name", seat == 0 ? "Serum Powder" : "Wastes"));
            entry.add("deck", deck); entries.add(entry);
        }
        config.add("players", entries); return config;
    }

    private static void run(NativeGuiBase base, int players, int mulligans, int repeats, int mode) {
        try (NativeSession session = new NativeSession(config(players), base); var scope = session.context.enter()) {
            base.setTestSession(session); session.start();
            Player owner = session.game.getRegisteredPlayers().get(0);
            ordinaryMulligans(session, owner, mulligans);
            int owed = Math.max(0, mulligans - (players > 2 ? 1 : 0));
            int handSize = 7 - owed, exiled = 0;
            long before = promptId(session);
            require(session.guis.get(0).human.getInputProxy().getInput() instanceof InputConfirmMulligan,
                    "Powder action bypassed the real native mulligan input");
            reject(session, NativeSession.object("type", "act"));
            JsonObject foreign = NativeSession.object("type", "act");
            foreign.addProperty("actionId", "card:" + session.game.getRegisteredPlayers().get(1).getCardsIn(ZoneType.Hand).getFirst().getId());
            reject(session, foreign);
            Set<String> originalHand = ids(owner.getCardsIn(ZoneType.Hand));
            activate(session, owner);
            require(kind(session).equals("chooseBoolean"), "Powder did not use its native confirmation");
            require(JsonParser.parseString(session.prompt(0)).getAsJsonObject().getAsJsonObject("sourceCard")
                    .getAsJsonObject("identity").get("name").getAsString().equals("Serum Powder"), "Confirmation lost native card context");
            decision(session, false);
            require(kind(session).equals("mulligan") && promptId(session) > before
                    && ids(owner.getCardsIn(ZoneType.Hand)).equals(originalHand)
                    && owner.getCardsIn(ZoneType.Library).size() == 53
                    && owner.getCardsIn(ZoneType.Exile).isEmpty(), "Declining Powder bottomed or mutated the hand");
            verifyActions(session, owner); verifyPrivacy(session, owner, players);
            for (int count = 0; count < repeats; count++) {
                Card selected = activate(session, owner);
                Set<String> hand = ids(owner.getCardsIn(ZoneType.Hand));
                Set<String> priorExile = ids(owner.getCardsIn(ZoneType.Exile));
                decision(session, true);
                Set<String> bottomed = Set.of();
                if (count == 0 && owed > 0) {
                    require(kind(session).equals("mulliganPutBack")
                            && input(session).get("count").getAsInt() == owed
                            && session.guis.get(0).human.getInputProxy().getInput() instanceof InputLondonMulligan,
                            "Paid Powder did not complete its still-owed native London bottom");
                    List<Card> cards = new ArrayList<>(owner.getCardsIn(ZoneType.Hand));
                    cards.remove(selected);
                    if (mode == 1) cards.addFirst(selected);
                    List<Card> chosen = cards.subList(0, owed);
                    bottomed = ids(chosen); bottom(session, chosen);
                }
                require(kind(session).equals("mulligan") && owner.getStats().getMulliganCount() == mulligans,
                        "Powder changed the ordinary mulligan count or failed to restore the input");
                if (mode == 1 && count == 0) {
                    require(owner.getCardsIn(ZoneType.Exile).isEmpty()
                            && owner.getCardsIn(ZoneType.Hand).size() == handSize,
                            "Bottoming the selected Powder still exiled a hand");
                    JsonObject stale = NativeSession.object("type", "act"); stale.addProperty("actionId", "card:" + selected.getId());
                    reject(session, stale);
                    // A remaining copy still works, with no repeated bottom debt.
                    hand = ids(owner.getCardsIn(ZoneType.Hand)); activate(session, owner); decision(session, true);
                    require(kind(session).equals("mulligan"), "Remaining Powder required another bottom");
                    bottomed = Set.of();
                }
                hand.removeAll(bottomed); priorExile.addAll(hand); exiled += handSize;
                require(ids(owner.getCardsIn(ZoneType.Exile)).equals(priorExile)
                        && owner.getCardsIn(ZoneType.Hand).size() == handSize
                        && owner.getCardsIn(ZoneType.Library).size() == 60 - exiled - handSize,
                        "Powder published an intermediate hand or exiled/drew the wrong physical cards");
                require(Collections.disjoint(ids(owner.getCardsIn(ZoneType.Hand)), hand), "Powder redrew an exiled card");
                verifyActions(session, owner); verifyPrivacy(session, owner, players);
            }
            if (mode == 2) {
                ordinaryMulligans(session, owner, 1); mulligans++;
                require(owner.getCardsIn(ZoneType.Hand).size() == 7, "Ordinary redraw did not reset the full London hand");
                activate(session, owner); decision(session, true);
                int nextOwed = mulligans;
                require(kind(session).equals("mulliganPutBack") && input(session).get("count").getAsInt() == nextOwed,
                        "Next ordinary redraw retained the previous paid-bottom counter");
                Card requested = owner.getCardsIn(ZoneType.Hand).getFirst();
                List<Card> cards = new ArrayList<>(owner.getCardsIn(ZoneType.Hand)); cards.remove(requested);
                bottom(session, cards.subList(0, nextOwed));
                handSize = 7 - nextOwed; exiled += handSize;
                require(kind(session).equals("mulligan") && owner.getCardsIn(ZoneType.Hand).size() == handSize
                        && owner.getCardsIn(ZoneType.Exile).size() == exiled, "Reset London Powder drew the wrong count");
            }
            keep(session, true);
            require(!kind(session).equals("mulliganPutBack"), "Keeping after Powder charged the same London bottom twice");
            require(owner.getCardsIn(ZoneType.Hand).size() == handSize, "Keeping changed the completed Powder hand");
            for (int seat = players - 1; seat > 0; seat--) concede(session, seat);
            require(session.gameOver(), "Powder regression did not terminate");
            System.out.println("PASS native Powder players=" + players + " mulligans=" + mulligans + " repeats=" + repeats + " mode=" + mode + " hand=" + handSize);
        }
    }

    private static void concedeDuringBottom(NativeGuiBase base) {
        try (NativeSession session = new NativeSession(config(2), base); var scope = session.context.enter()) {
            base.setTestSession(session); session.start();
            Player owner = session.game.getRegisteredPlayers().get(0);
            ordinaryMulligans(session, owner, 1); activate(session, owner); decision(session, true);
            require(kind(session).equals("mulliganPutBack"), "Cancellation fixture did not reach nested native bottom");
            concede(session, 1);
            require(session.gameOver() && !session.hasFailed(), "Concession during Powder bottom left a failed session");
            require(owner.getCardsIn(ZoneType.Exile).isEmpty(), "Cancelled Powder still exiled the hand");
        }
    }

    private static void ordinaryMulligans(NativeSession session, Player owner, int count) {
        int before = owner.getStats().getMulliganCount();
        for (int step = 0; step < count; step++) {
            require(kind(session).equals("mulligan"), "Ordinary redraw lacked a keep/mulligan decision");
            keep(session, false);
            while (!JsonParser.parseString(session.prompt(0)).getAsJsonObject().get("decidingPlayerId").getAsString().equals("player-0")) keep(session, true);
        }
        require(owner.getStats().getMulliganCount() == before + count, "Ordinary mulligans changed their count");
    }

    private static Card activate(NativeSession session, Player owner) {
        verifyActions(session, owner);
        Card selected = owner.getCardsIn(ZoneType.Hand).getFirst();
        JsonObject output = NativeSession.object("type", "act"); output.addProperty("actionId", "card:" + selected.getId());
        answer(session, "mulligan", output); return selected;
    }

    private static void verifyActions(NativeSession session, Player owner) {
        require(kind(session).equals("mulligan"), "Powder choices escaped the mulligan family");
        JsonArray actions = input(session).getAsJsonArray("actions");
        require(actions != null, "Native mulligan bridge omitted Serum Powder actions");
        Set<String> expected = ids(owner.getCardsIn(ZoneType.Hand)), actual = new HashSet<>();
        for (JsonElement element : actions) {
            JsonObject action = element.getAsJsonObject();
            require(action.get("type").getAsString().equals("activateAbility"), "Powder action is untyped");
            actual.add(action.get("cardId").getAsString());
        }
        require(actual.equals(expected), "Mulligan actions include stale, foreign or missing Powder cards");
    }

    private static void verifyPrivacy(NativeSession session, Player owner, int players) {
        JsonObject own = JsonParser.parseString(session.snapshot(0)).getAsJsonObject();
        for (JsonElement element : own.getAsJsonArray("zones")) {
            JsonObject zone = element.getAsJsonObject();
            if (!zone.get("ownerId").getAsString().equals("player-0")) continue;
            String kind = zone.get("zone").getAsString();
            if (kind.equals("library")) require(zone.get("count").getAsInt() == owner.getCardsIn(ZoneType.Library).size(),
                    "Powder returned a stale intermediate library snapshot");
            if (!kind.equals("hand")) continue;
            Set<String> visible = new HashSet<>();
            for (JsonElement card : zone.getAsJsonArray("cards")) visible.add(card.getAsJsonObject().get("id").getAsString());
            require(zone.get("count").getAsInt() == owner.getCardsIn(ZoneType.Hand).size()
                    && visible.equals(ids(owner.getCardsIn(ZoneType.Hand))), "Powder returned an intermediate replacement hand snapshot");
        }
        for (int viewer = -1; viewer < players; viewer++) {
            String snapshot = session.snapshot(viewer);
            for (Card card : owner.getCardsIn(ZoneType.Library))
                require(!snapshot.contains("\"" + NativeSession.cardId(card) + "\""), "Powder leaked a library identity");
            if (viewer == 0) continue;
            for (Card card : owner.getCardsIn(ZoneType.Hand))
                require(!snapshot.contains("\"" + NativeSession.cardId(card) + "\""), "Powder leaked the new private hand");
        }
    }

    private static void reject(NativeSession session, JsonObject output) {
        String prompt = session.prompt(0), snapshot = session.snapshot(0);
        boolean rejected = false;
        try { answer(session, "mulligan", output); } catch (IllegalArgumentException expected) { rejected = true; }
        require(rejected && session.prompt(0).equals(prompt) && session.snapshot(0).equals(snapshot), "Invalid Powder action advanced the input");
    }

    private static JsonObject input(NativeSession session) { return JsonParser.parseString(session.prompt(0)).getAsJsonObject().getAsJsonObject("input"); }
    private static String kind(NativeSession session) { return input(session).get("type").getAsString(); }
    private static long promptId(NativeSession session) { return JsonParser.parseString(session.prompt(0)).getAsJsonObject().get("promptId").getAsLong(); }
    private static Set<String> ids(Iterable<Card> cards) { Set<String> ids = new HashSet<>(); for (Card card : cards) ids.add(NativeSession.cardId(card)); return ids; }
    private static void answer(NativeSession session, String kind, JsonObject output) {
        long before = promptId(session);
        JsonObject response = NativeSession.object("type", kind); response.add("output", output); session.submit(response);
        require(promptId(session) > before, "Accepted Powder/mulligan response retained a stale prompt ID");
    }
    private static void keep(NativeSession session, boolean keep) { JsonObject output = NativeSession.object("type", "mulliganDecision"); output.addProperty("keep", keep); answer(session, "mulligan", output); }
    private static void decision(NativeSession session, boolean value) { JsonObject output = NativeSession.object("type", "decision"); output.addProperty("value", value); answer(session, "chooseBoolean", output); }
    private static void bottom(NativeSession session, List<Card> selected) { JsonArray ids = new JsonArray(); for (Card card : selected) ids.add(NativeSession.cardId(card)); JsonObject output = NativeSession.object("type", "mulliganPutBackDecision"); output.add("cardIds", ids); answer(session, "mulliganPutBack", output); }
    private static void concede(NativeSession session, int seat) { JsonObject response = NativeSession.object("type", "directive"); response.addProperty("player", seat); response.add("directive", NativeSession.object("type", "concede")); session.submit(response); }
}
