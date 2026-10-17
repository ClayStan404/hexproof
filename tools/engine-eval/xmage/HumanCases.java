// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.eval;

import mage.cards.CardSetInfo;
import mage.cards.basiclands.Plains;
import mage.cards.decks.Deck;
import mage.collectors.DataCollectorServices;
import mage.constants.MultiplayerAttackOption;
import mage.constants.PhaseStep;
import mage.constants.RangeOfInfluence;
import mage.constants.Rarity;
import mage.game.GameOptions;
import mage.game.TwoPlayerDuel;
import mage.game.TwoPlayerMatch;
import mage.game.events.PlayerQueryEvent;
import mage.game.match.MatchOptions;
import mage.game.mulligan.LondonMulligan;
import mage.player.human.HumanPlayer;
import mage.players.Player;
import mage.players.net.UserData;
import mage.server.game.GameSessionPlayer;
import mage.view.GameView;
import org.junit.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.Assert.*;

/** Independent setup uses the actual HumanPlayer request/response path. */
public class HumanCases {
    @Test
    public void openingKeepSeven() throws Exception {
        runOpening(false, false);
    }

    @Test
    public void openingOneLondonMulligan() throws Exception {
        runOpening(true, false);
    }

    @Test
    public void landAndPriority() throws Exception {
        runOpening(false, true);
    }

