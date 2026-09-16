// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.game.*;
import forge.card.mana.ManaAtom;
import forge.card.MagicColor;
import forge.game.card.*;
import forge.game.combat.*;
import forge.game.player.*;
import forge.game.spellability.SpellAbilityView;
import forge.game.spellability.SpellAbility;
import forge.game.zone.ZoneType;
import forge.gamemodes.match.input.*;
import forge.gui.interfaces.IGuiGame;
import forge.player.*;
import forge.util.FSerializableFunction;
import java.lang.reflect.*;
import java.util.*;
import java.util.function.Function;
import static org.hexproof.forge.NativeSession.*;

/** Converts native human GUI requests into bounded remote decisions. */
final class NativeGuiGame implements InvocationHandler {
    final PlayerControllerHuman human;
    private final NativeSession session;
    private final IGuiGame proxy;
    private String message = "", okLabel = "OK", cancelLabel = "Cancel";
    private CardView messageCard;
    private Input messageInput;
    private boolean okEnabled, cancelEnabled, scheduled;
    private record CardSelectionBounds(Set<Integer> ids, int min, int max) { }
    private volatile CardSelectionBounds cardSelectionBounds;
    private InputChooseStartingHand startingHandInput;
    private int startingHandIndex, startingHandCount;
    private static final Set<String> PRESENTATION = Set.of("setCurrentPlayer", "setSelectables", "clearSelectables", "setWeaklySelectable", "clearWeaklySelectable", "setHighlighted", "setCard", "updateSingleCard", "updateCards", "updateRevealedCards", "updateStack", "updatePhase", "updateTurn", "updateZones", "hideZones", "refreshCardDetails", "refreshField", "updateManaPool", "updateLives", "updateShards", "updateDependencies", "showManaPool", "hideManaPool", "showCombat", "setPanelSelection", "updateAutoPassPrompt", "refreshYieldUi", "notifyStackAddition", "notifyStackRemoval", "handleLandPlayed", "handleGameEvent", "alertUser", "flashIncorrectAction", "enableOverlay", "disableOverlay", "updatePlayerControl", "awaitNextInput", "cancelAwaitNextInput", "showWaitingTimer", "restoreOldZones", "openView", "afterGameEnd", "finishGame", "setPlayerAvatar", "setGameView", "setOriginalGameController", "setGameController", "setSpectator", "applyYieldUpdate");

