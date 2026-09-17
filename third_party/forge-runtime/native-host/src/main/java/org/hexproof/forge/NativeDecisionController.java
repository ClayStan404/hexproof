// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import forge.LobbyPlayer;
import forge.card.ICardFace;
import forge.game.Game;
import forge.game.card.Card;
import forge.game.card.CardCollection;
import forge.game.player.Player;
import forge.game.spellability.SpellAbility;
import forge.player.PlayerControllerHuman;
import java.util.List;
import java.util.HashSet;
import java.util.function.Predicate;
import java.util.function.Supplier;

/** Retains the actual native object that requires a synchronous human decision. */
final class NativeDecisionController extends PlayerControllerHuman {
    private final NativeSession session;
    private final Integer starts;

    NativeDecisionController(NativeSession session, Game game, Player player, LobbyPlayer lobby, Integer starts) {
        super(game, player, lobby);
        this.session = session;
        this.starts = starts;
    }

    private <T> T deciding(SpellAbility ability, Supplier<T> action) {
        return session.withDecisionAbility(ability, action);
    }

    @Override public Player chooseStartingPlayer(boolean firstGame) {
        return starts == null ? super.chooseStartingPlayer(firstGame) : getGame().getRegisteredPlayers().get(starts);
    }
    @Override public forge.game.card.CardCollectionView chooseCardsToDiscardToMaximumHandSize(int count) {
        // The desktop uses a specialized incremental input here. Use Forge's
        // complete card-dialog contract so selecting two cards stays one choice.
        var hand = getPlayer().getCardsIn(forge.game.zone.ZoneType.Hand);
        tempShowCards(hand);
        try {
            var candidates = forge.game.GameEntityView.getMap(hand);
            var chosen = getGui().many("Discard to maximum hand size", "Discarded", count, count,
                    candidates.getTrackableKeys(), null);
            var result = new CardCollection();
            candidates.addToList(chosen, result);
            return result;
        } finally { endTempShowCards(); }
    }
    @Override public org.apache.commons.lang3.tuple.ImmutablePair<CardCollection, CardCollection>
            arrangeForScry(CardCollection topN) {
        // Expose both ordered piles in one private decision. The desktop's
        // generic dual-list callbacks otherwise split selection and ordering
        // across unrelated dialogs and hide the top-order step in a small dock.
        var candidates = new CardCollection(topN);
        if (candidates.isEmpty()) return org.apache.commons.lang3.tuple.ImmutablePair.of(
                new CardCollection(), new CardCollection());
        var input = NativeSession.object("type", "scry");
        var cards = new com.google.gson.JsonArray();
        for (Card card : candidates) {
            var choice = NativeSession.object("id", NativeSession.cardId(card));
            choice.add("identity", NativeSnapshot.identity(card));
            cards.add(choice);
        }
        input.add("cards", cards);
        var zones = new com.google.gson.JsonArray();
        zones.add("libraryTop"); zones.add("libraryBottom"); input.add("zones", zones);
        input.add("presentation", NativeSession.object("title", "Scry"));
        return session.ask(getPlayer(), input, raw -> {
            if (!NativeSession.text(raw, "type", "").equals("scryDecision"))
                throw new IllegalArgumentException("Expected scry placement");
            var piles = raw.getAsJsonArray("zoneCardIds");
            if (piles == null || piles.size() != 2) throw new IllegalArgumentException("Expected two scry piles");
            var result = List.of(new CardCollection(), new CardCollection());
            var seen = new HashSet<String>();
            for (int index = 0; index < 2; index++) {
                for (var value : piles.get(index).getAsJsonArray()) {
                    String id = value.getAsString();
                    Card card = candidates.stream().filter(c -> NativeSession.cardId(c).equals(id)).findFirst().orElse(null);
                    if (card == null || !seen.add(id)) throw new IllegalArgumentException("Invalid scry card");
                    result.get(index).add(card);
                }
            }
            if (seen.size() != candidates.size()) throw new IllegalArgumentException("Incomplete scry placement");
            return org.apache.commons.lang3.tuple.ImmutablePair.of(result.get(0), result.get(1));
        });
    }
    @Override public boolean playChosenSpellAbility(SpellAbility ability) {
        return deciding(ability, () -> super.playChosenSpellAbility(ability));
    }
    @Override public void playSpellAbilityNoStack(SpellAbility ability, boolean canSetupTargets) {
        deciding(ability, () -> { super.playSpellAbilityNoStack(ability, canSetupTargets); return null; });
    }
    @Override public Integer announceRequirements(SpellAbility ability, int min, int max, String announce) {
        return deciding(ability, () -> super.announceRequirements(ability, min, max, announce));
    }
    @Override public int chooseNumber(SpellAbility ability, String title, int min, int max) {
        return deciding(ability, () -> super.chooseNumber(ability, title, min, max));
    }
    @Override public int chooseNumber(SpellAbility ability, String title, List<Integer> choices, Player relatedPlayer) {
        return deciding(ability, () -> super.chooseNumber(ability, title, choices, relatedPlayer));
    }
    @Override public String chooseCardName(SpellAbility ability, Predicate<ICardFace> predicate, String valid, String message) {
        return deciding(ability, () -> super.chooseCardName(ability, predicate, valid, message));
    }
    @Override public String chooseCardName(SpellAbility ability, List<ICardFace> faces, String message) {
        return deciding(ability, () -> super.chooseCardName(ability, faces, message));
    }
}
