// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.card.mana.ManaAtom;
import forge.game.GameStage;
import forge.game.card.*;
import forge.game.combat.Combat;
import forge.game.mana.Mana;
import forge.game.phase.PhaseType;
import forge.game.player.Player;
import forge.game.player.PlaySpellAbility;
import forge.game.spellability.SpellAbility;
import forge.game.zone.ZoneType;
import forge.gui.GuiBase;
import forge.item.PaperCard;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.model.FModel;
import forge.player.PlayerControllerHuman;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;
import static org.hexproof.forge.NativeSession.*;

/** Actual native resolution evidence; deliberately outside the packaged host. */
public final class NativeCorpus {
    private static final Gson JSON = new Gson();
    private static PrintWriter output;

    public static void main(String[] args) throws Exception {
        NativeProfile.create();
        try (NativeGuiBase base = new NativeGuiBase(args[0]);
                PrintWriter evidence = new PrintWriter(Files.newBufferedWriter(Path.of(args[2])))) {
            output = evidence;
            GuiBase.setInterface(base.proxy());
            FModel.initialize(null, prefs -> {
                prefs.setPref(FPref.DECKGEN_CARDBASED, false);
                prefs.setPref(FPref.UI_SELECT_FROM_CARD_DISPLAYS, false);
                return null;
            });
            JsonObject manifest = JsonParser.parseString(Files.readString(Path.of(args[1]))).getAsJsonObject();
            SortedSet<String> names = new TreeSet<>();
            for (JsonElement entry : manifest.getAsJsonArray("decks")) {
                JsonObject deck = entry.getAsJsonObject();
                for (String section : List.of("mainboard", "sideboard"))
                    for (JsonElement c : deck.getAsJsonArray(section)) names.add(c.getAsJsonObject().get("name").getAsString());
            }
            int count = 0;
            for (String name : names) {
                if (args.length > 3 && !name.matches(args[3])) continue;
                PaperCard paper = FModel.getMagicDb().getCommonCards().getCard(name);
                if (paper == null && name.contains(" // "))
                    paper = FModel.getMagicDb().getCommonCards().getCard(name.split(" // ")[0]);
                JsonObject record = object("card", name);
                record.addProperty("case", "play-and-resolve");
                if (paper == null) {
                    record.addProperty("status", "unsupported");
                    record.addProperty("reason", "Card absent from pinned Forge database");
                } else run(base, paper, record, -1);
                output.println(JSON.toJson(record)); output.flush();
                System.out.println(++count + " " + record.get("status").getAsString() + " " + name);
                if (paper != null && args.length > 4 && args[4].equals("abilities") && record.has("abilityInventory")) {
                    for (JsonElement entry : record.getAsJsonArray("abilityInventory")) {
                        JsonObject ability = entry.getAsJsonObject();
                        if (ability.get("spell").getAsBoolean() || ability.get("land").getAsBoolean()) continue;
                        JsonObject activation = object("card", name);
                        activation.addProperty("case", "ability-" + ability.get("index").getAsInt());
                        run(base, paper, activation, ability.get("index").getAsInt());
                        output.println(JSON.toJson(activation)); output.flush();
                        System.out.println("  " + activation.get("status").getAsString() + " " + activation.get("case").getAsString());
                    }
                }
            }
        } catch (Throwable error) { error.printStackTrace(); System.exit(2); }
    }

    private static Card card(NativeSession session, Player owner, String name, ZoneType zone) {
        PaperCard paper = FModel.getMagicDb().getCommonCards().getCard(name);
        if (paper == null) throw new IllegalArgumentException("Fixture card unavailable: " + name);
        Card card = CardFactory.getCard(paper, owner, session.game);
        if (zone == ZoneType.Stack) session.game.getStackZone().add(card);
        else owner.getZone(zone).add(card);
        card.setSickness(false);
        return card;
    }

