// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.game.GameStage;
import forge.game.ability.AbilityUtils;
import forge.game.card.Card;
import forge.game.card.CardCollection;
import forge.game.phase.PhaseType;
import forge.game.player.DelayedReveal;
import forge.game.player.Player;
import forge.game.spellability.SpellAbility;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import static org.hexproof.forge.NativeCallbackRegressionTest.*;

/** Combined private looks and legal choices on real effects and constructed boards. */
public final class NativeDelayedRevealRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                prefs.setPref(FPref.UI_SELECT_FROM_CARD_DISPLAYS, false);
                return null;
            });
            for (String scenario : List.of("company", "single", "fetch", "discard", "no-discard", "no-choice")) {
                JsonObject config = JsonParser.parseString("{\"gameId\":\"delayed-reveal-test\",\"seed\":42,\"variant\":\"constructed\",\"startingLife\":20,\"players\":[{\"name\":\"Reveal A\",\"deck\":[{\"name\":\"Forest\"}]},{\"name\":\"Reveal B\",\"deck\":[{\"name\":\"Forest\"}]}]}").getAsJsonObject();
                try (NativeSession session = new NativeSession(config, base); var scope = session.context.enter()) {
                    base.setTestSession(session);
                    session.game.setAge(GameStage.Play);
                    Player owner = session.game.getPlayers().get(0);
                    session.game.setStartingPlayer(owner);
                    session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, owner, false, 1);
                    switch (scenario) {
                        case "company", "single" -> run(session, owner, scenario.equals("single"));
                        case "fetch" -> fetch(session, owner);
                        case "discard", "no-discard" -> discard(session, owner, scenario.equals("no-discard"));
                        case "no-choice" -> noChoice(session, owner);
                        default -> throw new AssertionError(scenario);
                    }
                }
            }
        }
        System.out.println("PASS native combined choices: Company, fetch, Thoughtseize, no legal choice, privacy and invalid responses");
    }

    private static void run(NativeSession session, Player owner, boolean single) throws Exception {
        Card bears = card(session.game, owner, "Grizzly Bears", ZoneType.Library);
        Card elves = card(session.game, owner, "Llanowar Elves", ZoneType.Library);
        Card bolt = card(session.game, owner, "Lightning Bolt", ZoneType.Library);
        Card forest = card(session.game, owner, "Forest", ZoneType.Library);
        Card dreadmaw = card(session.game, owner, "Colossal Dreadmaw", ZoneType.Library);
        Card mountain = card(session.game, owner, "Mountain", ZoneType.Library);
        Card unlooked = card(session.game, owner, "Primeval Titan", ZoneType.Library);
        Card privateHand = card(session.game, owner, "Solitude", ZoneType.Hand);
        Card opposingHand = card(session.game, session.game.getPlayers().get(1), "Thoughtseize", ZoneType.Hand);
        Card company = card(session.game, owner, "Collected Company", ZoneType.Hand);
        List<Card> topSix = List.of(bears, elves, bolt, forest, dreadmaw, mountain);
        Set<String> lookedNames = new HashSet<>();
        for (Card c : topSix) lookedNames.add(c.getName());
        SpellAbility ability = company.getSpellAbilities().get(0);
        ability.setActivatingPlayer(owner);
        AtomicInteger decisions = new AtomicInteger();
        drive(session, owner, () -> {
            if (single) {
                Card chosen = owner.getController().chooseSingleEntityForEffect(
                        new CardCollection(List.of(bears, elves)),
                        new DelayedReveal(topSix, ZoneType.Library, owner.getView()),
                        ability, "Choose one of the eligible creatures", false, owner, null);
                require(chosen == bears, "Native single-choice callback changed the explicit selection");
            } else {
                // Choose zero creatures, a legal CoCo decision, so the policy can
                // focus on the owner's private look without another seat's reveal.
                AbilityUtils.resolve(ability);
                require(owner.getCardsIn(ZoneType.Battlefield).isEmpty(), "CoCo ignored the explicit empty selection");
                List<Card> library = new ArrayList<>(owner.getCardsIn(ZoneType.Library));
                require(library.size() == 7 && library.get(0) == unlooked,
                        "CoCo did not put the six inspected cards beneath the unlooked seventh card");
            }
        }, input -> {
            String type = input.get("type").getAsString();
            String raw = input.toString();
            for (Card secret : List.of(unlooked, privateHand, opposingHand)) {
                require(!raw.contains(secret.getName()), "Delayed reveal included an unrelated private identity");
                require(!raw.contains("\"" + NativeSession.cardId(secret) + "\""), "Delayed reveal included an unrelated private object ID");
            }
            for (int viewer : List.of(-1, 1)) {
                String snapshot = session.snapshot(viewer);
                for (Card looked : topSix) {
                    require(!snapshot.contains("\"name\":\"" + looked.getName() + "\""), "Private library look leaked into another viewer's snapshot");
                    require(!snapshot.contains("\"" + NativeSession.cardId(looked) + "\""), "Private library object ID leaked into another viewer's snapshot");
                }
            }
            JsonObject envelope = JsonParser.parseString(session.prompt(0)).getAsJsonObject();
            require(envelope.get("decidingPlayerId").getAsString().equals("player-0"),
                    "Private delayed reveal assigned the wrong deciding player");
            int decision = decisions.getAndIncrement();
            if (decision == 0) {
                require(type.equals("chooseCards"), "Private look must be part of the choice without an acknowledgement");
                checkCards(input, lookedNames, Set.of("Grizzly Bears", "Llanowar Elves"));
                rejectCard(session, forest);
                JsonObject response = NativeSession.object("type", "chooseCardsDecision");
                JsonArray chosen = new JsonArray();
                if (single) chosen.add(NativeSession.cardId(bears));
                response.add("chosenCardIds", chosen);
                return response;
            }
            require(!single && decision == 1 && type.equals("reorder"), "Unexpected delayed-reveal callback");
            JsonObject response = NativeSession.object("type", "reorderDecision");
            JsonArray ordered = new JsonArray();
            for (JsonElement item : input.getAsJsonArray("items")) ordered.add(item.getAsJsonObject().get("id"));
            require(ordered.size() == 6, "CoCo omitted cards from the bottom-library ordering");
            response.add("orderedIds", ordered);
            return response;
        });
        require(decisions.get() == (single ? 1 : 2), "Missing native delayed-reveal decisions");
    }

    private static void checkCards(JsonObject input, Set<String> expected, Set<String> eligible) {
        Set<String> names = new HashSet<>(), selectable = new HashSet<>();
        for (JsonElement element : input.getAsJsonArray("cards")) {
            JsonObject card = element.getAsJsonObject();
            String name = card.getAsJsonObject("identity").get("name").getAsString();
            names.add(name);
            if (!card.has("readOnly") || !card.get("readOnly").getAsBoolean()) selectable.add(name);
        }
        require(names.equals(expected), "Combined choice changed the authorized disclosure: " + names);
        require(selectable.equals(eligible), "Combined choice changed legal candidates: " + selectable);
    }

    private static JsonObject choose(Card card) {
        JsonObject output = NativeSession.object("type", "chooseCardsDecision");
        JsonArray cards = new JsonArray();
        if (card != null) cards.add(NativeSession.cardId(card));
        output.add("chosenCardIds", cards);
        return output;
    }

    private static void rejectCard(NativeSession session, Card card) {
        String original = session.prompt(0);
        JsonObject response = NativeSession.object("type", "chooseCards");
        response.add("output", choose(card));
        boolean rejected = false;
        try { session.submit(response); } catch (IllegalArgumentException expected) { rejected = true; }
        require(rejected && original.equals(session.prompt(0)), "Read-only card submission consumed the choice");
    }

    private static void fetch(NativeSession session, Player owner) throws Exception {
        Card swamp = card(session.game, owner, "Swamp", ZoneType.Library);
        card(session.game, owner, "Island", ZoneType.Library);
        Card forest = card(session.game, owner, "Forest", ZoneType.Library);
        card(session.game, owner, "Grizzly Bears", ZoneType.Library);
        Card source = card(session.game, owner, "Polluted Delta", ZoneType.Battlefield);
        SpellAbility ability = source.getSpellAbilities().stream()
                .filter(sa -> sa.getApi() == forge.game.ability.ApiType.ChangeZone).findFirst().orElseThrow();
        ability.setActivatingPlayer(owner);
        AtomicInteger decisions = new AtomicInteger();
        drive(session, owner, () -> {
            AbilityUtils.resolve(ability);
            require(owner.getCardsIn(ZoneType.Battlefield).stream().anyMatch(c -> c.getId() == swamp.getId()), "Fetch failed to move the selected land");
            require(forest.isInZone(ZoneType.Library), "Fetch moved a nonselectable card");
        }, input -> {
            require(input.get("type").getAsString().equals("chooseCards"), "Fetch required a separate reveal");
            checkCards(input, Set.of("Swamp", "Island", "Forest", "Grizzly Bears"), Set.of("Swamp", "Island"));
            require(!session.snapshot(1).contains("Grizzly Bears") && !session.snapshot(-1).contains("Grizzly Bears"),
                    "Fetch look escaped the deciding seat");
            rejectCard(session, forest);
            decisions.incrementAndGet();
            return choose(swamp);
        });
        require(decisions.get() == 1, "Fetch should need only one choice");
    }

    private static void discard(NativeSession session, Player owner, boolean noChoice) throws Exception {
        Player opponent = session.game.getPlayers().get(1);
        Card land = card(session.game, opponent, "Forest", ZoneType.Hand);
        Card chosen = noChoice ? null : card(session.game, opponent, "Grizzly Bears", ZoneType.Hand);
        Card hidden = card(session.game, opponent, "Primeval Titan", ZoneType.Library);
        Card source = card(session.game, owner, "Thoughtseize", ZoneType.Hand);
        SpellAbility ability = source.getSpellAbilities().get(0);
        ability.setActivatingPlayer(owner);
        ability.getTargets().add(opponent);
        AtomicInteger decisions = new AtomicInteger();
        drive(session, owner, () -> {
            AbilityUtils.resolve(ability);
            require(land.isInZone(ZoneType.Hand), "Thoughtseize discarded a land");
            if (!noChoice) require(chosen.isInZone(ZoneType.Graveyard), "Thoughtseize ignored the selected nonland");
            require(owner.getLife() == 18, "Thoughtseize failed to finish resolving");
        }, input -> {
            int decision = decisions.getAndIncrement();
            require(!input.toString().contains(hidden.getName()), "Thoughtseize disclosed the library");
            if (decision == 0 && !noChoice) {
                require(input.get("type").getAsString().equals("chooseCards"), "Thoughtseize required a separate hand reveal");
                checkCards(input, Set.of("Forest", "Grizzly Bears"), Set.of("Grizzly Bears"));
                require(!session.snapshot(-1).contains("Grizzly Bears"), "Private selection leaked to spectator");
                rejectCard(session, land);
                return choose(chosen);
            }
            require(input.get("type").getAsString().equals("revealCards"), "Standalone disclosure was lost");
            require(input.getAsJsonArray("cards").size() == 1, "Disclosure included extra cards");
            return NativeSession.object("type", "revealCardsAcknowledged");
        });
        require(decisions.get() == (noChoice ? 1 : 2), "Thoughtseize disclosure/choice count changed");
    }

    private static void noChoice(NativeSession session, Player owner) throws Exception {
        Card forest = card(session.game, owner, "Forest", ZoneType.Library);
        Card source = card(session.game, owner, "Collected Company", ZoneType.Hand);
        AtomicInteger decisions = new AtomicInteger();
        drive(session, owner, () -> {
            Card result = owner.getController().chooseSingleEntityForEffect(new CardCollection(),
                    new DelayedReveal(List.of(forest), ZoneType.Library, owner.getView()),
                    source.getSpellAbilities().get(0), "No eligible creatures", false, owner, null);
            require(result == null, "Empty candidates produced a card");
        }, input -> {
            require(input.get("type").getAsString().equals("revealCards"), "Empty choice lost its disclosure");
            require(input.getAsJsonArray("cards").size() == 1, "Empty choice omitted the visible card");
            decisions.incrementAndGet();
            return NativeSession.object("type", "revealCardsAcknowledged");
        });
        require(decisions.get() == 1, "Empty choice should retain one standalone disclosure");
    }
}
