// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import java.io.*;
import java.lang.management.ManagementFactory;
import java.lang.ref.WeakReference;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;

/** Local experiment only: multiple unmodified sessions sharing the production GUI base.
 * This deliberately retains the global dispatcher, RNG and failure handler so
 * the accompanying probes can measure their isolation failures. Never deploy.
 */
public final class SharedJvmHost {
    private static final Gson JSON = new Gson();
    private final Map<String, NativeSession> sessions = new HashMap<>();
    private final List<WeakReference<NativeSession>> closedSessions = new ArrayList<>();
    final NativeGuiBase base;

    SharedJvmHost(String assets) throws Exception {
        NativeProfile.create();
        base = new NativeGuiBase(assets);
        GuiBase.setInterface(base.proxy());
        FModel.initialize(null, prefs -> {
            prefs.setPref(FPref.DECKGEN_CARDBASED, false);
            prefs.setPref(FPref.YIELD_AUTO_PASS_NO_ACTIONS, false);
            prefs.setPref(FPref.UI_SHOW_ACTIONABLE_HIGHLIGHTS, true);
            prefs.setPref(FPref.UI_SELECT_FROM_CARD_DISPLAYS, false);
            return null;
        });
    }

    private String call(JsonObject request) {
        String command = request.get("command").getAsString();
        if (command.equals("reset")) return "";
        if (command.equals("stats")) {
            if (request.has("gc") && request.get("gc").getAsBoolean()) System.gc();
            JsonObject result = new JsonObject();
            result.addProperty("heapUsed", ManagementFactory.getMemoryMXBean().getHeapMemoryUsage().getUsed());
            result.addProperty("threads", ManagementFactory.getThreadMXBean().getThreadCount());
            synchronized (sessions) {
                result.addProperty("sessions", sessions.size());
                result.addProperty("closedSessionsRetained", closedSessions.stream().filter(ref -> ref.get() != null).count());
            }
            return result.toString();
        }
        if (command.equals("startGame")) {
            NativeSession session;
            synchronized (sessions) {
                JsonObject setup = JsonParser.parseString(request.get("payload").getAsString()).getAsJsonObject();
                String id = setup.get("gameId").getAsString();
                if (sessions.size() >= 3 || sessions.containsKey(id)) throw new IllegalArgumentException("Experiment capacity or duplicate ID");
                // Serialize construction: pinned Game.nextId is a plain static counter.
                session = new NativeSession(setup, base);
                sessions.put(id, session);
                base.setFailureHandler(session::fail);
            }
            session.start();
            return session.handle().toString();
        }
        NativeSession session;
        synchronized (sessions) { session = sessions.get(request.get("sessionId").getAsString()); }
        if (session == null) throw new IllegalArgumentException("Unknown session");
        // The Python driver admits one outstanding request per game. Different
        // games have simultaneous calls; stdout uses explicit request IDs.
        return switch (command) {
            case "getSnapshot" -> session.snapshot(request.get("viewer").getAsInt());
            case "getPrompt" -> session.prompt(request.get("playerIndex").getAsInt());
            case "getGameOver" -> Boolean.toString(session.gameOver());
            case "submitAction" -> session.submit(JsonParser.parseString(request.get("payload").getAsString()).getAsJsonObject());
            case "endGame", "abortGame" -> {
                session.close();
                synchronized (sessions) {
                    sessions.remove(session.id);
                    closedSessions.add(new WeakReference<>(session));
                }
                yield "{}";
            }
            default -> throw new IllegalArgumentException("Unknown experiment command");
        };
    }

    public static void main(String[] args) throws Exception {
        PrintStream protocol = System.out;
        System.setOut(System.err);
        SharedJvmHost host = new SharedJvmHost(args[0]);
        ExecutorService requests = new ThreadPoolExecutor(3, 3, 0, TimeUnit.SECONDS,
                new ArrayBlockingQueue<>(32));
        try (BufferedReader input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8))) {
            String line;
            while ((line = input.readLine()) != null) {
                if (line.length() > 4 * 1024 * 1024) throw new IllegalArgumentException("Request too large");
                JsonObject request = JsonParser.parseString(line).getAsJsonObject();
                if (request.get("command").getAsString().equals("quit")) break;
                requests.execute(() -> {
                    JsonObject response = new JsonObject();
                    response.add("requestId", request.get("requestId"));
                    try {
                        response.addProperty("result", host.call(request));
                        response.addProperty("ok", true);
                    } catch (Throwable error) {
                        error.printStackTrace(System.err);
                        response.addProperty("ok", false);
                        response.addProperty("error", error.toString());
                    }
                    synchronized (protocol) { protocol.println(JSON.toJson(response)); protocol.flush(); }
                });
            }
        } finally {
            synchronized (host.sessions) { host.sessions.values().forEach(NativeSession::close); }
            requests.shutdownNow();
            host.base.close();
        }
        System.exit(0);
    }
}
