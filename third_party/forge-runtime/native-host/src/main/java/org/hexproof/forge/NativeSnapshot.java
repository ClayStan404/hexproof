// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package org.hexproof.forge;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import forge.card.CardStateName;
import forge.card.MagicColor;
import forge.game.Game;
import forge.game.GameEntity;
import forge.game.card.Card;
import forge.game.phase.PhaseType;
import forge.game.player.GameLossReason;
import forge.game.player.Player;
import forge.game.player.PlayerOutcome;
import forge.game.spellability.SpellAbility;
import forge.game.spellability.SpellAbilityStackInstance;
import forge.game.zone.ZoneType;
import forge.item.IPaperCard;
import java.util.List;
import java.util.Locale;
import java.util.HashSet;
import java.util.Set;

/**
 * Captures the Hexproof snapshot subset at a stable native-input boundary.
 * The session must serialize this with game mutation: either on the game thread
 * or the native input dispatcher while the game thread is waiting and no answer
 * is being applied. It then publishes the returned JSON as a cached value. RPC
 * readers must never traverse a running game. No Forge objects escape into the
 * result.
 */
final class NativeSnapshot {
    private static final List<ZoneType> ZONES = List.of(ZoneType.Hand, ZoneType.Library,
            ZoneType.Graveyard, ZoneType.Exile, ZoneType.Command, ZoneType.Battlefield);

    private NativeSnapshot() { }

    static JsonObject capture(Game game, String gameId, int viewer, Player priorityPlayer) {
        List<Player> players = List.copyOf(game.getRegisteredPlayers());
        if (players.size() < 2) throw new IllegalArgumentException("Snapshot requires registered players");
        if (viewer < -1 || viewer >= players.size()) throw new IllegalArgumentException("Invalid snapshot viewer");
        Player viewingPlayer = viewer < 0 ? null : players.get(viewer);
        Player active = game.getPhaseHandler().getPlayerTurn();
        if (active == null) active = players.get(0);
        Player priority = priorityPlayer == null ? game.getPhaseHandler().getPriorityPlayer() : priorityPlayer;
        if (priority == null) priority = active;

        JsonObject result = new JsonObject();
        result.addProperty("gameId", gameId);
        result.addProperty("turn", game.getPhaseHandler().getTurn());
        result.addProperty("step", step(game.getPhaseHandler().getPhase()));
        result.addProperty("activePlayerId", playerId(game, active));
        result.addProperty("priorityPlayerId", playerId(game, priority));
        if (game.getStartingPlayer() != null) result.addProperty("startingPlayerId", playerId(game, game.getStartingPlayer()));
        JsonArray playerViews = new JsonArray();
        JsonArray zones = new JsonArray();
        for (Player player : players) {
            playerViews.add(player(game, player));
            for (ZoneType zone : ZONES) zones.add(zone(game, player, zone, viewingPlayer));
        }
        result.add("players", playerViews);
        result.add("zones", zones);
        JsonArray stackViews = stack(game, viewingPlayer, zones);
        result.add("stack", stackViews);
        for (int index = 0; index < players.size(); index++) {
            playerViews.get(index).getAsJsonObject().add("commanders",
                    commanders(game, players.get(index), zones, stackViews));
        }
        result.addProperty("gameOver", game.isGameOver());
        if (game.isGameOver() && game.getOutcome() != null) {
            for (Player player : players) {
                if (game.getOutcome().isWinner(player.getRegisteredPlayer())) {
                    result.addProperty("winnerId", playerId(game, player));
                    break;
                }
            }
        }
        return result;
    }

    static String playerId(Game game, Player player) {
        int index = game.getRegisteredPlayers().indexOf(player);
        if (index < 0) throw new IllegalArgumentException("Player is not registered in this game");
        return "player-" + index;
    }

    static String cardId(Card card) { return "card-" + card.getId(); }

