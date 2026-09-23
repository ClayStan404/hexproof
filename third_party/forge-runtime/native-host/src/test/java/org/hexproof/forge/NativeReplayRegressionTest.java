// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.common.eventbus.Subscribe;
import com.google.gson.*;
import forge.game.GameStage;
import forge.game.card.Card;
import forge.game.combat.Combat;
import forge.game.event.*;
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.spellability.SpellAbility;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.model.FModel;
import java.nio.file.*;
import java.util.*;
import static org.hexproof.forge.NativeCallbackRegressionTest.*;

public final class NativeReplayRegressionTest {
    public static final class Observer {
        final NativeSession session;
        final JsonArray frames = new JsonArray();
        Throwable failure;
        Observer(NativeSession session) { this.session = session; }
        @Subscribe public void event(GameEvent event) {
            try {
                JsonObject frame = new JsonObject();
                frame.addProperty("event", event.getClass().getSimpleName());
                JsonArray views = new JsonArray();
                for (int viewer = -1; viewer < 2; viewer++) views.add(NativeSnapshot.capture(session.game, session.id, viewer, null));
                frame.add("views", views); frames.add(frame);
            } catch (Throwable error) { failure = error; }
        }
    }
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy()); FModel.initialize(null, prefs -> null);
            JsonObject config = JsonParser.parseString("{\"gameId\":\"replay-probe\",\"seed\":42,\"variant\":\"constructed\",\"startingLife\":20,\"players\":[{\"name\":\"Replay A\",\"deck\":[{\"name\":\"Forest\"}]},{\"name\":\"Replay B\",\"deck\":[{\"name\":\"Island\"}]}]}").getAsJsonObject();
            try (NativeSession session = new NativeSession(config, base); var scope = session.context.enter()) {
                base.setTestSession(session); session.game.setAge(GameStage.Play);
                Player a = session.game.getPlayers().get(0), b = session.game.getPlayers().get(1);
                session.game.setStartingPlayer(a); session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, a, false, 2);
                card(session.game, a, "Forest", ZoneType.Hand); card(session.game, b, "Island", ZoneType.Hand);
                Card attacker = card(session.game, a, "Grizzly Bears", ZoneType.Battlefield);
                Card blocker = card(session.game, b, "Memnite", ZoneType.Battlefield);
                Combat combat = new Combat(a); session.game.getPhaseHandler().setCombat(combat);
                combat.addAttacker(attacker, b); combat.addBlocker(attacker, blocker);
                require(combat.getBlockers(attacker).contains(blocker) && combat.getDefenderByAttacker(attacker) == b, "combat relationships unavailable");
                long baseline = JsonParser.parseString(session.replay.read(0)).getAsJsonObject().get("lastSequence").getAsLong();
                session.replay.read(baseline);
                Observer observer = new Observer(session); session.game.subscribeToEvents(observer);
                drive(session, a, () -> {
                    for (int i = 0; i < 2; i++) {
                        Card bolt = card(session.game, a, "Lightning Bolt", ZoneType.Stack);
                        SpellAbility ability = bolt.getSpellAbilities().get(0); ability.setActivatingPlayer(a); ability.getTargets().add(b);
                        session.game.getStack().add(ability); session.game.getStack().resolveStack();
                    }
                    require(b.getLife() == 14, "two automatic resolutions lost");
                }, input -> { throw new AssertionError("unexpected human prompt"); });
                require(observer.failure == null, "snapshot in event failed: " + observer.failure);
                int resolved = 0; boolean intermediate = false;
                for (JsonElement value : observer.frames) {
                    JsonObject f = value.getAsJsonObject();
                    if (f.get("event").getAsString().equals("GameEventSpellResolved")) resolved++;
                    JsonArray views = f.getAsJsonArray("views");
                    for (int viewer = -1; viewer < 2; viewer++) {
                        for (JsonElement zone : views.get(viewer + 1).getAsJsonObject().getAsJsonArray("zones")) {
                            JsonObject z = zone.getAsJsonObject();
                            if (z.get("zone").getAsString().equals("hand")) {
                                boolean own = z.get("ownerId").getAsString().equals("player-" + viewer);
                                require(z.getAsJsonArray("cards").size() == (own ? 1 : 0), "hand visibility mismatch");
                            }
                        }
                    }
                    intermediate |= views.get(0).getAsJsonObject().getAsJsonArray("players").get(1).getAsJsonObject().get("life").getAsInt() == 17;
                }
                require(resolved == 2 && intermediate, "automatic intermediate states missing");
                JsonObject recorded = JsonParser.parseString(session.replay.read(baseline)).getAsJsonObject();
                require(recorded.get("complete").getAsBoolean(), "Private recording became incomplete");
                JsonArray history = recorded.getAsJsonArray("frames");
                require(history.size() > 4, "Actual native recorder omitted automatic events");
                boolean privateIntermediate = false;
                for (JsonElement value : history) {
                    JsonObject view = value.getAsJsonObject().getAsJsonObject("view");
                    int hands = 0;
                    for (JsonElement zone : view.getAsJsonArray("zones")) {
                        JsonObject z = zone.getAsJsonObject();
                        if (z.get("zone").getAsString().equals("hand")) hands += z.getAsJsonArray("cards").size();
                        if (z.get("zone").getAsString().equals("library")) require(z.getAsJsonArray("cards").isEmpty(), "Recorder revealed an unknown library");
                    }
                    require(hands == 2, "Recorder did not preserve both hands");
                    privateIntermediate |= view.getAsJsonArray("players").get(1).getAsJsonObject().get("life").getAsInt() == 17;
                }
                require(privateIntermediate, "Recording omitted an automatic intermediate board");
                require(session.replay.read(baseline).equals(recorded.toString()), "Retry changed a recorded frame");
                require(JsonParser.parseString(session.replay.read(recorded.get("lastSequence").getAsLong())).getAsJsonObject().getAsJsonArray("frames").isEmpty(), "Acknowledged prefix was retained");
                session.replay.record("Decision", 1, "Opponent chooses during the active player's turn");
                JsonObject decision = JsonParser.parseString(session.replay.read(recorded.get("lastSequence").getAsLong()))
                        .getAsJsonObject().getAsJsonArray("frames").get(0).getAsJsonObject();
                require(decision.getAsJsonObject("view").get("activePlayerId").getAsString().equals("player-0")
                        && decision.getAsJsonObject("view").get("priorityPlayerId").getAsString().equals("player-1"),
                        "Decision owner was confused with the turn owner");
                require(decision.getAsJsonArray("combat").size() == 2, "Recorded attack/block links missing");
                System.out.println("PASS " + observer.frames.size() + " event snapshots, two automatic resolutions, intermediate life 17, both private hands and combat relationships");
            }
        }
    }
}