    private static void run(NativeGuiBase base, PaperCard paper, JsonObject record, int activationIndex) {
        JsonObject config = JsonParser.parseString("{\"gameId\":\"card-corpus\",\"seed\":42,\"variant\":\"constructed\",\"startingLife\":40,\"players\":[{\"name\":\"Corpus A\",\"deck\":[{\"name\":\"Forest\"}]},{\"name\":\"Corpus B\",\"deck\":[{\"name\":\"Forest\"}]}]}").getAsJsonObject();
        JsonArray frames = new JsonArray(); record.add("frames", frames);
        try (NativeSession session = new NativeSession(config, base); var scope = session.context.enter()) {
            base.setTestSession(session);
            session.game.setAge(GameStage.Play);
            Player owner = session.game.getPlayers().get(0);
            session.game.setStartingPlayer(owner);
            session.game.getPhaseHandler().devModeSet(PhaseType.MAIN1, owner, false, 4);
            for (Player player : session.game.getPlayers()) {
                player.setLife(40, null);
                for (String name : List.of("Grizzly Bears", "Ornithopter", "Memnite", "Island", "Swamp", "Forest", "Mountain", "Plains", "Wastes", "Glorious Anthem", "Serra Angel"))
                    card(session, player, name, ZoneType.Battlefield);
                for (String name : List.of("Grizzly Bears", "Lightning Bolt", "Forest", "Ornithopter", "Ulamog, the Ceaseless Hunger", "Brainstorm", "Duress", "Mountain", "Serra Angel", "Swords to Plowshares"))
                    card(session, player, name, ZoneType.Hand);
                for (String name : List.of("Grizzly Bears", "Lightning Bolt", "Forest", "Ornithopter", "Ulamog, the Ceaseless Hunger", "Duress", "Glorious Anthem"))
                    card(session, player, name, ZoneType.Graveyard);
                for (int i = 0; i < 6; i++)
                    for (String name : List.of("Forest", "Grizzly Bears", "Lightning Bolt", "Island", "Ornithopter", "Swamp", "Mountain", "Plains"))
                        card(session, player, name, ZoneType.Library);
                Card source = player.getCardsIn(ZoneType.Battlefield).get(3);
                for (byte color : ManaAtom.MANATYPES)
                    for (int i = 0; i < 20; i++) player.getManaPool().addMana(new Mana(color, source, null, player));
            }
            Card source = CardFactory.getCard(paper, owner, session.game);
            owner.getZone(ZoneType.Hand).add(source);
            record.addProperty("nativeName", paper.getName());
            record.addProperty("type", source.getType().toString());
            JsonArray abilities = new JsonArray();
            for (SpellAbility a : source.getSpellAbilities()) abilities.add(a.toString());
            record.add("abilities", abilities);
            JsonArray inventory = new JsonArray();
            for (int index = 0; index < source.getSpellAbilities().size(); index++) {
                SpellAbility a = source.getSpellAbilities().get(index);
                JsonObject metadata = object("description", a.toString());
                metadata.addProperty("index", index); metadata.addProperty("spell", a.isSpell()); metadata.addProperty("land", a.isLandAbility());
                metadata.addProperty("zone", String.valueOf(a.getRestrictions().getZone())); inventory.add(metadata);
            }
            record.add("abilityInventory", inventory);
            session.game.getAction().checkStaticAbilities();
            session.game.getTriggerHandler().resetActiveTriggers();
            record.add("before", snapshots(session));
            AtomicBoolean played = new AtomicBoolean();
            JsonObject outcome = new JsonObject();
            drive(session, frames, () -> {
                SpellAbility ability = source.getSpellAbilities().stream().filter(a -> source.isLand() ? a.isLandAbility() : a.isSpell()).findFirst().orElse(null);
                if (ability == null) throw new IllegalStateException("No ordinary play ability");
                ability.setActivatingPlayer(owner);
                outcome.addProperty("ability", ability.toString());
                if (List.of("Focus Fire", "Razorgrass Ambush").contains(paper.getName())) {
                    Player attacker = session.game.getPlayers().get(1);
                    session.game.getPhaseHandler().devModeSet(PhaseType.COMBAT_DECLARE_BLOCKERS, attacker, false, 4);
                    Combat combat = new Combat(attacker); session.game.getPhaseHandler().setCombat(combat);
                    combat.addAttacker(attacker.getCreaturesInPlay().get(0), owner);
                    outcome.addProperty("combatFixture", "Opponent creature attacking the spell's controller");
                }
                if (ability.getApi() != null && ability.getApi().name().equals("Counter")
                        || List.of("Bilbo's Gambit", "Change the Equation", "Narset's Reversal", "Return the Favor").contains(paper.getName())) {
                    Player opponent = session.game.getPlayers().get(1);
                    String targetName = switch (paper.getName()) {
                        case "Annul", "Consign to Memory" -> "Ornithopter";
                        case "Disdainful Stroke" -> "Serra Angel";
                        case "Spell Snare", "Stern Scolding" -> "Grizzly Bears";
                        default -> "Lightning Bolt";
                    };
                    Card target = card(session, opponent, targetName, ZoneType.Stack);
                    SpellAbility burn = target.getSpellAbilities().get(0);
                    burn.setActivatingPlayer(opponent);
                    if (targetName.equals("Lightning Bolt")) burn.getTargets().add(owner);
                    session.game.getStack().add(burn);
                }
                ZoneType activationZone = activationIndex < 0 ? null : source.getSpellAbilities().get(activationIndex).getRestrictions().getZone();
                if (activationIndex >= 0 && source.getSpellAbilities().get(activationIndex).isPlotting()) activationZone = ZoneType.Hand;
                int resolved = 0;
                if (activationZone != null && activationZone != ZoneType.Battlefield) {
                    owner.getZone(ZoneType.Hand).remove(source);
                    owner.getZone(activationZone).add(source);
                    outcome.addProperty("activationSetupZone", activationZone.name());
                } else {
                    played.set(PlaySpellAbility.playSpellAbility((PlayerControllerHuman) owner.getController(), owner, ability));
                    if (!played.get()) throw new IllegalStateException("Native play returned false");
                    outcome.add("afterPlay", snapshots(session));
                    resolved = settle(session);
                }
                Card current = session.game.getCardState(source);
                if (activationIndex >= 0) {
                    current.setSickness(false); current.setTapped(false);
                    if (current.isPlaneswalker()) current.setCounters(CounterEnumType.LOYALTY, 20);
                    if (paper.getName().endsWith("Talent") || paper.getName().equals("Cool but Rude")) current.setClassLevel(activationIndex);
                    Player opponent = session.game.getPlayers().get(1);
                    card(session, opponent, "Hallowed Fountain", ZoneType.Battlefield);
                    Card legendary = card(session, owner, "Isamaru, Hound of Konda", ZoneType.Battlefield);
                    Card mouse = card(session, owner, "Heartfire Hero", ZoneType.Battlefield);
                    mouse.setCounters(CounterEnumType.P1P1, 2);
                    Card tapped = card(session, opponent, "Serra Angel", ZoneType.Battlefield); tapped.setTapped(true);
                    SpellAbility activated = current.getSpellAbilities().get(activationIndex);
                    activated.setActivatingPlayer(owner);
                    if (activated.toString().startsWith("Ninjutsu") || paper.getName().equals("Eiganjo, Seat of the Empire")) {
                        session.game.getPhaseHandler().devModeSet(PhaseType.COMBAT_DECLARE_BLOCKERS, owner, false, 4);
                        Combat combat = new Combat(owner); session.game.getPhaseHandler().setCombat(combat);
                        combat.addAttacker(legendary, opponent); combat.setBlocked(legendary, false);
                    }
                    if (paper.getName().equals("Lion Sash") && activated.toString().contains("Unattach")) current.attachToEntity(legendary, activated);
                    if (paper.getName().equals("Fountainport")) {
                        SpellAbility token = forge.game.ability.AbilityFactory.getAbility("DB$ Token | TokenScript$ c_a_treasure_sac", current);
                        token.setActivatingPlayer(owner); forge.game.ability.AbilityUtils.resolve(token);
                    }
                    if (paper.getName().equals("A Killer Among Us")) {
                        session.game.getPhaseHandler().devModeSet(PhaseType.COMBAT_DECLARE_BLOCKERS, owner, false, 4);
                        Combat combat = new Combat(owner); session.game.getPhaseHandler().setCombat(combat);
                        for (Card token : owner.getCreaturesInPlay()) if (token.isToken()) combat.addAttacker(token, opponent);
                        outcome.addProperty("combatFixture", "Tokens created by this enchantment are attacking");
                    }
                    if (paper.getName().equals("Mystifying Maze")) {
                        session.game.getPhaseHandler().devModeSet(PhaseType.COMBAT_DECLARE_BLOCKERS, opponent, false, 4);
                        Combat combat = new Combat(opponent); session.game.getPhaseHandler().setCombat(combat);
                        combat.addAttacker(tapped, owner);
                        outcome.addProperty("combatFixture", "Opponent Serra Angel is attacking");
                    }
                    if (paper.getName().equals("Inventors' Fair")) card(session, owner, "Chromatic Star", ZoneType.Battlefield);
                    if (paper.getName().equals("Swarmyard")) card(session, owner, "Relentless Rats", ZoneType.Battlefield);
                    if (paper.getName().equals("Blinkmoth Nexus") && activationIndex == 3) {
                        SpellAbility animation = current.getSpellAbilities().get(2);
                        animation.setActivatingPlayer(owner);
                        forge.game.ability.AbilityUtils.resolve(animation);
                    }
                    if (paper.getName().equals("Mirrorpool") && activationIndex == 2) {
                        Card target = card(session, owner, "Lightning Bolt", ZoneType.Stack);
                        SpellAbility burn = target.getSpellAbilities().get(0);
                        burn.setActivatingPlayer(owner); burn.getTargets().add(opponent);
                        session.game.getStack().add(burn);
                    }
                    session.game.getAction().checkStaticAbilities();
                    outcome.add("beforeActivation", snapshots(session));
                    outcome.addProperty("activatedAbility", activated.toString());
                    if (!activated.canPlay()) throw new IllegalStateException("Activation requires a different fixture: " + activated);
                    if (!PlaySpellAbility.playSpellAbility((PlayerControllerHuman) owner.getController(), owner, activated))
                        throw new IllegalStateException("Native activation returned false");
                    resolved += settle(session);
                    current = session.game.getCardState(source);
                }
                String zone = current.getZone() == null ? "None" : current.getZone().getZoneType().name();
                outcome.addProperty("finalZone", zone);
                outcome.addProperty("resolvedStackObjects", resolved);
                if (zone.equals("Stack") || activationIndex < 0 && zone.equals("Hand") && !paper.getName().equals("Acererak the Archlich"))
                    throw new AssertionError("Played card remained in " + zone);
                outcome.add("after", snapshots(session));
            });
            for (var entry : outcome.entrySet()) record.add(entry.getKey(), entry.getValue());
            record.addProperty("status", "resolved");
        } catch (Throwable error) {
            record.addProperty("status", "needs-triage");
            record.addProperty("reason", error.toString());
            StringWriter trace = new StringWriter(); error.printStackTrace(new PrintWriter(trace));
            record.addProperty("exception", trace.toString());
        }
    }