    private static JsonArray commanders(Game game, Player player, JsonArray zones, JsonArray stack) {
        JsonArray result = new JsonArray();
        for (Card designated : player.getCommanders()) {
            Card current = game.getCardState(designated);
            JsonObject entry = new JsonObject();
            // Designation and cast history are public. Never use this summary
            // to locate an otherwise hidden object, including a library card.
            entry.addProperty("name", designated.getState(CardStateName.Original).getName());
            int casts = player.getCommanderCast(designated);
            entry.addProperty("casts", casts);
            // Native CostAdjustment's command-zone surcharge, before other
            // increases/reductions. This is not the final payable cost.
            entry.addProperty("tax", 2 * casts);
            entry.addProperty("zone", "hidden");
            if (current != null) {
                String id = cardId(current);
                for (var zoneValue : zones) {
                    JsonObject zone = zoneValue.getAsJsonObject();
                    for (var cardValue : zone.getAsJsonArray("cards")) {
                        JsonObject card = cardValue.getAsJsonObject();
                        if (id.equals(card.get("id").getAsString()) && card.has("identity")
                                && !card.getAsJsonObject("identity").isEmpty()) {
                            entry.addProperty("objectId", id);
                            entry.addProperty("zone", zone.get("zone").getAsString());
                        }
                    }
                }
                for (var value : stack) {
                    JsonObject object = value.getAsJsonObject();
                    if (id.equals(object.get("sourceId").getAsString())
                            && !object.getAsJsonObject("identity").isEmpty()
                            && current.isInZone(ZoneType.Stack)) {
                        entry.addProperty("objectId", id);
                        entry.addProperty("zone", "stack");
                    }
                }
            }
            result.add(entry);
        }
        return result;
    }

    private static JsonObject player(Game game, Player player) {
        JsonObject result = new JsonObject();
        result.addProperty("id", playerId(game, player));
        result.addProperty("name", player.getName());
        if (player.isControlled()) result.addProperty("controllingPlayerId", playerId(game, player.getControllingPlayer()));
        PlayerOutcome outcome = player.getStats().getOutcome();
        result.addProperty("status", outcome != null && outcome.lossState == GameLossReason.Conceded
                ? "conceded" : player.hasLost() ? "lost" : "playing");
        result.addProperty("life", player.getLife());
        result.add("counters", counters(player));
        JsonObject pool = new JsonObject();
        for (byte color : MagicColor.WUBRGC) {
            int amount = player.getManaPool().getAmountOfColor(color);
            if (amount > 0) pool.addProperty(MagicColor.toShortString(color), amount);
        }
        result.add("manaPool", pool);
        return result;
    }

    private static JsonObject zone(Game game, Player player, ZoneType zone, Player viewer) {
        JsonObject result = new JsonObject();
        result.addProperty("zone", zone.name().toLowerCase(Locale.ROOT));
        result.addProperty("ownerId", playerId(game, player));
        JsonArray cards = new JsonArray();
        int count = 0;
        for (Card card : player.getCardsIn(zone)) {
            // Engine-only effects in Command are not physical tabletop objects.
            if (zone == ZoneType.Command && card.isImmutable()) continue;
            int position = count++;
            // Bulk library order and hidden card IDs never cross the boundary.
            if (zone == ZoneType.Library && position != 0) continue;
            if (zone.isHidden() && !canSee(card, viewer)) continue;
            cards.add(card(game, card, viewer, zone == ZoneType.Battlefield));
        }
        result.addProperty("count", count);
        result.add("cards", cards);
        return result;
    }

    private static boolean canSee(Card card, Player viewer) {
        if (viewer != null) return card.getView().canBeShownTo(viewer.getView());
        ZoneType zone = card.getZone() == null ? null : card.getZone().getZoneType();
        return zone != null && !zone.isHidden() && !card.isFaceDown();
    }

    private static boolean canSeeIdentity(Card card, Player viewer) {
        return canSee(card, viewer) && (!card.isFaceDown()
                || viewer != null && card.getView().canFaceDownBeShownTo(viewer.getView()));
    }

