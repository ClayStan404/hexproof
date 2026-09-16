/*
 * Forge: Play Magic: the Gathering.
 * Copyright (C) 2011 Forge Team
 * Copyright (C) 2026 Hexproof contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */
// SPDX-License-Identifier: GPL-3.0-or-later
package org.hexproof.forge;

import forge.game.GameEntityView;
import forge.game.card.CardView;
import java.util.*;

/**
 * Remote validation of the public decisions accepted by the pinned desktop
 * VAssignCombatDamage. Forge computes damage, lethal damage and ability flags;
 * this adapter enforces the same dialog constraints before returning its map.
 */
final class NativeDamageAssignment {
    final List<CardView> blockers;
    final boolean deathtouch;
    final String defenderId;
    private final int total;
    private final boolean overrideOrder, divideDamage;
    private final GameEntityView defender;
    private final Map<String, CardView> allowed = new LinkedHashMap<>();
    private final Map<CardView, Integer> lethal = new HashMap<>();

    NativeDamageAssignment(CardView attacker, List<CardView> blockers, int total,
                           GameEntityView defender, boolean overrideOrder, String defenderId) {
        if (total < 0 || total > 100000 || blockers.size() > 512) throw new IllegalArgumentException("Invalid native damage bounds");
        this.blockers = List.copyOf(blockers);
        this.total = total;
        this.defender = defender;
        this.overrideOrder = overrideOrder;
        deathtouch = attacker.getCurrentState().hasDeathtouch();
        divideDamage = attacker.getCurrentState().hasDivideDamage();
        boolean canHitDefender = defender != null && (attacker.getCurrentState().hasTrample() || divideDamage && overrideOrder);
        this.defenderId = canHitDefender ? defenderId : "";
        for (CardView blocker : blockers) {
            if (allowed.put("card-" + blocker.getId(), blocker) != null) throw new IllegalArgumentException("Duplicate native damage assignee");
            int damage = Math.max(0, blocker.getLethalDamage());
            if (blocker.getCurrentState().isPlaneswalker()) damage = Integer.parseInt(blocker.getCurrentState().getLoyalty());
            else if (deathtouch) damage = Math.min(damage, 1);
            if (damage < 0 || damage > 100000) throw new IllegalArgumentException("Native lethal damage exceeds protocol bounds");
            lethal.put(blocker, damage);
        }
        if (canHitDefender) {
            if (allowed.containsKey(defenderId)) throw new IllegalArgumentException("Duplicate native defender");
            allowed.put(defenderId, null); // Native PlayerControllerHuman uses null for the defender.
        }
        if (allowed.isEmpty()) throw new IllegalArgumentException("Native damage has no assignees");
    }

    Map<CardView, Integer> validate(Map<String, Integer> amounts) {
        if (!amounts.keySet().equals(allowed.keySet())) throw new IllegalArgumentException("Damage must specify every native assignee exactly once");
        long sum = 0;
        for (int amount : amounts.values()) {
            if (amount < 0 || amount > total) throw new IllegalArgumentException("Invalid damage amount");
            sum += amount;
        }
        if (sum != total) throw new IllegalArgumentException("Damage must use the native total");
        Map<CardView, Integer> result = new LinkedHashMap<>();
        boolean earlierSurvives = false;
        for (Map.Entry<String, CardView> entry : allowed.entrySet()) {
            CardView card = entry.getValue();
            int amount = amounts.get(entry.getKey());
            if (!(overrideOrder && divideDamage) && earlierSurvives
                    && (!overrideOrder || card == null || card == defender) && amount > 0) {
                throw new IllegalArgumentException("Damage requires lethal assignment to preceding native blockers");
            }
            if (card != null) earlierSurvives |= amount < lethal.get(card);
            result.put(card, amount);
        }
        return result;
    }

    String mode() {
        return !overrideOrder ? "ordered" : divideDamage ? "divideFreely" : "unordered";
    }

    int lethalDamage(CardView blocker) {
        Integer amount = lethal.get(blocker);
        if (amount == null) throw new IllegalArgumentException("Card is outside the native damage candidates");
        return amount;
    }
}
