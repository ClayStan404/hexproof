// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package org.hexproof.forge;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import forge.card.MagicColor;
import forge.deck.Deck;
import forge.game.Game;
import forge.game.GameEndReason;
import forge.game.GameRules;
import forge.game.GameStage;
import forge.game.GameType;
import forge.game.Match;
import forge.game.card.Card;
import forge.game.card.CardFactory;
import forge.game.card.CounterEnumType;
import forge.game.mana.Mana;
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.player.PlayerOutcome;
import forge.game.player.RegisteredPlayer;
import forge.game.spellability.SpellAbility;
import forge.game.spellability.AbilitySub;
import forge.game.ability.AbilityFactory;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences;
import forge.model.FModel;
import forge.player.LobbyPlayerHuman;
import java.util.List;

/** Synthetic boards exercise projection/privacy; no full-game coverage is claimed. */
public final class NativeSnapshotRegressionTest {
    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase gui = new NativeGuiBase(args[0])) {
            GuiBase.setInterface(gui.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(ForgePreferences.FPref.DECKGEN_CARDBASED, false);
                return null;
            });
            run();
        }
    }

    static void run() {
        Game game = new Match(new GameRules(GameType.Constructed), List.of(
                new RegisteredPlayer(new Deck()).setPlayer(new LobbyPlayerHuman("Snapshot A")),
                new RegisteredPlayer(new Deck()).setPlayer(new LobbyPlayerHuman("Snapshot B"))), "snapshot-regression").createGame();
        game.setAge(GameStage.Play);
        Player owner = game.getPlayers().get(0);
        Player opponent = game.getPlayers().get(1);
        game.setStartingPlayer(opponent);
        game.getPhaseHandler().devModeSet(PhaseType.MAIN1, owner, false, 2);
        Card hand = card(game, owner, "Lightning Bolt", ZoneType.Hand);
        Card opponentHand = card(game, opponent, "Black Lotus", ZoneType.Hand);
        Card top = card(game, owner, "Ancestral Recall", ZoneType.Library);
        Card below = card(game, owner, "Time Walk", ZoneType.Library);
        Card otherLibrary = card(game, opponent, "Demonic Tutor", ZoneType.Library);
        card(game, opponent, "Force of Will", ZoneType.Sideboard);
        Card battlefield = card(game, owner, "Grizzly Bears", ZoneType.Battlefield);
        battlefield.setTapped(true);
        battlefield.setCounters(CounterEnumType.P1P1, 2);
        battlefield.setDamage(1);
        Card aura = card(game, owner, "Rancor", ZoneType.Battlefield);
        aura.attachToEntity(battlefield, null);
        owner.getManaPool().addMana(new Mana(MagicColor.GREEN, battlefield, null, owner));
        owner.setCounters(CounterEnumType.ENERGY, 3);
        Card graveyard = card(game, opponent, "Shock", ZoneType.Graveyard);
        Card commander = card(game, owner, "Isamaru, Hound of Konda", ZoneType.Command);
        Card partner = card(game, owner, "Keleth, Sunmane Familiar", ZoneType.Command);
        owner.addCommander(commander);
        owner.addCommander(partner);
        owner.incCommanderCast(commander);
        owner.incCommanderCast(commander);
        Card faceDown = card(game, owner, "Willbender", ZoneType.Battlefield);
        faceDown.turnFaceDown(true);
        Card secretExile = card(game, opponent, "Phage the Untouchable", ZoneType.Exile);
        secretExile.turnFaceDown(true);
        Card allowedExile = card(game, owner, "Serra Angel", ZoneType.Exile);
        allowedExile.turnFaceDown(true);
        allowedExile.addMayLookFaceDownExile(owner);
        Card publicStack = card(game, owner, "Giant Growth", ZoneType.Stack);
        SpellAbility publicAbility = publicStack.getSpellAbilities().get(0);
        publicAbility.setActivatingPlayer(owner);
        publicAbility.getTargets().add(battlefield);
        AbilitySub sub = (AbilitySub) AbilityFactory.getAbility("DB$ Pump | ValidTgts$ Creature | NumAtt$ 1 | NumDef$ 1", publicStack);
        sub.getTargets().add(battlefield);
        publicAbility.setSubAbility(sub);
        publicAbility.setStackDescription("Giant Growth: target creature gets +3/+3.");
        game.getStack().add(publicAbility);
        // Add projection-only references after the native legality check.
        // These synthetic targets test redaction, not this spell's rules.
        publicAbility.getTargets().add(faceDown);
        publicAbility.getTargets().add(hand);
        sub.getTargets().add(opponent);
        Card hiddenStack = card(game, owner, "Exalted Angel", ZoneType.Stack);
        SpellAbility hiddenAbility = hiddenStack.getSpellAbilities().stream()
                .filter(SpellAbility::isCastFaceDown).findFirst().orElseThrow();
        hiddenAbility.setActivatingPlayer(owner);
        hiddenAbility.setStackDescription("Exalted Angel PRIVATE_PRINTING_MARKER");
        hiddenStack.turnFaceDown(true);
        game.getStack().add(hiddenAbility);

        Card counter = card(game, opponent, "Counterspell", ZoneType.Stack);
        SpellAbility counterAbility = counter.getSpellAbilities().get(0);
        counterAbility.setActivatingPlayer(opponent);
        counterAbility.getTargets().add(publicAbility);
        counterAbility.setStackDescription("Counterspell: counter target spell.");
        game.getStack().add(counterAbility);

        JsonObject own = NativeSnapshot.capture(game, "snapshot-regression", 0, opponent);
        JsonObject other = NativeSnapshot.capture(game, "snapshot-regression", 1, opponent);
        JsonObject spectator = NativeSnapshot.capture(game, "snapshot-regression", -1, opponent);
        check(own.get("priorityPlayerId").getAsString().equals("player-1"), "native priority override lost");
        check(own.get("activePlayerId").getAsString().equals("player-0"), "active player mapping lost");
        check(own.get("startingPlayerId").getAsString().equals("player-1"), "starting player mapping lost");
        check(zone(own, 0, "hand").getAsJsonArray("cards").size() == 1, "owner cannot see hand");
        check(zone(other, 0, "hand").getAsJsonArray("cards").isEmpty(), "opponent can see private hand IDs");
        check(zone(spectator, 0, "hand").get("count").getAsInt() == 1, "hidden hand count lost");
        check(zone(spectator, 1, "hand").getAsJsonArray("cards").isEmpty(), "spectator borrowed opponent view");
        for (JsonObject view : List.of(own, other, spectator)) {
            check(zone(view, 0, "library").getAsJsonArray("cards").isEmpty(), "unknown library exposed");
            check(zone(view, 0, "library").get("count").getAsInt() == 2, "library count lost");
            assertAbsent(view, "Force of Will", "Time Walk", "Demonic Tutor", "Phage the Untouchable", "Exalted Angel", "PRIVATE_PRINTING_MARKER");
            check(view.getAsJsonArray("stack").size() == 3, "stack objects omitted");
            JsonArray stack = view.getAsJsonArray("stack");
            JsonObject first = stack.get(0).getAsJsonObject();
            JsonObject last = stack.get(2).getAsJsonObject();
            check(first.getAsJsonObject("identity").get("name").getAsString().equals("Counterspell"), "native stack must be top-first");
            check(first.getAsJsonArray("targets").get(0).getAsJsonObject().get("id").equals(last.get("id")), "counterspell lost the exact stack target");
            JsonArray targets = last.getAsJsonArray("targets");
            check(targets.size() == (view == own ? 4 : 3), "stack targets omit public objects or expose private hand IDs");
            check(targets.get(targets.size() - 1).getAsJsonObject().get("id").getAsString().equals("player-1"), "native sub-instance player target lost");
            check(view.toString().contains("Face-down spell"), "face-down stack text not anonymized");
            for (var element : view.getAsJsonArray("stack")) {
                JsonObject entry = element.getAsJsonObject();
                if (entry.get("text").getAsString().equals("Face-down spell")) {
                    check(entry.getAsJsonObject("identity").isEmpty(), "anonymous stack identity contains a printing name");
                }
            }
            check(view.toString().contains("Giant Growth"), "public spell omitted");
            check(findCard(view, graveyard).has("identity"), "public graveyard omitted");
        }
        assertAbsent(other, "Lightning Bolt", "Willbender", "Serra Angel", NativeSnapshot.cardId(hand));
        assertAbsent(spectator, "Lightning Bolt", "Black Lotus", "Willbender", "Serra Angel", NativeSnapshot.cardId(hand), NativeSnapshot.cardId(opponentHand));
        check(findCard(own, faceDown).getAsJsonObject("identity").get("name").getAsString().equals("Willbender"), "controller lost face-down lookup");
        check(findCard(other, faceDown).getAsJsonObject("identity").isEmpty(), "face-down printing leaked to opponent");
        check(findCard(spectator, faceDown).getAsJsonObject("identity").isEmpty(), "face-down printing leaked to spectator");
        check(findCard(spectator, faceDown).get("visibility").getAsString().equals("visible"), "anonymous battlefield object is not actionable");
        check(findCard(spectator, faceDown).get("power").getAsString().equals("2"), "face-down public power lost");
        check(!findCard(own, secretExile).has("identity") && !findCard(other, secretExile).has("identity"), "exile ownership granted an illegal lookup");
        check(findCard(own, allowedExile).has("identity") && !findCard(other, allowedExile).has("identity"), "explicit face-down exile visibility lost");
        check(findCard(spectator, battlefield).get("tapped").getAsBoolean(), "public tapped state lost");
        check(findCard(spectator, battlefield).get("damage").getAsInt() == 1, "public marked damage lost");
        check(findCard(spectator, battlefield).getAsJsonObject("counters").size() == 1, "public counters lost");
        check(findCard(spectator, aura).get("attachedTo").getAsString().equals(NativeSnapshot.cardId(battlefield)), "attachment relation lost");
        check(spectator.getAsJsonArray("players").get(0).getAsJsonObject().getAsJsonObject("manaPool").get("G").getAsInt() == 1, "public mana pool lost");

        // The native permission oracle authorizes the owner without granting spectators access.
        top.addMayLookAt(100L, List.of(owner));
        below.addMayLookAt(101L, List.of(owner));
        JsonObject withLook = NativeSnapshot.capture(game, "snapshot-regression", 0, opponent);
        JsonArray topCards = zone(withLook, 0, "library").getAsJsonArray("cards");
        check(topCards.size() == 1 && topCards.get(0).getAsJsonObject().get("id").getAsString().equals(NativeSnapshot.cardId(top)), "library top visibility/order is wrong");
        assertAbsent(withLook, "Time Walk");
        check(zone(NativeSnapshot.capture(game, "snapshot-regression", -1, opponent), 0, "library").getAsJsonArray("cards").isEmpty(), "private top look leaked to spectator");
        top.removeMayLookAt(100L);
        check(zone(NativeSnapshot.capture(game, "snapshot-regression", 0, opponent), 0, "library").getAsJsonArray("cards").isEmpty(), "revoked top-card permission persisted");

        String captured = spectator.toString();
        JsonArray commanderViews = spectator.getAsJsonArray("players").get(0).getAsJsonObject().getAsJsonArray("commanders");
        check(commanderViews.size() == 2, "multiple commander designations lost");
        JsonObject firstCommander = commanderViews.get(0).getAsJsonObject();
        check(firstCommander.get("casts").getAsInt() == 2 && firstCommander.get("tax").getAsInt() == 4,
                "commander cast history/surcharge lost");
        check(firstCommander.get("objectId").getAsString().equals(NativeSnapshot.cardId(commander))
                && firstCommander.get("zone").getAsString().equals("command"), "public commander link lost");
        check(commanderViews.get(1).getAsJsonObject().get("casts").getAsInt() == 0, "partners share a cast counter");
        owner.getZone(ZoneType.Command).remove(commander);
        owner.getZone(ZoneType.Hand).add(commander);
        JsonObject privateCommander = NativeSnapshot.capture(game, "snapshot-regression", -1, opponent)
                .getAsJsonArray("players").get(0).getAsJsonObject().getAsJsonArray("commanders").get(0).getAsJsonObject();
        check(!privateCommander.has("objectId") && privateCommander.get("zone").getAsString().equals("hidden"),
                "commander summary leaked a hidden hand link");
        JsonObject ownCommander = NativeSnapshot.capture(game, "snapshot-regression", 0, opponent)
                .getAsJsonArray("players").get(0).getAsJsonObject().getAsJsonArray("commanders").get(0).getAsJsonObject();
        check(ownCommander.get("zone").getAsString().equals("hand"), "owner lost visible commander location");
        owner.getZone(ZoneType.Hand).remove(commander);
        owner.getZone(ZoneType.Library).add(commander);
        commander.addMayLookAt(102L, List.of(owner));
        ownCommander = NativeSnapshot.capture(game, "snapshot-regression", 0, opponent)
                .getAsJsonArray("players").get(0).getAsJsonObject().getAsJsonArray("commanders").get(0).getAsJsonObject();
        check(!ownCommander.has("objectId"), "commander summary exposed a non-top library card");
        battlefield.setTapped(false);
        card(game, owner, "Mountain", ZoneType.Hand);
        check(captured.equals(spectator.toString()), "published JSON retains live Forge state");
        check(!captured.equals(NativeSnapshot.capture(game, "snapshot-regression", -1, opponent).toString()), "new stable boundary did not update public state");
        owner.getStats().setOutcome(PlayerOutcome.concede());
        opponent.getStats().setOutcome(PlayerOutcome.win());
        game.setGameOver(GameEndReason.AllOpponentsLost);
        JsonObject terminal = NativeSnapshot.capture(game, "snapshot-regression", -1, opponent);
        check(terminal.get("gameOver").getAsBoolean() && terminal.get("winnerId").getAsString().equals("player-1"), "terminal winner lost");
        check(terminal.getAsJsonArray("players").get(0).getAsJsonObject().get("status").getAsString().equals("conceded"), "concession status lost");
        assertAbsent(terminal, "Lightning Bolt", "Black Lotus", "Force of Will", NativeSnapshot.cardId(otherLibrary));
        System.out.println("NATIVE_SNAPSHOT_REGRESSION_PASS: owner/opponent/spectator privacy, native look permissions, face-down stack, public state, detached publication, terminal outcome");
    }

    private static Card card(Game game, Player owner, String name, ZoneType zone) {
        Card card = CardFactory.getCard(FModel.getMagicDb().getCommonCards().getCard(name), owner, game);
        if (zone == ZoneType.Stack) game.getStackZone().add(card);
        else owner.getZone(zone).add(card);
        return card;
    }

    private static JsonObject zone(JsonObject view, int player, String zone) {
        for (var element : view.getAsJsonArray("zones")) {
            JsonObject candidate = element.getAsJsonObject();
            if (candidate.get("ownerId").getAsString().equals("player-" + player)
                    && candidate.get("zone").getAsString().equals(zone)) return candidate;
        }
        throw new AssertionError("Missing zone " + zone);
    }

    private static JsonObject findCard(JsonObject view, Card card) {
        for (var zone : view.getAsJsonArray("zones")) {
            for (var element : zone.getAsJsonObject().getAsJsonArray("cards")) {
                JsonObject candidate = element.getAsJsonObject();
                if (candidate.get("id").getAsString().equals(NativeSnapshot.cardId(card))) return candidate;
            }
        }
        throw new AssertionError("Missing public card " + card.getId());
    }

    private static void assertAbsent(JsonObject value, String... secrets) {
        String raw = value.toString();
        for (String secret : secrets) {
            String needle = secret.startsWith("card-") ? "\"" + secret + "\"" : secret;
            check(!raw.contains(needle), "Private data leaked: " + secret);
        }
    }

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
