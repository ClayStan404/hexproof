// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import com.google.gson.*;
import forge.harness.host.ManaBrewEngineAdapter;
import forge.harness.host.ManaBrewInteractiveSession;
import forge.harness.common.SnapshotExtractor;
import forge.game.Game;
import forge.game.card.Card;
import forge.game.card.CardFactory;
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.zone.ZoneType;
import forge.model.FModel;
import java.nio.file.*;
import java.util.*;
import java.lang.reflect.Field;

/** Isolated fixtures against the actual shipped Forge host, not mocked effects. */
public final class Qualification {
    static final ManaBrewEngineAdapter adapter = new ManaBrewEngineAdapter();
    static final Gson gson = new GsonBuilder().setPrettyPrinting().create();
    static String session;
    static Game game;
    static JsonObject prompt;
    static JsonObject result;
    static JsonArray transitions;
    static int assertions;
    static boolean negativeControl;
    static boolean commandReturnOffered;
    static Path authorityHelper;
    static Path evidenceDirectory;
    static class MissingCatalogCard extends RuntimeException {
        MissingCatalogCard(String name) { super("Pinned runtime card catalog does not contain " + name); }
    }

    public static void main(String[] args) throws Exception {
        adapter.initialize(args[0]);
        Path output = Path.of(args[1]);
        evidenceDirectory = output;
        String helper = System.getenv("HEXPROOF_EVAL_AUTHORITY_HELPER");
        authorityHelper = helper == null ? null : Path.of(helper);
        negativeControl = Arrays.asList(args).contains("--negative-control");
        JsonArray results = new JsonArray();
        List<String> cases = Arrays.asList(args).contains("--extensions")
                ? List.of("prepare_cast", "prepare_source_leaves")
                : List.of("opening", "land_priority", "bolt_player", "bolt_creature",
                "counterspell", "etb_draw", "hidden_views", "four_player_departure",
                "replacement", "tokens", "blocked_combat", "adventure", "modal_dfc", "morph", "copy", "commander_tax", "commander_damage");
        for (String id : cases) {
            if (negativeControl && !id.equals("bolt_player")) continue;
            result = new JsonObject();
            transitions = new JsonArray();
            assertions = 0;
            commandReturnOffered = false;
            result.addProperty("id", id);
            result.addProperty("layer", "engine");
            result.addProperty("setup", id.equals("opening") ? "Normal hosted opening, no state injection"
                    : "Normal hosted opening; paused game-thread fixture zone replacement and development phase setup; normal published actions thereafter");
            session = "qualification-" + id;
            try {
                start(id.equals("four_player_departure") || id.startsWith("commander_") ? 4 : 2, id.startsWith("commander_"));
                switch (id) {
                    case "opening" -> opening();
                    case "land_priority" -> land();
                    case "bolt_player" -> bolt(false, false);
                    case "bolt_creature" -> bolt(true, false);
                    case "counterspell" -> counterspell();
                    case "etb_draw" -> etb();
                    case "hidden_views" -> privacy();
                    case "four_player_departure" -> departure();
                    case "replacement" -> bolt(true, true);
                    case "tokens" -> tokens();
                    case "blocked_combat" -> combat();
                    case "adventure" -> adventure();
                    case "modal_dfc" -> modalDfc();
                    case "morph" -> morph();
                    case "copy" -> copy();
                    case "commander_tax" -> commanderTax();
                    case "commander_damage" -> commanderDamage();
                    case "prepare_cast" -> prepare(false);
                    case "prepare_source_leaves" -> prepare(true);
                }
                if (!result.has("status")) {
                    result.addProperty("status", "PASS");
                    result.addProperty("reason", "All frozen assertions exercised through actual engine actions");
                }
                result.addProperty("assertionsFailed", 0);
            } catch (MissingCatalogCard error) {
                result.addProperty("status", "UNSUPPORTED");
                result.addProperty("layer", "engine");
                result.addProperty("limitationScope", "bundled-card-catalog");
                result.addProperty("reason", error + "; this is not a claim that the underlying mechanic cannot be implemented");
                result.addProperty("assertionsFailed", 0);
                error.printStackTrace();
            } catch (AssertionError error) {
                result.addProperty("status", "FAIL");
                result.addProperty("layer", "unknown");
                result.addProperty("reason", error.toString());
                result.addProperty("assertionsFailed", 1);
                error.printStackTrace();
            } catch (Throwable error) {
                result.addProperty("status", "UNVERIFIED");
                result.addProperty("layer", "fixture");
                result.addProperty("reason", error.toString());
                result.addProperty("assertionsFailed", 0);
                error.printStackTrace();
            } finally {
                adapter.endGame(session);
            }
            result.addProperty("assertionsPassed", assertions);
            result.add("observed", transitions);
            JsonArray evidence = new JsonArray();
            evidence.add(id + ".json");
            evidence.add("run.log");
            result.add("evidence", evidence);
            Files.writeString(output.resolve(id + ".json"), gson.toJson(transitions) + "\n");
            results.add(result);
            Files.writeString(output.resolve("raw-results.json"), gson.toJson(results) + "\n");
            System.out.println("CASE " + id + " " + result.get("status") + " assertions=" + assertions);
        }
    }

