// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"
import "../../qml/screens"
import "../../../../tools/ui-automation/scenarios/ForgeNecrodominanceStudy.js" as NecroStudy

// Animation lifecycles, pending responses and queued mana payments.
ForgeDuelTestCase {
    id: testCase
    name: "ForgeDuelMotionPayment"

    function test_edhManaHintsStayInsideLandLane_data() {
        return [{tag:"payment-single", undo:false, lands:1}, {tag:"payment-two", undo:false, lands:2},
            {tag:"payment-three", undo:false, lands:3}, {tag:"undo-single", undo:true, lands:1},
            {tag:"undo-two", undo:true, lands:2}, {tag:"undo-three", undo:true, lands:3}]
    }
    function test_edhManaHintsStayInsideLandLane(data) {
        window.width = 1920; window.height = 1011
        room.format = "edh"; room.deckFormat = "commander"; room.maxSeats = 4
        const state = edhSnapshot([0, 1, 2, 3], 0, 1)
        for (const zone of state.zones.filter(zone => zone.zone === "battlefield")) {
            zone.cards = zone.cards.filter(row => row.power)
            for (let i = 0; i < data.lands; ++i)
                zone.cards.push(Object.assign(card("hint-land-" + zone.ownerSeat + "-" + i,
                    zone.ownerSeat, "Plains", false), {tapped:data.undo}))
            zone.count = zone.cards.length
        }
        verify(testRulesPrompt.applySnapshot(state))
        const options = []
        for (let i = 0; i < data.lands; ++i)
            options.push({responseId:"hint-action-" + i, cardId:"hint-land-0-" + i,
                kind:data.undo ? "undoMana" : "activateAbility", label:data.undo ? "Undo mana" : "Add mana"})
        prompt(data.undo ? "chooseAction" : "payManaCost", {options:options})
        const lane = item("forgeLands-0")
        tryCompare(lane, "stackCount", 1)
        compare(lane.scrollArea.clip, true)
        const front = lane.visibleCards.find(slot => slot.stackFront)
        compare(front.stackSize, data.lands)
        const hint = findChild(front, "forgeCardInteractionHint-" + front.cardId).parent
        verify(hint.visible)
        verify(waitForPolish(window))
        const rect = hint.mapToItem(lane.scrollArea, 0, 0, hint.width, hint.height)
        verify(rect.x >= -0.1 && rect.y >= -0.1
            && rect.x + rect.width <= lane.scrollArea.width + 0.1
            && rect.y + rect.height <= lane.scrollArea.height + 0.1,
            "Complete mana hint must stay in the clipped EDH land lane: " + JSON.stringify(rect)
            + ", viewport " + lane.scrollArea.width + "x" + lane.scrollArea.height)
    }

    function test_tappingDoesNotMoveAnotherPermanent() {
        const state = snapshot(1, 0)
        const bear = card("bear", 0, "Grizzly Bears", true)
        state.zones[4].cards = [card("land-a", 0, "Plains", false), card("land-b", 0, "Plains", false), bear]
        state.zones[4].count = 3
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        const bearFace = item("forgeCard-bear")
        const before = bearFace.mapToItem(table.presentation, 0, 0)
        const sizeBefore = Qt.size(bearFace.width, bearFace.height)
        const tapped = snapshot(1, 0)
        const tappedLand = card("land-b", 0, "Plains", false)
        tappedLand.tapped = true
        tapped.zones[4].cards = [card("land-a", 0, "Plains", false), tappedLand, card("bear", 0, "Grizzly Bears", true)]
        tapped.zones[4].count = 3
        verify(testRulesPrompt.applySnapshot(tapped))
        waitForRendering(table)
        tryVerify(() => item("forgeOwnLands").stackCount === 2)
        const after = item("forgeCard-bear").mapToItem(table.presentation, 0, 0)
        compare(Math.round(after.x), Math.round(before.x))
        compare(Math.round(after.y), Math.round(before.y))
        fuzzyCompare(bearFace.width, sizeBefore.width, 0.1,
            "Tapping a land cannot resize another permanent")
        fuzzyCompare(bearFace.height, sizeBefore.height, 0.1)
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        const restored = bearFace.mapToItem(table.presentation, 0, 0)
        compare(Math.round(restored.x), Math.round(before.x))
        compare(Math.round(restored.y), Math.round(before.y))
        fuzzyCompare(bearFace.width, sizeBefore.width, 0.1)
        fuzzyCompare(bearFace.height, sizeBefore.height, 0.1)
    }
    function test_mixedSupportTapKeepsCreatureBodyStill_data() {
        return [{tag:"near-side", nearSide:true}, {tag:"far-side", nearSide:false}]
    }
    function test_mixedSupportTapKeepsCreatureBodyStill(data) {
        catalog.typeOverrides = {"Sol Ring":"Artifact"}
        const state = snapshot(1, 1)
        state.zones[4].cards = [card("mixed-bear", 0, "Grizzly Bears", true),
            card("mixed-land-a", 0, "Plains", false), card("mixed-land-b", 0, "Plains", false),
            card("mixed-relic", 0, "Sol Ring", false)]
        state.zones[4].count = state.zones[4].cards.length
        verify(testRulesPrompt.applySnapshot(state))
        const field = createTemporaryObject(mixedSupportField, window.contentItem,
            {nearSide:data.nearSide})
        verify(field !== null)
        tryCompare(field.lands, "stackCount", 1)
        tryCompare(field.others, "stackCount", 1)
        verify(waitForPolish(window))
        const body = findChild(field.creatures.itemFor("mixed-bear"), "forgeCardFace-mixed-bear")
        verify(body !== null)
        const before = body.mapToItem(field, 0, 0, body.width, body.height)
        verify(before.width >= 80, "The compact mixed-support probe starts with a readable creature")
        for (const tapped of [true, false]) {
            const next = JSON.parse(JSON.stringify(state))
            next.zones[4].cards.find(card => card.id === "mixed-land-b").tapped = tapped
            verify(testRulesPrompt.applySnapshot(next))
            tryCompare(field.lands, "stackCount", tapped ? 2 : 1)
            verify(waitForPolish(window))
            const after = body.mapToItem(field, 0, 0, body.width, body.height)
            for (const key of ["x", "y", "width", "height"])
                fuzzyCompare(after[key], before[key], 0.1,
                    "Changing a support pile cannot change the unrelated creature body "
                    + key + ": " + JSON.stringify(before) + " -> " + JSON.stringify(after))
        }
    }
    function test_unusedManaUndoesFromTheLand_data() {
        return [{tag:"floating-before-cast", kind:"chooseAction"},
            {tag:"unfinished-payment", kind:"payManaCost"}]
    }
    function test_unusedManaUndoesFromTheLand(data) {
        testTranslations.setLanguage("zh")
        const state = landBoard(["land-a", "land-b"], ["land-a"])
        state.players[0].manaPool = [{name:"W", value:1}]
        verify(testRulesPrompt.applySnapshot(state))
        prompt(data.kind, {title:"Choose",
            options:[{responseId:"action:0", cardId:"land-b", kind:"activateAbility", label:"Plains — Tap for mana"},
                     {responseId:"action:1", cardId:"land-a", kind:"undoMana", label:"Undo mana"}]})
        const source = item("forgeCard-land-a")
        compare(item("forgeCardInteractionHint-land-a").text, "撤回法术力")
        verify(source.undoingMana && source.offeredUndo)
        compare(findChild(source, "forgeCardStateOutline-" + source.objectId).border.color, "#7ebcca")
        compare(findChild(table, "rulesPromptOption-action:1"), null, "An option on the table gets no dock button")
        mouseClick(source)
        compare(transport.responses.length, 1)
        compare(transport.responses[0].response, "action:1")
        verify(source.card.tapped, "A response never locally untaps the source")
        compare(item("forgeMana-0-W").modelData.amount, 1, "Only the engine snapshot can refund mana")
        verify(source.waiting && !source.undoingMana && source.offeredUndo)
        compare(findChild(source, "forgeCardStateOutline-" + source.objectId).border.color, Theme.withAlpha("#7ebcca", 0.5))
        mouseClick(source)
        compare(transport.responses.length, 1, "A pending undo cannot be submitted twice")
    }
    function test_floatingManaPressCannotAnswerTheNextUndoPrompt() {
        landBoard(["land-a"])
        prompt("chooseAction", {options:[
            {responseId:"activate-a", kind:"activateAbility", cardId:"land-a", label:"Add {W}"}]})
        const source = item("forgeCard-land-a")
        mouseClick(source)
        compare(transport.responses.length, 1)
        mousePress(source)
        const state = landBoard(["land-a"], ["land-a"])
        state.players[0].manaPool = [{name:"W", value:1}]
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[
            {responseId:"undo-a", kind:"undoMana", cardId:"land-a", label:"Undo mana"}]})
        mouseRelease(source)
        compare(transport.responses.length, 1, "An in-flight activation gesture cannot turn into an undo")
        compare(table.interaction.paymentQueue, [], "Priority undo never enters the payment click queue")
        mouseClick(source)
        compare(transport.responses.length, 2)
        compare(transport.responses[1].response, "undo-a")
    }
    function test_priorityManaClickDoesNotQueueAnotherSource() {
        prompt("chooseAction", {options:[
            {responseId:"activate-land", kind:"activateAbility", cardId:"land", label:"Add {W}"},
            {responseId:"activate-creature", kind:"activateAbility", cardId:"own-0", label:"Add {G}"}]})
        mouseClick(item("forgeCard-land"))
        compare(transport.responses.length, 1)
        mouseClick(item("forgeCard-own-0"))
        compare(transport.responses.length, 1, "Priority has no queued mana activations")
        compare(table.interaction.paymentQueue, [])
        verify(item("forgeWaitingCue").visible)
    }
    function test_floatingManaUndoWithAnotherAbilityNeedsAChoice() {
        landBoard(["land-a"], ["land-a"])
        prompt("chooseAction", {options:[
            {responseId:"other-a", kind:"activateAbility", cardId:"land-a", label:"Another ability"},
            {responseId:"undo-a", kind:"undoMana", cardId:"land-a", label:"Undo mana"}]})
        mouseClick(item("forgeCard-land-a"))
        compare(transport.responses.length, 0, "Undo must not silently replace another legal action")
        tryCompare(table.cardActionPicker, "opened", true)
        mouseClick(item("rulesCardAction-undo-a"))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].response, "undo-a")
    }
    function test_floatingManaUndoDisappearsWithItsDecision() {
        landBoard(["land-a"], ["land-a"])
        const options = [{responseId:"undo-a", kind:"undoMana", cardId:"land-a", label:"Undo mana"}]
        prompt("chooseAction", {options:options})
        const source = item("forgeCard-land-a")
        verify(source.undoingMana)
        prompt("chooseAction", {options:[]})
        verify(!source.undoingMana && !source.offeredUndo)
        mouseClick(source)
        compare(transport.responses.length, 0, "A revoked source cannot submit its previous undo")
        room.role = "spectator"; room.seatIndex = -1
        prompt("chooseAction", {options:options})
        verify(!source.undoingMana && !source.offeredUndo && !source.actionable)
        mouseClick(source)
        compare(transport.responses.length, 0, "Spectators cannot undo another player's source")
    }
    function test_necroNativeHelperMatchesSourceLessLifePayment() {
        const state = snapshot()
        state.step = "end"
        state.zones[4].cards[0].identity.name = "Necrodominance"
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseNumber", {title:"Choose X for Necrodominance", minNumber:0, maxNumber:20})
        compare(table.rulesSession.promptContextCards.items().length, 0)
        verify(NecroStudy.lifePaymentPromptMatches(table.rulesSession, "wait-trigger", "own-0"))
        verify(NecroStudy.lifePaymentPromptMatches(table.rulesSession, "number-input", "own-0"))
        verify(!NecroStudy.lifePaymentPromptMatches(table.rulesSession, "play-necro", "own-0"))
        verify(!NecroStudy.lifePaymentPromptMatches(table.rulesSession, "wait-trigger", "hand-0"))
        prompt("chooseNumber", {title:"Choose X for another spell", minNumber:0, maxNumber:20})
        verify(!NecroStudy.lifePaymentPromptMatches(table.rulesSession, "wait-trigger", "own-0"))
    }
    function test_necroNativeHelperConfirmsSourceLessLifePayment() {
        const state = snapshot()
        state.step = "end"
        state.zones[4].cards[0].identity.name = "Necrodominance"
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseBoolean", {title:"Confirm decision", detail:"Do you want to pay 10 life?",
            minChoiceTotal:1, maxChoiceTotal:1,
            choices:[{responseId:"choice:0", label:"No", weight:1, canRepeat:false},
                {responseId:"choice:1", label:"Yes", weight:1, canRepeat:false}]})
        compare(table.rulesSession.promptContextCards.items().length, 0)
        verify(NecroStudy.lifePaymentConfirmationMatches(table.rulesSession, "wait-draw", "own-0", 10))
        verify(!NecroStudy.lifePaymentConfirmationMatches(table.rulesSession, "wait-trigger", "own-0", 10))
        verify(!NecroStudy.lifePaymentConfirmationMatches(table.rulesSession, "wait-draw", "hand-0", 10))
        verify(!NecroStudy.lifePaymentConfirmationMatches(table.rulesSession, "wait-draw", "own-0", 5))
        const driver = {table:table, session:table.rulesSession,
            require:(ok, message) => verify(ok, message), item:name => findChild(table, name),
            click:name => { mouseClick(item(name)); return true }}
        NecroStudy.confirmLifePayment(driver, "wait-draw", "own-0", 10)
        compare(transport.responses, [{id:table.rulesSession.promptId, choices:["choice:1"]}])
    }
    function test_newPermanentFadesInWhenMotionIsOn() {
        Theme.motionEnabled = true
        const state = snapshot(1, 0)
        state.zones[4].cards.push(card("newcomer", 0, "Grizzly Bears", true))
        state.zones[4].count = state.zones[4].cards.length
        verify(testRulesPrompt.applySnapshot(state))
        let sawFade = false
        tryVerify(() => {
            const face = findChild(table, "forgeCard-newcomer")
            if (!face)
                return false
            if (face.arrivalOpacity < 1)
                sawFade = true
            return sawFade && face.arrivalOpacity === 1
        })
        Theme.motionEnabled = false
    }
    function test_keyboardPilePreviewFollowsFanAndCollapseGlides_data() {
        return [{tag:"expanded", collapse:false}, {tag:"collapsed", collapse:true}]
    }
    function test_keyboardPilePreviewFollowsFanAndCollapseGlides(data) {
        window.width = 1920; window.height = 1011
        landBoard(["ready", "spent-a", "spent-b"], ["spent-a", "spent-b"])
        table.priority.setFullControl(true)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        const lane = item("forgeOwnLands"), source = item("forgeCard-spent-b")
        const slot = source.parent, preview = item("rulesCardHoverPreview")
        tryCompare(lane, "stackCount", 2)
        verify(source.card.stackFront && source.card.stackSize === 2 && source.card.tapped)
        // Let resize suppression expire, then exercise the real CardSlot
        // Translate animation without snapping it to its destination.
        wait(300)
        Theme.motionEnabled = true
        mouseMove(item("forgeGameMenu"))
        source.forceActiveFocus()
        tryCompare(source, "activeFocus", true)
        tryCompare(table.inspector, "previewCardId", "spent-b")
        tryCompare(preview, "visible", true)
        tryCompare(preview, "opacity", 1)
        const closed = source.mapToItem(preview.parent, 0, 0, source.width, source.height)
        function distanceToSource(bounds) {
            return Math.max(0, preview.x - bounds.x - bounds.width, bounds.x - preview.x - preview.width)
                + Math.max(0, preview.y - bounds.y - bounds.height, bounds.y - preview.y - preview.height)
        }
        verify(preview.placement.faceWidth >= Theme.size(180), "The closed pile has a readable art pocket")
        const closedDistance = distanceToSource(closed)
        verify(closedDistance <= Theme.size(60), "The initial readable pocket is near the pile")
        keyClick(Qt.Key_Return)
        compare(lane.fannedStack, source.card.stackIndex)
        verify(Math.abs(slot.visualDx) + Math.abs(slot.visualDy) > 1,
            "Opening must exercise a painted glide, not an instantaneous layout")
        tryCompare(slot, "visualDx", 0)
        tryCompare(slot, "visualDy", 0)
        const expanded = source.mapToItem(preview.parent, 0, 0, source.width, source.height)
        verify(Math.abs(expanded.x - closed.x) > source.width / 2, "The focused member actually moves in the fan")
        if (data.collapse) {
            keyClick(Qt.Key_Escape)
            compare(lane.fannedStack, -1)
            verify(Math.abs(slot.visualDx) + Math.abs(slot.visualDy) > 1,
                "Closing must also exercise the production glide")
            tryCompare(slot, "visualDx", 0)
            tryCompare(slot, "visualDy", 0)
        }
        verify(source.activeFocus)
        compare(table.inspector.previewCardId, "spent-b")
        const origin = source.mapToItem(preview.parent, 0, 0)
        const bounds = source.mapToItem(preview.parent, 0, 0, source.width, source.height)
        tryVerify(() => Math.abs(preview.sourceGeometry.origin.x - origin.x) < 0.5
            && Math.abs(preview.sourceGeometry.origin.y - origin.y) < 0.5
            && Math.abs(preview.sourceGeometry.bounds.x - bounds.x) < 0.5
            && Math.abs(preview.sourceGeometry.bounds.y - bounds.y) < 0.5
            && Math.abs(preview.sourceGeometry.bounds.width - bounds.width) < 0.5
            && Math.abs(preview.sourceGeometry.bounds.height - bounds.height) < 0.5,
            1000, "Preview geometry must match the settled painted source after " + data.tag
                + "; painted=" + JSON.stringify(bounds) + "; cached=" + JSON.stringify(preview.sourceGeometry.bounds))
        if (data.collapse) {
            verify(Math.abs(bounds.x - closed.x) < 0.5 && Math.abs(bounds.y - closed.y) < 0.5)
            tryVerify(() => preview.placement.faceWidth >= Theme.size(180)
                && distanceToSource(bounds) <= closedDistance + Theme.size(1), 1000,
                "Collapsing restores the same nearby readable preview pocket")
        }
        compare(transport.responses.length, 0, "Inspecting a pile must never answer the Forge prompt")
    }
    function test_decisionDockContractionEasesWhenMotionIsOn() {
        wait(300)
        Theme.motionEnabled = true
        verify(testRulesPrompt.applySnapshot(snapshot()))
        const dock = item("rulesDecisionDock")
        prompt("chooseFromSelection", {title:"Choose a mode", detail:"A taller choice",
            minChoiceTotal:1, maxChoiceTotal:1,
            choices:[0, 1, 2, 3, 4, 5].map(i => ({responseId:"choice:" + i, label:"Mode " + i,
                weight:1, canRepeat:false}))})
        tryVerify(() => Math.abs(dock.height - dock.targetHeight) < 1)
        const before = dock.height
        action("playLand", "hand-0")
        const cap = table.presentation.boardDecision && table.presentation.reservesDock
            ? table.presentation.boardDecisionHeight : table.height - 24 * table.presentation.unit
        const target = Math.min(dock.implicitHeight, cap)
        verify(before - target > 8,
               "expected the dock to shrink, before " + before + " target " + target)
        verify(Math.abs(dock.height - before) + 1 < Math.abs(target - before),
               "Dock height eases from " + before + " toward " + target + ", now " + dock.height)
        tryVerify(() => Math.abs(dock.height - Math.min(dock.implicitHeight, cap)) < 1)
        Theme.motionEnabled = false
    }
    function test_handHoverFollowsMotionSwitch() {
        const slot = item("forgeHandCard-hand-0"), face = item("forgeHandSurface-hand-0")
        const lift = -18 * table.presentation.unit
        mouseMove(slot, slot.width / 2, slot.height / 2)
        compare(face.y, lift, "Disabled motion applies the hover lift immediately")
        mouseMove(slot, -10, -10)
        compare(face.y, 0)
        Theme.motionEnabled = true
        mouseMove(slot, slot.width / 2, slot.height / 2)
        verify(face.y > lift, "Enabled motion animates the hover lift")
        tryCompare(face, "y", lift)
    }

    function test_pendingPaymentKeepsManaColor() {
        prompt("payManaCost", {title:"Pay Mana Cost: {W}",
            options:[{responseId:"pay", kind:"activateAbility", cardId:"land", label:"Plains"},
                {responseId:"$cancel", kind:"cancel", label:"Cancel"}]})
        const land = item("forgeCard-land")
        const outline = findChild(land, "forgeCardStateOutline-land")
        compare(outline.border.color, "#e1bd7f")
        mouseClick(land)
        compare(transport.responses.length, 1)
        compare(outline.border.color, Theme.withAlpha("#e1bd7f", 0.5))
    }
    function test_tappedCardDimsTheArtAndShowsAMark() {
        const state = snapshot(1, 0)
        const bear = card("land", 0, "Grizzly Bears", true)
        bear.tapped = true
        state.zones[4].cards = [bear]
        state.zones[4].count = 1
        verify(testRulesPrompt.applySnapshot(state))
        const tapped = item("forgeCard-land")
        compare(tapped.rotation, 0)
        compare(item("forgeCardTappedShade-land").opacity, tapped.tappedShade)
        const mark = item("forgeCardTappedMark-land")
        verify(mark.visible)
        const face = item("forgeCardFace-land")
        verify(mark.width >= Math.min(face.width, face.height) * 0.5)
        verify(item("forgeCardStats-land").visible)
        bear.tapped = false
        verify(testRulesPrompt.applySnapshot(state))
        verify(!item("forgeCardTappedShade-land").visible)
        verify(!item("forgeCardTappedMark-land").visible)
    }
    function test_tappedPileUndoesTheSpentLand_data() {
        return [{tag:"floating-before-cast", kind:"chooseAction"},
            {tag:"unfinished-payment", kind:"payManaCost"}]
    }
    function test_tappedPileUndoesTheSpentLand(data) {
        const state = snapshot(1, 0)
        const spent = card("land-a", 0, "Plains", false)
        spent.tapped = true
        state.zones[4].cards = [spent, card("land-b", 0, "Plains", false)]
        state.zones[4].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        prompt(data.kind, {title:"Choose", options:[
            {responseId:"pay-b", kind:"activateAbility", cardId:"land-b", label:"Plains"},
            {responseId:"undo-a", kind:"undoMana", cardId:"land-a", label:"Undo"}]})
        tryCompare(item("forgeOwnLands"), "stackCount", 2)
        const ready = item("forgeCard-land-b"), tapped = item("forgeCard-land-a")
        verify(tapped.card.stackIndex > ready.card.stackIndex, "Spent copies follow the ready pile")
        compare(tapped.card.stackSize, 1)
        mouseClick(tapped)
        compare(transport.responses[0].response, "undo-a")
    }
    function test_closedTappedPileShowsItsBuriedManaUndo_data() {
        return [{tag:"floating-before-cast", kind:"chooseAction"},
            {tag:"unfinished-payment", kind:"payManaCost"}]
    }
    function test_closedTappedPileShowsItsBuriedManaUndo(data) {
        landBoard(["land-a", "land-b"], ["land-a", "land-b"])
        prompt(data.kind, {options:[
            {responseId:"undo-a", kind:"undoMana", cardId:"land-a", label:"Undo mana"}]})
        const lane = item("forgeOwnLands"), front = item("forgeCard-land-b")
        tryCompare(lane, "stackCount", 1)
        verify(front.card.stackFront && !item("forgeCard-land-a").card.stackFront)
        const position = front.mapToItem(lane, 0, 0)
        verify(front.undoingMana && front.actionable, "A buried legal source remains discoverable on the closed pile")
        compare(item("forgeCardInteractionHint-land-b").text, "Undo mana")
        verify(!item("forgeCardInteractionHint-land-a").visible, "The pile has only one visible hint")
        mouseClick(front)
        compare(transport.responses, [{id:serial, response:"undo-a"}])
        verify(front.waiting && front.submitted)
        compare(front.mapToItem(lane, 0, 0), position, "An undo offer/response never moves the pile")
    }
    function test_pendingManaPressDoesNotBecomeTheNextPromptsUndo() {
        landBoard(["land-a"])
        manaPrompt("sa:10", [
            {responseId:"pay-a", kind:"activateAbility", cardId:"land-a", label:"Plains"}])
        const source = item("forgeCard-land-a")
        mouseClick(source)
        compare(transport.responses.length, 1)
        for (let i = 0; i < 12; ++i)
            mouseClick(source)
        compare(transport.responses.length, 1, "Repeating an in-flight source never sends or queues it")
        compare(table.interaction.paymentQueue, [])
        mousePress(source)
        manaPrompt("sa:10", [
            {responseId:"undo-a", kind:"undoMana", cardId:"land-a", label:"Undo mana"}])
        mouseRelease(source)
        compare(transport.responses.length, 1, "A press during the previous decision cannot answer the new one")
        mouseClick(source)
        compare(transport.responses.length, 2, "An intentional click on the new undo offer remains available")
        compare(transport.responses[1].response, "undo-a")
    }
    function test_sameDecisionManaPressStillQueuesAndRemovesTheSource() {
        const options = forestAndIsland()
        manaPrompt("sa:10", options)
        mouseClick(item("forgeCard-land-a"))
        const queued = item("forgeCard-land-b")
        mousePress(queued)
        republish("payManaCost", {title:"Pay Mana Cost: {G}", paymentId:"sa:10", options:options})
        mouseRelease(queued)
        compare(table.interaction.paymentQueue, ["land-b"], "An identical prompt republication preserves a waiting gesture")
        compare(transport.responses.length, 1)
        mouseClick(queued)
        compare(table.interaction.paymentQueue, [], "A fresh second click still removes the queued source")
        compare(transport.responses.length, 1)
    }
    function test_pendingQueuedManaPressCannotAnswerAChangedPayment() {
        const options = forestAndIsland()
        manaPrompt("sa:10", options)
        mouseClick(item("forgeCard-land-a"))
        const queued = item("forgeCard-land-b")
        mousePress(queued)
        manaPrompt("sa:11", [{responseId:"new-pay-b", kind:"activateAbility", cardId:"land-b", label:"Island"}])
        mouseRelease(queued)
        compare(table.interaction.paymentQueue, [])
        compare(transport.responses.length, 1, "A pending press cannot silently activate a different payment")
        mouseClick(queued)
        compare(transport.responses.length, 2)
        compare(transport.responses[1].response, "new-pay-b")
    }
    function test_paymentQueueSubmitsTheNextStepOfTheSameSpell() {
        const state = snapshot(1, 0)
        state.zones[4].cards = [card("land-a", 0, "Forest", false), card("land-b", 0, "Island", false)]
        state.zones[4].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        manaPrompt("sa:10", [
            {responseId:"pay-a", kind:"activateAbility", cardId:"land-a", label:"Forest"},
            {responseId:"pay-b", kind:"activateAbility", cardId:"land-b", label:"Island"}])
        mouseClick(item("forgeCard-land-a"))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].response, "pay-a")
        mouseClick(item("forgeCard-land-b"))
        compare(transport.responses.length, 1, "A queued land is not sent yet")
        compare(item("forgeCardPaymentQueue-land-b").text, "1")
        mouseClick(item("forgeCard-land-b"))
        verify(findChild(table, "forgeCardPaymentQueue-land-b") === null)
        mouseClick(item("forgeCard-land-b"))
        compare(item("forgeCardPaymentQueue-land-b").text, "1")
        manaPrompt("sa:10", [
            {responseId:"pay-b2", kind:"activateAbility", cardId:"land-b", label:"Island"}])
        compare(transport.responses.length, 2)
        compare(transport.responses[1].response, "pay-b2")
        compare(table.rulesSession.promptPaymentId, "sa:10")
    }
    function test_paymentQueueClearsWhenTheSpellChanges() {
        const state = snapshot(1, 0)
        state.zones[4].cards = [card("land-a", 0, "Forest", false), card("land-b", 0, "Island", false)]
        state.zones[4].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        manaPrompt("sa:10", [
            {responseId:"pay-a", kind:"activateAbility", cardId:"land-a", label:"Forest"},
            {responseId:"pay-b", kind:"activateAbility", cardId:"land-b", label:"Island"}])
        mouseClick(item("forgeCard-land-a"))
        mouseClick(item("forgeCard-land-b"))
        manaPrompt("sa:11", [
            {responseId:"pay-b2", kind:"activateAbility", cardId:"land-b", label:"Island"}])
        compare(transport.responses.length, 1)
        compare(item("forgeWaitingCueText").text, "Queued mana was cleared")
        verify(item("forgeWaitingCue").visible)
    }
    function test_sacrificialManaColorChoiceInterruptsQueuedPayment_data() {
        return [{tag:"english", language:"en", label:"Blue"},
                {tag:"chinese", language:"zh", label:"蓝色"}]
    }
    function test_sacrificialManaColorChoiceInterruptsQueuedPayment(data) {
        testTranslations.setLanguage(data.language)
        catalog.typeOverrides = ({"Lotus Bloom":"Artifact"})
        const state = snapshot(1, 0)
        const lotus = card("lotus", 0, "Lotus Bloom", false)
        state.zones[4].cards = [lotus, card("land", 0, "Plains", false)]
        state.zones[4].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        manaPrompt("sa:50", [
            {responseId:"activate-lotus", kind:"activateAbility", cardId:"lotus", label:"Lotus Bloom"},
            {responseId:"activate-plains", kind:"activateAbility", cardId:"land", label:"Plains"}])
        mouseClick(item("forgeCard-lotus"))
        const initialId = table.rulesSession.promptId
        compare(transport.responses, [{id:initialId, response:"activate-lotus"}])
        verify(transport.rulesResponsePending)
        mouseClick(item("forgeCard-land"))
        compare(table.interaction.paymentQueue, ["land"])

        const dock = item("rulesDecisionDock")
        dock.collapsed = true
        prompt("chooseBoolean", {title:"Confirm decision", detail:"Sacrifice Lotus Bloom?",
            minChoiceTotal:1, maxChoiceTotal:1,
            choices:[{responseId:"choice:0", label:"No", weight:1, canRepeat:false},
                     {responseId:"choice:1", label:"Yes", weight:1, canRepeat:false}]})
        verify(!dock.collapsed && dock.showsBody, "The nested choice reopens the decision dock")
        compare(table.interaction.paymentQueue, [], "A queued source cannot answer a sacrifice decision")
        verify(!transport.rulesResponsePending)
        mouseClick(item("rulesScalarChoice-choice:1"))
        compare(transport.responses[1], {id:table.rulesSession.promptId, choices:["choice:1"]})

        // Forge has paid the sacrifice before asking for its enum color. The
        // source's visible identity remains in the graveyard and prompt context.
        state.zones[4].cards = [state.zones[4].cards[1]]
        state.zones[4].count = 1
        state.zones.push({zone:"graveyard", ownerSeat:0, count:1, cards:[lotus]})
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseFromSelection", {title:"Select Mana to Produce",
            minChoiceTotal:1, maxChoiceTotal:1,
            choices:["WHITE", "BLUE", "BLACK", "RED", "GREEN"].map((color, index) =>
                ({responseId:"choice:" + index, label:color, weight:1, canRepeat:false})),
            contextCards:[{id:"context-card:0", name:"Lotus Bloom"}]})
        const colorId = table.rulesSession.promptId
        verify(dock.showsBody && !dock.collapsed)
        verify(!transport.rulesResponsePending)
        verify(!table.interaction.objectActionable("card", "lotus"))
        verify(!table.interaction.objectActionable("card", "land"))
        const blue = item("rulesScalarChoice-choice:1")
        verify(blue.visible && blue.enabled)
        compare(blue.text, data.label)
        const scalarList = item("rulesScalarCandidates")
        scalarList.positionViewAtIndex(1, ListView.Contain)
        const scroll = item("rulesPromptScroll")
        const blueTop = blue.mapToItem(scroll.contentItem, 0, 0).y
        scroll.contentY = Math.max(0, Math.min(blueTop, scroll.contentHeight - scroll.height))
        waitForRendering(table)
        const position = blue.mapToItem(scroll, 0, 0)
        verify(position.y >= 0 && position.y + blue.height <= scroll.height,
               "A sacrificed source's color button stays reachable in the decision dock")
        verify(!item("rulesConfirmChoices").visible)
        verify(!item("rulesSkipChoice").visible)
        mouseClick(blue)
        compare(transport.responses[2], {id:colorId, choices:["choice:1"]})
        verify(transport.rulesResponsePending)
        mouseClick(blue)
        compare(transport.responses.length, 3, "A color click is sent once while the response is pending")

        manaPrompt("sa:50", [
            {responseId:"activate-plains-current", kind:"activateAbility", cardId:"land", label:"Plains"},
            {responseId:"$pay", kind:"pay", label:"Confirm payment"}])
        compare(table.rulesSession.promptPaymentId, "sa:50")
        compare(table.interaction.paymentQueue, [], "Interrupted click-ahead never resumes after the color choice")
        verify(!transport.rulesResponsePending)
        compare(transport.responses.length, 3)
        verify(!table.interaction.objectActionable("card", "lotus"))
        verify(table.interaction.objectActionable("card", "land"))
        mouseClick(item("rulesPromptOption-$pay"))
        compare(transport.responses[3], {id:table.rulesSession.promptId, response:"$pay"})
    }
    function test_paymentWithoutAnIdKeepsTheWaitingCue() {
        const state = snapshot(1, 0)
        state.zones[4].cards = [card("land-a", 0, "Forest", false), card("land-b", 0, "Island", false)]
        state.zones[4].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        manaPrompt("", [
            {responseId:"pay-a", kind:"activateAbility", cardId:"land-a", label:"Forest"},
            {responseId:"pay-b", kind:"activateAbility", cardId:"land-b", label:"Island"}])
        mouseClick(item("forgeCard-land-a"))
        mouseClick(item("forgeCard-land-b"))
        compare(transport.responses.length, 1)
        compare(item("forgeWaitingCueText").text, "Waiting for the game")
        verify(findChild(table, "forgeCardPaymentQueue-land-b") === null)
    }
    function test_paymentQueueStopsAtEightAndEscapeRemovesTheLast() {
        const state = snapshot(1, 0)
        const lands = []
        for (let i = 0; i < 9; ++i)
            lands.push(card("land-" + i, 0, "Forest " + i, false))
        state.zones[4].cards = lands
        state.zones[4].count = lands.length
        verify(testRulesPrompt.applySnapshot(state))
        manaPrompt("sa:10", lands.map((land, i) => ({
            responseId:"pay-" + i, kind:"activateAbility", cardId:land.id, label:land.identity.name})))
        transport.rulesResponsePending = true
        for (let i = 0; i < 8; ++i)
            verify(table.interaction.tryQueuePayment("card", "land-" + i))
        verify(!table.interaction.tryQueuePayment("card", "land-8"))
        compare(table.interaction.paymentQueue.length, 8)
        table.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(table.interaction.paymentQueue.length, 7)
        compare(table.interaction.paymentQueue[6], "land-6")
    }
    function test_oneCardArtArrivalDoesNotRefreshTheWholeTable() {
        const state = snapshot(1, 0)
        const spell = card("spell", 0, "Shock", false)
        state.zones[4].cards = [spell]
        state.zones[4].count = 1
        verify(testRulesPrompt.applySnapshot(state))
        tryVerify(() => item("forgeOwnOther").visibleCards.some(card => card.cardId === "spell"))
        const before = catalog.requested.length
        catalog.imageRevision++
        waitForRendering(table)
        compare(catalog.requested.length, before)
        verify(item("forgeOwnOther").visibleCards.some(card => card.cardId === "spell"))
        catalog.typeOverrides = Object.assign({}, catalog.typeOverrides, {Shock: "Land"})
        catalog.cardAvailable("Shock", "Shock", "Land", "", "", "")
        tryVerify(() => item("forgeOwnLands").visibleCards.some(card => card.cardId === "spell"))
        verify(catalog.requested.length > before)
    }
    function test_damageMarkPulsesAndThenRests() {
        Theme.motionEnabled = true
        const state = snapshot(1, 1)
        verify(testRulesPrompt.applySnapshot(state))
        const face = item("forgeCard-own-0")
        compare(face.markPulse, 1)
        state.zones[4].cards[0].damage = 3
        verify(testRulesPrompt.applySnapshot(state))
        tryVerify(() => item("forgeCard-own-0").markPulse > 1)
        tryCompare(item("forgeCard-own-0"), "markPulse", 1)
        Theme.motionEnabled = false
    }
    function test_stackEntryArrivesAndLeaves() {
        Theme.motionEnabled = true
        const state = snapshot()
        state.stack = [{id:"bolt", controllerSeat:0, identity:{name:"Lightning Bolt"}, text:"Deal 3 damage"}]
        verify(testRulesPrompt.applySnapshot(state))
        const entry = item("forgeStackEntry-bolt")
        tryCompare(entry, "opacity", 1)
        state.stack = []
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(item("forgeStack"), "count", 0)
        Theme.motionEnabled = false
    }
    function test_lifeLossFloatsARedDelta() {
        Theme.motionEnabled = true
        const state = snapshot()
        state.players[0].life = 17
        verify(testRulesPrompt.applySnapshot(state))
        const delta = item("forgeLifeDelta-0")
        const value = item("forgeLifeValue-0")
        compare(delta.text, "-3")
        verify(delta.opacity > 0)
        tryVerify(() => delta.implicitWidth > 0 && value.implicitWidth > 0)
        const deltaRect = delta.mapToItem(table, 0, 0, delta.width, delta.height)
        const valueRect = value.mapToItem(table, 0, 0, value.width, value.height)
        verify(deltaRect.y + deltaRect.height <= valueRect.y + 0.5,
               "The life change stays above the current total")
        tryCompare(value, "text", "17")
    }
    function test_lifeDeltasStayInsideTheirReservedSpace_data() {
        return [
            {tag:"duel-player", seats:2, seat:0, scale:1, resize:true},
            {tag:"duel-opponent-compact", seats:2, seat:1, scale:1.8, compact:true, chinese:true},
            {tag:"duel-spectator", seats:2, seat:-1, scale:1.8},
            {tag:"duel-replay", seats:2, seat:-1, scale:1.8, replay:true},
            {tag:"three-player", seats:3, seat:0, scale:1},
            {tag:"three-spectator", seats:3, seat:-1, scale:1.8},
            {tag:"four-player", seats:4, seat:0, scale:1.8, resize:true},
            {tag:"four-opponent-compact", seats:4, seat:3, scale:1.8, compact:true, chinese:true},
            {tag:"four-spectator", seats:4, seat:-1, scale:1},
            {tag:"four-replay", seats:4, seat:-1, scale:1.8, replay:true},
            {tag:"duel-wide-delta", seats:2, seat:0, scale:1.8, wide:true},
            {tag:"four-wide-delta", seats:4, seat:0, scale:1.8, wide:true}
        ]
    }
    function test_lifeDeltasStayInsideTheirReservedSpace(data) {
        window.width = data.compact ? 900 : 1920
        window.height = data.compact ? 620 : 1011
        Theme.uiScale = data.scale
        testTranslations.setLanguage(data.chinese ? "zh" : "en")
        room.role = data.seat < 0 ? "spectator" : "player"
        room.seatIndex = data.seat
        room.spectatorsSeeHands = data.seat < 0
        table.replayMode = data.replay === true
        room.actionClockEnabled = true
        room.actionClockMs = [180000, 165000, 150000, 145000]
        const seats = Array.from({length:data.seats}, (_, index) => index)
        if (data.seats > 2) {
            room.format = "edh"; room.deckFormat = "commander"; room.maxSeats = data.seats
        }
        const state = data.seats > 2 ? edhSnapshot(seats, Math.max(0, data.seat), 1) : snapshot()
        if (data.chinese)
            for (const player of state.players) player.name = "中文玩家 " + player.seat
        room.players = state.players.map(player => player.name)
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(table.presentation, "multiplayer", data.seats > 2)
        verify(waitForPolish(window)); verify(waitForRendering(table))
        function bounds(target) {
            return target.mapToItem(table, 0, 0, target.width, target.height)
        }
        const fixedItems = []
        for (const seat of seats) {
            fixedItems.push(item("rulesPlayerTarget" + seat), item("forgePlayerName-" + seat))
            if (data.seats > 2)
                fixedItems.push(item("forgeField-" + seat), item("forgeCard-creature-" + seat + "-0"))
        }
        if (data.seats === 2)
            fixedItems.push(item("forgeCard-own-0"), item("forgeCard-opponent"))
        const initial = fixedItems.map(target => bounds(target))
        const readouts = seats.map(seat => {
            const target = item("rulesPlayerTarget" + seat)
            const names = ["forgePlayerName-", "forgePlayerZones-"]
                .concat(data.seats > 2 ? ["forgeSeatStatus-", "forgeSeatZones-"] : ["forgeActionClock-"])
            return {seat:seat, delta:item("forgeLifeDelta-" + seat), value:item("forgeLifeValue-" + seat),
                envelope:data.seats > 2 ? target.parent : target, labels:names.map(name => item(name + seat))}
        })
        function check(stage, requiresVisible) {
            for (const readout of readouts) {
                const seat = readout.seat, delta = readout.delta, value = readout.value
                if (requiresVisible)
                    verify(delta.opacity > 0, stage + ": the change is still visible")
                const rect = bounds(delta)
                verify(rect.x >= -0.5 && rect.y >= -0.5
                    && rect.x + rect.width <= table.width + 0.5
                    && rect.y + rect.height <= table.height + 0.5,
                    stage + ": delta stays in the viewport for seat " + seat + ": " + JSON.stringify(rect))
                const envelope = bounds(readout.envelope)
                verify(rect.x >= envelope.x - 0.5 && rect.y >= envelope.y - 0.5
                    && rect.x + rect.width <= envelope.x + envelope.width + 0.5
                    && rect.y + rect.height <= envelope.y + envelope.height + 0.5,
                    stage + ": the whole delta stays inside its reserved player area")
                verify(rect.y + rect.height <= bounds(value.parent).y - 1 * table.presentation.unit,
                    stage + ": the signed change stays above the life disc")
                for (const label of readout.labels) {
                    if (label.visible)
                        verify(!rectsOverlap(delta, label), stage + ": delta overlaps " + label.objectName)
                }
                verify(!rectsOverlap(delta, value), stage + ": delta overlaps the current total")
            }
            for (let index = 0; index < fixedItems.length; ++index)
                compare(bounds(fixedItems[index]), initial[index], stage + ": life motion must not move the board")
        }
        Theme.motionEnabled = true
        const values = data.wide ? [2000000000, -2000000000, 2000000000] : [17, 23, 19]
        for (const life of values) {
            for (const player of state.players) player.life = life
            verify(testRulesPrompt.applySnapshot(state))
            verify(waitForPolish(window))
            check("start " + life, true)
            wait(180)
            check("rising " + life, true)
            if (data.resize && life === values[values.length - 1]) {
                window.width = 1280; window.height = 720
                tryCompare(table, "width", 1280); tryCompare(table, "height", 720)
                verify(waitForPolish(window)); verify(waitForRendering(table))
                for (let index = 0; index < fixedItems.length; ++index)
                    initial[index] = bounds(fixedItems[index])
                // Processing a native resize can outlast the remaining fade.
                // Its resulting position must fit the new band at any progress.
                check("resized animation position", false)
            }
        }
        for (const readout of readouts) tryCompare(readout.delta, "opacity", 0)
        check("final animation position", false)
        Theme.finishMotion()
        for (const readout of readouts) compare(readout.delta.opacity, 0)
        for (let index = 0; index < fixedItems.length; ++index)
            compare(bounds(fixedItems[index]), initial[index], "Finishing motion keeps the same reserved geometry")
    }
    function test_handCardBecomesOneBattlefieldMove() {
        const before = snapshot(1, 1)
        const after = snapshot(1, 1)
        const played = after.zones[0].cards.pop()
        after.zones[0].count = after.zones[0].cards.length
        after.zones[4].cards.push(played)
        after.zones[4].count = after.zones[4].cards.length
        verify(testRulesPrompt.applySnapshot(before))
        verify(testRulesPrompt.applySnapshot(after))
        const move = table.rulesSession.transitions.find(event => event.id === "hand-0")
        verify(move)
        compare(move.kind, "move")
        compare(move.fromZone, "hand")
        compare(move.toZone, "battlefield")
        compare(table.rulesSession.transitions.filter(event =>
            event.kind === "move" || event.kind === "enter" || event.kind === "leave").length, 1)
    }
    function test_enabledMotionRotatesATap() {
        Theme.motionEnabled = true
        const state = snapshot(1, 0)
        const plains = card("land", 0, "Plains", false)
        state.zones[4].cards = [plains]
        state.zones[4].count = 1
        verify(testRulesPrompt.applySnapshot(state))
        const land = item("forgeCard-land")
        plains.tapped = true
        verify(testRulesPrompt.applySnapshot(state))
        verify(land.tapShade < 1)
        tryCompare(land, "tapShade", 1)
        compare(item("forgeCardTappedShade-land").opacity, land.tappedShade)
    }
    function test_slotGlideKeepsTheHitTargetAndAClickFinishesIt() {
        const state = snapshot(1, 0)
        state.zones[4].cards = [card("land-a", 0, "Plains", false), card("land-b", 0, "Plains", false)]
        state.zones[4].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(item("forgeOwnLands"), "stackCount", 1)
        const front = item("forgeCard-land-b")
        const slot = front.parent
        compare(slot.visualDx, 0)
        compare(slot.visualDy, 0)
        Theme.motionEnabled = true
        mouseClick(item("forgeCardStackCount-land-b"))
        verify(Math.abs(slot.visualDx) + Math.abs(slot.visualDy) > 1)
        mouseClick(front)
        compare(slot.visualDx, 0)
        compare(slot.visualDy, 0)
    }

    // Publishes the pending prompt again under the same id, as Forge does when
    // it re-sends a decision.
    function test_tappedSiblingWithAnActionDoesNotAnswerAFrontClick() {
        landBoard(["land-a", "land-b"], ["land-a"])
        prompt("chooseAction", {options:[
            {responseId:"animate-a", kind:"activateAbility", cardId:"land-a", label:"Animate"},
            {responseId:"mana-b", kind:"activateAbility", cardId:"land-b", label:"Add {W}"},
            {responseId:"animate-b", kind:"activateAbility", cardId:"land-b", label:"Animate"},
            {responseId:"$pass", kind:"pass", label:"Pass"}]})
        tryCompare(item("forgeOwnLands"), "stackCount", 2)
        mouseClick(item("forgeCard-land-b"))
        compare(transport.responses.length, 0, "Only the clicked card answers")
        verify(table.cardActionPicker.opened)
        verify(!item("forgeWaitingCue").visible)
        mouseClick(item("rulesCardAction-animate-b"))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].response, "animate-b")
    }
    function test_pileClickAheadQueuesSeveralLands() {
        landBoard(["land-a", "land-b", "land-c"])
        manaPrompt("sa:10", ["a", "b", "c"].map(x => ({responseId:"pay-" + x, kind:"activateAbility",
            cardId:"land-" + x, label:"Plains"})))
        tryCompare(item("forgeOwnLands"), "stackCount", 1)
        const front = item("forgeCard-land-c")
        mouseClick(front)
        compare(transport.responses.length, 1)
        compare(transport.responses[0].response, "pay-c")
        mouseClick(front)
        mouseClick(front)
        compare(table.interaction.paymentQueue, ["land-a", "land-b"])
        compare(item("forgeCardPaymentQueue-land-c").text, "1 2")
        mouseClick(front)
        compare(table.interaction.paymentQueue.length, 2, "A further click never unqueues a land")
        manaPrompt("sa:10", ["a", "b"].map(x => ({responseId:"pay2-" + x, kind:"activateAbility",
            cardId:"land-" + x, label:"Plains"})))
        compare(transport.responses.length, 2)
        compare(transport.responses[1].response, "pay2-a")
        compare(table.interaction.paymentQueue, ["land-b"])
    }
    function test_handSourcesAreNeverQueued() {
        const state = snapshot(1, 0)
        state.zones[0].cards = [card("spirit", 0, "Simian Spirit Guide", true)]
        state.zones[4].cards = [card("land-a", 0, "Forest", false)]
        state.zones[4].count = 1
        verify(testRulesPrompt.applySnapshot(state))
        manaPrompt("sa:10", [
            {responseId:"pay-a", kind:"activateAbility", cardId:"land-a", label:"Forest"},
            {responseId:"pay-s", kind:"activateAbility", cardId:"spirit", label:"Exile"}])
        mouseClick(item("forgeCard-land-a"))
        compare(transport.responses.length, 1)
        verify(!table.interaction.tryQueuePayment("card", "spirit"))
        verify(!table.interaction.tryQueuePayment("card", "land-a"), "The land in flight is not queued again")
        compare(table.interaction.paymentQueue.length, 0)
    }
    function test_errorReleaseDropsQueuedMana() {
        const options = forestAndIsland()
        manaPrompt("sa:10", options)
        mouseClick(item("forgeCard-land-a"))
        mouseClick(item("forgeCard-land-b"))
        compare(table.interaction.paymentQueue, ["land-b"])
        transport.rulesResponsePending = false
        tryVerify(() => table.interaction.paymentQueue.length === 0)
        compare(item("forgeWaitingCueText").text, "Queued mana was cleared")
        verify(findChild(table, "forgeCardPaymentQueue-land-b") === null)
        mouseClick(item("forgeCard-land-b"))
        compare(transport.responses.length, 2)
        compare(transport.responses[1].response, "pay-b")
    }
    function test_sameIdRepublicationKeepsTheQueueAndRing() {
        const options = forestAndIsland()
        manaPrompt("sa:10", options)
        mouseClick(item("forgeCard-land-a"))
        mouseClick(item("forgeCard-land-b"))
        republish("payManaCost", {title:"Pay Mana Cost: {G}", paymentId:"sa:10", options:options})
        compare(table.interaction.paymentQueue, ["land-b"])
        verify(item("forgeCard-land-a").submitted)
        verify(!item("forgeWaitingCue").visible)
        compare(transport.responses.length, 1)
    }
    function test_stackEntriesFinishArrivingWhenInterrupted() {
        Theme.motionEnabled = true
        const state = snapshot()
        const first = {id:"spell-a", controllerSeat:0, identity:{name:"Lightning Bolt"}, text:"Deal 3 damage"}
        const second = {id:"spell-b", controllerSeat:1, identity:{name:"Shock"}, text:"Deal 2 damage"}
        state.stack = [first]
        verify(testRulesPrompt.applySnapshot(state))
        const entry = item("forgeStackEntry-spell-a")
        verify(entry.opacity < 1, "A new entry fades in")
        state.stack = [second, first]
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(entry, "opacity", 1)
        compare(entry.scale, 1)
        tryCompare(item("forgeStackEntry-spell-b"), "opacity", 1)
        state.stack = [first]
        verify(testRulesPrompt.applySnapshot(state))
        Theme.finishMotion()
        compare(entry.opacity, 1)
        compare(entry.glideY, 0)
    }
    function test_localUpdateFliesToTheNewPlaceWithoutHoldingPasses() {
        Theme.motionEnabled = true
        const overlay = item("forgeMotionOverlay"), flights = item("forgeMotionFlights")
        const after = snapshot()
        after.zones[4].cards = after.zones[4].cards.filter(row => row.id !== "land")
        after.zones[4].count = after.zones[4].cards.length
        after.zones.push({zone:"graveyard", ownerSeat:0, count:1, cards:[card("land", 0, "Plains", false)]})
        verify(testRulesPrompt.applySnapshot(after))
        tryVerify(() => flights.children.some(proxy => proxy.opacity === 1))
        const proxy = flights.children.find(proxy => proxy.opacity === 1)
        verify(Math.hypot(proxy.toX - proxy.fromX, proxy.toY - proxy.fromY) > 40 * table.presentation.unit,
            "The flight leaves the battlefield for the graveyard pile")
        verify(!overlay.staging)
        Theme.finishMotion()
        compare(overlay.flights, 0)
    }
    function test_otherPlayersUpdateIsStagedAndReleased() {
        const base = snapshot()
        base.activeSeat = 1; base.prioritySeat = 1
        verify(testRulesPrompt.applySnapshot(base))
        waitForRendering(table)
        Theme.motionEnabled = true
        const overlay = item("forgeMotionOverlay"), flights = item("forgeMotionFlights")
        const died = snapshot()
        died.activeSeat = 1; died.prioritySeat = 1
        died.zones[5].cards = []; died.zones[5].count = 0
        died.zones[1].count = 8; died.zones[3].count = 48
        died.zones.push({zone:"graveyard", ownerSeat:1, count:1, cards:[card("opponent", 1, "Grizzly Bears", true)]})
        verify(testRulesPrompt.applySnapshot(died))
        tryVerify(() => overlay.staging)
        tryVerify(() => flights.children.some(proxy => proxy.label === "" && proxy.opacity === 1))
        const draw = flights.children.find(proxy => proxy.label === "" && proxy.opacity === 1)
        verify(Math.hypot(draw.toX - draw.fromX, draw.toY - draw.fromY) > 20 * table.presentation.unit,
            "A hidden draw travels from the library to the hand count")
        verify(overlay.changedIds.includes("opponent"))
        const tapped = JSON.parse(JSON.stringify(died))
        tapped.zones[4].cards[1].tapped = true
        verify(testRulesPrompt.applySnapshot(tapped))
        tryVerify(() => !overlay.staging, 300, "An update without flights releases the hold")
        compare(overlay.stagedFlights, 0)
    }
    function test_opponentCastFromAHiddenHandFliesToTheStack() {
        const base = snapshot()
        base.activeSeat = 1
        base.prioritySeat = 1
        verify(testRulesPrompt.applySnapshot(base))
        waitForRendering(table)
        Theme.motionEnabled = true
        const cast = JSON.parse(JSON.stringify(base))
        cast.zones[1].count = 6
        cast.stack = [{id:"their-bolt", controllerSeat:1, ownerSeat:1,
            identity:{name:"Lightning Bolt", setCode:"M11", collectorNumber:"149"},
            text:"Lightning Bolt deals 3 damage to any target."}]
        verify(testRulesPrompt.applySnapshot(cast))
        const flights = item("forgeMotionFlights")
        tryVerify(() => flights.children.some(proxy => proxy.label === "Lightning Bolt" && proxy.opacity === 1))
        const proxy = flights.children.find(proxy => proxy.label === "Lightning Bolt")
        verify(Math.hypot(proxy.toX - proxy.fromX, proxy.toY - proxy.fromY) > 40 * table.presentation.unit,
            "An opponent spell travels from the hand count to the stack")
        Theme.finishMotion()
    }
    function test_ownAnswerIsNotStaged() {
        const base = snapshot()
        base.activeSeat = 1; base.prioritySeat = 0
        verify(testRulesPrompt.applySnapshot(base))
        prompt("chooseAction", {options:[{responseId:"mana", kind:"activateAbility", cardId:"land", label:"Plains"},
            {responseId:"$pass", kind:"pass", label:"Pass"}]})
        Theme.motionEnabled = true
        mouseClick(item("forgeCard-land"))
        compare(transport.responses.length, 1)
        const overlay = item("forgeMotionOverlay")
        const after = JSON.parse(JSON.stringify(base))
        const played = after.zones[0].cards.pop()
        after.zones[0].count = after.zones[0].cards.length
        after.zones[4].cards.push(played)
        after.zones[4].count = after.zones[4].cards.length
        verify(testRulesPrompt.applySnapshot(after))
        tryVerify(() => overlay.flights > 0)
        verify(!overlay.staging, "The update that answers your own action is not held")
    }
    function test_inputFinishesRunningMotion() {
        Theme.motionEnabled = true
        const state = snapshot(1, 0)
        const plains = card("tap-land", 0, "Plains", false)
        state.zones[4].cards = [plains]
        state.zones[4].count = 1
        verify(testRulesPrompt.applySnapshot(state))
        const land = item("forgeCard-tap-land")
        plains.tapped = true
        verify(testRulesPrompt.applySnapshot(state))
        verify(land.tapShade < 1)
        const hand = item("forgeHand")
        mousePress(hand, 2, 2)
        compare(land.tapShade, 1, "A press anywhere on the table finishes the dim")
        mouseRelease(hand, 2, 2)
        plains.tapped = false
        verify(testRulesPrompt.applySnapshot(state))
        verify(land.tapShade > 0)
        table.forceActiveFocus()
        keyClick(Qt.Key_A)
        compare(land.tapShade, 0, "A key finishes it too")

        const dock = item("rulesDecisionDock")
        prompt("chooseFromSelection", {title:"Choose one", minChoiceTotal:1, maxChoiceTotal:1,
            choices:[0, 1, 2, 3, 4, 5].map(i => ({responseId:"choice:" + i, label:"Option " + i,
                weight:1, canRepeat:false}))})
        Theme.finishMotion()
        // Expansion exposes choices immediately; contraction still animates
        // and must finish on input after the resize hold has expired.
        wait(300)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        tryVerify(() => dock.height > dock.targetHeight, 1000)
        mousePress(hand, 2, 2)
        compare(dock.height, dock.targetHeight, "A press finishes the dock resize")
        mouseRelease(hand, 2, 2)
    }
}