    private static int settle(NativeSession session) {
        int resolved = 0;
        for (int step = 0; step < 64; step++) {
            session.game.getAction().checkStateEffects(false);
            session.game.getTriggerHandler().runWaitingTriggers();
            session.game.getStack().addAllTriggeredAbilitiesToStack();
            if (session.game.getStack().isEmpty()) return resolved;
            session.game.getStack().resolveStack(); resolved++;
        }
        throw new IllegalStateException("Resolution step budget exhausted");
    }

    private static JsonArray snapshots(NativeSession session) {
        JsonArray states = new JsonArray();
        for (int viewer : new int[]{0, 1, -1}) states.add(NativeSnapshot.capture(session.game, session.id, viewer, session.game.getPlayers().get(0)));
        return states;
    }

    private static void drive(NativeSession session, JsonArray frames, Runnable work) throws Exception {
        Player owner = session.game.getPlayers().get(0);
        session.context.gameExecutor().execute(() -> {
            try { work.run(); session.publish(owner, object("type", "corpusComplete"), ignored -> () -> {}, false); }
            catch (Throwable error) { session.fail(error); }
        });
        long deadline = System.nanoTime() + 20_000_000_000L;
        Map<String, Integer> repeated = new HashMap<>();
        while (System.nanoTime() < deadline && frames.size() < 120) {
            String raw = session.prompt(0);
            if (raw.isEmpty()) { Thread.sleep(2); continue; }
            JsonObject prompt = JsonParser.parseString(raw).getAsJsonObject();
            int actor = Integer.parseInt(prompt.get("decidingPlayerId").getAsString().substring("player-".length()));
            JsonObject input = prompt.getAsJsonObject("input");
            String type = input.get("type").getAsString();
            if (type.equals("corpusComplete")) return;
            JsonObject frame = new JsonObject(); frame.addProperty("actor", actor);
            frame.add("prompt", prompt); frame.add("snapshots", snapshots(session)); frames.add(frame);
            String signature = input.toString();
            int occurrence = repeated.merge(signature, 1, Integer::sum);
            if (occurrence > 8) throw new IllegalStateException("Repeated native decision: " + input);
            JsonObject response = object("type", type);
            response.add("output", answer(input, occurrence)); frame.add("response", response);
            session.submit(response);
        }
        throw new IllegalStateException("Native case exceeded its time or decision budget");
    }