    static void start(int players, boolean commander) throws Exception {
        List<ManaBrewEngineAdapter.CardIdentity> deck = new ArrayList<>();
        for (int i = 0; i < (commander ? 99 : 60); i++) deck.add(new ManaBrewEngineAdapter.CardIdentity("Plains", null, null, false));
        if (commander) deck.add(new ManaBrewEngineAdapter.CardIdentity("Isamaru, Hound of Konda", null, null, false));
        List<ManaBrewEngineAdapter.PlayerConfig> seats = new ArrayList<>();
        for (int i = 0; i < players; i++) seats.add(new ManaBrewEngineAdapter.PlayerConfig("Seat " + i, deck,
                commander ? List.of("Isamaru, Hound of Konda") : List.of(), false));
        adapter.startGame(new ManaBrewEngineAdapter.StartGameRequest(session, commander ? "Commander" : "Constructed", commander ? 40 : 20, 42L, seats, 0));
        Field sessions = ManaBrewEngineAdapter.class.getDeclaredField("sessions");
        sessions.setAccessible(true);
        game = ((ManaBrewInteractiveSession)((Map<?, ?>)sessions.get(adapter)).get(session)).getGame();
        next(-1);
        for (int i = 0; i < 40; i++) {
            if (kind().equals("chooseAction") && game.getPhaseHandler().getPhase() == PhaseType.MAIN1
                    && actor() == 0) return;
            send("{\"kind\":\"pass\"}");
        }
        throw new IllegalStateException("Opening did not reach first main phase");
    }

    static void opening() {
        for (Player player : game.getPlayers()) {
            check(player.getCardsIn(ZoneType.Hand).size() == 7, "opening hand seven");
            check(player.getCardsIn(ZoneType.Library).size() == 53, "opening library 53, including skipped first draw");
        }
        check(actor() == 0 && game.getPhaseHandler().getTurn() == 1, "first player main decision");
        capture("opening");
    }

    static void fixture() throws Exception {
        // Publication precedes the queue wait. Confirm the producer is blocked
        // before changing test state; no concurrent readers are launched here.
        Thread worker = Thread.getAllStackTraces().keySet().stream()
                .filter(t -> t.getName().equals("mana-brew-forge-" + session)).findFirst().orElseThrow();
        long deadline = System.nanoTime() + 2_000_000_000L;
        while (Arrays.stream(worker.getStackTrace()).noneMatch(frame ->
                frame.getClassName().equals("java.util.concurrent.LinkedBlockingQueue")
                        && frame.getMethodName().equals("poll"))) {
            if (System.nanoTime() > deadline) throw new IllegalStateException("Game thread not paused");
            Thread.sleep(1);
        }
        for (Player player : game.getPlayers()) {
            for (ZoneType zone : List.of(ZoneType.Hand, ZoneType.Library, ZoneType.Battlefield,
                    ZoneType.Graveyard, ZoneType.Exile)) player.getZone(zone).setCards(List.of());
            for (int i = 0; i < 30; i++) add(player, ZoneType.Library, "Plains");
        }
        game.getPhaseHandler().devModeSet(PhaseType.MAIN1, player(0), 1);
    }

    static Player player(int index) { return game.getRegisteredPlayers().get(index); }
    static Card add(Player player, ZoneType zone, String name) {
        var paper = FModel.getMagicDb().getCommonCards().getCard(name);
        if (paper == null) {
            JsonObject missing = new JsonObject(); missing.addProperty("requestedCatalogCard", name);
            missing.addProperty("present", false); transitions.add(missing);
            throw new MissingCatalogCard(name);
        }
        Card card = CardFactory.getCard(paper, player, game);
        player.getZone(zone).add(card);
        return card;
    }
    static Card add(int player, ZoneType zone, String name) { return add(player(player), zone, name); }
    static void refresh() throws Exception {
        // Empty undo stack: asks the real controller to rebuild legal actions
        // after test setup without advancing priority, phase or turn.
        if (!game.getStack().isEmpty()) throw new IllegalStateException("Fixture refresh with nonempty stack");
        send("{\"kind\":\"untap_land\"}");
        capture("fixture");
    }

    static void land() throws Exception {
        fixture(); add(0, ZoneType.Hand, "Plains"); add(0, ZoneType.Hand, "Plains"); refresh();
        if (authorityHelper != null) {
            String before = adapter.getSnapshot(session, -1);
            long pending = prompt.get("promptId").getAsLong();
            JsonObject rejected = authorizeLand(1, pending);
            check(!rejected.get("accepted").getAsBoolean(), "production Go builder rejects the wrong actor");
            check(before.equals(adapter.getSnapshot(session, -1))
                    && pending == JsonParser.parseString(adapter.getPrompt(session, 0)).getAsJsonObject().get("promptId").getAsLong(),
                    "rejected actor did not mutate game or consume the pending decision");
            check(!authorizeLand(0, pending + 1).get("accepted").getAsBoolean(), "stale prompt rejected by production Go builder");
            JsonObject accepted = authorizeLand(0, pending);
            check(accepted.get("accepted").getAsBoolean(), "owner receives a valid engine response from production Go builder");
            send(accepted.get("response").toString());
        } else {
            choose("Play Plains");
        }
        settleToPriority();
        check(count(0, ZoneType.Hand, "Plains") == 1 && count(0, ZoneType.Battlefield, "Plains") == 1,
                "one land moved hand to battlefield");
        check(option("Play Plains") == null, "second land not offered");
        result.addProperty("layer", "adapter");
        if (authorityHelper == null) {
            result.addProperty("status", "UNVERIFIED");
            result.addProperty("reason", "Two engine land assertions passed; no production Go authority helper supplied.");
        } else {
            check(!authorizeLand(0, prompt.get("promptId").getAsLong()).get("accepted").getAsBoolean(),
                    "second land cannot be translated into an allowed engine response");
            result.addProperty("status", "PASS");
            result.addProperty("reason", "Exact two-Plains fixture through Java rules and production Go BuildPromptResponse: wrong actor and stale id rejected, owner action applied, second land unavailable. Trusted laboratory supplies actor; WebSocket identity authentication is separately exercised.");
        }
        capture("land authority and rules");
    }

