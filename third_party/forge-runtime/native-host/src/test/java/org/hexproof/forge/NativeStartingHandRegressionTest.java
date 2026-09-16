// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.common.eventbus.Subscribe;
import com.google.gson.*;
import forge.game.card.Card;
import forge.game.event.GameEventShuffle;
import forge.game.player.Player;
import forge.game.zone.ZoneType;
import forge.gamemodes.match.input.InputChooseStartingHand;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import java.util.*;
import static org.hexproof.forge.NativeCallbackRegressionTest.require;

/** Actual Backup Plan setup and InputQueue decisions, including private hand rotation. */
public final class NativeStartingHandRegressionTest {
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
            for (int[] scenario : List.of(new int[]{1, 0}, new int[]{1, 1}, new int[]{2, 2}, new int[]{2, 4}))
                run(base, scenario[0], scenario[1]);
        }
        System.out.println("PASS native starting hands: first/extra/wrap choices, complete recycle and shuffle, private snapshots");
    }

    private static void run(NativeGuiBase base, int extraHands, int rotations) {
        JsonObject config = NativeSession.object("gameId", "starting-hands-" + extraHands + "-" + rotations);
        config.addProperty("seed", 42); config.addProperty("variant", "constructed");
        config.addProperty("startingLife", 20); config.addProperty("startingPlayerIndex", 0);
        JsonArray players = new JsonArray();
        String[] names = {"Forest", "Island", "Mountain", "Plains", "Swamp", "Lightning Bolt", "Grizzly Bears", "Opt"};
        for (int seat = 0; seat < 2; seat++) {
            JsonObject player = NativeSession.object("name", "Starting hand seat " + seat);
            JsonArray deck = new JsonArray();
            for (int count = 0; count < 60; count++)
                deck.add(NativeSession.object("name", seat == 0 ? names[count % names.length] : "Wastes"));
            if (seat == 0) for (int count = 0; count < extraHands; count++)
                deck.add(NativeSession.object("name", "Backup Plan"));
            player.add("deck", deck); players.add(player);
        }
        config.add("players", players);
        try (NativeSession session = new NativeSession(config, base)) {
            base.setFailureHandler(session::fail);
            Player owner = session.game.getRegisteredPlayers().get(0);
            ShuffleObserver shuffles = new ShuffleObserver(owner);
            session.game.subscribeToEvents(shuffles);
            session.start();
            require(owner.getCardsIn(ZoneType.Command).stream().filter(card -> card.getName().equals("Backup Plan")).count() == extraHands,
                    "Imported conspiracies did not enter the native command zone");
            List<List<Card>> hands = new ArrayList<>();
            hands.add(new ArrayList<>(owner.getCardsIn(ZoneType.Hand)));
            owner.getExtraZones().stream().filter(zone -> zone.getZoneType() == ZoneType.ExtraHand)
                    .forEach(zone -> hands.add(new ArrayList<>(zone.getCards())));
            require(hands.size() == extraHands + 1 && hands.stream().allMatch(hand -> hand.size() == 7),
                    "Backup Plan did not draw complete additional starting hands");
            Set<Card> deckCards = new HashSet<>(owner.getCardsIn(ZoneType.Library));
            hands.forEach(deckCards::addAll);
            require(deckCards.size() == 60, "Conspiracies were shuffled into the playable deck");
            int shuffleCount = shuffles.count;
            long previousPrompt = -1;
            for (int view = 0; view <= rotations; view++) {
                require(session.guis.get(0).human.getInputProxy().getInput() instanceof InputChooseStartingHand,
                        "Starting-hand choice bypassed the official native InputQueue");
                JsonObject envelope = JsonParser.parseString(session.prompt(0)).getAsJsonObject();
                JsonObject input = envelope.getAsJsonObject("input");
                require(envelope.get("promptId").getAsLong() > previousPrompt, "Hand rotation retained a stale response prompt");
                previousPrompt = envelope.get("promptId").getAsLong();
                require(envelope.get("decidingPlayerId").getAsString().equals("player-0"), "Starting hand assigned to another seat");
                require(input.get("type").getAsString().equals("chooseBoolean")
                        && input.get("confirmLabel").getAsString().equals("View next hand")
                        && input.get("denyLabel").getAsString().equals("Keep this hand"),
                        "Starting-hand input did not preserve native next/accept actions");
                int selectedIndex = view % hands.size();
                require(input.getAsJsonObject("presentation").get("title").getAsString()
                        .equals("Starting hand " + (selectedIndex + 1) + " of " + hands.size()), "Displayed hand index drifted from native rotation");
                require(new HashSet<>(owner.getCardsIn(ZoneType.Hand)).equals(new HashSet<>(hands.get(selectedIndex))),
                        "Native next action did not rotate the complete hand");
                verifyPrivacy(session, hands.get(selectedIndex), deckCards);
                require(shuffles.count == shuffleCount, "Browsing hands shuffled a library before accepting a hand");
                if (view == 0) {
                    String before = session.prompt(0), snapshot = session.snapshot(0);
                    JsonObject wrong = NativeSession.object("type", "chooseBoolean");
                    wrong.add("output", NativeSession.object("type", "cancel"));
                    boolean rejected = false;
                    try { session.submit(wrong); } catch (IllegalArgumentException expected) { rejected = true; }
                    require(rejected && before.equals(session.prompt(0)) && snapshot.equals(session.snapshot(0)),
                            "Malformed hand choice changed the native hand or pending prompt");
                }
                JsonObject answer = NativeSession.object("type", "decision"); answer.addProperty("value", view < rotations);
                JsonObject response = NativeSession.object("type", "chooseBoolean"); response.add("output", answer);
                session.submit(response);
            }
            Set<Card> selected = new HashSet<>(hands.get(rotations % hands.size()));
            Set<Card> unused = new HashSet<>(deckCards); unused.removeAll(selected);
            require(new HashSet<>(owner.getCardsIn(ZoneType.Hand)).equals(selected), "Accepting a hand lost the chosen seven cards");
            require(owner.getCardsIn(ZoneType.Library).size() == 53
                    && new HashSet<>(owner.getCardsIn(ZoneType.Library)).equals(unused), "Unused hands were lost or duplicated during native recycling");
            require(owner.getExtraZones() == null || owner.getExtraZones().stream().noneMatch(zone -> zone.getZoneType() == ZoneType.ExtraHand),
                    "Native temporary extra-hand zones survived the choice");
            require(shuffles.count == shuffleCount + 1, "Backup Plan must shuffle exactly once after returning unused hands");
            require(shuffles.libraryAtShuffle.size() == 53 && new HashSet<>(shuffles.libraryAtShuffle).equals(unused)
                    && new HashSet<>(shuffles.handAtShuffle).equals(selected) && shuffles.extraCardsAtShuffle == 0,
                    "Native shuffle ran before all unused hands were returned or included the selected hand");
            verifyPrivacy(session, new ArrayList<>(selected), deckCards);
            require(JsonParser.parseString(session.prompt(0)).getAsJsonObject().getAsJsonObject("input").get("type").getAsString().equals("mulligan"),
                    "Starting-hand acceptance did not continue into the native mulligan procedure");
            JsonObject concede = NativeSession.object("type", "directive"); concede.addProperty("player", 1);
            concede.add("directive", NativeSession.object("type", "concede")); session.submit(concede);
            require(session.gameOver(), "Starting-hand regression left the actual game running");
        }
    }

    private static void verifyPrivacy(NativeSession session, List<Card> viewedHand, Set<Card> deckCards) {
        Set<String> expectedIds = new HashSet<>();
        for (Card card : viewedHand) expectedIds.add(NativeSession.cardId(card));
        JsonObject own = JsonParser.parseString(session.snapshot(0)).getAsJsonObject();
        Set<String> actualIds = new HashSet<>();
        for (JsonElement element : own.getAsJsonArray("zones")) {
            JsonObject zone = element.getAsJsonObject();
            require(!zone.get("zone").getAsString().equals("extrahand"), "Extra hand became a public snapshot zone");
            if (!zone.get("ownerId").getAsString().equals("player-0") || !zone.get("zone").getAsString().equals("hand")) continue;
            require(zone.get("count").getAsInt() == 7, "Owner hand snapshot lost its exact count");
            for (JsonElement entry : zone.getAsJsonArray("cards")) {
                JsonObject card = entry.getAsJsonObject();
                require(card.getAsJsonObject("identity").has("name"), "Owner cannot inspect the currently viewed hand");
                actualIds.add(card.get("id").getAsString());
            }
        }
        require(actualIds.equals(expectedIds), "New hand snapshot did not replace the previous private cards");
        for (int viewer : List.of(-1, 0, 1)) {
            String snapshot = session.snapshot(viewer);
            for (Card card : deckCards) {
                if (viewer == 0 && viewedHand.contains(card)) continue;
                require(!snapshot.contains("\"" + NativeSession.cardId(card) + "\""), "Hidden starting-hand or library object ID escaped to a viewer");
                if (viewer != 0) require(!snapshot.contains("\"name\":\"" + card.getName() + "\""),
                        "Starting-hand identity escaped to an opponent or spectator");
            }
        }
    }

    public static final class ShuffleObserver {
        private final Player owner;
        volatile int count;
        volatile List<Card> libraryAtShuffle = List.of(), handAtShuffle = List.of();
        volatile int extraCardsAtShuffle;
        ShuffleObserver(Player owner) { this.owner = owner; }
        @Subscribe public void onShuffle(GameEventShuffle event) {
            if (!event.player().equals(owner.getView())) return;
            libraryAtShuffle = new ArrayList<>(owner.getCardsIn(ZoneType.Library));
            handAtShuffle = new ArrayList<>(owner.getCardsIn(ZoneType.Hand));
            extraCardsAtShuffle = owner.getExtraZones() == null ? 0 : owner.getExtraZones().stream()
                    .filter(zone -> zone.getZoneType() == ZoneType.ExtraHand).mapToInt(zone -> zone.size()).sum();
            count++;
        }
    }
}
