// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import forge.harness.host.ManaBrewEngineAdapter;
import forge.harness.host.InteractiveSnapshotExtractor;
import forge.harness.host.ManaBrewInteractiveSession;
import forge.game.Game;
import forge.game.GameRules;
import forge.game.GameType;
import forge.game.Match;
import forge.game.card.Card;
import forge.game.card.CardFactory;
import forge.game.player.RegisteredPlayer;
import forge.game.spellability.SpellAbility;
import forge.game.spellability.Spell;
import forge.game.spellability.SpellAbilityStackInstance;
import forge.ai.LobbyPlayerAi;
import forge.deck.Deck;
import forge.model.FModel;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Deque;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.BooleanSupplier;

/** Real-engine regressions for Hexproof's downstream interactive-host patch. */
public final class HexproofSessionRegressionTest {
    private static final ManaBrewEngineAdapter ADAPTER = new ManaBrewEngineAdapter();

    public static void main(String[] args) throws Exception {
        if (args.length != 1) {
            throw new IllegalArgumentException("expected the complete Forge assets directory");
        }
        ADAPTER.initialize(args[0]);
        startingLifeAndPrivacy();
        fixedStartingPlayers();
        faceDownStackProjection();
        for (int iteration = 0; iteration < 3; iteration++) {
            concurrentConcessions("concessions-" + iteration);
        }
        abortWaitingGame();
        failedGame();
        System.out.println("Hexproof session regressions passed: life, privacy, stable snapshots, "
                + "fixed starting players, face-down stack, concurrent concessions, terminal state, abort, failure propagation");
    }

    private static void fixedStartingPlayers() throws Exception {
        for (int playerCount : List.of(2, 4)) {
            for (int first : List.of(0, playerCount - 1)) {
                String id = "fixed-first-" + playerCount + "-" + first;
                start(id, playerCount, 20, first);
                try {
                    await(() -> !ADAPTER.getPrompt(id, 0).isEmpty(), "fixed-start opening prompt missing");
                    JsonObject opening = object(ADAPTER.getPrompt(id, 0));
                    check(!opening.getAsJsonObject("input").get("type").getAsString().equals("diceRolled"),
                            "fixed starting player was replaced with a new die roll");
                    reachPriority(id);
                    for (int viewer = -1; viewer < playerCount; viewer++) {
                        JsonObject view = object(ADAPTER.getSnapshot(id, viewer));
                        check(view.get("startingPlayerId").getAsString().equals("player-" + first),
                                "host-requested starting player was ignored");
                        check(view.get("activePlayerId").getAsString().equals("player-" + first),
                                "the wrong player received the first turn");
                        checkPrivacy(view, viewer);
                    }
                } finally {
                    ADAPTER.endGame(id);
                }
            }
        }
    }

    @SuppressWarnings("unchecked")
    private static void faceDownStackProjection() throws Exception {
        // An isolated actual Forge card/game (no running game thread) lets this
        // check both the in-progress casting record and the committed stack
        // record, including a deliberately identity-bearing original ability.
        List<RegisteredPlayer> players = List.of(
                new RegisteredPlayer(new Deck()).setPlayer(new LobbyPlayerAi("A", null)),
                new RegisteredPlayer(new Deck()).setPlayer(new LobbyPlayerAi("B", null)));
        Game game = new Match(new GameRules(GameType.Constructed), players, "Synthetic morph").createGame();
        Card card = CardFactory.getCard(FModel.getMagicDb().getCommonCards().getCard("Willbender"),
                game.getPlayers().get(0), game);
        SpellAbility spell = card.getSpellAbilities().get(0);
        spell.setActivatingPlayer(game.getPlayers().get(0));
        var labelMethod = ManaBrewInteractiveSession.class.getDeclaredMethod(
                "priorityActionLabel", SpellAbility.class, String.class);
        labelMethod.setAccessible(true);
        check("Cast Willbender".equals(labelMethod.invoke(null, spell, "Cast Willbender")),
                "ordinary cast label changed");
        ((Spell) spell).setCastFaceDown(true);
        check("Cast Willbender (Face down)".equals(labelMethod.invoke(null, spell, "Cast Willbender")),
                "Morph is indistinguishable from the normal cast mode");
        card.turnFaceDown(true);
        var castingMethod = InteractiveSnapshotExtractor.class.getDeclaredMethod(
                "castingStackEntry", Game.class, SpellAbility.class, String.class);
        castingMethod.setAccessible(true);
        checkHiddenStack((Map<String, Object>) castingMethod.invoke(null, game, spell, "player-0"));
        var stackField = game.getStack().getClass().getDeclaredField("stack");
        stackField.setAccessible(true);
        ((Deque<SpellAbilityStackInstance>) stackField.get(game.getStack())).addFirst(new SpellAbilityStackInstance(spell));
        var stackMethod = InteractiveSnapshotExtractor.class.getDeclaredMethod(
                "snapshotStack", Game.class, SpellAbility.class, String.class);
        stackMethod.setAccessible(true);
        List<Map<String, Object>> hidden = (List<Map<String, Object>>) stackMethod.invoke(null, game, null, "player-0");
        check(hidden.size() == 1, "face-down spell missing from actual stack");
        checkHiddenStack(hidden.get(0));
        card.turnFaceUp(false, null);
        List<Map<String, Object>> visible = (List<Map<String, Object>>) stackMethod.invoke(null, game, null, "player-0");
        Map<String, Object> identity = (Map<String, Object>) visible.get(0).get("identity");
        check("Willbender".equals(identity.get("name")) && !"".equals(identity.get("setCode")),
                "face-up public spell lost its real identity");
    }

