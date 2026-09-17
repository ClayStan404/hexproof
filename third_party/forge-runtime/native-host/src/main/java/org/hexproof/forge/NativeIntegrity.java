// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.game.Game;
import forge.game.card.Card;
import forge.game.player.Player;
import forge.game.spellability.SpellAbility;
import forge.game.zone.ZoneType;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;

/** Replay drift guard captured at the same paused boundary as viewer snapshots.
 * This is a logical-state digest, not a serialized JVM or an anti-cheat claim.
 * Hidden source data stays inside this method; only its digest leaves Java.
 */
final class NativeIntegrity {
    private NativeIntegrity() { }

    static String capture(Game game, NativeExecution context) {
        try {
            JsonObject state = new JsonObject();
            state.add("execution", context.integrity());
            JsonArray players = new JsonArray();
            for (Player player : game.getRegisteredPlayers()) {
                JsonObject entry = new JsonObject();
                entry.addProperty("id", NativeSnapshot.playerId(game, player));
                JsonObject zones = new JsonObject();
                for (ZoneType zone : ZoneType.values()) {
                    if (player.getZone(zone) == null) continue;
                    JsonArray cards = new JsonArray();
                    for (Card card : player.getCardsIn(zone)) {
                        JsonObject object = new JsonObject();
                        object.addProperty("id", card.getId());
                        object.addProperty("timestamp", card.getGameTimestamp());
                        object.add("identity", NativeSnapshot.identity(card));
                        object.addProperty("controller", NativeSnapshot.playerId(game, card.getController()));
                        object.addProperty("faceDown", card.isFaceDown());
                        object.addProperty("tapped", card.isTapped());
                        object.addProperty("damage", card.getDamage());
                        object.addProperty("power", card.getNetPower());
                        object.addProperty("toughness", card.getNetToughness());
                        object.add("svars", NativeHost.JSON.toJsonTree(new TreeMap<>(card.getSVars())));
                        object.addProperty("chosenType", card.getChosenType());
                        object.addProperty("chosenType2", card.getChosenType2());
                        object.addProperty("chosenNumber", card.getChosenNumber());
                        object.addProperty("chosenMode", card.getChosenMode());
                        object.add("chosenPlayer", reference(game, card.getChosenPlayer()));
                        object.add("chosenCards", references(game, card.getChosenCards()));
                        object.add("remembered", references(game, card.getRemembered()));
                        object.add("exiled", references(game, card.getExiledCards()));
                        object.add("exiledWith", reference(game, card.getExiledWith()));
                        cards.add(object);
                    }
                    zones.add(zone.name(), cards);
                }
                entry.add("zones", zones);
                players.add(entry);
            }
            state.add("players", players);
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(canonical(state).toString().getBytes(StandardCharsets.UTF_8)));
        } catch (Exception unsupported) {
            // Exotic remembered values disable migration for this position.
            // They must not interrupt a game that can otherwise continue.
            return "";
        }
    }

    private static JsonArray references(Game game, Iterable<?> values) {
        JsonArray result = new JsonArray();
        if (values != null) for (Object value : values) result.add(reference(game, value));
        return result;
    }

    private static JsonElement reference(Game game, Object value) {
        if (value == null) return JsonNull.INSTANCE;
        if (value instanceof Card card) return new JsonPrimitive("card:" + card.getId() + ":" + card.getGameTimestamp());
        if (value instanceof Player player) return new JsonPrimitive(NativeSnapshot.playerId(game, player));
        if (value instanceof SpellAbility ability) return new JsonPrimitive("ability:" + ability.getId());
        if (value instanceof String text) return new JsonPrimitive(text);
        if (value instanceof Number number) return new JsonPrimitive(number);
        if (value instanceof Boolean flag) return new JsonPrimitive(flag);
        if (value instanceof Enum<?> choice) return new JsonPrimitive(choice.getDeclaringClass().getName() + ":" + choice.name());
        throw new IllegalArgumentException("Unsupported remembered value");
    }

    private static JsonElement canonical(JsonElement value) {
        if (value.isJsonObject()) {
            JsonObject result = new JsonObject();
            for (String key : new TreeSet<>(value.getAsJsonObject().keySet()))
                result.add(key, canonical(value.getAsJsonObject().get(key)));
            return result;
        }
        if (value.isJsonArray()) {
            JsonArray result = new JsonArray();
            for (JsonElement item : value.getAsJsonArray()) result.add(canonical(item));
            return result;
        }
        return value;
    }
}
