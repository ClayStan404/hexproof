// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.eval;

import mage.constants.PhaseStep;
import mage.constants.EmptyNames;
import mage.constants.SubType;
import mage.constants.Zone;
import mage.constants.CardType;
import mage.cards.Card;
import mage.filter.predicate.mageobject.NamePredicate;
import mage.filter.predicate.mageobject.NoAbilityPredicate;
import mage.game.permanent.Permanent;
import mage.game.stack.Spell;
import mage.abilities.SpellAbility;
import mage.view.CardView;
import org.junit.Test;

import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

import static org.junit.Assert.*;

public class MechanicCases extends DuelCases {
    @Test
    public void morph() throws Exception {
        addCard(Zone.HAND, playerA, "Willbender");
        addCard(Zone.BATTLEFIELD, playerA, "Plains", 4);
        addCard(Zone.BATTLEFIELD, playerA, "Island");
        final UUID[] identity = new UUID[1];
        for (int i = 0; i < 3; i++) activateManaAbility(1, PhaseStep.PRECOMBAT_MAIN, playerA, "{T}: Add {W}");
        castSpell(1, PhaseStep.PRECOMBAT_MAIN, playerA, "Willbender using Morph");
        runCode("face-down stack projection", 1, PhaseStep.PRECOMBAT_MAIN, playerA, (info, player, game) -> {
            String opponent = getGameView(playerB).toJson();
            String spectator = getGameView(null, UUID.randomUUID()).toJson();
            Qualification.observe("face_down.stack_opponent", opponent);
            Qualification.observe("face_down.stack_spectator", spectator);
            assertFalse(opponent.contains("Willbender"));
            assertFalse(spectator.contains("Willbender"));
            CardView projected = getGameView(playerB).getStack().values().iterator().next();
            assertTrue(projected.isFaceDown());
            assertTrue(projected.getColor().isColorless());
            assertEquals("", projected.getManaCostStr());
            assertEquals("2", projected.getPower());
            assertEquals("2", projected.getToughness());
            Spell spell = (Spell) game.getStack().getFirst();
            Card characteristics = spell.getSpellAbility().getCharacteristics(game);
            Qualification.observe("face_down.stack_display_label", projected.getName());
            Qualification.observe("face_down.stack_rules_name", characteristics.getName());
            assertEquals("", characteristics.getName());
            // This blueprint retains source payment metadata; the exposed spell has no cost.
            Qualification.observe("face_down.stack_blueprint_cost_metadata", characteristics.getManaCost().getText());
            assertEquals(0, spell.getManaValue());
            assertTrue(spell.getColor(game).isColorless());
            assertEquals(java.util.Collections.singletonList(CardType.CREATURE), spell.getCardType(game));
            Qualification.observe("face_down.raw_spell_subtypes", spell.getSubtype(game).toString());
            Qualification.observe("face_down.actual_spell_no_abilities_predicate", NoAbilityPredicate.instance.apply(spell, game));
            assertTrue(characteristics.getColor(game).isColorless());
            assertEquals(2, characteristics.getPower().getValue());
            assertEquals(2, characteristics.getToughness().getValue());
            Qualification.observe("face_down.stack_blueprint_no_abilities_predicate",
                    NoAbilityPredicate.instance.apply(characteristics, game));
            assertFalse(new NamePredicate("Willbender").apply(spell, game));
            assertFalse(new NamePredicate("Morph").apply(spell, game));
        });
        waitStackResolved(1, PhaseStep.PRECOMBAT_MAIN);
        runCode("face-down permanent", 1, PhaseStep.PRECOMBAT_MAIN, playerA, (info, player, game) -> {
            Permanent faceDown = getPermanent(EmptyNames.FACE_DOWN_CREATURE.getTestCommand(), playerA);
            identity[0] = faceDown.getId();
            assertTrue(faceDown.isFaceDown(game));
            assertEquals("", faceDown.getName());
            assertTrue(faceDown.getColor(game).isColorless());
            assertTrue(faceDown.getManaCost().isEmpty());
            assertEquals(2, faceDown.getPower().getValue());
            assertEquals(2, faceDown.getToughness().getValue());
            assertTrue(NoAbilityPredicate.instance.apply(faceDown, game));
            String opponent = getGameView(playerB).toJson();
            String spectator = getGameView(null, UUID.randomUUID()).toJson();
            Qualification.observe("face_down.battlefield_opponent", opponent);
            Qualification.observe("face_down.battlefield_spectator", spectator);
            assertFalse(opponent.contains("Willbender"));
            assertFalse(spectator.contains("Willbender"));
            assertEquals(0, game.getStack().size());
        });
        activateAbility(1, PhaseStep.PRECOMBAT_MAIN, playerA, "{1}{U}: Turn this face-down permanent face up.");
        finish();
        Permanent revealed = getPermanent("Willbender", playerA);
        assertEquals(identity[0], revealed.getId());
        assertPowerToughness(playerA, "Willbender", 1, 2);
        Qualification.observe("identity_preserved", identity[0].equals(revealed.getId()));
        Qualification.observe("face_up_power_toughness", "1/2");
        morphZeroManaValueFixture();
        morphRestrictedManaPositiveControl();
        morphRestrictedManaFixture();
        Qualification.observe("rule_observable_characteristics_complete", true);
    }

