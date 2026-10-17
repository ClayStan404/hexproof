// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.eval;

import com.google.gson.JsonElement;
import com.google.gson.JsonParser;
import mage.constants.PhaseStep;
import mage.constants.Zone;
import mage.cards.Card;
import mage.view.GameView;
import org.junit.Before;
import org.junit.Test;
import org.mage.test.player.TestPlayer;
import org.mage.test.serverside.base.CardTestPlayerBase;

import java.util.UUID;
import java.util.ArrayList;
import java.util.List;

import static org.junit.Assert.*;

/** New actions and assertions for the engine-neutral scenario contract. */
public class DuelCases extends CardTestPlayerBase {
    @Before
    public void frozenDefaults() {
        removeAllCardsFromLibrary(playerA);
        removeAllCardsFromLibrary(playerB);
        addCard(Zone.LIBRARY, playerA, "Plains", 30);
        addCard(Zone.LIBRARY, playerB, "Plains", 30);
    }

    protected void finish() {
        setStrictChooseMode(true);
        setStopAt(1, PhaseStep.POSTCOMBAT_MAIN);
        execute();
        observeState();
    }

    protected void observeState() {
        Qualification.observe("a_life", playerA.getLife());
        Qualification.observe("b_life", playerB.getLife());
        Qualification.observe("a_hand", playerA.getHand().size());
        Qualification.observe("b_hand", playerB.getHand().size());
        Qualification.observe("a_library", playerA.getLibrary().size());
        Qualification.observe("b_library", playerB.getLibrary().size());
        Qualification.observe("stack", currentGame.getStack().size());
        Qualification.observe("a_graveyard", playerA.getGraveyard().getCards(currentGame).stream()
                .map(card -> card.getName()).sorted().toArray());
        Qualification.observe("b_graveyard", playerB.getGraveyard().getCards(currentGame).stream()
                .map(card -> card.getName()).sorted().toArray());
        Qualification.observe("a_battlefield", currentGame.getBattlefield().getAllActivePermanents(playerA.getId()).stream()
                .map(card -> card.getName()).sorted().toArray());
        Qualification.observe("b_battlefield", currentGame.getBattlefield().getAllActivePermanents(playerB.getId()).stream()
                .map(card -> card.getName()).sorted().toArray());
    }

    @Test
    public void boltPlayer() {
        addCard(Zone.HAND, playerA, "Lightning Bolt");
        addCard(Zone.BATTLEFIELD, playerA, "Mountain");
        castSpell(1, PhaseStep.PRECOMBAT_MAIN, playerA, "Lightning Bolt", playerB);
        runCode("inspect unresolved Bolt", 1, PhaseStep.PRECOMBAT_MAIN, playerA, (info, player, game) -> {
            Qualification.observe("before_resolution.b_life", playerB.getLife());
            Qualification.observe("before_resolution.stack", game.getStack().getFirst().getName());
            assertEquals(20, playerB.getLife());
            assertEquals(1, game.getStack().size());
            assertEquals("Lightning Bolt", game.getStack().getFirst().getName());
        });
        finish();
        assertLife(playerA, 20);
        assertLife(playerB, 17);
        assertGraveyardCount(playerA, "Lightning Bolt", 1);
        assertTapped("Mountain", true);
        assertEquals(0, currentGame.getStack().size());
    }

    @Test
    public void boltCreature() {
        addCard(Zone.HAND, playerA, "Lightning Bolt");
        addCard(Zone.BATTLEFIELD, playerA, "Mountain");
        addCard(Zone.BATTLEFIELD, playerB, "Grizzly Bears");
        castSpell(1, PhaseStep.PRECOMBAT_MAIN, playerA, "Lightning Bolt", "Grizzly Bears");
        finish();
        assertLife(playerA, 20);
        assertLife(playerB, 20);
        assertGraveyardCount(playerA, "Lightning Bolt", 1);
        assertGraveyardCount(playerB, "Grizzly Bears", 1);
        assertPermanentCount(playerB, "Grizzly Bears", 0);
    }

