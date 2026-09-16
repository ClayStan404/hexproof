// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import forge.ai.ComputerUtilAbility;
import forge.ai.ComputerUtilMana;
import forge.ai.PlayerControllerAi;
import forge.game.GameActionUtil;
import forge.game.cost.CostTap;
import forge.game.keyword.Keyword;
import forge.game.player.Player;
import forge.game.spellability.SpellAbility;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

/** A conservative priority hint, using the same native candidates as card selection. */
final class NativePriority {
    private NativePriority() { }

    static boolean autoPassEligible(Player player, List<SpellAbility> abilities) {
        // Floating mana is an intentional resource decision, even without a payable spell.
        if (!player.getManaPool().isEmpty()) return false;
        long deadline = System.nanoTime() + 150_000_000L;
        AtomicBoolean eligible = new AtomicBoolean(false);
        try {
            // Forge's AvailableActions uses this controller scope too: cost-adjustment
            // prediction must not open a human payment/amount choice.
            player.runWithController(() -> eligible.set(noAvailableAction(player, abilities, deadline)),
                    new PlayerControllerAi(player.getGame(), player, player.getOriginalLobbyPlayer()));
        } catch (RuntimeException error) {
            // An uncertain predictive check must keep the player's priority window.
            return false;
        }
        return eligible.get() && System.nanoTime() < deadline;
    }

    private static boolean noAvailableAction(Player player, List<SpellAbility> abilities, long deadline) {
        boolean uncertainManaSources = abilities.stream().filter(SpellAbility::isManaAbility)
                .anyMatch(ability -> !ability.getHostCard().getType().isBasicLand()
                        || ability.getHostCard().isCreature() || ability.getHostCard().isEnchanted()
                        || ability.getSubAbility() != null || !ability.getHostCard().getTriggers().isEmpty()
                        || ability.getPayCosts() == null
                        || ability.getPayCosts().getCostParts().stream().anyMatch(cost -> !(cost instanceof CostTap)));
        for (SpellAbility ability : abilities) {
            if (System.nanoTime() >= deadline) return false;
            if (ability.isManaAbility()) continue;
            // Native selection also admits optional/alternative payments. A base-cost
            // estimate cannot rule these out before those choices have been made.
            if (ability.isOffering() || ability.isEmerge() || ability.hasParam("AlternateCost")
                    || !GameActionUtil.getOptionalCostValues(ability).isEmpty()) return false;
            // The upstream AI payment predictor can refuse sacrifices, filter sources,
            // life payments, and additional resource choices for strategic reasons.
            // Only use its negative result for ordinary payments from basic lands.
            // A positive estimate still preserves priority with any kind of source.
            boolean uncertainCost = ability.hasParam("TapCreaturesForMana")
                    || ability.getMaxWaterbend() != null || ability.hasParam("AIPhyrexianPayment")
                    || ability.getHostCard().hasKeyword(Keyword.CONVOKE)
                    || ability.getHostCard().hasKeyword(Keyword.IMPROVISE)
                    || ability.getHostCard().hasKeyword(Keyword.DELVE)
                    || ability.getHostCard().hasKeyword(Keyword.ASSIST)
                    || (ability.getPayCosts() != null && ability.getPayCosts().getTotalMana().hasPhyrexian())
                    || player.hasKeyword("PayLifeInsteadOf:B");
            if (uncertainCost) return false;
            // Targets on a later sub-ability can depend on an earlier effect resolving.
            for (SpellAbility sub = ability.getSubAbility(); sub != null; sub = sub.getSubAbility())
                if (sub.usesTargeting()) return false;
            if (ComputerUtilAbility.isFullyTargetable(ability)
                    && (ability.getPayCosts() == null || !ability.getPayCosts().hasManaCost()
                        || ComputerUtilMana.canPayManaCost(ability, player, 0, false))) return false;
            if (uncertainManaSources) return false;
        }
        return true;
    }
}
