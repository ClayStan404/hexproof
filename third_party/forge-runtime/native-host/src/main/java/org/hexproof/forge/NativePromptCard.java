// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.JsonObject;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import forge.game.card.Card;
import forge.game.card.CardView;
import forge.game.player.Player;
import forge.util.Visitor;
import java.util.IdentityHashMap;
import java.util.Map;
import java.util.LinkedHashMap;
import java.util.List;
import static org.hexproof.forge.NativeSession.object;

/** Serializes only the card views explicitly supplied by one native prompt. */
final class NativePromptCard {
    private final NativeSession session;
    private final Player viewer;
    private Map<CardView, Card> cardsByView;

    NativePromptCard(NativeSession session, Player viewer) {
        if (viewer.getGame() != session.game) throw new IllegalArgumentException("Prompt viewer belongs to another game");
        this.session = session;
        this.viewer = viewer;
    }

    JsonObject describe(CardView view) {
        JsonObject result = object("id", "card-" + view.getId());
        // Check the supplied view's disclosure permission before resolving any
        // physical object. An explicit candidate is not permission to unmask it.
        if (view.isFaceDown() && !view.canFaceDownBeShownTo(viewer.getView())) {
            result.add("identity", object("name", "Face-down card"));
            return result;
        }
        if (cardsByView == null) {
            cardsByView = new IdentityHashMap<>();
            // One index per serialization, including wish/sideboard candidates;
            // no repeated whole-library scan and no index across zone changes.
            session.game.forEachCardInGame(new Visitor<Card>() {
                @Override public boolean visit(Card card) {
                    cardsByView.put(card.getView(), card);
                    return true;
                }
            }, true);
        }
        // Object identity is essential: an ID-only lookup could lend a hidden
        // printing to a detached or stale view with the same numerical ID.
        Card card = cardsByView.get(view);
        if (card != null && card.isFaceDown() && !view.canFaceDownBeShownTo(viewer.getView())) {
            result.add("identity", object("name", "Face-down card"));
        } else {
            result.add("identity", card == null ? object("name", view.getName()) : NativeSnapshot.identity(card));
        }
        return result;
    }

    JsonArray withRevealed(JsonArray candidates, List<CardView> revealed) {
        Map<String, JsonObject> remaining = new LinkedHashMap<>();
        for (JsonElement candidate : candidates) {
            JsonObject card = candidate.getAsJsonObject();
            remaining.put(card.get("id").getAsString(), card);
        }
        JsonArray result = new JsonArray();
        var seen = new java.util.HashSet<String>();
        for (CardView view : revealed) {
            String id = "card-" + view.getId();
            if (!seen.add(id)) continue;
            JsonObject card = remaining.remove(id);
            if (card == null) {
                card = describe(view);
                card.addProperty("readOnly", true);
            }
            result.add(card);
        }
        for (JsonObject card : remaining.values()) result.add(card);
        if (result.size() > 512) throw new IllegalArgumentException("Too many visible selection cards");
        return result;
    }
}
