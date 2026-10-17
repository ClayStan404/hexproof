// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package org.hexproof.forge;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import forge.deck.Deck;
import forge.game.Game;
import forge.game.GameRules;
import forge.game.GameStage;
import forge.game.GameType;
import forge.game.Match;
import forge.game.card.Card;
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.player.RegisteredPlayer;
import forge.game.spellability.SpellAbility;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgePreferences;
import forge.model.FModel;
import forge.player.LobbyPlayerHuman;
import java.util.List;
import java.util.Map;
import static org.hexproof.forge.NativeCallbackRegressionTest.card;
import static org.hexproof.forge.NativeCallbackRegressionTest.require;

/**
 * Forge keeps a physical card's numeric id across the zone changes the table
 * animates. The published snapshot uses that same id.
 */
public final class NativeIdContinuityRegressionTest {
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
        System.out.println("PASS native id continuity");
    }

    private static void run() {
        Game game = new Match(new GameRules(GameType.Constructed), List.of(
                new RegisteredPlayer(new Deck()).setPlayer(new LobbyPlayerHuman("Continuity A")),
                new RegisteredPlayer(new Deck()).setPlayer(new LobbyPlayerHuman("Continuity B"))),
                "id-continuity").createGame();
        game.setAge(GameStage.Play);
        Player owner = game.getPlayers().get(0);
        game.setStartingPlayer(owner);
        game.getPhaseHandler().devModeSet(PhaseType.MAIN1, owner, false, 2);

        Card bears = card(game, owner, "Grizzly Bears", ZoneType.Hand);
        Card stacked = game.getAction().moveToStack(bears, null);
        same(game, "hand to stack", bears, stacked, null);
        spell(game, stacked);

        Card plains = card(game, owner, "Plains", ZoneType.Hand);
        same(game, "hand to battlefield", plains, game.getAction().moveToPlay(plains, null, null), "battlefield");

        Card growth = card(game, owner, "Grizzly Bears", ZoneType.Hand);
        Card growthStack = game.getAction().moveToStack(growth, null);
        same(game, "stack to battlefield", growthStack, game.getAction().moveToPlay(growthStack, null, null), "battlefield");

        Card shock = card(game, owner, "Hill Giant", ZoneType.Hand);
        Card shockStack = game.getAction().moveToStack(shock, null);
        same(game, "stack to graveyard", shockStack, game.getAction().moveToGraveyard(shockStack, null), "graveyard");

        Card recall = card(game, owner, "Runeclaw Bear", ZoneType.Hand);
        Card recallStack = game.getAction().moveToStack(recall, null);
        same(game, "stack to exile", recallStack, game.getAction().exile(recallStack, null, Map.of()), "exile");

        Card bearsPermanent = card(game, owner, "Grizzly Bears", ZoneType.Battlefield);
        same(game, "battlefield to graveyard", bearsPermanent, game.getAction().moveToGraveyard(bearsPermanent, null), "graveyard");

        Card lion = card(game, owner, "Silvercoat Lion", ZoneType.Battlefield);
        same(game, "battlefield to exile", lion, game.getAction().exile(lion, null, Map.of()), "exile");

        Card giant = card(game, owner, "Hill Giant", ZoneType.Battlefield);
        same(game, "battlefield to hand", giant, game.getAction().moveToHand(giant, null), "hand");

        Card drawn = card(game, owner, "Llanowar Elves", ZoneType.Library);
        same(game, "library to hand", drawn, game.getAction().moveToHand(drawn, null), "hand");

        Card commander = card(game, owner, "Isamaru, Hound of Konda", ZoneType.Command);
        same(game, "command to battlefield", commander, game.getAction().moveToPlay(commander, null, null), "battlefield");

        Card returning = card(game, owner, "Keleth, Sunmane Familiar", ZoneType.Battlefield);
        int returningId = returning.getId();
        game.getAction().moveToCommand(returning, null);
        Card commanded = owner.getCardsIn(ZoneType.Command).stream()
                .filter(candidate -> candidate.getId() == returningId).findFirst().orElse(null);
        same(game, "battlefield to command", returning, commanded, "command");
    }

    private static void spell(Game game, Card card) {
        String id = NativeSnapshot.cardId(card);
        if (stackHas(game, card, id))
            return;
        SpellAbility ability = card.getSpellAbilities().get(0);
        ability.setActivatingPlayer(card.getController());
        game.getStack().add(ability);
        require(stackHas(game, card, id), "Stack spell lost its card id " + id);
    }

    private static boolean stackHas(Game game, Card card, String id) {
        JsonObject snapshot = NativeSnapshot.capture(game, "id-continuity", 0, card.getController());
        for (JsonElement entry : snapshot.getAsJsonArray("stack")) {
            if (entry.getAsJsonObject().get("sourceId").getAsString().equals(id))
                return true;
        }
        return false;
    }

    private static void same(Game game, String label, Card before, Card after, String zone) {
        require(after != null, label + " removed the card");
        require(after.getId() == before.getId(), label + " changed id " + before.getId() + " to " + after.getId());
        if (zone == null)
            return;
        String id = NativeSnapshot.cardId(after);
        JsonObject snapshot = NativeSnapshot.capture(game, "id-continuity", 0, after.getOwner());
        for (JsonElement element : snapshot.getAsJsonArray("zones")) {
            JsonObject row = element.getAsJsonObject();
            if (!row.get("zone").getAsString().equals(zone) || !row.get("ownerId").getAsString().equals("player-0"))
                continue;
            for (JsonElement card : row.getAsJsonArray("cards")) {
                if (card.getAsJsonObject().get("id").getAsString().equals(id))
                    return;
            }
        }
        throw new AssertionError(label + " did not publish " + id + " in " + zone);
    }
}