    @SuppressWarnings("unchecked")
    private static void checkHiddenStack(Map<String, Object> item) {
        Map<String, Object> identity = (Map<String, Object>) item.get("identity");
        check("".equals(identity.get("name")) && "".equals(identity.get("setCode"))
                && "".equals(identity.get("cardNumber")) && Boolean.FALSE.equals(identity.get("isToken"))
                && !identity.containsKey("tokenScript"), "face-down stack leaked a printing");
        check("Face-down spell".equals(item.get("text")) && !item.containsKey("sourceAbilityText")
                && Boolean.FALSE.equals(item.get("isDoubleFaced")) && Integer.valueOf(0).equals(item.get("faceIndex")),
                "face-down stack leaked ability/face metadata");
    }

    private static void startingLifeAndPrivacy() throws Exception {
        String id = "duel-life";
        start(id, 2, 20);
        try {
            reachPriority(id);
            for (int viewer = -1; viewer < 2; viewer++) {
                String snapshot = ADAPTER.getSnapshot(id, viewer);
                JsonObject view = object(snapshot);
                for (JsonElement player : view.getAsJsonArray("players")) {
                    check(player.getAsJsonObject().get("life").getAsInt() == 20,
                            "Commander variant ignored the host's starting life");
                }
                checkPrivacy(view, viewer);
                for (int read = 0; read < 1000; read++) {
                    check(snapshot == ADAPTER.getSnapshot(id, viewer),
                            "RPC rebuilt a snapshot while the game was idle");
                }
            }
            expectFailure(() -> ADAPTER.getSnapshot(id, 2), "invalid snapshot viewer");
        } finally {
            ADAPTER.endGame(id);
        }
    }

    private static void concurrentConcessions(String id) throws Exception {
        start(id, 4, 40);
        AtomicBoolean stop = new AtomicBoolean();
        AtomicReference<Throwable> readerFailure = new AtomicReference<>();
        Thread reader = new Thread(() -> {
            try {
                while (!stop.get()) {
                    for (int viewer = -1; viewer < 4; viewer++) {
                        checkPrivacy(object(ADAPTER.getSnapshot(id, viewer)), viewer);
                        ADAPTER.getGameOver(id);
                        ADAPTER.getPrompt(id, viewer);
                    }
                }
            } catch (Throwable error) {
                readerFailure.set(error);
            }
        }, "hexproof-snapshot-regression");
        try {
            JsonObject prompt = reachPriority(id);
            int decider = Integer.parseInt(prompt.get("decidingPlayerId").getAsString()
                    .substring("player-".length()));
            long promptId = prompt.get("promptId").getAsLong();
            reader.start();
            int remaining = 4;
            for (int player = 0; player < 4; player++) {
                if (player == decider) {
                    continue;
                }
                final int conceding = player;
                ADAPTER.submitAction(id, "{\"kind\":\"concede\",\"player\":" + player + "}");
                remaining--;
                final boolean terminal = remaining == 1;
                await(() -> {
                    JsonObject view = object(ADAPTER.getSnapshot(id, -1));
                    if (terminal) {
                        return view.get("gameOver").getAsBoolean();
                    }
                    return !"playing".equals(view.getAsJsonArray("players").get(conceding)
                            .getAsJsonObject().get("status").getAsString());
                }, "concession was not published at the next stable boundary");
                JsonObject view = object(ADAPTER.getSnapshot(id, -1));
                check(view.get("gameOver").getAsBoolean() == terminal,
                        "concession published the wrong terminal state");
                if (!terminal) {
                    check(object(ADAPTER.getPrompt(id, decider)).get("promptId").getAsLong()
                            == promptId, "unrelated concession consumed the deciding player's prompt");
                } else {
                    check(view.get("winnerId").getAsString().equals("player-" + decider),
                            "wrong final concession winner");
                    check(ADAPTER.getPrompt(id, decider).isEmpty(), "terminal prompt was retained");
                    check("true".equals(ADAPTER.getGameOver(id)), "terminal API disagrees");
                }
            }
        } finally {
            stop.set(true);
            reader.join(5000);
            ADAPTER.endGame(id);
        }
        check(!reader.isAlive(), "snapshot reader did not stop");
        if (readerFailure.get() != null) {
            throw new AssertionError("concurrent snapshot reader failed", readerFailure.get());
        }
    }

