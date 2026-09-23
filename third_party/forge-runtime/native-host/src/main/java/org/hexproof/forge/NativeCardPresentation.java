// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import java.util.Map;

/** Missing display annotations for reviewed scripts in the pinned card database. */
final class NativeCardPresentation {
    private NativeCardPresentation() {}

    static Map<String, String> hints(String name, Map<String, String> parameters) {
        String stack = switch (name) {
            case "Duress" -> "Discard".equals(parameters.get("SP"))
                    && "Card.nonCreature+nonLand".equals(parameters.get("DiscardValid"))
                    ? "SpellDescription" : null;
            case "Deadly Cover-Up" -> {
                if (!"ChangeZone".equals(parameters.get("DB"))) yield null;
                yield switch (parameters.getOrDefault("ChangeType", "")) {
                    case "Card.OppCtrl" -> "SpellDescription";
                    case "Remembered.sameName" -> "None";
                    default -> null;
                };
            }
            case "Shallow Grave" -> {
                if ("ChangeZone".equals(parameters.get("SP"))
                        && "Creature.TopGraveyardCreature+YouCtrl".equals(parameters.get("ChangeType")))
                    yield "SpellDescription";
                yield "Animate".equals(parameters.get("DB"))
                        && "Remembered".equals(parameters.get("Defined"))
                        && "Exile".equals(parameters.get("AtEOT"))
                        && "Haste".equals(parameters.get("Keywords")) ? "None" : null;
            }
            default -> null;
        };
        if (stack != null && (!stack.equals("SpellDescription") || parameters.containsKey("SpellDescription")))
            return Map.of("StackDescription", stack);
        if (name.equals("Emptiness") && "ChangeZone".equals(parameters.get("DB"))
                && "Graveyard".equals(parameters.get("Origin"))
                && "Battlefield".equals(parameters.get("Destination"))
                && "Creature.YouCtrl+cmcLE3".equals(parameters.get("ValidTgts")))
            return Map.of("TgtPrompt", "Select target creature card with mana value 3 or less from your graveyard");
        return Map.of();
    }
}