    private void morphRestrictedManaFixture() throws Exception {
        reset();
        frozenDefaults();
        addCard(Zone.HAND, playerA, "Willbender");
        addCard(Zone.BATTLEFIELD, playerA, "Plains");
        addCard(Zone.BATTLEFIELD, playerA, "Jasmine Boreal of the Seven");
        activateManaAbility(1, PhaseStep.PRECOMBAT_MAIN, playerA, "{T}: Add {G}{W}");
        activateManaAbility(1, PhaseStep.PRECOMBAT_MAIN, playerA, "{T}: Add {W}");
        runCode("inspect real restricted payment before casting", 1, PhaseStep.PRECOMBAT_MAIN, playerA, (info, player, game) -> {
            Qualification.observe("restricted_mana.regular_pool", playerA.getManaPool().getMana().toString());
            Qualification.observe("restricted_mana.conditional_pool", playerA.getManaPool().getConditionalMana().toString());
            Qualification.observe("restricted_mana.playable_abilities", playerA.getPlayable(game, true).stream()
                    .map(ability -> ability.getRule()).collect(Collectors.toList()));
            assertTapped("Jasmine Boreal of the Seven", true);
            assertTapped("Plains", true);
            boolean available = playerA.getPlayable(game, true).stream()
                    .filter(SpellAbility.class::isInstance).map(SpellAbility.class::cast)
                    .anyMatch(ability -> ability.getSpellAbilityCastMode().isFaceDown());
            if (!available) Qualification.observe("rule_failure", "morph_rejected_by_ability_free_restricted_mana");
            assertTrue("Face-down Willbender must be payable with Jasmine GW plus Plains W", available);
        });
        castSpell(1, PhaseStep.PRECOMBAT_MAIN, playerA, "Willbender using Morph");
        runCode("restricted mana paid for an ability-free creature spell", 1, PhaseStep.PRECOMBAT_MAIN, playerA, (info, player, game) -> {
            assertEquals(1, game.getStack().size());
            Spell spell = (Spell) game.getStack().getFirst();
            assertTrue(spell.isFaceDown(game));
            assertEquals(0, playerA.getManaPool().getMana().count());
            assertTapped("Jasmine Boreal of the Seven", true);
            assertTapped("Plains", true);
            Qualification.observe("restricted_mana.face_down_spell_cast", true);
            Qualification.observe("restricted_mana.payment", "Jasmine's GW restricted to ability-free creature spells plus one Plains W; all three spent");
        });
        setStrictChooseMode(true);
        setStopAt(1, PhaseStep.POSTCOMBAT_MAIN);
        execute();
        assertHandCount(playerA, "Willbender", 0);
        assertPermanentCount(playerA, EmptyNames.FACE_DOWN_CREATURE.getTestCommand(), 1);
    }

