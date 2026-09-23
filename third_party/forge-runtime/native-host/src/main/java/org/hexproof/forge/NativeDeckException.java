// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** Bounded deck rejection coordinates; no submitted identity enters the wire response. */
final class NativeDeckException extends IllegalArgumentException {
    enum Code {
        PRINTING_UNAVAILABLE("printing_unavailable", "Requested card printing is unavailable"),
        COMMANDER_MISSING("commander_missing", "Commander missing from deck"),
        INVALID_DECK_SIZE("invalid_deck_size", "Invalid deck size"),
        INVALID_SIDEBOARD_SIZE("invalid_sideboard_size", "Invalid sideboard size");

        final String wire;
        final String message;
        Code(String wire, String message) { this.wire = wire; this.message = message; }
    }

    private record Issue(int playerIndex, String section, int cardIndex, Code code) { }
    private final List<Issue> issues;
    private final boolean truncated;

    private NativeDeckException(List<Issue> issues, boolean truncated) {
        super(issues.get(0).code().message);
        this.issues = List.copyOf(issues);
        this.truncated = truncated;
    }

    JsonObject startFailure() {
        JsonObject failure = new JsonObject();
        failure.addProperty("reason", "deck_rejected");
        JsonArray entries = new JsonArray();
        for (Issue issue : issues) {
            JsonObject entry = new JsonObject();
            entry.addProperty("playerIndex", issue.playerIndex());
            entry.addProperty("section", issue.section());
            entry.addProperty("cardIndex", issue.cardIndex());
            entry.addProperty("code", issue.code().wire);
            entries.add(entry);
        }
        failure.add("issues", entries);
        failure.addProperty("truncated", truncated);
        return failure;
    }

    static final class Builder {
        private static final int LIMIT = 32;
        private final List<Issue> issues = new ArrayList<>();
        private final Set<List<Object>> seen = new HashSet<>();
        private boolean truncated;

        void add(int player, String section, int index, Code code, String... identity) {
            // Deduplicate copies before applying the limit, separately per seat
            // and section. Preserve the first submitted array index for mapping.
            List<Object> key = new ArrayList<>(List.of(player, section, code));
            key.addAll(Arrays.asList(identity));
            if (!seen.add(key)) return;
            if (issues.size() == LIMIT) { truncated = true; return; }
            issues.add(new Issue(player, section, index, code));
        }

        void rejectIfPresent() {
            if (!issues.isEmpty()) throw new NativeDeckException(issues, truncated);
        }
    }
}
