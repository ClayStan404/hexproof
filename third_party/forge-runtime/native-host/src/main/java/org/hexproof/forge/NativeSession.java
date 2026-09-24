// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.LobbyPlayer;
import forge.card.CardDb;
import forge.deck.*;
import forge.game.*;
import forge.game.card.Card;
import forge.game.player.*;
import forge.game.player.PlayerController.PlayerDecisionCancelled;
import forge.game.spellability.SpellAbility;
import forge.game.zone.ZoneType;
import forge.item.PaperCard;
import forge.model.FModel;
import forge.player.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Function;
import java.util.function.Supplier;

/** Owns the game, stable prompt snapshots, and one outstanding player decision. */
final class NativeSession implements AutoCloseable {
    final String id;
    final Game game;
    final Match match;
    final NativeGuiBase base;
    final NativeExecution context;
    final NativeReplay replay;
    final List<NativeGuiGame> guis = new java.util.concurrent.CopyOnWriteArrayList<>();
    private final Map<Integer, String> snapshots = new HashMap<>();
    private final Set<SynchronousAnswer<?>> answers = new HashSet<>();
    private final ThreadLocal<SpellAbility> decisionAbility = new ThreadLocal<>();
    private long serial;
    private Pending pending;
    private Throwable failure;
    private boolean closed;
    private boolean finished;
    private boolean terminalConcession;
    private boolean nativeActionQueued;
    private record Pending(long id, JsonObject envelope, Function<JsonObject, Runnable> prepare,
                           boolean onEdt, SynchronousAnswer<?> answer) { }
    private static final class SynchronousAnswer<T> {
        final SpellAbility ability;
        SynchronousAnswer(SpellAbility ability) { this.ability = ability; }
        final CompletableFuture<T> result = new CompletableFuture<>();
        final BlockingQueue<Runnable> controls = new LinkedBlockingQueue<>();
        void complete(T value) { result.complete(value); wake(); }
        void cancel(Throwable error) { result.completeExceptionally(error); wake(); }
        void wake() { controls.offer(() -> { }); }
        T await() {
            // A native menu can run on either the game thread or the GUI input
            // dispatcher. Execute concession on that same stopped thread;
            // queueing it behind a GUI thread blocked in join would deadlock.
            while (!result.isDone()) {
                try { controls.take().run(); }
                catch (InterruptedException error) {
                    Thread.currentThread().interrupt();
                    throw new CancellationException("Native synchronous decision interrupted");
                }
            }
            return result.join();
        }
    }
    private static final class TerminalDecisionCancelled extends CancellationException {
        TerminalDecisionCancelled() { super("Native game ended while a synchronous decision was pending"); }
    }