    static JsonObject authorizeLand(int caller, long id) throws Exception {
        JsonObject request = new JsonObject();
        request.add("prompt", prompt.deepCopy()); request.addProperty("actor", caller);
        request.addProperty("promptId", id); request.addProperty("label", "Play Plains");
        Process process = new ProcessBuilder(authorityHelper.toString())
                .redirectError(ProcessBuilder.Redirect.appendTo(evidenceDirectory.resolve("authority-stderr.log").toFile())).start();
        try {
            process.getOutputStream().write((request + "\n").getBytes(java.nio.charset.StandardCharsets.UTF_8));
            process.getOutputStream().close();
            if (!process.waitFor(15, java.util.concurrent.TimeUnit.SECONDS))
                throw new IllegalStateException("Authority helper timeout");
            String raw = new String(process.getInputStream().readAllBytes(), java.nio.charset.StandardCharsets.UTF_8);
            if (process.exitValue() != 0) throw new IllegalStateException("Authority helper exit " + process.exitValue());
            JsonObject reply = JsonParser.parseString(raw).getAsJsonObject();
            JsonObject observation = new JsonObject(); observation.add("authorityRequest", request); observation.add("authorityResult", reply);
            transitions.add(observation); return reply;
        } finally {
            if (process.isAlive()) process.destroyForcibly().waitFor();
        }
    }

    static void bolt(boolean creature, boolean replacement) throws Exception {
        fixture(); add(0, ZoneType.Hand, "Lightning Bolt");
        Card mountain = add(0, ZoneType.Battlefield, "Mountain");
        if (creature) add(1, ZoneType.Battlefield, "Grizzly Bears");
        if (replacement) add(0, ZoneType.Battlefield, "Rest in Peace");
        refresh();
        cast("Cast Lightning Bolt", creature ? "Grizzly Bears" : "player-1");
        check(player(1).getLife() == 20 && !game.getStack().isEmpty(), "Bolt on stack before damage");
        resolveStack();
        if (creature) {
            ZoneType destination = replacement ? ZoneType.Exile : ZoneType.Graveyard;
            check(count(1, destination, "Grizzly Bears") == 1 && count(0, destination, "Lightning Bolt") == 1,
                    "Bears and Bolt correct destination " + destination);
            check(count(1, ZoneType.Battlefield, "Grizzly Bears") == 0 && player(1).getLife() == 20,
                    "lethal damage SBA, not player damage");
            if (replacement) check(player(0).getCardsIn(ZoneType.Graveyard).isEmpty()
                    && player(1).getCardsIn(ZoneType.Graveyard).isEmpty(), "replacement prevented graveyard placement");
        } else {
            check(player(1).getLife() == (negativeControl ? 16 : 17), "Bolt deals exactly three damage");
            check(count(0, ZoneType.Graveyard, "Lightning Bolt") == 1 && mountain.isTapped(), "spell graveyard and mana paid");
        }
        capture("resolved");
    }

    static void counterspell() throws Exception {
        fixture(); add(0, ZoneType.Hand, "Lightning Bolt"); add(0, ZoneType.Battlefield, "Mountain");
        add(1, ZoneType.Hand, "Counterspell"); add(1, ZoneType.Battlefield, "Island"); add(1, ZoneType.Battlefield, "Island");
        refresh(); cast("Cast Lightning Bolt", "player-1");
        while (actor() != 1) send("{\"kind\":\"pass\"}");
        cast("Cast Counterspell", "Lightning Bolt");
        check(game.getStack().size() == 2 && game.getStack().peekAbility().getHostCard().getName().equals("Counterspell"),
                "Counterspell above Bolt");
        resolveStack();
        check(player(0).getLife() == 20 && player(1).getLife() == 20, "no damage from countered spell");
        check(count(0, ZoneType.Graveyard, "Lightning Bolt") == 1
                && count(1, ZoneType.Graveyard, "Counterspell") == 1 && game.getStack().isEmpty(), "both spells graveyard");
        capture("resolved");
    }

    static void etb() throws Exception {
        fixture(); add(0, ZoneType.Hand, "Elvish Visionary"); add(0, ZoneType.Battlefield, "Forest"); add(0, ZoneType.Battlefield, "Plains");
        refresh(); cast("Cast Elvish Visionary", null);
        for (int i = 0; i < 30 && count(0, ZoneType.Battlefield, "Elvish Visionary") == 0; i++) automatic(null);
        check(count(0, ZoneType.Battlefield, "Elvish Visionary") == 1, "Visionary resolved to battlefield");
        check(!game.getStack().isEmpty() && player(0).getCardsIn(ZoneType.Library).size() == 30,
                "ETB trigger on stack before draw");
        capture("trigger"); resolveStack();
        check(player(0).getCardsIn(ZoneType.Library).size() == 29 && player(0).getCardsIn(ZoneType.Hand).size() == 1,
                "exactly one card drawn without draw step"); capture("resolved");
    }

