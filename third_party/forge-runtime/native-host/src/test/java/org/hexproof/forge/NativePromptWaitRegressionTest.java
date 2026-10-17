// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package org.hexproof.forge;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import static org.hexproof.forge.NativeCallbackRegressionTest.require;

/** Adapter 29 waits for the next prompt and returns every viewer in one call. */
public final class NativePromptWaitRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                return null;
            });
            JsonObject config = NativeIsolationRegressionTest.setup("prompt-wait", 42);
            try (NativeSession session = new NativeSession(config, base)) {
                session.start();
                String first = session.awaitPrompt(0, 5000);
                require(!first.isEmpty(), "awaitPrompt missed the opening prompt");
                JsonObject envelope = JsonParser.parseString(first).getAsJsonObject();
                require(envelope.getAsJsonObject("input").get("type").getAsString().equals("mulligan"),
                        "Opening prompt was not a mulligan: " + first);
                long id = envelope.get("promptId").getAsLong();
                require(id > 0, "Opening prompt id was not positive");
                require(session.awaitPrompt(id, 40).isEmpty(), "An unchanged prompt must time out");
                requireRejected(() -> session.awaitPrompt(id, 0), "A zero timeout must be rejected");

                JsonArray viewers = new JsonArray();
                viewers.add(-1);
                viewers.add(0);
                viewers.add(1);
                JsonArray batch = JsonParser.parseString(session.snapshots(viewers)).getAsJsonArray();
                require(batch.size() == viewers.size(), "Snapshot batch length " + batch.size());
                for (int index = 0; index < viewers.size(); index++) {
                    int viewer = viewers.get(index).getAsInt();
                    require(batch.get(index).equals(JsonParser.parseString(session.snapshot(viewer))),
                            "Batched viewer " + viewer + " differed from its own snapshot");
                }
                requireRejected(() -> session.snapshots(new JsonArray()), "An empty viewer list must be rejected");

                Thread keep = new Thread(() -> keepOpeningHand(session), "prompt-wait-keep");
                keep.start();
                String next = session.awaitPrompt(id, 5000);
                keep.join(5000);
                require(!keep.isAlive(), "Keeping the opening hand did not finish");
                require(!next.isEmpty(), "awaitPrompt missed the prompt after the keep");
                long nextId = JsonParser.parseString(next).getAsJsonObject().get("promptId").getAsLong();
                require(nextId != id, "The prompt id did not change after the keep");
            }
        }
        System.out.println("PASS native prompt wait");
    }

    private static void keepOpeningHand(NativeSession session) {
        JsonObject output = NativeSession.object("type", "mulliganDecision");
        output.addProperty("keep", true);
        JsonObject response = NativeSession.object("type", "mulligan");
        response.add("output", output);
        session.submit(response);
    }

    private static void requireRejected(Runnable action, String message) {
        try {
            action.run();
        } catch (IllegalArgumentException rejected) {
            return;
        }
        throw new AssertionError(message);
    }
}