    @Test
    public void counterspell() {
        addCard(Zone.HAND, playerA, "Lightning Bolt");
        addCard(Zone.BATTLEFIELD, playerA, "Mountain");
        addCard(Zone.HAND, playerB, "Counterspell");
        addCard(Zone.BATTLEFIELD, playerB, "Island", 2);
        castSpell(1, PhaseStep.PRECOMBAT_MAIN, playerA, "Lightning Bolt", playerB);
        castSpell(1, PhaseStep.PRECOMBAT_MAIN, playerB, "Counterspell", "Lightning Bolt");
        runCode("inspect response stack", 1, PhaseStep.PRECOMBAT_MAIN, playerB, (info, player, game) -> {
            Object[] names = game.getStack().stream().map(card -> card.getName()).toArray();
            Qualification.observe("before_resolution.stack_top_first", names);
            assertArrayEquals(new Object[]{"Counterspell", "Lightning Bolt"}, names);
        });
        finish();
        assertLife(playerA, 20);
        assertLife(playerB, 20);
        assertGraveyardCount(playerA, "Lightning Bolt", 1);
        assertGraveyardCount(playerB, "Counterspell", 1);
        assertTappedCount("Island", true, 2);
        assertEquals(0, currentGame.getStack().size());
    }

    @Test
    public void landPriority() {
        addCard(Zone.HAND, playerA, "Plains", 2);
        runCode("reject wrong player", 1, PhaseStep.PRECOMBAT_MAIN, playerA, (info, player, game) -> {
            Card land = playerA.getHand().getCards(game).iterator().next();
            assertEquals(playerA.getId(), game.getPriorityPlayerId());
            assertFalse(playerB.playLand(land, game, false));
            assertEquals(2, playerA.getHand().size());
            assertEquals(0, game.getBattlefield().getAllActivePermanents().size());
            assertEquals(playerA.getId(), game.getPriorityPlayerId());
            Qualification.observe("wrong_actor_rejected_without_mutation", true);
            Qualification.observe("actor_seam", "Player.playLand validates acting player; network authentication not exercised");
        });
        playLand(1, PhaseStep.PRECOMBAT_MAIN, playerA, "Plains");
        checkPlayableAbility("second land unavailable", 1, PhaseStep.PRECOMBAT_MAIN, playerA, "Play Plains", false);
        runCode("reject extra land", 1, PhaseStep.PRECOMBAT_MAIN, playerA, (info, player, game) -> {
            Card land = playerA.getHand().getCards(game).iterator().next();
            assertFalse(playerA.playLand(land, game, false));
            Qualification.observe("second_land_rejected_without_mutation", true);
        });
        finish();
        assertHandCount(playerA, "Plains", 1);
        assertPermanentCount(playerA, "Plains", 1);
    }

    @Test
    public void etbDraw() {
        addCard(Zone.HAND, playerA, "Elvish Visionary");
        addCard(Zone.BATTLEFIELD, playerA, "Forest");
        addCard(Zone.BATTLEFIELD, playerA, "Plains");
        castSpell(1, PhaseStep.PRECOMBAT_MAIN, playerA, "Elvish Visionary");
        waitStackResolved(1, PhaseStep.PRECOMBAT_MAIN, true);
        runCode("ETB after creature before draw", 1, PhaseStep.PRECOMBAT_MAIN, playerA, (info, player, game) -> {
            assertPermanentCount(playerA, "Elvish Visionary", 1);
            assertEquals(1, game.getStack().size());
            assertEquals(30, playerA.getLibrary().size());
            assertEquals(0, playerA.getHand().size());
            Qualification.observe("etb.creature_on_battlefield_before_draw", true);
            Qualification.observe("etb.stack_top", game.getStack().getFirst().getName());
            Qualification.observe("etb.library_before_resolution", playerA.getLibrary().size());
        });
        finish();
        assertPermanentCount(playerA, "Elvish Visionary", 1);
        assertHandCount(playerA, "Plains", 1);
        assertLibraryCount(playerA, 29);
    }

    @Test
    public void blockedCombat() {
        addCard(Zone.BATTLEFIELD, playerA, "Grizzly Bears");
        addCard(Zone.BATTLEFIELD, playerB, "Grizzly Bears");
        attack(1, playerA, "Grizzly Bears", playerB);
        block(1, playerB, "Grizzly Bears", "Grizzly Bears");
        finish();
        assertLife(playerA, 20);
        assertLife(playerB, 20);
        assertPermanentCount(playerA, "Grizzly Bears", 0);
        assertPermanentCount(playerB, "Grizzly Bears", 0);
        assertGraveyardCount(playerA, "Grizzly Bears", 1);
        assertGraveyardCount(playerB, "Grizzly Bears", 1);
    }