    private static JsonObject card(Game game, Card card, Player viewer, boolean battlefield) {
        JsonObject result = new JsonObject();
        boolean visible = canSeeIdentity(card, viewer);
        // A face-down battlefield object remains a legal public target. The
        // transport distinguishes that object from knowledge of its printing.
        result.addProperty("visibility", visible || battlefield ? "visible" : "hidden");
        result.addProperty("id", cardId(card));
        result.addProperty("ownerId", playerId(game, card.getOwner()));
        result.addProperty("controllerId", playerId(game, card.getController()));
        result.addProperty("isFaceDown", card.isFaceDown());
        if (visible) result.add("identity", identity(card));
        else if (battlefield) result.add("identity", new JsonObject());
        if (battlefield) {
            result.addProperty("tapped", card.isTapped());
            result.addProperty("enteredThisTurn", card.enteredThisTurn());
            result.addProperty("summoningSick", card.isCreature() && card.isSick());
            result.addProperty("isAttacking", game.getCombat() != null && card.isAttacking());
            if (card.isCreature()) {
                result.addProperty("power", Integer.toString(card.getNetPower()));
                result.addProperty("toughness", Integer.toString(card.getNetToughness()));
            }
            result.add("counters", counters(card));
            result.addProperty("damage", card.getDamage());
            if (visible && !card.isFaceDown()) {
                // CardView contains only revealed choices. Raw Card getters
                // also hold secret number/type choices that must stay private.
                var view = card.getView();
                JsonArray annotations = new JsonArray();
                if (view.getNamedCard() != null)
                    for (String name : view.getNamedCard()) annotation(annotations, "namedCard", name);
                annotation(annotations, "chosenType", view.getChosenType());
                annotation(annotations, "chosenType", view.getChosenType2());
                if (view.getChosenColors() != null)
                    for (String color : view.getChosenColors()) annotation(annotations, "chosenColor", color);
                annotation(annotations, "chosenNumber", view.getChosenNumber());
                annotation(annotations, "chosenMode", view.getChosenMode());
                if (card.isClassCard() && view.getClassLevel() > 0)
                    annotation(annotations, "classLevel", Integer.toString(view.getClassLevel()));
                if (!annotations.isEmpty()) result.add("annotations", annotations);
                JsonArray chosenCards = new JsonArray();
                for (Card chosen : card.getChosenCards()) {
                    if (!view.getChosenCards().contains(chosen.getView())) continue;
                    Card current = game.getCardState(chosen, null);
                    // A zone change can reuse the numeric id for a new object.
                    // Do not reconnect an old choice to that new incarnation.
                    if (current != null && current.equalsWithGameTimestamp(chosen)
                            && canSeeIdentity(current, viewer)) chosenCards.add(cardId(current));
                }
                if (!chosenCards.isEmpty()) result.add("chosenCardIds", chosenCards);
            }
            if (card.getAttachedTo() != null) result.addProperty("attachedTo", cardId(card.getAttachedTo()));
            JsonArray linked = new JsonArray();
            int linkedCount = 0;
            for (Card exiled : card.getExiledCards()) {
                if (!exiled.isInZone(ZoneType.Exile) || exiled.getExiledWith() == null
                        || !exiled.getExiledWith().equalsWithGameTimestamp(card)) continue;
                linkedCount++;
                if (canSeeIdentity(exiled, viewer)) linked.add(cardId(exiled));
            }
            if (linkedCount > 0) {
                result.addProperty("exiledCardCount", linkedCount);
                result.add("exiledCardIds", linked);
            }
        }
        if (visible && !card.isFaceDown() && card.isInZone(ZoneType.Command)) {
            JsonArray annotations = new JsonArray();
            annotation(annotations, "dungeonRoom", card.getView().getCurrentRoom());
            if (!annotations.isEmpty()) result.add("annotations", annotations);
        }
        return result;
    }

    private static JsonObject counters(GameEntity entity) {
        JsonObject result = new JsonObject();
        for (var entry : entity.getCounters().entrySet()) {
            result.addProperty(entry.getElement().toString(), entry.getCount());
        }
        return result;
    }

    private static void annotation(JsonArray result, String kind, String value) {
        if (value == null || value.isBlank()) return;
        JsonObject entry = new JsonObject();
        entry.addProperty("kind", kind);
        entry.addProperty("value", value);
        result.add(entry);
    }

