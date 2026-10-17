// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.eval;

import com.google.gson.Gson;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.google.gson.JsonElement;
import mage.MageObject;
import mage.abilities.Ability;
import mage.abilities.ActivatedAbility;
import mage.abilities.PlayLandAbility;
import mage.abilities.SpellAbility;
import mage.cards.Card;
import mage.cards.CardSetInfo;
import mage.cards.basiclands.Forest;
import mage.cards.decks.Deck;
import mage.cards.g.GrizzlyBears;
import mage.cards.repository.CardInfo;
import mage.cards.repository.CardRepository;
import mage.collectors.DataCollectorServices;
import mage.constants.MultiplayerAttackOption;
import mage.constants.ManaType;
import mage.constants.RangeOfInfluence;
import mage.constants.Rarity;
import mage.constants.CommanderCardType;
import mage.game.Game;
import mage.game.FreeForAll;
import mage.game.CommanderFreeForAll;
import mage.game.FreeForAllMatch;
import mage.game.GameOptions;
import mage.game.TwoPlayerDuel;
import mage.game.TwoPlayerMatch;
import mage.game.events.PlayerQueryEvent;
import mage.game.match.MatchOptions;
import mage.game.mulligan.LondonMulligan;
import mage.game.permanent.Permanent;
import mage.player.human.HumanPlayer;
import mage.players.Player;
import mage.players.net.UserData;
import mage.server.game.GameSessionPlayer;
import mage.view.CardView;
import mage.view.GameView;
import mage.view.PermanentView;
import mage.view.PlayerView;
import mage.watchers.common.CommanderInfoWatcher;
import mage.util.RandomUtil;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.PrintStream;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;

/** Test-only hot-seat bridge. Every move returns through HumanPlayer callbacks. */
public final class HumanBridge {
    private final Gson gson = new Gson();
    private final PrintStream protocol;
    private final Game game;
    private final HumanPlayer[] players;
    private final JsonObject workload;
    private final int starter;
    private final AtomicLong sequence = new AtomicLong();
    private volatile Map<String, Object> pending;
    private volatile List<Map<String, Object>> choices;
    private volatile boolean inputClosed;
    private volatile boolean cancelled;
    private Thread gameThread;

    private HumanBridge(PrintStream protocol, JsonObject workload) {
        this.protocol = protocol;
        this.workload = workload;
        int count = workload == null ? 2 : workload.getAsJsonArray("players").size();
        if (count != 2 && count != 4) throw new IllegalArgumentException("Laboratory supports exactly two or four players");
        int life = workload == null ? 20 : workload.get("startingLife").getAsInt();
        starter = workload == null ? 0 : workload.get("startingPlayer").getAsInt();
        if (starter < 0 || starter >= count) throw new IllegalArgumentException("Invalid starting player");
        if (workload != null && workload.get("variant").getAsString().equals("Commander")) {
            CommanderFreeForAll commander = new CommanderFreeForAll(MultiplayerAttackOption.MULTIPLE,
                    RangeOfInfluence.ALL, new LondonMulligan(1), life, 7);
            commander.setNumPlayers(count);
            game = commander;
        } else if (count == 4) {
            FreeForAll multiplayer = new FreeForAll(MultiplayerAttackOption.MULTIPLE,
                    RangeOfInfluence.ALL, new LondonMulligan(1), life, 7);
            multiplayer.setNumPlayers(count);
            game = multiplayer;
        } else {
            game = new TwoPlayerDuel(MultiplayerAttackOption.MULTIPLE,
                    RangeOfInfluence.ALL, new LondonMulligan(0), workload == null ? 60 : 40, life, 7);
        }
        players = new HumanPlayer[count];
        for (int i = 0; i < count; i++) {
            String name = workload == null ? "Player " + i : workload.getAsJsonArray("players").get(i).getAsJsonObject().get("name").getAsString();
            players[i] = new HumanPlayer(name, RangeOfInfluence.ALL, 1);
        }
    }

    private static Map<String, Object> object(Object... fields) {
        Map<String, Object> result = new LinkedHashMap<>();
        for (int i = 0; i < fields.length; i += 2) result.put((String) fields[i], fields[i + 1]);
        return result;
    }