    @Test
    public void hiddenViews() {
        removeAllCardsFromLibrary(playerA);
        removeAllCardsFromLibrary(playerB);
        // Clear the queued default library before inserting distinctive secrets.
        getLibraryCards(playerA).clear();
        getLibraryCards(playerB).clear();
        addCard(Zone.LIBRARY, playerA, "Black Lotus", 15);
        addCard(Zone.LIBRARY, playerA, "Mox Ruby", 15);
        addCard(Zone.LIBRARY, playerB, "Time Walk", 15);
        addCard(Zone.LIBRARY, playerB, "Mox Sapphire", 15);
        addCard(Zone.HAND, playerA, "Ancestral Recall");
        addCard(Zone.HAND, playerB, "Demonic Tutor");
        addCard(Zone.BATTLEFIELD, playerA, "Grizzly Bears");
        finish();
        GameView a = getGameView(playerA);
        GameView b = getGameView(playerB);
        GameView spectator = getGameView(null, UUID.randomUUID());
        String aJson = a.toJson();
        String bJson = b.toJson();
        String sJson = spectator.toJson();
        Qualification.observe("owner_projection", aJson);
        Qualification.observe("opponent_projection", bJson);
        Qualification.observe("spectator_projection", sJson);
        assertTrue(aJson.contains("Ancestral Recall"));
        assertFalse(aJson.contains("Demonic Tutor"));
        assertTrue(bJson.contains("Demonic Tutor"));
        assertFalse(bJson.contains("Ancestral Recall"));
        assertFalse(sJson.contains("Ancestral Recall"));
        assertFalse(sJson.contains("Demonic Tutor"));
        for (Card card : playerA.getHand().getCards(currentGame)) {
            assertFalse("Opponent received private hand identity", bJson.contains(card.getId().toString()));
            assertFalse("Spectator received private hand identity", sJson.contains(card.getId().toString()));
            for (String rule : card.getRules()) {
                assertFalse("Opponent received private rules", bJson.contains(rule));
                assertFalse("Spectator received private rules", sJson.contains(rule));
            }
        }
        for (Card card : playerB.getHand().getCards(currentGame)) {
            assertFalse("Opponent received private hand identity", aJson.contains(card.getId().toString()));
            assertFalse("Spectator received private hand identity", sJson.contains(card.getId().toString()));
            for (String rule : card.getRules()) {
                assertFalse("Opponent received private rules", aJson.contains(rule));
                assertFalse("Spectator received private rules", sJson.contains(rule));
            }
        }
        for (String json : new String[]{aJson, bJson, sJson}) {
            for (String secret : new String[]{"Black Lotus", "Mox Ruby", "Time Walk", "Mox Sapphire"}) {
                assertFalse("Library identity escaped: " + secret, json.contains(secret));
            }
            assertTrue(json.contains("Grizzly Bears"));
            List<String> strings = new ArrayList<>();
            collectStrings(new JsonParser().parse(json), strings);
            for (TestPlayer seat : new TestPlayer[]{playerA, playerB}) {
                for (Card card : seat.getLibrary().getCards(currentGame)) {
                    assertSecretAbsent(card, strings);
                    assertFalse("Library card UUID/order escaped", json.contains(card.getId().toString()));
                }
            }
        }
        Qualification.observe("library_identity_order_check", "All 60 private library card UUIDs absent from every owner/opponent/spectator serialized native projection");
        assertTrue(a.getOpponentHands().isEmpty());
        assertTrue(b.getOpponentHands().isEmpty());
        assertTrue(spectator.getMyHand().isEmpty());
        assertTrue(spectator.getOpponentHands().isEmpty());
        assertTrue(spectator.getWatchedHands().isEmpty());
        for (GameView view : new GameView[]{a, b, spectator}) {
            assertEquals(2, view.getPlayers().size());
            view.getPlayers().forEach(player -> {
                assertEquals(1, player.getHandCount());
                assertEquals(30, player.getLibraryCount());
            });
        }
    }

    private static void collectStrings(JsonElement value, List<String> strings) {
        if (value.isJsonObject()) value.getAsJsonObject().entrySet().forEach(entry -> collectStrings(entry.getValue(), strings));
        else if (value.isJsonArray()) value.getAsJsonArray().forEach(item -> collectStrings(item, strings));
        else if (value.isJsonPrimitive() && value.getAsJsonPrimitive().isString()) strings.add(value.getAsString());
    }

    private static void assertSecretAbsent(Card card, List<String> strings) {
        for (String value : strings) {
            assertFalse("Library identity in nested field", value.contains(card.getName()));
            for (String rule : card.getRules()) {
                if (!rule.isEmpty()) assertFalse("Library rules in nested field", value.contains(rule));
            }
        }
    }
}