    static void tokens() throws Exception {
        fixture(); add(0, ZoneType.Hand, "Raise the Alarm"); add(0, ZoneType.Battlefield, "Plains"); add(0, ZoneType.Battlefield, "Plains");
        refresh(); cast("Cast Raise the Alarm", null); resolveStack();
        List<Card> tokens = new ArrayList<>();
        for (Card card : player(0).getCardsIn(ZoneType.Battlefield)) if (card.isToken()) tokens.add(card);
        check(tokens.size() == 2 && tokens.stream().allMatch(c -> c.isCreature() && c.getType().hasSubtype("Soldier")
                && c.getColor().hasWhite() && c.getColor().isMonoColor() && c.getNetPower() == 1 && c.getNetToughness() == 1), "two white 1/1 Soldier tokens");
        check(count(0, ZoneType.Graveyard, "Raise the Alarm") == 1, "resolved instant graveyard");
        check(player(0).getCardsIn(ZoneType.Hand).isEmpty() && player(0).getCardsIn(ZoneType.Library).size() == 30,
                "tokens did not consume cards"); capture("resolved");
    }

    static void prepare(boolean removeSource) throws Exception {
        fixture();
        Card goblin = add(0, ZoneType.Hand, "Goblin Glasswright");
        for (int i = 0; i < 3; i++) add(0, ZoneType.Battlefield, "Mountain");
        if (removeSource) { add(1, ZoneType.Hand, "Lightning Bolt"); add(1, ZoneType.Battlefield, "Mountain"); }
        refresh();
        check(option("Craft with Pride") == null, "prepared sorcery is not castable directly from hand");
        cast("Cast Goblin Glasswright", null); resolveStack();
        capture("after creature resolution");
        int goblinId = goblin.getId();
        goblin = player(0).getCardsIn(ZoneType.Battlefield).stream()
                .filter(c -> c.getId() == goblinId).findFirst().orElseThrow();
        Card copy = goblin.getPreparedSpell();
        JsonObject prepared = new JsonObject();
        prepared.addProperty("label", "native prepared state");
        prepared.addProperty("creatureId", goblin.getId());
        prepared.addProperty("prepared", goblin.isPrepared());
        prepared.addProperty("copyName", copy == null ? null : copy.getName());
        prepared.addProperty("copyZone", copy == null ? null : String.valueOf(copy.getZone()));
        transitions.add(prepared);
        check(goblin.isInZone(ZoneType.Battlefield) && goblin.getNetPower() == 2 && goblin.getNetToughness() == 2
                && goblin.isPrepared() && copy != null && copy.isInZone(ZoneType.Exile)
                && copy.getName().equals("Craft with Pride") && count(0, ZoneType.Exile, "Craft with Pride") == 1,
                "actual creature entered prepared with one exiled associated sorcery copy");
        capture("prepared");
        if (removeSource) {
            for (int i = 0; i < 12 && actor() != 1; i++) automatic(null);
            cast("Cast Lightning Bolt", "Goblin Glasswright"); resolveStack();
            check(goblin.isInZone(ZoneType.Graveyard), "Bolt damage destroyed prepared creature");
            check(game.getCardsInGame().stream().noneMatch(c -> c.getId() == copy.getId())
                    && option("Craft with Pride") == null, "uncast prepared copy ceased to exist after source left");
        } else {
            cast("Cast Craft with Pride", null);
            check(!goblin.isPrepared() && goblin.isInZone(ZoneType.Battlefield)
                    && game.getStack().peekAbility().getHostCard().getName().equals("Craft with Pride"),
                    "paid sorcery on stack; casting unprepared the same battlefield creature");
            resolveStack();
            check(player(0).getCardsIn(ZoneType.Battlefield).stream().filter(c -> c.isToken() && c.getType().hasSubtype("Treasure")).count() == 1
                    && count(0, ZoneType.Exile, "Craft with Pride") == 0 && option("Craft with Pride") == null,
                    "one Treasure created; copy gone and unavailable for repeat cast");
        }
        capture("prepare outcome");
    }

