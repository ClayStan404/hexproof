// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.game.GameStage;
import forge.game.ability.AbilityFactory;
import forge.game.ability.AbilityUtils;
import forge.game.card.Card;
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.spellability.SpellAbility;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import static org.hexproof.forge.NativeCallbackRegressionTest.*;

/** Public persistent choices and actual Ugin's Labyrinth exile/return effects. */
public final class NativeCardStateRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> { prefs.setPref(FPref.DECKGEN_CARDBASED, false); return null; });
            JsonObject config = JsonParser.parseString("{\"gameId\":\"card-state\",\"seed\":42,\"variant\":\"constructed\",\"startingLife\":20,\"players\":[{\"name\":\"A\",\"deck\":[{\"name\":\"Island\"}]},{\"name\":\"B\",\"deck\":[{\"name\":\"Island\"}]}]}").getAsJsonObject();
            try (NativeSession session = new NativeSession(config, base); var scope = session.context.enter()) {
                base.setTestSession(session);
                Player owner = session.game.getPlayers().get(0);
                session.game.setAge(GameStage.Play);
                session.game.setStartingPlayer(owner);
                session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, owner, false, 2);
                if (args[1].equals("labyrinth")) labyrinth(session, owner);
                else if (args[1].equals("class-level")) classLevel(session, owner);
                else if (args[1].equals("chosen-card")) chosenCard(session, owner);
                else annotations(session, owner);
            }
        }
        System.out.println("PASS native card state " + args[1]);
    }

    private static void classLevel(NativeSession session, Player owner) {
        Card ordinary = card(session.game, owner, "Ornithopter", ZoneType.Battlefield);
        for (int viewer : new int[]{0, 1, -1})
            require(!projected(session, ordinary, viewer).has("annotations"), "Default class level appeared on a non-Class permanent");
        Card talent = card(session.game, owner, "Artist's Talent", ZoneType.Battlefield);
        talent.setClassLevel(1);
        SpellAbility upgrade = talent.getSpellAbilities().stream().filter(a -> a.isClassLevelNAbility(1)).findFirst().orElseThrow();
        upgrade.setActivatingPlayer(owner);
        AbilityUtils.resolve(upgrade);
        require(talent.getClassLevel() == 2, "Actual class ability did not advance its level");
        for (int viewer : new int[]{0, 1, -1}) {
            JsonObject view = projected(session, talent, viewer);
            require(view.has("annotations") && view.getAsJsonArray("annotations").asList().stream().anyMatch(value -> {
                JsonObject annotation = value.getAsJsonObject();
                return annotation.get("kind").getAsString().equals("classLevel") && annotation.get("value").getAsString().equals("2");
            }), "Class level is missing from the current public object");
        }
        owner.getZone(ZoneType.Battlefield).remove(talent); owner.getZone(ZoneType.Hand).add(talent);
        require(!projected(session, talent, 0).has("annotations"), "Old class level followed the object back to hand");
    }

    static JsonObject projected(NativeSession session, Card card, int viewer) {
        JsonObject snapshot = NativeSnapshot.capture(session.game, "card-state", viewer, card.getController());
        for (JsonElement zone : snapshot.getAsJsonArray("zones"))
            for (JsonElement value : zone.getAsJsonObject().getAsJsonArray("cards")) {
                JsonObject candidate = value.getAsJsonObject();
                if (candidate.get("id").getAsString().equals(NativeSnapshot.cardId(card))) return candidate;
            }
        throw new AssertionError("Card missing from projection");
    }

    private static void chosenCard(NativeSession session, Player owner) throws Exception {
        Card source = card(session.game, owner, "Dauntless Bodyguard", ZoneType.Battlefield);
        Card target = card(session.game, owner, "Grizzly Bears", ZoneType.Battlefield);
        card(session.game, owner, "Silvercoat Lion", ZoneType.Battlefield);
        AtomicInteger choices = new AtomicInteger();
        drive(session, owner, () -> {
            SpellAbility choose = AbilityFactory.getAbility(source.getSVar("ChooseC"), source);
            choose.setActivatingPlayer(owner);
            AbilityUtils.resolve(choose);
            require(source.getChosenCard().equalsWithGameTimestamp(target), "Bodyguard chose a different creature");
            for (int viewer : new int[]{0, 1, -1}) {
                JsonObject view = projected(session, source, viewer);
                require(view.has("chosenCardIds") && view.getAsJsonArray("chosenCardIds").size() == 1
                        && view.getAsJsonArray("chosenCardIds").get(0).getAsString().equals(NativeSnapshot.cardId(target)),
                        "Chosen creature is missing for viewer " + viewer);
            }
            Card returned = session.game.getAction().moveToHand(target, null);
            for (int viewer : new int[]{0, 1, -1})
                require(!projected(session, source, viewer).has("chosenCardIds"), "Old choice followed a zone change");
            Card blinked = session.game.getAction().moveToPlay(returned, null, null);
            require(blinked.getId() == target.getId() && !blinked.equalsWithGameTimestamp(target),
                    "Blink fixture did not retain the id with a new timestamp");
            for (int viewer : new int[]{0, 1, -1})
                require(!projected(session, source, viewer).has("chosenCardIds"), "Old choice reattached after a blink");

            Card secret = card(session.game, owner, "Black Lotus", ZoneType.Hand);
            source.setChosenCards(List.of(secret));
            require(projected(session, source, 0).has("chosenCardIds"), "Owner lost their visible chosen card");
            for (int viewer : new int[]{1, -1})
                require(!projected(session, source, viewer).has("chosenCardIds"), "Private chosen card leaked");
            source.setChosenCards(List.of(blinked));
            source.turnFaceDown(true);
            for (int viewer : new int[]{0, 1, -1})
                require(!projected(session, source, viewer).has("chosenCardIds"), "Face-down source exposed a choice");
        }, input -> {
            require(input.get("type").getAsString().equals("chooseCards"), "Unexpected Bodyguard input: " + input);
            choices.incrementAndGet();
            JsonObject response = NativeSession.object("type", "chooseCardsDecision");
            JsonArray ids = new JsonArray(); ids.add(NativeSession.cardId(target));
            response.add("chosenCardIds", ids); return response;
        });
        require(choices.get() == 1, "Bodyguard did not request one actual creature choice");
    }

    private static void annotations(NativeSession session, Player owner) {
        Card source = card(session.game, owner, "Pithing Needle", ZoneType.Battlefield);
        source.addNamedCard("Black Lotus");
        source.setChosenType("Elf");
        source.setChosenColors(List.of("Blue", "Red"));
        source.setChosenNumber(0);
        source.setChosenMode("Khans");
        for (int viewer : new int[]{0, 1, -1}) {
            JsonObject view = projected(session, source, viewer);
            require(view.has("annotations"), "Persistent choices are missing from the battlefield");
            String choices = view.getAsJsonArray("annotations").toString();
            for (String expected : List.of("Black Lotus", "Elf", "Blue", "Red", "Khans", "\"value\":\"0\""))
                require(choices.contains(expected), "Public choice is missing: " + expected);
        }
        source.setSecretChosenType("SECRET_TYPE");
        source.setChosenNumber(987654, true);
        for (int viewer : new int[]{0, 1, -1}) {
            String view = projected(session, source, viewer).toString();
            require(!view.contains("SECRET_TYPE") && !view.contains("987654"), "Unrevealed native choice leaked");
        }
        source.turnFaceDown(true);
        for (int viewer : new int[]{1, -1})
            require(!projected(session, source, viewer).has("annotations"), "Face-down source leaked choices");
    }

    private static void labyrinth(NativeSession session, Player owner) throws Exception {
        List<Card> sources = List.of(card(session.game, owner, "Ugin's Labyrinth", ZoneType.Battlefield),
                card(session.game, owner, "Ugin's Labyrinth", ZoneType.Battlefield));
        List<Card> exiles = List.of(card(session.game, owner, "Ulamog, the Ceaseless Hunger", ZoneType.Hand),
                card(session.game, owner, "Thought Monitor", ZoneType.Hand));
        // Thought Monitor is blue and must remain in hand; use a second legal colorless card.
        Card second = card(session.game, owner, "Devourer of Destiny", ZoneType.Hand);
        AtomicInteger choices = new AtomicInteger();
        drive(session, owner, () -> {
            for (Card source : sources) {
                SpellAbility ability = AbilityFactory.getAbility(source.getSVar("TrigExile"), source);
                ability.setActivatingPlayer(owner);
                AbilityUtils.resolve(ability);
            }
            for (int viewer : new int[]{0, 1, -1}) {
                JsonObject first = projected(session, sources.get(0), viewer);
                JsonObject other = projected(session, sources.get(1), viewer);
                require(first.has("exiledCardIds") && first.get("exiledCardCount").getAsInt() == 1,
                        "Actual Labyrinth imprint is missing from its public state");
                require(!first.get("exiledCardIds").equals(other.get("exiledCardIds")), "Identical lands share another land's exile");
            }
            SpellAbility back = sources.get(0).getSpellAbilities().stream()
                    .filter(sa -> "ExiledWith".equals(sa.getParam("Defined"))).findFirst().orElseThrow();
            back.setActivatingPlayer(owner);
            AbilityUtils.resolve(back);
            require(owner.getCardsIn(ZoneType.Hand).stream().anyMatch(c -> c.getName().equals(exiles.get(0).getName())), "Labyrinth did not return the card");
            for (int viewer : new int[]{0, 1, -1}) {
                require(!projected(session, sources.get(0), viewer).has("exiledCardCount"), "Returned imprint remained on the source");
                require(projected(session, sources.get(1), viewer).get("exiledCardCount").getAsInt() == 1, "Returning one imprint removed another");
            }
        }, input -> {
            String type = input.get("type").getAsString();
            if (type.equals("revealCards")) return NativeSession.object("type", "revealCardsAcknowledged");
            require(type.equals("chooseCards"), "Unexpected Labyrinth input: " + input);
            JsonObject response = NativeSession.object("type", "chooseCardsDecision");
            JsonArray ids = new JsonArray();
            ids.add(NativeSession.cardId(choices.getAndIncrement() == 0 ? exiles.get(0) : second));
            response.add("chosenCardIds", ids); return response;
        });
        require(choices.get() == 2, "Labyrinth did not make two independent choices");
    }
}
