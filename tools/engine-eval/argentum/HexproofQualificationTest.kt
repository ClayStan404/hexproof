// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package com.wingedsheep.engine.evaluation

import com.wingedsheep.engine.core.*
import com.wingedsheep.engine.support.GameTestDriver
import com.wingedsheep.engine.state.ZoneKey
import com.wingedsheep.engine.state.components.stack.ChosenTarget
import com.wingedsheep.engine.view.ClientStateTransformer
import com.wingedsheep.mtg.sets.MtgSetCatalog
import com.wingedsheep.sdk.core.Step
import com.wingedsheep.sdk.core.Zone
import com.wingedsheep.sdk.model.Deck
import com.wingedsheep.sdk.model.EntityId
import com.wingedsheep.sdk.core.Color
import com.wingedsheep.sdk.core.Format
import com.wingedsheep.sdk.model.CardLayout
import com.wingedsheep.sdk.scripting.targets.EffectTarget
import com.wingedsheep.sdk.dsl.*
import com.wingedsheep.sdk.scripting.*
import com.wingedsheep.sdk.scripting.values.*
import com.wingedsheep.sdk.scripting.predicates.CardPredicate
import com.wingedsheep.sdk.scripting.targets.TargetObject
import com.wingedsheep.sdk.scripting.filters.unified.TargetFilter
import com.wingedsheep.engine.state.components.identity.FaceDownComponent
import com.wingedsheep.engine.state.components.player.ManaPoolComponent
import com.wingedsheep.engine.state.components.battlefield.PreparedComponent
import com.wingedsheep.engine.state.components.battlefield.PreparedSpellCopyComponent
import io.kotest.core.spec.style.FunSpec
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import java.io.File