    private void morphRestrictedManaPositiveControl() throws Exception {
        reset();
        frozenDefaults();
        addCard(Zone.HAND, playerA, "Grizzly Bears");
        addCard(Zone.BATTLEFIELD, playerA, "Jasmine Boreal of the Seven");
        activateManaAbility(1, PhaseStep.PRECOMBAT_MAIN, playerA, "{T}: Add {G}{W}");
        castSpell(1, PhaseStep.PRECOMBAT_MAIN, playerA, "Grizzly Bears");
        setStrictChooseMode(true);
        setStopAt(1, PhaseStep.POSTCOMBAT_MAIN);
        execute();
        assertPermanentCount(playerA, "Grizzly Bears", 1);
        assertHandCount(playerA, "Grizzly Bears", 0);
        assertTapped("Jasmine Boreal of the Seven", true);
        assertTrue(playerA.getManaPool().getConditionalMana().isEmpty());
        Qualification.observe("restricted_mana.positive_control_bears_cast_with_jasmine_only", true);
    }

    private void morphZeroManaValueFixture() throws Exception {
        reset();
        frozenDefaults();
        addCard(Zone.HAND, playerA, "Willbender");
        addCard(Zone.BATTLEFIELD, playerA, "Plains", 3);
        addCard(Zone.BATTLEFIELD, playerB, "Chalice of the Void");
        castSpell(1, PhaseStep.PRECOMBAT_MAIN, playerA, "Willbender using Morph");
        setStrictChooseMode(true);
        setStopAt(1, PhaseStep.POSTCOMBAT_MAIN);
        execute();
        assertGraveyardCount(playerA, "Willbender", 1);
        assertPermanentCount(playerA, EmptyNames.FACE_DOWN_CREATURE.getTestCommand(), 0);
        assertPermanentCount(playerB, "Chalice of the Void", 1);
        assertEquals(0, currentGame.getStack().size());
        Qualification.observe("zero_mana_value.chalice_countered_face_down_spell", true);
    }

    @Test
    public void adventure() {
        addCard(Zone.HAND, playerA, "Lovestruck Beast");
        addCard(Zone.BATTLEFIELD, playerA, "Forest", 3);
        addCard(Zone.BATTLEFIELD, playerA, "Plains");
        castSpell(1, PhaseStep.PRECOMBAT_MAIN, playerA, "Heart's Desire", true);
        runCode("adventure exiled and created token", 1, PhaseStep.PRECOMBAT_MAIN, playerA, (info, player, game) -> {
            assertExileCount(playerA, "Lovestruck Beast", 1);
            List<Permanent> tokens = game.getBattlefield().getAllActivePermanents(playerA.getId()).stream()
                    .filter(Permanent::isToken).collect(Collectors.toList());
            assertEquals(1, tokens.size());
            Permanent token = tokens.get(0);
            assertTrue(token.getColor(game).isWhite());
            assertTrue(token.hasSubtype(SubType.HUMAN, game));
            assertEquals(1, token.getPower().getValue());
            assertEquals(1, token.getToughness().getValue());
            Qualification.observe("after_adventure.exiled_beast", 1);
            Qualification.observe("after_adventure.token", "one white 1/1 Human");
        });
        castSpell(1, PhaseStep.PRECOMBAT_MAIN, playerA, "Lovestruck Beast");
        finish();
        assertExileCount(playerA, "Lovestruck Beast", 0);
        assertPowerToughness(playerA, "Lovestruck Beast", 5, 5);
    }