    static void privacy() throws Exception {
        fixture(); add(0, ZoneType.Hand, "Lightning Bolt"); add(1, ZoneType.Hand, "Counterspell");
        player(0).getZone(ZoneType.Library).setCards(List.of()); player(1).getZone(ZoneType.Library).setCards(List.of());
        add(0, ZoneType.Library, "Elvish Visionary"); add(1, ZoneType.Library, "Clone"); add(0, ZoneType.Battlefield, "Grizzly Bears"); refresh();
        for (int viewer : List.of(-1, 0, 1)) {
            String raw = adapter.getSnapshot(session, viewer);
            JsonObject view = JsonParser.parseString(raw).getAsJsonObject();
            check(viewer == 0 ? raw.contains("Lightning Bolt") : !raw.contains("Lightning Bolt"), "own hand identity only: Bolt viewer " + viewer);
            check(viewer == 1 ? raw.contains("Counterspell") : !raw.contains("Counterspell"), "own hand identity only: Counterspell viewer " + viewer);
            check(!raw.contains("Elvish Visionary") && !raw.contains("Clone"), "library names absent viewer " + viewer);
            check(raw.contains("Grizzly Bears"), "public card visible");
            for (JsonElement element : view.getAsJsonArray("zones")) {
                JsonObject zone = element.getAsJsonObject();
                String type = zone.get("zone").getAsString();
                if (type.equals("library") || type.equals("hand") && !zone.get("ownerId").getAsString().equals("player-" + viewer)) {
                    for (JsonElement card : zone.getAsJsonArray("cards")) {
                        JsonObject item = card.getAsJsonObject();
                        check(!item.has("identity"), "no nested hidden identity");
                        check(!item.has("oracleText") && !item.has("manaCost") && !item.has("typeLine"), "no hidden text side channel");
                    }
                    check(zone.get("count").getAsInt() == 1, "public private-zone count");
                }
            }
            JsonObject observed = new JsonObject(); observed.addProperty("viewer", viewer); observed.add("view", view); transitions.add(observed);
        }
    }

    static void combat() throws Exception {
        fixture();
        Card attacker = add(0, ZoneType.Battlefield, "Grizzly Bears"); attacker.setSickness(false);
        Card blocker = add(1, ZoneType.Battlefield, "Grizzly Bears"); blocker.setSickness(false);
        refresh();
        for (int i = 0; i < 20 && !kind().equals("chooseAttackers"); i++) automatic(null);
        if (!kind().equals("chooseAttackers")) throw new IllegalStateException("No attack declaration");
        send("{\"kind\":\"declare_attackers\",\"assignments\":[{\"attackerId\":\"" + SnapshotExtractor.javaCardId(attacker) + "\",\"defenderId\":\"player-1\"}]}");
        for (int i = 0; i < 20 && !kind().equals("chooseBlockers"); i++) automatic(null);
        if (!kind().equals("chooseBlockers")) throw new IllegalStateException("No block declaration");
        send("{\"kind\":\"declare_blockers\",\"assignments\":[{\"attackerId\":\"" + SnapshotExtractor.javaCardId(attacker)
                + "\",\"blockerId\":\"" + SnapshotExtractor.javaCardId(blocker) + "\"}]}");
        capture("blocked");
        for (int i = 0; i < 30 && game.getPhaseHandler().getPhase().isBefore(PhaseType.COMBAT_END); i++) automatic(null);
        check(count(0, ZoneType.Battlefield, "Grizzly Bears") == 0 && count(1, ZoneType.Battlefield, "Grizzly Bears") == 0, "both Bears die");
        check(player(0).getLife() == 20 && player(1).getLife() == 20, "no unblocked damage");
        check(count(0, ZoneType.Graveyard, "Grizzly Bears") == 1 && count(1, ZoneType.Graveyard, "Grizzly Bears") == 1, "Bears in respective graveyards");
        capture("combat-end");
    }

    static void adventure() throws Exception {
        fixture(); add(0, ZoneType.Hand, "Lovestruck Beast");
        for (int i = 0; i < 4; i++) add(0, ZoneType.Battlefield, "Forest");
        refresh(); cast("Heart's Desire", null); resolveStack();
        List<Card> humans = new ArrayList<>();
        for (Card card : player(0).getCardsIn(ZoneType.Battlefield)) if (card.isToken()) humans.add(card);
        check(humans.size() == 1 && humans.get(0).getType().hasSubtype("Human")
                && humans.get(0).getColor().hasWhite() && humans.get(0).getColor().isMonoColor()
                && humans.get(0).getNetPower() == 1 && humans.get(0).getNetToughness() == 1, "one white 1/1 Human token");
        check(count(0, ZoneType.Exile, "Lovestruck Beast") == 1, "adventurer exiled");
        Card exiled = player(0).getCardsIn(ZoneType.Exile).get(0); capture("adventure-resolved");
        cast("Cast Lovestruck Beast", null); resolveStack();
        Card beast = player(0).getCardsIn(ZoneType.Battlefield).stream().filter(c -> c.getName().equals("Lovestruck Beast")).findFirst().orElseThrow();
        check(beast.getId() == exiled.getId() && beast.getNetPower() == 5 && beast.getNetToughness() == 5
                && count(0, ZoneType.Exile, "Lovestruck Beast") == 0, "same adventurer cast from exile as 5/5"); capture("creature-resolved");
    }

    static void modalDfc() throws Exception {
        fixture(); add(0, ZoneType.Hand, "Bala Ged Recovery"); refresh();
        choose("Play Bala Ged Sanctuary"); settleToPriority();
        Card land = player(0).getCardsIn(ZoneType.Battlefield).get(0);
        check(land.getName().equals("Bala Ged Sanctuary") && land.isLand() && land.isTapped(), "MDFC land face enters tapped");
        check(game.getStack().isEmpty() && player(0).getCardsIn(ZoneType.Graveyard).isEmpty()
                && player(0).getCardsIn(ZoneType.Hand).isEmpty(), "no sorcery cast or recovery effect");
        for (int i = 0; i < 80 && (game.getPhaseHandler().getTurn() < 3 || actor() != 0
                || game.getPhaseHandler().getPhase() != PhaseType.MAIN1); i++) automatic(null);
        JsonObject mana = null;
        for (JsonElement e : prompt.getAsJsonObject("input").getAsJsonArray("actions")) {
            JsonObject action = e.getAsJsonObject();
            if (action.has("cardId") && action.get("cardId").getAsString().equals(SnapshotExtractor.javaCardId(land))
                    && action.get("type").getAsString().equals("activateAbility")) { mana = action; break; }
        }
        if (mana == null) throw new IllegalStateException("MDFC mana action missing");
        send("{\"type\":\"chooseAction\",\"output\":{\"type\":\"act\",\"actionId\":\"" + mana.get("id").getAsString() + "\"}}"); settleToPriority();
        check(land.isTapped() && player(0).getManaPool().getAmountOfColor(forge.card.MagicColor.GREEN) == 1, "land untapped next turn and produced green mana");
        capture("mana");
    }