// Isolated downstream fixture. No engine/card-definition changes or mocked outcomes.
class HexproofQualificationTest : FunSpec({
    test("frozen Hexproof 2026-09-09.2 core and hard gates") {
        val rows = mutableListOf<JsonElement>()
        fun probe(id: String, body: (MutableList<Pair<String, Boolean>>, MutableMap<String, JsonElement>) -> Unit) {
            val checks = mutableListOf<Pair<String, Boolean>>()
            val observed = linkedMapOf<String, JsonElement>()
            var error: String? = null
            try { body(checks, observed) } catch (e: Throwable) {
                error = e.stackTraceToString()
            }
            rows.add(buildJsonObject {
                put("id", id)
                put("assertions", buildJsonArray { checks.forEach { (name, ok) ->
                    add(buildJsonObject { put("name", name); put("passed", ok) })
                } })
                put("observed", JsonObject(observed))
                if (error != null) put("error", error!!)
            })
            println("HEXPROOF_CASE " + rows.last())
        }
        // Missing printed entries are explicit downstream card-data fixtures,
        // never engine repairs or a claim of bundled card coverage. Text/costs
        // match the fixed suite and the pinned actual card scripts used by Rust.
        fun fillFixtureCards(d: GameTestDriver) {
            // Same declared predefined-token data used by ScenarioTestBase;
            // GameTestDriver itself does not register these automatically.
            d.registerCards(com.wingedsheep.mtg.sets.tokens.PredefinedTokens.allTokens)
            if (d.cardRegistry.getCard("Lovestruck Beast") == null) d.registerCard(card("Lovestruck Beast") {
                manaCost="{2}{G}"; typeLine="Creature — Beast Noble"; power=5; toughness=5
                oracleText="Lovestruck Beast can't attack unless you control a 1/1 creature."
                staticAbility { ability=CantAttackUnless(Conditions.YouControl(GameObjectFilter.Creature.copy(cardPredicates=listOf(CardPredicate.PowerEquals(1),CardPredicate.ToughnessEquals(1))))) }
                adventure("Heart's Desire") {
                    manaCost="{G}"; typeLine="Sorcery — Adventure"; oracleText="Create a 1/1 white Human creature token."
                    spell {effect=Effects.CreateToken(power=1,toughness=1,colors=setOf(Color.WHITE),creatureTypes=setOf("Human"))}
                }
            })
            if (d.cardRegistry.getCard("Bala Ged Recovery") == null) {
                val back=card("Bala Ged Sanctuary") {
                    typeLine="Land"; oracleText="Bala Ged Sanctuary enters tapped.\n{T}: Add {G}."
                    replacementEffect(EntersTapped())
                    activatedAbility {cost=AbilityCost.Tap; effect=Effects.AddMana(Color.GREEN);manaAbility=true;timing=TimingRule.ManaAbility}
                }
                val front=card("Bala Ged Recovery") {
                    manaCost="{2}{G}";typeLine="Sorcery";oracleText="Return target card from your graveyard to your hand."
                    spell {target=TargetObject(filter=TargetFilter.CardInGraveyard.ownedByYou());effect=Effects.ReturnToHand(EffectTarget.ContextTarget(0))}
                }
                d.registerCard(front.copy(backFace=back,layout=CardLayout.MODAL_DFC))
            }
            if (d.cardRegistry.getCard("Soul's Fire") == null) d.registerCard(card("Soul's Fire") {
                manaCost="{2}{R}";typeLine="Instant";oracleText="Target creature you control deals damage equal to its power to any target."
                spell {
                    val source=target("source",Targets.CreatureYouControl); val victim=target("victim",Targets.Any)
                    effect=Effects.DealDamage(DynamicAmount.EntityProperty(EntityReference.Target(0),EntityNumericProperty.Power),victim,damageSource=source)
                }
            })
        }
        fun fresh(players: Int = 2, opening: Boolean = false, commander: Boolean = false): Pair<GameTestDriver, List<EntityId>> {
            val d = GameTestDriver()
            // Use production catalog only; TestCards contains simplified named overrides.
            d.registerCards(MtgSetCatalog.all.flatMap { it.cards + it.basicLands })
            fillFixtureCards(d)
            val ids = d.initMultiplayer(List(players) { Deck.of("Plains" to 60) }, skipMulligans = !opening,
                format=if(commander) Format.Commander() else Format.Standard,
                commanders=if(commander) List(players){"Isamaru, Hound of Konda"} else emptyList())
            if (!opening) {
                d.passPriorityUntil(Step.PRECOMBAT_MAIN)
                // Canonical core fixtures: empty hands, 30 ordered Plains libraries.
                d.replaceState(d.state.copy(zones = d.state.zones.mapValues { (key, value) ->
                    when (key.zoneType) {
                        Zone.HAND -> emptyList()
                        Zone.LIBRARY -> value.take(30)
                        else -> value
                    }
                }))
            }
            return d to ids
        }
        fun ok(r: ExecutionResult) { check(r.error == null) { r.error ?: "unknown action error" } }
        fun snapshot(d: GameTestDriver): JsonElement = buildJsonObject {
            put("step", d.currentStep.name)
            put("active", d.activePlayer?.value)
            put("priority", d.priorityPlayer?.value)
            put("gameOver", d.state.gameOver)
            put("winner", d.state.winnerId?.value)
            put("activePlayers", buildJsonArray { d.state.activePlayers.forEach { add(it.value) } })
            put("stack", buildJsonArray { d.state.stack.forEach { add(it.value) } })
            put("stackNames", buildJsonArray { d.getStackSpellNames().forEach { add(it) } })
            put("zones", buildJsonArray { d.state.zones.forEach { (key, ids) ->
                add(buildJsonObject {
                    put("owner", key.ownerId.value); put("zone", key.zoneType.name); put("size", ids.size)
                    put("names", buildJsonArray { ids.forEach { add(d.getCardName(it)) } })
                })
            } })
        }
        fun resolve(d: GameTestDriver) {
            var n = 0
            while (d.stackSize > 0) {
                check(++n <= 40) { "Stack did not drain" }
                check(d.pendingDecision == null) { "Unhandled choice: " + d.pendingDecision }
                ok(d.passPriority(requireNotNull(d.priorityPlayer)))
            }
        }
        fun grave(d: GameTestDriver, p: EntityId, id: EntityId) = id in d.state.getZone(p, Zone.GRAVEYARD)
        fun drain(d: GameTestDriver, selected: EntityId?=null, prompts: MutableList<String> = mutableListOf()) {
            var steps=0
            while(d.stackSize>0 || d.pendingDecision!=null) {
                check(++steps<80){"bounded stack/choice drain"}
                val q=d.pendingDecision
                if(q!=null) {
                    prompts+=Json.encodeToString<PendingDecision>(q)
                    when(q) {
                        is YesNoDecision -> ok(d.submitDecision(q.playerId,YesNoResponse(q.id,true)))
                        is SelectCardsDecision -> {
                            val chosen=selected?.takeIf{it in q.options} ?: q.options.firstOrNull()
                            ok(d.submitDecision(q.playerId,CardsSelectedResponse(q.id,chosen?.let{listOf(it)} ?: emptyList())))
                        }
                        else -> error("Unhandled exact choice: $q")
                    }
                } else ok(d.passPriority(requireNotNull(d.priorityPlayer)))
            }
        }
        fun cardView(d: GameTestDriver,p:EntityId,id:EntityId) = ClientStateTransformer(d.cardRegistry).transform(d.state,p).cards[id]
        fun power(d:GameTestDriver,id:EntityId)=d.state.projectedState.getPower(id)
        fun toughness(d:GameTestDriver,id:EntityId)=d.state.projectedState.getToughness(id)

        probe("opening") { a, o ->
            val (d, p) = fresh(opening = true)
            ok(d.submit(KeepHand(p[0]))); ok(d.submit(KeepHand(p[1])))
            d.passPriorityUntil(Step.PRECOMBAT_MAIN)
            a += "Both hands contain seven cards" to p.all { d.getHand(it).size == 7 }
            a += "Both libraries contain 53 cards" to p.all { d.state.getZone(it, Zone.LIBRARY).size == 53 }
            a += "Starting player skipped their first draw" to (d.getHand(p[0]).size == 7 && d.state.getZone(p[0], Zone.LIBRARY).size == 53)
            a += "Player 0 can receive a main-phase decision" to (d.priorityPlayer == p[0] && d.currentStep == Step.PRECOMBAT_MAIN && d.legalActions(p[0]).isNotEmpty())
            o["final"] = snapshot(d)
        }
        probe("land_priority") { a, o ->
            val (d, p) = fresh()
            val one = d.putCardInHand(p[0], "Plains"); val two = d.putCardInHand(p[0], "Plains")
            ok(d.playLand(p[0], one))
            a += "Exactly one Plains moved from hand to battlefield" to (d.getLands(p[0]) == listOf(one) && d.getHand(p[0]) == listOf(two))
            val before = d.state
            val second = d.playLand(p[0], two)
            a += "Second land rejected without mutation" to (second.error != null && d.state == before)
            val wrong = d.passPriority(p[1])
            a += "Out-of-turn actor cannot spend player 0 decision" to (wrong.error != null && d.state == before && d.priorityPlayer == p[0])
            o["secondError"] = JsonPrimitive(second.error); o["wrongActorError"] = JsonPrimitive(wrong.error)
            o["final"] = snapshot(d)
        }
        probe("bolt_player") { a, o ->
            val (d, p) = fresh()
            val bolt = d.putCardInHand(p[0], "Lightning Bolt"); val land = d.putLandOnBattlefield(p[0], "Mountain")
            ok(d.castSpell(p[0], bolt, listOf(p[1])))
            a += "Before resolution player 1 life 20 and Bolt on stack" to (d.getLifeTotal(p[1]) == 20 && bolt in d.state.stack && bolt !in d.getHand(p[0]))
            o["beforeResolution"] = snapshot(d)
            resolve(d)
            a += "After resolution player 1 life 17" to (d.getLifeTotal(p[1]) == 17)
            a += "Bolt graveyard and Mountain tapped" to (grave(d, p[0], bolt) && d.isTapped(land))
            o["final"] = snapshot(d); o["life"] = JsonPrimitive(d.getLifeTotal(p[1]))
        }
        probe("bolt_creature") { a, o ->
            val (d, p) = fresh()
            val bolt = d.putCardInHand(p[0], "Lightning Bolt"); d.putLandOnBattlefield(p[0], "Mountain")
            val bears = d.putCreatureOnBattlefield(p[1], "Grizzly Bears")
            ok(d.castSpell(p[0], bolt, listOf(bears))); resolve(d)
            a += "Bears and Bolt in owners graveyards" to (grave(d, p[0], bolt) && grave(d, p[1], bears))
            a += "Player 1 still life 20" to (d.getLifeTotal(p[1]) == 20)
            a += "No Bears remains on battlefield" to (bears !in d.getPermanents(p[1]))
            o["final"] = snapshot(d)
        }
        probe("counterspell") { a, o ->
            val (d, p) = fresh()
            val bolt = d.putCardInHand(p[0], "Lightning Bolt"); d.putLandOnBattlefield(p[0], "Mountain")
            val counter = d.putCardInHand(p[1], "Counterspell")
            repeat(2) { d.putLandOnBattlefield(p[1], "Island") }
            ok(d.castSpell(p[0], bolt, listOf(p[1])))
            ok(d.passPriority(p[0]))
            ok(d.castSpellWithTargets(p[1], counter, listOf(ChosenTarget.Spell(bolt))))
            a += "Counterspell above Bolt on stack" to (d.state.stack == listOf(bolt, counter))
            o["beforeResolution"] = snapshot(d)
            resolve(d)
            a += "Both life totals remain 20" to p.all { d.getLifeTotal(it) == 20 }
            a += "Both spells in owners graveyards and empty stack" to (grave(d, p[0], bolt) && grave(d, p[1], counter) && d.stackSize == 0)
            o["final"] = snapshot(d)
        }
        probe("etb_draw") { a, o ->
            val (d, p) = fresh()
            val visionary = d.putCardInHand(p[0], "Elvish Visionary")
            d.putLandOnBattlefield(p[0], "Forest"); d.putLandOnBattlefield(p[0], "Plains")
            val before = d.state.getZone(p[0], Zone.LIBRARY).size
            ok(d.castSpell(p[0], visionary))
            ok(d.passPriority(requireNotNull(d.priorityPlayer))); ok(d.passPriority(requireNotNull(d.priorityPlayer)))
            val triggerIntermediate = visionary in d.getPermanents(p[0]) && d.stackSize == 1 &&
                d.state.getZone(p[0], Zone.LIBRARY).size == before && visionary !in d.state.stack
            o["creatureResolvedTriggerPending"] = snapshot(d)
            resolve(d)
            a += "Visionary on battlefield" to (visionary in d.getPermanents(p[0]))
            a += "Exactly one card drawn" to (before == 30 && d.state.getZone(p[0], Zone.LIBRARY).size == 29 && d.getHand(p[0]).size == 1)
            a += "ETB stack resolves after creature" to (triggerIntermediate && d.currentStep == Step.PRECOMBAT_MAIN)
            o["final"] = snapshot(d)
        }
        probe("blocked_combat") { a, o ->
            val (d, p) = fresh()
            val x = d.putCreatureOnBattlefield(p[0], "Grizzly Bears")
            val y = d.putCreatureOnBattlefield(p[1], "Grizzly Bears")
            d.removeSummoningSickness(x); d.removeSummoningSickness(y)
            d.passPriorityUntil(Step.DECLARE_ATTACKERS)
            ok(d.declareAttackers(p[0], mapOf(x to p[1])))
            d.passPriorityUntil(Step.DECLARE_BLOCKERS)
            ok(d.declareBlockers(p[1], mapOf(y to listOf(x))))
            d.passPriorityUntil(Step.POSTCOMBAT_MAIN)
            a += "Both Bears die" to (x !in d.getPermanents(p[0]) && y !in d.getPermanents(p[1]))
            a += "Both life totals stay 20" to p.all { d.getLifeTotal(it) == 20 }
            a += "Each Bears in owners graveyard" to (grave(d, p[0], x) && grave(d, p[1], y))
            o["final"] = snapshot(d)
        }
        probe("hidden_views") { a, o ->
            val (d, p) = fresh()
            val h0 = d.putCardInHand(p[0], "Lightning Bolt"); val h1 = d.putCardInHand(p[1], "Counterspell")
            d.putCardOnTopOfLibrary(p[0], "Mountain"); d.putCardOnTopOfLibrary(p[1], "Swamp")
            d.replaceState(d.state.copy(zones = d.state.zones.mapValues { (key, value) ->
                if (key.zoneType == Zone.LIBRARY) value.take(30) else value
            }))
            val bears = d.putCreatureOnBattlefield(p[0], "Grizzly Bears")
            val transformer = ClientStateTransformer(d.cardRegistry)
            val owner = transformer.transform(d.state, p[0])
            val opponent = transformer.transform(d.state, p[1])
            val spectator = transformer.transform(d.state, p[0], isSpectator = true)
            val views = listOf(owner, opponent, spectator)
            val serialized = views.map { Json.encodeToString(it) }
            a += "Owner can identify own hand" to (owner.cards[h0]?.name == "Lightning Bolt" && opponent.cards[h1]?.name == "Counterspell")
            a += "Opponent and spectator lack secret identities and private text in nested JSON" to (
                !serialized[1].contains("Lightning Bolt") && !serialized[0].contains("Counterspell") &&
                !serialized[2].contains("Lightning Bolt") && !serialized[2].contains("Counterspell") &&
                !serialized[1].contains(d.cardRegistry.requireCard("Lightning Bolt").oracleText) &&
                !serialized[0].contains(d.cardRegistry.requireCard("Counterspell").oracleText))
            // Preserve the actual raw external projection, including ordered opaque library IDs.
            val libraryNamesHidden = serialized.none { it.contains("Mountain") || it.contains("Swamp") }
            val orderedLibraryIdsExposed = views.any { view -> view.zones.any { zone ->
                zone.zoneId.zoneType == Zone.LIBRARY && zone.cardIds.isNotEmpty() &&
                    zone.cardIds == d.state.getZone(zone.zoneId)
            } }
            a += "Library identities and order private even to owner" to (libraryNamesHidden && !orderedLibraryIdsExposed)
            a += "Public Bears and public zone counts visible" to views.all { v ->
                v.cards[bears]?.name == "Grizzly Bears" && p.all { id ->
                    v.zones.any { it.zoneId == ZoneKey(id, Zone.HAND) && it.size == 1 } &&
                    v.zones.any { it.zoneId == ZoneKey(id, Zone.LIBRARY) && it.size == 30 }
                }
            }
            o["owner"] = Json.parseToJsonElement(serialized[0])
            o["opponent"] = Json.parseToJsonElement(serialized[1])
            o["spectator"] = Json.parseToJsonElement(serialized[2])
            o["libraryNamesHidden"] = JsonPrimitive(libraryNamesHidden)
            o["orderedOpaqueLibraryIdsExposed"] = JsonPrimitive(orderedLibraryIdsExposed)
            o["scope"] = JsonPrimitive("Actual ClientStateTransformer with isSpectator=true; not WebSocket/session/event-stream certification. Opaque IDs are not a demonstrated card-name leak.")
        }
        probe("supplemental_library_tracking") { a, o ->
            // Separate runtime proof, not a different fixture promoted as the hidden_views case.
            val (d, p) = fresh()
            val bears = d.putCreatureOnBattlefield(p[1], "Grizzly Bears")
            val ebb = d.putCardInHand(p[0], "Time Ebb")
            repeat(3) { d.putLandOnBattlefield(p[0], "Island") }
            val myr = d.putCreatureOnBattlefield(p[1], "Myr Mindservant")
            d.removeSummoningSickness(myr)
            repeat(2) { d.putLandOnBattlefield(p[1], "Plains") }
            val transformer = ClientStateTransformer(d.cardRegistry)
            val before = transformer.transform(d.state, p[0], isSpectator = true)
            ok(d.castSpell(p[0], ebb, listOf(bears))); resolve(d)
            val after = transformer.transform(d.state, p[0], isSpectator = true)
            val library = after.zones.single { it.zoneId == ZoneKey(p[1], Zone.LIBRARY) }
            a += "Real Time Ebb moved Bears into library" to (bears in d.state.getZone(p[1], Zone.LIBRARY))
            a += "Spectator links known public Bears identity to exact library slot by stable ID" to (
                before.cards[bears]?.name == "Grizzly Bears" &&
                    library.cardIds == d.state.getZone(p[1], Zone.LIBRARY) && bears in library.cardIds)
            o["knownPublicId"] = JsonPrimitive(bears.value)
            o["actualLibraryIndex"] = JsonPrimitive(d.state.getZone(p[1], Zone.LIBRARY).indexOf(bears))
            o["visibleLibraryIndex"] = JsonPrimitive(library.cardIds.indexOf(bears))
            o["beforeSpectator"] = Json.encodeToJsonElement(before)
            o["afterSpectator"] = Json.encodeToJsonElement(after)
            o["cardDetailsStillVisible"] = JsonPrimitive(after.cards.containsKey(bears))
            while (d.priorityPlayer != p[1]) ok(d.passPriority(requireNotNull(d.priorityPlayer)))
            ok(d.submit(ActivateAbility(p[1], myr, d.cardRegistry.requireCard("Myr Mindservant").activatedAbilities.single().id)))
            resolve(d)
            val shuffled = transformer.transform(d.state, p[0], isSpectator = true)
            val shuffledLibrary = shuffled.zones.single { it.zoneId == ZoneKey(p[1], Zone.LIBRARY) }
            a += "Real paid Myr ability shuffles library and taps source" to (
                d.isTapped(myr) && shuffledLibrary.cardIds != library.cardIds)
            a += "Spectator still recovers known Bears location after real shuffle" to (
                bears in shuffledLibrary.cardIds &&
                    shuffledLibrary.cardIds == d.state.getZone(p[1], Zone.LIBRARY) &&
                    !shuffled.cards.containsKey(bears))
            o["afterShuffleSpectator"] = Json.encodeToJsonElement(shuffled)
            o["afterShuffleKnownCardIndex"] = JsonPrimitive(shuffledLibrary.cardIds.indexOf(bears))
            o["scope"] = JsonPrimitive("Supplemental proof: real Time Ebb then paid Myr Mindservant shuffle; spectator links public Bears ID to hidden library slot after shuffle.")
        }
        probe("four_player_departure") { a, o ->
            val (d, p) = fresh(4)
            val bears = d.putCreatureOnBattlefield(p[2], "Grizzly Bears")
            val land = d.putCardInHand(p[0], "Plains")
            check(d.priorityPlayer == p[0] && d.legalActions(p[0]).isNotEmpty())
            o["pendingDecisionBefore"] = snapshot(d)
            ok(d.concede(p[2]))
            a += "First departure leaves three players, game continues" to (d.state.activePlayers == listOf(p[0], p[1], p[3]) && !d.state.gameOver)
            a += "Departing players Bears leaves game" to (d.state.zones.values.none { bears in it } && d.state.getEntity(bears) == null)
            o["afterFirstDeparture"] = snapshot(d)
            val play = d.playLand(p[0], land)
            a += "Remaining player continues through decision" to (play.error == null && land in d.getPermanents(p[0]))
            ok(d.concede(p[1]))
            val notYetOver = !d.state.gameOver
            ok(d.concede(p[3]))
            a += "Only after all opponents leave player 0 wins" to (notYetOver && d.state.gameOver && d.state.winnerId == p[0])
            o["final"] = snapshot(d)
        }
        probe("commander_tax") { a,o ->
            val(d,p)=fresh(4,commander=true)
            val command=p.map{d.state.getZone(it,Zone.COMMAND).single()};val cmd=command[0]
            a += "Four players start at 40 with commanders in command zones" to (p.all{d.getLifeTotal(it)==40}&&command.distinct().size==4)
            val lands=List(4){d.putLandOnBattlefield(p[0],"Plains")};repeat(3){d.putLandOnBattlefield(p[0],"Swamp")}
            val murder=d.putCardInHand(p[0],"Murder")
            ok(d.castSpell(p[0],cmd));drain(d)
            val firstPaid=d.getLands(p[0]).count{d.isTapped(it)}
            ok(d.castSpell(p[0],murder,listOf(cmd)));val prompts=mutableListOf<String>();drain(d,prompts=prompts)
            val returned=cmd in d.state.getZone(p[0],Zone.COMMAND)
            a += "Return to command offered as optional choice" to (firstPaid==1&&returned&&prompts.any{it.contains("YesNoDecision")&&it.contains("command",true)})
            val poor=GameTestDriver();poor.registerCards(MtgSetCatalog.all.flatMap{it.cards+it.basicLands});fillFixtureCards(poor);poor.replaceState(d.state)
            poor.getLands(p[0]).forEach{poor.tapPermanent(it)};poor.untapPermanent(lands[0])
            val beforePoor=poor.state;val rejected=poor.castSpell(p[0],cmd)
            val before=d.getLands(p[0]).count{d.isTapped(it)}
            ok(d.castSpell(p[0],cmd));drain(d)
            val paid=d.getLands(p[0]).count{d.isTapped(it)}-before
            a += "Second command cast costs 2W and W alone rejected unchanged" to (paid==3&&rejected.error!=null&&poor.state==beforePoor)
            a += "Commander ends on battlefield after paid recast" to (cmd in d.getPermanents(p[0]))
            o["prompts"]=Json.encodeToJsonElement(prompts);o["firstPaid"]=JsonPrimitive(firstPaid);o["secondPaid"]=JsonPrimitive(paid);o["insufficientError"]=JsonPrimitive(rejected.error);o["final"]=snapshot(d)
        }
        probe("commander_damage") { a,o ->
            val(d,p)=fresh(4,commander=true);val cmd=d.state.getZone(p[0],Zone.COMMAND).single()
            d.putLandOnBattlefield(p[0],"Plains");repeat(3){d.putLandOnBattlefield(p[0],"Mountain")}
            val fire=d.putCardInHand(p[0],"Soul's Fire")
            ok(d.castSpell(p[0],cmd));drain(d);d.removeSummoningSickness(cmd)
            d.replaceState(d.state.recordCommanderDamage(cmd,p[1],19))
            val nc=GameTestDriver();nc.registerCards(MtgSetCatalog.all.flatMap{it.cards+it.basicLands});fillFixtureCards(nc);nc.replaceState(d.state)
            ok(nc.castSpellWithTargets(p[0],fire,listOf(ChosenTarget.Permanent(cmd),ChosenTarget.Player(p[1]))));drain(nc)
            val ncLife=nc.getLifeTotal(p[1]);val ncDamage=nc.state.commanderDamageOf(cmd,p[1])
            d.passPriorityUntil(Step.DECLARE_ATTACKERS);ok(d.declareAttackers(p[0],mapOf(cmd to p[1])))
            d.passPriorityUntil(Step.POSTCOMBAT_MAIN)
            val defenderLife=d.getLifeTotal(p[1]);val damage=d.state.commanderDamageOf(cmd,p[1]);val alive=d.state.activePlayers
            val continuation=d.passPriority(requireNotNull(d.priorityPlayer))
            a += "Defender loses at 21 commander damage despite positive life" to (damage==21&&defenderLife==38&&p[1] !in alive)
            a += "Other players continue through actual priority action" to (alive.size==3&&!d.state.gameOver&&continuation.error==null)
            a += "Actual noncombat two damage does not increment commander counter" to (ncLife==38&&ncDamage==19)
            o["noncombatLife"]=JsonPrimitive(ncLife);o["noncombatCounter"]=JsonPrimitive(ncDamage);o["combatLife"]=JsonPrimitive(defenderLife);o["combatCounter"]=JsonPrimitive(damage);o["final"]=snapshot(d)
        }
        probe("adventure") {a,o ->
            val(d,p)=fresh();repeat(4){d.putLandOnBattlefield(p[0],"Forest")};val beast=d.putCardInHand(p[0],"Lovestruck Beast")
            ok(d.submit(CastSpell(p[0],beast,faceIndex=0)));drain(d)
            val tokens=d.getPermanents(p[0]).mapNotNull{cardView(d,p[0],it)}.filter{it.isToken}
            val exiled=beast in d.getExile(p[0]);val paidFirst=d.getLands(p[0]).count{d.isTapped(it)}
            a += "Adventure makes one white 1/1 Human" to (tokens.size==1&&tokens.all{it.power==1&&it.toughness==1&&it.colors==setOf(Color.WHITE)&&"Human" in it.subtypes&&"CREATURE" in it.cardTypes})
            a += "Same Beast exiled after successful Adventure" to (exiled&&paidFirst==1)
            o["afterAdventure"]=snapshot(d);o["tokens"]=Json.encodeToJsonElement(tokens)
            ok(d.castSpell(p[0],beast));drain(d)
            a += "Same creature cast from exile for 2G enters 5/5" to (beast in d.getPermanents(p[0])&&power(d,beast)==5&&toughness(d,beast)==5&&d.getLands(p[0]).count{d.isTapped(it)}==4)
            o["final"]=snapshot(d);o["dataScope"]=JsonPrimitive("Lovestruck Beast absent from bundled catalog; exact printed DSL test data, existing native Adventure runtime")
        }
        probe("modal_dfc") {a,o ->
            val(d,p)=fresh();val recovery=d.putCardInHand(p[0],"Bala Ged Recovery")
            ok(d.submit(PlayLand(p[0],recovery,asBackFace=true)))
            val entry=cardView(d,p[0],recovery)
            a += "Sanctuary enters tapped as land without casting sorcery" to (entry?.name=="Bala Ged Sanctuary"&&"LAND" in entry.cardTypes&&d.isTapped(recovery)&&d.stackSize==0)
            a += "No Recovery sorcery effect occurs" to (d.getHand(p[0]).isEmpty()&&d.getGraveyard(p[0]).isEmpty())
            o["entry"]=Json.encodeToJsonElement(entry)
            var steps=0
            while(d.isTapped(recovery)||d.activePlayer!=p[0]||d.currentStep!=Step.PRECOMBAT_MAIN) {
                check(++steps<200){"MDFC turn advance bound"};d.passPriorityUntil(Step.POSTCOMBAT_MAIN);d.passPriorityUntil(Step.PRECOMBAT_MAIN)
            }
            val mana=d.legalActions(p[0]).map{it.action}.filterIsInstance<ActivateAbility>().first{it.sourceId==recovery}
            ok(d.submit(mana))
            val green=d.state.getEntity(p[0])?.get<ManaPoolComponent>()?.green
            a += "After real untap Sanctuary taps for G" to (d.isTapped(recovery)&&green==1)
            o["green"]=JsonPrimitive(green);o["final"]=snapshot(d);o["dataScope"]=JsonPrimitive("Bala Ged Recovery absent from bundled catalog; exact printed front/back DSL test data, native modal back-land path")
        }
        probe("morph") {a,o ->
            val(d,p)=fresh();repeat(4){d.putLandOnBattlefield(p[0],"Plains")};d.putLandOnBattlefield(p[0],"Island")
            val will=d.putCardInHand(p[0],"Willbender");ok(d.submit(CastSpell(p[0],will,castFaceDown=true)))
            val stack=cardView(d,p[1],will);val paidDown=d.getLands(p[0]).count{d.isTapped(it)}
            val tr=ClientStateTransformer(d.cardRegistry)
            val stackViews=listOf(tr.transform(d.state,p[1]),tr.transform(d.state,p[0],isSpectator=true))
            drain(d)
            val down=cardView(d,p[1],will);val downViews=listOf(tr.transform(d.state,p[1]),tr.transform(d.state,p[0],isSpectator=true))
            o["stackViews"]=Json.encodeToJsonElement(stackViews);o["battlefieldViews"]=Json.encodeToJsonElement(downViews)
            // This is the engine's explicit nameless-card UI placeholder, not
            // a real name characteristic or an arbitrary non-Willbender name.
            fun hiddenBody(c:com.wingedsheep.engine.view.ClientCard?)=c!=null&&c.name==com.wingedsheep.engine.state.FACE_DOWN_DISPLAY_NAME&&c.power==2&&c.toughness==2&&c.colors.isEmpty()&&c.manaCost.isEmpty()&&c.manaValue==0&&c.oracleText.isEmpty()&&c.keywords.isEmpty()&&c.abilityFlags.isEmpty()&&c.subtypes.isEmpty()&&c.cardTypes==setOf("CREATURE")&&c.isFaceDown
            a += "Face-down stack/permanent have nameless colorless 2/2 profile and cost 3" to (hiddenBody(stack)&&hiddenBody(down)&&paidDown==3)
            a += "Opponent/spectator stack and battlefield do not reveal Willbender" to ((stackViews+downViews).none{Json.encodeToString(it).contains("Willbender")})
            ok(d.submit(TurnFaceUp(p[0],will)));drain(d)
            a += "Paid face-up preserves identity and becomes Willbender 1/2" to (will in d.getPermanents(p[0])&&d.getCardName(will)=="Willbender"&&power(d,will)==1&&toughness(d,will)==2&&d.state.getEntity(will)?.has<FaceDownComponent>()==false&&d.getLands(p[0]).count{d.isTapped(it)}==5)
            o["paidDown"]=JsonPrimitive(paidDown);o["final"]=snapshot(d)
        }
        probe("replacement") {a,o ->
            val(d,p)=fresh();d.putPermanentOnBattlefield(p[0],"Rest in Peace");val bears=d.putCreatureOnBattlefield(p[1],"Grizzly Bears")
            d.putLandOnBattlefield(p[0],"Mountain");val bolt=d.putCardInHand(p[0],"Lightning Bolt");ok(d.castSpell(p[0],bolt,listOf(bears)));drain(d)
            a += "Lethal Bears goes to exile not graveyard" to (bears in d.getExile(p[1])&&!grave(d,p[1],bears))
            a += "Resolved Bolt goes to exile not graveyard" to (bolt in d.getExile(p[0])&&!grave(d,p[0],bolt))
            a += "Both graveyards empty" to p.all{d.getGraveyard(it).isEmpty()};o["final"]=snapshot(d)
        }
        probe("copy") {a,o ->
            val(d,p)=fresh();d.putLandOnBattlefield(p[0],"Forest");repeat(4){d.putLandOnBattlefield(p[0],"Island")}
            val bears=d.putCreatureOnBattlefield(p[1],"Grizzly Bears");val growth=d.putCardInHand(p[0],"Giant Growth");val clone=d.putCardInHand(p[0],"Clone")
            ok(d.castSpell(p[0],growth,listOf(bears)));drain(d);check(power(d,bears)==5)
            ok(d.castSpell(p[0],clone));val prompts=mutableListOf<String>();drain(d,bears,prompts)
            val copied=cardView(d,p[0],clone)
            a += "Clone enters as Bears copy" to (clone in d.getPermanents(p[0])&&copied?.name=="Grizzly Bears")
            a += "Copy is 2/2 without temporary growth" to (power(d,clone)==2&&toughness(d,clone)==2)
            a += "Original remains 5/5 this turn" to (power(d,bears)==5&&toughness(d,bears)==5)
            o["copy"]=Json.encodeToJsonElement(copied);o["prompts"]=Json.encodeToJsonElement(prompts);o["final"]=snapshot(d)
        }
        probe("tokens") {a,o ->
            val(d,p)=fresh();repeat(2){d.putLandOnBattlefield(p[0],"Plains")};val raise=d.putCardInHand(p[0],"Raise the Alarm")
            ok(d.castSpell(p[0],raise));drain(d)
            val tokens=d.getPermanents(p[0]).mapNotNull{cardView(d,p[0],it)}.filter{it.isToken}
            a += "Exactly two white 1/1 Soldier creature tokens controlled by player 0" to (tokens.size==2&&tokens.all{it.power==1&&it.toughness==1&&it.colors==setOf(Color.WHITE)&&"Soldier" in it.subtypes&&"CREATURE" in it.cardTypes})
            a += "Raise the Alarm goes to graveyard" to grave(d,p[0],raise)
            a += "No token card taken from hand/library" to (d.getHand(p[0]).isEmpty()&&d.state.getZone(p[0],Zone.LIBRARY).size==30)
            o["tokens"]=Json.encodeToJsonElement(tokens);o["final"]=snapshot(d)
        }
        for(removal in listOf(false,true)) probe(if(removal) "prepare_source_leaves" else "prepare_cast") {a,o ->
            val(d,p)=fresh();repeat(3){d.putLandOnBattlefield(p[0],"Mountain")}
            val glass=d.putCardInHand(p[0],"Goblin Glasswright")
            val bolt=if(removal){d.putLandOnBattlefield(p[1],"Mountain");d.putCardInHand(p[1],"Lightning Bolt")}else null
            if(!removal) {
                // Isolated negative branch: an accepted illegal action must not
                // contaminate the subsequent normal prepared-copy lifecycle.
                val handAttempt=GameTestDriver();handAttempt.registerCards(MtgSetCatalog.all.flatMap{it.cards+it.basicLands});fillFixtureCards(handAttempt);handAttempt.replaceState(d.state)
                val handOffered=handAttempt.legalActions(p[0]).any{it.action is CastSpell&&(it.action as CastSpell).cardId==glass&&(it.action as CastSpell).faceIndex==0}
                val before=handAttempt.state;val direct=handAttempt.submit(CastSpell(p[0],glass,faceIndex=0));val directUnchanged=handAttempt.state==before
                a += "Prepare sorcery cannot be cast directly from hand" to (direct.error!=null&&directUnchanged&&!handOffered)
                o["directHandOffered"]=JsonPrimitive(handOffered);o["directHandCastError"]=JsonPrimitive(direct.error);o["directHandUnchanged"]=JsonPrimitive(directUnchanged)
                o["directHandStackView"]=Json.encodeToJsonElement(cardView(handAttempt,p[0],glass))
                if(direct.error==null) drain(handAttempt)
                o["directHandAfterResolution"]=snapshot(handAttempt)
                o["directHandTreasures"]=Json.encodeToJsonElement(handAttempt.getPermanents(p[0]).mapNotNull{cardView(handAttempt,p[0],it)}.filter{it.isToken})
            }
            ok(d.castSpell(p[0],glass));drain(d)
            val prepared=d.state.getEntity(glass)?.get<PreparedComponent>()
            val copies=d.getExile(p[0]).filter{d.state.getEntity(it)?.get<PreparedSpellCopyComponent>()?.sourceId==glass}
            val entered=glass in d.getPermanents(p[0])&&power(d,glass)==2&&toughness(d,glass)==2&&prepared!=null&&copies.size==1&&prepared.exileCopyId==copies.single()
            a += "Creature enters prepared with one associated exile copy" to entered
            o["beforeCopyCastOrRemoval"]=snapshot(d);o["copies"]=Json.encodeToJsonElement(copies);o["prepared"]=Json.encodeToJsonElement(prepared)
            check(entered){"Required prepared source/copy fixture not produced by real paid cast"}
            val copy=copies.single()
            if(removal) {
                while(d.priorityPlayer!=p[1])ok(d.passPriority(requireNotNull(d.priorityPlayer)))
                ok(d.castSpell(p[1],bolt!!,listOf(glass)));drain(d)
                a += "Real paid Bolt destroys the creature" to (grave(d,p[0],glass)&&grave(d,p[1],bolt))
                val offered=d.legalActions(requireNotNull(d.priorityPlayer)).any{it.action is CastSpell&&(it.action as CastSpell).cardId==copy}
                a += "Uncast associated copy ceases and is no longer castable" to (d.state.getEntity(copy)==null&&d.state.zones.values.none{copy in it}&&!offered)
            } else {
                val firstPaid=d.getLands(p[0]).count{d.isTapped(it)}
                ok(d.submit(CastSpell(p[0],copy,faceIndex=0)))
                a += "Paid sorcery on stack unprepares same creature" to (firstPaid==2&&copy in d.state.stack&&cardView(d,p[0],copy)?.name=="Craft with Pride"&&glass in d.getPermanents(p[0])&&d.state.getEntity(glass)?.get<PreparedComponent>()==null&&d.getLands(p[0]).count{d.isTapped(it)}==3)
                o["copyOnStack"]=snapshot(d);drain(d)
                val treasures=d.getPermanents(p[0]).mapNotNull{cardView(d,p[0],it)}.filter{it.isToken}
                val replay=d.submit(CastSpell(p[0],copy,faceIndex=0))
                a += "One Treasure, copy gone and cannot recast" to (treasures.size==1&&treasures.single().name=="Treasure"&&"ARTIFACT" in treasures.single().cardTypes&&d.state.getEntity(copy)==null&&d.state.zones.values.none{copy in it}&&replay.error!=null)
                o["treasures"]=Json.encodeToJsonElement(treasures);o["recastError"]=JsonPrimitive(replay.error)
            }
            o["final"]=snapshot(d)
        }
        for(count in listOf(2,4)) probe("supplemental_complete_${count}p") {a,o ->
            val d=GameTestDriver();d.registerCards(MtgSetCatalog.all.flatMap{it.cards+it.basicLands});fillFixtureCards(d)
            val p=d.initMultiplayer(List(count){Deck.of("Forest" to 30,"Grizzly Bears" to 30)},skipMulligans=false)
            val controller=java.util.concurrent.Executors.newSingleThreadExecutor()
            val trace=mutableListOf<JsonElement>();var casts=0;var attacks=0;var eliminationSeen=false;var continued=false
            val engineThread=Thread.currentThread().id
            fun external(allowedActors:Set<EntityId>,choose:()->GameAction):GameAction {
                // The policy executes on the other thread over captured legal
                // requests; it does not merely echo a preselected action.
                val response=controller.submit<Pair<Long,GameAction>>{Thread.currentThread().id to choose()}.get(10,java.util.concurrent.TimeUnit.SECONDS)
                val action=response.second;val actor=action.playerId
                check(response.first!=engineThread&&actor in allowedActors){"External response must retain an authenticated requested seat"}
                trace+=buildJsonObject{put("actor",actor.value);put("engineThread",engineThread);put("controllerThread",response.first);put("action",Json.encodeToJsonElement<GameAction>(action));put("turn",d.state.turnNumber);put("step",d.currentStep.name);put("alive",d.state.activePlayers.size);put("life",Json.encodeToJsonElement(p.map{d.getLifeTotal(it)}))}
                ok(d.submit(action));return action
            }
            try {
                for(id in p)external(setOf(id)){KeepHand(id)}
                for(step in 0 until 5000) {
                    if(d.state.gameOver)break
                    val q=d.pendingDecision
                    if(q!=null) {
                        external(setOf(q.playerId)) {
                            val response=when(q) {
                                is SelectCardsDecision -> CardsSelectedResponse(q.id,q.options.take(q.minSelections))
                                is YesNoDecision -> YesNoResponse(q.id,true)
                                else -> error("Unimplemented synthetic-deck choice $q")
                            }
                            SubmitDecision(q.playerId,response)
                        }
                        continue
                    }
                    val choices=d.state.activePlayers.flatMap{d.legalActions(it)}.filter{it.affordable}
                    val priority=d.priorityPlayer;val currentStep=d.currentStep
                    val action=external(choices.map{it.action.playerId}.toSet()) {
                        val selected=choices.firstOrNull{it.action is DeclareAttackers||it.action is DeclareBlockers}
                            ?:choices.firstOrNull{it.action is PlayLand&&it.action.playerId==priority}
                            ?:choices.firstOrNull{it.action is CastSpell&&it.action.playerId==priority}
                            ?:choices.firstOrNull{it.action is PassPriority&&it.action.playerId==priority}
                            ?:error("No supported native human action at $currentStep, priority $priority")
                        when(val offered=selected.action) {
                            is DeclareAttackers -> {
                                val target=selected.validAttackTargets?.firstOrNull()
                                val chosen=if(target==null)emptyMap()else selected.validAttackers.orEmpty().associateWith{target}
                                offered.copy(attackers=chosen)
                            }
                            else -> offered
                        }
                    }
                    if(action is CastSpell)casts++
                    if(action is DeclareAttackers)attacks+=action.attackers.size
                    if(eliminationSeen&&(action is PassPriority||action is CastSpell||action is PlayLand))continued=true
                    if(d.state.activePlayers.size in 2 until count)eliminationSeen=true
                }
                a += "Normal opening reaches natural single-winner terminal" to (d.state.gameOver&&d.state.winnerId!=null&&d.state.activePlayers.size==1)
                a += "Real creature casting and combat occurred with no forced concession" to (casts>0&&attacks>0&&trace.none{it.jsonObject["action"].toString().contains("Concede")})
                a += "Four-player game continues after first elimination when applicable" to (count==2||continued)
            } finally {
                controller.shutdownNow();check(controller.awaitTermination(5,java.util.concurrent.TimeUnit.SECONDS))
                o["final"]=snapshot(d);o["turn"]=JsonPrimitive(d.state.turnNumber);o["casts"]=JsonPrimitive(casts);o["attackAssignments"]=JsonPrimitive(attacks);o["continuedAfterElimination"]=JsonPrimitive(continued);o["decisions"]=JsonPrimitive(trace.size)
                o["deckScope"]=JsonPrimitive("Synthetic 30 Forest/30 Grizzly Bears per player; normal 20 life; not tournament-legal or owner-provided; separate actor-checked controller thread selects native legal actions/choices, not GUI")
                val file=File(File(requireNotNull(System.getenv("HEXPROOF_ARGENTUM_OUTPUT"))).parentFile,"complete-${count}p-trace.json")
                file.writeText(Json{prettyPrint=true}.encodeToString(JsonArray(trace)));o["trace"]=JsonPrimitive(file.name)
            }
        }
        val output = File(requireNotNull(System.getenv("HEXPROOF_ARGENTUM_OUTPUT")))
        output.parentFile.mkdirs()
        output.writeText(Json { prettyPrint = true }.encodeToString(JsonArray(rows)))
        println("HEXPROOF_OUTPUT " + output.absolutePath)
    }
})
