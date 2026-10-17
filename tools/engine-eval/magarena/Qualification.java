// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package magic.model.choice;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.List;
import java.util.function.BooleanSupplier;
import java.util.function.Predicate;
import magic.data.CardDefinitions;
import magic.test.TestGameBuilder;
import magic.model.*;
import magic.model.choice.*;
import magic.model.event.*;
import magic.model.phase.*;
import magic.model.stack.MagicItemOnStack;
import org.json.JSONArray;
import org.json.JSONObject;

/** Test-only external decisions; direct setup follows upstream TestGameBuilder. */
public final class Qualification {
    private static JSONObject observation;
    private static JSONArray assertions;
    private static JSONArray decisions;
    private static MagicGame game;
    private static Object preferredTarget;
    private static boolean combat;
    private static MagicEvent pending;
    private static long pendingId;

    private static void check(String name, boolean passed) {
        assertions.put(new JSONObject().put("name", name).put("passed", passed));
        if (!passed) throw new AssertionError(name);
    }

    private static MagicGame fixture() {
        game = TestGameBuilder.createDuel().nextGame(17, 31, false);
        game.setPhase(MagicMainPhase.getFirstInstance());
        for (MagicPlayer player : game.getPlayers()) {
            player.setLife(20);
            if (!player.getHand().isEmpty()) throw new IllegalStateException("Expected empty upstream test deck");
            player.getLibrary().clear();
            TestGameBuilder.addToLibrary(player, "Plains", 30);
        }
        preferredTarget = null;
        combat = false;
        pending = null;
        return game;
    }

