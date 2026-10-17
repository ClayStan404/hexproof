// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../../apps/client-qt/qml/components" as Components
import "../scenarios/ForgeBorosStudy.js" as Common
import "../scenarios/ForgeFormatStudy.js" as FormatStudy

TestCase {
    id: testCase
    name: "ForgeNativeTestPlayer"
    property var blockerSources: []

    QtObject {
        id: ws
        property var roomSession: ({seatIndex:0})
    }
    QtObject {
        id: cardCatalog
        function enrichLimitedCards(cards) { return cards }
    }
    QtObject {
        id: auditProbe
        function record(name, value) {}
    }
    QtObject {
        id: combatSession
        property string promptKind: "chooseBlockers"
        property var promptCombat: ({sourceItems:() => testCase.blockerSources})
        signal promptChanged()
        signal snapshotChanged()
    }
    QtObject {
        id: combatTableController
        property var rulesSession: combatSession
        property int localSeat: 0
        property var interaction: ({contextActive:true, canRespond:true, promptRevision:0})
    }
    Components.ForgeCombatInteraction {
        id: combat
        tableController: combatTableController
    }

    function init() {
        blockerSources = []
        combat.resetAssignments()
    }

    function card(id, seat, tapped) {
        // ForgeCardLane.CardSlot exposes card roles; category belongs to its lane.
        return {cardId:id, name:"Plains", controllerSeat:seat, tapped:tapped}
    }
    function lane(zone, cards, extra) {
        return Object.assign({visible:true, zone:zone, category:"land", visibleCards:cards,
            scrollArea:({}), children:[]}, extra || {})
    }
    function driverWithNestedLanes() {
        const ready = lane("battlefield", [card("ready-1", 0, false), card("ready-2", 0, false)])
        const spent = lane("battlefield", [card("spent", 0, true)])
        const opponent = lane("battlefield", [card("opponent", 1, false)])
        const hand = lane("hand", [card("hand", 0, false)], {objectName:"forgeHand", category:undefined})
        const graveyard = lane("graveyard", [card("graveyard", 0, false)])
        const hidden = {visible:false, children:[lane("battlefield", [card("stale", 0, false)])]}
        return {table:{presentation:{children:[{children:[{children:[ready, spent, opponent]}]}, hand, graveyard, hidden]}}}
    }

    function test_nestedLanesCountEveryReadyPhysicalLand() {
        const driver = driverWithNestedLanes()
        compare(Common.laneItems(driver).length, 3)
        compare(Common.lanes(driver).map(c => c.cardId), ["ready-1", "ready-2", "spent", "opponent"])
        compare(Common.lanes(driver).map(c => c.category), ["land", "land", "land", "land"])
        compare(Common.basicMana(driver, 0), 2)
        compare(Common.basicMana(driver, 1), 1)
        compare(Common.laneItems(driver, true).find(c => c.objectName === "forgeHand").visibleCards[0].cardId, "hand")
    }

    function test_formatPlayerAttemptsAnAffordableSpell_data() {
        return [{tag:"affordable", cost:2, casts:1}, {tag:"unaffordable", cost:3, casts:0}]
    }
    function test_formatPlayerAttemptsAnAffordableSpell(data) {
        const driver = driverWithNestedLanes(), actions = [], passed = []
        driver.maximumTax = 0
        driver.casts = 0
        driver.session = {gameId:data.tag, turn:1,
            cardForInspection:id => ({cardId:id, name:data.tag, manaValue:data.cost,
                manaCost:"{W}{W}", typeLine:"Creature", zone:"hand"}),
            stackObjectIds:() => []}
        driver.cardAction = option => { actions.push(option.responseId); return true }
        driver.click = name => { passed.push(name); return true }
        FormatStudy.chooseAction(driver, [{responseId:"cast", kind:"cast", cardId:"spell"},
            {responseId:"$pass", kind:"pass", cardId:""}])
        compare(driver.casts, data.casts)
        compare(actions, data.casts ? ["cast"] : [])
        compare(passed, data.casts ? [] : ["rulesPromptOption-$pass"])
    }

    function blockingDriver(promptId, singleTarget, ambiguousPile) {
        const knight = {responseId:"target-knight", objectId:"knight", kind:"creature", maxAssignments:2}
        const buried = {responseId:"target-buried", objectId:"buried", kind:"creature", maxAssignments:2}
        const front = {responseId:"target-front", objectId:"front", kind:"creature", maxAssignments:2}
        blockerSources = [{responseId:"source-one", objectId:"one", maxAssignments:1,
            validTargets:singleTarget ? [buried] : [knight, buried, front]}]
        if (!singleTarget) blockerSources = blockerSources.concat([{responseId:"source-two", objectId:"two",
            maxAssignments:1, validTargets:[knight, buried, front]}])
        combatTableController.interaction = {contextActive:true, canRespond:true,
            promptRevision:combatTableController.interaction.promptRevision + 1}
        const buriedCard = {cardId:"buried", stackIndex:1, stackSize:2, stackFront:false, fanned:false}
        const frontCard = {cardId:"front", stackIndex:1, stackSize:2, stackFront:true, fanned:false,
            stackChoice:() => ambiguousPile ? ({id:"", fan:true}) : ({id:"front", fan:false}),
            stackActivateId:() => ambiguousPile ? "buried" : "front"}
        const driver = {blocks:0, capturedCombat:false, inputs:[], captures:[],
            table:{combatInteraction:combat, presentation:{children:[lane("battlefield", [
                {cardId:"one", stackSize:1}, {cardId:"two", stackSize:1},
                {cardId:"knight", stackSize:1}, buriedCard, frontCard], {category:"creature"})]}},
            session:{promptId:promptId, promptCombat:combatSession.promptCombat,
                cardForInspection:id => ({cardId:id, power:3, toughness:2, rulesText:""})}}
        driver.require = (ok, message) => { if (!ok) throw new Error(message) }
        driver.combatInputId = id => Common.combatInputId(driver, id)
        driver.click = name => {
            driver.inputs.push(name)
            if (name === "forgeCardStackCount-front") {
                buriedCard.fanned = true
                frontCard.fanned = true
                return true
            }
            if (name.startsWith("forgeCard-")) {
                const id = name.slice("forgeCard-".length)
                driver.require(id !== "buried" || buriedCard.fanned,
                    "The covered delegate must be exposed through its pile control")
                return combat.activate(id)
            }
            driver.require(name === "rulesConfirmCombat-blockers", "Unexpected native control")
            driver.require(!combat.selectedSource && !combat.pendingAttacker,
                "Cannot confirm a pending blocker selection")
            return true
        }
        driver.clickCombatSource = (source, id) => driver.click("forgeCard-" + id)
        driver.wheelToCard = (id, actions) => { throw new Error("Unexpected scroll: " + id) }
        driver.capture = name => driver.captures.push(name)
        return driver
    }

    function test_blockPlanFansBuriedAttackerBeforeConfirming_data() {
        return [{tag:"interchangeable", prompt:101, ambiguous:false},
            {tag:"distinct-members", prompt:102, ambiguous:true}]
    }
    function test_blockPlanFansBuriedAttackerBeforeConfirming(data) {
        const driver = blockingDriver(data.prompt, false, data.ambiguous)
        compare(Common.combatInputId(driver, "buried"), "")
        FormatStudy.chooseBlockers(driver)
        compare(combat.selectedSource, "source-one")
        FormatStudy.chooseBlockers(driver)
        compare(combat.selectedTargets("source-one"), ["target-knight"])
        FormatStudy.chooseBlockers(driver)
        compare(combat.selectedSource, "source-two")
        FormatStudy.chooseBlockers(driver)
        compare(driver.inputs[driver.inputs.length - 1], "forgeCardStackCount-front")
        compare(combat.selectedSource, "source-two")
        compare(Common.combatInputId(driver, "buried"), "buried")
        FormatStudy.chooseBlockers(driver)
        compare(combat.selectedTargets("source-two"), ["target-buried"])
        compare(combat.selectedSource, "")
        FormatStudy.chooseBlockers(driver)
        compare(driver.inputs, ["forgeCard-one", "forgeCard-knight", "forgeCard-two",
            "forgeCardStackCount-front", "forgeCard-buried", "rulesConfirmCombat-blockers"])
        compare(driver.blocks, 2)
    }

    function test_singleTargetBlockIsCountedAfterItsOneClick() {
        const driver = blockingDriver(103, true, false)
        FormatStudy.chooseBlockers(driver)
        compare(combat.selectedTargets("source-one"), ["target-buried"])
        compare(combat.selectedSource, "")
        compare(driver.blocks, 1)
        FormatStudy.chooseBlockers(driver)
        compare(driver.inputs, ["forgeCard-one", "rulesConfirmCombat-blockers"])
    }
}
