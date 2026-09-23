// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import forge.ai.AiProps;
import forge.ai.LobbyPlayerAi;
import forge.ai.PlayerControllerAi;
import forge.game.Game;
import forge.game.player.Player;
import java.util.Map;

/** Fixed, seat-owned tactical presets on top of Forge's official Default AI. */
final class NativeAiLobby extends LobbyPlayerAi {
    private final Map<AiProps, String> overrides;
    private final Integer starts;

    NativeAiLobby(String name, String difficulty, Integer starts) {
        super(name, null);
        this.starts = starts;
        setAiProfile("Default");
        // These affect planning, not legality, resources or hidden-information
        // permissions. The standard and beginner presets still use native
        // mana payment, threat evaluation, attacks, blocks and mulligans.
        overrides = switch (difficulty) {
            case "hard" -> Map.of();
            case "normal" -> Map.of(
                    AiProps.HOLD_LAND_DROP_FOR_MAIN2_IF_UNUSED, "0",
                    AiProps.CHANCE_TO_CHAIN_TWO_DAMAGE_SPELLS, "45");
            case "easy" -> Map.of(
                    AiProps.HOLD_LAND_DROP_FOR_MAIN2_IF_UNUSED, "0",
                    AiProps.CHANCE_TO_CHAIN_TWO_DAMAGE_SPELLS, "0",
                    AiProps.TRY_TO_HOLD_COMBAT_TRICKS_UNTIL_BLOCK, "false",
                    AiProps.FLASH_ENABLE_ADVANCED_LOGIC, "false",
                    AiProps.AVOID_TARGETING_CREATS_THAT_WILL_DIE, "false",
                    AiProps.COMBAT_ASSAULT_ATTACK_EVASION_PREDICTION, "false",
                    AiProps.COMBAT_ATTRITION_ATTACK_EVASION_PREDICTION, "false");
            default -> throw new IllegalArgumentException("Invalid AI difficulty");
        };
    }

    @Override public String getAiProperty(AiProps property) { return overrides.get(property); }

    @Override public Player createIngamePlayer(Game game, int playerId) {
        Player result = new Player(getName(), game, playerId);
        result.setFirstController(new PlayerControllerAi(game, result, this) {
            @Override public Player chooseStartingPlayer(boolean firstGame) {
                return starts == null ? super.chooseStartingPlayer(firstGame) : game.getRegisteredPlayers().get(starts);
            }
        });
        return result;
    }
}
