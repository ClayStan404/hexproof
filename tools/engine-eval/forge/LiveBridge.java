// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import com.google.gson.*;
import forge.harness.host.ManaBrewEngineAdapter;
import forge.harness.host.ManaBrewInteractiveSession;
import java.io.*;
import java.nio.file.*;
import java.util.*;

/** Local trusted hot-seat evaluation bridge. Never expose this on a network. */
public final class LiveBridge {
    static final ManaBrewEngineAdapter adapter = new ManaBrewEngineAdapter();
    static final PrintStream wire = System.out;
    static final BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
    static final String session = "native-laboratory";
    static long sequence;
    static int playerCount = 2;

    public static void main(String[] args) throws Exception {
        System.setOut(System.err);
        adapter.initialize(args[0]);
        ManaBrewInteractiveSession.setBridge(LiveBridge::exchange);
        List<ManaBrewEngineAdapter.CardIdentity> deck = new ArrayList<>();
        for (String name : List.of("Forest", "Grizzly Bears")) for (int i = 0; i < 30; i++)
            deck.add(new ManaBrewEngineAdapter.CardIdentity(name, null, null, false));
        List<ManaBrewEngineAdapter.PlayerConfig> players = new ArrayList<>();
        for (int i = 0; i < 2; i++) players.add(new ManaBrewEngineAdapter.PlayerConfig("Seat " + i, deck, List.of(), false));
        String variant = "Constructed";
        int life = 20, startingPlayer = 0;
        long seed = 42;
        if (args.length != 1 && args.length != 3) throw new IllegalArgumentException("Assets [workloads.json workload-id]");
        if (args.length == 3) {
            JsonObject selected = null;
            for (JsonElement value : JsonParser.parseString(Files.readString(Path.of(args[1]))).getAsJsonObject().getAsJsonArray("workloads"))
                if (value.getAsJsonObject().get("id").getAsString().equals(args[2])) selected = value.getAsJsonObject();
            if (selected == null) throw new IllegalArgumentException("Unknown workload: " + args[2]);
            variant = selected.get("variant").getAsString(); life = selected.get("startingLife").getAsInt();
            seed = selected.get("seed").getAsLong(); startingPlayer = selected.get("startingPlayer").getAsInt();
            players.clear();
            for (JsonElement value : selected.getAsJsonArray("players")) {
                JsonObject p = value.getAsJsonObject();
                List<ManaBrewEngineAdapter.CardIdentity> cards = new ArrayList<>();
                for (JsonElement c : p.getAsJsonArray("cards")) for (int i = 0; i < c.getAsJsonObject().get("count").getAsInt(); i++)
                    cards.add(new ManaBrewEngineAdapter.CardIdentity(c.getAsJsonObject().get("name").getAsString(), null, null, false));
                List<String> commanders = new ArrayList<>();
                for (JsonElement c : p.getAsJsonArray("commanders")) commanders.add(c.getAsString());
                players.add(new ManaBrewEngineAdapter.PlayerConfig(p.get("name").getAsString(), cards, commanders, false));
            }
        }
        playerCount = players.size();
        try {
            adapter.startGame(new ManaBrewEngineAdapter.StartGameRequest(session, variant, life, seed, players, startingPlayer));
            JsonObject result = new JsonObject(); result.addProperty("type", "result"); result.addProperty("engine", "Forge");
            result.add("view", normalizedView(-1));
            result.addProperty("gameOver", Boolean.parseBoolean(adapter.getGameOver(session)));
            result.addProperty("naturalCompletion", Boolean.parseBoolean(adapter.getGameOver(session)));
            JsonObject finalState = JsonParser.parseString(adapter.getSnapshot(session, -1)).getAsJsonObject();
            if (finalState.has("winnerId")) result.add("winner", finalState.get("winnerId"));
            result.addProperty("decisions", sequence); wire.println(result);
        } finally { adapter.endGame(session); }
    }