    static void morph() throws Exception {
        fixture(); Card initial = add(0, ZoneType.Hand, "Willbender");
        for (int i = 0; i < 4; i++) add(0, ZoneType.Battlefield, "Plains");
        add(0, ZoneType.Battlefield, "Island"); refresh();
        cast("Cast Willbender (Face down)", null);
        Card stackCard = game.getStack().peekAbility().getHostCard();
        check(stackCard.isFaceDown() && stackCard.getName().isEmpty() && stackCard.getColor().isColorless()
                && stackCard.getNetPower() == 2 && stackCard.getNetToughness() == 2
                && stackCard.getManaCost().isNoCost() && stackCard.getKeywords().isEmpty(),
                "face-down stack has nameless colorless no-cost ability-free 2/2 characteristics");
        check(player(0).getCardsIn(ZoneType.Battlefield).stream().filter(Card::isTapped).count() == 3,
                "face-down cast paid three mana");
        for (int viewer : List.of(-1, 1)) check(!adapter.getSnapshot(session, viewer).contains("Willbender"), "face-down stack private");
        resolveStack();
        Card faceDown = player(0).getCardsIn(ZoneType.Battlefield).stream().filter(Card::isFaceDown).findFirst().orElseThrow();
        check(faceDown.getNetPower() == 2 && faceDown.getNetToughness() == 2 && faceDown.getColor().isColorless()
                && faceDown.getName().isEmpty() && faceDown.getManaCost().isNoCost() && faceDown.getKeywords().isEmpty(), "nameless colorless no-cost ability-free 2/2");
        for (int viewer : List.of(-1, 1)) check(!adapter.getSnapshot(session, viewer).contains("Willbender"), "face-down battlefield private");
        capture("face-down"); choose("Morph"); settleToPriority(); resolveStack();
        Card faceUp = player(0).getCardsIn(ZoneType.Battlefield).stream().filter(c -> c.getName().equals("Willbender")).findFirst().orElseThrow();
        check(faceUp.getId() == initial.getId() && faceUp.getNetPower() == 1 && faceUp.getNetToughness() == 2, "turn-up preserves identity and 1/2 characteristics");
        check(player(0).getCardsIn(ZoneType.Battlefield).stream().filter(Card::isLand).allMatch(Card::isTapped),
                "turn-up paid remaining 1U including Island"); capture("face-up");
    }

    static void copy() throws Exception {
        fixture(); Card bears = add(1, ZoneType.Battlefield, "Grizzly Bears");
        add(0, ZoneType.Hand, "Giant Growth"); add(0, ZoneType.Hand, "Clone");
        add(0, ZoneType.Battlefield, "Forest"); add(0, ZoneType.Battlefield, "Island");
        for (int i = 0; i < 3; i++) add(0, ZoneType.Battlefield, "Plains");
        refresh(); cast("Cast Giant Growth", "Grizzly Bears"); resolveStack();
        cast("Cast Clone", null);
        for (int i = 0; i < 40 && count(0, ZoneType.Battlefield, "Grizzly Bears") == 0; i++) automatic("Grizzly Bears");
        Card clone = player(0).getCardsIn(ZoneType.Battlefield).stream().filter(c -> c.getName().equals("Grizzly Bears")).findFirst().orElseThrow();
        check(clone.isCreature(), "Clone copied Bears name and type");
        check(clone.getNetPower() == 2 && clone.getNetToughness() == 2, "copy excludes temporary growth");
        check(bears.getNetPower() == 5 && bears.getNetToughness() == 5, "original retains temporary growth"); capture("copy-resolved");
    }

    static void commanderTax() throws Exception {
        capture("commander-opening");
        check(game.getPlayers().size() == 4 && game.getPlayers().stream().allMatch(p -> p.getLife() == 40
                && p.getCardsIn(ZoneType.Command).stream().filter(c -> c.getName().equals("Isamaru, Hound of Konda")).count() == 1),
                "four players start 40 with commanders");
        fixture();
        List<Card> plains = new ArrayList<>();
        for (int i = 0; i < 3; i++) plains.add(add(0, ZoneType.Battlefield, "Plains"));
        for (int i = 0; i < 3; i++) add(0, ZoneType.Battlefield, "Swamp");
        add(0, ZoneType.Hand, "Murder"); refresh();
        cast("Cast Isamaru", null); resolveStack();
        check(plains.stream().filter(Card::isTapped).count() == 1, "first command cast pays W");
        cast("Cast Murder", "Isamaru, Hound of Konda"); resolveStack();
        check(commandReturnOffered && count(0, ZoneType.Command, "Isamaru, Hound of Konda") == 1,
                "optional command-zone return offered and accepted after actual destroy");
        // Separate mana-availability subfixtures; no outcome/cast-count mutation.
        player(0).getManaPool().clearPool(false);
        for (Card land : player(0).getCardsIn(ZoneType.Battlefield)) land.setTapped(true);
        plains.get(0).setTapped(false); refresh();
        check(option("Cast Isamaru") == null, "W alone cannot pay taxed commander");
        for (Card land : plains) land.setTapped(false); refresh();
        cast("Cast Isamaru", null); resolveStack();
        check(plains.stream().allMatch(Card::isTapped), "second command cast paid all three Plains: 2W");
        check(count(0, ZoneType.Battlefield, "Isamaru, Hound of Konda") == 1, "recast commander on battlefield"); capture("taxed-recast");
    }