    static JsonObject identity(Card card) {
        JsonObject result = new JsonObject();
        IPaperCard paper = card.getPaperCard();
        // A permitted face-down lookup needs its original face; current state is anonymous.
        String name = card.isFaceDown() ? card.getState(CardStateName.Original).getName() : card.getName();
        result.addProperty("name", name);
        boolean matchesPrinting = paper != null && name.equals(paper.getName());
        String edition = matchesPrinting ? paper.getEdition() : "";
        if (matchesPrinting && paper instanceof NativePromoCard promo) edition = promo.catalogSet;
        if (matchesPrinting && paper.isToken()) {
            // PaperToken uses the parent edition's token numbering. Its Scryfall
            // token set can differ (including editions without the usual T prefix).
            var metadata = forge.StaticData.instance().getCardEdition(edition);
            edition = metadata == null ? "" : metadata.getTokensCode().toUpperCase(Locale.ROOT);
            if (name.endsWith(" Token")) name = name.substring(0, name.length() - 6);
            result.addProperty("name", name);
        }
        result.addProperty("setCode", edition);
        result.addProperty("cardNumber", matchesPrinting ? paper.getCollectorNumber() : "");
        result.addProperty("isToken", card.isToken());
        return result;
    }

    private static JsonArray stack(Game game, Player viewer, JsonArray zones) {
        Set<String> visibleObjects = new HashSet<>();
        for (var zone : zones) {
            for (var card : zone.getAsJsonObject().getAsJsonArray("cards")) {
                visibleObjects.add(card.getAsJsonObject().get("id").getAsString());
            }
        }
        JsonArray result = new JsonArray();
        for (SpellAbilityStackInstance instance : game.getStack()) {
            SpellAbility ability = instance.getSpellAbility();
            Card source = ability.getHostCard();
            Player controller = ability.getActivatingPlayer();
            if (controller == null) controller = source.getController();
            JsonObject entry = new JsonObject();
            entry.addProperty("id", "stack-" + instance.getId());
            entry.addProperty("sourceId", cardId(source));
            entry.addProperty("controllerId", playerId(game, controller));
            entry.addProperty("ownerId", playerId(game, source.getOwner()));
            entry.add("targets", stackTargets(game, instance, visibleObjects));
            if (!source.isFaceDown() && canSeeIdentity(source, viewer)) {
                entry.add("identity", identity(source));
                entry.addProperty("text", instance.getStackDescription());
            } else {
                String label = source.isFaceDown() ? ability.isSpell() ? "Face-down spell" : "Face-down ability" : "Ability";
                JsonObject anonymous = new JsonObject();
                entry.add("identity", anonymous);
                entry.addProperty("text", label);
            }
            result.add(entry);
        }
        return result;
    }

    private static JsonArray stackTargets(Game game, SpellAbilityStackInstance instance, Set<String> visibleObjects) {
        JsonArray result = new JsonArray();
        Set<String> seen = new HashSet<>();
        // Modal spells can store targets on distinct native sub-instances.
        for (var part = instance; part != null; part = part.getSubInstance()) {
            for (var target : part.getTargetChoices()) {
                String kind = "", id = "";
                if (target instanceof Player player) {
                    kind = "player";
                    id = playerId(game, player);
                } else if (target instanceof Card card) {
                    Card current = game.getCardState(card, null);
                    if (current != null && current.equalsWithGameTimestamp(card) && visibleObjects.contains(cardId(card))) {
                        kind = "card";
                        id = cardId(card);
                    }
                } else if (target instanceof SpellAbility ability) {
                    for (var candidate : game.getStack()) {
                        if (candidate.getSpellAbility().equals(ability)) {
                            kind = "spell";
                            id = "stack-" + candidate.getId();
                            break;
                        }
                    }
                }
                if (!id.isEmpty() && seen.add(kind + ":" + id)) {
                    JsonObject reference = new JsonObject();
                    reference.addProperty("kind", kind);
                    reference.addProperty("id", id);
                    result.add(reference);
                }
            }
        }
        return result;
    }

    private static String step(PhaseType phase) {
        if (phase == null) return "untap";
        return switch (phase) {
            case UNTAP -> "untap";
            case UPKEEP -> "upkeep";
            case DRAW -> "draw";
            case MAIN1 -> "main1";
            case COMBAT_BEGIN -> "combatBegin";
            case COMBAT_DECLARE_ATTACKERS -> "combatDeclareAttackers";
            case COMBAT_DECLARE_BLOCKERS -> "combatDeclareBlockers";
            case COMBAT_FIRST_STRIKE_DAMAGE -> "combatFirstStrikeDamage";
            case COMBAT_DAMAGE -> "combatDamage";
            case COMBAT_END -> "combatEnd";
            case MAIN2 -> "main2";
            case END_OF_TURN -> "endOfTurn";
            case CLEANUP -> "cleanup";
        };
    }
}
