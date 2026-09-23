// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.ai.*;
import forge.ai.ability.DamageDealAi;
import forge.game.GameStage;
import forge.game.card.Card;
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import forge.util.MyRandom;
import java.util.List;
import java.util.Random;
import java.util.concurrent.atomic.AtomicBoolean;
import forge.util.ThreadUtil;
import static org.hexproof.forge.NativeCallbackRegressionTest.*;

/** Native AI strategy, stable seat mapping and mixed-controller lifecycle checks. */
public final class NativeAiRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                prefs.setPref(FPref.YIELD_AUTO_PASS_NO_ACTIONS, false);
                prefs.setPref(FPref.UI_ENABLE_AI_CHEATS, false);
                return null;
            });
            rejectInvalid(base);
            timeoutFailure(base);
            deckAdvisory(base);
            for (String tier : List.of("easy", "normal", "hard")) {
                tactics(base, tier);
                for (int aiSeat = 0; aiSeat < 2; aiSeat++) lifecycle(base, tier, aiSeat);
            }
        }
        System.out.println("PASS native AI: tactical tiers, default parity, both seats, privacy, concession and cleanup");
    }

    private static void timeoutFailure(NativeGuiBase base) {
        try (NativeSession session = new NativeSession(setup("hard", 1), base)) {
            boolean rejected = false;
            try { session.awaitBoundary(5, java.util.concurrent.TimeUnit.MILLISECONDS); }
            catch (IllegalStateException expected) { rejected = true; }
            require(rejected && session.hasFailed(), "Expired native boundary did not make the session fatal");
            try { session.prompt(0); throw new AssertionError("Failed session still allowed a prompt"); }
            catch (IllegalStateException expected) { }
        }
    }

    static JsonObject setup(String tier, int aiSeat) {
        JsonObject setup = NativeIsolationRegressionTest.setup("native-ai-" + tier + "-" + aiSeat, 42);
        setup.getAsJsonArray("players").get(aiSeat).getAsJsonObject().addProperty("ai", true);
        setup.getAsJsonArray("players").get(aiSeat).getAsJsonObject().addProperty("aiDifficulty", tier);
        return setup;
    }

    private static void deckAdvisory(NativeGuiBase base) {
        JsonObject config = setup("hard", 1);
        JsonObject aiConfig = config.getAsJsonArray("players").get(1).getAsJsonObject();
        aiConfig.getAsJsonArray("deck").set(59, NativeSession.object("name", "Prismatic Ending"));
        JsonArray sideboard = new JsonArray();
        sideboard.add(NativeSession.object("name", "Wrath of the Skies"));
        aiConfig.add("sideboard", sideboard);
        try (NativeSession session = new NativeSession(config, base)) {
            session.start();
            String original = session.prompt(0);
            JsonObject prompt = JsonParser.parseString(original).getAsJsonObject();
            JsonObject input = prompt.getAsJsonObject("input");
            require(input.get("type").getAsString().equals("acknowledge"),
                    "AI deck advisory must be one acknowledgement, not a boolean choice: " + input);
            JsonObject presentation = input.getAsJsonObject("presentation");
            require(presentation.get("title").getAsString().equals("AI deck advisory"), "Missing advisory heading");
            String detail = presentation.get("description").getAsString();
            require(detail.contains("\n=== Main Deck ===\nPrismatic Ending")
                    && detail.contains("\n=== Sideboard ===\nWrath of the Skies")
                    && detail.contains("You can continue this game."), "Advisory lost card names, sections or continuation");
            Player ai = session.game.getRegisteredPlayers().get(1);
            require(ai.getCardsIn(ZoneType.Library).size() == 60 && ai.getCardsIn(ZoneType.Sideboard).size() == 1,
                    "Advisory altered registered deck sizes");
            require(session.prompt(0).equals(original), "Notice was automatically dismissed");
            JsonObject answer = NativeSession.object("type", "acknowledge");
            answer.add("output", NativeSession.object("type", "decision"));
            try { session.submit(answer); throw new AssertionError("Notice accepted a boolean response"); }
            catch (IllegalArgumentException expected) { }
            require(!session.hasFailed() && session.prompt(0).equals(original), "Invalid acknowledgement consumed the notice");
            answer.add("output", NativeSession.object("type", "acknowledged"));
            session.submit(answer);
            JsonObject next = JsonParser.parseString(session.prompt(0)).getAsJsonObject().getAsJsonObject("input");
            require(next.get("type").getAsString().equals("mulligan"), "Acknowledgement did not reach opening hands: " + next);
            require(ai.getCardsIn(ZoneType.Library).stream().anyMatch(c -> c.getName().equals("Prismatic Ending"))
                    || ai.getCardsIn(ZoneType.Hand).stream().anyMatch(c -> c.getName().equals("Prismatic Ending")),
                    "Advisory removed the main-deck card");
            require(ai.getCardsIn(ZoneType.Sideboard).stream().anyMatch(c -> c.getName().equals("Wrath of the Skies")),
                    "Advisory removed the sideboard card");
        }
        System.out.println("PASS native AI deck advisory: one explicit acknowledgement, unchanged decks and opening hand");
    }

    private static void rejectInvalid(NativeGuiBase base) {
        for (String invalid : List.of("", "Default", "expert")) {
            boolean rejected = false;
            try (NativeSession ignored = new NativeSession(setup(invalid, 1), base)) { }
            catch (IllegalArgumentException expected) { rejected = true; }
            require(rejected, "Unknown difficulty was accepted");
        }
        JsonObject setup = setup("hard", 1);
        setup.getAsJsonArray("players").get(0).getAsJsonObject().addProperty("ai", true);
        boolean rejected = false;
        try (NativeSession ignored = new NativeSession(setup, base)) { }
        catch (IllegalArgumentException expected) { rejected = true; }
        require(rejected, "Production accepted two AI seats");
    }

    private static void tactics(NativeGuiBase base, String tier) {
        try (NativeSession session = new NativeSession(setup(tier, 1), base); var scope = session.context.enter()) {
            Player ai = session.game.getRegisteredPlayers().get(1);
            PlayerControllerAi controller = (PlayerControllerAi) ai.getController();
            require(!controller.getAi().usesFullSimulation(), "AI unexpectedly enabled simulation");
            LobbyPlayerAi official = new LobbyPlayerAi("Official", null);
            official.setAiProfile("Default");
            if (tier.equals("hard")) for (AiProps property : AiProps.values())
                require(AiProfileUtil.getAIProp(ai.getLobbyPlayer(), property).equals(AiProfileUtil.getAIProp(official, property)),
                        "Hard changed official Default: " + property);
            session.game.setAge(GameStage.Play);
            session.game.setStartingPlayer(ai);
            session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, ai, false, 5);
            Card first = card(session.game, ai, "Lightning Bolt", ZoneType.Hand);
            Card second = card(session.game, ai, "Lightning Bolt", ZoneType.Hand);
            for (int i = 0; i < 2; i++) card(session.game, ai, "Mountain", ZoneType.Battlefield);
            first.getSpellAbilities().get(0).setActivatingPlayer(ai);
            second.getSpellAbilities().get(0).setActivatingPlayer(ai);
            session.game.getAction().checkStaticAbilities();
            // Exercise Forge's actual two-spell planner with every percentage
            // roll, holding the same board and resource availability constant.
            int chained = 0;
            for (int roll = 0; roll < 100; roll++) {
                final int percentRoll = roll;
                MyRandom.setRandom(new Random(42) {
                    @Override public int nextInt(int bound) { return bound == 100 ? percentRoll : super.nextInt(bound); }
                });
                var result = DamageDealAi.getDamagingSAToChain(ai, first.getSpellAbilities().get(0), "3");
                if (result != null) {
                    require(result.getLeft().getHostCard() == second && result.getRight() == 3,
                            "Planner did not find the other actual Bolt");
                    chained++;
                }
            }
            int expected = tier.equals("hard") ? 90 : tier.equals("normal") ? 45 : 0;
            require(chained == expected, "Wrong tactical planning count for " + tier + ": " + chained);
            require(ai.getCardsIn(ZoneType.Battlefield).stream().noneMatch(Card::isTapped), "Planning spent mana");
            require(ai.getLife() == 20, "Difficulty changed resources");
            AtomicBoolean workerRandom = new AtomicBoolean();
            Thread caller = Thread.currentThread();
            MyRandom.setRandom(new Random(42) {
                @Override protected int next(int bits) {
                    require(ThreadUtil.executionContext() == session.context, "AI worker lost its game scope");
                    if (Thread.currentThread() != caller) workerRandom.set(true);
                    return super.next(bits);
                }
            });
            controller.chooseSpellAbilityToPlay();
            require(workerRandom.get(), "Actual AI evaluation did not use the game-owned RNG worker");
            System.out.println("PASS AI tactical planning " + tier + "=" + chained + "/100");
        }
    }

    private static void lifecycle(NativeGuiBase base, String tier, int aiSeat) throws Exception {
        NativeSession session = new NativeSession(setup(tier, aiSeat), base);
        try (session) {
            session.start();
            int humanSeat = 1 - aiSeat;
            require(session.handle().getAsJsonArray("playerIndexes").size() == 2, "AI removed a registered seat");
            JsonObject prompt = JsonParser.parseString(session.prompt(humanSeat)).getAsJsonObject();
            require(prompt.get("decidingPlayerId").getAsString().equals("player-" + humanSeat), "AI emitted a human prompt");
            JsonObject invalid = NativeSession.object("type", "chooseAction");
            invalid.add("output", NativeSession.object("type", "pass"));
            try { session.submit(invalid); throw new AssertionError("Mismatched human answer was accepted"); }
            catch (IllegalArgumentException expected) { }
            require(!session.hasFailed() && JsonParser.parseString(session.prompt(humanSeat)).equals(prompt),
                    "Rejected human answer failed the AI game or consumed its prompt");
            for (int viewer : List.of(humanSeat, -1)) {
                JsonObject snapshot = JsonParser.parseString(session.snapshot(viewer)).getAsJsonObject();
                for (var raw : snapshot.getAsJsonArray("zones")) {
                    JsonObject zone = raw.getAsJsonObject();
                    if (zone.get("zone").getAsString().equals("hand")
                            && zone.get("ownerId").getAsString().equals("player-" + aiSeat))
                        for (var card : zone.getAsJsonArray("cards"))
                            require(!card.getAsJsonObject().has("identity"), "AI private hand escaped projection");
                }
            }
            JsonObject concede = NativeSession.object("type", "directive");
            concede.addProperty("player", humanSeat);
            concede.add("directive", NativeSession.object("type", "concede"));
            session.submit(concede);
            require(session.gameOver(), "Human concession did not end AI game");
            JsonObject terminal = JsonParser.parseString(session.snapshot(-1)).getAsJsonObject();
            require(terminal.get("winnerId").getAsString().equals("player-" + aiSeat), "Wrong AI winner seat");
        }
        require(session.context.awaitClosed(2000), "AI game leaked a worker");
    }
}