    private static void abortWaitingGame() throws Exception {
        String id = "abort-waiting";
        start(id, 2, 20);
        await(() -> !ADAPTER.getPrompt(id, 0).isEmpty(), "initial prompt missing");
        ADAPTER.endGame(id);
        await(() -> Thread.getAllStackTraces().keySet().stream().noneMatch(thread ->
                thread.isAlive() && thread.getName().equals("mana-brew-forge-" + id)),
                "aborted game thread remained alive");
    }

    private static void failedGame() throws Exception {
        String id = "intentional-failure";
        start(id, 2, 20);
        try {
            await(() -> !ADAPTER.getPrompt(id, 0).isEmpty(), "initial prompt missing");
            System.err.println("[hexproof-test] Injecting an expected unsupported action failure");
            ADAPTER.submitAction(id, "{\"kind\":\"hexproof_intentional_invalid_action\"}");
            await(() -> {
                try {
                    ADAPTER.getPrompt(id, 0);
                    return false;
                } catch (IllegalStateException error) {
                    return "interactive game failed".equals(error.getMessage());
                }
            }, "dead game thread retained its old prompt");
            expectFailure(() -> ADAPTER.getSnapshot(id, -1), "interactive game failed");
            expectFailure(() -> ADAPTER.getGameOver(id), "interactive game failed");
            expectFailure(() -> ADAPTER.submitAction(id, "{\"kind\":\"pass\"}"),
                    "interactive game failed");
        } finally {
            ADAPTER.endGame(id);
        }
    }

    private static void start(String id, int playerCount, int life) {
        start(id, playerCount, life, null);
    }

    private static void start(String id, int playerCount, int life, Integer startingPlayer) {
        List<ManaBrewEngineAdapter.CardIdentity> deck = new ArrayList<>();
        for (int i = 0; i < 99; i++) {
            deck.add(new ManaBrewEngineAdapter.CardIdentity("Plains", null, null, false));
        }
        deck.add(new ManaBrewEngineAdapter.CardIdentity("Isamaru, Hound of Konda", null, null, false));
        List<ManaBrewEngineAdapter.PlayerConfig> players = new ArrayList<>();
        for (int player = 0; player < playerCount; player++) {
            players.add(new ManaBrewEngineAdapter.PlayerConfig("Player " + player, deck,
                    List.of("Isamaru, Hound of Konda"), false));
        }
        ADAPTER.startGame(new ManaBrewEngineAdapter.StartGameRequest(id, "Commander", life,
                42L, players, startingPlayer));
    }

    private static JsonObject reachPriority(String id) throws Exception {
        long previous = -1;
        for (int step = 0; step < 30; step++) {
            final long last = previous;
            await(() -> {
                String raw = ADAPTER.getPrompt(id, 0);
                return !raw.isEmpty() && object(raw).get("promptId").getAsLong() != last;
            }, "next prompt missing");
            JsonObject prompt = object(ADAPTER.getPrompt(id, 0));
            previous = prompt.get("promptId").getAsLong();
            String kind = prompt.getAsJsonObject("input").get("type").getAsString();
            if (kind.equals("chooseAction")) {
                return prompt;
            }
            check(kind.equals("diceRolled") || kind.equals("mulligan") || kind.equals("revealCards"),
                    "unexpected opening prompt: " + prompt);
            ADAPTER.submitAction(id, "{\"kind\":\"pass\"}");
        }
        throw new AssertionError("did not reach priority");
    }

    private static void checkPrivacy(JsonObject view, int viewer) {
        for (JsonElement element : view.getAsJsonArray("zones")) {
            JsonObject zone = element.getAsJsonObject();
            boolean privateZone = zone.get("zone").getAsString().equals("library")
                    || zone.get("zone").getAsString().equals("hand")
                    && !zone.get("ownerId").getAsString().equals("player-" + viewer);
            if (privateZone) {
                for (JsonElement card : zone.getAsJsonArray("cards")) {
                    check(!card.getAsJsonObject().has("identity"), "hidden card identity leaked");
                }
            }
        }
    }

    private static void await(BooleanSupplier condition, String message) throws Exception {
        long deadline = System.nanoTime() + 10_000_000_000L;
        while (!condition.getAsBoolean()) {
            check(System.nanoTime() < deadline, message);
            Thread.sleep(2);
        }
    }

    private static void expectFailure(Runnable action, String message) {
        try {
            action.run();
        } catch (IllegalArgumentException | IllegalStateException expected) {
            check(expected.getMessage().contains(message), "unexpected failure: " + expected);
            return;
        }
        throw new AssertionError("expected failure: " + message);
    }

    private static JsonObject object(String json) {
        return JsonParser.parseString(json).getAsJsonObject();
    }

    private static void check(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }
}
