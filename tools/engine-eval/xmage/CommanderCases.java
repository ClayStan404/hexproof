// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.eval;

import mage.constants.MultiplayerAttackOption;
import mage.constants.PhaseStep;
import mage.constants.RangeOfInfluence;
import mage.constants.Zone;
import mage.game.CommanderFreeForAll;
import mage.game.Game;
import mage.game.GameException;
import mage.game.mulligan.LondonMulligan;
import mage.game.permanent.Permanent;
import mage.watchers.common.CommanderInfoWatcher;
import org.junit.Before;
import org.junit.Test;
import org.mage.test.player.TestPlayer;

import java.io.FileNotFoundException;

import static org.junit.Assert.*;

public class CommanderCases extends FourCases {
    private static final String COMMANDER = "Isamaru, Hound of Konda";

    @Override
    protected Game createNewGameAndPlayers() throws GameException, FileNotFoundException {
        CommanderFreeForAll game = new CommanderFreeForAll(MultiplayerAttackOption.MULTIPLE,
                RangeOfInfluence.ALL, new LondonMulligan(1), 40, 7);
        game.setNumPlayers(4);
        createSeats(game);
        return game;
    }

    @Before
    public void commanders() {
        for (TestPlayer player : seats()) addCard(Zone.COMMAND, player, COMMANDER);
        // The multiplayer starting player draws on turn one: 31 before draw gives the frozen 30 at main.
        addCard(Zone.LIBRARY, playerA, "Plains");
    }

    @Test
    public void tax() {
        addCard(Zone.BATTLEFIELD, playerA, "Plains", 2);
        addCard(Zone.HAND, playerA, "Plains");
        addCard(Zone.BATTLEFIELD, playerB, "Swamp", 3);
        addCard(Zone.HAND, playerB, "Murder");
        runCode("initial commander state", 1, PhaseStep.PRECOMBAT_MAIN, playerA, (info, player, game) -> {
            for (TestPlayer seat : seats()) {
                assertEquals(40, seat.getLife());
                assertCommandZoneCount(seat, COMMANDER, 1);
            }
            assertEquals(30, playerA.getLibrary().size());
            Qualification.observe("starting_life", new int[]{40, 40, 40, 40});
            Qualification.observe("starting_commanders_in_command", 4);
        });
        castSpell(1, PhaseStep.PRECOMBAT_MAIN, playerA, COMMANDER, true);
        checkPermanentTapped("first cast costs W", 1, PhaseStep.PRECOMBAT_MAIN, playerA, "Plains", true, 1);
        castSpell(1, PhaseStep.BEGIN_COMBAT, playerB, "Murder", COMMANDER);
        setChoice(playerA, true);
        runCode("returned by optional choice", 1, PhaseStep.POSTCOMBAT_MAIN, playerA, (info, player, game) -> {
            assertCommandZoneCount(playerA, COMMANDER, 1);
            assertGraveyardCount(playerA, COMMANDER, 0);
            assertPermanentCount(playerA, COMMANDER, 0);
            assertTappedCount("Plains", false, 1);
            Qualification.observe("optional_return_choice_consumed", true);
            Qualification.observe("available_white_mana_before_failed_recast", 1);
        });
        checkPlayableAbility("W cannot pay commander tax", 1, PhaseStep.POSTCOMBAT_MAIN, playerA,
                "Cast " + COMMANDER, false);
        playLand(5, PhaseStep.PRECOMBAT_MAIN, playerA, "Plains");
        castSpell(5, PhaseStep.PRECOMBAT_MAIN, playerA, COMMANDER, true);
        runCode("second cast paid 2W", 5, PhaseStep.PRECOMBAT_MAIN, playerA, (info, player, game) -> {
            assertTappedCount("Plains", true, 3);
            assertPermanentCount(playerA, COMMANDER, 1);
            assertCommandZoneCount(playerA, COMMANDER, 0);
            Qualification.observe("second_cast_plains_tapped", 3);
            Qualification.observe("commander_final_zone", "battlefield");
        });
        setStrictChooseMode(true);
        setStopAt(5, PhaseStep.POSTCOMBAT_MAIN);
        execute();
    }