    private synchronized void emit(Map<String, Object> value) {
        protocol.println(gson.toJson(value));
        protocol.flush();
    }

    private int seat(UUID id) {
        for (int i = 0; i < players.length; i++) if (players[i].getId().equals(id)) return i;
        return -1;
    }

    private void setup() {
        FreeForAllMatch match = new FreeForAllMatch(new MatchOptions("Hexproof native laboratory", "Test-only human game", true));
        if (workload != null) RandomUtil.setSeed(workload.get("seed").getAsLong());
        for (int index = 0; index < players.length; index++) {
            HumanPlayer player = players[index];
            player.setUserData(UserData.getDefaultUserDataView());
            Deck deck = new Deck();
            if (workload == null) {
                for (int i = 0; i < 30; i++) {
                    deck.getCards().add(new Forest(player.getId(), new CardSetInfo("Forest", "M21", "272", Rarity.LAND)));
                    deck.getCards().add(new GrizzlyBears(player.getId(), new CardSetInfo("Grizzly Bears", "M10", "185", Rarity.COMMON)));
                }
            } else {
                JsonObject seat = workload.getAsJsonArray("players").get(index).getAsJsonObject();
                for (JsonElement entry : seat.getAsJsonArray("cards")) {
                    JsonObject item = entry.getAsJsonObject();
                    int amount = item.get("count").getAsInt();
                    if (amount < 1 || amount > 100) throw new IllegalArgumentException("Invalid card count");
                    for (int n = 0; n < amount; n++) deck.getCards().add(loadCard(item.get("name").getAsString()));
                }
                if (seat.has("commanders")) for (JsonElement name : seat.getAsJsonArray("commanders")) {
                    Card commander = deck.getCards().stream().filter(card -> card.getName().equals(name.getAsString()))
                            .findFirst().orElseThrow(() -> new IllegalArgumentException("Commander must be included in total cards"));
                    deck.getCards().remove(commander);
                    deck.getSideboard().add(commander);
                }
            }
            game.loadCards(deck.getCards(), player.getId());
            game.loadCards(deck.getSideboard(), player.getId());
            game.addPlayer(player, deck);
            match.addPlayer(player, deck);
        }
        game.setStartingPlayerId(players[starter].getId());
        GameOptions options = new GameOptions();
        options.skipInitShuffling = workload == null;
        game.setGameOptions(options);
        DataCollectorServices.init(true, false);
        game.addPlayerQueryEventListener(this::query);
    }

    private Card loadCard(String name) {
        CardInfo entry = CardRepository.instance.findCard(name, true);
        if (entry == null) throw new IllegalArgumentException("Pinned shipped catalog lacks required workload card: " + name);
        Card card = entry.createCard();
        if (card == null) throw new IllegalArgumentException("Pinned implementation cannot instantiate workload card: " + name);
        return card;
    }

    private void action(List<Map<String, Object>> actions, String label, String category, String cardName,
                        String responseType, Object response) {
        actions.add(object("id", Integer.toString(actions.size()), "label", label, "category", category,
                "cardId", responseType.equals("uuid") ? response : "",
                "cardName", cardName, "response", object(responseType, response)));
    }

