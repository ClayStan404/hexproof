// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"
import "../../qml/screens"
import "../../../../tools/ui-automation/scenarios/ForgeNecrodominanceStudy.js" as NecroStudy

// Attacker/blocker drafts, legal targets and board interaction.
ForgeDuelTestCase {
    id: testCase
    name: "ForgeDuelCombat"

    function test_edhCombatAndStackAcrossAllFields() {
        room.format = "edh"; room.maxSeats = 4
        const data = edhSnapshot([0,1,2,3], 0)
        data.activeSeat = 0; data.prioritySeat = 0; data.step = "declare_attackers"
        verify(testRulesPrompt.applySnapshot(data))
        tryCompare(table.presentation, "multiplayer", true)
        prompt("chooseAttackers", {combatSources:[{responseId:"attacker", objectId:"creature-0-0",
            label:"Bear 0", name:"Bear 0", validTargetIds:["defender-1", "defender-2", "defender-3"], maxAssignments:1}],
            combatTargets:[1,2,3].map(seat => ({responseId:"defender-" + seat, kind:"player", seat:seat,
                label:"Player " + seat, minAssignments:0, maxAssignments:8}))})
        mouseClick(item("forgeCard-creature-0-0"))
        mouseClick(item("rulesPlayerTarget3"))
        compare(table.combatInteraction.assignments.attacker, "defender-3")
        const combatArrow = item("forgeCombatArrow-creature-0-0-seat-3")
        compare(combatArrow.endPoint, table.presentation.playerPoint(3))
        verify(combatArrow.startPoint.x > 0 && combatArrow.endPoint.x > 0)
        mouseClick(item("rulesConfirmCombat-attackers"))
        compare(transport.responses[0].assignments, [{sourceId:"attacker", targetId:"defender-3"}])
        data.stack = [{id:"bolt", controllerSeat:2, identity:{name:"Lightning Bolt"}, text:"Deal 3 damage",
            targets:[{kind:"card", objectId:"creature-1-0", label:"Bear 0"}, {kind:"player", seat:3, label:"Player 3"}]}]
        verify(testRulesPrompt.applySnapshot(data))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        mouseClick(item("forgeStackTarget-bolt-0"))
        const arrow = item("forgeStackTargetArrow")
        tryVerify(() => arrow.visible && arrow.endPoint.x > 0)
        compare(arrow.endPoint, table.presentation.pointFor("creature-1-0"))
        mouseClick(item("forgeStackTarget-bolt-1"))
        compare(arrow.endPoint, table.presentation.playerPoint(3))
        verify(item("forgeField-3").selected)
        transport.inRoom = false
        tryCompare(arrow, "visible", false)
        verify(!item("forgeField-3").selected)
    }

    function test_combatChromeFitsWithoutMovingOtherCards_data() {
        return [{tag:"opponent-unattached", w:1920, h:1011, seat:1, depth:0},
            {tag:"own-unattached", w:1920, h:1011, seat:0, depth:0},
            {tag:"opponent-attached", w:1920, h:1011, seat:1, depth:1},
            {tag:"own-attached", w:1920, h:1011, seat:0, depth:3},
            {tag:"laptop-opponent", w:1280, h:720, seat:1, depth:2},
            {tag:"laptop-own-blocker", w:1280, h:720, seat:0, depth:2, blocking:true}]
    }
    function test_combatChromeFitsWithoutMovingOtherCards(data) {
        window.width = data.w; window.height = data.h
        const state = snapshot(1, 1, true)
        const hostId = data.seat === 0 ? "own-0" : "opponent"
        const field = state.zones[4 + data.seat]
        for (let i = 0; i < data.depth; ++i)
            field.cards.push(Object.assign(card("aura-" + i, data.seat, "Aura " + i, false), {attachedTo:hostId}))
        field.count = field.cards.length
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"pass", kind:"pass", label:"Pass"}]})
        const lane = item(data.seat === 0 ? "forgeOwnCreatures" : "forgeOpponentCreatures")
        const host = item("forgeCard-" + hostId)
        const geometry = Qt.rect(lane.x, lane.y, lane.width, lane.height)
        const width = host.width
        const atRest = host.mapToItem(table.presentation, 0, 0)
        const land = item("forgeCard-land")
        const landAtRest = land.mapToItem(table.presentation, 0, 0)
        state.step = "declare_blockers"
        if (data.blocking) {
            field.cards[0].blocking = ["opponent"]
            state.zones[5].cards[0].attacking = true
            state.zones[5].cards[0].attackingPlayer = 0
        } else {
            field.cards[0].attacking = true
            field.cards[0].attackingPlayer = 1 - data.seat
        }
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        compare(Qt.rect(lane.x, lane.y, lane.width, lane.height), geometry)
        compare(host.width, width, "Combat keeps the preallocated readable card size")
        compare(land.mapToItem(table.presentation, 0, 0), landAtRest)
        verify(host.width >= 80 * table.presentation.unit - 0.1)
        const moved = host.mapToItem(table.presentation, 0, 0)
        verify(Math.abs(moved.y - atRest.y - (data.blocking ? 0 : lane.combatForward * 14 * lane.unit)) < 0.1)
        const badge = item("forgeCardInteractionHint-" + hostId).parent
        verify(badge.visible)
        const cardAt = host.mapToItem(lane.scrollArea, 0, 0)
        const badgeAt = badge.mapToItem(lane.scrollArea, 0, 0)
        verify(cardAt.y >= -0.1 && cardAt.y + host.height <= lane.scrollArea.height + 0.1,
            "The full attacking face stays inside its clipped lane")
        verify(badgeAt.y >= 0 && badgeAt.y + badge.height <= lane.scrollArea.height + 0.1,
            "The entire combat destination badge stays inside the viewport")
        for (let i = 0; i < data.depth; ++i) {
            const strip = item("forgeAttachmentStrip-aura-" + i)
            const stripAt = strip.mapToItem(lane.scrollArea, 0, 0)
            verify(stripAt.y + strip.height <= badgeAt.y
                || badgeAt.y + badge.height <= stripAt.y,
                "The host badge cannot cover any attachment name strip")
            verify(stripAt.y >= 0 && stripAt.y + strip.height <= lane.scrollArea.height + 0.1)
        }
        const ids = [hostId].concat(Array.from({length:data.depth}, (_, i) => "aura-" + i))
        for (let i = 0; i < ids.length; ++i) {
            prompt("chooseBoardTargets", {minSelections:1, maxSelections:1,
                targets:ids.map(id => ({responseId:"target-" + id, kind:"card", objectId:id, label:id}))})
            const face = item("forgeCard-" + ids[i])
            mouseClick(face, face.width / 2, i === 0 ? face.height / 2 : face.height - 8 * lane.unit)
            compare(transport.responses.length, i + 1)
            compare(transport.responses[i].targets, ["target-" + ids[i]])
        }
    }
    function test_retargetedLaneCannotRestoreCachedCombatGrouping() {
        // This seat has no live field in the two-player fixture. Seed the
        // cached native model as a previous view with a combat draft left it.
        const cached = table.rulesSession.laneSlots(3, "battlefield", "creature")
        cached.combatGroupingKeys = {"old-card":"earlier-combat-draft"}
        const temporary = createTemporaryObject(shortLane, window.contentItem,
            {ownerSeat:3, visible:false})
        compare(temporary.slotModel, cached)
        compare(Object.keys(cached.combatGroupingKeys).length, 0)
        temporary.ownerSeat = 2
        compare(temporary.slotModel, table.rulesSession.laneSlots(2, "battlefield", "creature"))
        compare(Object.keys(cached.combatGroupingKeys).length, 0,
            "Retargeting the view must retain the latest grouping, not its saved old value")
    }
    function test_shortCombatLaneKeepsReadableScrolling_data() {
        return [{tag:"near-side", direction:-1}, {tag:"far-side", direction:1}]
    }
    function test_shortCombatLaneKeepsReadableScrolling(data) {
        const state = snapshot(1, 12, true)
        state.step = "declare_blockers"
        state.zones[4].cards.forEach(row => {
            if (row.power) { row.attacking = true; row.attackingPlayer = 1 }
        })
        verify(testRulesPrompt.applySnapshot(state))
        const lane = createTemporaryObject(shortLane, window.contentItem,
            {combatForward:data.direction, height:110})
        verify(lane !== null)
        tryCompare(lane, "stackCount", 12)
        verify(lane.cardWidth >= 80, "Combat margins cannot reduce the readable floor")
        verify(lane.scrollArea.contentHeight > lane.scrollArea.height)
        const finalCard = lane.itemFor("own-11")
        verify(finalCard !== null)
        verify(lane.reveal("own-11"))
        verify(lane.scrollArea.contentY > 0)
        const at = finalCard.mapToItem(lane.scrollArea, 0, 0)
        verify(at.y >= -0.1 && at.y + finalCard.height <= lane.scrollArea.height + 0.1,
            "Revealing the final exact card keeps its face visible")
    }
    function test_targetsAndCombatKeepIdenticalCreaturesInOneSlot() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 2)))
        const land = item("forgeCard-land")
        const before = land.mapToItem(table.presentation, 0, 0)
        const creatures = item("forgeOwnCreatures")
        prompt("chooseAttackers", {
            combatSources:[0, 1].map(i => ({responseId:"source-" + i, objectId:"own-" + i,
                label:"Bear", name:"Grizzly Bears", validTargetIds:["defender"], maxAssignments:1})),
            combatTargets:[{responseId:"defender", kind:"player", seat:1, label:"Opponent", maxAssignments:2}]
        })
        tryCompare(creatures, "stackCount", 1)
        const duringCombat = land.mapToItem(table.presentation, 0, 0)
        compare(Math.round(duringCombat.x), Math.round(before.x))
        compare(Math.round(duringCombat.y), Math.round(before.y))
        prompt("chooseBoardTargets", {minSelections:1, maxSelections:1,
            targets:[0, 1].map(i => ({responseId:"target-" + i, kind:"card",
                objectId:"own-" + i, label:"Bear", name:"Grizzly Bears"}))})
        tryCompare(creatures, "stackCount", 1)
        const duringTargets = land.mapToItem(table.presentation, 0, 0)
        compare(Math.round(duringTargets.x), Math.round(before.x))
        compare(Math.round(duringTargets.y), Math.round(before.y))
        mouseClick(item("forgeCard-own-1"))
        compare(table.interaction.selectedTargetIds["target-0"], true)
    }
    function test_boardAndDockShareOpaqueCombatChoices() {
        combat("chooseAttackers")
        const source = item("forgeCard-own-0")
        tryCompare(source, "actionable", true)
        mouseClick(source)
        compare(table.combatInteraction.selectedSource, "")
        compare(table.combatInteraction.assignments["opaque-source"], "opaque-target")
        verify(item("rulesConfirmCombat-attackers").enabled)
        verify(!item("rulesCombatCandidates-attackers").visible)
        waitForRendering(table)
        mouseClick(item("rulesCombatDetails-attackers"))
        tryVerify(() => findChild(table, "rulesCombatAssignment-opaque-source") !== null)
        const combo = item("rulesCombatAssignment-opaque-source")
        compare(combo.currentIndex, 1)
        compare(table.combatInteraction.links.length, 1)
        mouseClick(item("rulesConfirmCombat-attackers"))
        compare(transport.responses[0].assignments, [{sourceId:"opaque-source", targetId:"opaque-target"}])
        combat("chooseBlockers")
        compare(table.combatInteraction.links.length, 0)
        mouseClick(source)
        tryCompare(item("forgeCard-opponent"), "actionable", true)
        mouseClick(item("forgeCard-opponent"))
        compare(table.combatInteraction.links[0].to, "opponent")
        waitForRendering(table)
        mouseClick(item("rulesCombatDetails-blockers"))
        tryVerify(() => findChild(table, "rulesCombatAssignment-opaque-source") !== null)
        item("rulesCombatAssignment-opaque-source").forceActiveFocus(); keyClick(Qt.Key_Up)
        compare(table.combatInteraction.links.length, 0)
    }
    function test_combatStateCannotCrossAuthorityOrPromptBoundaries_data() {
        return [{tag:"disconnect"}, {tag:"spectate"}, {tag:"seat-change"}, {tag:"new-prompt"}, {tag:"new-game"}]
    }
    function test_combatAimFollowsPointerAndLocksOnClick_data() {
        return [{tag:"attackers", kind:"chooseAttackers", target:"rulesPlayerTarget1", suffix:"seat-1",
                    invalid:"forgeCard-opponent"},
                {tag:"blockers", kind:"chooseBlockers", target:"forgeCard-opponent", suffix:"opponent",
                    invalid:"rulesPlayerTarget1"}]
    }
    function test_combatSoundsFollowSelectionAndAssignmentOnly_data() {
        return [{tag:"attack", kind:"chooseAttackers", target:"rulesPlayerTarget1"},
                {tag:"block", kind:"chooseBlockers", target:"forgeCard-opponent"}]
    }
    function test_combatSoundsFollowSelectionAndAssignmentOnly(data) {
        const previousBackend = SoundEffects.backend
        SoundEffects.backend = soundRecorder
        soundRecorder.cues = []
        try {
            combat(data.kind, 1, true)
            const source = item("forgeCard-own-0"), target = item(data.target)
            mouseMove(source)
            compare(soundRecorder.cues, [])
            mouseClick(source)
            compare(soundRecorder.cues, ["select"])
            mouseMove(table.presentation, table.presentation.width / 2, table.presentation.height / 2)
            mouseMove(target)
            compare(soundRecorder.cues, ["select"])
            mouseClick(target)
            compare(soundRecorder.cues, ["select", data.tag])
            mouseClick(source)
            mouseClick(target)
            compare(soundRecorder.cues, ["select", data.tag, "select", "cancel"])
            mouseClick(source)
            source.forceActiveFocus()
            keyClick(Qt.Key_Escape)
            compare(soundRecorder.cues, ["select", data.tag, "select", "cancel", "select", "cancel"])
            mouseClick(source)
            const beforeReset = soundRecorder.cues.slice()
            combat(data.kind, 1, true)
            transport.inRoom = false
            compare(soundRecorder.cues, beforeReset)
        } finally {
            SoundEffects.backend = previousBackend
        }
    }
    function test_combatAimFollowsPointerAndLocksOnClick(data) {
        combat(data.kind, 1, true)
        const source = item("forgeCard-own-0"), aim = item("forgeCombatAimArrow")
        verify(!aim.visible)
        mouseClick(source)
        compare(table.combatInteraction.selectedSource, "opaque-source")
        tryCompare(aim, "visible", true)
        verify(Math.hypot(aim.endPoint.x - aim.startPoint.x, aim.endPoint.y - aim.startPoint.y) > 8)
        compare(aim.startPoint, table.presentation.pointFor("own-0"))
        for (const delta of [0, 60, 120]) {
            const x = Math.round(table.presentation.width - 50 - delta)
            const y = Math.round(table.presentation.height / 2 - delta / 2)
            mouseMove(table.presentation, x, y)
            tryCompare(aim, "snapped", false)
            tryVerify(() => Math.abs(aim.endPoint.x - x) < 1 && Math.abs(aim.endPoint.y - y) < 1)
            compare(table.combatInteraction.links.length, 0)
            compare(transport.responses.length, 0)
        }
        mouseMove(item(data.invalid))
        tryCompare(aim, "snapped", false)
        compare(table.combatInteraction.hoveredTarget, null)
        const target = item(data.target)
        mouseMove(target, target.width / 2, target.height / 2)
        tryCompare(aim, "snapped", true)
        const endpoint = data.tag === "attackers" ? table.presentation.playerPoint(1)
            : table.presentation.pointFor("opponent")
        compare(aim.endPoint, endpoint)
        compare(table.combatInteraction.links.length, 0)
        compare(transport.responses.length, 0)
        mouseClick(target)
        tryCompare(aim, "visible", false)
        compare(table.combatInteraction.selectedSource, "")
        compare(table.combatInteraction.assignments["opaque-source"], "opaque-target")
        const fixed = item("forgeCombatArrow-own-0-" + data.suffix)
        compare(fixed.endPoint, endpoint)
        verify(fixed.visible)
        mouseMove(table.presentation, table.presentation.width - 40, table.presentation.height / 2)
        compare(fixed.endPoint, endpoint)
        verify(!aim.visible)
        compare(table.combatInteraction.links.length, 1)
        compare(transport.responses.length, 0)
    }
    function test_combatAimHidesPendingAndOffscreen() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 70, true)))
        combat("chooseAttackers", 1, true)
        const source = item("forgeCard-own-0"), aim = item("forgeCombatAimArrow")
        const lane = item("forgeOwnCreatures")
        lane.scrollArea.contentY = 0
        mouseClick(source)
        tryCompare(aim, "visible", true)
        transport.rulesResponsePending = true
        tryCompare(aim, "visible", false)
        compare(table.combatInteraction.links.length, 0)
        transport.rulesResponsePending = false
        mouseMove(source, source.width / 2, source.height / 2)
        tryCompare(aim, "visible", true)
        lane.scrollArea.contentY = lane.scrollArea.contentHeight - lane.scrollArea.height
        tryCompare(aim, "startPoint", Qt.point(0, 0))
        tryCompare(aim, "visible", false)
        compare(table.combatInteraction.selectedSource, "opaque-source")
        compare(table.combatInteraction.links.length, 0)
        lane.scrollArea.contentY = 0
        mouseMove(source, source.width / 2, source.height / 2)
        tryCompare(aim, "visible", true)
        compare(aim.startPoint, table.presentation.pointFor("own-0"))
        compare(transport.responses.length, 0)
    }
    function test_focusingHoveredCombatSourceKeepsPreviewSuppressed() {
        combat("chooseAttackers", 1, true)
        const source = item("forgeCard-own-0")
        mouseClick(source)
        compare(table.combatInteraction.selectedSource, "opaque-source")
        source.forceActiveFocus()
        verify(source.activeFocus)
        verify(!source.previewActive)
        compare(table.inspector.previewCardId, "")
        verify(!item("rulesCardHoverPreview").visible)
        compare(transport.responses.length, 0)
    }
    function test_combatAimDoesNotSnapToScrolledTarget() {
        const state = snapshot()
        state.zones[5].cards = Array.from({length:70}, (_, i) => card("opponent-" + i, 1, "Attacker " + i, true))
        state.zones[5].count = state.zones[5].cards.length
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseBlockers", {
            combatSources:[{responseId:"source", objectId:"own-0", label:"Bear", name:"Grizzly Bears",
                validTargetIds:["target", "alternate"], maxAssignments:1}],
            combatTargets:[{responseId:"target", kind:"attacker", objectId:"opponent-0", label:"Attacker",
                minAssignments:0, maxAssignments:8},
                {responseId:"alternate", kind:"attacker", objectId:"opponent-69", label:"Other attacker",
                    minAssignments:0, maxAssignments:8}]
        })
        const lane = item("forgeOpponentCreatures"), target = item("forgeCard-opponent-0")
        const aim = item("forgeCombatAimArrow")
        lane.scrollArea.contentY = 0
        mouseClick(item("forgeCard-own-0"))
        mouseMove(target, target.width / 2, target.height / 2)
        tryCompare(aim, "snapped", true)
        compare(aim.endPoint, table.presentation.pointFor("opponent-0"))
        lane.scrollArea.contentY = lane.scrollArea.contentHeight - lane.scrollArea.height
        tryCompare(aim, "snapped", false)
        verify(aim.visible)
        verify(aim.endPoint.x > 0 && aim.endPoint.y > 0)
        compare(table.combatInteraction.selectedSource, "source")
        compare(table.combatInteraction.links.length, 0)
        compare(transport.responses.length, 0)
    }
    function test_multipleDefendersUseBoardAndPlayerSeat_data() {
        return [{tag:"planeswalker", kind:"planeswalker", name:"Test Walker", seat:1},
                {tag:"battle", kind:"battle", name:"Test Battle", seat:0}]
    }
    function test_multipleDefendersUseBoardAndPlayerSeat(data) {
        const state = snapshot()
        state.zones[4 + data.seat].cards.push(card("defender", data.seat, data.name, false))
        state.zones[4 + data.seat].count++
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAttackers", {combatSources:[{responseId:"source", objectId:"own-0", label:"Bear", name:"Grizzly Bears",
            validTargetIds:["player-choice", "permanent-choice"], maxAssignments:1}], combatTargets:[
                {responseId:"player-choice", kind:"player", seat:1, label:"Opponent", minAssignments:0, maxAssignments:1},
                {responseId:"permanent-choice", kind:data.kind, objectId:"defender", label:data.name, minAssignments:0, maxAssignments:1}]})
        verify(!item("forgeCard-defender").actionable)
        mouseClick(item("forgeCard-own-0"))
        verify(!item("rulesPlayerTarget0").actionable)
        verify(item("rulesPlayerTarget1").actionable)
        verify(item("forgeCard-defender").combatDestination)
        verify(!item("forgeCard-opponent").actionable)
        const aim = item("forgeCombatAimArrow")
        mouseClick(item("forgeCard-opponent"))
        compare(table.combatInteraction.selectedSource, "source")
        compare(table.combatInteraction.links.length, 0)
        // Longer decisions are hideable overlays over the stable resting
        // reservation. Exact-object navigation exposes a covered battle.
        verify(table.presentation.reveal("defender"))
        mouseMove(item("forgeCard-defender"))
        tryCompare(aim, "snapped", true)
        compare(aim.endPoint, table.presentation.pointFor("defender"))
        compare(table.combatInteraction.links.length, 0)
        mouseClick(item("forgeCard-defender"))
        tryCompare(aim, "visible", false)
        compare(table.combatInteraction.assignments.source, "permanent-choice")
        compare(table.combatInteraction.links[0].to, "defender")
        const fixed = item("forgeCombatArrow-own-0-defender")
        compare(fixed.endPoint, table.presentation.pointFor("defender"))
        mouseClick(item("forgeCard-own-0"))
        mouseClick(item("rulesPlayerTarget1"))
        compare(table.combatInteraction.assignments.source, "player-choice")
        compare(table.combatInteraction.links[0].seat, 1)
        if (item("rulesDecisionDock").collapsed)
            mouseClick(item("forgeDecisionCollapse"))
        tryVerify(() => item("rulesConfirmCombat-attackers").visible)
        mouseClick(item("rulesConfirmCombat-attackers"))
        compare(transport.responses[0].assignments, [{sourceId:"source", targetId:"player-choice"}])
    }
    function test_combatSelectionCanBeCancelledRemovedAndCleared_data() {
        return [{tag:"attackers", kind:"chooseAttackers", target:"rulesPlayerTarget1"},
                {tag:"blockers", kind:"chooseBlockers", target:"forgeCard-opponent"}]
    }
    function test_combatSelectionCanBeCancelledRemovedAndCleared(data) {
        combat(data.kind, 1, true)
        const source = item("forgeCard-own-0"), target = item(data.target), aim = item("forgeCombatAimArrow")
        mouseClick(source)
        tryCompare(aim, "visible", true)
        source.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        verify(!aim.visible)
        compare(table.combatInteraction.selectedSource, "")
        verify(item("rulesConfirmCombat-" + data.tag).enabled)
        mouseClick(source); mouseClick(source)
        verify(!aim.visible)
        compare(table.combatInteraction.selectedSource, "")
        mouseClick(source); mouseClick(target)
        compare(table.combatInteraction.links.length, 1)
        const fixed = item("forgeCombatArrow-own-0-" + (data.tag === "attackers" ? "seat-1" : "opponent"))
        const endpoint = fixed.endPoint
        mouseClick(source)
        tryCompare(aim, "visible", true)
        source.forceActiveFocus(); keyClick(Qt.Key_Escape)
        verify(!aim.visible)
        compare(fixed.endPoint, endpoint)
        compare(table.combatInteraction.links.length, 1)
        mouseClick(source)
        waitForRendering(table)
        mouseClick(item("rulesCombatCancelSelection-" + data.tag))
        verify(!aim.visible)
        compare(table.combatInteraction.selectedSource, "")
        compare(table.combatInteraction.links.length, 1)
        mouseClick(source)
        mouseClick(item("rulesCombatRemoveAssignment-" + data.tag))
        compare(table.combatInteraction.links.length, 0)
        mouseClick(source); mouseClick(target)
        mouseClick(source); mouseClick(target)
        compare(table.combatInteraction.links.length, 0)
        source.forceActiveFocus(); keyClick(Qt.Key_Space)
        target.forceActiveFocus(); keyClick(Qt.Key_Return)
        compare(table.combatInteraction.links.length, 1)
        waitForRendering(table)
        mouseClick(item("rulesCombatClear-" + data.tag))
        compare(table.combatInteraction.links.length, 0)
        mouseClick(item("rulesConfirmCombat-" + data.tag))
        compare(transport.responses[0].assignments, [])
    }
    function test_combatLegacyPlayerMappingRetainsExplicitListFallback() {
        prompt("chooseAttackers", {combatSources:[{responseId:"source", objectId:"own-0", label:"Bear", name:"Grizzly Bears",
            validTargetIds:["defender"], maxAssignments:1}], combatTargets:[
                {responseId:"defender", kind:"player", label:"Bob", minAssignments:0, maxAssignments:1}]})
        mouseClick(item("forgeCard-own-0"))
        compare(table.combatInteraction.assignments.source, "defender")
        verify(!item("rulesPlayerTarget0").actionable)
        verify(!item("rulesPlayerTarget1").actionable)
        waitForRendering(table)
        mouseClick(item("rulesCombatDetails-attackers"))
        tryVerify(() => findChild(table, "rulesCombatAssignment-source") !== null)
        compare(table.combatInteraction.selectedSource, "")
        mouseClick(item("rulesConfirmCombat-attackers"))
        compare(transport.responses[0].assignments, [{sourceId:"source", targetId:"defender"}])
    }
    function test_blockerLegalityAndMinimumsRemainAuthoritative() {
        const state = snapshot(1, 4)
        state.zones[5].cards.push(card("opponent-2", 1, "Other Attacker", true))
        state.zones[5].count++
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseBlockers", {
            combatSources:[0, 1, 2, 3].map(i => ({responseId:"source-" + i, objectId:"own-" + i,
                label:"Bear", name:"Grizzly Bears", maxAssignments:i === 3 ? 0 : 1,
                validTargetIds:i === 2 ? ["menace", "other"] : ["menace"]})),
            combatTargets:[{responseId:"menace", kind:"attacker", objectId:"opponent", label:"Menace",
                minAssignments:2, maxAssignments:2, mustReceiveIfAble:true},
                {responseId:"other", kind:"attacker", objectId:"opponent-2", label:"Other", minAssignments:0, maxAssignments:1}]
        })
        tryCompare(item("forgeOwnCreatures"), "stackCount", 1)
        verify(!table.combatInteraction.actionable("own-3"))
        showPile("own-3")
        mouseClick(item("forgeCard-own-0"))
        compare(table.combatInteraction.assignments["source-0"], "menace")
        compare(table.combatInteraction.selectedSource, "")
        verify(item("forgeCard-opponent-2").actionable, "Attacker-first selection remains available")
        verify(!item("rulesConfirmCombat-blockers").enabled, "One blocker does not meet menace")
        mouseClick(item("forgeCard-own-1"))
        verify(item("rulesConfirmCombat-blockers").enabled)
        mouseClick(item("forgeCard-own-2"))
        verify(!item("forgeCard-opponent").actionable)
        mouseClick(item("forgeCard-opponent"))
        compare(table.combatInteraction.selectedSource, "source-2")
        verify(item("forgeCard-opponent-2").actionable)
        mouseClick(item("forgeCard-opponent-2"))
        mouseClick(item("rulesConfirmCombat-blockers"))
        compare(transport.responses[0].assignments, [
            {sourceId:"source-0", targetId:"menace"}, {sourceId:"source-1", targetId:"menace"},
            {sourceId:"source-2", targetId:"other"}])
        verify(!item("forgeCard-own-0").actionable)
        mouseClick(item("forgeCard-own-0"))
        compare(table.combatInteraction.selectedSource, "")
        compare(transport.responses.length, 1)
    }
    function test_attackerFirstMultipleBlocksPreserveOtherAssignments() {
        const state = snapshot(1, 1)
        state.zones[5].cards.push(card("opponent-2", 1, "Goblin", true))
        state.zones[5].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseBlockers", {combatSources:[{responseId:"source", objectId:"own-0",
            label:"Palace Guard", name:"Palace Guard", validTargetIds:["a", "b"], maxAssignments:2}],
            combatTargets:[
                {responseId:"a", kind:"attacker", objectId:"opponent", label:"Bear", maxAssignments:1},
                {responseId:"b", kind:"attacker", objectId:"opponent-2", label:"Goblin", maxAssignments:1}]})
        for (const id of ["opponent", "opponent-2"]) {
            mouseClick(item("forgeCard-" + id))
            compare(table.combatInteraction.pendingAttacker, id)
            mouseClick(item("forgeCard-own-0"))
        }
        compare(table.combatInteraction.selectedTargets("source"), ["a", "b"])
        mouseClick(item("forgeCard-opponent"))
        mouseClick(item("forgeCard-own-0"))
        compare(table.combatInteraction.selectedTargets("source"), ["b"],
                "Removing one pair must preserve the blocker's other assignments")
        mouseClick(item("rulesConfirmCombat-blockers"))
        compare(transport.responses[0].assignments, [{sourceId:"source", targetId:"b"}])
    }
    function test_damageDialogShowsTargetsAndFitsWindow_data() {
        return [{tag:"ordered", mode:"ordered", width:1600, height:1000},
            {tag:"unordered", mode:"unordered", width:1280, height:800},
            {tag:"scaled", mode:"ordered", width:1280, height:800, scale:1.35},
            {tag:"divide-freely-compact", mode:"divideFreely", width:900, height:620}]
    }
    function test_damageDialogShowsTargetsAndFitsWindow(data) {
        window.width = data.width; window.height = data.height
        Theme.uiScale = data.scale || 1
        prompt("chooseCombatDamageAssignment", {damageSource:{objectId:"own-0", name:"Trampler", label:"Trampler"},
            damageTargets:[{responseId:"damage-target:0", kind:"card", label:"Blocker A", name:"Bear", lethalDamage:2},
                {responseId:"damage-target:1", kind:"card", label:"Blocker B", name:"Bear", lethalDamage:2},
                {responseId:"damage-target:2", kind:"player", label:"Opponent", lethalDamage:-1}], totalDamage:6,
            damageAssignmentMode:data.mode})
        const dialog = item("rulesDamageDialog")
        tryCompare(dialog, "opened", true)
        const auto = findChild(dialog, "rulesAutoAssignDamage"), confirm = findChild(dialog, "rulesConfirmDamage")
        verify(auto !== null && confirm !== null)
        compare(findChild(dialog, "rulesDamageSourceName").text, "Trampler")
        verify(!confirm.enabled)
        const candidates = findChild(dialog, "rulesDamageCandidates")
        if (data.width >= 1280) {
            tryCompare(candidates, "count", 3)
            verify(candidates.contentWidth <= candidates.width,
                   "Both blockers and the defending player must fit without scrolling")
        }
        mouseClick(auto)
        verify(confirm.enabled)
        const point = confirm.mapToItem(table, confirm.width / 2, confirm.height / 2)
        verify(point.x > 0 && point.x < table.width && point.y > 0 && point.y < table.height)
        mouseClick(confirm)
        compare(transport.responses[0].damage, [{targetId:"damage-target:0", damage:2}, {targetId:"damage-target:1", damage:2}, {targetId:"damage-target:2", damage:2}])
        verify(!confirm.enabled, "A pending response must disable repeated submission")
        transport.inRoom = false
        tryCompare(dialog, "visible", false)
        verify(!item("rulesDecisionDock").expanded, "Revoked damage must not reopen the fallback dock")
        transport.inRoom = true
        room.seatIndex = 1
        tryCompare(dialog, "visible", false)
    }
    function test_combatStateCannotCrossAuthorityOrPromptBoundaries(data) {
        combat("chooseAttackers")
        mouseClick(item("forgeCard-own-0"))
        compare(table.combatInteraction.links.length, 1)
        compare(table.combatInteraction.selectedSource, "")
        verify(!item("forgeCombatAimArrow").visible)
        if (data.tag === "disconnect") transport.inRoom = false
        else if (data.tag === "spectate") room.role = "spectator"
        else if (data.tag === "seat-change") room.seatIndex = 1
        else if (data.tag === "new-prompt") combat("chooseAttackers")
        else { const next = snapshot(); next.gameId = "next-game"; verify(testRulesPrompt.applySnapshot(next)) }
        compare(table.combatInteraction.links.length, 0)
        compare(table.combatInteraction.selectedSource, "")
        verify(!item("forgeCombatAimArrow").visible)
        compare(transport.responses.length, 0)
    }
    function test_combatSeparatesSelectedFromIdleCopies_data() {
        return [{tag:"front-ineligible", cards:2, eligible:1},
                {tag:"two-eligible", cards:2, eligible:2},
                {tag:"three-eligible", cards:3, eligible:3}]
    }
    function test_combatSeparatesSelectedFromIdleCopies(data) {
        verify(testRulesPrompt.applySnapshot(snapshot(3, data.cards)))
        prompt("chooseAttackers", {
            combatSources:Array.from({length:data.eligible}, (_, i) => ({
                responseId:"source-" + i, objectId:"own-" + i, label:"Bear", name:"Grizzly Bears",
                validTargetIds:["defender"], mustAssignIfAble:false, maxAssignments:1})),
            combatTargets:[{responseId:"defender", kind:"player", seat:1, label:"Opponent",
                minAssignments:0, maxAssignments:8}]
        })
        tryCompare(item("forgeOwnCreatures"), "stackCount", 1)
        verify(table.combatInteraction.canAct)
        const front = item("forgeCard-own-" + (data.cards - 1))
        compare(front.card.stackSize, data.cards)
        const expected = []
        for (let i = 0; i < data.eligible; ++i) {
            const source = item("forgeCard-own-" + i)
            verify(source.actionable)
            mouseClick(front)
            expected.push({sourceId:"source-" + i, targetId:"defender"})
            compare(Object.keys(table.combatInteraction.assignments).length, expected.length)
            compare(table.combatInteraction.assignments["source-" + i], "defender")
            compare(source.card.stackSize, i + 1)
            compare(item("forgeOwnCreatures").stackCount, i + 1 === data.cards ? 1 : 2)
            verify(waitForPolish(window))
        }
        const confirm = item("rulesConfirmCombat-attackers")
        const dock = item("rulesDecisionDock")
        const center = confirm.mapToItem(dock, confirm.width / 2, confirm.height / 2)
        verify(center.x >= 0 && center.y >= 0 && center.x <= dock.width && center.y <= dock.height)
        verify(confirm.enabled)
        mouseClick(confirm)
        compare(transport.responses[0].assignments, expected)
        action("playLand", "hand-0")
        tryCompare(item("forgeOwnCreatures"), "stackCount", 1)
    }
    function test_blockingRepeatedAttackersKeepsEveryCreatureReachable() {
        const state = snapshot(1, 3)
        state.zones[5].cards = [0, 1, 2].map(i => card("attacker-" + i, 1, "Cat", true))
        state.zones[5].count = 3
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseBlockers", {
            combatSources:[0, 1, 2].map(i => ({responseId:"blocker-" + i, objectId:"own-" + i,
                label:"Bear", name:"Grizzly Bears", maxAssignments:1,
                validTargetIds:["target-0", "target-1", "target-2"]})),
            combatTargets:[0, 1, 2].map(i => ({responseId:"target-" + i, objectId:"attacker-" + i,
                kind:"attacker", label:"Cat", minAssignments:1, maxAssignments:3}))
        })
        tryCompare(item("forgeOwnCreatures"), "stackCount", 1)
        tryCompare(item("forgeOpponentCreatures"), "stackCount", 1)
        for (let i = 0; i < 3; ++i) {
            mouseClick(item("forgeCard-own-" + i))
            compare(table.combatInteraction.selectedSource, "blocker-" + i)
            mouseClick(item("forgeCard-attacker-" + i))
            compare(table.combatInteraction.assignments["blocker-" + i], "target-" + i)
            verify(waitForPolish(window))
        }
        const back = item("forgeCard-own-0"), pileFront = item("forgeCard-own-2")
        compare(item("forgeOwnCreatures").stackCount, 3)
        compare(item("forgeOpponentCreatures").stackCount, 3)
        compare(back.card.stackSize, 1)
        verify(Math.abs(back.mapToItem(table, 0, 0).x - pileFront.mapToItem(table, 0, 0).x) > 20)
        mouseClick(back)
        compare(table.combatInteraction.selectedSource, "blocker-0")
        mouseClick(item("forgeCard-attacker-2"))
        compare(table.combatInteraction.assignments["blocker-0"], "target-2")
        compare(table.combatInteraction.links.filter(link => link.to === "attacker-2").length, 2)
        compare(item("forgeOwnCreatures").stackCount, 2)
        compare(item("forgeCard-own-2").card.stackSize, 2)
        mouseClick(item("rulesConfirmCombat-blockers"))
        compare(transport.responses[0].assignments.length, 3)
    }
    function test_combatParticipantsSplitFromIdleTokens_data() {
        const rows = []
        for (const seats of [2, 4])
            for (const kind of ["chooseAttackers", "chooseBlockers"])
                rows.push({tag:seats + "-players-" + kind, seats:seats, kind:kind})
        return rows
    }
    function test_combatParticipantsSplitFromIdleTokens(data) {
        const attacking = data.kind === "chooseAttackers"
        room.maxSeats = data.seats
        room.format = data.seats === 4 ? "edh" : "modern"
        const state = snapshot(1, 1)
        state.step = attacking ? "declare_attackers" : "declare_blockers"
        state.activeSeat = attacking ? 0 : 1
        for (let seat = 2; seat < data.seats; ++seat)
            state.players.push({seat:seat, name:"Player " + seat, life:40})
        const copies = Array.from({length:10}, (_, i) => token("spawn-" + i, 0, "Eldrazi Spawn", true))
        state.zones[4].cards = copies
        state.zones[4].count = copies.length
        if (!attacking) {
            state.zones[5].cards[0].attacking = true
            state.zones[5].cards[0].attackingPlayer = 0
        }
        verify(testRulesPrompt.applySnapshot(state))
        prompt(data.kind, {
            combatSources:copies.map(copy => ({responseId:"source-" + copy.id, objectId:copy.id,
                label:"Spawn", validTargetIds:["destination"], maxAssignments:1})),
            combatTargets:[{responseId:"destination", kind:attacking ? "player" : "attacker",
                objectId:attacking ? "" : "opponent", seat:1, label:"Opponent", maxAssignments:10}]
        })
        const lane = item(data.seats === 4 ? "forgeCreatures-0" : "forgeOwnCreatures")
        tryCompare(lane, "stackCount", 1)
        const front = item("forgeCard-spawn-9")
        mouseClick(front)
        tryCompare(lane, "stackCount", 2)
        const first = item("forgeCard-spawn-0")
        compare(first.card.stackSize, 1)
        compare(front.card.stackSize, 9)
        verify(first.pointerEnabled)
        verify(waitForPolish(window))
        const firstRect = first.mapToItem(lane, 0, 0, first.width, first.height)
        const idleRect = front.mapToItem(lane, 0, 0, front.width, front.height)
        // mapToItem crosses float-backed scene coordinates; touching edges
        // can differ by a few millionths of a logical pixel.
        const epsilon = 0.01
        verify(firstRect.x + firstRect.width <= idleRect.x + epsilon
            || idleRect.x + idleRect.width <= firstRect.x + epsilon
            || firstRect.y + firstRect.height <= idleRect.y + epsilon
            || idleRect.y + idleRect.height <= firstRect.y + epsilon,
            "A combat participant must have a separate visible card face")
        mouseClick(first)
        tryCompare(lane, "stackCount", 1)
        compare(table.combatInteraction.links.length, 0)
        compare(front.card.stackSize, 10)
        verify(waitForPolish(window))
        mouseClick(front)
        verify(waitForPolish(window))
        mouseClick(front)
        tryCompare(lane, "stackCount", 2)
        compare(front.card.stackSize, 8)
        compare(item("forgeCard-spawn-1").card.stackSize, 2)
        mouseClick(item("rulesConfirmCombat-" + (attacking ? "attackers" : "blockers")))
        compare(transport.responses[0].assignments.length, 2)

        for (let i = 0; i < 2; ++i) {
            if (attacking) {
                copies[i].attacking = true
                copies[i].attackingPlayer = 1
            } else copies[i].blocking = ["opponent"]
        }
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"pass", kind:"pass", label:"Pass"}]})
        tryCompare(lane, "stackCount", 2)
        compare(table.combatInteraction.links.length, 0)
        compare(first.card.stackSize, 2)
        compare(item("forgeCard-spawn-1").card.stackSize, 2)
        compare(front.card.stackSize, 8)
        if (attacking) {
            copies[0].tapped = true
            copies[1].tapped = true
            verify(testRulesPrompt.applySnapshot(state))
            verify(waitForPolish(window))
            verify(!rectsOverlap(item("forgeCard-spawn-1"), front),
                   "A spent attacking pile must not cover the idle pile's face or count badge")
        }
        room.role = "spectator"
        tryCompare(lane, "stackCount", 2)
        state.step = "main2"
        for (const copy of copies) {
            copy.attacking = false
            copy.tapped = false
            delete copy.attackingPlayer
            copy.blocking = []
        }
        state.zones[5].cards[0].attacking = false
        delete state.zones[5].cards[0].attackingPlayer
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(lane, "stackCount", 1)
        compare(front.card.stackSize, 10)
    }
    function test_blockedAttackersSeparateFromUnblockedCopies() {
        const state = snapshot(1, 3)
        state.step = "combat_damage"
        for (const creature of state.zones[4].cards.filter(row => row.power)) {
            creature.attacking = true
            creature.attackingPlayer = 1
        }
        state.zones[5].cards[0].blocking = ["own-0"]
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"pass", kind:"pass", label:"Pass"}]})
        const lane = item("forgeOwnCreatures")
        tryCompare(lane, "stackCount", 2)
        compare(item("forgeCard-own-0").card.stackSize, 1)
        compare(item("forgeCard-own-2").card.stackSize, 2)
        verify(item("forgeCardInteractionHint-own-0").text.includes("Blocked"))
        verify(!item("forgeCardInteractionHint-own-2").text.includes("Blocked"))
        // A blocker allowed to block several creatures gives both the same
        // public relationship, so those two copies can share a combat pile.
        state.zones[5].cards[0].blocking = ["own-0", "own-1"]
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(lane, "stackCount", 2)
        compare(item("forgeCard-own-1").card.stackSize, 2)
        compare(item("forgeCard-own-2").card.stackSize, 1)
        state.zones[5].cards[0].blocking = []
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(lane, "stackCount", 1)
        compare(item("forgeCard-own-2").card.stackSize, 3)
    }
    function test_expandedCombatKeepsRightmostPileClickable_data() {
        return ["chooseAttackers", "chooseBlockers"].map(kind => ({tag:kind, kind:kind}))
    }
    function test_expandedCombatKeepsRightmostPileClickable(data) {
        window.width = 1920; window.height = 1011
        const state = snapshot(7, 7, true)
        // The last pile reproduced the covered White Orchid Phantom in the
        // live Legacy game. Include another physical copy in that pile.
        state.zones[4].cards.push(card("own-7", 0, "Bear 6", true))
        state.zones[4].count++
        verify(testRulesPrompt.applySnapshot(state))
        prompt(data.kind, {
            combatSources:Array.from({length:8}, (_, i) => ({
                responseId:"source-" + i, objectId:"own-" + i, label:"Bear " + Math.min(i, 6),
                name:"Bear " + Math.min(i, 6), validTargetIds:["defender"], maxAssignments:1})),
            combatTargets:[{responseId:"defender", kind:data.kind === "chooseAttackers" ? "player" : "attacker",
                objectId:data.kind === "chooseAttackers" ? "" : "opponent", seat:1,
                label:"Opponent", minAssignments:0, maxAssignments:8}]
        })
        const front = item("forgeCard-own-7"), dock = item("rulesDecisionDock")
        tryCompare(item("forgeOwnCreatures"), "stackCount", 7)
        tryVerify(() => front.card.stackFront)
        const point = front.mapToItem(table, 0, 0)
        verify(point.x + front.width <= dock.x || point.y + front.height <= dock.y,
               "An expanded combat decision must not cover its battlefield sources")
        mouseClick(item("forgeCard-own-6"))
        mouseClick(item(data.kind === "chooseBlockers" ? "forgeCard-opponent" : "rulesPlayerTarget1"))
        compare(table.combatInteraction.assignments["source-6"], "defender")
        mouseClick(front)
        mouseClick(item(data.kind === "chooseBlockers" ? "forgeCard-opponent" : "rulesPlayerTarget1"))
        compare(table.combatInteraction.assignments["source-7"], "defender")
        mouseClick(item("rulesConfirmCombat-" + (data.kind === "chooseAttackers" ? "attackers" : "blockers")))
        compare(transport.responses[0].assignments.length, 2)
    }
    function test_compactPinnedPlayerTargetAndAttackAnchorRemainAccessible() {
        window.width=900; window.height=620; Theme.uiScale=1.5
        const state=snapshot(7,2,true)
        state.zones[5].cards[0].attacking=true
        state.zones[5].cards[0].attackingPlayer=0
        verify(testRulesPrompt.applySnapshot(state))
        table.priority.setFullControl(true)
        action("activate","own-0")
        mouseMove(table,30,70)
        waitForRendering(table)
        const source=item("forgeCard-land")
        mouseClick(source,source.width/2,source.height/2,Qt.RightButton)
        tryCompare(table.inspector,"pinnedCardId","land")
        const plate=item("rulesPlayerTarget0"), dock=item("rulesDecisionDock")
        const arrow=item("forgeRelationship-attack-opponent-")
        function assertPlayerReachable() {
            waitForRendering(table)
            verify(!rectsOverlap(plate,dock))
            for(const id of ["own-0","own-1","land"])
                verify(!rectsOverlap(plate,item("forgeCard-"+id)),"Moving the plate must not cover public cards")
            const point=plate.mapToItem(table.presentation,plate.width/2,plate.lifeCenterY)
            compare(table.presentation.playerPoint(0),point)
            tryCompare(arrow,"endPoint",point)
            verify(arrow.validAnchors)
        }
        assertPlayerReachable()
        prompt("chooseBoardTargets",{minSelections:1,maxSelections:1,
            targets:[{responseId:"self",kind:"player",seat:0,label:"Alice"}]})
        assertPlayerReachable()
        mouseClick(plate,plate.width/2,plate.lifeCenterY)
        compare(transport.responses.length,1)
        compare(transport.responses[0].targets,["self"])
    }
    function test_hoverAtRightEdgeAndDuringCombatRemainsReadOnly() {
        const state = snapshot()
        state.stack = [{id:"bolt", controllerSeat:1, identity:{name:"Lightning Bolt"}}]
        verify(testRulesPrompt.applySnapshot(state))
        combat("chooseAttackers")
        const source = item("forgeStackCard-bolt"), preview = item("rulesCardHoverPreview")
        mouseMove(source, 25, 40)
        tryCompare(preview, "visible", true)
        const origin = source.mapToItem(table, 0, 0)
        verify(preview.x + preview.width <= origin.x)
        verify(preview.x >= 0 && preview.y >= 0 && preview.y + preview.height <= table.height)
        compare(transport.responses.length, 0)
        mouseMove(item("forgeCard-own-0"), 20, 30)
        tryCompare(table.inspector, "previewCardId", "own-0")
        mouseClick(item("forgeCard-own-0"))
        mouseClick(item("rulesPlayerTarget1"))
        compare(table.combatInteraction.assignments["opaque-source"], "opaque-target")
    }
    function test_declaredAttackKeepsTheRestOfTheBoardStill() {
        window.width = 1920; window.height = 1010
        const state = stillBoard()
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        const ids = ["own-1", "own-5", "land", "land-2", "labyrinth", "walker", "opponent"]
        const baseline = boardGeometry(ids)
        const attacker = state.zones[4].cards.find(card => card.id === "own-0")
        attacker.attacking = true
        attacker.attackingPlayer = 1
        state.step = "declare_attackers"
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        compare(boardGeometry(ids), baseline, "One attacker must not reflow the other cards")
        verify(item("forgeCardInteractionHint-own-0").text.indexOf("Attacking") === 0)
    }

    function test_combatListMayOverlayTheBattlefield() {
        verify(testRulesPrompt.applySnapshot(stillBoard()))
        combat("chooseAttackers")
        const ids = ["own-0", "own-5", "land", "labyrinth", "walker", "opponent"]
        const baseline = boardGeometry(ids)
        const dock = item("rulesDecisionDock"), reservation = table.presentation.dockReservation
        verify(dock.height <= table.presentation.boardDecisionHeight + 0.5)
        mouseClick(item("rulesCombatDetails-attackers"))
        tryVerify(() => dock.listChoiceShown)
        waitForRendering(table)
        verify(dock.y < reservation.y, "The explicit assignment list may extend above the reservation")
        compare(dock.height, dock.implicitHeight)
        compare(boardGeometry(ids), baseline)
        const confirm = item("rulesConfirmCombat-attackers"), point = confirm.mapToItem(table, 0, 0)
        verify(point.y >= dock.y && point.y + confirm.height <= dock.y + dock.height + 1)
    }
    function test_blockedCombatAndSeatClicksShowWaitingCue() {
        combat("chooseAttackers")
        const source = item("forgeCard-own-0"), cue = item("forgeWaitingCue")
        mouseClick(item("rulesConfirmCombat-attackers"))
        compare(transport.responses.length, 1)
        verify(source.offered && source.waiting && !source.actionable)
        mouseClick(source)
        compare(table.combatInteraction.selectedSource, "")
        verify(cue.visible)
        prompt("chooseBoardTargets", {minSelections:1, maxSelections:1,
            targets:[{responseId:"player", kind:"player", seat:1, label:"Bob"}]})
        verify(!cue.visible)
        const plate = item("rulesPlayerTarget1")
        verify(plate.actionable)
        mouseClick(plate)
        compare(transport.responses.length, 2)
        verify(plate.offered && plate.waiting && !plate.actionable)
        mouseClick(plate)
        compare(transport.responses.length, 2)
        verify(cue.visible)
    }
    function test_hiddenCombatListCanBeShownAgain() {
        verify(testRulesPrompt.applySnapshot(stillBoard()))
        combat("chooseAttackers")
        const dock = item("rulesDecisionDock"), toggle = item("forgeDecisionCollapse")
        mouseClick(item("rulesCombatDetails-attackers"))
        tryVerify(() => dock.listChoiceShown)
        waitForRendering(table)
        verify(toggle.visible)
        mouseClick(toggle)
        waitForRendering(table)
        verify(dock.collapsed)
        verify(toggle.visible, "Show choice stays after hiding an open combat list")
        compare(toggle.text, "Show choice")
        mouseClick(toggle)
        waitForRendering(table)
        verify(!dock.collapsed)
        verify(item("rulesConfirmCombat-attackers").visible)
        compare(transport.responses.length, 0)
    }
    function test_singleDestinationAttackAssignsInOneClick() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 1)))
        prompt("chooseAttackers", {
            combatSources:[{responseId:"source-0", objectId:"own-0", label:"Bear", name:"Grizzly Bears",
                validTargetIds:["defender"], maxAssignments:1}],
            combatTargets:[{responseId:"defender", kind:"player", seat:1, label:"Opponent", maxAssignments:1}]
        })
        mouseClick(item("forgeCard-own-0"))
        compare(table.combatInteraction.assignments["source-0"], "defender")
        compare(table.combatInteraction.selectedSource, "")
        mouseClick(item("forgeCard-own-0"))
        compare(table.combatInteraction.assignments["source-0"], undefined)
    }
    function test_eitherAttackerCanBeBlockedFromTheBoard() {
        const state = snapshot(1, 2)
        state.zones[5].cards = [card("opponent", 1, "Grizzly Bears", true), card("opponent-b", 1, "Goblin", true)]
        state.zones[5].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseBlockers", {
            combatSources:[0, 1].map(i => ({responseId:"block-" + i, objectId:"own-" + i,
                label:"Bear", name:"Grizzly Bears", validTargetIds:["atk-a", "atk-b"], maxAssignments:1})),
            combatTargets:[
                {responseId:"atk-a", kind:"attacker", objectId:"opponent", label:"Attacker",
                    name:"Grizzly Bears", maxAssignments:2},
                {responseId:"atk-b", kind:"attacker", objectId:"opponent-b", label:"Goblin",
                    name:"Goblin", maxAssignments:2}]
        })
        verify(table.combatInteraction.offered("opponent"))
        verify(table.combatInteraction.offered("opponent-b"))
        mouseClick(item("forgeCard-opponent-b"))
        compare(table.combatInteraction.pendingAttacker, "opponent-b")
        mouseClick(item("forgeCard-own-0"))
        compare(table.combatInteraction.assignments["block-0"], "atk-b")
        mouseClick(item("forgeCard-own-1"))
        mouseClick(item("forgeCard-opponent"))
        compare(table.combatInteraction.assignments["block-1"], "atk-a")
    }
    function test_escapeCancelsAttackerFirstSelectionWithoutClearingBlocks() {
        const state = snapshot(1, 2)
        state.zones[5].cards = [card("opponent", 1, "Grizzly Bears", true), card("opponent-b", 1, "Goblin", true)]
        state.zones[5].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseBlockers", {
            combatSources:[0, 1].map(i => ({responseId:"block-" + i, objectId:"own-" + i,
                label:"Bear", name:"Grizzly Bears", validTargetIds:["atk-a", "atk-b"], maxAssignments:1})),
            combatTargets:[
                {responseId:"atk-a", kind:"attacker", objectId:"opponent", label:"Bear", maxAssignments:2},
                {responseId:"atk-b", kind:"attacker", objectId:"opponent-b", label:"Goblin", maxAssignments:2}]
        })
        table.forceActiveFocus()
        mouseClick(item("forgeCard-opponent"))
        mouseClick(item("forgeCard-own-0"))
        compare(table.combatInteraction.assignments["block-0"], "atk-a")
        mouseClick(item("forgeCard-opponent-b"))
        compare(table.combatInteraction.pendingAttacker, "opponent-b")
        keyClick(Qt.Key_Escape)
        compare(table.combatInteraction.pendingAttacker, "")
        compare(table.combatInteraction.assignments["block-0"], "atk-a")
        mouseClick(item("forgeCard-own-1"))
        compare(table.combatInteraction.selectedSource, "block-1")
        compare(table.combatInteraction.selectedTargets("block-1"), [])
        compare(transport.responses.length, 0)
    }
    function test_singleAttackerBlockAssignsInOneClick() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 1)))
        prompt("chooseBlockers", {
            combatSources:[{responseId:"block-0", objectId:"own-0", label:"Bear", name:"Grizzly Bears",
                validTargetIds:["atk"], maxAssignments:1}],
            combatTargets:[{responseId:"atk", kind:"card", objectId:"opponent", label:"Attacker",
                name:"Grizzly Bears", maxAssignments:1}]
        })
        mouseClick(item("forgeCard-own-0"))
        compare(table.combatInteraction.assignments["block-0"], "atk")
        compare(table.combatInteraction.selectedSource, "")
        mouseClick(item("forgeCard-own-0"))
        compare(table.combatInteraction.assignments["block-0"], undefined)
    }
    function test_blockWithAllAssignsSingleAttackerBlockers() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 2)))
        prompt("chooseBlockers", {
            combatSources:[0, 1].map(i => ({responseId:"block-" + i, objectId:"own-" + i,
                label:"Bear", name:"Grizzly Bears", validTargetIds:["atk"], maxAssignments:1})),
            combatTargets:[{responseId:"atk", kind:"card", objectId:"opponent", label:"Attacker",
                name:"Grizzly Bears", maxAssignments:2}]
        })
        mouseClick(item("rulesBlockWithAll"))
        compare(table.combatInteraction.assignments["block-0"], "atk")
        compare(table.combatInteraction.assignments["block-1"], "atk")
    }
    function test_blockWithAllLeavesChoicesWithSeveralAttackers() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 2)))
        prompt("chooseBlockers", {
            combatSources:[
                {responseId:"block-0", objectId:"own-0", label:"Bear", name:"Grizzly Bears",
                    validTargetIds:["atk"], maxAssignments:1},
                {responseId:"block-1", objectId:"own-1", label:"Bear", name:"Grizzly Bears",
                    validTargetIds:["atk", "atk-b"], maxAssignments:1}],
            combatTargets:[
                {responseId:"atk", kind:"card", objectId:"opponent", label:"Attacker",
                    name:"Grizzly Bears", maxAssignments:1},
                {responseId:"atk-b", kind:"card", objectId:"other-attacker", label:"Other",
                    name:"Other", maxAssignments:1}]
        })
        mouseClick(item("rulesBlockWithAll"))
        compare(table.combatInteraction.assignments["block-0"], "atk")
        compare(table.combatInteraction.assignments["block-1"], undefined)
    }
    function test_blockWithAllStopsWhenTheAttackerIsFull() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 2)))
        prompt("chooseBlockers", {
            combatSources:[0, 1].map(i => ({responseId:"block-" + i, objectId:"own-" + i,
                label:"Bear", name:"Grizzly Bears", validTargetIds:["atk"], maxAssignments:1})),
            combatTargets:[{responseId:"atk", kind:"card", objectId:"opponent", label:"Attacker",
                name:"Grizzly Bears", maxAssignments:1}]
        })
        mouseClick(item("rulesBlockWithAll"))
        compare(Object.keys(table.combatInteraction.assignments).length, 1)
    }
    function test_attackWithAllAssignsEveryCreature() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 2)))
        prompt("chooseAttackers", {
            combatSources:[0, 1].map(i => ({responseId:"source-" + i, objectId:"own-" + i,
                label:"Bear", name:"Grizzly Bears", validTargetIds:["defender"], maxAssignments:1})),
            combatTargets:[{responseId:"defender", kind:"player", seat:1, label:"Opponent", maxAssignments:2}]
        })
        mouseClick(item("rulesAttackWithAll"))
        compare(table.combatInteraction.assignments["source-0"], "defender")
        compare(table.combatInteraction.assignments["source-1"], "defender")
    }
    function test_attackWithAllStopsAtTheDefenderCapacity() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 3)))
        prompt("chooseAttackers", {
            combatSources:[0, 1, 2].map(i => ({responseId:"source-" + i, objectId:"own-" + i,
                label:"Bear", name:"Grizzly Bears", validTargetIds:["defender"], maxAssignments:1})),
            combatTargets:[{responseId:"defender", kind:"player", seat:1, label:"Opponent", maxAssignments:2}]
        })
        mouseClick(item("rulesAttackWithAll"))
        compare(Object.keys(table.combatInteraction.assignments).length, 2)
        compare(table.combatInteraction.assignments["source-2"], undefined)
    }
    function test_separateBlockerCanBeTargetedDirectly() {
        const state = snapshot(1, 1)
        state.step = "declare_blockers"
        state.zones[4].cards[0].attacking = true
        state.zones[4].cards[0].attackingPlayer = 1
        const blocker = card("opp-b", 1, "Grizzly Bears", true)
        blocker.blocking = ["own-0"]
        state.zones[5].cards = [card("opp-a", 1, "Grizzly Bears", true), blocker]
        state.zones[5].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseBoardTargets", {minSelections:1, maxSelections:1, targets:[
            {responseId:"t-a", kind:"card", objectId:"opp-a", label:"Grizzly Bears", name:"Grizzly Bears"},
            {responseId:"t-b", kind:"card", objectId:"opp-b", label:"Grizzly Bears", name:"Grizzly Bears"}]})
        const lane = item("forgeOpponentCreatures")
        tryCompare(lane, "stackCount", 2)
        compare(item("forgeCard-opp-b").card.stackSize, 1)
        mouseClick(item("forgeCard-opp-b"))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].targets, ["t-b"])
    }
    function test_attackWithAllNeedsAPlayerDestination() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 1)))
        prompt("chooseAttackers", {
            combatSources:[{responseId:"source-0", objectId:"own-0", label:"Bear", name:"Grizzly Bears",
                validTargetIds:["walker"], maxAssignments:1}],
            combatTargets:[{responseId:"walker", kind:"planeswalker", objectId:"missing-walker",
                label:"Walker", maxAssignments:1}]
        })
        const button = item("rulesAttackWithAll")
        verify(button.visible)
        verify(!button.enabled)
        mouseClick(button)
        compare(Object.keys(table.combatInteraction.assignments).length, 0)
        compare(table.combatInteraction.attackAllPlayers.length, 0)
    }
    function test_combatListFlagClearsWhenTheDecisionChanges() {
        verify(testRulesPrompt.applySnapshot(stillBoard()))
        combat("chooseAttackers")
        const dock = item("rulesDecisionDock")
        mouseClick(item("rulesCombatDetails-attackers"))
        tryVerify(() => dock.listChoiceShown)
        prompt("chooseBoardTargets", {minSelections:1, maxSelections:1,
            targets:[{responseId:"player", kind:"player", seat:1, label:"Bob"}]})
        tryVerify(() => !dock.listChoiceShown)
        verify(table.presentation.boardDecision)
    }
    function test_newBlockerHintIsProtectedOnItsFirstFrame() {
        window.width = 1920; window.height = 1011
        const state = snapshot(1, 3, true), opponents = state.zones[5]
        opponents.cards = ["Centaur Courser", "Colossal Dreadmaw", "Duskdale Wurm", "Rumbling Baloth"]
            .map((name, index) => card("attacker-" + index, 1, name, true))
        opponents.count = opponents.cards.length
        state.activeSeat = 1; state.prioritySeat = 0; state.step = "declare_attackers"
        opponents.cards[0].attacking = true; opponents.cards[0].attackingPlayer = 0
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        mouseMove(table, 1, 1)
        verify(waitForRendering(table))
        const board = table.presentation
        verify(board.hasVisibleArrows, "The first attack line must already be active")
        Theme.motionEnabled = true
        opponents.cards[1].attacking = true; opponents.cards[1].attackingPlayer = 0
        opponents.cards[1].tapped = true
        state.step = "declare_blockers"
        verify(testRulesPrompt.applySnapshot(state))
        // Do not use prompt(), which deliberately waits for a rendered frame.
        // Forge may publish the combat snapshot and its decision together.
        verify(testRulesPrompt.applyPrompt({roomId:"DUEL01", gameId:"duel-game", promptId:++serial,
            pending:true, supported:true, kind:"chooseBlockers", title:"Declare blockers", detail:"",
            options:[], choices:[], cards:[], targets:[], contextCards:[], contextTargets:[],
            damageTargets:[], scryDestinations:[], totalDamage:0,
            combatSources:[{responseId:"blocker", objectId:"own-0", label:"Bear", name:"Bear 0",
                validTargetIds:["attacker"], maxAssignments:1}],
            combatTargets:[{responseId:"attacker", kind:"attacker", objectId:"attacker-1",
                label:"Colossal Dreadmaw", minAssignments:0, maxAssignments:8}]}))
        const hint = item("forgeCardInteractionHint-attacker-1")
        const arrow = item("forgeRelationship-attack-attacker-1-")
        const slot = item("forgeOpponentCreatures").itemFor("attacker-1")
        compare(hint.text, "Block this creature")
        verify(arrow.visible && arrow.validAnchors)
        // An immediate capture takes the same polish/render path as the
        // native audit. It must not need an event-loop wait to protect text.
        const firstFrame = grabImage(table)
        const position = hint.mapToItem(board, 0, 0)
        arrow.visible = false
        const withoutArrow = grabImage(table)
        compare(hint.mapToItem(board, 0, 0), position,
            "The pixel comparison must use the same animation pose")
        verify(!firstFrame.equals(withoutArrow), "The real attack curve must be present")
        compare(textRegionChangedPixels(firstFrame, withoutArrow, hint), 0,
            "The newly visible blocker hint must be protected in the first frame")
        arrow.visible = true
        let movingFrames = 0
        for (let frame = 0; frame < 18; ++frame) {
            wait(16)
            grabImage(table)
            const center = slot.mapToItem(board, slot.width / 2, slot.height / 2)
            verify(Math.abs(arrow.startPoint.x - center.x) < 0.001
                && Math.abs(arrow.startPoint.y - center.y) < 0.001,
                "The attack curve must remain attached to the painted card during its glide")
            if (Math.abs(slot.visualDy) > 0.1) ++movingFrames
            const rect = hint.mapToItem(board, 0, 0, hint.width, hint.height)
            for (const interval of arrow.geometry.intervals) {
                for (let sample = 0; sample <= 300; ++sample) {
                    const t = interval[0] + (interval[1] - interval[0]) * sample / 300, u = 1 - t
                    const x = u*u*arrow.startPoint.x + 2*u*t*arrow.controlPoint.x + t*t*arrow.endPoint.x
                    const y = u*u*arrow.startPoint.y + 2*u*t*arrow.controlPoint.y + t*t*arrow.endPoint.y
                    verify(x <= rect.x + 1 || x >= rect.x + rect.width - 1
                        || y <= rect.y + 1 || y >= rect.y + rect.height - 1,
                        "A rendered attack segment must not cross the moving blocker hint")
                }
            }
        }
        verify(movingFrames > 0, "The regression must exercise real card animation")
        tryCompare(slot, "visualDy", 0)
        compare(transport.responses.length, 0)
    }
}