    static String exchange(String raw) {
        JsonObject prompt = JsonParser.parseString(raw).getAsJsonObject();
        JsonObject decision = new JsonObject();
        decision.addProperty("type", "decision"); decision.addProperty("engine", "Forge");
        decision.addProperty("id", ++sequence);
        decision.addProperty("actor", Integer.parseInt(prompt.get("decidingPlayerId").getAsString().substring(7)));
        JsonObject p = prompt.getAsJsonObject("input");
        String kind = p.get("type").getAsString(); decision.addProperty("kind", kind);
        decision.addProperty("message", p.has("presentation") ? p.get("presentation").toString() : kind);
        JsonArray views = new JsonArray(); for (int viewer = -1; viewer < playerCount; viewer++) views.add(normalizedView(viewer));
        decision.add("views", views);
        JsonArray actions = new JsonArray();
        switch (kind) {
            case "mulligan" -> actions.add(action("Keep seven", "keep", "{\"kind\":\"pass\"}"));
            case "chooseAction" -> {
                for (JsonElement element : p.getAsJsonArray("actions")) {
                    JsonObject option = element.getAsJsonObject();
                    String label = option.has("label") ? option.get("label").getAsString()
                            : option.has("description") ? option.get("description").getAsString() : option.get("type").getAsString();
                    String category = label.startsWith("Play ") ? "land" : label.startsWith("Cast ") ? "cast" : "other";
                    JsonObject mapped = action(label, category, "{\"type\":\"chooseAction\",\"output\":{\"type\":\"act\",\"actionId\":" + option.get("id") + "}}");
                    if (option.has("cardId")) mapped.add("cardId", option.get("cardId"));
                    actions.add(mapped);
                }
                actions.add(action("Pass priority", "pass", "{\"kind\":\"pass\"}"));
            }
            case "payManaCost" -> {
                if (p.get("canConfirmFromPool").getAsBoolean()) actions.add(action("Confirm payment", "confirm", "{\"kind\":\"pay_mana\"}"));
                for (JsonElement element : p.getAsJsonArray("actions")) {
                    JsonObject option = element.getAsJsonObject();
                    if (!option.get("type").getAsString().equals("activateManaAbility")) continue;
                    actions.add(action("Tap " + option.get("description").getAsString(), "mana",
                            "{\"type\":\"payManaCost\",\"output\":{\"type\":\"act\",\"actionId\":" + option.get("id") + "}}"));
                }
            }
            case "chooseAttackers" -> {
                JsonArray assignments = new JsonArray();
                for (JsonElement element : p.getAsJsonArray("attackers")) {
                    JsonObject attacker = element.getAsJsonObject();
                    JsonArray targets = attacker.getAsJsonArray("validTargetIds");
                    if (targets.size() > 0) {
                        JsonObject assignment = new JsonObject(); assignment.add("attackerId", attacker.get("attackerId"));
                        assignment.add("defenderId", targets.get(0)); assignments.add(assignment);
                    }
                }
                actions.add(action("Attack with all legal creatures", "attack_all", "{\"kind\":\"declare_attackers\",\"assignments\":" + assignments + "}"));
                actions.add(action("Attack with none", "pass", "{\"kind\":\"pass\"}"));
            }
            case "chooseBlockers" -> actions.add(action("Declare no blockers", "block_none", "{\"kind\":\"pass\"}"));
            case "chooseBoolean" -> actions.add(action("Confirm", "confirm", "{\"kind\":\"boolean_decision\",\"accept\":true}"));
            case "chooseCards" -> {
                JsonArray chosen = new JsonArray();
                int minimum = p.get("min").getAsInt();
                for (int i = 0; i < minimum; i++) chosen.add(p.getAsJsonArray("cards").get(i).getAsJsonObject().get("id"));
                actions.add(action("Choose first " + minimum + " legal cards", "confirm",
                        "{\"type\":\"chooseCards\",\"output\":{\"type\":\"chooseCardsDecision\",\"chosenCardIds\":" + chosen + "}}"));
            }
            case "chooseBoardTargets" -> {
                for (JsonElement candidate : p.getAsJsonArray("candidates")) {
                    JsonObject c = candidate.getAsJsonObject();
                    String id = c.get("id").getAsString();
                    String category = id.startsWith("player-") && !id.equals("player-" + decision.get("actor").getAsInt()) ? "target_opponent" : "target";
                    actions.add(action("Target " + id, category,
                            "{\"type\":\"chooseBoardTargets\",\"output\":{\"chosen\":[" + c + "]}}"));
                }
            }
            case "diceRolled", "revealCards" -> actions.add(action("Continue", "confirm", "{\"kind\":\"pass\"}"));
            default -> throw new IllegalStateException("Unsupported laboratory prompt (not an engine verdict): " + raw);
        }
        decision.add("actions", actions); wire.println(decision); wire.flush();
        try {
            while (true) {
                String line = input.readLine(); if (line == null) throw new IllegalStateException("Laboratory disconnected");
                JsonObject response = JsonParser.parseString(line).getAsJsonObject();
                if (!response.has("id") || !response.has("actor") || response.get("id").getAsLong() != sequence
                        || response.get("actor").getAsInt() != decision.get("actor").getAsInt()
                        || !offered(actions, response.get("response"))) {
                    JsonObject error = new JsonObject(); error.addProperty("type", "error");
                    error.addProperty("message", "Stale, wrong actor, or unoffered response in test-only hot-seat host");
                    wire.println(error); wire.flush();
                    continue;
                }
                return response.get("response").toString();
            }
        } catch (IOException error) { throw new UncheckedIOException(error); }
    }