    private void query(PlayerQueryEvent event) {
        if (event.getQueryType() == PlayerQueryEvent.QueryType.PERSONAL_MESSAGE) return;
        int actor = seat(event.getPlayerId());
        Player player = game.getPlayer(event.getPlayerId());
        String message = event.getMessage() == null ? "" : event.getMessage();
        List<Map<String, Object>> actions = new ArrayList<>();
        switch (event.getQueryType()) {
            case ASK:
                boolean mulligan = message.toLowerCase().contains("mulligan");
                action(actions, mulligan ? "Keep seven" : "Yes", mulligan ? "keep" : "confirm", "",
                        "boolean", !mulligan);
                action(actions, mulligan ? "Mulligan" : "No", "other", "", "boolean", mulligan);
                break;
            case SELECT:
                if (message.equals("Select attackers")) {
                    boolean selected = !game.getCombat().getAttackers().isEmpty();
                    boolean canAttack = game.getBattlefield().getAllActivePermanents(player.getId()).stream()
                            .anyMatch(permanent -> permanent.canAttack(null, game));
                    if (!selected && canAttack) action(actions, "Attack with all", "attack_all", "", "string", "special");
                    for (Permanent permanent : game.getBattlefield().getAllActivePermanents(player.getId())) {
                        if (permanent.canAttack(null, game)) action(actions, "Attack: " + permanent.getName(), "other",
                                permanent.getName(), "uuid", permanent.getId().toString());
                    }
                    action(actions, selected ? "Confirm attackers" : "No attackers", selected ? "confirm" : "pass", "", "boolean", true);
                } else if (message.equals("Select blockers")) {
                    for (Permanent permanent : game.getBattlefield().getAllActivePermanents(player.getId())) {
                        if (permanent.isCreature(game) && !permanent.isTapped()) action(actions,
                                "Block: " + permanent.getName(), "other", permanent.getName(), "uuid", permanent.getId().toString());
                    }
                    action(actions, "Confirm blockers / no blocks", "block_none", "", "boolean", true);
                } else {
                    for (ActivatedAbility ability : player.getPlayable(game, true)) {
                        MageObject source = game.getObject(ability.getSourceId());
                        String name = source == null ? "" : source.getName();
                        String category = ability instanceof PlayLandAbility ? "land"
                                : ability instanceof SpellAbility ? "cast" : ability.isManaAbility() ? "mana" : "other";
                        action(actions, category + ": " + name + " — " + ability.getRule(), category, name,
                                "uuid", ability.getSourceId().toString());
                    }
                    action(actions, "Pass priority", "pass", "", "boolean", true);
                }
                break;
            case PLAY_MANA:
            case PLAY_X_MANA:
                for (ManaType type : ManaType.values()) {
                    if (type != ManaType.GENERIC && player.getManaPool().get(type) > 0) {
                        action(actions, "Spend " + type + " from mana pool", "mana", "", "manaType", type.name());
                    }
                }
                for (ActivatedAbility ability : player.getPlayable(game, true)) {
                    if (ability.isManaAbility()) {
                        MageObject source = game.getObject(ability.getSourceId());
                        String name = source == null ? "" : source.getName();
                        action(actions, "Mana: " + name, "mana", name, "uuid", ability.getSourceId().toString());
                    }
                }
                action(actions, "Cancel payment", "other", "", "boolean", true);
                break;
            case PICK_TARGET:
                if (event.getTargets() != null) for (UUID id : event.getTargets()) target(actions, id);
                if (event.getCards() != null) for (UUID id : event.getCards()) target(actions, id);
                if (event.getPerms() != null) for (Permanent permanent : event.getPerms()) target(actions, permanent.getId());
                if (!event.isRequired()) action(actions, "Done", "confirm", "", "boolean", true);
                break;
            case CHOOSE_ABILITY:
            case PICK_ABILITY:
                if (event.getAbilities() != null) for (Ability ability : event.getAbilities())
                    action(actions, ability.getRule(), "confirm", "", "uuid", ability.getId().toString());
                break;
            case CHOOSE_MODE:
                event.getModes().forEach((id, label) -> action(actions, label, "other", "", "uuid", id.toString()));
                break;
            case CHOOSE_CHOICE:
                if (event.getChoice().isKeyChoice()) event.getChoice().getKeyChoices().forEach((key, label) ->
                        action(actions, label, "other", "", "string", key));
                else for (String choice : event.getChoice().getChoices()) action(actions, choice, "other", "", "string", choice);
                message = event.getChoice().getMessage();
                break;
            case AMOUNT:
                for (int n = event.getMin(); n <= Math.min(event.getMax(), event.getMin() + 20); n++)
                    action(actions, Integer.toString(n), "other", "", "integer", n);
                break;
            default:
                break;
        }
        choices = actions;
        Map<String, Object> packet = object("type", "decision", "engine", "XMage", "id", sequence.incrementAndGet(), "actor", actor,
                "kind", event.getQueryType().name(), "message", message, "actions", actions, "views", views(),
                "turn", game.getTurnNum(), "step", String.valueOf(game.getTurnStepType()));
        pending = packet;
        emit(packet);
    }

    private void target(List<Map<String, Object>> actions, UUID id) {
        MageObject target = game.getObject(id);
        Player player = game.getPlayer(id);
        String name = target != null ? target.getName() : player != null ? player.getName() : id.toString();
        action(actions, "Choose: " + name, "other", name, "uuid", id.toString());
    }

