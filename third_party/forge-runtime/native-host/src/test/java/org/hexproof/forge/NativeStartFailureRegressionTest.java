// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

/** Preserve request coordinates and privacy across real dedicated/shared JSONL rejection. */
public final class NativeStartFailureRegressionTest {
    private static final String PRIVATE_NAME = "Private unavailable card sentinel";

    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                return null;
            });
            coordinatesAndCopies(base);
            sizesAndLimit(base);
            check(NativeHost.startFailure(new IllegalArgumentException("private/raw/path")) == null,
                    "Untyped errors gained structured diagnostics");
        }
        jsonl(args[0], 1);
        jsonl(args[0], 2);
        System.out.println("Native start failure regression passed");
        System.exit(0);
    }

    private static JsonObject setup() {
        JsonObject setup = NativeSession.object("gameId", "start-failure-regression");
        setup.addProperty("seed", 44);
        setup.addProperty("startingLife", 20);
        setup.addProperty("startingPlayerIndex", 0);
        setup.addProperty("variant", "constructed");
        JsonArray players = new JsonArray();
        for (int seat = 0; seat < 2; seat++) {
            JsonObject player = NativeSession.object("name", "Private seat " + seat);
            JsonArray cards = new JsonArray();
            for (int index = 0; index < 60; index++) cards.add(NativeSession.object("name", "Forest"));
            player.add("deck", cards);
            player.add("sideboard", new JsonArray());
            players.add(player);
        }
        setup.add("players", players);
        return setup;
    }

    private static JsonObject player(JsonObject setup, int seat) {
        return setup.getAsJsonArray("players").get(seat).getAsJsonObject();
    }

    private static JsonObject unavailable(String number) {
        JsonObject card = NativeSession.object("name", "Forest");
        card.addProperty("setCode", "M21");
        card.addProperty("collectorNumber", number);
        return card;
    }

    private static JsonObject reject(JsonObject setup, NativeGuiBase base, String message) {
        try (NativeSession ignored = new NativeSession(setup, base)) {
            throw new AssertionError("Invalid deck was accepted");
        } catch (NativeDeckException error) {
            check(error.getMessage().equals(message), "Safe exception message changed");
            JsonObject failure = NativeHost.startFailure(error);
            validateFailure(failure);
            return failure;
        }
    }

    private static void validateFailure(JsonObject failure) {
        check(failure.keySet().equals(Set.of("reason", "issues", "truncated")), "Unexpected failure fields");
        check(failure.get("reason").getAsString().equals("deck_rejected"), "Incorrect failure category");
        check(!failure.toString().contains(PRIVATE_NAME) && !failure.toString().contains("Forest")
                && !failure.toString().contains("M21") && !failure.toString().contains("Private seat"),
                "A private submitted identity escaped in the diagnostics");
        for (JsonElement value : failure.getAsJsonArray("issues"))
            check(value.getAsJsonObject().keySet().equals(Set.of("playerIndex", "section", "cardIndex", "code")),
                    "Unexpected issue fields");
    }

    private static void issue(JsonObject failure, int item, int seat, String section, int index, String code) {
        JsonObject issue = failure.getAsJsonArray("issues").get(item).getAsJsonObject();
        check(issue.get("playerIndex").getAsInt() == seat && issue.get("section").getAsString().equals(section)
                && issue.get("cardIndex").getAsInt() == index && issue.get("code").getAsString().equals(code),
                "Incorrect original request coordinate: " + issue);
    }

    private static void coordinatesAndCopies(NativeGuiBase base) {
        JsonObject request = setup();
        player(request, 0).getAsJsonArray("deck").set(3, unavailable("999991"));
        player(request, 0).getAsJsonArray("deck").set(4, unavailable("999991"));
        player(request, 0).getAsJsonArray("sideboard").add(unavailable("999992"));
        player(request, 1).getAsJsonArray("deck").set(7, NativeSession.object("name", PRIVATE_NAME));
        JsonArray commanders = new JsonArray(); commanders.add(PRIVATE_NAME);
        player(request, 1).add("commanderNames", commanders);
        JsonObject failure = reject(request, base, "Requested card printing is unavailable");
        check(failure.getAsJsonArray("issues").size() == 4 && !failure.get("truncated").getAsBoolean(),
                "All seats and sections were not collected or copies consumed the limit");
        issue(failure, 0, 0, "mainboard", 3, "printing_unavailable");
        issue(failure, 1, 0, "sideboard", 0, "printing_unavailable");
        issue(failure, 2, 1, "mainboard", 7, "printing_unavailable");
        issue(failure, 3, 1, "commanders", 0, "commander_missing");
        request = setup();
        for (int index = 0; index < 60; index++)
            player(request, 0).getAsJsonArray("deck").set(index, unavailable("999991"));
        player(request, 1).getAsJsonArray("deck").set(22, unavailable("999991"));
        failure = reject(request, base, "Requested card printing is unavailable");
        check(failure.getAsJsonArray("issues").size() == 2 && !failure.get("truncated").getAsBoolean(),
                "Repeated copies hid another seat's error");
        issue(failure, 1, 1, "mainboard", 22, "printing_unavailable");
    }

    private static void sizesAndLimit(NativeGuiBase base) {
        JsonObject request = setup();
        player(request, 0).add("deck", new JsonArray());
        for (int index = 0; index < 1001; index++)
            player(request, 0).getAsJsonArray("sideboard").add(NativeSession.object("name", "Forest"));
        player(request, 1).getAsJsonArray("deck").set(9, unavailable("999991"));
        JsonObject failure = reject(request, base, "Invalid deck size");
        check(failure.getAsJsonArray("issues").size() == 3, "Size validation hid other known errors");
        issue(failure, 0, 0, "mainboard", -1, "invalid_deck_size");
        issue(failure, 1, 0, "sideboard", -1, "invalid_sideboard_size");
        issue(failure, 2, 1, "mainboard", 9, "printing_unavailable");
        JsonArray missingCommander = new JsonArray(); missingCommander.add(PRIVATE_NAME);
        player(request, 0).add("commanderNames", missingCommander);
        failure = reject(request, base, "Invalid deck size");
        issue(failure, 2, 0, "commanders", 0, "commander_missing");
        request = setup();
        for (int index = 0; index < 60; index++)
            player(request, 0).getAsJsonArray("deck").set(index, unavailable("99999" + index));
        failure = reject(request, base, "Requested card printing is unavailable");
        check(failure.getAsJsonArray("issues").size() == 32 && failure.get("truncated").getAsBoolean(),
                "Diagnostic limit was not applied to distinct printing issues");
    }

    private static void jsonl(String assets, int capacity) throws Exception {
        Path profile = Files.createTempDirectory(Path.of(System.getProperty("user.home")), "start-failure-");
        Process process = new ProcessBuilder(Path.of(System.getProperty("java.home"), "bin", "java").toString(),
                "-Xmx1g", "-Djava.awt.headless=true", "-Duser.home=" + profile,
                "-cp", System.getProperty("java.class.path"), "org.hexproof.forge.NativeHost",
                "--forge-home", assets, "--max-games", Integer.toString(capacity))
                .redirectError(profile.resolve("stderr.log").toFile()).start();
        BufferedWriter input = process.outputWriter(StandardCharsets.UTF_8);
        BufferedReader output = process.inputReader(StandardCharsets.UTF_8);
        try {
            JsonObject reset = call(input, output, "reset", "", 1);
            check(reset.get("ok").getAsBoolean()
                    && JsonParser.parseString(reset.get("result").getAsString()).getAsJsonObject()
                    .get("adapterRevision").getAsInt() == NativeHost.ADAPTER_REVISION, "Stale adapter capability revision");
            JsonObject broken = setup();
            player(broken, 1).getAsJsonArray("deck").set(6, unavailable("999991"));
            JsonObject rejected = call(input, output, "startGame", broken.toString(), 2);
            check(!rejected.get("ok").getAsBoolean()
                    && rejected.get("error").getAsString().equals("Native Forge request rejected"),
                    "JSONL rejection changed its safe fallback");
            validateFailure(rejected.getAsJsonObject("startFailure"));
            issue(rejected.getAsJsonObject("startFailure"), 0, 1, "mainboard", 6, "printing_unavailable");
            JsonObject unknown = call(input, output, "unknown-private-command", "", 3);
            check(!unknown.get("ok").getAsBoolean() && !unknown.has("startFailure"),
                    "Generic JSONL failure was misclassified as a deck rejection");
            JsonObject valid = setup();
            if (capacity == 1) {
                player(valid, 1).addProperty("ai", true);
                player(valid, 1).addProperty("aiDifficulty", "normal");
            }
            JsonObject started = call(input, output, "startGame", valid.toString(), 4);
            check(started.get("ok").getAsBoolean() && !started.has("startFailure"),
                    "Rejected deck poisoned a later valid human/AI game");
            JsonObject ended = call(input, output, "abortGame", "", 5);
            check(ended.get("ok").getAsBoolean(), "Valid retry game did not clean up");
            input.write("{\"command\":\"quit\"}\n"); input.flush();
            check(process.waitFor(10, TimeUnit.SECONDS) && process.exitValue() == 0, "JSONL worker did not exit cleanly");
        } finally {
            if (process.isAlive()) {
                process.destroy();
                if (!process.waitFor(3, TimeUnit.SECONDS)) process.destroyForcibly();
            }
            input.close();
            output.close();
        }
    }

    private static JsonObject call(BufferedWriter input, BufferedReader output,
                                   String command, String payload, int requestId) throws Exception {
        JsonObject request = NativeSession.object("command", command);
        request.addProperty("requestId", requestId);
        request.addProperty("payload", payload);
        request.addProperty("sessionId", "start-failure-regression");
        input.write(request.toString()); input.newLine(); input.flush();
        String line = CompletableFuture.supplyAsync(() -> {
            try { return output.readLine(); }
            catch (java.io.IOException error) { throw new java.io.UncheckedIOException(error); }
        }).get(30, TimeUnit.SECONDS);
        check(line != null, "JSONL worker closed before replying");
        JsonObject response = JsonParser.parseString(line).getAsJsonObject();
        if (response.has("requestId")) check(response.get("requestId").getAsInt() == requestId, "Wrong shared request ID");
        return response;
    }

    private static void check(boolean valid, String message) {
        if (!valid) throw new AssertionError(message);
    }
}
