// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"
import "../../qml/screens"
import "../../../../tools/ui-automation/scenarios/ForgeNecrodominanceStudy.js" as NecroStudy

// Public zone browsing, pointer/keyboard previews and pinned inspection.
ForgeDuelTestCase {
    id: testCase
    name: "ForgeDuelInspection"

    function test_decisionInspectionRetainsDraft_data() {
        return ["chooseCards", "mulliganPutBack", "revealCards", "scry", "reorder",
                "chooseDamageAssignmentOrder", "chooseCombatDamageAssignment"].map(kind => ({tag:kind, kind:kind}))
    }
    function test_decisionInspectionRetainsDraft(data) {
        const state = snapshot()
        state.zones.push({zone:"graveyard", ownerSeat:0, count:1,
            cards:[card("grave-card", 0, "Graveyard creature", true)]})
        state.zones.push({zone:"exile", ownerSeat:1, count:1,
            cards:[card("exile-card", 1, "Exiled creature", true)]})
        verify(testRulesPrompt.applySnapshot(state))
        const isDamage = data.kind === "chooseCombatDamageAssignment"
        const hasDamage = isDamage || data.kind === "chooseDamageAssignmentOrder"
        prompt(data.kind, {cards:[{id:"scry:0", name:"First card"}, {id:"scry:1", name:"Second card"}],
            minCardSelections:1, maxCardSelections:1,
            scryDestinations:data.kind === "scry" ? ["libraryTop", "libraryBottom"] : [],
            orderItems:[{responseId:"order:0", name:"First trigger"}, {responseId:"order:1", name:"Second trigger"}],
            damageSource:hasDamage ? {objectId:"own-0", name:"Trampler", label:"Trampler"} : undefined,
            totalDamage:hasDamage ? 4 : 0, damageAssignmentMode:"unordered",
            damageTargets:hasDamage ? [{responseId:"damage-target:0", kind:"card", label:"First blocker", lethalDamage:2},
                {responseId:"damage-target:1", kind:"card", label:"Second blocker", lethalDamage:2}] : []})
        const popup = item(isDamage ? "rulesDamageDialog" : "rulesCardChoiceDialog")
        tryCompare(popup, "opened", true)
        const loader = findChild(popup.contentItem, isDamage ? "rulesDamageContent" : "rulesChoiceContent")
        const content = loader.item
        verify(content !== null)
        const filter = findChild(popup.contentItem, "rulesCardFilter")
        if (filter) {
            filter.text = "Second"
            const list = findChild(popup.contentItem, data.kind === "revealCards" ? "revealCardList" : "rulesCardCandidates")
            tryCompare(list, "count", 1)
            if (data.kind !== "revealCards") {
                waitForRendering(list)
                mouseClick(list.itemAtIndex(0))
                compare(content.selectedCount, 1)
            }
        } else if (data.kind === "scry") {
            verify(content.moveCard("scry:1", 0, 1))
        } else if (isDamage) {
            mouseClick(findChild(popup.contentItem, "rulesAutoAssignDamage"))
            verify(content.validAssignment)
        } else {
            content.moveItem(0, 1)
            compare(findChild(content, "rulesOrderCandidates").model.get(0).responseId,
                data.kind === "reorder" ? "order:1" : "damage-target:1")
        }
        const draft = JSON.stringify(isDamage ? content.assignments : data.kind === "scry"
            ? content.piles : content.selectedIds || {})
        const promptId = table.rulesSession.promptId
        mouseClick(findChild(popup.contentItem, isDamage ? "rulesDamageViewBattlefield" : "rulesChoiceViewBattlefield"))
        tryCompare(popup, "visible", false)
        verify(popup.requested && popup.inspectingBattlefield)
        verify(item("rulesResumeDecision").visible)
        verify(!table.priorityInputBlocked)
        compare(transport.responses.length, 0)
        mouseMove(item("forgeCard-own-0"), 20, 20)
        verify(testRulesPrompt.applySnapshot(state))
        verify(popup.inspectingBattlefield, "Ordinary snapshots must not reopen or reset the draft")
        mouseClick(item("forgeZone-graveyard"))
        const zone = item("forgeZonePopup")
        tryCompare(zone, "opened", true)
        compare(zone.zone, "graveyard")
        compare(table.zoneCount(0, "graveyard"), 1)
        mouseClick(item("forgeCloseZonePopup"))
        tryCompare(zone, "opened", false)
        mouseClick(item("forgeOpponentZone-exile"))
        tryCompare(zone, "opened", true)
        compare(zone.ownerSeat, 1)
        compare(zone.zone, "exile")
        waitForRendering(zone.contentItem)
        const restore = findChild(zone.contentItem, "rulesResumeDecisionFromZone")
        verify(restore.mapToItem(zone.contentItem, 0, 0).y >= 0)
        const tabs = findChild(zone.contentItem, "forgeZoneTabs")
        verify(item("forgeZoneCards").y >= tabs.y + tabs.height)
        mouseClick(restore)
        tryCompare(zone, "opened", false)
        tryCompare(popup, "opened", true)
        verify(!item("rulesResumeDecision").visible)
        compare(loader.item, content, "Inspection must keep the same prompt instance alive")
        compare(table.rulesSession.promptId, promptId)
        compare(JSON.stringify(isDamage ? content.assignments : data.kind === "scry"
            ? content.piles : content.selectedIds || {}), draft)
        if (filter) compare(filter.text, "Second")
        if (["reorder", "chooseDamageAssignmentOrder"].includes(data.kind))
            compare(findChild(content, "rulesOrderCandidates").model.get(0).responseId,
                data.kind === "reorder" ? "order:1" : "damage-target:1")
        compare(transport.responses.length, 0, "Inspecting and resuming never responds to Forge")
        if (data.kind === "chooseCards" || data.kind === "mulliganPutBack") {
            mouseClick(findChild(popup.contentItem, "rulesConfirmCards"))
            compare(transport.responses[0].cards, ["scry:1"])
        } else if (data.kind === "revealCards") {
            mouseClick(findChild(popup.contentItem, "acknowledgeRevealButton"))
            compare(transport.responses[0].response, "$ack")
        }
    }
    function test_ownPlayerTargetAboveHoveredHand_data() {
        return [{tag:"seven-cards", hand:7, width:1600, height:1000},
                {tag:"crowded-desktop", hand:12, width:1920, height:1011}]
    }
    function test_ownPlayerTargetAboveHoveredHand(data) {
        window.width = data.width; window.height = data.height
        verify(testRulesPrompt.applySnapshot(snapshot(data.hand, 1)))
        prompt("chooseBoardTargets", {minSelections:1, maxSelections:2,
            targets:[{responseId:"self", kind:"player", seat:0, label:"Alice"},
                     {responseId:"opponent", kind:"player", seat:1, label:"Bob"}]})
        const plate = item("rulesPlayerTarget0")
        const hand = item("forgeHand")
        const nearest = hand.visibleCards.reduce((best, card) => {
            const point = card.mapToItem(plate, card.width / 2, 0)
            const previous = best.mapToItem(plate, best.width / 2, 0)
            return Math.abs(point.x - plate.width / 2) < Math.abs(previous.x - plate.width / 2) ? card : best
        })
        mouseMove(nearest, nearest.width / 2, nearest.height / 2)
        tryCompare(item("forgeHandSurface-" + nearest.cardId), "y", -18 * table.presentation.unit)
        mouseClick(plate, plate.width / 2, plate.lifeCenterY)
        compare(Object.keys(table.interaction.selectedTargetIds), ["self"])
        compare(transport.responses.length, 0)
    }
    function test_zonePopupClosesWhenConnectionEnds() {
        mouseClick(item("forgeZone-library"))
        const popup = item("forgeZonePopup")
        tryCompare(popup, "opened", true)
        transport.inRoom = false
        tryCompare(popup, "opened", false)
    }
    function test_hiddenLibraryUsesLiveZoneCounts_data() {
        return [{tag:"own", opponent:false, seat:0, count:50},
            {tag:"opponent", opponent:true, seat:1, count:49}]
    }
    function test_hiddenLibraryUsesLiveZoneCounts(data) {
        mouseClick(item(data.opponent ? "forgeOpponentZones" : "forgeZone-library"))
        tryCompare(item("forgeZonePopup"), "opened", true)
        waitForRendering(item("forgeZonePopup").contentItem)
        if (data.opponent) mouseClick(item("forgeZoneTab-library"))
        const lane = item("forgeZoneCards"), label = item("forgeZoneCardsCount")
        compare(lane.ownerSeat, data.seat)
        compare(lane.zone, "library")
        tryCompare(lane, "cardCount", data.count)
        compare(label.text, "Library  /  " + data.count)
        compare(lane.visibleCards.length, 0)
        verify(item("forgeZoneCardsHiddenNotice").visible)
        const state = snapshot()
        const library = state.zones.find(zone => zone.ownerSeat === data.seat && zone.zone === "library")
        const hand = state.zones.find(zone => zone.ownerSeat === data.seat && zone.zone === "hand")
        library.count--; hand.count++
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(lane, "cardCount", data.count - 1)
        compare(label.text, "Library  /  " + (data.count - 1))
        compare(item("forgePlayerZones-" + data.seat).text,
                "Hand · " + hand.count + " · Library · " + library.count)
        compare(lane.visibleCards.length, 0)
        compare(transport.responses.length, 0)
        library.count = 0
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(label, "text", "Library  /  0")
        verify(!item("forgeZoneCardsHiddenNotice").visible)
        mouseClick(item("forgeCloseZonePopup"))
        tryCompare(item("forgeZonePopup"), "visible", false)
    }
    function test_zoneCountIncludesUnidentifiedCards() {
        const state = snapshot()
        state.zones.push({zone:"exile", ownerSeat:1, count:3,
            cards:[card("known-exile", 1, "Plains", false)]})
        verify(testRulesPrompt.applySnapshot(state))
        mouseClick(item("forgeOpponentZones"))
        tryCompare(item("forgeZonePopup"), "opened", true)
        waitForRendering(item("forgeZonePopup").contentItem)
        mouseClick(item("forgeZoneTab-exile"))
        tryVerify(() => item("forgeZoneCards").visibleCards.length === 1)
        compare(item("forgeZoneCardsCount").text, "Exile  /  3")
        mouseClick(item("forgeCloseZonePopup"))
        tryCompare(item("forgeZonePopup"), "visible", false)
    }
    function test_commandZoneOnlyInDuel_data() {
        return ["standard", "pioneer", "modern", "legacy", "vintage", "pauper", "duel"].map(
            format => ({tag:format, format:format, commander:format === "duel"}))
    }
    function test_commandZoneOnlyInDuel(data) {
        room.format = data.commander ? "duel" : "modern"
        room.deckFormat = data.format
        waitForRendering(table)
        compare(findChild(table, "forgeZone-command") !== null, data.commander)
        for (const opener of ["forgeZone-library", "forgeOpponentZones"]) {
            mouseClick(item(opener))
            tryCompare(item("forgeZonePopup"), "opened", true)
            waitForRendering(item("forgeZonePopup").contentItem)
            compare(findChild(item("forgeZonePopup").contentItem, "forgeZoneTab-command") !== null, data.commander)
            if (data.commander) {
                mouseClick(item("forgeZoneTab-command"))
                compare(item("forgeZoneCards").zone, "command")
            }
            mouseClick(item("forgeCloseZonePopup"))
            tryCompare(item("forgeZonePopup"), "visible", false)
        }
    }
    function test_zonePilesOpenMatchingBrowser() {
        const own = item("forgeZone-graveyard")
        compare(own.width, Math.round(own.width))
        compare(own.height, Math.round(own.height))
        compare(own.zone, "graveyard")
        mouseClick(own)
        tryCompare(item("forgeZonePopup"), "opened", true)
        compare(item("forgeZonePopup").zone, "graveyard")
        compare(item("forgeZonePopup").ownerSeat, 0)
        mouseClick(item("forgeCloseZonePopup"))
        tryCompare(item("forgeZonePopup"), "visible", false)
        mouseClick(item("forgeOpponentZone-exile"))
        tryCompare(item("forgeZonePopup"), "opened", true)
        compare(item("forgeZonePopup").zone, "exile")
        compare(item("forgeZonePopup").ownerSeat, 1)
        mouseClick(item("forgeCloseZonePopup"))
        tryCompare(item("forgeZonePopup"), "visible", false)
    }
    function test_zonePilesShowPublicTopAndStayOffPermanentLanes() {
        const state = snapshot()
        state.zones.push({zone:"exile", ownerSeat:1, count:3,
            cards:[card("known-exile", 1, "Plains", false)]})
        state.zones.push({zone:"graveyard", ownerSeat:0, count:2,
            cards:[card("known-yard", 0, "Grizzly Bears", true)]})
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        const exile = item("forgeOpponentZone-exile")
        const yard = item("forgeZone-graveyard")
        compare(exile.count, 3)
        verify(exile.showsPublicFace)
        compare(yard.count, 2)
        verify(yard.showsPublicFace)
        verify(item("forgeZone-library").count === 50)
        verify(!item("forgeZone-library").showsPublicFace)
        const ownLand = item("forgeCard-land")
        const exilePoint = exile.mapToItem(table, 0, 0)
        const yardPoint = yard.mapToItem(table, 0, 0)
        const landPoint = ownLand.mapToItem(table, 0, 0)
        const hand = item("forgeHand")
        verify(yard.width >= 96 * table.presentation.unit)
        verify(yard.height >= 110 * table.presentation.unit)
        const yardFace = findChild(yard, "forgeZonePileFace")
        const yardArt = findChild(yard, "forgeZonePileArt")
        verify(yardFace !== null && yardArt !== null)
        compare(yardArt.fillMode, Image.PreserveAspectFit)
        verify(Math.abs(yardFace.width / yardFace.height - 63 / 88) < 0.03)
        verify(yardFace.height <= yard.height)
        verify(yardFace.width <= yard.width)
        verify(yardPoint.y >= hand.y - 4 * table.presentation.unit)
        verify(yardPoint.y + yard.height <= table.height + 1)
        verify(landPoint.y + ownLand.height <= yardPoint.y + 8 * table.presentation.unit)
        verify(exilePoint.y < table.height * 0.22)
        verify(exilePoint.x < table.width * 0.28)
    }
    function test_hoverAvoidsPublicBoardContent() {
        window.width=1920; window.height=1011
        const state=snapshot(5,4,true)
        state.players[0].manaPool=[{name:"U",value:2}]
        verify(testRulesPrompt.applySnapshot(state))
        table.forceActiveFocus()
        mouseMove(table,30,70)
        waitForRendering(table)
        const source=item("forgeHandCard-hand-2")
        mouseMove(source,source.width/2,source.height/3)
        tryCompare(table.inspector,"previewCardId","hand-2")
        const preview=item("rulesCardHoverPreview")
        tryCompare(preview,"visible",true)
        compare(preview.inspectionRequired,false)
        for (const name of ["forgeCard-own-0","forgeCard-own-1","forgeCard-own-2",
            "forgeCard-own-3","forgeCard-land","forgeCard-opponent","forgePhaseTrack",
            "rulesPlayerTarget0","rulesPlayerTarget1","forgeManaPool-0",
            "forgeOpponentZoneStrip","forgeOwnZoneStrip","rulesDecisionDock"])
            verify(!rectsOverlap(preview,item(name)),"Preview obscures "+name)
        verify(preview.placement.faceWidth>=Theme.size(180))
    }
    function test_contextKeysInspectWithoutActivating_data() {
        const rows=[]
        for (const zone of ["battlefield","hand","attachment"])
            for (const key of ["menu","shift-f10"])
                rows.push({tag:zone+"-"+key,zone:zone,key:key})
        return rows
    }
    function test_contextKeysInspectWithoutActivating(data) {
        const state=snapshot(1,2,true)
        if (data.zone==="attachment") state.zones[4].cards[1].attachedTo="own-0"
        verify(testRulesPrompt.applySnapshot(state))
        const id=data.zone==="hand"?"hand-0":data.zone==="attachment"?"own-1":"own-0"
        action(data.zone==="hand"?"playLand":"activateAbility",id)
        mouseMove(table,30,70)
        const source=item(data.zone==="hand"?"forgeHandSurface-hand-0":"forgeCard-"+id)
        source.forceActiveFocus()
        tryCompare(source,"activeFocus",true)
        keyClick(data.key==="menu"?Qt.Key_Menu:Qt.Key_F10,
            data.key==="menu"?Qt.NoModifier:Qt.ShiftModifier)
        tryCompare(table.inspector,"pinnedCardId",id)
        tryCompare(table.inspector,"previewCardId","")
        verify(item("rulesInspectionHost").visible)
        compare(transport.responses.length,0)
    }
    function test_inspectionBoundsIncludeUnclippedFanAndMergePiles() {
        verify(testRulesPrompt.applySnapshot(snapshot(1,40,false)))
        const lane=item("forgeOwnCreatures"), board=item("forgeDuelTable")
        tryCompare(lane,"stackCount",1)
        compare(lane.inspectionRects(board).length,1)
        lane.openFan(0)
        tryCompare(lane.scrollArea,"clip",true)
        // The isolated fan remains visible above the lane while unrelated
        // rows keep their viewport clipping and the scroll position changes.
        lane.scrollArea.contentY=lane.slotY(0)+20*lane.unit
        waitForRendering(lane)
        const rects=lane.inspectionRects(board)
        compare(rects.length,40)
        const viewport=lane.scrollArea.mapToItem(board,0,0,lane.scrollArea.width,lane.scrollArea.height)
        verify(rects.some(rect=>rect.y<viewport.y-5))
        lane.scrollArea.contentY=0
    }
    function test_hoverPreviewWaitsThenFades() {
        Theme.motionEnabled = true
        mouseMove(table, 30, 70)
        const source = item("forgeHandCard-hand-0")
        mouseMove(source, Math.round(source.width * 0.75), Math.round(source.height * 0.4))
        tryCompare(table.inspector, "previewCardId", "hand-0")
        const preview = item("rulesCardHoverPreview")
        tryCompare(preview, "visible", true)
        verify(preview.opacity < 1)
        tryCompare(preview, "opacity", 1)
        mouseMove(table, 30, 70)
        tryCompare(preview, "visible", false)
        Theme.motionEnabled = false
    }
    function test_keyboardPreviewFollowsLaneWheel() {
        const lane = keyboardPreviewLane(true), viewport = lane.scrollArea
        const source = item("forgeCard-own-0"), preview = item("rulesCardHoverPreview")
        const sourceBefore = source.mapToItem(preview.parent, 0, 0)
        const scrollBefore = viewport.contentY
        // Wheel the unused edge of the lane so pointer hover cannot replace
        // the keyboard-selected card's inspection.
        mouseWheel(viewport, viewport.width - 2, viewport.height / 2, 0, -60)
        tryVerify(() => viewport.contentY > scrollBefore + 5)
        tryCompare(viewport, "moving", false)
        verify(source.activeFocus)
        compare(table.inspector.previewCardId, "own-0")
        const sourceAfter = source.mapToItem(preview.parent, 0, 0)
        verify(sourceAfter.y < sourceBefore.y - 5)
        const inLane = source.mapToItem(viewport, 0, 0)
        verify(inLane.y < 0 && inLane.y + source.height > 0, "Part of the card remains visible")
        verify(preview.visible)
        tryVerify(() => Math.abs(preview.sourceGeometry.origin.y-sourceAfter.y)<0.5,
                  1000, "Focused card geometry follows its lane even when the same free area stays best")
        verify(!rectsOverlap(preview,source))
        verify(preview.x >= 0 && preview.y >= 0
            && preview.x + preview.width <= preview.parent.width
            && preview.y + preview.height <= preview.parent.height)
    }
    function test_keyboardPreviewHidesOutsideLaneAndReturns() {
        const lane = keyboardPreviewLane(), viewport = lane.scrollArea
        const source = item("forgeCard-own-0"), preview = item("rulesCardHoverPreview")
        mouseWheel(viewport, viewport.width - 2, viewport.height / 2, 0, -1200)
        tryVerify(() => source.mapToItem(viewport, 0, source.height).y <= 0)
        verify(source.activeFocus)
        tryCompare(preview, "visible", false)
        mouseWheel(viewport, viewport.width - 2, viewport.height / 2, 0, 1200)
        tryCompare(viewport, "contentY", 0)
        verify(source.activeFocus)
        tryCompare(preview, "visible", true)
        compare(table.inspector.previewCardId, "own-0")
        keyClick(Qt.Key_Tab)
        tryCompare(item("forgeCard-own-1"), "activeFocus", true)
        tryCompare(table.inspector, "previewCardId", "own-1")
        tryCompare(preview, "visible", true)
        item("forgeGameMenu").forceActiveFocus()
        tryCompare(item("forgeCard-own-1"), "activeFocus", false)
        tryCompare(preview, "visible", false)
    }
    function test_keyboardPreviewChangesFocusWhileOldCardIsClipped() {
        const lane = keyboardPreviewLane(), viewport = lane.scrollArea
        const source = item("forgeCard-own-0"), preview = item("rulesCardHoverPreview")
        mouseWheel(viewport, viewport.width - 2, viewport.height / 2, 0, -1200)
        tryVerify(() => source.mapToItem(viewport, 0, source.height).y <= 0)
        tryCompare(preview, "visible", false)
        keyClick(Qt.Key_Tab)
        const next = item("forgeCard-own-1")
        tryCompare(next, "activeFocus", true)
        tryCompare(table.inspector, "previewCardId", "own-1")
        tryCompare(preview, "visible", true)
        const point = next.mapToItem(viewport, 0, 0)
        verify(point.y >= 0 && point.y + next.height <= viewport.height)
    }
    function test_decisionDockExpansionKeepsBothAnswersVisible_data() {
        return [{tag:"desktop", width:1920, height:1011, scale:1},
            {tag:"scaled", width:1920, height:1011, scale:1.5},
            {tag:"compact", width:900, height:620, scale:1}]
    }
    function test_decisionDockExpansionKeepsBothAnswersVisible(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        wait(300) // Leave the initial window-resize suppression interval.
        Theme.motionEnabled = true
        prompt("chooseBoolean", {title:"Confirm decision",
            detail:"Isamaru, Hound of Konda: If a commander is in a graveyard or in exile and that card was put into that zone since the last time state-based actions were checked, its owner may put it into the command zone.",
            minChoiceTotal:1, maxChoiceTotal:1,
            choices:[{responseId:"choice:0", label:"No", weight:1, canRepeat:false},
                {responseId:"choice:1", label:"Yes", weight:1, canRepeat:false}]})
        waitForRendering(table)
        const dock = item("rulesDecisionDock"), scroll = item("rulesPromptScroll")
        const viewport = scroll.mapToItem(table, 0, 0)
        for (const id of ["choice:0", "choice:1"]) {
            const button = item("rulesScalarChoice-" + id), point = button.mapToItem(table, 0, 0)
            verify(button.enabled)
            verify(point.y >= viewport.y && point.y + button.height <= viewport.y + scroll.height + 1,
                   "An enabled answer must be fully visible on expansion, without waiting for the height animation")
        }
        compare(dock.height, dock.targetHeight)
    }
    function test_hoverPreviewClosesWithoutMovingTheBoard() {
        action("playLand", "hand-0")
        const lane = item("forgeOwnCreatures"), x = lane.x, width = lane.width
        mouseMove(table, 30, 70)
        tryCompare(table.inspector, "hasCard", false)
        const source = item("forgeHandCard-hand-0")
        mouseMove(source, Math.round(source.width * 0.75), Math.round(source.height * 0.4))
        tryCompare(table.inspector, "previewCardId", "hand-0")
        const preview = item("rulesCardHoverPreview")
        tryCompare(preview, "visible", true)
        const origin = source.mapToItem(table, 0, 0)
        const previewPoint = preview.mapToItem(table, 0, 0)
        verify(previewPoint.x >= origin.x + source.width || previewPoint.x + preview.width <= origin.x
               || previewPoint.y + preview.height <= origin.y)
        verify(preview.y >= 0 && preview.y + preview.height <= table.height)
        compare(findChild(preview, "rulesCardHoverLinkedCards"), null)
        compare(preview.height, preview.width * 88 / 63)
        verify(!item("rulesInspectionHost").visible)
        mouseMove(table, 30, 70)
        tryCompare(table.inspector, "hasCard", false)
        compare(item("rulesInspectionHost").visible, false)
        compare(lane.x, x); compare(lane.width, width)
    }
    function test_multifaceHoverBothFacesAreReachableAndReadOnly_data() {
        return [{tag:"duel", seats:2}, {tag:"multiplayer", seats:4}]
    }
    function test_multifaceHoverClosesOnModalOrAuthorityLoss_data() {
        return ["zone", "disconnect", "sideboard"].map(change => ({tag:change, change:change}))
    }
    function test_multifaceHoverClosesOnModalOrAuthorityLoss(data) {
        previewFaces()
        const state = snapshot()
        state.zones[4].cards[0].identity = {name:"Delver of Secrets", setCode:"ISD", collectorNumber:"51"}
        verify(testRulesPrompt.applySnapshot(state))
        mouseMove(item("forgeCard-own-0"), 20, 20)
        const preview = item("rulesCardHoverPreview")
        tryCompare(preview, "visible", true)
        if (data.change === "zone") table.presentation.openZone(0, "graveyard")
        else if (data.change === "disconnect") transport.inRoom = false
        else match.sideboarding = true
        compare(preview.visible, false)
        tryCompare(table.inspector, "previewCardId", "")
        mouseMove(table, 30, 70)
        if (data.change === "zone") item("forgeZonePopup").close()
        else if (data.change === "disconnect") transport.inRoom = true
        else match.sideboarding = false
        verify(!preview.visible, "Restoring authority must not restore the old preview")
    }
    function test_multifaceHoverBothFacesAreReachableAndReadOnly(data) {
        previewFaces()
        const state = data.seats === 2 ? snapshot() : edhSnapshot([0,1,2,3], 0)
        if (data.seats === 4) { room.format = "edh"; room.maxSeats = 4 }
        const permanent = state.zones.find(zone => zone.zone === "battlefield" && zone.ownerSeat === 0).cards[0]
        permanent.identity = {name:"Delver of Secrets", setCode:"ISD", collectorNumber:"51"}
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(table.presentation, "multiplayer", data.seats > 2)
        action("activateAbility", permanent.id)
        const authority = JSON.stringify(table.rulesSession.cardForInspection(permanent.id))
        const source = item("forgeCard-" + permanent.id)
        mouseMove(source, source.width / 2, source.height / 2)
        tryCompare(table.inspector, "previewCardId", permanent.id)
        const preview = item("rulesCardHoverPreview")
        waitForRendering(table)
        tryCompare(preview, "visible", true)
        if (preview.inspectionRequired) {
            const button=item("rulesCardHoverInspect")
            mouseMove(button)
            wait(400)
            verify(button.visible)
            mouseClick(button)
            tryCompare(table.inspector,"pinnedCardId",permanent.id)
            verifyFaceGallery(table.inspector,"rulesCardInspectorArt")
            mouseClick(item("clearRulesCardInspectorButton"))
            tryCompare(source, "activeFocus", true)
            // End keyboard inspection before checking pointer departure below.
            item("forgeGameMenu").forceActiveFocus()
        } else {
            verifyFaceGallery(preview, "rulesCardHoverPreviewArt")
            mouseMove(item("rulesCardHoverPreviewArt-1"))
            wait(400)
            verify(preview.visible)
            verify(item("rulesCardHoverPreviewArt").width >= Theme.size(180))
        }
        compare(JSON.stringify(table.rulesSession.cardForInspection(permanent.id)), authority)
        compare(transport.responses.length, 0)
        mouseMove(table, 30, 70)
        tryCompare(preview, "visible", false, 1000)
        mouseClick(source)
        compare(transport.responses, [{id:table.rulesSession.promptId, response:"opaque-play"}])
    }
    function test_multifaceHoverBothArtBodiesPassInput() {
        previewFaces()
        const state = snapshot()
        state.zones[4].cards[0].identity = {name:"Delver of Secrets", setCode:"ISD", collectorNumber:"51"}
        verify(testRulesPrompt.applySnapshot(state))
        action("activateAbility", "own-0")
        const source = item("forgeCard-own-0")
        mouseMove(source, source.width / 2, source.height / 2)
        tryCompare(table.inspector, "previewCardId", "own-0")
        const preview = item("rulesCardHoverPreview")
        verifyFaceGallery(preview, "rulesCardHoverPreviewArt")
        const target = createTemporaryObject(previewInputTargetComponent, preview.parent,
            {x:preview.x, y:preview.y, width:preview.width, height:preview.height, z:preview.z - 1})
        verify(target !== null)
        const back = item("rulesCardHoverPreviewArt-1")
        mouseMove(back)
        wait(400)
        verify(preview.visible)
        const front = item("rulesCardHoverPreviewArt")
        mouseClick(front, front.width / 2, front.height / 2, Qt.RightButton)
        mouseClick(back, back.width / 2, back.height / 2, Qt.RightButton)
        compare(target.clicks, 2)
        compare(transport.responses.length, 0)
        compare(table.inspector.card.name, "Delver of Secrets")
        table.inspector.hidePreview()
        verify(!preview.visible)
    }
    function test_multifaceHandHoverShowsBothFacesWithoutPlayingOrSelecting() {
        previewFaces()
        const state = snapshot()
        state.zones[0].cards[0].identity = {name:"Delver of Secrets", setCode:"ISD", collectorNumber:"51"}
        verify(testRulesPrompt.applySnapshot(state))
        action("cast", "hand-0")
        const slot = item("forgeHandCard-hand-0")
        const face = item("forgeHandSurface-hand-0")
        tryCompare(face, "actionable", true)
        const authority = JSON.stringify(table.rulesSession.cardForInspection("hand-0"))
        const revision = table.rulesSession.snapshotRevision
        const promptId = table.rulesSession.promptId
        mouseMove(table, 30, 70)
        mouseMove(slot, slot.width / 2, slot.height / 2)
        tryCompare(table.inspector, "previewCardId", "hand-0")
        const preview = item("rulesCardHoverPreview")
        verifyFaceGallery(preview, "rulesCardHoverPreviewArt")
        mouseMove(item("rulesCardHoverPreviewArt-1"))
        wait(400)
        verify(preview.visible)
        compare(JSON.stringify(table.rulesSession.cardForInspection("hand-0")), authority)
        compare(table.rulesSession.snapshotRevision, revision)
        compare(table.rulesSession.promptId, promptId)
        compare(slot.name, "Delver of Secrets")
        verify(!slot.faceDown)
        compare(table.inspector.pinnedCardId, "")
        compare(transport.responses.length, 0)
        verify(!transport.rulesResponsePending)
        compare(table.interaction.selectedCount, 0)
        compare(table.interaction.nativeSelectedCount, 0)
        verify(!face.selected)
        compare(slot.ghost, null)
        mouseMove(table, 30, 70)
        tryCompare(preview, "visible", false, 1000)
        compare(table.inspector.previewCardId, "")
        compare(JSON.stringify(table.rulesSession.cardForInspection("hand-0")), authority)
        compare(transport.responses.length, 0)
    }
    function test_multifaceHandReusedPreviewExpiresAfterWindowReactivation() {
        previewFaces()
        const state = snapshot()
        state.zones[4].cards[0].identity = {name:"Delver of Secrets", setCode:"ISD", collectorNumber:"51"}
        verify(testRulesPrompt.applySnapshot(state))
        action("activateAbility", "own-0")
        mouseMove(item("forgeCard-own-0"))
        tryCompare(table.inspector, "previewCardId", "own-0")
        const preview = item("rulesCardHoverPreview")
        verifyFaceGallery(preview, "rulesCardHoverPreviewArt")
        mouseMove(item("rulesCardHoverPreviewArt-1"))
        state.zones[4].cards[0].identity.name = "Insectile Aberration"
        verify(testRulesPrompt.applySnapshot(state))
        verifyFaceGallery(preview, "rulesCardHoverPreviewArt", ["Insectile Aberration", "Delver of Secrets"])
        state.zones[4].cards[0].faceDown = true
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(preview, "visible", false)
        state.zones[4].cards[0].visible = false
        verify(testRulesPrompt.applySnapshot(state))
        const handCard = state.zones[4].cards.shift()
        state.zones[4].count--
        handCard.faceDown = false
        handCard.visible = true
        handCard.identity.name = "Delver of Secrets"
        state.zones[0].cards = [handCard]
        state.zones[0].count = 1
        verify(testRulesPrompt.applySnapshot(state))
        action("cast", "own-0")
        const authority = JSON.stringify(table.rulesSession.cardForInspection("own-0"))
        mouseMove(item("forgeHandCard-own-0"))
        tryCompare(table.inspector, "previewCardId", "own-0")
        verifyFaceGallery(preview, "rulesCardHoverPreviewArt")
        mouseMove(item("rulesCardHoverPreviewArt-1"))
        wait(400)
        verify(preview.visible)
        const otherWindow = createTemporaryObject(otherWindowComponent, testCase)
        otherWindow.requestActivate()
        tryCompare(otherWindow, "active", true)
        tryCompare(window, "active", false)
        window.requestActivate()
        tryCompare(window, "active", true)
        otherWindow.close()
        mouseMove(item("rulesPlayerTarget1"))
        tryCompare(preview, "visible", false, 1000)
        compare(table.inspector.previewCardId, "")
        compare(JSON.stringify(table.rulesSession.cardForInspection("own-0")), authority)
        compare(transport.responses.length, 0)
        compare(table.interaction.selectedCount, 0)
    }
    function test_pinKeepsInspectionDuringHandReflow_data() {
        return [{tag:"right-click",method:"right-click"},
            {tag:"menu",method:"menu"},{tag:"shift-f10",method:"shift-f10"}]
    }
    function test_closeInspectionReturnsFocusToSource_data() {
        return [{tag:"hand-close",hand:true,escape:false},
            {tag:"battlefield-close",hand:false,escape:false},
            {tag:"hand-escape",hand:true,escape:true}]
    }
    function test_pinnedInspectionKeepsReadableContentAndActions_data() {
        return [{tag:"compact-scaled", width:900, height:620, scale:1.5, language:"en"},
            {tag:"compact-scaled-chinese", width:900, height:620, scale:1.5, language:"zh"},
            {tag:"laptop", width:1280, height:800, scale:1, language:"en"},
            {tag:"desktop", width:1920, height:1011, scale:1, language:"en"}]
    }
    function test_pinnedInspectionKeepsReadableContentAndActions(data) {
        window.width=data.width; window.height=data.height; Theme.uiScale=data.scale
        testTranslations.setLanguage(data.language)
        catalog.language=data.language
        catalog.names=({"Isamaru, Hound of Konda":"今田家猎犬勇丸"})
        const state=snapshot(7,2,true)
        state.zones[0].cards[0].identity={name:"Isamaru, Hound of Konda"}
        verify(testRulesPrompt.applySnapshot(state))
        table.priority.setFullControl(true)
        action("activate", "own-0")
        table.forceActiveFocus()
        mouseMove(table,30,70)
        waitForRendering(table)
        const source=item("forgeHandCard-hand-0")
        mouseMove(source,source.width*0.3,source.height*0.5)
        tryCompare(table.inspector,"previewCardId","hand-0")
        waitForRendering(table)
        const preview=item("rulesCardHoverPreview")
        tryCompare(preview,"visible",true)
        if (data.width===900) verify(preview.inspectionRequired)
        if (preview.inspectionRequired) {
            const hint=item("rulesCardHoverInspect")
            mouseMove(hint)
            wait(450)
            verify(hint.visible)
            mouseClick(hint)
        } else mouseClick(source,source.width*0.3,source.height*0.5,Qt.RightButton)
        tryCompare(table.inspector,"pinnedCardId","hand-0")
        const host=item("rulesInspectionHost")
        tryCompare(host,"visible",true)
        waitForRendering(table)
        wait(450)
        compare(table.inspector.previewCardId,"")
        verify(host.width>=Theme.size(200),"Fixed details must retain a readable column")
        const title=item("rulesCardInspectorTitle")
        const close=item("clearRulesCardInspectorButton")
        verify(title.width>=Theme.size(140),"Close must not squeeze the card name into single-character lines")
        verify(close.width>=close.implicitWidth-1)
        verify(!rectsOverlap(title,close))
        verify(title.mapToItem(host,0,0).x>=0 && close.mapToItem(host,close.width,0).x<=host.width)
        const heading=item("rulesCardInspectorStateHeading")
        verify(heading.paintedWidth<=heading.width+1,"The state heading must wrap within its column")
        verify(item("rulesCardInspectorScroll").height>=Theme.size(60))
        const dock=item("rulesDecisionDock")
        verify(!rectsOverlap(host,dock),"The readable inspector must leave decisions accessible")
        for (const name of ["rulesPlayerTarget0","forgePlayerName-0","forgePlayerZones-0"])
            verify(!rectsOverlap(item(name),dock),"Fixed inspection must not hide the player's identity or life")
        const own=item("forgeCard-own-0")
        verify(!rectsOverlap(host,own))
        verify(table.presentation.pointFor("own-0").x>0)
        compare(transport.responses.length,0)
        const pass=findChild(item("rulesActionBar"),"rulesPromptOption-$pass")
        verify(pass.visible && pass.enabled)
        verify(!rectsOverlap(host,pass))
        state.zones[0].cards[0].faceDown=true
        state.zones[0].cards[0].identity={name:"SECRET"}
        catalog.faceRequests=[]
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        verify(!table.inspector.hasIdentity)
        verify(!item("rulesCardInspectorGallery").visible)
        verify(!item("rulesCardInspectorState").text.includes("SECRET"))
        verify(!title.text.includes("SECRET"))
        verify(!catalog.faceRequests.includes("SECRET"))
        mouseClick(pass)
        compare(transport.responses.length,1)
        compare(transport.responses[0].response,"$pass")
    }
    function test_closeInspectionReturnsFocusToSource(data) {
        window.width = 1920; window.height = 1011
        verify(testRulesPrompt.applySnapshot(snapshot(7, 2, true)))
        table.forceActiveFocus()
        mouseMove(table, 30, 70)
        waitForRendering(table)
        const source = item(data.hand ? "forgeHandCard-hand-0" : "forgeCard-own-0")
        const focusItem = data.hand ? item("forgeHandSurface-hand-0") : source
        const id = data.hand ? "hand-0" : "own-0"
        mouseClick(source, source.width * 0.6, source.height * 0.3, Qt.RightButton)
        tryCompare(table.inspector, "pinnedCardId", id)
        tryCompare(item("rulesInspectionHost"), "visible", true)
        if (data.escape) keyClick(Qt.Key_Escape)
        else mouseClick(item("clearRulesCardInspectorButton"))
        tryCompare(table.inspector, "pinnedCardId", "")
        tryCompare(focusItem, "activeFocus", true)
        verify(window.activeFocusItem.visible)
        keyClick(Qt.Key_Tab)
        verify(window.activeFocusItem !== focusItem)
        verify(window.activeFocusItem.visible && window.activeFocusItem.enabled,
            "Closing details must leave a usable keyboard focus chain")
        compare(transport.responses.length, 0)
    }
    function test_inspectionAuthorityClearDoesNotRestoreSourceFocus() {
        const source = item("forgeHandSurface-hand-0")
        source.forceActiveFocus()
        keyClick(Qt.Key_Menu)
        tryCompare(table.inspector, "pinnedCardId", "hand-0")
        const focusTarget = item("forgeGameMenu")
        focusTarget.forceActiveFocus()
        verify(focusTarget.activeFocus)
        transport.inRoom = false
        tryCompare(table.inspector, "pinnedCardId", "")
        waitForRendering(table)
        verify(focusTarget.activeFocus)
        verify(!source.activeFocus)
    }
    function test_closeInspectionWithoutSourceReturnsFocusToTable() {
        mouseMove(table, 30, 70)
        table.endCardPreview()
        table.openCardDetails("land")
        compare(table.inspector.pinnedSource, null)
        mouseClick(item("clearRulesCardInspectorButton"))
        tryCompare(table.inspector, "pinnedCardId", "")
        tryVerify(() => table.activeFocus && window.activeFocusItem
            && window.activeFocusItem.visible && window.activeFocusItem.enabled)
        keyClick(Qt.Key_Tab)
        verify(window.activeFocusItem.visible && window.activeFocusItem.enabled)
        compare(transport.responses.length, 0)
    }
    function test_pinKeepsInspectionDuringHandReflow(data) {
        window.width=1920; window.height=1011
        const state=snapshot(7,2,true)
        state.zones[0].cards[0].identity={name:"Isamaru, Hound of Konda"}
        verify(testRulesPrompt.applySnapshot(state))
        table.forceActiveFocus()
        mouseMove(table,30,70)
        waitForRendering(table)
        const source=item("forgeHandCard-hand-0")
        const pointer=source.mapToItem(table,source.width*0.65,source.height*0.3)
        mouseMove(table,pointer.x,pointer.y)
        tryCompare(table.inspector,"previewCardId","hand-0")
        if (data.method==="right-click") mouseClick(table,pointer.x,pointer.y,Qt.RightButton)
        else {
            item("forgeHandSurface-hand-0").forceActiveFocus()
            keyClick(data.method==="menu"?Qt.Key_Menu:Qt.Key_F10,
                data.method==="menu"?Qt.NoModifier:Qt.ShiftModifier)
        }
        waitForRendering(table)
        wait(450)
        compare(table.inspector.pinnedCardId,"hand-0")
        compare(table.inspector.previewCardId,"")
        verify(item("rulesInspectionHost").visible)
        verify(table.presentation.pinnedHoverGuard)
        const deferred=table.presentation.deferredHover
        verify(deferred!==null && deferred.cardId!=="hand-0",
            "The changed layout must actually enter a different card under the still pointer")
        const nextId=deferred.cardId
        mouseMove(table,pointer.x+3,pointer.y)
        tryCompare(table.inspector,"previewCardId",nextId)
        compare(table.inspector.pinnedCardId,"hand-0")
        mouseMove(table,30,70)
        tryCompare(table.inspector,"previewCardId","")
        verify(item("rulesInspectionHost").visible)
        compare(table.inspector.cardId,"hand-0")
        compare(transport.responses.length,0)
    }
    function test_pinnedPointerGuardAllowsKeyboardAndResetsOnAuthorityLoss() {
        table.openCardDetails("missing-card")
        compare(table.presentation.pinnedHoverGuard,false)
        table.openCardDetails("land")
        verify(table.presentation.pinnedHoverGuard)
        item("forgeHandSurface-hand-0").forceActiveFocus()
        tryCompare(table.inspector,"previewCardId","hand-0")
        compare(table.inspector.pinnedCardId,"land")
        transport.inRoom=false
        tryCompare(table.inspector,"pinnedCardId","")
        compare(table.presentation.pinnedHoverGuard,false)
        compare(table.presentation.deferredHover,null)
        transport.inRoom=true
        item("forgeCard-own-0").forceActiveFocus()
        tryCompare(table.inspector,"previewCardId","own-0")
    }
    function test_leftClickDoesNotPinInspectionAndRightClickDoes() {
        const land = item("forgeCard-land")
        const dock = item("rulesInspectionHost")
        verify(!land.actionable)
        mouseClick(land)
        compare(table.inspector.pinnedCardId, "")
        compare(dock.visible, false)
        mouseClick(land, land.width / 2, land.height / 2, Qt.RightButton)
        tryCompare(table.inspector, "pinnedCardId", "land")
        tryCompare(dock, "visible", true)
        verify(dock.inspectionOpened)
    }
    function test_floatingPreviewPreservesOpenLogAndChatDraft() {
        action("playLand", "hand-0")
        table.setGameLogVisible(true)
        table.gameLogRail.chatInput.text = "Unsent draft"
        mouseMove(item("forgeHandCard-hand-0"), 20, 40)
        tryCompare(item("rulesCardHoverPreview"), "visible", true)
        verify(!item("rulesInspectionHost").visible)
        verify(table.gameLogRail.visible)
        verify(!table.inspector.visible)
        compare(table.gameLogRail.chatInput.text, "Unsent draft")
        mouseMove(table, 30, 70)
        tryCompare(item("rulesCardHoverPreview"), "visible", false)
        verify(table.gameLogRail.visible)
        table.gameLogRail.chatInput.text = ""
    }
    function test_privateDecisionPreviewClearsWithAuthority_data() {
        return [{tag:"disconnect"}, {tag:"spectator"}, {tag:"seat"}, {tag:"prompt"}, {tag:"game"}]
    }
    function test_privateDecisionPreviewClearsWithAuthority(data) {
        surveilPrompt()
        const context = findChild(item("rulesDecisionDock"), "rulesPromptContext")
        const source = findChild(context, "rulesPromptSourceCard")
        const preview = findChild(context, "rulesPromptCardPreview")
        mouseMove(source, 20, 30)
        tryCompare(preview, "visible", true)
        if (data.tag === "disconnect") transport.inRoom = false
        else if (data.tag === "spectator") room.role = "spectator"
        else if (data.tag === "seat") room.seatIndex = 1
        else if (data.tag === "prompt") prompt("chooseBoolean", {choices:[], minChoiceTotal:0, maxChoiceTotal:0})
        else { const state = snapshot(); state.gameId = "next-game"; verify(testRulesPrompt.applySnapshot(state)) }
        tryCompare(preview, "visible", false)
        verify(!context.visible)
    }
    function test_attachmentStripsInspectTheHoveredAndClickedObject() {
        const hostId = attachmentBoard(3, 0)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        const ids = [hostId, "attached-0", "attached-1", "attached-2"]
        for (let i = 0; i < ids.length; ++i) {
            const selected = item("forgeCard-" + ids[i])
            const y = i === 0 ? selected.height / 2 : selected.height - 8 * selected.unit
            if (i > 0)
                compare(item("forgeAttachmentName-" + ids[i]).text, selected.displayName)
            mouseMove(selected, selected.width / 2, y)
            tryCompare(table.inspector, "previewCardId", ids[i])
            mouseClick(selected, selected.width / 2, y, Qt.RightButton)
            tryCompare(table.inspector, "pinnedCardId", ids[i])
            compare(transport.responses.length, 0, "Inspecting an attachment never submits a decision")
            table.inspector.clear()
        }
    }
    function test_closingTheZoneBrowserDoesNotSwallowTheNextClick() {
        const state = snapshot()
        state.zones.push({zone:"graveyard", ownerSeat:0, count:1, cards:[card("buried", 0, "Grizzly Bears", true)]})
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"mana", kind:"activateAbility", cardId:"land", label:"Plains"},
            {responseId:"$pass", kind:"pass", label:"Pass"}]})
        Theme.motionEnabled = true
        table.presentation.openZone(0, "graveyard")
        const popup = item("forgeZonePopup")
        tryCompare(popup, "opened", true)
        compare(item("forgeCard-buried").arrivalOpacity, 1, "Opening a zone does not fade its cards in")
        popup.close()
        verify(!popup.visible, "A closing modal popup leaves at once")
        mouseClick(item("forgeCard-land"))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].response, "mana")
    }
    function test_hoverPreviewAvoidsDecisionDock() {
        window.width = 1920; window.height = 1011
        verify(testRulesPrompt.applySnapshot(snapshot(1, 8, true)))
        combat("chooseAttackers", 1, true)
        const dock = item("rulesDecisionDock")
        verify(dock.visible && dock.width > 100)
        let rightmost = item("forgeCard-own-0")
        let rightX = rightmost.mapToItem(table, 0, 0).x
        for (let i = 1; i < 8; ++i) {
            const card = item("forgeCard-own-" + i)
            const x = card.mapToItem(table, 0, 0).x
            if (x > rightX) { rightmost = card; rightX = x }
        }
        mouseMove(table, 30, 70)
        mouseMove(rightmost, rightmost.width / 2, rightmost.height / 2)
        tryCompare(table.inspector, "previewCardId", "own-" + rightmost.objectId.split("-").pop())
        const preview = item("rulesCardHoverPreview")
        tryCompare(preview, "visible", true)
        verify(!rectsOverlap(preview, dock),
               "preview " + preview.x + "," + preview.y + " " + preview.width + "x" + preview.height
               + " overlaps dock " + dock.x + "," + dock.y + " " + dock.width + "x" + dock.height)
        const origin = rightmost.mapToItem(preview.parent, 0, 0)
        verify(preview.x >= origin.x + rightmost.width - 1
               || preview.x + preview.width <= origin.x + 1
               || preview.y + preview.height <= origin.y + 1)
        verify(preview.x >= -1 && preview.y >= -1)
        verify(preview.x + preview.width <= preview.parent.width + 1)
        verify(preview.y + preview.height <= preview.parent.height + 1)
    }
}
