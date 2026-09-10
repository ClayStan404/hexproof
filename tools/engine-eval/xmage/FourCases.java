// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.eval;

import mage.constants.MultiplayerAttackOption;
import mage.constants.PhaseStep;
import mage.constants.RangeOfInfluence;
import mage.constants.Zone;
import mage.game.FreeForAll;
import mage.game.Game;
import mage.game.GameException;
import mage.game.mulligan.LondonMulligan;
import org.junit.Before;
import org.junit.Test;
import org.mage.test.player.TestPlayer;
import org.mage.test.serverside.base.impl.CardTestPlayerAPIImpl;

import java.io.FileNotFoundException;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import static org.junit.Assert.*;

public class FourCases extends CardTestPlayerAPIImpl {
    @Override
    protected Game createNewGameAndPlayers() throws GameException, FileNotFoundException {
        FreeForAll game = new FreeForAll(MultiplayerAttackOption.MULTIPLE,
                RangeOfInfluence.ALL, new LondonMulligan(1), 20, 7);
        game.setNumPlayers(4);
        createSeats(game);
        return game;
    }

    protected void createSeats(Game game) throws GameException {
        playerA = createPlayer(game, "PlayerA");
        playerB = createPlayer(game, "PlayerB");
        playerC = createPlayer(game, "PlayerC");
        playerD = createPlayer(game, "PlayerD");
    }

    @Before
    public void frozenLibraries() {
        for (TestPlayer player : seats()) {
            removeAllCardsFromLibrary(player);
            addCard(Zone.LIBRARY, player, "Plains", 30);
        }
    }

    protected TestPlayer[] seats() {
        return new TestPlayer[]{playerA, playerB, playerC, playerD};
    }

    protected long remaining(Game game) {
        return game.getPlayers().values().stream().filter(player -> player.isInGame()).count();
    }

    private Map<String, Long> activeZoneOccurrences(Game game, UUID cardId) {
        Map<String, Long> counts = new LinkedHashMap<>();
        counts.put("battlefield", game.getBattlefield().getAllPermanents().stream()
                .filter(card -> card.getId().equals(cardId)).count());
        counts.put("stack", game.getStack().stream()
                .filter(card -> card.getId().equals(cardId) || card.getSourceId().equals(cardId)).count());
        counts.put("exile", game.getExile().getAllCards(game).stream()
                .filter(card -> card.getId().equals(cardId)).count());
        counts.put("command", game.getState().getCommand().stream()
                .filter(card -> card.getId().equals(cardId)).count());
        for (TestPlayer seat : seats()) {
            counts.put(seat.getName() + ".hand", seat.getHand().getCards(game).stream()
                    .filter(card -> card.getId().equals(cardId)).count());
            counts.put(seat.getName() + ".library", seat.getLibrary().getCards(game).stream()
                    .filter(card -> card.getId().equals(cardId)).count());
            counts.put(seat.getName() + ".graveyard", seat.getGraveyard().getCards(game).stream()
                    .filter(card -> card.getId().equals(cardId)).count());
        }
        return counts;
    }

    @Test
    public void departure() {
        addCard(Zone.HAND, playerA, "Plains");
        addCard(Zone.BATTLEFIELD, playerC, "Grizzly Bears");
        runCode("departure during A priority", 1, PhaseStep.PRECOMBAT_MAIN, playerA, (info, player, game) -> {
            assertEquals(playerA.getId(), game.getPriorityPlayerId());
            for (TestPlayer seat : seats()) assertEquals(20, seat.getLife());
            UUID bearsId = getPermanent("Grizzly Bears", playerC).getId();
            Qualification.observe("departing_owned_bears_id", bearsId.toString());
            assertEquals(1L, (long) activeZoneOccurrences(game, bearsId).get("battlefield"));
            game.concede(playerC.getId());
            game.checkStateAndTriggered();
            assertEquals(3, remaining(game));
            assertFalse(game.hasEnded());
            Map<String, Long> occurrences = activeZoneOccurrences(game, bearsId);
            Qualification.observe("after_first_departure.card_active_zone_occurrences", occurrences);
            for (Map.Entry<String, Long> entry : occurrences.entrySet()) {
                assertEquals("Departed card retained in " + entry.getKey(), 0L, (long) entry.getValue());
            }
            Map<String, String> projections = new LinkedHashMap<>();
            for (TestPlayer survivor : new TestPlayer[]{playerA, playerB, playerD}) {
                projections.put(survivor.getName(), getGameView(survivor).toJson());
            }
            projections.put("spectator", getGameView(null, UUID.randomUUID()).toJson());
            Qualification.observe("after_first_departure.projections", projections);
            for (String json : projections.values()) {
                assertFalse("Departed card identity retained in projection", json.contains(bearsId.toString()));
                assertFalse("Departed card name retained in projection", json.contains("Grizzly Bears"));
            }
            Qualification.observe("after_first_departure.players", remaining(game));
            Qualification.observe("after_first_departure.ended", game.hasEnded());
            Qualification.observe("after_first_departure.bears", occurrences.get("battlefield"));
        });
        playLand(1, PhaseStep.PRECOMBAT_MAIN, playerA, "Plains");
        runCode("continued action then terminal departures", 1, PhaseStep.PRECOMBAT_MAIN, playerA, (info, player, game) -> {
            assertPermanentCount(playerA, "Plains", 1);
            assertFalse(game.hasEnded());
            Qualification.observe("remaining_player_completed_land_action", true);
            game.concede(playerB.getId());
            game.checkStateAndTriggered();
            assertFalse(game.hasEnded());
            game.concede(playerD.getId());
            game.checkStateAndTriggered();
            Qualification.observe("after_final_departure.ended", game.hasEnded());
            assertTrue(game.hasEnded());
            assertTrue(playerA.hasWon());
            Qualification.observe("after_final_departure.player_a_has_won", playerA.hasWon());
        });
        setStrictChooseMode(true);
        setStopAt(1, PhaseStep.POSTCOMBAT_MAIN);
        execute();
        // The game loop finalizes winnerId after the last action callback returns.
        assertFalse(currentGame.isADraw());
        assertEquals("Player " + playerA.getName() + " is the winner", currentGame.getWinner());
        assertTrue(playerA.hasWon());
        assertFalse(playerB.hasWon());
        assertFalse(playerC.hasWon());
        assertFalse(playerD.hasWon());
        Qualification.observe("after_finalization.winner", currentGame.getWinner());
        Qualification.observe("after_finalization.is_draw", currentGame.isADraw());
    }
}
