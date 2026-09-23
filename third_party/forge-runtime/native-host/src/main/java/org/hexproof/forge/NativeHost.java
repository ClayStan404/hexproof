// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import java.io.*;
import java.nio.charset.StandardCharsets;

/** JSONL entry point. Shared workers require an explicit bounded capacity. */
public final class NativeHost {
    public static final String FORGE_COMMIT = "2be4858216742009afe8a7cffb035fc7671e960d";
    static final int ADAPTER_REVISION = 17;
    static final Gson JSON = new Gson();
    private NativeHost() { }

    public static void main(String[] args) throws Exception {
        // JSONL is UTF-8 regardless of the host's console/output code page.
        PrintStream protocol = new PrintStream(System.out, true, StandardCharsets.UTF_8);
        System.setOut(System.err);
        String assets = null;
        int capacity = 1;
        for (int i = 0; i < args.length; i++) {
            if (args[i].equals("--forge-home") && i + 1 < args.length) assets = args[++i];
            else if (args[i].equals("--max-games") && i + 1 < args.length) capacity = Integer.parseInt(args[++i]);
            else if (!args[i].equals("--interactive-server")) throw new IllegalArgumentException("Unknown argument");
        }
        if (assets == null) throw new IllegalArgumentException("--forge-home is required");
        if (capacity < 1 || capacity > 4) throw new IllegalArgumentException("Invalid game capacity");
        NativeProfile.create();
        NativeGuiBase base = new NativeGuiBase(assets);
        GuiBase.setInterface(base.proxy());
        FModel.initialize(null, prefs -> {
            prefs.setPref(FPref.DECKGEN_CARDBASED, false);
            prefs.setPref(FPref.YIELD_AUTO_PASS_NO_ACTIONS, false);
            prefs.setPref(FPref.UI_SHOW_ACTIONABLE_HIGHLIGHTS, true);
            prefs.setPref(FPref.UI_SELECT_FROM_CARD_DISPLAYS, false);
            prefs.setPref(FPref.UI_ENABLE_AI_CHEATS, false);
            return null;
        });
        if (capacity > 1) {
            new NativeSharedHost(base, capacity).run(protocol);
            System.exit(0);
            return;
        }
        NativeSession session = null;
        try (BufferedReader input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8))) {
            String line;
            while ((line = input.readLine()) != null) {
                if (line.isBlank()) continue;
                try {
                    if (line.length() > 4 * 1024 * 1024) throw new IllegalArgumentException("Request exceeds limit");
                    JsonObject request = JsonParser.parseString(line).getAsJsonObject();
                    String command = request.get("command").getAsString();
                    if (command.equals("quit")) break;
                    String result;
                    if (command.equals("reset")) {
                        if (session != null) throw new IllegalStateException("A process cannot reset an existing game");
                        result = "{\"capabilities\":[\"forge-ai-v1\"],\"adapterRevision\":" + ADAPTER_REVISION + "}";
                    } else if (command.equals("startGame")) {
                        if (session != null) throw new IllegalStateException("A process hosts one game only");
                        session = new NativeSession(JsonParser.parseString(request.get("payload").getAsString()).getAsJsonObject(), base);
                        session.start();
                        result = session.handle().toString();
                    } else {
                        if (session == null || !session.id.equals(request.get("sessionId").getAsString())) throw new IllegalArgumentException("Unknown session");
                        result = switch (command) {
                            case "getSnapshot" -> session.snapshot(request.has("viewer") ? request.get("viewer").getAsInt() : -1);
                            case "getReplay" -> session.replay.read(request.has("after") ? request.get("after").getAsLong() : 0);
                            case "getPrompt" -> session.prompt(request.get("playerIndex").getAsInt());
                            case "getGameOver" -> Boolean.toString(session.gameOver());
                            case "submitAction" -> session.submit(JsonParser.parseString(request.get("payload").getAsString()).getAsJsonObject());
                            case "endGame", "abortGame" -> { session.close(); yield "{}"; }
                            default -> throw new IllegalArgumentException("Unknown command");
                        };
                    }
                    protocol.println(JSON.toJson(new Response(true, result, "", false, null)));
                } catch (Exception e) {
                    e.printStackTrace(System.err);
                    protocol.println(JSON.toJson(new Response(false, "", "Native Forge request rejected",
                            session != null && session.hasFailed(), startFailure(e))));
                    protocol.flush();
                    // A rejected player answer leaves the native input intact.
                    // An unrecoverable session failure ends this game process
                    // so its supervisor can publish a scoped runtime failure.
                    if (session != null && session.hasFailed()) break;
                }
                protocol.flush();
            }
        } finally {
            if (session != null) session.close();
            base.close();
        }
        System.exit(0);
    }
    static JsonObject startFailure(Exception error) {
        return error instanceof NativeDeckException rejected ? rejected.startFailure() : null;
    }
    private record Response(boolean ok, String result, String error, boolean fatal, JsonObject startFailure) { }
}
