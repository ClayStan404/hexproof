// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.common.eventbus.Subscribe;
import com.google.gson.*;
import forge.game.Game;
import forge.game.GameLog;
import forge.game.GameLogEntry;
import forge.game.GameLogFormatter;
import forge.game.card.Card;
import forge.game.event.*;
import forge.game.player.Player;
import forge.game.player.PlayerView;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Private, bounded observation journal. It never participates in rules or migration. */
final class NativeReplay {
    private static final int MAX_BYTES = 3 * 1024 * 1024;
    private static final Set<String> EVENTS = Set.of("GameEventTurnBegan", "GameEventTurnPhase",
            "GameEventLandPlayed", "GameEventSpellAbilityCast", "GameEventSpellResolved",
            "GameEventSpellRemovedFromStack", "GameEventCardChangeZone", "GameEventCardTapped",
            "GameEventCardCounters", "GameEventCardStatsChanged", "GameEventPlayerLivesChanged",
            "GameEventPlayerCounters", "GameEventManaPool", "GameEventPlayerDamaged", "GameEventCardDamaged",
            "GameEventAttackersDeclared", "GameEventBlockersDeclared", "GameEventCombatEnded",
            "GameEventCardAttachment", "GameEventMulligan", "GameEventScry", "GameEventSurveil",
            "GameEventShuffle", "GameEventGameOutcome", "GameEventCardModeChosen", "GameEventTokenCreated");
    private record Entry(long sequence, String json, int bytes) { }
    private final Game game;
    private final String gameId;
    private final long started = System.nanoTime();
    private final Deque<Entry> entries = new ArrayDeque<>();
    private long sequence;
    private int bytes;
    private boolean complete = true;

    NativeReplay(Game game, String gameId) {
        this.game = game; this.gameId = gameId;
        game.subscribeToEvents(this);
    }

    @Subscribe public void event(GameEvent event) {
        String kind = event.getClass().getSimpleName();
        if (!EVENTS.contains(kind)) return;
        try {
            GameLogEntry formatted = event.visit(new GameLogFormatter(new GameLog()));
            int actor = -1;
            if (event instanceof GameEventSpellAbilityCast cast) actor = playerIndex(cast.si().getActivatingPlayer());
            else if (event instanceof GameEventLandPlayed land) actor = playerIndex(land.player());
            else if (event instanceof GameEventAttackersDeclared attack) actor = playerIndex(attack.player());
            String text = formatted == null ? kind.substring("GameEvent".length()) : formatted.message();
            record(kind.substring("GameEvent".length()), actor, text);
        } catch (RuntimeException error) { incomplete(); }
    }

    private int playerIndex(PlayerView view) {
        for (int i = 0; i < game.getRegisteredPlayers().size(); i++)
            if (game.getRegisteredPlayers().get(i).getId() == view.getId()) return i;
        return -1;
    }

    // Called only on the native game/input thread, at the same boundaries as snapshots.
    synchronized void record(String kind, int actor, String text) {
        if (!complete || game.getRegisteredPlayers().size() != 2) return;
        try {
            Player priority = kind.equals("Decision") && actor >= 0 && actor < 2
                    ? game.getRegisteredPlayers().get(actor) : null;
            JsonObject view = NativeSnapshot.capture(game, gameId, -1, priority);
            JsonArray zones = view.getAsJsonArray("zones");
            for (int player = 0; player < 2; player++) {
                JsonObject own = NativeSnapshot.capture(game, gameId, player, priority);
                for (JsonElement value : own.getAsJsonArray("zones")) {
                    JsonObject zone = value.getAsJsonObject();
                    if (!zone.get("zone").getAsString().equals("hand")
                            || !zone.get("ownerId").getAsString().equals("player-" + player)) continue;
                    for (int index = 0; index < zones.size(); index++) {
                        JsonObject existing = zones.get(index).getAsJsonObject();
                        if (existing.get("zone").equals(zone.get("zone")) && existing.get("ownerId").equals(zone.get("ownerId")))
                            zones.set(index, zone);
                    }
                }
            }
            JsonObject frame = new JsonObject();
            frame.addProperty("sequence", ++sequence);
            frame.addProperty("elapsedMs", (System.nanoTime() - started) / 1_000_000);
            frame.addProperty("kind", kind);
            frame.addProperty("actor", actor);
            frame.addProperty("text", text == null ? "" : text.substring(0, Math.min(text.length(), 1200)));
            frame.add("view", view);
            frame.add("combat", combat());
            String encoded = frame.toString();
            int size = encoded.getBytes(StandardCharsets.UTF_8).length;
            if (bytes + size > MAX_BYTES || entries.size() >= 2000) { complete = false; return; }
            entries.add(new Entry(sequence, encoded, size)); bytes += size;
        } catch (RuntimeException error) { complete = false; }
    }

    private JsonArray combat() {
        JsonArray result = new JsonArray();
        var combat = game.getCombat();
        if (combat == null) return result;
        for (Card attacker : combat.getAttackers()) {
            JsonObject attack = new JsonObject();
            attack.addProperty("kind", "attack"); attack.addProperty("sourceId", NativeSession.cardId(attacker));
            var defender = combat.getDefenderByAttacker(attacker);
            if (defender instanceof Card card) attack.addProperty("targetId", NativeSession.cardId(card));
            else if (defender instanceof Player player) attack.addProperty("targetPlayer", game.getRegisteredPlayers().indexOf(player));
            result.add(attack);
            for (Card blocker : combat.getBlockers(attacker)) {
                JsonObject block = new JsonObject(); block.addProperty("kind", "block");
                block.addProperty("sourceId", NativeSession.cardId(blocker)); block.addProperty("targetId", NativeSession.cardId(attacker)); result.add(block);
            }
        }
        return result;
    }

    synchronized void incomplete() { complete = false; }

    // Acknowledgement removes only an already-received prefix; retries are idempotent.
    synchronized String read(long after) {
        if (after < 0 || after > sequence) throw new IllegalArgumentException("Invalid replay cursor");
        while (!entries.isEmpty() && entries.peekFirst().sequence() <= after) bytes -= entries.removeFirst().bytes();
        JsonObject result = new JsonObject(); result.addProperty("complete", complete);
        result.addProperty("lastSequence", sequence);
        JsonArray frames = new JsonArray();
        for (Entry entry : entries) frames.add(JsonParser.parseString(entry.json()));
        result.add("frames", frames); return result.toString();
    }
}