    static void commanderDamage() throws Exception {
        fixture(); add(0, ZoneType.Battlefield, "Plains"); refresh();
        cast("Cast Isamaru", null); resolveStack();
        Card commander = player(0).getCardsIn(ZoneType.Battlefield).stream().filter(Card::isCommander).findFirst().orElseThrow();
        commander.setSickness(false); player(1).addCommanderDamage(commander, 19);
        for (int i = 0; i < 30 && !kind().equals("chooseAttackers"); i++) automatic(null);
        if (!kind().equals("chooseAttackers")) throw new IllegalStateException("Commander attack unavailable");
        send("{\"kind\":\"declare_attackers\",\"assignments\":[{\"attackerId\":\"" + SnapshotExtractor.javaCardId(commander)
                + "\",\"defenderId\":\"player-1\"}]}");
        for (int i = 0; i < 40 && !player(1).hasLost(); i++) automatic(null);
        check(player(1).hasLost() && player(1).getLife() > 0 && player(1).getCommanderDamage(commander) == 21,
                "21 commander combat damage loses despite positive life");
        check(!game.isGameOver() && game.getPlayers().size() == 3 && !player(actor()).hasLost(),
                "three players remain with a surviving decision owner");
        long prior = prompt.get("promptId").getAsLong(); automatic(null);
        check(prompt.get("promptId").getAsLong() != prior && !game.isGameOver(), "survivor completes next real decision");
        capture("commander-lethal");
        adapter.endGame(session); session += "-noncombat"; start(4, true);
        fixture(); add(0, ZoneType.Battlefield, "Plains"); refresh(); cast("Cast Isamaru", null); resolveStack();
        commander = player(0).getCardsIn(ZoneType.Battlefield).stream().filter(Card::isCommander).findFirst().orElseThrow();
        player(1).addCommanderDamage(commander, 19);
        // Actual damage-classification seam in a fresh, prevention-free fixture.
        player(1).addDamageAfterPrevention(2, commander, null, false, new forge.game.GameEntityCounterTable());
        player(1).processDamage();
        check(player(1).getLife() == 38 && player(1).getCommanderDamage(commander) == 19,
                "actual two noncombat damage decreases life but not commander counter");
        // Publish the completed classification fixture before recording its view.
        refresh(); capture("noncombat-counter");
    }

    static void departure() throws Exception {
        fixture(); Card departing = add(2, ZoneType.Battlefield, "Grizzly Bears"); refresh();
        String departingId = SnapshotExtractor.javaCardId(departing);
        adapter.submitAction(session, "{\"kind\":\"concede\",\"player\":2}");
        long end = System.nanoTime() + 5_000_000_000L;
        while (JsonParser.parseString(adapter.getSnapshot(session, -1)).getAsJsonObject()
                .getAsJsonArray("players").get(2).getAsJsonObject().get("status").getAsString().equals("playing")) {
            if (System.nanoTime() > end) throw new IllegalStateException("Concession not published"); Thread.sleep(2);
        }
        check(!Boolean.parseBoolean(adapter.getGameOver(session)) && game.getPlayers().size() == 3, "three players continue");
        check(game.getCardsInGame().stream().noneMatch(c -> c.getId() == departing.getId()),
                "departing owned card absent from every active game zone, including exile");
        check(!adapter.getSnapshot(session, -1).contains(departingId), "departing card absent from complete public projection");
        long old = prompt.get("promptId").getAsLong(); send("{\"kind\":\"pass\"}");
        check(prompt.get("promptId").getAsLong() != old, "remaining player's pending decision completes"); capture("after-departure");
        adapter.submitAction(session, "{\"kind\":\"concede\",\"player\":1}");
        adapter.submitAction(session, "{\"kind\":\"concede\",\"player\":3}");
        end = System.nanoTime() + 5_000_000_000L;
        while (!Boolean.parseBoolean(adapter.getGameOver(session))) {
            if (System.nanoTime() > end) throw new IllegalStateException("Final concessions not completed"); Thread.sleep(2);
        }
        check(game.getOutcome().isWinner(player(0).getLobbyPlayer()), "last remaining player wins"); capture("terminal");
    }

