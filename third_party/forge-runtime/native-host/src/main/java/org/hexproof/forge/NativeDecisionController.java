// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import forge.LobbyPlayer;
import forge.card.ICardFace;
import forge.game.Game;
import forge.game.player.Player;
import forge.game.spellability.SpellAbility;
import forge.player.PlayerControllerHuman;
import java.util.List;
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
