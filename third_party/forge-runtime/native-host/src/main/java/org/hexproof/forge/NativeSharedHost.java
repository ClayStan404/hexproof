// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

/** Bounded multiplexed transport; every admitted game retains its own execution scope. */
final class NativeSharedHost {
    private record Entry(NativeSession session, AtomicBoolean busy) { }
    private static final class TerminalFailure extends RuntimeException {
        final JsonObject capsule;
        TerminalFailure(Throwable cause, JsonObject capsule) { super(cause); this.capsule = capsule; }
    }
    private final Map<String, Entry> sessions = new ConcurrentHashMap<>();
    private final NativeGuiBase base;
    private final int capacity;
    private volatile boolean closing;

    NativeSharedHost(NativeGuiBase base, int capacity) {
        if (capacity < 2 || capacity > 4) throw new IllegalArgumentException("Shared capacity must be between two and four");
        this.base = base; this.capacity = capacity;
    }

    private String call(JsonObject request) throws Exception {
        String command = request.get("command").getAsString();
        if (closing) throw new IllegalStateException("Worker is closing");
        if (command.equals("reset")) return "{\"sharedVersion\":1,\"capacity\":" + capacity
                + ",\"capabilities\":[\"forge-ai-v1\",\"forge-crash-diagnostics-v1\"],\"adapterRevision\":" + NativeHost.ADAPTER_REVISION + "}";
        if (command.equals("startGame")) {
            NativeSession session;
            synchronized (sessions) {
                JsonObject setup = JsonParser.parseString(request.get("payload").getAsString()).getAsJsonObject();
                if (setup.getAsJsonArray("players").asList().stream().anyMatch(e -> NativeSession.isAi(e.getAsJsonObject())))
                    throw new IllegalArgumentException("AI games require a dedicated worker");
                String id = setup.get("gameId").getAsString();
                if (closing || sessions.size() >= capacity || sessions.containsKey(id))
                    throw new IllegalArgumentException("Worker capacity or duplicate game");
                session = new NativeSession(setup, base);
                sessions.put(id, new Entry(session, new AtomicBoolean(true)));
            }
            try { session.start(); return session.handle().toString(); }
            catch (Throwable error) { throw retire(session, error); }
            finally { Entry entry = sessions.get(session.id); if (entry != null) entry.busy().set(false); }
        }
        String id = request.get("sessionId").getAsString();
        if (command.equals("endGame") || command.equals("abortGame")) { stop(id); return "{}"; }
        Entry entry = sessions.get(id);
        if (entry == null || !entry.busy().compareAndSet(false, true)) throw new IllegalStateException("Game unavailable or request already pending");
        NativeSession session = entry.session();
        try {
            return switch (command) {
                case "getSnapshot" -> session.snapshot(request.get("viewer").getAsInt());
                case "getReplay" -> session.replay.read(request.has("after") ? request.get("after").getAsLong() : 0);
                case "getPrompt" -> session.prompt(request.get("playerIndex").getAsInt());
                case "getGameOver" -> Boolean.toString(session.gameOver());
                case "submitAction" -> session.submit(JsonParser.parseString(request.get("payload").getAsString()).getAsJsonObject());
                default -> throw new IllegalArgumentException("Unknown shared command");
            };
        } catch (Throwable error) {
            if (session.hasFailed() || error instanceof Error) throw retire(session, error);
            throw error;
        } finally { entry.busy().set(false); }
    }

    private TerminalFailure retire(NativeSession session, Throwable error) {
        session.fail(error);
        JsonObject capsule = session.failureInfo(); // Freeze before stop removes ownership or cleanup throws.
        if (error instanceof Error || capsule != null && capsule.get("kind").getAsString().equals("resource_exhausted")) closing = true;
        try { stop(session.id); } catch (Throwable cleanup) { closing = true; }
        return new TerminalFailure(error, capsule);
    }

    private void stop(String id) throws InterruptedException {
        Entry entry = sessions.get(id);
        if (entry == null) return;
        entry.session().close();
        // Retain the slot until callbacks and game tasks have terminated. If
        // cleanup cannot finish, the supervisor must replace this whole JVM.
        if (!entry.session().context.awaitClosed(2000)) {
            closing = true;
            throw new IllegalStateException("Game cleanup did not terminate");
        }
        sessions.remove(id, entry);
    }

    JsonObject response(JsonObject request, long id) {
        JsonObject response = new JsonObject(); response.addProperty("requestId", id);
        try {
            response.addProperty("result", call(request)); response.addProperty("ok", true);
        } catch (Throwable error) {
            response.addProperty("ok", false); response.addProperty("error", "Native Forge request rejected");
            JsonObject failure = NativeHost.startFailure(error);
            if (failure != null) response.add("startFailure", failure);
            if (error instanceof TerminalFailure terminal) {
                response.addProperty("fatal", true);
                if (terminal.capsule != null) response.add("failureInfo", terminal.capsule);
            } else if (error instanceof Error) {
                closing = true;
                NativeDiagnostics diagnostic = new NativeDiagnostics("bootstrap");
                diagnostic.terminal(error, "rpc");
                response.addProperty("fatal", true);
                response.add("failureInfo", diagnostic.failureInfo());
            }
            if (closing) response.addProperty("workerFatal", true);
        }
        return response;
    }

    void run(PrintStream protocol) throws Exception {
        ThreadPoolExecutor requests = new ThreadPoolExecutor(capacity * 2, capacity * 2, 0, TimeUnit.SECONDS,
                new ArrayBlockingQueue<>(32));
        try (BufferedReader input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8))) {
            String line;
            while (!closing && (line = input.readLine()) != null) {
                if (line.isBlank()) continue;
                if (line.length() > 4 * 1024 * 1024) throw new IllegalArgumentException("Shared request exceeds limit");
                JsonObject request = JsonParser.parseString(line).getAsJsonObject();
                if (request.get("command").getAsString().equals("quit")) break;
                long id = request.get("requestId").getAsLong();
                if (id <= 0) throw new IllegalArgumentException("Invalid request ID");
                requests.execute(() -> {
                    JsonObject response = response(request, id);
                    synchronized (protocol) { protocol.println(NativeHost.JSON.toJson(response)); protocol.flush(); }
                    if (closing) System.exit(3);
                });
            }
        } finally {
            closing = true;
            requests.shutdownNow();
            for (Entry entry : sessions.values()) entry.session().close();
            for (Entry entry : sessions.values()) entry.session().context.awaitClosed(2000);
            sessions.clear(); base.close();
        }
    }
}