    static boolean offered(JsonArray actions, JsonElement response) {
        for (JsonElement value : actions) if (value.getAsJsonObject().get("response").equals(response)) return true;
        return false;
    }

    static JsonObject action(String label, String category, String response) {
        JsonObject result = new JsonObject(); result.addProperty("label", label); result.addProperty("category", category);
        result.add("response", JsonParser.parseString(response)); return result;
    }

    static JsonObject normalizedView(int viewer) {
        JsonObject original = JsonParser.parseString(adapter.getSnapshot(session, viewer)).getAsJsonObject();
        JsonObject result = new JsonObject(); result.addProperty("viewer", viewer);
        result.add("players", original.get("players")); result.add("turn", original.get("turn")); result.add("step", original.get("step"));
        JsonArray zones = new JsonArray();
        for (JsonElement element : original.getAsJsonArray("zones")) {
            JsonObject zone = element.getAsJsonObject(); JsonObject item = new JsonObject();
            item.addProperty("owner", Integer.parseInt(zone.get("ownerId").getAsString().substring(7)));
            item.add("zone", zone.get("zone")); item.add("count", zone.get("count"));
            JsonArray cards = new JsonArray();
            for (JsonElement cardElement : zone.getAsJsonArray("cards")) {
                JsonObject card = cardElement.getAsJsonObject(); JsonObject entry = new JsonObject(); entry.add("id", card.get("id"));
                entry.addProperty("name", card.has("identity") ? card.getAsJsonObject("identity").get("name").getAsString() : "Hidden card");
                for (String field : List.of("tapped", "power", "toughness")) if (card.has(field)) entry.add(field, card.get(field));
                cards.add(entry);
            }
            item.add("cards", cards); zones.add(item);
        }
        result.add("zones", zones);
        JsonArray stack = new JsonArray();
        for (JsonElement element : original.getAsJsonArray("stack")) {
            JsonObject source = element.getAsJsonObject(); JsonObject entry = new JsonObject();
            entry.add("id", source.get("id"));
            if (source.has("sourceId")) entry.add("cardId", source.get("sourceId"));
            entry.add("name", source.getAsJsonObject("identity").get("name")); stack.add(entry);
        }
        result.add("stack", stack); return result;
    }
}