    NativeSession(JsonObject request, NativeGuiBase base) {
        this.base = base;
        id = request.get("gameId").getAsString();
        context = new NativeExecution(request.get("seed").getAsLong(), this::fail);
        try (var scope = context.enter()) {
            JsonArray configured = request.getAsJsonArray("players");
            if (id.isBlank() || configured.size() < 2 || configured.size() > 8) throw new IllegalArgumentException("Invalid game setup");
            GameType type = switch (text(request, "variant", "constructed").toLowerCase(Locale.ROOT)) {
                case "constructed", "modern", "standard", "legacy", "vintage", "pioneer", "pauper" -> GameType.Constructed;
                case "limited", "sealed" -> GameType.Sealed;
                case "draft", "cube" -> GameType.Draft;
                case "commander", "duelcommander", "duel_commander", "duel-commander" -> GameType.Commander;
                default -> throw new IllegalArgumentException("Unsupported game variant");
            };
            long aiCount = configured.asList().stream().filter(e -> isAi(e.getAsJsonObject())).count();
            if (aiCount > 0 && (configured.size() != 2 || aiCount != 1 || type != GameType.Constructed))
                throw new IllegalArgumentException("AI requires one human and one AI in Constructed");
            List<RegisteredPlayer> registered = new ArrayList<>();
            Integer starts = request.has("startingPlayerIndex") ? request.get("startingPlayerIndex").getAsInt() : null;
            if (starts != null && (starts < 0 || starts >= configured.size())) throw new IllegalArgumentException("Invalid starting seat");
            List<Deck> decks = resolveDecks(configured);
            for (int playerIndex = 0; playerIndex < configured.size(); playerIndex++) {
                JsonObject player = configured.get(playerIndex).getAsJsonObject();
                Deck deck = decks.get(playerIndex);
                LobbyPlayer lobby = isAi(player)
                        ? new NativeAiLobby(player.get("name").getAsString(), text(player, "aiDifficulty", ""), starts)
                        : new LobbyPlayerHuman(player.get("name").getAsString()) {
                    @Override public Player createIngamePlayer(Game game, int playerId) {
                        Player result = new Player(getName(), game, playerId);
                        result.setFirstController(new NativeDecisionController(NativeSession.this, game, result, this, starts));
                        return result;
                    }
                    @Override public PlayerController createMindSlaveController(Player master, Player slave) {
                        // The desktop shares one GUI/input queue with the master.
                        // Remote inputs need the acting player's own controller;
                        // publish maps its decisions to the controlling seat.
                        var controller = new NativeDecisionController(NativeSession.this, slave.getGame(), slave, this, null);
                        NativeGuiGame gui = new NativeGuiGame(NativeSession.this, controller);
                        controller.setGui(gui.proxy());
                        guis.add(gui);
                        return controller;
                    }
                };
                RegisteredPlayer seat = RegisteredPlayer.forVariants(configured.size(), EnumSet.of(type), deck, null, false, null, null).setPlayer(lobby);
                seat.assignConspiracies();
                seat.setStartingLife(request.get("startingLife").getAsInt());
                registered.add(seat);
            }
            GameRules rules = new GameRules(type);
            rules.setAppliedVariants(EnumSet.of(type));
            match = new Match(rules, registered, "Hexproof native Forge");
            game = match.createGame();
            replay = new NativeReplay(game, id);
            for (Player p : game.getRegisteredPlayers()) {
                if (p.getController() instanceof PlayerControllerHuman human) {
                    NativeGuiGame gui = new NativeGuiGame(this, human);
                    human.setGui(gui.proxy());
                    guis.add(gui);
                }
            }
        } catch (RuntimeException | Error error) { context.close(); throw error; }
    }
    static boolean isAi(JsonObject player) {
        return player.has("ai") && player.get("ai").getAsBoolean();
    }
    private static List<Deck> resolveDecks(JsonArray configured) {
        List<Deck> decks = new ArrayList<>();
        NativeDeckException.Builder failures = new NativeDeckException.Builder();
        for (int playerIndex = 0; playerIndex < configured.size(); playerIndex++) {
            JsonObject player = configured.get(playerIndex).getAsJsonObject();
            Deck deck = new Deck(player.get("name").getAsString());
            JsonArray cards = player.getAsJsonArray("deck");
            JsonArray sideboard = player.has("sideboard") ? player.getAsJsonArray("sideboard") : new JsonArray();
            for (var section : List.of(DeckSection.Main, DeckSection.Sideboard)) {
                boolean main = section == DeckSection.Main;
                String sectionName = main ? "mainboard" : "sideboard";
                JsonArray submitted = main ? cards : sideboard;
                if ((main && submitted.isEmpty()) || submitted.size() > 1000) {
                    failures.add(playerIndex, sectionName, -1, main ? NativeDeckException.Code.INVALID_DECK_SIZE
                            : NativeDeckException.Code.INVALID_SIDEBOARD_SIZE);
                    continue;
                }
                for (int cardIndex = 0; cardIndex < submitted.size(); cardIndex++) {
                    JsonObject ci = submitted.get(cardIndex).getAsJsonObject();
                    String name = ci.get("name").getAsString();
                    String set = text(ci, "setCode", "");
                    String number = text(ci, "collectorNumber", "");
                    PaperCard card = findCard(FModel.getMagicDb().getCommonCards(), name, set, number);
                    if (card == null) {
                        PaperCard variant = findCard(FModel.getMagicDb().getVariantCards(), name, set, number);
                        if (variant != null && variant.getRules().getType().isConspiracy()) card = variant;
                    }
                    if (card == null) {
                        failures.add(playerIndex, sectionName, cardIndex,
                                NativeDeckException.Code.PRINTING_UNAVAILABLE, name, set, number);
                        continue;
                    }
                    deck.getOrCreate(main && card.getRules().getType().isConspiracy()
                            ? DeckSection.Conspiracy : section).add(card, 1);
                }
            }
            if (player.has("commanderNames")) {
                JsonArray commanders = player.getAsJsonArray("commanderNames");
                for (int cardIndex = 0; cardIndex < commanders.size(); cardIndex++) {
                    String name = commanders.get(cardIndex).getAsString();
                    PaperCard card = deck.getMain().toFlatList().stream()
                            .filter(c -> matchesCardName(c, name)).findFirst().orElse(null);
                    if (card == null) {
                        failures.add(playerIndex, "commanders", cardIndex,
                                NativeDeckException.Code.COMMANDER_MISSING, name);
                        continue;
                    }
                    deck.getMain().remove(card, 1);
                    deck.getOrCreate(DeckSection.Commander).add(card, 1);
                }
            }
            decks.add(deck);
        }
        failures.rejectIfPresent();
        return decks;
    }
    static PaperCard findCard(CardDb database, String name, String set, String number) {
        PaperCard card = lookupCard(database, name, set, number);
        if (card != null) return card;
        // Catalogs join both faces for modal, transforming and Adventure cards;
        // Forge indexes those by the front. Split cards already match in full.
        int separator = name.indexOf(" // ");
        if (separator < 0) return null;
        card = lookupCard(database, name.substring(0, separator).trim(), set, number);
        return card != null && matchesCardName(card, name) ? card : null;
    }
    private static PaperCard lookupCard(CardDb database, String name, String set, String number) {
        PaperCard exact = findExactCard(database, name, set, number);
        if (exact != null || set.isEmpty() || number.isEmpty()) return exact;
        PaperCard alias = findLegacyPrinting(database, name, set, number);
        if (alias != null) return alias;
        return NativePrintingAliases.find(database, name, set, number);
    }
    // Also used by the offline index generator: this path must never consult
    // aliases or accept CardDb's unrelated-printing fallback.
    static PaperCard findExactCard(CardDb database, String name, String set, String number) {
        PaperCard card = set.isEmpty() ? database.getCard(name)
                : number.isEmpty() ? database.getCard(name, set) : database.getCard(name, set, number);
        if (card == null && name.contains(" // ")) {
            card = findExactCard(database, name.substring(0, name.indexOf(" // ")).trim(), set, number);
            if (card != null && !matchesCardName(card, name)) return null;
        }
        if (set.isEmpty() || number.isEmpty()) return card;
        // CardDb falls back to another printing when an explicit lookup fails.
        // Full identities must retain their coordinates; edition aliases still
        // resolve through Forge's own registry rather than literal code matching.
        var editions = FModel.getMagicDb().getEditions();
        var requested = editions.get(set.toUpperCase(Locale.ROOT));
        var actual = card == null ? null : editions.get(card.getEdition().toUpperCase(Locale.ROOT));
        if (requested != null && actual != null && requested.getCode().equals(actual.getCode())
                && number.equals(card.getCollectorNumber())) return card;
        return null;
    }
    private static PaperCard findLegacyPrinting(CardDb database, String name, String set, String number) {
        // Catalog prerelease (s) and promo-pack (p) printings have a P-prefixed
        // parent set. Forge often lists only the parent printing. Resolve that
        // exact parent, never CardDb's unrelated latest-printing fallback.
        String promoSet = set.toUpperCase(Locale.ROOT);
        if (promoSet.matches("P[A-Z0-9]{3}") && number.matches("[0-9]+[ps]")) {
            PaperCard parent = lookupCard(database, name, promoSet.substring(1),
                    number.substring(0, number.length() - 1));
            if (parent != null) return new NativePromoCard(parent, promoSet, number);
        }
        // Scryfall distinguishes Seventh Edition foils and BRR serialized
        // schematic cards, while Forge stores their same-set base printings.
        // Restrict suffix aliases to these known treatments, never all sets.
        boolean treatment = (promoSet.equals("7ED") && number.matches("[0-9]+★"))
                || (promoSet.equals("BRR") && number.matches("[0-9]+z"));
        if (treatment) {
            PaperCard parent = lookupCard(database, name, promoSet,
                    number.substring(0, number.length() - 1));
            if (parent != null) return new NativePromoCard(parent.getFoiled(), promoSet, number);
        }
        return null;
    }
    private static boolean matchesCardName(PaperCard card, String name) {
        if (card.getName().equalsIgnoreCase(name)) return true;
        String[] faces = name.split(" // ", -1);
        return faces.length == 2 && card.getOtherFace() != null
                && card.getMainFace().getName().equalsIgnoreCase(faces[0].trim())
                && card.getOtherFace().getName().equalsIgnoreCase(faces[1].trim());
    }
    JsonObject handle() {
        JsonObject result = object("sessionId", id);
        JsonArray players = new JsonArray();
        for (int i = 0; i < game.getRegisteredPlayers().size(); i++) players.add(i);
        result.add("playerIndexes", players);
        return result;
    }
    void start() { start(null); }
    void start(Runnable startGameHook) {
        context.gameExecutor().execute(() -> {
            try {
                match.startGame(game, startGameHook);
            } catch (Throwable error) {
                if (!game.isGameOver() || !isTerminalCancellation(error)) {
                    fail(error);
                    return;
                }
            }
            // Publish terminal state only after the native game thread has
            // returned or unwound its cancelled menu, never while it is live.
            try {
                capture(null);
                synchronized (this) { finished = true; pending = null; notifyAll(); }
            } catch (Throwable error) { fail(error); }
        });
        awaitBoundary();
    }
    private static boolean isTerminalCancellation(Throwable error) {
        for (Throwable cause = error; cause != null; cause = cause.getCause())
            if (cause instanceof TerminalDecisionCancelled) return true;
        return false;
    }
    int index(Player player) { return game.getRegisteredPlayers().indexOf(player); }
    String playerId(Player player) { return "player-" + index(player); }
    static String cardId(Card card) { return "card-" + card.getId(); }
    Card card(String id) {
        if (!id.startsWith("card-")) throw new IllegalArgumentException("Invalid card ID");
        int number = Integer.parseInt(id.substring(5));
        Card c = game.getCardsInGame().stream().filter(candidate -> candidate.getId() == number).findFirst().orElse(null);
        if (c == null) throw new IllegalArgumentException("Card unavailable");
        return c;
    }
    Player player(String id) {
        if (!id.startsWith("player-")) throw new IllegalArgumentException("Invalid player ID");
        return game.getRegisteredPlayers().get(Integer.parseInt(id.substring(7)));
    }
    private void capture(Player priority) {
        replay.record(game.isGameOver() ? "GameFinished" : "Decision", priority == null ? -1 : index(priority),
                game.isGameOver() ? "Game finished" : "Waiting for a decision");
        Map<Integer, String> copies = new HashMap<>();
        String integrity = NativeIntegrity.capture(game, context);
        for (int viewer = -1; viewer < game.getRegisteredPlayers().size(); viewer++) {
            JsonObject snapshot = NativeSnapshot.capture(game, id, viewer, priority);
            snapshot.addProperty("integrityHash", integrity);
            copies.put(viewer, snapshot.toString());
        }
        synchronized (this) { snapshots.clear(); snapshots.putAll(copies); }
    }
    void publish(Player owner, JsonObject input, Function<JsonObject, Runnable> prepare, boolean onEdt) {
        publish(owner, input, null, prepare, onEdt, null);
    }
    void publish(Player owner, JsonObject input, JsonObject sourceCard, Function<JsonObject, Runnable> prepare, boolean onEdt) {
        publish(owner, input, sourceCard, prepare, onEdt, null);
    }
    private synchronized void publish(Player owner, JsonObject input, JsonObject sourceCard, Function<JsonObject, Runnable> prepare,
                                      boolean onEdt, SynchronousAnswer<?> answer) {
        check();
        // A queued refresh of the old input must not acknowledge a response
        // whose native action has not started. The dispatcher releases this
        // barrier before running the action, so nested human menus still work.
        if (nativeActionQueued) return;
        capture(owner);
        JsonObject envelope = object("decidingPlayerId", playerId(decisionOwner(owner)));
        envelope.addProperty("promptId", ++serial);
        envelope.add("input", input);
        if (sourceCard != null) envelope.add("sourceCard", sourceCard.deepCopy());
        pending = new Pending(serial, envelope, prepare, onEdt, answer);
        notifyAll();
    }
    private void dispatchNativeAction(Runnable action) {
        later(() -> {
            synchronized (NativeSession.this) { nativeActionQueued = false; }
            action.run();
        });
    }
    private Player decisionOwner(Player acting) {
        // Match the controller's immutable lobby identity, including a human
        // controlling an AI seat or a player who is themselves controlled.
        LobbyPlayer lobby = acting.getController().getLobbyPlayer();
        return game.getRegisteredPlayers().stream()
                .filter(player -> player.getOriginalLobbyPlayer() == lobby).findFirst()
                .orElseThrow(() -> new IllegalStateException("Unregistered decision controller"));
    }
    void later(Runnable action) {
        context.later(() -> {
            synchronized (NativeSession.this) { if (closed) return; }
            try { action.run(); } catch (Throwable error) { fail(error); }
        });
    }
    <T> T ask(Player owner, JsonObject input, Function<JsonObject, T> validate) {
        return ask(owner, input, null, validate);
    }
    <T> T ask(Player owner, JsonObject input, JsonObject sourceCard, Function<JsonObject, T> validate) {
        SpellAbility ability = decisionAbility.get();
        // End-the-turn effects empty the stack before cleanup choices finish.
        if (ability == null && game.getStack().isResolving() && !game.getStack().isEmpty())
            ability = game.getStack().peekAbility();
        SynchronousAnswer<T> answer = new SynchronousAnswer<>(ability);
        synchronized (this) { answers.add(answer); }
        try {
            publish(owner, input, sourceCard, raw -> {
                T selected = validate.apply(raw);
                return () -> answer.complete(selected);
            }, false, answer);
            return answer.await();
        } finally { synchronized (this) { answers.remove(answer); } }
    }
    <T> T withDecisionAbility(SpellAbility ability, Supplier<T> action) {
        SpellAbility previous = decisionAbility.get();
        decisionAbility.set(ability);
        try { return action.get(); }
        finally {
            if (previous == null) decisionAbility.remove(); else decisionAbility.set(previous);
        }
    }
    private Player replacementChooser(SpellAbility ability, Player departed) {
        Player controller = ability.getActivatingPlayer();
        if (controller == null || !controller.isInGame())
            throw new IllegalStateException("A surviving decision requires a live native controller");
        return withDecisionAbility(ability, () -> controller.getController()
                .choosePlayerForDepartedDecision(ability, departed));
    }