    private Map<String, Object> card(CardView card) {
        return object("id", card.getId().toString(), "name", card.getName(), "power", card.getPower(),
                "toughness", card.getToughness(), "tapped", card instanceof PermanentView && ((PermanentView) card).isTapped());
    }

    private List<Map<String, Object>> views() {
        List<Map<String, Object>> result = new ArrayList<>();
        for (int viewer = -1; viewer < players.length; viewer++) {
            UUID playerId = viewer < 0 ? null : players[viewer].getId();
            GameView raw = GameSessionPlayer.prepareGameView(game, playerId, viewer < 0 ? UUID.randomUUID() : playerId);
            List<Map<String, Object>> seats = new ArrayList<>();
            List<Map<String, Object>> zones = new ArrayList<>();
            for (HumanPlayer player : players) {
                Map<String, Integer> commanderDamage = new LinkedHashMap<>();
                for (HumanPlayer source : players) for (UUID id : game.getCommandersIds(source, CommanderCardType.ANY, false)) {
                    CommanderInfoWatcher watcher = game.getState().getWatcher(CommanderInfoWatcher.class, id);
                    if (watcher != null) commanderDamage.put(id.toString(), watcher.getDamageToPlayer().getOrDefault(player.getId(), 0));
                }
                seats.add(object("id", seat(player.getId()), "name", player.getName(), "life", player.getLife(),
                        "handCount", player.getHand().size(), "libraryCount", player.getLibrary().size(),
                        "hasLost", player.hasLost(), "hasWon", player.hasWon(), "hasLeft", player.hasLeft(),
                        "commanderDamage", commanderDamage));
            }
            for (PlayerView player : raw.getPlayers()) {
                int owner = seat(player.getPlayerId());
                List<Map<String, Object>> battlefield = new ArrayList<>();
                player.getBattlefield().values().forEach(value -> battlefield.add(card(value)));
                zones.add(object("owner", owner, "zone", "battlefield", "cards", battlefield));
                List<Map<String, Object>> graveyard = new ArrayList<>();
                player.getGraveyard().values().forEach(value -> graveyard.add(card(value)));
                zones.add(object("owner", owner, "zone", "graveyard", "cards", graveyard));
                List<Map<String, Object>> exile = new ArrayList<>();
                player.getExile().values().forEach(value -> exile.add(card(value)));
                zones.add(object("owner", owner, "zone", "exile", "cards", exile));
                List<Map<String, Object>> command = new ArrayList<>();
                player.getCommandObjectList().forEach(value -> command.add(object("id", value.getId().toString(), "name", value.getName())));
                zones.add(object("owner", owner, "zone", "command", "cards", command));
            }
            List<Map<String, Object>> hand = new ArrayList<>();
            raw.getMyHand().values().forEach(value -> hand.add(card(value)));
            zones.add(object("owner", viewer, "zone", "hand", "cards", hand));
            List<Map<String, Object>> stack = new ArrayList<>();
            raw.getStack().values().forEach(value -> {
                Map<String, Object> item = card(value);
                game.getStack().stream().filter(object -> object.getId().equals(value.getId())).findFirst()
                        .ifPresent(object -> item.put("cardId", object.getSourceId().toString()));
                stack.add(item);
            });
            result.add(object("viewer", viewer, "players", seats, "zones", zones, "stack", stack));
        }
        // Keep player zero first for compatibility with the existing common laboratory.
        result.add(result.remove(0));
        return result;
    }

