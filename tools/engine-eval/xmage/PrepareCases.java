// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.eval;

import mage.cards.repository.CardRepository;
import mage.cards.Sets;
import mage.cards.CardSetInfo;
import mage.cards.g.GoblinGlasswright;
import mage.constants.PhaseStep;
import mage.constants.Rarity;
import mage.constants.Zone;
import mage.game.Game;
import mage.game.permanent.Permanent;
import org.junit.Test;

import java.util.UUID;

import static org.junit.Assert.*;

/** Exact, separately frozen Prepare extension; no synthesized card definitions. */
public class PrepareCases extends DuelCases {
    private static final String CREATURE = "Goblin Glasswright";
    private static final String SORCERY = "Craft with Pride";
    private final boolean curated = Boolean.getBoolean("hexproof.eval.curatedPrepare");

    private void setupPrepare() {
        int entries = CardRepository.instance.findCards(CREATURE).size();
        long registryEntries = Sets.getInstance().get("SOS").getSetCardInfo().stream()
                .filter(card -> card.getName().equals(CREATURE)).count();
        Qualification.observe("catalog.creature_entries", entries);
        Qualification.observe("catalog.live_set_registry_entries", registryEntries);
        Qualification.observe("catalog.card_name", CREATURE);
        Qualification.observe("catalog.curated_existing_class_opt_in", curated);
        if (!curated && entries == 0 && registryEntries == 0) {
            Qualification.observe("support_gap", "catalog_missing");
            throw new UnsupportedOperationException("Pinned shipped card catalog does not expose " + CREATURE);
        }
        if (curated) {
            GoblinGlasswright existing = new GoblinGlasswright(playerA.getId(),
                    new CardSetInfo(CREATURE, "SOS", "117", Rarity.COMMON));
            Qualification.observe("curated.class", existing.getClass().getName());
            Qualification.observe("curated.printed_spell", existing.getSpellCard().getName());
            Qualification.observe("curated.printed_spell_cost", existing.getSpellCard().getManaCost().getText());
            getHandCards(playerA).add(existing);
        } else {
            addCard(Zone.HAND, playerA, CREATURE);
        }
        addCard(Zone.BATTLEFIELD, playerA, "Mountain", 3);
    }

    private UUID assertPrepared(Game game) {
        Permanent permanent = getPermanent(CREATURE, playerA);
        assertTrue(permanent.isPrepared());
        assertEquals(2, permanent.getPower().getValue());
        assertEquals(2, permanent.getToughness().getValue());
        long copies = game.getExile().getAllCards(game).stream()
                .filter(card -> card.getName().equals(SORCERY)).count();
        Qualification.observe("prepared.copy_count", copies);
        Qualification.observe("prepared.source_id", permanent.getId().toString());
        Qualification.observe("prepared.source_prepared", permanent.isPrepared());
        assertTappedCount("Mountain", true, 2);
        Qualification.observe("prepared.creature_paid", 2);
        if (curated && copies == 0) {
            Qualification.observe("support_gap", "curated_prepare_copy_missing");
        } else {
            assertEquals(1, copies);
        }
        return permanent.getId();
    }

    @Test
    public void cast() {
        setupPrepare();
        checkPlayableAbility("alternative unavailable from hand", 1, PhaseStep.PRECOMBAT_MAIN,
                playerA, "Cast " + SORCERY, false);
        castSpell(1, PhaseStep.PRECOMBAT_MAIN, playerA, CREATURE, true);
        final UUID[] sourceId = new UUID[1];
        runCode("prepared creature and exile copy", 1, PhaseStep.PRECOMBAT_MAIN, playerA,
                (info, player, game) -> sourceId[0] = assertPrepared(game));
        castSpell(1, PhaseStep.PRECOMBAT_MAIN, playerA, SORCERY);
        runCode("cast copy consumes preparation", 1, PhaseStep.PRECOMBAT_MAIN, playerA, (info, player, game) -> {
            assertEquals(1, game.getStack().size());
            assertEquals(SORCERY, game.getStack().getFirst().getName());
            Permanent permanent = getPermanent(CREATURE, playerA);
            assertEquals(sourceId[0], permanent.getId());
            assertFalse(permanent.isPrepared());
            assertTappedCount("Mountain", true, 3);
            Qualification.observe("copy.cast_from_exile_and_source_unprepared", true);
        });
        waitStackResolved(1, PhaseStep.PRECOMBAT_MAIN);
        checkPlayableAbility("copy cannot be reused", 1, PhaseStep.PRECOMBAT_MAIN,
                playerA, "Cast " + SORCERY, false);
        finish();
        assertPermanentCount(playerA, "Treasure", 1);
        assertEquals(1, currentGame.getBattlefield().getAllActivePermanents(playerA.getId()).stream()
                .filter(Permanent::isToken).count());
        assertExileCount(playerA, SORCERY, 0);
        assertPermanentCount(playerA, CREATURE, 1);
        Qualification.observe("resolved.treasure_count", 1);
        Qualification.observe("resolved.prepare_copy_count", 0);
        assertEquals(1L, Qualification.observations.get("prepared.copy_count"));
    }

    @Test
    public void sourceLeaves() {
        setupPrepare();
        addCard(Zone.HAND, playerB, "Lightning Bolt");
        addCard(Zone.BATTLEFIELD, playerB, "Mountain");
        castSpell(1, PhaseStep.PRECOMBAT_MAIN, playerA, CREATURE, true);
        runCode("prepared source before removal", 1, PhaseStep.PRECOMBAT_MAIN, playerA,
                (info, player, game) -> assertPrepared(game));
        waitStackResolved(1, PhaseStep.PRECOMBAT_MAIN, playerB);
        castSpell(1, PhaseStep.PRECOMBAT_MAIN, playerB, "Lightning Bolt", CREATURE, true);
        checkPlayableAbility("copy unavailable after source departure", 1, PhaseStep.PRECOMBAT_MAIN,
                playerA, "Cast " + SORCERY, false);
        finish();
        assertGraveyardCount(playerA, CREATURE, 1);
        assertGraveyardCount(playerB, "Lightning Bolt", 1);
        assertPermanentCount(playerA, CREATURE, 0);
        assertExileCount(playerA, SORCERY, 0);
        Qualification.observe("after_bolt.creature_graveyard", 1);
        Qualification.observe("after_bolt.prepare_copy_count", 0);
        assertEquals(1L, Qualification.observations.get("prepared.copy_count"));
    }
}
