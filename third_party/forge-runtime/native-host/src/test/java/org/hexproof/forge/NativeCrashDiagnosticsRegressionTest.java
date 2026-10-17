// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.game.ability.AbilityUtils;
import forge.game.ability.ApiType;
import forge.game.card.Card;
import forge.game.cost.Cost;
import forge.game.spellability.SpellAbility;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import java.io.*;
import java.util.List;
import java.util.concurrent.*;
import static org.hexproof.forge.NativeCallbackRegressionTest.*;

/** Controlled faults at the real native dispatch boundaries, never production fault switches. */
public final class NativeCrashDiagnosticsRegressionTest {
    private static java.nio.file.Path exportedCapsule;
    public static void main(String[] args) throws Exception {
        if (args.length > 1) exportedCapsule = java.nio.file.Path.of(args[1]);
        require(!NativeDiagnosticSymbols.INSTANCE.id.isEmpty(), "Packaged symbol index missing");
        recoveredAndNested(); futureAndCallback(); stalledStream();
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> { prefs.setPref(FPref.DECKGEN_CARDBASED, false); return null; });
            for (String visibility : List.of("battlefield", "hand", "library", "face_down")) publicEvidence(base, visibility);
            timeoutAndClose(base); sharedTerminal(base);
        }
        System.out.println("PASS native crash diagnostics: nested dispatch, four seats, hidden sources, Futures, cancellation and stalled stderr");
    }
    private static void recoveredAndNested() {
        NativeDiagnostics diagnostic = new NativeDiagnostics("recoverable");
        try { diagnostic.run("effect", null, () -> { throw new IllegalArgumentException("PRIVATE-FIRST-CARD"); }); }
        catch (IllegalArgumentException expected) { }
        require(diagnostic.failureInfo() == null, "Recovered exception occupied first terminal slot");
        RuntimeException failure = new IllegalStateException("PRIVATE-SECOND-CARD /home/private/token");
        try { nested(diagnostic, 20, failure); } catch (RuntimeException expected) { }
        diagnostic.terminal(new IllegalStateException("PRIVATE-WRAPPER", failure), "game_callback");
        JsonObject value = diagnostic.failureInfo();
        require(value.getAsJsonArray("spans").size() == 8 && value.get("omittedSpans").getAsInt() >= 12,
                "Deepest bounded spans were not retained");
        require(value.get("boundary").getAsString().equals("decision"), "Inner site lost while unwinding");
        require(!value.toString().contains("PRIVATE") && !value.toString().contains("/home"), "Exception text escaped");
        diagnostic.terminal(new OutOfMemoryError("PRIVATE-LATER"), "rpc");
        require(value.equals(diagnostic.failureInfo()), "Later cleanup overwrote first failure");
        value.addProperty("kind", "changed");
        require(diagnostic.failureInfo().get("kind").getAsString().equals("engine_exception"), "Report copy retained mutable ownership");
        require(diagnostic.failureInfo().toString().getBytes(java.nio.charset.StandardCharsets.UTF_8).length <= 16384,
                "Terminal capsule exceeded transport limit");
    }
    private static void nested(NativeDiagnostics diagnostic, int depth, RuntimeException failure) {
        diagnostic.run(depth == 0 ? "decision" : "effect", null, () -> {
            if (depth == 0) throw failure;
            nested(diagnostic, depth - 1, failure); return null;
        });
    }
    private static void futureAndCallback() throws Exception {
        NativeDiagnostics diagnostic = new NativeDiagnostics("future-owner");
        CountDownLatch terminal = new CountDownLatch(1);
        try (NativeExecution execution = new NativeExecution(1, error -> { diagnostic.terminal(error, "game_callback"); terminal.countDown(); }, diagnostic)) {
            Future<?> handled = execution.gameExecutor().submit(() -> { throw new IllegalArgumentException("PRIVATE-HANDLED"); });
            try { handled.get(); throw new AssertionError("Future swallowed failure"); }
            catch (ExecutionException expected) { }
            require(diagnostic.failureInfo() == null, "Handled Future changed execution semantics");
            diagnostic.run("decision", null, () -> {
                execution.gameExecutor().execute(() -> {
                    try { execution.gameExecutor().submit(() -> { throw new NullPointerException("PRIVATE-FUTURE"); }).get(); }
                    catch (Exception failure) { throw new IllegalStateException(failure); }
                }); return null;
            });
            require(terminal.await(5, TimeUnit.SECONDS), "Unobserved callback failure was lost");
            JsonObject value = diagnostic.failureInfo();
            require(value.get("boundary").getAsString().equals("submitted_task"), "Callable context lost inside FutureTask");
            require(value.getAsJsonArray("spans").asList().stream().anyMatch(v -> v.getAsJsonObject().get("stage").getAsString().equals("decision")),
                    "Scheduled work lost immutable parent provenance");
            require(!value.toString().contains("PRIVATE"), "Future exception text escaped");
        }
        NativeDiagnostics supplied = new NativeDiagnostics("external-future");
        try (NativeExecution execution = new NativeExecution(2, error -> supplied.terminal(error, "game_callback"), supplied)) {
            FutureTask<Object> task = new FutureTask<>(() -> { throw new NullPointerException("PRIVATE-EXTERNAL-FUTURE"); });
            execution.later(task); execution.andWait(() -> { });
            require(supplied.failureInfo() == null, "Observed caller FutureTask became terminal before propagation");
            try { task.get(); throw new AssertionError("Caller FutureTask failure disappeared"); }
            catch (ExecutionException error) { supplied.terminal(error, "rpc"); }
            require(supplied.failureInfo().get("boundary").getAsString().equals("edt_callback"), "Caller FutureTask lost its execution site");
        }
        NativeDiagnostics other = new NativeDiagnostics("future-owner");
        require(other.failureInfo() == null && !other.producerId().equals(diagnostic.producerId()), "Lease diagnostic ownership leaked");
    }
    private static void stalledStream() throws Exception {
        CountDownLatch blocked = new CountDownLatch(1), release = new CountDownLatch(1);
        NativeDiagnosticStream.initialize(new PrintStream(new OutputStream() {
            @Override public void write(int value) {
                blocked.countDown();
                try { release.await(); } catch (InterruptedException error) { Thread.currentThread().interrupt(); }
            }
        }));
        NativeDiagnostics diagnostic = new NativeDiagnostics("stalled-stream");
        diagnostic.run("effect", null, () -> null);
        require(blocked.await(2, TimeUnit.SECONDS), "Diagnostic stream fixture did not block");
        long began = System.nanoTime();
        for (int i = 0; i < 1000; i++) diagnostic.run("decision", null, () -> null);
        diagnostic.terminal(new IllegalStateException("PRIVATE"), "rpc");
        require(System.nanoTime() - began < TimeUnit.SECONDS.toNanos(2), "Blocked stderr blocked gameplay");
        require(diagnostic.failureInfo() != null, "Blocked stderr removed inline terminal evidence");
        release.countDown();
    }
    private static JsonObject setup(String id) {
        JsonObject setup = NativeIsolationRegressionTest.setup(id, 42);
        JsonArray players = setup.getAsJsonArray("players");
        players.add(players.get(0).deepCopy()); players.add(players.get(1).deepCopy());
        setup.addProperty("variant", "commander"); setup.addProperty("startingLife", 40);
        for (JsonElement entry : players) {
            JsonObject player = entry.getAsJsonObject();
            JsonArray deck = new JsonArray();
            for (int i = 0; i < 99; i++) deck.add(NativeSession.object("name", "Forest"));
            deck.add(NativeSession.object("name", "Karametra, God of Harvests")); player.add("deck", deck);
            JsonArray commanders = new JsonArray(); commanders.add("Karametra, God of Harvests"); player.add("commanderNames", commanders);
        }
        return setup;
    }
    private static void publicEvidence(NativeGuiBase base, String visibility) throws IOException {
        try (NativeSession session = new NativeSession(setup("native-crash-" + visibility), base); var ignored = session.context.enter()) {
            var owner = session.game.getRegisteredPlayers().getFirst();
            ZoneType zone = visibility.equals("hand") ? ZoneType.Hand : visibility.equals("library") ? ZoneType.Library : ZoneType.Battlefield;
            Card source = card(session.game, owner, "Lightning Bolt", zone);
            if (visibility.equals("face_down")) source.turnFaceDown(true);
            SpellAbility inner = new SpellAbility(source, new Cost("0", false)) {
                @Override public boolean canPlay() { return true; }
                @Override public void resolve() { throw new NullPointerException("PRIVATE-TARGET-HAND-CARD"); }
            };
            inner.setApi(ApiType.Draw); inner.setActivatingPlayer(owner);
            try { AbilityUtils.resolve(inner); throw new AssertionError("Dispatch did not throw injected fault"); }
            catch (NullPointerException error) { session.fail(error); }
            JsonObject value = session.failureInfo();
            require(value != null && value.get("boundary").getAsString().equals("effect"), "Real API dispatch lacks execution span");
            JsonObject span = value.getAsJsonArray("spans").get(value.getAsJsonArray("spans").size() - 1).getAsJsonObject();
            require(span.get("api").getAsString().equals("Draw"), "API enum lost");
            require(span.has("source") == visibility.equals("battlefield"), "Public-source projection disagrees with spectator visibility");
            require(!value.toString().contains("PRIVATE-TARGET"), "Private fault message escaped");
            if (span.has("source")) {
                if (exportedCapsule != null) java.nio.file.Files.writeString(exportedCapsule, value.toString());
                require(span.getAsJsonObject("source").getAsJsonObject("card").get("name").getAsString().equals("Lightning Bolt"), "Verified public name missing");
                session.game.getAction().moveToHand(source, null);
                require(session.failureInfo().equals(value), "Later zone change rewrote captured public evidence");
            } else require(!value.toString().contains("Lightning Bolt"), "Hidden card identity escaped");
            require(value.get("producerId").getAsString().equals(session.handle().get("diagnosticProducerId").getAsString()), "Handle did not fence diagnostic producer");
        }
    }
    private static void sharedTerminal(NativeGuiBase base) throws Exception {
        NativeSharedHost host = new NativeSharedHost(base, 2);
        JsonObject start = NativeSession.object("command", "startGame");
        start.addProperty("payload", setup("native-crash-shared").toString());
        JsonObject opened = host.response(start, 1);
        require(opened.get("ok").getAsBoolean(), "Shared fixture did not start");
        var sessionsField = NativeSharedHost.class.getDeclaredField("sessions"); sessionsField.setAccessible(true);
        var sessions = (java.util.Map<?, ?>) sessionsField.get(host);
        Object entry = sessions.get("native-crash-shared");
        var accessor = entry.getClass().getDeclaredMethod("session"); accessor.setAccessible(true);
        NativeSession session = (NativeSession) accessor.invoke(entry);
        session.fail(new NullPointerException("PRIVATE-SHARED-HAND"));
        JsonObject expected = session.failureInfo();
        JsonObject read = NativeSession.object("command", "getSnapshot");
        read.addProperty("sessionId", session.id); read.addProperty("viewer", -1);
        JsonObject failed = host.response(read, 2);
        require(!failed.get("ok").getAsBoolean() && failed.get("fatal").getAsBoolean(), "Shared terminal failure was an ordinary rejection");
        require(failed.getAsJsonObject("failureInfo").equals(expected), "Cleanup discarded the inline first failure capsule");
        require(!failed.has("workerFatal") && sessions.isEmpty(), "Session failure leaked its lease or killed the healthy worker");
        require(!failed.toString().contains("PRIVATE"), "Shared response leaked exception text");
        JsonObject restarted = host.response(start, 3);
        require(restarted.get("ok").getAsBoolean(), "Shared replacement game was not admitted");
        entry = sessions.get("native-crash-shared");
        session = (NativeSession) accessor.invoke(entry);
        require(!session.context.diagnostics.producerId().equals(expected.get("producerId").getAsString()), "Same logical game reused a retired producer");
        session.fail(new OutOfMemoryError("PRIVATE-SYNTHETIC-OOM"));
        JsonObject resource = host.response(read, 4);
        require(resource.get("workerFatal").getAsBoolean(), "Resource failure left shared worker available");
        require(resource.getAsJsonObject("failureInfo").get("kind").getAsString().equals("resource_exhausted"), "Wrapped resource cause was lost");
    }
    private static void timeoutAndClose(NativeGuiBase base) {
        try (NativeSession session = new NativeSession(setup("native-crash-timeout"), base)) {
            try { session.awaitBoundary(1, TimeUnit.MILLISECONDS); } catch (IllegalStateException expected) { }
            require(session.failureInfo().get("kind").getAsString().equals("execution_timeout"), "Input boundary lost timeout classification");
        }
        NativeSession closed = new NativeSession(setup("native-crash-closed"), base);
        closed.close(); closed.fail(new CancellationException("PRIVATE-CLOSED"));
        require(closed.failureInfo() == null, "Acknowledged cleanup became a crash");
    }
}
