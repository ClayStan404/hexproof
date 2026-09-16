// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import forge.game.card.CardView;
import forge.game.player.Player;
import forge.game.player.PlayerView;
import forge.game.spellability.SpellAbilityView;
import forge.gui.interfaces.IGuiGame;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import static org.hexproof.forge.NativeSession.*;

/** Preserves the native dual-list choice and returns the original candidate objects. */
final class NativeOrdering {
    private NativeOrdering() { }

    static IGuiGame.OrderResult<?> order(NativeSession session, Player owner, String title,
            int remainingMin, int remainingMax, List<?> source, List<?> destination) {
        List<Object> candidates = new ArrayList<>();
        if (source != null) candidates.addAll(source);
        if (destination != null) candidates.addAll(destination);
        // Native destination entries are initially selected, but may move back
        // into the source list. The bounds constrain the final remaining list.
        int total = candidates.size();
        int min = remainingMax < 0 ? 0 : Math.max(0, total - remainingMax);
        int max = remainingMax < 0 || remainingMin <= 0 ? total : total - remainingMin;
        if (min > max || total > 512) {
            throw new IllegalArgumentException("Invalid native ordering bounds");
        }
        List<?> selected = min == total && max == total ? candidates
                : select(session, owner, title, min, max, candidates);
        return new IGuiGame.OrderResult<>(reorder(session, owner, title, selected), false);
    }

    static List<?> insertInList(NativeSession session, Player owner, String title, Object item, List<?> oldItems) {
        List<Object> result = new ArrayList<>(oldItems);
        if (result.isEmpty()) { result.add(item); return result; }
        if (result.size() >= 512) throw new IllegalArgumentException("Native insertion has too many positions");
        JsonObject input = input("chooseFromSelection", title);
        JsonArray options = new JsonArray();
        JsonObject first = object("label", "First"); first.addProperty("weight", 1); first.addProperty("canRepeat", false); options.add(first);
        for (Object existing : result) {
            JsonObject option = object("label", "After " + label(owner, existing));
            option.addProperty("weight", 1); option.addProperty("canRepeat", false); options.add(option);
        }
        input.add("options", options); input.addProperty("minTotal", 1); input.addProperty("maxTotal", 1);
        int position = session.ask(owner, input, raw -> {
            requireType(raw, "selectionDecision");
            JsonArray selected = raw.getAsJsonArray("chosenIndices");
            if (selected.size() != 1) throw new IllegalArgumentException("Choose one insertion position");
            int value = selected.get(0).getAsInt();
            if (value < 0 || value > result.size()) throw new IllegalArgumentException("Invalid insertion position");
            return value;
        });
        result.add(position, item);
        return result;
    }

    private static List<?> select(NativeSession session, Player owner, String title, int min, int max, List<?> candidates) {
        if (candidates.isEmpty()) return List.of();
        boolean cardsOnly = candidates.stream().allMatch(CardView.class::isInstance);
        JsonObject input = input(cardsOnly ? "chooseCards" : "chooseFromSelection", title);
        JsonArray choices = new JsonArray();
        Map<String, Object> cards = new LinkedHashMap<>();
        for (Object candidate : candidates) {
            if (cardsOnly) {
                CardView card = (CardView) candidate;
                if (cards.put("card-" + card.getId(), candidate) != null) throw new IllegalArgumentException("Duplicate native card candidate");
                choices.add(promptCard(owner, card));
            } else {
                JsonObject option = object("label", label(owner, candidate));
                option.addProperty("weight", 1); option.addProperty("canRepeat", false); choices.add(option);
            }
        }
        input.add(cardsOnly ? "cards" : "options", choices);
        input.addProperty(cardsOnly ? "min" : "minTotal", min);
        input.addProperty(cardsOnly ? "max" : "maxTotal", max);
        return session.ask(owner, input, raw -> {
            requireType(raw, cardsOnly ? "chooseCardsDecision" : "selectionDecision");
            JsonArray selected = raw.getAsJsonArray(cardsOnly ? "chosenCardIds" : "chosenIndices");
            if (selected.size() < min || selected.size() > max) throw new IllegalArgumentException("Invalid native selection count");
            Set<Object> seen = new HashSet<>();
            List<Object> result = new ArrayList<>();
            for (JsonElement entry : selected) {
                if (cardsOnly) {
                    String id = entry.getAsString();
                    if (!cards.containsKey(id) || !seen.add(id)) throw new IllegalArgumentException("Invalid native card selection");
                    result.add(cards.get(id));
                } else {
                    int index = entry.getAsInt();
                    if (index < 0 || index >= candidates.size() || !seen.add(index)) throw new IllegalArgumentException("Invalid native selection index");
                    result.add(candidates.get(index));
                }
            }
            return result;
        });
    }

    private static List<?> reorder(NativeSession session, Player owner, String title, List<?> selected) {
        List<?> candidates = List.copyOf(selected);
        if (candidates.size() < 2) return candidates;
        JsonObject input = input("reorder", title);
        JsonArray items = new JsonArray();
        Map<String, Object> allowed = new LinkedHashMap<>();
        for (int i = 0; i < candidates.size(); i++) {
            Object candidate = candidates.get(i);
            String id = "order-" + i;
            JsonObject item = object("id", id); item.addProperty("oracle", label(owner, candidate));
            CardView card = candidate instanceof CardView c ? c : candidate instanceof SpellAbilityView ability ? ability.getHostCard() : null;
            if (card != null) item.add("card", promptCard(owner, card));
            items.add(item); allowed.put(id, candidate);
        }
        input.add("items", items);
        return session.ask(owner, input, raw -> {
            requireType(raw, "reorderDecision");
            JsonArray selectedIds = raw.getAsJsonArray("orderedIds");
            if (selectedIds.size() != candidates.size()) throw new IllegalArgumentException("Invalid native order size");
            Set<String> seen = new HashSet<>();
            List<Object> result = new ArrayList<>();
            for (JsonElement entry : selectedIds) {
                String id = entry.getAsString();
                if (!allowed.containsKey(id) || !seen.add(id)) throw new IllegalArgumentException("Invalid native order ID");
                result.add(allowed.get(id));
            }
            return result;
        });
    }

    private static String label(Player owner, Object value) {
        if (value instanceof CardView card) return card.isFaceDown() && !card.canFaceDownBeShownTo(owner.getView()) ? "Face-down card" : card.getName();
        if (value instanceof PlayerView player) return player.getName();
        if (value instanceof SpellAbilityView ability) return ability.getDescription();
        return Objects.toString(value, "");
    }

    private static JsonObject promptCard(Player owner, CardView card) {
        JsonObject result = object("id", "card-" + card.getId());
        result.add("identity", object("name", label(owner, card)));
        return result;
    }

    private static JsonObject input(String type, String title) {
        JsonObject result = object("type", type);
        result.add("presentation", object("title", title));
        return result;
    }

    private static void requireType(JsonObject response, String expected) {
        if (!text(response, "type", "").equals(expected)) throw new IllegalArgumentException("Unexpected native ordering response");
    }
}