    @Test
    public void modalDfc() {
        addCard(Zone.HAND, playerA, "Bala Ged Recovery");
        playLand(1, PhaseStep.PRECOMBAT_MAIN, playerA, "Bala Ged Sanctuary");
        runCode("land face entered", 1, PhaseStep.PRECOMBAT_MAIN, playerA, (info, player, game) -> {
            assertPermanentCount(playerA, "Bala Ged Sanctuary", 1);
            assertTapped("Bala Ged Sanctuary", true);
            assertEquals(0, game.getStack().size());
            assertGraveyardCount(playerA, "Bala Ged Recovery", 0);
            assertHandCount(playerA, 0);
            Qualification.observe("entered_tapped_land_without_spell", true);
        });
        checkPermanentTapped("untapped next turn", 3, PhaseStep.PRECOMBAT_MAIN, playerA, "Bala Ged Sanctuary", false, 1);
        activateManaAbility(3, PhaseStep.PRECOMBAT_MAIN, playerA, "{T}: Add {G}");
        checkManaPool("green mana produced", 3, PhaseStep.PRECOMBAT_MAIN, playerA, "G", 1);
        runCode("mana observed", 3, PhaseStep.PRECOMBAT_MAIN, playerA, (info, player, game) ->
                Qualification.observe("green_mana", playerA.getManaPool().getGreen()));
        setStrictChooseMode(true);
        setStopAt(3, PhaseStep.POSTCOMBAT_MAIN);
        execute();
        observeState();
        assertTapped("Bala Ged Sanctuary", true);
    }

    @Test
    public void replacement() {
        addCard(Zone.BATTLEFIELD, playerA, "Rest in Peace");
        addCard(Zone.BATTLEFIELD, playerA, "Mountain");
        addCard(Zone.HAND, playerA, "Lightning Bolt");
        addCard(Zone.BATTLEFIELD, playerB, "Grizzly Bears");
        castSpell(1, PhaseStep.PRECOMBAT_MAIN, playerA, "Lightning Bolt", "Grizzly Bears");
        finish();
        assertExileCount("Lightning Bolt", 1);
        assertExileCount("Grizzly Bears", 1);
        assertGraveyardCount(playerA, 0);
        assertGraveyardCount(playerB, 0);
        assertPermanentCount(playerB, "Grizzly Bears", 0);
        Qualification.observe("exiled", new String[]{"Lightning Bolt", "Grizzly Bears"});
    }

    @Test
    public void copy() {
        addCard(Zone.BATTLEFIELD, playerB, "Grizzly Bears");
        addCard(Zone.BATTLEFIELD, playerB, "Forest");
        addCard(Zone.HAND, playerB, "Giant Growth");
        addCard(Zone.BATTLEFIELD, playerA, "Island", 4);
        addCard(Zone.HAND, playerA, "Clone");
        castSpell(1, PhaseStep.PRECOMBAT_MAIN, playerB, "Giant Growth", "Grizzly Bears", true);
        waitStackResolved(1, PhaseStep.PRECOMBAT_MAIN);
        // Player A waits for the actual Growth to resolve before casting Clone.
        castSpell(1, PhaseStep.PRECOMBAT_MAIN, playerA, "Clone");
        setChoice(playerA, true);
        setChoice(playerA, "Grizzly Bears");
        finish();
        assertPermanentCount(playerA, "Grizzly Bears", 1);
        assertPowerToughness(playerA, "Grizzly Bears", 2, 2);
        assertPowerToughness(playerB, "Grizzly Bears", 5, 5);
        Qualification.observe("copy_power_toughness", "2/2");
        Qualification.observe("original_power_toughness", "5/5");
    }

    @Test
    public void tokens() {
        addCard(Zone.HAND, playerA, "Raise the Alarm");
        addCard(Zone.BATTLEFIELD, playerA, "Plains", 2);
        castSpell(1, PhaseStep.PRECOMBAT_MAIN, playerA, "Raise the Alarm");
        finish();
        List<Permanent> tokens = currentGame.getBattlefield().getAllActivePermanents(playerA.getId()).stream()
                .filter(Permanent::isToken).collect(Collectors.toList());
        assertEquals(2, tokens.size());
        for (Permanent token : tokens) {
            assertTrue(token.getColor(currentGame).isWhite());
            assertTrue(token.hasSubtype(SubType.SOLDIER, currentGame));
            assertTrue(token.isCreature(currentGame));
            assertEquals(1, token.getPower().getValue());
            assertEquals(1, token.getToughness().getValue());
        }
        assertGraveyardCount(playerA, "Raise the Alarm", 1);
        assertLibraryCount(playerA, 30);
        assertHandCount(playerA, 0);
        Qualification.observe("tokens", "exactly two white 1/1 Soldier creatures");
    }
}