    private void input() {
        try (BufferedReader input = new BufferedReader(new InputStreamReader(System.in, "UTF-8"))) {
            String line;
            while ((line = input.readLine()) != null) {
                try {
                    JsonObject request = new JsonParser().parse(line).getAsJsonObject();
                    String type = request.get("type").getAsString();
                    if (type.equals("test_snapshot")) {
                        if (pending == null) throw new IllegalArgumentException("Snapshot is only supported at a pending decision");
                        int viewer = request.get("viewer").getAsInt();
                        if (viewer < -1 || viewer >= players.length) throw new IllegalArgumentException("Invalid viewer");
                        Map<String, Object> view = views().stream().filter(item -> (int) item.get("viewer") == viewer).findFirst().get();
                        emit(object("type", "test_snapshot", "engine", "XMage", "requestId", request.get("requestId"), "view", view));
                        continue;
                    }
                    if (type.equals("test_cancel")) {
                        cancelled = true;
                        emit(object("type", "test_cancelled", "engine", "XMage", "requestId", request.get("requestId")));
                        gameThread.interrupt();
                        break;
                    }
                    if (!type.equals("respond") && !type.equals("test_reissue"))
                        throw new IllegalArgumentException("Unknown laboratory request type");
                    Map<String, Object> decision = pending;
                    if (decision == null || request.get("id").getAsLong() != ((Number) decision.get("id")).longValue()
                            || request.get("actor").getAsInt() != (int) decision.get("actor")) {
                        throw new IllegalArgumentException("Stale decision or wrong actor");
                    }
                    if (type.equals("test_reissue")) {
                        emit(object("type", "test_reissued", "engine", "XMage", "decision", decision));
                        continue;
                    }
                    JsonObject response = request.getAsJsonObject("response");
                    if (choices.stream().noneMatch(choice -> gson.toJsonTree(choice.get("response")).equals(response)))
                        throw new IllegalArgumentException("Response is not an offered choice");
                    pending = null;
                    Player player = players[(int) decision.get("actor")];
                    if (response.has("uuid")) player.setResponseUUID(UUID.fromString(response.get("uuid").getAsString()));
                    else if (response.has("boolean")) player.setResponseBoolean(response.get("boolean").getAsBoolean());
                    else if (response.has("integer")) player.setResponseInteger(response.get("integer").getAsInt());
                    else if (response.has("string")) player.setResponseString(response.get("string").getAsString());
                    else if (response.has("manaType")) player.setResponseManaType(player.getId(), ManaType.valueOf(response.get("manaType").getAsString()));
                } catch (Exception error) {
                    emit(object("type", "error", "message", error.toString()));
                }
            }
        } catch (Exception error) {
            emit(object("type", "error", "message", error.toString()));
        } finally {
            inputClosed = true;
            for (HumanPlayer player : players) player.abort();
        }
    }

    private void run() {
        setup();
        emit(object("type", "ready", "candidate", "XMage", "engine", "XMage",
                "workload", workload == null ? "interactive_bears_v1" : workload.get("id").getAsString(),
                "deck", workload == null ? "30 Forest / 30 Grizzly Bears; alternating insertion order; initial shuffle disabled" : "Frozen manifest; native engine shuffle with recorded seed",
                "scope", "Test-only local hot-seat controller receives separate already-redacted viewer projections"));
        gameThread = Thread.currentThread();
        Thread reader = new Thread(this::input, "CALL native laboratory input");
        reader.setDaemon(true);
        reader.start();
        Thread.currentThread().setName("GAME native laboratory");
        try {
            game.start(players[starter].getId());
            int winner = -1;
            for (int i = 0; i < players.length; i++) if (players[i].hasWon()) winner = i;
            List<Map<String, Object>> finalViews = views();
            emit(object("type", "result", "engine", "XMage", "gameOver", game.hasEnded(), "winner", winner,
                    "winnerName", game.getWinner(), "turn", game.getTurnNum(), "decisions", sequence.get(),
                    "cancelled", cancelled, "naturalCompletion", !inputClosed && !cancelled && winner >= 0,
                    "views", finalViews, "view", finalViews.get(0)));
        } finally {
            for (HumanPlayer player : players) player.abort();
        }
    }

    public static void main(String[] args) throws Exception {
        PrintStream protocol = System.out;
        System.setOut(System.err);
        JsonObject workload = null;
        if (args.length != 0) {
            if (args.length != 2) throw new IllegalArgumentException("Expected workload file and workload ID");
            JsonObject document = new JsonParser().parse(new String(Files.readAllBytes(Paths.get(args[0])), StandardCharsets.UTF_8)).getAsJsonObject();
            for (JsonElement value : document.getAsJsonArray("workloads")) {
                if (value.getAsJsonObject().get("id").getAsString().equals(args[1])) workload = value.getAsJsonObject();
            }
            if (workload == null) throw new IllegalArgumentException("Unknown workload ID: " + args[1]);
        }
        new HumanBridge(protocol, workload).run();
    }
}