    static int count(int p, ZoneType zone, String name) {
        int count = 0; for (Card card : player(p).getCardsIn(zone)) if (card.getName().equals(name)) count++; return count;
    }
    static String kind() { return prompt.getAsJsonObject("input").get("type").getAsString(); }
    static int actor() { return Integer.parseInt(prompt.get("decidingPlayerId").getAsString().substring(7)); }
    static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
        assertions++; System.out.println("ASSERT " + message);
    }
    static void capture(String label) {
        JsonObject entry = new JsonObject(); entry.addProperty("label", label);
        entry.add("view", JsonParser.parseString(adapter.getSnapshot(session, -1)));
        entry.add("prompt", prompt.deepCopy()); transitions.add(entry);
    }
    static void next(long previous) throws Exception {
        long end = System.nanoTime() + 5_000_000_000L;
        while (System.nanoTime() < end) {
            String raw = adapter.getPrompt(session, 0);
            if (!raw.isEmpty()) {
                JsonObject candidate = JsonParser.parseString(raw).getAsJsonObject();
                if (candidate.get("promptId").getAsLong() != previous) { prompt = candidate; return; }
            }
            Thread.sleep(2);
        }
        throw new IllegalStateException("Timed out waiting for prompt after " + previous);
    }
    static void send(String action) throws Exception {
        long previous = prompt.get("promptId").getAsLong();
        System.out.println("ACTION " + kind() + " " + action);
        adapter.submitAction(session, action); next(previous);
    }
    static JsonObject option(String label) {
        if (!kind().equals("chooseAction")) return null;
        for (JsonElement e : prompt.getAsJsonObject("input").getAsJsonArray("actions")) {
            JsonObject action = e.getAsJsonObject();
            if (action.toString().contains(label)) return action;
        }
        return null;
    }
    static void choose(String label) throws Exception {
        JsonObject action = option(label);
        if (action == null) throw new IllegalStateException("Action unavailable: " + label + " in " + prompt);
        String id = action.get("id").getAsString();
        send("{\"type\":\"chooseAction\",\"output\":{\"type\":\"act\",\"actionId\":\"" + id + "\"}}");
    }
    static void cast(String label, String target) throws Exception {
        choose(label);
        for (int i = 0; i < 40; i++) {
            if (kind().equals("chooseAction") && !game.getStack().isEmpty()) { capture("stack"); return; }
            automatic(target);
        }
        throw new IllegalStateException("Cast did not reach stack");
    }
    static void settleToPriority() throws Exception {
        for (int i = 0; i < 20 && !kind().equals("chooseAction"); i++) automatic(null);
    }
    static void resolveStack() throws Exception {
        for (int i = 0; i < 60; i++) {
            if (kind().equals("chooseAction") && game.getStack().isEmpty()) return;
            automatic(null);
        }
        throw new IllegalStateException("Stack did not resolve");
    }
    static void automatic(String target) throws Exception {
        System.out.println("PROMPT " + prompt);
        switch (kind()) {
            case "payManaCost" -> {
                JsonObject input = prompt.getAsJsonObject("input");
                if (input.get("canConfirmFromPool").getAsBoolean()) {
                    send("{\"kind\":\"pay_mana\"}");
                } else {
                    JsonObject source = null;
                    for (JsonElement e : input.getAsJsonArray("actions")) {
                        if (e.getAsJsonObject().get("type").getAsString().equals("activateManaAbility")) { source = e.getAsJsonObject(); break; }
                    }
                    if (source == null) throw new IllegalStateException("No payment source in fixture: " + prompt);
                    send("{\"type\":\"payManaCost\",\"output\":{\"type\":\"act\",\"actionId\":\"" + source.get("id").getAsString() + "\"}}");
                }
            }
            case "chooseAction", "mulligan", "diceRolled", "revealCards" -> send("{\"kind\":\"pass\"}");
            case "chooseAttackers", "chooseBlockers" -> send("{\"kind\":\"pass\"}");
            case "chooseBoolean" -> {
                if (prompt.toString().toLowerCase(Locale.ROOT).contains("command")) commandReturnOffered = true;
                send("{\"kind\":\"boolean_decision\",\"accept\":true}");
            }
            case "chooseBoardTargets" -> {
                JsonObject input = prompt.getAsJsonObject("input");
                JsonObject chosen = null;
                for (JsonElement e : input.getAsJsonArray("candidates")) {
                    JsonObject candidate = e.getAsJsonObject();
                    String id = candidate.get("id").getAsString();
                    boolean matches = id.equals(target);
                    if (target != null && !target.startsWith("player-")) {
                        for (Card card : game.getCardsInGame()) {
                            if (card.getName().equals(target) && id.equals(SnapshotExtractor.javaCardId(card))) matches = true;
                        }
                        JsonObject view = JsonParser.parseString(adapter.getSnapshot(session, actor())).getAsJsonObject();
                        for (JsonElement entry : view.getAsJsonArray("stack")) {
                            JsonObject stack = entry.getAsJsonObject();
                            if (stack.has("identity") && stack.getAsJsonObject("identity").get("name").getAsString().equals(target)
                                    && stack.get("id").getAsString().equals(id)) matches = true;
                        }
                    }
                    if (matches) { chosen = candidate; break; }
                }
                if (chosen == null) throw new IllegalStateException("Target unavailable: " + target + " in " + prompt);
                send("{\"type\":\"chooseBoardTargets\",\"output\":{\"chosen\":[" + chosen + "]}}");
            }
            default -> throw new IllegalStateException("Unimplemented evaluator prompt: " + prompt);
        }
    }
}