    @Test
    public void damage() throws Exception {
        noncombatFixture();
        reset();
        frozenLibraries();
        commanders();
        addCard(Zone.BATTLEFIELD, playerA, "Plains");
        castSpell(1, PhaseStep.PRECOMBAT_MAIN, playerA, COMMANDER, true);
        runCode("set recorded historical combat damage", 5, PhaseStep.PRECOMBAT_MAIN, playerA, (info, player, game) -> {
            Permanent commander = getPermanent(COMMANDER, playerA);
            CommanderInfoWatcher watcher = game.getState().getWatcher(CommanderInfoWatcher.class, commander.getId());
            watcher.getDamageToPlayer().put(playerB.getId(), 19);
            assertEquals(40, playerB.getLife());
            assertEquals(2, commander.getPower().getValue());
            assertFalse(commander.hasSummoningSickness());
            Qualification.observe("before_attack.recorded_combat_damage", 19);
            Qualification.observe("before_attack.defender_life", 40);
        });
        attack(5, playerA, COMMANDER, playerB);
        runCode("survivor has next priority after commander lethal", 5, PhaseStep.POSTCOMBAT_MAIN, playerA, (info, player, game) -> {
            assertTrue(playerB.hasLost());
            assertFalse(game.hasEnded());
            assertEquals(playerA.getId(), game.getActivePlayerId());
            assertEquals(playerA.getId(), game.getPriorityPlayerId());
            assertTrue(playerA.isInGame());
            Qualification.observe("after_lethal.next_decision_actor", game.getPriorityPlayerId().toString());
            Qualification.observe("after_lethal.next_decision_phase", String.valueOf(game.getTurnStepType()));
        });
        playLand(5, PhaseStep.POSTCOMBAT_MAIN, playerA, "Plains");
        runCode("survivor executes land action after commander lethal", 5, PhaseStep.POSTCOMBAT_MAIN, playerA, (info, player, game) -> {
            assertPermanentCount(playerA, "Plains", 2);
            assertEquals(playerA.getId(), game.getPriorityPlayerId());
            Qualification.observe("after_lethal.survivor_completed_land_action", true);
        });
        setStrictChooseMode(true);
        setStopAt(5, PhaseStep.END_TURN);
        execute();
        Permanent commander = getPermanent(COMMANDER, playerA);
        CommanderInfoWatcher watcher = currentGame.getState().getWatcher(CommanderInfoWatcher.class, commander.getId());
        Qualification.observe("after_combat.recorded_combat_damage", watcher.getDamageToPlayer().get(playerB.getId()));
        Qualification.observe("after_combat.defender_life", playerB.getLife());
        Qualification.observe("after_combat.defender_lost", playerB.hasLost());
        Qualification.observe("after_combat.remaining_players", remaining(currentGame));
        Qualification.observe("after_combat.game_ended", currentGame.hasEnded());
        assertEquals(21, (int) watcher.getDamageToPlayer().get(playerB.getId()));
        assertEquals(38, playerB.getLife());
        assertTrue(playerB.hasLost());
        assertEquals(3, remaining(currentGame));
        assertFalse(currentGame.hasEnded());
    }

    private void noncombatFixture() {
        addCard(Zone.BATTLEFIELD, playerA, "Plains");
        castSpell(1, PhaseStep.PRECOMBAT_MAIN, playerA, COMMANDER, true);
        runCode("noncombat commander damage is excluded", 1, PhaseStep.POSTCOMBAT_MAIN, playerA, (info, player, game) -> {
            Permanent commander = getPermanent(COMMANDER, playerA);
            CommanderInfoWatcher watcher = game.getState().getWatcher(CommanderInfoWatcher.class, commander.getId());
            assertNotNull(watcher);
            assertEquals(40, playerB.getLife());
            assertEquals(2, playerB.damage(2, commander.getId(), null, game, false, true));
            assertEquals(38, playerB.getLife());
            assertEquals(0, (int) watcher.getDamageToPlayer().getOrDefault(playerB.getId(), 0));
            Qualification.observe("noncombat.damage", 2);
            Qualification.observe("noncombat.commander_combat_count", 0);
            Qualification.observe("noncombat.action_seam", "Fresh game; Player.damage, combatDamage=false; no final state mutation");
        });
        setStrictChooseMode(true);
        setStopAt(1, PhaseStep.POSTCOMBAT_MAIN);
        execute();
    }
}