    private void runOpening(boolean mulligan, boolean land) throws Exception {
        TwoPlayerDuel game = new TwoPlayerDuel(MultiplayerAttackOption.MULTIPLE,
                RangeOfInfluence.ALL, new LondonMulligan(0), 60, 20, 7);
        HumanPlayer a = new HumanPlayer("A", RangeOfInfluence.ALL, 1);
        HumanPlayer b = new HumanPlayer("B", RangeOfInfluence.ALL, 1);
        TwoPlayerMatch match = new TwoPlayerMatch(new MatchOptions("Independent qualification", "Two Player Duel", true));
        for (HumanPlayer player : new HumanPlayer[]{a, b}) {
            player.setUserData(UserData.getDefaultUserDataView());
            Deck deck = new Deck();
            for (int i = 0; i < 60; i++) {
                deck.getCards().add(new Plains(player.getId(),
                        new CardSetInfo("Plains", "M21", "260", Rarity.LAND)));
            }
            game.loadCards(deck.getCards(), player.getId());
            game.addPlayer(player, deck);
            match.addPlayer(player, deck);
        }
        game.setStartingPlayerId(a.getId());
        GameOptions options = new GameOptions();
        options.stopOnTurn = 1;
        options.stopAtStep = PhaseStep.BEGIN_COMBAT;
        game.setGameOptions(options);
        DataCollectorServices.init(true, false);
        ExecutorService responses = Executors.newSingleThreadExecutor(r -> new Thread(r, "CALL qualification"));
        ExecutorService execution = Executors.newSingleThreadExecutor(r -> new Thread(r, "GAME qualification"));
        List<Future<?>> tasks = new ArrayList<>();
        AtomicBoolean tookMulligan = new AtomicBoolean();
        AtomicBoolean playedLand = new AtomicBoolean();
        AtomicInteger requests = new AtomicInteger();
        AtomicInteger mainDecisions = new AtomicInteger();
        AtomicInteger priorityAfterLand = new AtomicInteger();
        AtomicInteger bottomChoices = new AtomicInteger();
        game.addPlayerQueryEventListener(event -> {
            Player player = game.getPlayer(event.getPlayerId());
            requests.incrementAndGet();
            System.out.println("QUERY " + player.getName() + " " + event.getQueryType()
                    + " step=" + game.getTurnStepType() + " message=" + event.getMessage());
            switch (event.getQueryType()) {
                case PERSONAL_MESSAGE:
                    return;
                case ASK:
                    boolean answer = mulligan && player.getId().equals(a.getId())
                            && event.getMessage().toLowerCase().contains("mulligan")
                            && tookMulligan.compareAndSet(false, true);
                    tasks.add(responses.submit(() -> player.setResponseBoolean(answer)));
                    return;
                case PICK_TARGET:
                    assertTrue("Only London bottom-card selection expected", mulligan);
                    UUID bottom = player.getHand().iterator().next();
                    bottomChoices.incrementAndGet();
                    tasks.add(responses.submit(() -> player.setResponseUUID(bottom)));
                    return;
                case SELECT:
                    if (player.getId().equals(a.getId()) && game.getTurnStepType() == PhaseStep.PRECOMBAT_MAIN) {
                        mainDecisions.incrementAndGet();
                    }
                    if (playedLand.get()) priorityAfterLand.incrementAndGet();
                    if (land && player.getId().equals(a.getId())
                            && game.getTurnStepType() == PhaseStep.PRECOMBAT_MAIN
                            && playedLand.compareAndSet(false, true)) {
                        Qualification.observe("before_land.a_hand", player.getHand().size());
                        Qualification.observe("before_land.stack", game.getStack().size());
                        UUID card = player.getHand().iterator().next();
                        tasks.add(responses.submit(() -> player.setResponseUUID(card)));
                    } else {
                        tasks.add(responses.submit(() -> player.setResponseBoolean(true)));
                    }
                    return;
                default:
                    throw new AssertionError("Unhandled human query " + event.getQueryType());
            }
        });
        try {
            execution.submit(() -> game.start(a.getId())).get(30, TimeUnit.SECONDS);
            for (Future<?> task : tasks) task.get(2, TimeUnit.SECONDS);
            GameView owner = GameSessionPlayer.prepareGameView(game, a.getId(), a.getId());
            GameView opponent = GameSessionPlayer.prepareGameView(game, b.getId(), b.getId());
            GameView spectator = GameSessionPlayer.prepareGameView(game, null, UUID.randomUUID());
            Qualification.observe("a_hand", a.getHand().size());
            Qualification.observe("b_hand", b.getHand().size());
            Qualification.observe("a_library", a.getLibrary().size());
            Qualification.observe("b_library", b.getLibrary().size());
            Qualification.observe("a_life", a.getLife());
            Qualification.observe("b_life", b.getLife());
            Qualification.observe("a_battlefield", game.getBattlefield().getAllActivePermanents(a.getId()).size());
            Qualification.observe("stack", game.getStack().size());
            Qualification.observe("human_requests", requests.get());
            Qualification.observe("a_main_phase_decisions", mainDecisions.get());
            Qualification.observe("priority_after_land", priorityAfterLand.get());
            Qualification.observe("mulligan_bottom_choices", bottomChoices.get());
            Qualification.observe("spectator_hand", spectator.getMyHand().size());
            assertEquals(7 - (mulligan ? 1 : 0) - (land ? 1 : 0), a.getHand().size());
            assertEquals(7, b.getHand().size());
            assertEquals(53 + (mulligan ? 1 : 0), a.getLibrary().size());
            assertEquals(53, b.getLibrary().size());
            assertEquals(20, a.getLife());
            assertEquals(20, b.getLife());
            assertTrue("Starting player receives a real main-phase decision", mainDecisions.get() > 0);
            assertEquals(land ? 1 : 0, game.getBattlefield().getAllActivePermanents(a.getId()).size());
            assertEquals(0, game.getStack().size());
            assertEquals(a.getHand().size(), owner.getMyHand().size());
            assertEquals(7, opponent.getMyHand().size());
            assertEquals(0, spectator.getMyHand().size());
            assertTrue(opponent.getOpponentHands().isEmpty());
            assertTrue(spectator.getOpponentHands().isEmpty());
            assertTrue(spectator.getWatchedHands().isEmpty());
            if (mulligan) assertEquals(1, bottomChoices.get());
            if (land) assertTrue("Priority must continue after the land action", priorityAfterLand.get() > 0);
        } finally {
            a.abort();
            b.abort();
            execution.shutdownNow();
            responses.shutdownNow();
            execution.awaitTermination(3, TimeUnit.SECONDS);
            responses.awaitTermination(3, TimeUnit.SECONDS);
        }
    }
}
