// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import forge.game.mana.Mana;
import forge.game.player.Player;
import forge.game.spellability.SpellAbility;
import forge.game.zone.MagicStack;
import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.Map;
import java.util.Set;

/** Qualifies a native last-action undo without exposing non-mana actions. */
final class NativePriorityManaUndo {
    private NativePriorityManaUndo() { }

    static SpellAbility source(Player player) {
        SpellAbility ability = player.getGame().getStack().peekUndoStack();
        return canUndo(player, ability) ? ability : null;
    }

    static boolean canUndo(Player player, SpellAbility ability) {
        MagicStack stack = player.getGame().getStack();
        if (ability == null || player.getGame().isGameOver() || !player.isInGame()
                || player.getGame().getPhaseHandler().getPriorityPlayer() != player
                || !stack.canUndo(player) || stack.peekUndoStack() != ability) return false;

        Set<SpellAbility> refund = Collections.newSetFromMap(new IdentityHashMap<>());
        if (!collectRefund(player, ability, refund)) return false;
        Map<Mana, Integer> floating = counts(player.getManaPool());
        // The selected activation must be wholly unspent. In particular, an
        // equal-color globe from another source cannot replace a consumed one.
        if (!accounted(ability, floating)) return false;
        Map<Mana, Integer> available = new IdentityHashMap<>(floating);
        for (SpellAbility source : refund)
            for (Mana mana : source.getPayingMana()) available.merge(mana, 1, Integer::sum);
        // Native undo recursively refunds activation fees. Their exact globes
        // must still be in this refund graph or the pool, never another action.
        for (SpellAbility source : refund)
            if (!accounted(source, available)) return false;
        return true;
    }

    private static boolean collectRefund(Player player, SpellAbility ability, Set<SpellAbility> refund) {
        if (!refund.add(ability) || ability.getActivatingPlayer() != player
                || !ability.isManaAbility() || ability.isSpell() || ability.getManaPart() == null
                || ability.getAllManaParts().size() != 1 || ability.getPayCosts() == null
                || !ability.isUndoable()) return false;
        int recorded = 0;
        for (SpellAbility undo : player.getGame().getStack().filterUndoStackByHost(ability.getHostCard()))
            if (undo == ability) recorded++;
        // A reused ability can overwrite its previous activation's cost ledger.
        // Do not let native recursive refunds operate on ambiguous history.
        if (recorded != 1) return false;
        for (SpellAbility paid : ability.getPayingManaAbilities())
            if (!collectRefund(player, paid, refund)) return false;
        return true;
    }

    private static Map<Mana, Integer> counts(Iterable<Mana> mana) {
        Map<Mana, Integer> result = new IdentityHashMap<>();
        for (Mana globe : mana) result.merge(globe, 1, Integer::sum);
        return result;
    }

    private static boolean accounted(SpellAbility ability, Map<Mana, Integer> available) {
        Map<Mana, Integer> produced = counts(ability.getManaPart().getLastManaProduced());
        if (produced.isEmpty()) return false;
        for (Map.Entry<Mana, Integer> entry : produced.entrySet())
            if (!entry.getValue().equals(available.get(entry.getKey()))) return false;
        return true;
    }
}
