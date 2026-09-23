// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.game.GameStage;
import forge.game.card.Card;
import forge.game.phase.PhaseType;
import forge.game.player.PlaySpellAbility;
import forge.game.player.Player;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import forge.player.PlayerControllerHuman;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import static org.hexproof.forge.NativeCallbackRegressionTest.*;

/** Kappa's real human cost input, including provisional choices and rollback. */
public final class NativeImproviseRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                prefs.setPref(FPref.UI_SELECT_FROM_CARD_DISPLAYS, false);
                return null;
            });
            JsonObject config = JsonParser.parseString("{\"gameId\":\"native-improvise\",\"seed\":42,\"variant\":\"constructed\",\"startingLife\":20,\"players\":[{\"name\":\"A\",\"deck\":[{\"name\":\"Island\"}]},{\"name\":\"B\",\"deck\":[{\"name\":\"Island\"}]}]}").getAsJsonObject();
            try (NativeSession session = new NativeSession(config, base); var scope = session.context.enter()) {
                base.setTestSession(session);
                Player owner = session.game.getPlayers().get(0);
                session.game.setAge(GameStage.Play);
                session.game.setStartingPlayer(owner);
                session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, owner, false, 2);
                run(session, owner, args[1]);
            }
        }
        System.out.println("PASS native improvise " + args[1]);
    }

    private static void run(NativeSession session, Player owner, String scenario) throws Exception {
        boolean inspect = scenario.equals("selection");
        boolean convoke = scenario.equals("convoke-cancel");
        require(inspect || convoke || scenario.equals("cancel-retry"), "Unknown improvise scenario");
        Card source = card(session.game, owner, convoke ? "Siege Wurm" : "Kappa Cannoneer", ZoneType.Hand);
        Card island = card(session.game, owner, convoke ? "Forest" : "Island", ZoneType.Battlefield);
        List<Card> artifacts = new ArrayList<>();
        artifacts.add(card(session.game, owner, "Ornithopter", ZoneType.Battlefield));
        artifacts.add(card(session.game, owner, "Memnite", ZoneType.Battlefield));
        Card untouched = card(session.game, owner, "Bone Saw", ZoneType.Battlefield);
        Card alreadyTapped = card(session.game, owner, "Ornithopter", ZoneType.Battlefield);
        alreadyTapped.setTapped(true);
        Card opposing = card(session.game, session.game.getPlayers().get(1), "Memnite", ZoneType.Battlefield);
        AtomicInteger clicks = new AtomicInteger(), payments = new AtomicInteger();
        drive(session, owner, () -> {
            int rounds = inspect ? 1 : convoke ? 2 : 3;
            for (int attempt = 0; attempt < rounds; ++attempt) {
                clicks.set(0); payments.set(0);
                if (attempt == 2) for (int i = 0; i < 3; ++i)
                    artifacts.add(card(session.game, owner, "Ornithopter", ZoneType.Battlefield));
                boolean played = PlaySpellAbility.playSpellAbility(
                        (PlayerControllerHuman) owner.getController(), owner, source.getSpellAbilities().get(0));
                require(played == (attempt == 2), "Unexpected Kappa casting result");
                require(artifacts.stream().allMatch(c -> c.isTapped() == played),
                        "Cancelling Kappa left an improvised artifact tapped");
                require(island.isTapped() == played, "Mana-source rollback differs from improvise rollback");
                require(alreadyTapped.isTapped() && !untouched.isTapped() && !opposing.isTapped(),
                        "Rollback changed a permanent outside this payment");
                require(source.isInZone(played ? ZoneType.Stack : ZoneType.Hand), "Kappa returned to the wrong zone");
                require(session.game.getStack().size() == (played ? 1 : 0), "Cancelled Kappa remained on the stack");
                if (played) require(source.getConvoked().isEmpty(), "Improvise was misreported as convoke");
            }
        }, input -> {
            String kind = input.get("type").getAsString();
            if (kind.equals("chooseBoardTargets")) {
                int click = clicks.getAndIncrement();
                if (inspect) {
                    Set<String> expected = switch (click) {
                        case 0 -> Set.of();
                        case 1 -> Set.of(NativeSession.cardId(artifacts.get(0)));
                        case 2 -> Set.of(NativeSession.cardId(artifacts.get(0)), NativeSession.cardId(artifacts.get(1)));
                        default -> Set.of(NativeSession.cardId(artifacts.get(1)));
                    };
                    Set<String> selected = new HashSet<>();
                    for (JsonElement value : input.getAsJsonArray("candidates")) {
                        JsonObject candidate = value.getAsJsonObject();
                        if (candidate.has("selected") && candidate.get("selected").getAsBoolean())
                            selected.add(candidate.get("id").getAsString());
                    }
                    require(selected.equals(expected), "Native improvise selections are missing or stale: " + selected);
                    require(artifacts.stream().noneMatch(Card::isTapped), "Provisional selection already tapped artifacts");
                    // This native selector only offers OK. Cancellation occurs
                    // in the subsequent mana-payment input, after the tap.
                    if (click == 3) return select(input, null);
                    return select(input, artifacts.get(click == 1 ? 1 : 0));
                }
                return select(input, click < artifacts.size() ? artifacts.get(click) : null);
            }
            require(kind.equals("payManaCost"), "Unexpected Kappa input: " + input);
            if (inspect || payments.getAndIncrement() > 0) return NativeSession.object("type", "cancel");
            require(artifacts.stream().allMatch(Card::isTapped), "Confirmed improvise did not tap exact artifacts");
            JsonObject response = NativeSession.object("type", "act");
            response.addProperty("actionId", "card:" + island.getId());
            return response;
        });
    }

    private static JsonObject select(JsonObject input, Card card) {
        JsonArray chosen = new JsonArray();
        if (card != null) chosen.add(input.getAsJsonArray("candidates").asList().stream()
                .map(JsonElement::getAsJsonObject)
                .filter(c -> c.get("id").getAsString().equals(NativeSession.cardId(card)))
                .findFirst().orElseThrow());
        JsonObject response = NativeSession.object("type", "boardTargets");
        response.add("chosen", chosen);
        return response;
    }
}