    private static JsonObject answer(JsonObject input, int occurrence) {
        String type = input.get("type").getAsString();
        JsonObject out;
        JsonArray selected = new JsonArray();
        switch (type) {
            case "payManaCost":
                if (input.get("canAutoPay").getAsBoolean()) {
                    out = object("type", "pay"); out.addProperty("auto", true); return out;
                }
                throw new IllegalStateException("Fixture cannot automatically pay native cost: " + input.get("manaCost"));
            case "chooseBoolean": out = object("type", "decision"); out.addProperty("value", true); return out;
            case "chooseNumber":
                out = object("type", "numberDecision");
                out.addProperty("chosenNumber", Math.min(input.get("max").getAsInt(), Math.max(input.get("min").getAsInt(), 2))); return out;
            case "chooseCardName":
                out = object("type", "cardName");
                String title = input.getAsJsonObject("presentation").get("title").getAsString();
                out.addProperty("name", title.contains("dungeon") ? "Lost Mine of Phandelver"
                        : title.contains("land card") && !title.contains("nonland") ? "Forest" : "Lightning Bolt"); return out;
            case "revealCards": return object("type", "revealCardsAcknowledged");
            case "chooseBoardTargets":
                boolean crew = input.toString().contains("Crewing:");
                if (input.get("minTargets").getAsInt() > 0 || !crew && occurrence == 1)
                    for (JsonElement c : input.getAsJsonArray("candidates")) {
                        if ((input.get("minTargets").getAsInt() == 0 || crew) && c.getAsJsonObject().has("selected")
                                && c.getAsJsonObject().get("selected").getAsBoolean()) continue;
                        JsonObject target = object("kind", c.getAsJsonObject().get("kind").getAsString());
                        target.add("id", c.getAsJsonObject().get("id")); selected.add(target); break;
                    }
                out = object("type", "boardTargets"); out.add("chosen", selected); return out;
            case "chooseCards":
                int count = Math.min(input.get("max").getAsInt(), Math.max(input.get("min").getAsInt(), 1));
                List<JsonElement> cards = new ArrayList<>(input.getAsJsonArray("cards").asList());
                cards.removeIf(c -> c.getAsJsonObject().has("readOnly") && c.getAsJsonObject().get("readOnly").getAsBoolean());
                if (input.toString().contains("Exile evidence")) cards.sort(Comparator.comparing(c ->
                        !c.getAsJsonObject().getAsJsonObject("identity").get("name").getAsString().equals("Ulamog, the Ceaseless Hunger")));
                boolean hasNativeSelection = cards.stream().anyMatch(c -> c.getAsJsonObject().has("selected")
                        && c.getAsJsonObject().get("selected").getAsBoolean());
                if (hasNativeSelection && input.get("min").getAsInt() == 0) count = 0;
                for (JsonElement c : cards) {
                    if (selected.size() == count) break;
                    if (c.getAsJsonObject().has("selected") && c.getAsJsonObject().get("selected").getAsBoolean()) continue;
                    selected.add(c.getAsJsonObject().get("id"));
                }
                out = object("type", "chooseCardsDecision"); out.add("chosenCardIds", selected); return out;
            case "chooseFromSelection":
                int total = Math.min(input.get("maxTotal").getAsInt(), Math.max(input.get("minTotal").getAsInt(), 1));
                for (int i = 0; i < total; i++) selected.add(i);
                out = object("type", "selectionDecision"); out.add("chosenIndices", selected); return out;
            case "reorder":
                for (JsonElement item : input.getAsJsonArray("items")) selected.add(item.getAsJsonObject().get("id"));
                out = object("type", "reorderDecision"); out.add("orderedIds", selected); return out;
            case "scry":
                for (JsonElement item : input.getAsJsonArray("cards")) selected.add(item.getAsJsonObject().get("id"));
                JsonArray zones = new JsonArray(); zones.add(selected); zones.add(new JsonArray());
                out = object("type", "scryDecision"); out.add("zoneCardIds", zones); return out;
            default: throw new IllegalStateException("Driver has no policy for " + type + ": " + input);
        }
    }
}