    private void reassign(Pending previous, Player replacement) {
        if (replacement == null || !replacement.isInGame()) throw new IllegalStateException("No surviving player for native decision");
        capture(replacement);
        synchronized (this) {
            JsonObject envelope = previous.envelope().deepCopy();
            envelope.addProperty("decidingPlayerId", playerId(decisionOwner(replacement)));
            envelope.addProperty("promptId", ++serial);
            pending = new Pending(serial, envelope, previous.prepare(), previous.onEdt(), previous.answer());
            notifyAll();
        }
    }
    synchronized String snapshot(int viewer) {
        check();
        String value = snapshots.get(viewer);
        if (value == null) throw new IllegalArgumentException("Invalid snapshot viewer");
        return value;
    }
    synchronized String prompt(int playerIndex) {
        check();
        if (playerIndex < 0 || playerIndex >= game.getRegisteredPlayers().size()) throw new IllegalArgumentException("Invalid player");
        return pending == null ? "" : pending.envelope().toString();
    }
    synchronized boolean gameOver() { check(); return finished && game.isGameOver(); }
    String submit(JsonObject response) {
        try (var scope = context.enter()) { return submitScoped(response); }
    }
    private String submitScoped(JsonObject response) {
        if (text(response, "type", "").equals("directive")) {
            if (!response.getAsJsonObject("directive").get("type").getAsString().equals("concede")) throw new IllegalArgumentException("Unknown directive");
            int player = response.get("player").getAsInt();
            if (player < 0 || player >= game.getRegisteredPlayers().size()) throw new IllegalArgumentException("Unknown conceding player");
            NativeGuiGame conceding = guis.stream().filter(gui -> index(gui.human.getPlayer()) == player)
                    .findFirst().orElseThrow(() -> new IllegalArgumentException("Only a human seat may submit a concession"));
            Pending previous;
            synchronized (this) {
                check(); previous = pending; pending = null;
                nativeActionQueued = previous == null || previous.answer() == null;
            }
            Runnable concede = () -> {
                conceding.human.concede();
                if (game.isGameOver()) {
                    // Forge has already recorded the real outcome. The native
                    // InputQueue release does not cover our synchronous GUI
                    // futures, and none of those decisions needs an answer now.
                    synchronized (NativeSession.this) {
                        terminalConcession = true;
                        pending = null;
                        for (SynchronousAnswer<?> answer : answers)
                            answer.cancel(new TerminalDecisionCancelled());
                    }
                } else {
                    Player departed = game.getRegisteredPlayers().get(player);
                    SpellAbility ability = previous == null || previous.answer() == null ? null : previous.answer().ability;
                    // The departing object's controller need not own the menu:
                    // an opponent may currently be choosing for their effect.
                    if (ability != null) {
                        PlayerDecisionCancelled cancelled = new PlayerDecisionCancelled(departed, ability);
                        if (cancelled.canAbandon(ability)) {
                            previous.answer().cancel(cancelled);
                            return;
                        }
                    }
                    boolean ownedPrompt = previous != null && previous.envelope().get("decidingPlayerId").getAsString().equals("player-" + player);
                    if (ownedPrompt && previous.answer() != null) {
                        // CR 800.4g/h: a surviving object selects its replacement
                        // chooser, while a rule passes the choice in turn order.
                        Player replacement = ability == null ? game.getNextPlayerAfter(departed)
                                : replacementChooser(ability, departed);
                        reassign(previous, replacement);
                    } else if (ownedPrompt) {
                        // A departed player's native input cannot hold up the
                        // remaining players. Stop its own queue only.
                        while (conceding.human.getInputQueue().getInput() instanceof forge.gamemodes.match.input.InputSynchronized input) input.stop();
                    } else if (previous != null) {
                        Player deciding = player(previous.envelope().get("decidingPlayerId").getAsString());
                        capture(deciding);
                        synchronized (NativeSession.this) {
                            if (pending == null) pending = previous;
                            NativeSession.this.notifyAll();
                        }
                    }
                }
            };
            if (previous != null && previous.answer() != null)
                previous.answer().controls.offer(concede);
            else dispatchNativeAction(concede);
            awaitBoundary();
            return "{}";
        }
        Pending current;
        Runnable action;
        synchronized (this) {
            check();
            current = pending;
            if (current == null) throw new IllegalArgumentException("No decision is pending");
            // Validation happens before invalidating the pending prompt so a bad
            // card name or foreign option leaves the original decision intact.
            String expected = current.envelope().getAsJsonObject("input").get("type").getAsString();
            if (!text(response, "type", "").equals(expected) || !response.has("output") || !response.get("output").isJsonObject()) {
                throw new IllegalArgumentException("Response does not match the current prompt family");
            }
            action = current.prepare().apply(response.getAsJsonObject("output"));
            nativeActionQueued = current.onEdt();
            pending = null;
        }
        if (current.onEdt()) dispatchNativeAction(action); else action.run();
        awaitBoundary();
        return "{}";
    }
    private void awaitBoundary() { awaitBoundary(30, TimeUnit.SECONDS); }
    synchronized void awaitBoundary(long timeout, TimeUnit unit) {
        long deadline = System.nanoTime() + unit.toNanos(timeout);
        while (pending == null && !finished && failure == null && !closed) {
            long left = deadline - System.nanoTime();
            if (left <= 0) {
                fail(new IllegalStateException("Native input boundary timed out"));
                break;
            }
            try { TimeUnit.NANOSECONDS.timedWait(this, left); }
            catch (InterruptedException e) { Thread.currentThread().interrupt(); throw new IllegalStateException(e); }
        }
        check();
    }
    synchronized void fail(Throwable error) {
        if (closed) return;
        if (terminalConcession && isTerminalCancellation(error)) return;
        for (Throwable cause = error; cause != null; cause = cause.getCause())
            if (closed && cause instanceof CancellationException) return;
        if (failure == null) { failure = error; error.printStackTrace(System.err); }
        for (SynchronousAnswer<?> answer : answers) answer.cancel(error);
        notifyAll();
    }
    synchronized boolean hasFailed() { return failure != null; }
    private void check() {
        if (failure != null) throw new IllegalStateException("Native game failed", failure);
        if (closed) throw new IllegalStateException("Native game is closed");
    }
    @Override public synchronized void close() {
        if (closed) return;
        closed = true;
        try (var scope = context.enter()) {
            for (SynchronousAnswer<?> answer : answers) answer.cancel(new CancellationException("Host closed"));
            for (NativeGuiGame gui : guis) gui.human.getInputQueue().onGameOver(true);
        } finally { context.close(); }
        notifyAll();
    }
    static JsonObject object(String key, String value) { JsonObject o = new JsonObject(); o.addProperty(key, value); return o; }
    static String text(JsonObject o, String key, String fallback) { return o.has(key) && !o.get(key).isJsonNull() ? o.get(key).getAsString() : fallback; }
}