    NativeGuiGame(NativeSession session, PlayerControllerHuman human) {
        this.session = session; this.human = human;
        proxy = (IGuiGame) Proxy.newProxyInstance(IGuiGame.class.getClassLoader(), new Class<?>[]{IGuiGame.class}, this);
    }
    IGuiGame proxy() { return proxy; }
    private Player owner() { return human.getPlayer(); }
    @Override public Object invoke(Object p, Method m, Object[] a) throws Throwable {
        if (m.isDefault()) return InvocationHandler.invokeDefault(p, m, a);
        return switch (m.getName()) {
            case "toString" -> "HexproofNativeGuiGame-" + session.index(owner());
            case "getGameView" -> session.game.getView();
            case "isNetGame", "isGamePaused", "isSelecting", "isUiSetToSkipPhase" -> false;
            case "tempShowZones" -> a[1];
            case "openZones" -> new PlayerZoneUpdates();
            case "setSelectables" -> {
                Set<Integer> ids = new HashSet<>();
                for (Object value : (Iterable<?>) a[0]) ids.add(((CardView) value).getId());
                cardSelectionBounds = new CardSelectionBounds(Set.copyOf(ids), (Integer) a[1], (Integer) a[2]);
                yield null;
            }
            case "clearSelectables" -> { cardSelectionBounds = null; yield null; }
            case "showPromptMessage" -> {
                message = (String) a[1];
                messageCard = (CardView) a[2];
                messageInput = human.getInputProxy().getInput();
                scheduleInput(); yield null;
            }
            case "updateButtons" -> {
                okLabel = (String) a[1]; cancelLabel = (String) a[2];
                okEnabled = (Boolean) a[3]; cancelEnabled = (Boolean) a[4];
                yield null;
            }
            case "getAbilityToPlay" -> {
                @SuppressWarnings("unchecked") List<SpellAbilityView> abilities = (List<SpellAbilityView>) a[1];
                // Match the native desktop's public click behavior. A lone
                // ability already represents the action the player selected.
                Object result;
                if (abilities.isEmpty()) result = null;
                else if (abilities.size() == 1 && a[2] == null) result = abilities.get(0);
                else if (abilities.size() == 1 && !abilities.get(0).promptIfOnlyPossibleAbility()) {
                    result = abilities.get(0).canPlay() ? abilities.get(0) : null;
                } else result = chooseOne("Choose an ability", abilities, true, null);
                if (result == null) scheduleInput();
                yield result;
            }
            case "one", "oneOrNone" -> chooseOne((String) a[0], (List<?>) a[1], m.getName().equals("oneOrNone"), a.length > 2 ? a[2] : null);
            case "getChoices" -> choose((String) a[0], (Integer) a[1], (Integer) a[2], (List<?>) a[3], a[5]);
            case "many" -> {
                List<?> choices = (List<?>) a[4];
                int min = (Integer) a[2], max = (Integer) a[3];
                List<?> destination = (List<?>) a[5];
                if (max == 1) yield choose((String) a[0], min, max, choices, null);
                // Match AbstractGuiGame's native many -> dual-list conversion.
                // Negative bounds mean any number; getChoices(-1,-1) instead reveals.
                int remainingMin = max >= 0 ? choices.size() - max : -1;
                int remainingMax = min >= 0 ? choices.size() - min : -1;
                yield NativeOrdering.order(session, owner(), (String) a[0], remainingMin, remainingMax, choices, destination).ordered();
            }
            case "getInteger" -> number((String) a[0], (Integer) a[1], (Integer) a[2]);
            case "showConfirmDialog" -> bool((String) a[0], (String) a[2], (String) a[3]);
            case "confirm" -> bool((String) a[1], ((List<?>) a[3]).get(0).toString(), ((List<?>) a[3]).get(1).toString(), (CardView) a[0]);
            case "showOptionDialog" -> option((String) a[0], (List<?>) a[3]);
            case "chooseSingleEntityForEffect" -> {
                delayedReveal((DelayedReveal) a[2]);
                yield chooseOne((String) a[0], (List<?>) a[1], (Boolean) a[3], null);
            }
            case "chooseEntitiesForEffect" -> {
                delayedReveal((DelayedReveal) a[4]);
                List<?> choices = (List<?>) a[1];
                yield NativeOrdering.order(session, owner(), (String) a[0], choices.size() - (Integer) a[3], choices.size() - (Integer) a[2], choices, null).ordered();
            }
            case "reveal" -> { reveal((String) a[0], (List<?>) a[1]); yield null; }
            case "message" -> { acknowledge((String) a[0]); yield null; }
            case "order" -> NativeOrdering.order(session, owner(), (String) a[0], (Integer) a[2], (Integer) a[3], (List<?>) a[4], (List<?>) a[5]);
            case "insertInList" -> NativeOrdering.insertInList(session, owner(), (String) a[0], a[1], (List<?>) a[2]);
            case "assignCombatDamage" -> {
                @SuppressWarnings("unchecked") List<CardView> blockers = (List<CardView>) a[1];
                yield assignCombatDamage((CardView) a[0], blockers, (Integer) a[2], (GameEntityView) a[3], (Boolean) a[4], (Boolean) a[5]);
            }
            case "assignGenericAmount" -> {
                @SuppressWarnings("unchecked") Map<Object, Integer> targets = (Map<Object, Integer>) a[1];
                yield assignGenericAmount(targets, (Integer) a[2], (Boolean) a[3], (String) a[4]);
            }
            case "showErrorDialog" -> throw new IllegalStateException("Forge reported an error dialog");
            default -> {
                if (PRESENTATION.contains(m.getName())) yield null;
                throw new UnsupportedOperationException("Unsupported native GUI callback: " + m.getName());
            }
        };
    }
    private void scheduleInput() {
        if (scheduled) return;
        scheduled = true;
        session.base.later(() -> { scheduled = false; renderInput(); });
    }
    private JsonObject input(String type, String title) {
        JsonObject result = object("type", type);
        JsonObject presentation = object("title", title);
        presentation.addProperty("description", message);
        result.add("presentation", presentation);
        return result;
    }
    private void renderInput() {
        Input current = human.getInputProxy().getInput();
        if (current == null || current instanceof InputLockUI || session.game.isGameOver()) return;
        if (current instanceof InputSyncronizedBase waiting && !waiting.isAwaitingInput()) return;
        if (current instanceof InputPayMana paying && paying.isPaymentActionPending()) return;
        JsonObject input;
        Function<JsonObject, Runnable> prepare;
        if (current instanceof InputChooseStartingHand startingHand) {
            if (startingHandInput != startingHand) {
                startingHandInput = startingHand;
                startingHandIndex = 0;
                startingHandCount = 1 + (int) owner().getExtraZones().stream()
                        .filter(zone -> zone.getZoneType() == ZoneType.ExtraHand).count();
            }
            input = input("chooseBoolean", "Starting hand " + (startingHandIndex + 1) + " of " + startingHandCount);
            input.getAsJsonObject("presentation").addProperty("description",
                    "Review the cards in your hand. Keep this hand or view the next starting hand.");
            input.addProperty("confirmLabel", "View next hand");
            input.addProperty("denyLabel", "Keep this hand");
            prepare = raw -> {
                requireType(raw, "decision");
                boolean next = raw.get("value").getAsBoolean();
                return () -> {
                    // Native OK rotates the complete hand; native Cancel accepts
                    // it. BackupPlanService owns disposal of the unused hands.
                    button(next);
                    if (next) startingHandIndex = (startingHandIndex + 1) % startingHandCount;
                };
            };
        } else if (current instanceof InputConfirmMulligan) {
            input = input("mulligan", "Opening hand");
            input.addProperty("mulliganCount", owner().getStats().getMulliganCount());
            prepare = raw -> { requireType(raw, "mulliganDecision"); boolean keep = raw.get("keep").getAsBoolean(); return () -> button(keep); };
        } else if (current instanceof InputConfirm) {
            input = input("chooseBoolean", "Confirm decision");
            input.addProperty("confirmLabel", okLabel); input.addProperty("denyLabel", cancelLabel);
            prepare = raw -> { requireType(raw, "decision"); boolean yes = raw.get("value").getAsBoolean(); return () -> button(yes); };
        } else if (current instanceof InputPassPriority || current instanceof InputPayMana) {
            boolean paying = current instanceof InputPayMana;
            input = input(paying ? "payManaCost" : "chooseAction", paying ? "Pay mana" : "Choose an action");
            Map<String, Runnable> actions = new LinkedHashMap<>();
            JsonArray options = new JsonArray();
            List<SpellAbility> priorityAbilities = new ArrayList<>();
            for (Card c : session.game.getCardsInGame()) {
                if (!mayExpose(c)) continue;
                String description = current.getActivateAction(c);
                if (description == null) continue;
                String actionId = "card:" + c.getId();
                JsonObject action = object("id", actionId);
                String actionType = "activateAbility";
                if (!paying) {
                    // Use the same native ability list as InputPassPriority.
                    // This includes land faces and spells cast from exile.
                    var abilities = c.getAllPossibleAbilities(owner(), true);
                    priorityAbilities.addAll(abilities);
                    if (!abilities.isEmpty()) {
                        var ability = abilities.get(0);
                        actionType = ability.isLandAbility() ? "playLand" : ability.isSpell() ? "cast" : "activateAbility";
                    }
                }
                action.addProperty("type", actionType);
                action.addProperty("cardId", cardId(c));
                action.addProperty("label", c.getName() + " — " + description);
                options.add(action);
                actions.put(actionId, () -> select(c));
            }
            if (paying) {
                InputPayMana payment = (InputPayMana) current;
                input.addProperty("manaCost", payment.getUnpaidManaCost());
                input.addProperty("canConfirmFromPool", false);
                input.addProperty("canAutoPay", okEnabled && payment.supportsAutomaticPayment());
                input.addProperty("canCancel", cancelEnabled);
                if (payment instanceof InputPayManaOfCostPayment cost && cost.canPayLifeForMana()) {
                    JsonObject action = object("id", "life:2");
                    action.addProperty("type", "activateAbility"); action.addProperty("label", "Pay 2 life");
                    options.add(action); actions.put("life:2", () -> human.selectPlayer(owner().getView(), null));
                }
                for (byte color : ManaAtom.MANATYPES) {
                    if (owner().getManaPool().getAmountOfColor(color) <= 0) continue;
                    String id = "pool:" + color;
                    JsonObject action = object("id", id);
                    action.addProperty("type", "activateAbility");
                    action.addProperty("label", "Use floating " + MagicColor.toShortString(color) + " mana");
                    options.add(action); actions.put(id, () -> human.useMana(color));
                }
            }
            input.add("actions", options);
            if (!paying) input.addProperty("autoPassEligible", NativePriority.autoPassEligible(owner(), priorityAbilities));
            prepare = raw -> {
                String type = text(raw, "type", "");
                if (type.equals("act")) {
                    Runnable action = actions.get(text(raw, "actionId", ""));
                    if (action == null) throw new IllegalArgumentException("Action unavailable");
                    return action;
                }
                if (paying && type.equals("cancel") && cancelEnabled) return () -> button(false);
                if (paying && type.equals("pay") && okEnabled) return () -> button(true);
                if (!paying && type.equals("pass")) return ((InputPassPriority) current)::passPriority;
                throw new IllegalArgumentException("Unsupported action response");
            };
        } else if (current instanceof InputAttack || current instanceof InputBlock) {
            renderCombat(current);
            return;
        } else if (current instanceof InputLondonMulligan london) {
            renderCardSelection(current, new ArrayList<>(owner().getCardsIn(ZoneType.Hand)), london.getCardsToReturn(), london.getCardsToReturn());
            return;
        } else if (current instanceof InputSelectEntitiesFromList<?> nativeChoices
                && nativeChoices.getValidChoices().stream().allMatch(c -> c instanceof Card)) {
            List<Card> cards = nativeChoices.getValidChoices().stream().map(c -> (Card) c).toList();
            if (current.getClass() == InputSelectEntitiesFromList.class || current.getClass() == InputSelectCardsFromList.class) {
                // Forge already sends the complete cardinality to its GUI.
                // Preserve that batch instead of losing selections between
                // one-card prompts (for example, discard two cards).
                CardSelectionBounds bounds = cardSelectionBounds;
                Set<Integer> ids = new HashSet<>();
                for (Card card : cards) ids.add(card.getId());
                if (bounds == null || !bounds.ids().equals(ids) || bounds.min() < 0 || bounds.max() < bounds.min())
                    throw new IllegalStateException("Native card selection metadata is unavailable");
                renderCardSelection(current, cards, bounds.min(), Math.min(bounds.max(), cards.size()));
            } else {
                // Specialized native subclasses can enable completion from
                // properties other than count. Keep their own click checks.
                renderCardSelection(current, cards, okEnabled ? 0 : 1, 1);
            }
            return;
        } else if (current instanceof InputSelectManyBase<?> || current instanceof InputSelectTargets) {
            // A native click is one incremental choice. Forge keeps its selected
            // state and decides whether further clicks or an OK are required.
            input = input("chooseBoardTargets", "Choose a card or player");
            Map<String, Runnable> choices = new LinkedHashMap<>();
            JsonArray candidates = new JsonArray();
            for (Card c : session.game.getCardsInGame()) {
                if (!mayExpose(c) || current.getActivateAction(c) == null) continue;
                JsonObject candidate = object("kind", "card"); candidate.addProperty("id", cardId(c));
                candidates.add(candidate); choices.put("card:" + cardId(c), () -> select(c));
            }
            if (current instanceof InputSelectTargets targets) {
                for (Player player : targets.getSelectablePlayers()) {
                    JsonObject candidate = object("kind", "player"); candidate.addProperty("id", session.playerId(player));
                    candidates.add(candidate); choices.put("player:" + session.playerId(player), () -> human.selectPlayer(player.getView(), null));
                }
            }
            if (current instanceof InputSelectEntitiesFromList<?> list) {
                for (Object entity : list.getValidChoices()) if (entity instanceof Player player) {
                    JsonObject candidate = object("kind", "player"); candidate.addProperty("id", session.playerId(player));
                    candidates.add(candidate); choices.put("player:" + session.playerId(player), () -> human.selectPlayer(player.getView(), null));
                }
            }
            input.add("candidates", candidates);
            input.addProperty("minTargets", okEnabled ? 0 : 1);
            input.addProperty("maxTargets", 1);
            input.addProperty("chosenTargets", 0);
            input.addProperty("cancellable", cancelEnabled);
            boolean canFinish = okEnabled, canCancel = cancelEnabled;
            prepare = raw -> {
                if (text(raw, "type", "").equals("cancel") && canCancel) return () -> button(false);
                requireType(raw, "boardTargets");
                JsonArray selected = raw.getAsJsonArray("chosen");
                if (selected.size() == 0 && canFinish) return () -> button(true);
                if (selected.size() != 1) throw new IllegalArgumentException("One native input action is required");
                JsonObject item = selected.get(0).getAsJsonObject();
                Runnable action = choices.get(text(item, "kind", "") + ":" + text(item, "id", ""));
                if (action == null) throw new IllegalArgumentException("Selected entity unavailable");
                return action;
            };
        } else throw new UnsupportedOperationException("Unsupported native input: " + current.getClass().getName());
        JsonObject source = current == messageInput ? promptSource(messageCard, input) : null;
        session.publish(owner(), input, source, guarded(current, prepare), true);
    }
    private void renderCardSelection(Input current, List<Card> cards, int min, int max) {
        JsonObject in = input("chooseCards", "Choose cards");
        JsonArray identities = new JsonArray(); Map<String, Card> allowed = new HashMap<>();
        for (Card c : cards) { identities.add(promptCard(c.getView())); allowed.put(cardId(c), c); }
        in.add("cards", identities); in.addProperty("min", min); in.addProperty("max", max);
        boolean canCancel = cancelEnabled;
        in.addProperty("cancellable", canCancel);
        session.publish(owner(), in, guarded(current, raw -> {
            if (text(raw, "type", "").equals("cancel") && canCancel) return () -> button(false);
            requireType(raw, "chooseCardsDecision");
            JsonArray chosen = raw.getAsJsonArray("chosenCardIds");
            if (chosen.size() < min || chosen.size() > max) throw new IllegalArgumentException("Invalid native card selection count");
            List<Card> selected = new ArrayList<>(); Set<String> seen = new HashSet<>();
            for (JsonElement id : chosen) {
                Card c = allowed.get(id.getAsString());
                if (c == null || !seen.add(id.getAsString())) throw new IllegalArgumentException("Invalid native card selection");
                selected.add(c);
            }
            return () -> {
                for (Card c : selected) select(c);
                if (human.getInputProxy().getInput() == current
                        && (selected.isEmpty() || current instanceof InputLondonMulligan
                        || (current.getClass() == InputSelectEntitiesFromList.class
                            || current.getClass() == InputSelectCardsFromList.class) && okEnabled)) button(true);
            };
        }), true);
    }
    private Function<JsonObject, Runnable> guarded(Input input, Function<JsonObject, Runnable> prepare) {
        return raw -> {
            Runnable action = prepare.apply(raw);
            return () -> {
                if (human.getInputProxy().getInput() != input) throw new IllegalStateException("Native input changed before response");
                action.run();
                if (human.getInputProxy().getInput() == input
                        && (!(input instanceof InputPayMana paying) || !paying.isPaymentActionPending())) scheduleInput();
            };
        };
    }
    private boolean mayExpose(Card card) {
        return card.getView().canBeShownTo(owner().getView());
    }
    private void button(boolean yes) { if (yes) human.selectButtonOk(); else human.selectButtonCancel(); }
    private void select(Card card) {
        if (!human.selectCard(card.getView(), null, null)) throw new IllegalArgumentException("Native input rejected card");
    }
    private void renderCombat(Input current) {
        Combat combat = session.game.getCombat();
        boolean attack = current instanceof InputAttack;
        JsonObject in = input(attack ? "chooseAttackers" : "chooseBlockers", attack ? "Declare attackers" : "Declare blockers");
        JsonArray attackers = new JsonArray();
        Map<String, Card> cards = new HashMap<>();
        Map<String, GameEntity> defenders = new HashMap<>();
        Map<String, Integer> assignmentLimits = new HashMap<>();
        Map<String, Set<String>> validAssignments = new HashMap<>();
        if (attack) {
            JsonArray targets = new JsonArray();
            for (GameEntity defender : combat.getDefenders()) {
                String id = defender instanceof Player p ? session.playerId(p) : cardId((Card) defender);
                JsonObject target = object("id", id);
                target.addProperty("kind", defender instanceof Player ? "player" : ((Card) defender).isBattle() ? "battle" : "planeswalker");
                target.addProperty("label", defender.getName()); targets.add(target); defenders.put(id, defender);
            }
            for (Card c : owner().getCreaturesInPlay()) {
                JsonArray valid = new JsonArray();
                for (Map.Entry<String, GameEntity> defender : defenders.entrySet()) if (CombatUtil.canAttack(c, defender.getValue())) valid.add(defender.getKey());
                if (valid.isEmpty()) continue;
                JsonObject entry = object("attackerId", cardId(c)); entry.add("validTargetIds", valid); attackers.add(entry); cards.put(cardId(c), c);
                assignmentLimits.put(cardId(c), 1);
                Set<String> legal = new HashSet<>();
                for (JsonElement target : valid) legal.add(target.getAsString());
                validAssignments.put(cardId(c), legal);
            }
            in.add("attackTargets", targets);
        } else {
            JsonArray blockers = new JsonArray(), limits = new JsonArray();
            for (Card blocker : owner().getCreaturesInPlay()) if (CombatUtil.canBlock(blocker, combat)) {
                String id = cardId(blocker);
                blockers.add(id); cards.put(id, blocker);
                int maximum = blocker.canBlockAny() ? combat.getAttackers().size()
                        : (int) Math.min(combat.getAttackers().size(), Math.max(1L, 1L + blocker.canBlockAdditional()));
                assignmentLimits.put(id, maximum);
                validAssignments.put(id, new HashSet<>());
                JsonObject limit = object("blockerId", id); limit.addProperty("maxAssignments", maximum); limits.add(limit);
            }
            in.add("availableBlockerIds", blockers);
            in.add("blockerAssignmentLimits", limits);
            for (Card attacker : combat.getAttackers()) {
                JsonObject entry = object("attackerId", cardId(attacker));
                JsonArray valid = new JsonArray();
                for (Card blocker : cards.values()) if (CombatUtil.canBlock(attacker, blocker, combat)) {
                    valid.add(cardId(blocker));
                    validAssignments.get(cardId(blocker)).add(cardId(attacker));
                }
                entry.add("validBlockerIds", valid);
                entry.addProperty("minBlockers", CombatUtil.getMinNumBlockersForAttacker(attacker, owner()));
                attackers.add(entry); defenders.put(cardId(attacker), attacker);
            }
        }
        in.add("attackers", attackers);
        session.publish(owner(), in, guarded(current, raw -> {
            requireType(raw, attack ? "declareAttackers" : "declareBlockers");
            List<Runnable> actions = new ArrayList<>();
            Map<String, Set<String>> chosen = new HashMap<>();
            for (JsonElement element : raw.getAsJsonArray("assignments")) {
                JsonObject assignment = element.getAsJsonObject();
                String sourceId = text(assignment, attack ? "attackerId" : "blockerId", "");
                String targetId = text(assignment, attack ? "targetId" : "attackerId", "");
                Card source = cards.get(sourceId);
                GameEntity target = defenders.get(targetId);
                if (source == null || target == null) throw new IllegalArgumentException("Invalid combat assignment");
                Set<String> destinations = chosen.computeIfAbsent(sourceId, ignored -> new HashSet<>());
                if (!validAssignments.get(sourceId).contains(targetId) || !destinations.add(targetId)
                        || destinations.size() > assignmentLimits.get(sourceId))
                    throw new IllegalArgumentException("Invalid combat assignment combination");
                actions.add(() -> {
                    if (target instanceof Player p) human.selectPlayer(p.getView(), null); else select((Card) target);
                    select(source);
                });
            }
            return () -> { for (Runnable action : actions) action.run(); button(true); };
        }), true);
    }
    private Object chooseOne(String title, List<?> choices, boolean optional, Object display) {
        if (!choices.isEmpty() && choices.get(0) instanceof CardFaceView) {
            JsonObject in = input("chooseCardName", title);
            in.addProperty("message", title); in.addProperty("canCancel", optional);
            Map<String, Object> legal = new HashMap<>();
            for (Object choice : choices) legal.put(((CardFaceView) choice).getName().toLowerCase(Locale.ROOT), choice);
            return session.ask(owner(), in, raw -> {
                if (text(raw, "type", "").equals("cancel") && optional) return null;
                requireType(raw, "cardName");
                String name = text(raw, "name", "").trim();
                Object answer = legal.get(name.toLowerCase(Locale.ROOT));
                if (answer == null) throw new IllegalArgumentException("Name is outside the native legal candidate set");
                return answer;
            });
        }
        List<?> selected = choose(title, optional ? 0 : 1, 1, choices, display);
        return selected.isEmpty() ? null : selected.get(0);
    }
    @SuppressWarnings("unchecked")
    private List<?> choose(String title, int min, int max, List<?> choices, Object display) {
        if (min == -1 && max == -1) { reveal(title, choices); return List.of(); }
        if (choices.size() > 512 || min < 0 || max < min) throw new UnsupportedOperationException("Choice list needs a dedicated bounded protocol");
        int upper = Math.min(max, choices.size());
        if (!choices.isEmpty() && choices.stream().allMatch(c -> c instanceof CardView) && display == null) {
            JsonObject in = input("chooseCards", title); JsonArray cards = new JsonArray();
            Map<String, Object> allowed = new LinkedHashMap<>();
            for (Object choice : choices) {
                CardView card = (CardView) choice;
                cards.add(promptCard(card)); allowed.put("card-" + card.getId(), choice);
            }
            in.add("cards", cards); in.addProperty("min", min); in.addProperty("max", upper);
            return session.ask(owner(), in, raw -> {
                requireType(raw, "chooseCardsDecision");
                JsonArray selected = raw.getAsJsonArray("chosenCardIds");
                if (selected.size() < min || selected.size() > upper) throw new IllegalArgumentException("Invalid card selection count");
                Set<String> seen = new HashSet<>(); List<Object> result = new ArrayList<>();
                for (JsonElement id : selected) {
                    Object card = allowed.get(id.getAsString());
                    if (card == null || !seen.add(id.getAsString())) throw new IllegalArgumentException("Invalid card selection ID");
                    result.add(card);
                }
                return result;
            });
        }
        JsonObject in = input("chooseFromSelection", title);
        JsonArray options = new JsonArray();
        for (Object choice : choices) {
            String label = display == null ? label(choice) : ((FSerializableFunction<Object, String>) display).apply(choice);
            JsonObject option = object("label", label);
            option.addProperty("weight", 1); option.addProperty("canRepeat", false); options.add(option);
        }
        in.add("options", options); in.addProperty("minTotal", min); in.addProperty("maxTotal", upper);
        return session.ask(owner(), in, raw -> {
            requireType(raw, "selectionDecision");
            JsonArray selected = raw.getAsJsonArray("chosenIndices");
            if (selected.size() < min || selected.size() > upper) throw new IllegalArgumentException("Invalid choice count");
            Set<Integer> seen = new HashSet<>(); List<Object> result = new ArrayList<>();
            for (JsonElement e : selected) {
                int i = e.getAsInt();
                if (i < 0 || i >= choices.size() || !seen.add(i)) throw new IllegalArgumentException("Invalid choice index");
                result.add(choices.get(i));
            }
            return result;
        });
    }
    private int number(String title, int min, int max) {
        return number(title, min, max, null);
    }
    private int number(String title, int min, int max, Object target) {
        JsonObject in = input("chooseNumber", title); in.addProperty("min", min); in.addProperty("max", max);
        if (target instanceof GameEntityView entity) {
            JsonObject reference = object("kind", entity instanceof CardView ? "card" : "player");
            reference.addProperty("id", entityId(entity));
            JsonArray targets = new JsonArray(); targets.add(reference);
            in.getAsJsonObject("presentation").add("targets", targets);
        }
        return session.ask(owner(), in, raw -> {
            requireType(raw, "numberDecision"); int value = raw.get("chosenNumber").getAsInt();
            if (value < min || value > max) throw new IllegalArgumentException("Number outside native bounds");
            return value;
        });
    }
    private boolean bool(String title, String yes, String no) {
        return bool(title, yes, no, null);
    }
    private boolean bool(String title, String yes, String no, CardView card) {
        JsonObject in = input("chooseBoolean", title); in.addProperty("confirmLabel", yes); in.addProperty("denyLabel", no);
        in.getAsJsonObject("presentation").addProperty("description", "");
        return session.ask(owner(), in, promptSource(card, in), raw -> { requireType(raw, "decision"); return raw.get("value").getAsBoolean(); });
    }
    private int option(String title, List<?> options) {
        Object chosen = chooseOne(title, options, true, null);
        return chosen == null ? -1 : options.indexOf(chosen);
    }
    private String label(Object choice) {
        if (choice instanceof CardView c) return c.getName();
        if (choice instanceof PlayerView p) return p.getName();
        if (choice instanceof SpellAbilityView sa) return sa.getDescription();
        return Objects.toString(choice, "");
    }
    private void reveal(String title, List<?> cards) {
        if (cards.stream().allMatch(c -> c instanceof CardView)) {
            JsonObject in = input("revealCards", title); JsonArray options = new JsonArray();
            for (Object value : cards) options.add(promptCard((CardView) value));
            in.add("cards", options);
            session.ask(owner(), in, raw -> { requireType(raw, "revealCardsAcknowledged"); return true; });
        } else acknowledge(title + "\n" + cards);
    }
    private void delayedReveal(DelayedReveal delayed) {
        if (delayed != null) reveal(delayed.getMessagePrefix(), delayed.getCards());
    }
    private void acknowledge(String message) { bool(message, "Continue", "Continue"); }
    private JsonObject promptCard(CardView card) {
        JsonObject result = object("id", "card-" + card.getId());
        JsonObject identity = object("name", card.isFaceDown() && !card.canFaceDownBeShownTo(owner().getView()) ? "Face-down card" : card.getName());
        result.add("identity", identity); return result;
    }
    private JsonObject promptSource(CardView card, JsonObject input) {
        // Only the card explicitly supplied with this native decision is a
        // disclosure. Do not infer it from labels, the library or setCard calls.
        if (card == null || card.isFaceDown() && !card.canFaceDownBeShownTo(owner().getView())) return null;
        // A face-down casting view can permit its owner without supplying a
        // printed name. Keep the decision usable without optional card context.
        if (Objects.toString(card.getName(), "").isBlank()) return null;
        input.getAsJsonObject("presentation").addProperty("text", card.getText());
        return promptCard(card);
    }
    private Map<CardView, Integer> assignCombatDamage(CardView attacker, List<CardView> blockers, int amount,
                                                     GameEntityView defender, boolean overrideOrder, boolean maySkip) {
        if (maySkip && !bool("Assign " + attacker.getName() + " combat damage now?", "Assign now", "Assign later")) return null;
        String defenderId = defender == null ? "" : entityId(defender);
        NativeDamageAssignment assignment = new NativeDamageAssignment(attacker, blockers, amount, defender, overrideOrder, defenderId);
        JsonObject in = input("chooseCombatDamageAssignment", "Assign combat damage");
        in.addProperty("attackerId", "card-" + attacker.getId());
        in.addProperty("totalDamage", amount); in.addProperty("attackerHasDeathtouch", assignment.deathtouch);
        in.addProperty("damageAssignmentMode", assignment.mode());
        JsonArray ids = new JsonArray(), cards = new JsonArray(), hints = new JsonArray();
        for (CardView blocker : blockers) {
            String id = "card-" + blocker.getId();
            ids.add(id); cards.add(promptCard(blocker));
            JsonObject hint = object("id", id);
            hint.addProperty("lethalDamage", assignment.lethalDamage(blocker));
            hints.add(hint);
        }
        in.add("blockerIds", ids); in.add("blockerCards", cards);
        in.add("blockerDamageHints", hints);
        if (!assignment.defenderId.isEmpty()) in.addProperty("defenderId", assignment.defenderId);
        return session.ask(owner(), in, raw -> {
            requireType(raw, "combatDamageAssignmentDecision");
            Map<String, Integer> values = new LinkedHashMap<>();
            for (JsonElement element : raw.getAsJsonArray("assignments")) {
                JsonObject value = element.getAsJsonObject();
                String id = text(value, "assigneeId", "");
                if (values.put(id, value.get("damage").getAsInt()) != null) throw new IllegalArgumentException("Duplicate damage assignee");
            }
            return assignment.validate(values);
        });
    }
    private Map<Object, Integer> assignGenericAmount(Map<Object, Integer> targets, int amount, boolean atLeastOne, String label) {
        if (targets.size() > 512 || amount < 0 || amount > 100000) throw new IllegalArgumentException("Invalid native allocation bounds");
        List<Map.Entry<Object, Integer>> entries = new ArrayList<>(targets.entrySet());
        int minimum = atLeastOne ? 1 : 0;
        long capacity = 0;
        for (Map.Entry<Object, Integer> entry : entries) {
            int maximum = entry.getValue() == null ? amount : entry.getValue();
            if (maximum < minimum) throw new IllegalArgumentException("Native target cannot receive its minimum allocation");
            capacity += maximum;
        }
        if (amount < (long) minimum * entries.size() || amount > capacity) throw new IllegalArgumentException("Native allocation cannot satisfy its bounds");
        Map<Object, Integer> result = new LinkedHashMap<>();
        int remaining = amount;
        for (int index = 0; index < entries.size(); index++) {
            Map.Entry<Object, Integer> entry = entries.get(index);
            int maximum = entry.getValue() == null ? amount : entry.getValue();
            capacity -= maximum;
            int low = (int) Math.max(minimum, remaining - capacity);
            int high = Math.min(maximum, remaining - minimum * (entries.size() - index - 1));
            int chosen = number("Assign " + label + " to " + label(entry.getKey()), low, high, entry.getKey());
            result.put(entry.getKey(), chosen); remaining -= chosen;
        }
        if (remaining != 0) throw new IllegalStateException("Native allocation total changed");
        return result;
    }
    private String entityId(GameEntityView entity) {
        if (entity instanceof CardView card) return "card-" + card.getId();
        if (entity instanceof PlayerView player) {
            return session.game.getRegisteredPlayers().stream().filter(p -> p.getView().equals(player))
                    .map(session::playerId).findFirst().orElseThrow(() -> new IllegalArgumentException("Unknown native player"));
        }
        throw new IllegalArgumentException("Unknown native entity");
    }
    private static void requireType(JsonObject response, String expected) {
        if (!text(response, "type", "").equals(expected)) throw new IllegalArgumentException("Unexpected response type");
    }
}
