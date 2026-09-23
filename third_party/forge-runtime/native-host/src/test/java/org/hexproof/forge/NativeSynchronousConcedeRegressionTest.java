// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import java.util.List;
import java.util.Set;
import java.util.HashSet;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import static org.hexproof.forge.NativeCallbackRegressionTest.require;

/** Real native opening/game loops, with a synchronous GUI menu injected at the native start hook. */
public final class NativeSynchronousConcedeRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                prefs.setPref(FPref.UI_SELECT_FROM_CARD_DISPLAYS, false);
                prefs.setPref(FPref.YIELD_AUTO_PASS_NO_ACTIONS, false);
                return null;
            });
            List<String> scenarios = args.length > 1 ? List.of(args[1]) : List.of(
                    "terminal-number", "terminal-name", "terminal-number-edt", "terminal-name-edt",
                    "terminal-other-number", "terminal-other-name-edt", "terminal-four-number",
                    "outside-number", "outside-name-edt", "owner-number", "owner-name-edt",
                    "surviving-number", "surviving-name-edt");
            for (String scenario : scenarios) try (NativeGuiBase scenarioBase = new NativeGuiBase(args[0])) {
                GuiBase.setInterface(scenarioBase.proxy());
                run(scenarioBase, scenario);
            }
        }
    }

    private static void run(NativeGuiBase base, String scenario) throws Exception {
        boolean terminal = scenario.startsWith("terminal");
        boolean naming = scenario.contains("name");
        boolean edt = scenario.endsWith("-edt");
        boolean ownerDeparture = scenario.startsWith("owner");
        boolean surviving = scenario.startsWith("surviving");
        int seats = terminal && !scenario.contains("-four-") ? 2 : 4;
        JsonObject config = NativeSession.object("gameId", "synchronous-concede-" + scenario);
        config.addProperty("seed", 42); config.addProperty("variant", "constructed");
        config.addProperty("startingLife", 20); config.addProperty("startingPlayerIndex", 0);
        JsonArray players = new JsonArray();
        for (int seat = 0; seat < seats; seat++) {
            JsonObject player = NativeSession.object("name", "Concede seat " + seat);
            JsonArray deck = new JsonArray();
            for (int count = 0; count < 60; count++) deck.add(NativeSession.object("name", "Forest"));
            player.add("deck", deck); players.add(player);
        }
        config.add("players", players);
        AtomicBoolean returned = new AtomicBoolean();
        AtomicBoolean cancelled = new AtomicBoolean();
        CountDownLatch unwound = new CountDownLatch(1);
        ExecutorService rpc = Executors.newSingleThreadExecutor();
        try (NativeSession session = new NativeSession(config, base); var scope = session.context.enter()) {
            base.setTestSession(session);
            Runnable menu = () -> {
                try {
                    if (surviving) {
                        var source = NativeCallbackRegressionTest.card(session.game, session.game.getRegisteredPlayers().get(2), "Pithing Needle", forge.game.zone.ZoneType.Hand);
                        var ability = source.getSpellAbilities().get(0);
                        ability.setActivatingPlayer(session.game.getRegisteredPlayers().get(2));
                        if (naming) {
                            var face = FModel.getMagicDb().getCommonCards().getCard("Pithing Needle").getRules().getMainPart();
                            var other = FModel.getMagicDb().getCommonCards().getCard("Lightning Bolt").getRules().getMainPart();
                            String answer = session.guis.get(0).human.chooseCardName(ability, List.of(face, other), "Name a card");
                            require(answer.equals("Lightning Bolt"), "Replacement chooser's card name was not returned to the native controller");
                        } else {
                            int answer = session.guis.get(0).human.chooseNumber(ability, "Choose a number", 1, Integer.MAX_VALUE);
                            require(answer == 7, "Replacement chooser's number was not returned to the native controller");
                        }
                    } else if (naming) {
                        var face = FModel.getMagicDb().getCommonCards().getCard("Pithing Needle").getRules().getMainPart();
                        var other = FModel.getMagicDb().getCommonCards().getCard("Lightning Bolt").getRules().getMainPart();
                        session.guis.get(0).proxy().one("Name a card", List.of(new forge.game.card.CardFaceView(face), new forge.game.card.CardFaceView(other)));
                    } else {
                        session.guis.get(0).proxy().getInteger("Choose a number", 1, 10, false);
                    }
                    returned.set(true);
                } catch (RuntimeException error) {
                    if (hasCause(error, CancellationException.class)) cancelled.set(true);
                    throw error;
                } finally { unwound.countDown(); }
            };
            Future<?> opening = rpc.submit(() -> session.start(() -> {
                if (!edt) menu.run();
                else {
                    try { base.andWait(menu); }
                    catch (Exception error) { throw new CompletionException(error); }
                }
            }));
            String expected = naming ? "chooseFromSelection" : "chooseNumber";
            String pending = awaitPrompt(session);
            while (!JsonParser.parseString(pending).getAsJsonObject().getAsJsonObject("input").get("type").getAsString().equals(expected)) {
                String type = JsonParser.parseString(pending).getAsJsonObject().getAsJsonObject("input").get("type").getAsString();
                require(type.equals("mulligan"), "Unexpected native opening prompt " + type);
                JsonObject keep = NativeSession.object("type", "mulliganDecision"); keep.addProperty("keep", true);
                submitAnswer(session, type, keep);
                pending = awaitPrompt(session);
            }
            opening.get(2, TimeUnit.SECONDS);
            JsonObject concession = NativeSession.object("type", "directive");
            int departing = scenario.contains("-other-") ? 1 : terminal || ownerDeparture || surviving ? 0 : 3;
            concession.addProperty("player", departing);
            concession.add("directive", NativeSession.object("type", "concede"));
            if (terminal && seats == 4) {
                for (int prior : List.of(3, 2)) {
                    JsonObject earlier = concession.deepCopy(); earlier.addProperty("player", prior);
                    rpc.submit(() -> session.submit(earlier)).get(2, TimeUnit.SECONDS);
                    require(session.prompt(0).equals(pending), "Nonterminal departures changed the original menu");
                }
            }
            Future<String> reply = rpc.submit(() -> session.submit(concession));
            Throwable rejected = null;
            try { reply.get(2, TimeUnit.SECONDS); }
            catch (TimeoutException error) {
                throw new AssertionError("Concession left the synchronous answer unresolved; no stable boundary within two seconds", error);
            } catch (ExecutionException error) { rejected = error; }
            if (surviving) {
                require(rejected == null, "Surviving object's chooser departure failed: " + rejected);
                JsonObject chooserPrompt = JsonParser.parseString(session.prompt(0)).getAsJsonObject();
                require(chooserPrompt.get("decidingPlayerId").getAsString().equals("player-2"), "Surviving object's controller did not choose the replacement player");
                JsonObject chooserInput = chooserPrompt.getAsJsonObject("input");
                String chooserType = chooserInput.get("type").getAsString();
                if (chooserType.equals("chooseBoardTargets")) {
                    JsonArray choices = chooserInput.getAsJsonArray("candidates");
                    require(choices.size() == 2, "Replacement candidates must retain the original opponent restriction");
                    Set<String> ids = new HashSet<>();
                    for (var choice : choices) ids.add(choice.getAsJsonObject().get("id").getAsString());
                    require(ids.equals(Set.of("player-1", "player-3")), "Native replacement candidates include an ineligible player");
                    JsonObject select = NativeSession.object("type", "boardTargets");
                    JsonArray chosen = new JsonArray();
                    JsonObject target = NativeSession.object("kind", "player"); target.addProperty("id", "player-3");
                    chosen.add(target); select.add("chosen", chosen);
                    require(!returned.get(), "Replacement was selected without its controller's input");
                    submitAnswer(session, chooserType, select);
                } else {
                    require(chooserType.equals("chooseFromSelection"), "Unexpected native replacement prompt " + chooserType);
                    JsonArray choices = chooserInput.getAsJsonArray("options");
                    require(choices.size() == 2, "Replacement candidates must retain the original opponent restriction");
                    int chosen = -1;
                    for (int index = 0; index < choices.size(); index++) {
                        String label = choices.get(index).getAsJsonObject().get("label").getAsString();
                        require(!label.contains("seat 0") && !label.contains("seat 2"), "Departed player or original controller became a replacement opponent");
                        if (label.contains("seat 3")) chosen = index;
                    }
                    require(chosen >= 0 && !returned.get(), "Replacement was selected without its controller's input");
                    JsonObject select = NativeSession.object("type", "selectionDecision");
                    JsonArray ids = new JsonArray(); ids.add(chosen); select.add("chosenIndices", ids);
                    submitAnswer(session, chooserType, select);
                }
                JsonObject handoff = JsonParser.parseString(session.prompt(0)).getAsJsonObject();
                require(handoff.get("decidingPlayerId").getAsString().equals("player-3"), "Original decision did not go to the explicitly chosen player");
                require(handoff.get("promptId").getAsLong() > chooserPrompt.get("promptId").getAsLong(), "Handoff reused a stale prompt id");
                JsonObject output = explicitAnswer(session, naming);

                submitAnswer(session, expected, output);
                require(unwound.await(2, TimeUnit.SECONDS) && returned.get() && !cancelled.get(), "Explicit replacement answer did not continue the native callback");
                require(!session.hasFailed() && !session.game.isGameOver(), "Handoff failed the game");
                for (int remaining : List.of(1, 3)) {
                    JsonObject cleanup = concession.deepCopy(); cleanup.addProperty("player", remaining);
                    rpc.submit(() -> session.submit(cleanup)).get(2, TimeUnit.SECONDS);
                }
                require(session.gameOver(), "Handoff test did not finish its cleanup game");
            } else if (ownerDeparture) {
                require(rejected == null, "Deciding player's departure failed: " + rejected);
                JsonObject reassigned = JsonParser.parseString(session.prompt(0)).getAsJsonObject();
                require(reassigned.get("decidingPlayerId").getAsString().equals("player-1"), "Rule choice did not pass to the next surviving seat");
                require(reassigned.get("promptId").getAsLong() > JsonParser.parseString(pending).getAsJsonObject().get("promptId").getAsLong(), "Reassigned prompt reused its old id");
                require(!returned.get() && !cancelled.get() && !session.game.isGameOver(), "Departure invented a choice or ended the game");
                JsonObject output = explicitAnswer(session, naming);

                submitAnswer(session, expected, output);
                require(unwound.await(2, TimeUnit.SECONDS) && returned.get() && !cancelled.get(), "Successor could not explicitly answer the rule choice");
                require(JsonParser.parseString(session.prompt(0)).getAsJsonObject().getAsJsonObject("input").get("type").getAsString().equals("chooseAction"), "Remaining native game did not reach priority");
                for (int remaining : List.of(2, 1)) {
                    JsonObject cleanup = concession.deepCopy(); cleanup.addProperty("player", remaining);
                    rpc.submit(() -> session.submit(cleanup)).get(2, TimeUnit.SECONDS);
                }
                require(session.gameOver(), "Multiplayer test did not finish its cleanup game");
            } else {
                require(rejected == null, "Supported concession failed: " + rejected);
                if (terminal) {
                    require(session.gameOver(), "Native terminal outcome was not published");
                    require(session.prompt(0).isEmpty(), "Terminal game retained the abandoned private prompt");
                    require(unwound.await(2, TimeUnit.SECONDS) && cancelled.get() && !returned.get(), "Terminal concession chose a default answer or retained the blocked menu");
                    JsonObject snapshot = JsonParser.parseString(session.snapshot(-1)).getAsJsonObject();
                    require(snapshot.get("winnerId").getAsString().equals("player-" + (1 - departing)), "Concession changed the engine's winning seat");
                } else {
                    require(session.prompt(0).equals(pending), "Another player's concession changed the pending decision");
                    require(!cancelled.get() && !returned.get(), "Unrelated concession answered or cancelled the menu");
                    JsonObject output = explicitAnswer(session, naming);

                    submitAnswer(session, expected, output);
                    require(unwound.await(2, TimeUnit.SECONDS) && returned.get() && !cancelled.get(), "Original native menu could not accept its explicit response");
                    require(JsonParser.parseString(session.prompt(0)).getAsJsonObject().getAsJsonObject("input").get("type").getAsString().equals("chooseAction"), "Native game did not continue to priority after the menu");
                    // Finish through Forge before releasing the GUI dispatcher;
                    // simply closing a live priority loop can schedule further
                    // upstream presentation callbacks during test teardown.
                    for (int remaining : List.of(2, 1)) {
                        JsonObject cleanup = concession.deepCopy(); cleanup.addProperty("player", remaining);
                        rpc.submit(() -> session.submit(cleanup)).get(2, TimeUnit.SECONDS);
                    }
                    require(session.gameOver(), "Supported multiplayer test did not finish its cleanup game");
                }
            }
            System.out.println("PASS synchronous concession " + scenario);
        } finally {
            rpc.shutdownNow();
            require(rpc.awaitTermination(2, TimeUnit.SECONDS), "Concession RPC thread survived session cleanup");
            require(unwound.await(2, TimeUnit.SECONDS), "Synchronous game callback survived session cleanup");
        }
    }

    private static String awaitPrompt(NativeSession session) throws Exception {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10);
        String pending;
        while ((pending = session.prompt(0)).isEmpty()) {
            if (System.nanoTime() > deadline) throw new AssertionError("Synchronous GUI menu did not appear");
            Thread.sleep(5);
        }
        return pending;
    }
    private static JsonObject explicitAnswer(NativeSession session, boolean naming) {
        JsonObject output = NativeSession.object("type", naming ? "selectionDecision" : "numberDecision");
        if (naming) {
            JsonArray options = JsonParser.parseString(session.prompt(0)).getAsJsonObject().getAsJsonObject("input").getAsJsonArray("options");
            require(options.size() == 2, "Restricted name choice lost its explicit legal options");
            JsonArray indices = new JsonArray();
            for (int i = 0; i < options.size(); i++)
                if (options.get(i).getAsJsonObject().get("label").getAsString().equals("Lightning Bolt")) indices.add(i);
            require(indices.size() == 1, "Replacement chooser cannot name Lightning Bolt");
            output.add("chosenIndices", indices);
        } else output.addProperty("chosenNumber", 7);
        return output;
    }

    private static void submitAnswer(NativeSession session, String type, JsonObject output) {
        JsonObject response = NativeSession.object("type", type); response.add("output", output);
        session.submit(response);
    }
    private static boolean hasCause(Throwable error, Class<? extends Throwable> kind) {
        for (Throwable cause = error; cause != null; cause = cause.getCause()) if (kind.isInstance(cause)) return true;
        return false;
    }
    private static String exceptionText(Throwable error) {
        StringBuilder text = new StringBuilder();
        for (Throwable cause = error; cause != null; cause = cause.getCause()) text.append(cause).append('\n');
        return text.toString();
    }
}