    private static MagicPlayer p(int seat) { return game.getPlayer(seat); }
    private static MagicPermanent permanent(int seat, String name) {
        return TestGameBuilder.createPermanent(p(seat), name);
    }
    private static void hand(int seat, String name) { TestGameBuilder.addToHand(p(seat), name); }
    private static String name(Object card) {
        return card instanceof MagicSource ? ((MagicSource) card).getName() : ((MagicItemOnStack) card).getName();
    }
    private static long count(Iterable<?> cards, String name) {
        long result = 0;
        for (Object card : cards) if (name(card).equals(name)) result++;
        return result;
    }
    private static boolean contains(Object value, Object target) {
        if (value == target) return true;
        if (value instanceof Object[]) {
            for (Object child : (Object[]) value) if (contains(child, target)) return true;
        }
        if (value instanceof Iterable<?>) {
            for (Object child : (Iterable<?>) value) if (contains(child, target)) return true;
        }
        return false;
    }
    private static void submit(MagicEvent event, Object[] choice) {
        decisions.put(new JSONObject().put("actor", event.getPlayer().getIndex())
            .put("event", event.toString()).put("choice", Arrays.deepToString(choice)));
        if (!respond(event.getPlayer().getIndex(), pendingId, event, choice)) throw new IllegalStateException("Host rejected its current owner response");
    }
    private static boolean respond(int actor, long id, MagicEvent event, Object[] choice) {
        // Test-only external host contract, not native Magarena authentication.
        if (event != pending || !game.hasNextEvent() || game.getNextEvent() != pending || id != pendingId || actor != pending.getPlayer().getIndex()) return false;
        game.executeNextEvent(choice);
        pending = null;
        return true;
    }
    private static MagicEvent next() {
        if (!game.advanceToNextEventWithChoice()) throw new IllegalStateException("Game ended before expected decision");
        MagicEvent event = game.getNextEvent();
        if (pending != event) { pending = event; pendingId++; }
        return event;
    }
    private static List<MagicSourceActivation<? extends MagicSource>> activations(MagicEvent event, String name) {
        List<MagicSourceActivation<? extends MagicSource>> result = new ArrayList<>();
        for (MagicSourceActivation<? extends MagicSource> activation : event.getPlayer().getSourceActivations()) {
            if (activation.source.getName().equals(name) && activation.canPlay(game, event.getPlayer(), false)) result.add(activation);
        }
        return result;
    }
    private static Object[] automatic(MagicEvent event) {
        if (event instanceof MagicPriorityEvent) return new Object[]{MagicPlayChoiceResult.PASS};
        if (event.getChoice() instanceof MagicMulliganChoice) return new Object[]{MagicChoice.NO_CHOICE};
        List<Object[]> choices = event.getArtificialChoiceResults(game);
        if (choices.isEmpty()) throw new IllegalStateException("No generated legal choice for " + event);
        if (preferredTarget != null) {
            for (Object[] choice : choices) if (contains(choice, preferredTarget)) return choice;
        }
        if (event.getChoice() instanceof MagicMulliganChoice) {
            for (Object[] choice : choices) if (choice.length > 0 && MagicChoice.isNoChoice(choice[0])) return choice;
        }
        if (combat && (event.getChoice() instanceof MagicDeclareAttackersChoice || event.getChoice() instanceof MagicDeclareBlockersChoice)) {
            for (Object[] choice : choices) {
                if (choice.length == 1 && choice[0] instanceof Collection<?> && !((Collection<?>) choice[0]).isEmpty()) return choice;
            }
            throw new IllegalStateException("Expected nonempty legal combat choice: " + event);
        }
        return choices.get(0);
    }
    private static void advanceUntil(BooleanSupplier done) {
        for (int step = 0; step < 250; step++) {
            if (done.getAsBoolean()) return;
            MagicEvent event = next();
            if (done.getAsBoolean()) return;
            submit(event, automatic(event));
        }
        throw new IllegalStateException("Bounded decision limit exceeded");
    }
    private static void cast(int seat, String name, Object target) {
        preferredTarget = target;
        for (int step = 0; step < 40; step++) {
            MagicEvent event = next();
            if (event instanceof MagicPriorityEvent && event.getPlayer() == p(seat)) {
                List<MagicSourceActivation<? extends MagicSource>> available = activations(event, name);
                if (available.isEmpty()) throw new IllegalStateException("Named card has no human-legal activation: " + name + " at " + event);
                MagicSourceActivation<? extends MagicSource> selected = available.get(0);
                observation.put("selectedActivation", selected.activation.getText());
                submit(event, new Object[]{new MagicPlayChoiceResult(selected)});
                advanceUntil(() -> count(game.getStack(), name) > 0 || count(p(seat).getPermanents(), name) > 0);
                return;
            }
            submit(event, automatic(event));
        }
        throw new IllegalStateException("No priority for requested actor");
    }
    private static void settle() {
        advanceUntil(() -> game.getStack().isEmpty() && game.hasNextEvent() && game.getNextEvent() instanceof MagicPriorityEvent);
        game.update();
    }
    private static JSONObject state() {
        JSONObject out = new JSONObject().put("phase", game.getPhase().getType().toString());
        JSONArray players = new JSONArray();
        for (MagicPlayer player : game.getPlayers()) {
            JSONObject one = new JSONObject().put("seat", player.getIndex()).put("life", player.getLife());
            one.put("hand", names(player.getHand())).put("library", names(player.getLibrary()))
                .put("graveyard", names(player.getGraveyard())).put("exile", names(player.getExile()));
            JSONArray board = new JSONArray();
            for (MagicPermanent card : player.getPermanents()) {
                board.put(new JSONObject().put("id", card.getId()).put("name", card.getName()).put("tapped", card.isTapped())
                    .put("power", card.getPower()).put("toughness", card.getToughness()).put("token", card.isToken()));
            }
            one.put("battlefield", board);
            players.put(one);
        }
        return out.put("players", players).put("stack", names(game.getStack()));
    }
    private static JSONArray names(Iterable<?> cards) {
        JSONArray out = new JSONArray();
        for (Object card : cards) out.put(name(card));
        return out;
    }
    private static void opening() {
        MagicDuel duel = TestGameBuilder.createDuel();
        for (DuelPlayerConfig player : duel.getPlayers()) {
            player.getDeck().clear();
            for (int i = 0; i < 60; i++) player.getDeck().add(CardDefinitions.getCard("Plains"));
        }
        game = duel.nextGame(17, 31, false);
        int keeps = 0;
        for (int step = 0; step < 100; step++) {
            MagicEvent event = next();
            if (game.isPhase(MagicPhaseType.FirstMain) && event instanceof MagicPriorityEvent) break;
            if (event.getChoice() instanceof MagicMulliganChoice) keeps++;
            submit(event, automatic(event));
        }
        observation.put("keepDecisions", keeps);
        check("Both hands contain seven", p(0).getHandSize() == 7 && p(1).getHandSize() == 7);
        check("Both libraries contain 53", p(0).getLibrary().size() == 53 && p(1).getLibrary().size() == 53);
        check("Starting player skipped first draw after real keeps", keeps == 2 && p(0).getHandSize() == 7);
        check("Player 0 owns first main decision", game.isPhase(MagicPhaseType.FirstMain) && game.getNextEvent().getPlayer() == p(0));
    }
    private static void land() {
        fixture(); hand(0, "Plains"); hand(0, "Plains");
        MagicEvent first = next();
        Object[] legal = {new MagicPlayChoiceResult(activations(first, "Plains").get(0))};
        long initial = game.getStateId();
        boolean wrongActor = !respond(1, pendingId, first, legal) && game.getStateId() == initial;
        boolean wrongId = !respond(0, pendingId + 1, first, legal) && game.getStateId() == initial;
        cast(0, "Plains", null);
        MagicEvent event = next();
        check("Exactly one Plains moves from hand to battlefield", p(0).getHandSize() == 1 && count(p(0).getPermanents(), "Plains") == 1);
        long before = game.getStateId();
        check("Second Plains has no legal activation and lookup is nonmutating", activations(event, "Plains").isEmpty() && before == game.getStateId());
        check("Host rejects wrong actor and stale decision ID without mutation", wrongActor && wrongId);
        observation.put("actorBoundary", "TEST-ONLY HOST-ADDED actor/id validation around native executeNextEvent(Object[]); accepted owner actually plays land. This is not native engine seat authentication.");
        observation.put("statusHint", "PASS").put("layerHint", "adapter")
            .put("limitation", "Native legal land paths plus explicitly host-added pending actor/id validation passed all frozen assertions");
    }
    private static void bolt(boolean creature, boolean replacement) {
        fixture();
        if (replacement) permanent(0, "Rest in Peace");
        MagicPermanent mountain = permanent(0, "Mountain");
        MagicPermanent bears = creature ? permanent(1, "Grizzly Bears") : null;
        hand(0, "Lightning Bolt");
        cast(0, "Lightning Bolt", creature ? bears : p(1));
        observation.put("beforeResolution", state());
        if (!creature) check("Target is 20 and Bolt is on stack before resolution", p(1).getLife() == 20 && count(game.getStack(), "Lightning Bolt") == 1);
        settle();
        if (replacement) {
            check("Bears is exiled, not graveyard", count(p(1).getExile(), "Grizzly Bears") == 1 && p(1).getGraveyard().isEmpty());
            check("Bolt is exiled, not graveyard", count(p(0).getExile(), "Lightning Bolt") == 1 && p(0).getGraveyard().isEmpty());
            check("Both graveyards empty", p(0).getGraveyard().isEmpty() && p(1).getGraveyard().isEmpty());
        } else if (creature) {
            check("Both Bears and Bolt in owners graveyards", count(p(1).getGraveyard(), "Grizzly Bears") == 1 && count(p(0).getGraveyard(), "Lightning Bolt") == 1);
            check("Player 1 life unchanged", p(1).getLife() == 20);
            check("No Bears on battlefield", count(p(1).getPermanents(), "Grizzly Bears") == 0);
        } else {
            check("Exactly three damage", p(1).getLife() == (Boolean.getBoolean("hexproof.eval.negativeControl") ? 18 : 17));
            check("Bolt graveyard and Mountain tapped", count(p(0).getGraveyard(), "Lightning Bolt") == 1 && mountain.isTapped());
        }
    }
    private static void counterspell() {
        fixture(); permanent(0, "Mountain"); permanent(1, "Island"); permanent(1, "Island");
        hand(0, "Lightning Bolt"); hand(1, "Counterspell");
        cast(0, "Lightning Bolt", p(1));
        MagicItemOnStack bolt = game.getStack().getFirst();
        cast(1, "Counterspell", bolt);
        observation.put("beforeResolution", state());
        check("Counterspell above Bolt", game.getStack().size() == 2 && game.getStack().getFirst().getName().equals("Counterspell") && game.getStack().getLast() == bolt);
        settle();
        check("No damage dealt", p(0).getLife() == 20 && p(1).getLife() == 20);
        check("Both spells in graveyards and empty stack", count(p(0).getGraveyard(), "Lightning Bolt") == 1 && count(p(1).getGraveyard(), "Counterspell") == 1 && game.getStack().isEmpty());
    }
    private static void visionary() {
        fixture(); permanent(0, "Forest"); permanent(0, "Plains"); hand(0, "Elvish Visionary");
        cast(0, "Elvish Visionary", null);
        advanceUntil(() -> count(p(0).getPermanents(), "Elvish Visionary") == 1);
        observation.put("afterCreatureBeforeTrigger", state());
        boolean trigger = !game.getStack().isEmpty() && p(0).getLibrary().size() == 30;
        settle();
        check("Visionary on battlefield", count(p(0).getPermanents(), "Elvish Visionary") == 1);
        check("Exactly one card drawn without draw step", p(0).getHandSize() == 1 && p(0).getLibrary().size() == 29 && game.isPhase(MagicPhaseType.FirstMain));
        check("ETB observed on stack after creature before draw", trigger);
    }
    private static void combat() {
        fixture(); permanent(0, "Grizzly Bears"); permanent(1, "Grizzly Bears"); combat = true;
        advanceUntil(() -> game.isPhase(MagicPhaseType.SecondMain));
        check("Both Bears die", p(0).getPermanents().isEmpty() && p(1).getPermanents().isEmpty());
        check("Both life totals unchanged", p(0).getLife() == 20 && p(1).getLife() == 20);
        check("Each Bears in owners graveyard", count(p(0).getGraveyard(), "Grizzly Bears") == 1 && count(p(1).getGraveyard(), "Grizzly Bears") == 1);
    }
    private static void tokens() {
        fixture(); permanent(0, "Plains"); permanent(0, "Plains"); hand(0, "Raise the Alarm");
        cast(0, "Raise the Alarm", null); settle();
        List<MagicPermanent> tokens = new ArrayList<>();
        for (MagicPermanent card : p(0).getPermanents()) if (card.isToken()) tokens.add(card);
        check("Exactly two white 1/1 Soldier creature tokens", tokens.size() == 2 && tokens.stream().allMatch(card -> card.isCreature() && card.getPower() == 1 && card.getToughness() == 1 && card.hasColor(MagicColor.White) && card.hasSubType(MagicSubType.Soldier)));
        check("Raise the Alarm in graveyard", count(p(0).getGraveyard(), "Raise the Alarm") == 1);
        check("No token consumed from library or hand", p(0).getLibrary().size() == 30 && p(0).getHandSize() == 0);
    }
    private static void copy() {
        fixture(); MagicPermanent bears = permanent(1, "Grizzly Bears");
        permanent(0, "Forest"); permanent(0, "Island");
        for (int i = 0; i < 3; i++) permanent(0, "Plains");
        hand(0, "Giant Growth"); hand(0, "Clone");
        cast(0, "Giant Growth", bears); settle();
        observation.put("afterGrowth", state());
        cast(0, "Clone", bears); settle();
        List<MagicPermanent> copies = new ArrayList<>();
        for (MagicPermanent card : p(0).getPermanents()) if (card.isCreature()) copies.add(card);
        check("Clone enters as Bears", copies.size() == 1 && copies.get(0).getName().equals("Grizzly Bears"));
        check("Clone is 2/2", copies.get(0).getPower() == 2 && copies.get(0).getToughness() == 2);
        check("Original remains 5/5", bears.getPower() == 5 && bears.getToughness() == 5);
    }
    private static void fourPlayers() {
        MagicDuel duel = TestGameBuilder.createDuel();
        DuelPlayerConfig[] configs = duel.getPlayers();
        duel.setPlayers(new DuelPlayerConfig[]{configs[0], configs[1], configs[0], configs[1]});
        game = duel.nextGame(17, 31, false);
        observation.put("requestedPlayerConfigs", duel.getNrOfPlayers()).put("actualGamePlayers", game.getPlayers().length);
        observation.put("statusHint", "UNSUPPORTED").put("layerHint", "engine")
            .put("limitation", "Actual MagicDuel with four configured seats constructs only two game players; canonical four-player continuation cannot be instantiated");
        check("Four-seat configuration actually attempted", duel.getNrOfPlayers() == 4);
        check("Actual game is limited to two seats", game.getPlayers().length == 2);
    }
    private static void catalog(String name) {
        fixture();
        try {
            hand(0, name);
            observation.put("catalogLoaded", true).put("statusHint", "UNVERIFIED").put("layerHint", "fixture")
                .put("limitation", "Catalog entry loaded; scenario adapter not yet implemented");
        } catch (RuntimeException error) {
            observation.put("catalogLoaded", false).put("catalogError", error.toString())
                .put("statusHint", "UNSUPPORTED").put("layerHint", "engine")
                .put("limitation", "Pinned actual card catalog cannot load the named canonical card; no substitute card or synthetic implementation used");
        }
    }
    private static void prepareCatalog() {
        fixture();
        JSONArray lookups = new JSONArray();
        boolean missing = false;
        for (String name : new String[]{"Goblin Glasswright", "Craft with Pride"}) {
            JSONObject lookup = new JSONObject().put("name", name);
            try {
                lookup.put("loaded", true).put("actualName", CardDefinitions.getCard(name).getName());
            } catch (RuntimeException error) {
                missing = true;
                lookup.put("loaded", false).put("error", error.toString());
            }
            lookups.put(lookup);
        }
        boolean sos = Arrays.stream(magic.data.MagicSets.values()).anyMatch(set -> set.name().equals("SOS"));
        boolean prepare = Arrays.stream(MagicAbility.values()).anyMatch(ability -> ability.name().equalsIgnoreCase("Prepare"));
        observation.put("cardLookups", lookups).put("SOSRegistered", sos).put("PrepareAbilityRegistered", prepare)
            .put("statusHint", missing ? "UNSUPPORTED" : "UNVERIFIED").put("layerHint", missing ? "engine" : "fixture")
            .put("limitation", missing ? "Actual pinned CardDefinitions lookup rejects the exact Prepare cards; SOS and Prepare enum probes are separate supporting observations. No substitute card or new mechanic implementation is injected; frozen casting/removal actions cannot begin." : "Cards exist; full Prepare fixture requires implementation.");
    }
    private static JSONObject project(int viewer) {
        JSONArray players = new JSONArray();
        for (MagicPlayer player : game.getPlayers()) {
            JSONObject one = new JSONObject().put("seat", player.getIndex()).put("life", player.getLife());
            JSONObject hand = new JSONObject().put("count", player.getHandSize());
            if (viewer == player.getIndex()) hand.put("cards", names(player.getHand()));
            one.put("hand", hand).put("library", new JSONObject().put("count", player.getLibrary().size()));
            one.put("graveyard", names(player.getGraveyard())).put("exile", names(player.getExile()));
            one.put("battlefield", names(player.getPermanents()));
            players.put(one);
        }
        return new JSONObject().put("viewer", viewer).put("players", players).put("stack", names(game.getStack()));
    }
    private static JSONArray libraryIds(int seat) {
        JSONArray ids = new JSONArray();
        for (MagicCard card : p(seat).getLibrary()) ids.put(card.getId());
        return ids;
    }
    private static void hidden() {
        fixture(); hand(0, "Shock"); hand(1, "Healing Salve");
        p(0).getLibrary().removeCardAtTop(); TestGameBuilder.addToLibrary(p(0), "Ancestral Recall");
        p(1).getLibrary().removeCardAtTop(); TestGameBuilder.addToLibrary(p(1), "Counterspell");
        MagicPermanent bears = permanent(1, "Grizzly Bears");
        JSONArray views = new JSONArray();
        for (int viewer : new int[]{0, 1, -1}) views.put(project(viewer));
        observation.put("nativeTrustedModelNotAProjection", state()).put("hostRemediationBefore", views);
        check("Host owner projection identifies own hand", project(0).toString().contains("Shock") && project(1).toString().contains("Healing Salve"));
        check("Host opponent and spectator do not expose secret hand names or nested text", !project(0).toString().contains("Healing Salve") && !project(1).toString().contains("Shock") && !project(-1).toString().contains("Shock") && !project(-1).toString().contains("Healing Salve"));
        check("Host library projection is count-only for every viewer", !views.toString().contains("Ancestral Recall") && !views.toString().contains("Counterspell"));
        check("Host public Bears and public counts retained", project(-1).toString().contains("Grizzly Bears") && project(-1).getJSONArray("players").getJSONObject(1).getJSONObject("library").getInt("count") == 30);
        permanent(0, "Island"); permanent(0, "Plains"); permanent(0, "Plains");
        MagicPermanent myr = permanent(1, "Myr Mindservant"); permanent(1, "Plains"); permanent(1, "Plains");
        hand(0, "Time Ebb"); cast(0, "Time Ebb", bears); settle();
        long knownId = bears.getCard().getId();
        JSONArray before = libraryIds(1);
        check("Real Time Ebb moved known public card to library top", p(1).getLibrary().getCardAtTop().getId() == knownId);
        for (int step = 0; step < 30; step++) {
            MagicEvent event = next();
            if (event instanceof MagicPriorityEvent && event.getPlayer() == p(1)) {
                MagicSourceActivation<? extends MagicSource> activation = activations(event, "Myr Mindservant").get(0);
                submit(event, new Object[]{new MagicPlayChoiceResult(activation)});
                advanceUntil(() -> count(game.getStack(), "Myr Mindservant") > 0);
                break;
            }
            submit(event, automatic(event));
        }
        settle();
        JSONArray after = libraryIds(1);
        views = new JSONArray();
        boolean countOnly = true;
        for (int viewer : new int[]{0, 1, -1}) {
            JSONObject view = project(viewer);
            views.put(view);
            countOnly &= view.getJSONArray("players").getJSONObject(1).getJSONObject("library").length() == 1;
        }
        check("Actual paid Myr ability taps and changes ordered library IDs", myr.isTapped() && !before.toString().equals(after.toString()));
        check("Host projections expose no post-shuffle library identity or order", countOnly);
        observation.put("knownPublicCardId", knownId).put("oracleOnlyBeforeShuffleIds", before).put("oracleOnlyAfterShuffleIds", after)
            .put("hostRemediationAfterShuffle", views).put("hostRemediationStatus", "PASS")
            .put("statusHint", "UNSUPPORTED").put("layerHint", "adapter")
            .put("limitation", "Native API has no serialized per-viewer DTO (trusted model is not a network leak). Separately executed whitelist host redactor passes the frozen privacy fixture and real paid post-shuffle tracking test. Host remediation is test-only, not native privacy certification.");
    }
    private static boolean hadFailure = false;
    private static void run(String id, Runnable action) {
        observation = new JSONObject(); assertions = new JSONArray(); decisions = new JSONArray();
        game = null; preferredTarget = null; combat = false;
        JSONObject result = new JSONObject().put("id", id);
        try { action.run(); }
        catch (AssertionError error) { result.put("error", error.toString()).put("errorKind", "assertion"); }
        catch (Throwable error) {
            result.put("error", error.toString()).put("errorKind", "execution");
            error.printStackTrace(System.err);
        }
        if (game != null) observation.put("final", state());
        if (Boolean.getBoolean("hexproof.eval.negativeControl")) observation.put("negativeControl", true);
        hadFailure |= result.has("error");
        result.put("observed", observation).put("assertions", assertions).put("decisions", decisions);
        System.out.println("HEXPROOF_OBSERVATION " + result.toString());
    }
    public static void main(String[] args) {
        magic.data.GeneralConfig.getInstance().load();
        List<String> chosen = Arrays.asList(args);
        String[] ids = {"opening", "land_priority", "bolt_player", "bolt_creature", "counterspell", "etb_draw", "blocked_combat", "hidden_views", "four_player_departure", "commander_tax", "commander_damage", "adventure", "modal_dfc", "morph", "replacement", "copy", "tokens"};
        Runnable[] cases = {Qualification::opening, Qualification::land, () -> bolt(false, false), () -> bolt(true, false), Qualification::counterspell, Qualification::visionary, Qualification::combat, Qualification::hidden, Qualification::fourPlayers, Qualification::fourPlayers, Qualification::fourPlayers, () -> catalog("Lovestruck Beast"), () -> catalog("Bala Ged Recovery"), () -> catalog("Willbender"), () -> bolt(true, true), Qualification::copy, Qualification::tokens};
        for (int i = 0; i < ids.length; i++) if (chosen.isEmpty() || chosen.contains(ids[i])) run(ids[i], cases[i]);
        for (String id : new String[]{"prepare_cast", "prepare_source_leaves"}) if (chosen.contains(id)) run(id, Qualification::prepareCatalog);
        magic.ui.MagicSound.shutdown();
        System.out.println("HEXPROOF_RUN_COMPLETE");
        if (hadFailure) System.exit(1);
    }
}
