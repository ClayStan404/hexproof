// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"
import "../../qml/screens"
import "../../../../tools/ui-automation/scenarios/ForgeNecrodominanceStudy.js" as NecroStudy

// Phase/player text, clocks and overlays that protect public information.
ForgeDuelTestCase {
    id: testCase
    name: "ForgeDuelReadouts"

    function test_edhOpeningReclaimsPhaseSpace_data() {
        return [{tag:"three", seats:[0,2,3], local:2, width:1600, height:1000, scale:1},
            {tag:"three-small-controls", seats:[0,2,3], local:2, width:1915, height:1045, scale:0.8},
            {tag:"four", seats:[0,1,2,3], local:0, width:1600, height:1000, scale:1},
            {tag:"four-small-controls", seats:[0,1,2,3], local:2, width:1915, height:1045, scale:0.8}]
    }
    function test_edhOpeningReclaimsPhaseSpace(data) {
        room.format = "edh"; room.maxSeats = 4; room.seatIndex = data.local
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        const state = edhSnapshot(data.seats, data.local)
        for (const zone of state.zones) {
            if (zone.zone === "command") continue
            zone.cards = []; zone.count = zone.zone === "library" ? 99 : 0
        }
        state.turn = 0; state.activeSeat = -1; state.prioritySeat = data.local; state.step = "untap"
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(table.presentation, "playerSeats", data.seats)
        const board = item("forgeMultiplayerBattlefield"), track = item("forgePhaseTrack")
        const initialFields = data.seats.map(seat => item("forgeField-" + seat))
        const openingHeight = board.fieldFor(data.local).height
        const nearWidth = board.fieldFor(data.local).width
        for (const stage of ["starting-player", "mulligan", "first-turn", "next-game"]) {
            state.turn = stage === "first-turn" ? 1 : 0
            state.activeSeat = stage === "starting-player" || stage === "next-game" ? -1 : data.local
            if (stage === "next-game") state.gameId = "next-game"
            verify(testRulesPrompt.applySnapshot(state))
            verify(waitForPolish(window))
            const fields = data.seats.map(seat => item("forgeField-" + seat))
            const near = board.fieldFor(data.local), far = fields.find(field => !field.nearSide)
            compare(track.visible, stage === "first-turn")
            compare(near.width, nearWidth)
            verify(Math.abs(far.y) < 1 && Math.abs(near.y + near.height - board.height) < 1)
            if (stage !== "next-game") {
                for (let index = 0; index < fields.length; ++index)
                    compare(fields[index], initialFields[index])
            }
            if (track.visible) {
                const phaseTop = track.mapToItem(board, 0, 0).y
                verify(phaseTop >= far.y + far.height,
                       "The visible phase track must fit between the player fields")
                verify(phaseTop + track.height <= near.y)
                verify(near.height < openingHeight)
            } else {
                const upper = fields.filter(field => !field.nearSide).sort((a, b) => a.x - b.x)
                const columnGap = upper[1].x - upper[0].x - upper[0].width
                verify(Math.abs(near.y - far.y - far.height - columnGap) < 1,
                       "A hidden phase track must leave only the same narrow gutter as the columns")
                compare(near.height, openingHeight)
            }
        }
    }
    function test_phaseSnapshotsKeepTableObjects_data() {
        return [{tag:"ordinary", hand:5, creatures:3}, {tag:"crowded", hand:18, creatures:40}]
    }
    function test_phaseSnapshotsKeepTableObjects(data) {
        table.priority.setFullControl(true)
        const state = snapshot(data.hand, data.creatures)
        state.stack = [{id:"spell", controllerSeat:1, ownerSeat:1, identity:{name:"Lightning Bolt"}, text:"Deal 3 damage."}]
        verify(testRulesPrompt.applySnapshot(state))
        verify(waitForPolish(window))
        const names = ["forgeCard-own-0", "forgeCard-land", "forgeCard-opponent",
            "forgeHandSurface-hand-0", "rulesPlayerTarget0", "rulesPlayerTarget1", "forgeStackEntry-spell"]
        const objects = names.map(name => item(name))
        const lane = item("forgeOwnCreatures")
        const hand = item("forgeHand")
        lane.scrollArea.contentY = Math.max(0, lane.scrollArea.contentHeight - lane.scrollArea.height)
        hand.scrollArea.contentX = Math.max(0, hand.scrollArea.contentWidth - hand.scrollArea.width)
        const scrollY = lane.scrollArea.contentY, scrollX = hand.scrollArea.contentX
        objects[2].forceActiveFocus()
        tryVerify(() => objects[2].activeFocus)
        wait(150)
        const positions = objects.map(object => ({x:object.x, y:object.y, width:object.width, height:object.height}))
        const phases = ["begin_combat", "attackers", "blockers", "damage", "end_combat", "main2", "end"]
        for (const phase of phases) {
            state.step = phase
            state.prioritySeat = state.prioritySeat === 0 ? 1 : 0
            verify(testRulesPrompt.applySnapshot(state))
            verify(waitForPolish(window))
            for (let i = 0; i < names.length; ++i) {
                compare(item(names[i]), objects[i], "Preserve " + names[i] + " during " + phase)
                compare(objects[i].x, positions[i].x)
                compare(objects[i].y, positions[i].y)
                compare(objects[i].width, positions[i].width)
                compare(objects[i].height, positions[i].height)
            }
            compare(lane.scrollArea.contentY, scrollY)
            compare(hand.scrollArea.contentX, scrollX)
            verify(objects[2].activeFocus)
            verify(item("forgeTurnPhase").text.includes(table.stepLabel(phase)))
        }
        // Real changes must still update immediately without replacing peers.
        state.zones[4].cards[0].tapped = true
        state.zones[4].cards[0].power = "4"
        state.players[0].life = 17
        state.zones[0].cards.push(card("drawn", 0, "Plains", false))
        state.zones[0].count++
        verify(testRulesPrompt.applySnapshot(state))
        verify(waitForPolish(window))
        for (let i = 0; i < names.length; ++i) compare(item(names[i]), objects[i])
        verify(objects[0].card.tapped)
        compare(objects[0].card.power, "4")
        compare(objects[4].life, 17)
        compare(hand.visibleCards.length, data.hand + 1)
    }

    function test_sparsePileReadoutClearsObstacleAtItsBottomEdge_data() {
        return [{tag:"mana-payment", payment:true}, {tag:"combat-label", payment:false}]
    }
    function test_sparsePileReadoutClearsObstacleAtItsBottomEdge(data) {
        const state = snapshot(1, 3)
        state.zones[4].cards = state.zones[4].cards.filter(card => card.power)
        state.zones[4].count = 3
        if (!data.payment) {
            state.step = "declare_blockers"
            state.zones[4].cards.forEach(card => card.blocking = ["opponent"])
            state.zones[5].cards[0].attacking = true
            state.zones[5].cards[0].attackingPlayer = 0
        }
        verify(testRulesPrompt.applySnapshot(state))
        prompt(data.payment ? "payManaCost" : "chooseAction", {options:data.payment
            ? state.zones[4].cards.map(card => ({responseId:"pay-" + card.id,
                cardId:card.id, kind:"activateAbility", label:"Add mana"}))
            : [{responseId:"$pass", kind:"pass", label:"Pass"}]})
        const field = createTemporaryObject(pileObstacleField, window.contentItem)
        verify(field !== null)
        const lane = field.creatures
        tryCompare(lane, "stackCount", 1)
        const front = lane.visibleCards.find(slot => slot.stackFront)
        compare(front.stackSize, 3)
        const hint = findChild(front, "forgeCardInteractionHint-" + front.cardId).parent
        verify(hint.visible, "The edge probe needs a painted interaction/combat label")
        verify(waitForPolish(window))
        waitForRendering(field)
        const before = hint.mapToItem(field, 0, 0, hint.width, hint.height)
        verify(before.x + before.width > field.obstacleLeft,
            "The initial centered label reaches the future obstacle's horizontal range")
        field.obstacleTop = before.y + before.height - 1
        verify(waitForPolish(window))
        waitForRendering(field)
        const after = hint.mapToItem(field, 0, 0, hint.width, hint.height)
        verify(after.x + after.width <= field.obstacleLeft + 0.1
            || after.y + after.height <= field.obstacleTop + 0.1,
            "The complete painted label must clear the obstacle, including its bottom edge: "
            + JSON.stringify(after) + ", obstacle " + field.obstacleLeft + "," + field.obstacleTop)
        for (const rect of lane.readoutRects(field))
            verify(rect.x + rect.width <= field.obstacleLeft + 0.1
                || rect.y + rect.height <= field.obstacleTop + 0.1,
                "No visible public readout may remain under the obstacle")
    }
    function test_privateHandsAndHiddenIdentityStayRedacted() {
        const state = snapshot()
        state.zones[4].cards.push({id:"hidden", ownerSeat:1, controllerSeat:1, visible:false, faceDown:true, power:"2", toughness:"2"})
        state.zones[4].count++
        verify(testRulesPrompt.applySnapshot(state))
        const hidden = item("forgeCard-hidden")
        compare(hidden.publicFace, false)
        compare(hidden.card.name, "")
        room.role = "spectator"
        tryVerify(() => item("forgeHand").visibleCards.length === 0)
        room.spectatorsSeeHands = true
        tryVerify(() => item("forgeHand").visibleCards.length === 1)
        verify(!item("forgeHandSurface-hand-0").actionable)
        room.spectatorsSeeHands = false
        tryVerify(() => item("forgeHand").visibleCards.length === 0)
    }
    function test_unspentManaUsesDedicatedColoredReadout() {
        const state = snapshot()
        state.players[0].manaPool = [{name:"U", value:2}, {name:"R", value:1}, {name:"C", value:3}]
        verify(testRulesPrompt.applySnapshot(state))
        const pool = item("forgeManaPool-0")
        tryCompare(pool, "visible", true)
        compare(pool.manaPool.length, 3)
        compare(item("forgeMana-0-U").modelData.amount, 2)
        compare(item("forgeMana-0-C").modelData.amount, 3)
        compare(pool.parent, item("forgeDuelTable"))
        verify(pool.z > item("forgeHand").z)
        verify(pool.z > item("rulesCardHoverPreview").z)
        tryVerify(() => pool.width > item("forgeMana-0-C").width)
        state.players[0].manaPool[0].value = 1
        verify(testRulesPrompt.applySnapshot(state))
        compare(item("forgeMana-0-U").modelData.amount, 1)
        state.players[0].manaPool = []
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(pool, "visible", false)
    }
    function test_combatPileReadoutsClearStatusPhase_data() {
        return [{tag:"single-attacker", width:1920, height:1011, scale:1, attackers:1},
            {tag:"attacking-pile", width:1920, height:1011, scale:1, attackers:2},
            {tag:"scaled-pile", width:1920, height:1011, scale:1.5, attackers:2},
            {tag:"compact-pile", width:900, height:620, scale:1.5, attackers:2}]
    }
    function test_combatPileReadoutsClearStatusPhase(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        const state = snapshot(1, 3)
        state.step = "declare_blockers"; state.prioritySeat = 1
        for (let index = 0; index < data.attackers; ++index) {
            state.zones[4].cards[index].attacking = true
            state.zones[4].cards[index].attackingPlayer = 1
            state.zones[4].cards[index].tapped = true
        }
        verify(testRulesPrompt.applySnapshot(state))
        prompt("", {pending:false, supported:false})
        verify(waitForPolish(window)); verify(waitForRendering(table))
        const lane = item("forgeOwnCreatures"), track = item("forgePhaseTrack")
        const phase = track.compactMode ? item("forgeCurrentPhase") : track
        const banner = item("forgeOpponentDeciding")
        verify(banner.visible)
        for (const slot of lane.visibleCards.filter(card => card.stackFront)) {
            const prefixes = slot.stackSize > 1
                ? ["forgeCardName-", "forgeCardStackCount-"] : ["forgeCardName-"]
            for (const prefix of prefixes) {
                const label = item(prefix + slot.cardId)
                if (!label.visible) continue
                verify(!rectsOverlap(label, banner), "The deciding banner must leave " + label.objectName + " visible")
                verify(!rectsOverlap(label, phase), "The phase strip must leave " + label.objectName + " visible")
            }
        }
        const before = boardGeometry(["own-0", "own-1", "own-2"])
        state.prioritySeat = 0
        verify(testRulesPrompt.applySnapshot(state))
        verify(waitForPolish(window)); verify(waitForRendering(table))
        compare(boardGeometry(["own-0", "own-1", "own-2"]), before,
                "Changing priority cannot move or resize the combat piles")
    }
    function test_crowdedInspectionHintKeepsExactIdentityAndExpires() {
        window.width=900; window.height=620; Theme.uiScale=1.5
        room.format="edh"; room.deckFormat="commander"; room.maxSeats=4
        previewFaces()
        const state=edhSnapshot([0,1,2,3],0,2)
        state.turn=8; state.step="declare_blockers"; state.activeSeat=0; state.prioritySeat=0
        for(const player of state.players) player.name="Preview Player "+(player.seat+1)
        for(const zone of state.zones) {
            if(zone.zone==="battlefield") {
                zone.cards[0].identity={name:"Delver of Secrets"}
                zone.cards[1].identity={name:"Isamaru, Hound of Konda"}
                for(let index=0;index<2;++index) {
                    zone.cards[index].attacking=true
                    zone.cards[index].attackingPlayer=(zone.ownerSeat+index+1)%4
                }
            } else if(zone.zone==="command") {zone.cards=[];zone.count=0}
            else if(zone.zone==="hand" && zone.ownerSeat===0)
                zone.cards=Array.from({length:7},(_,index)=>card("icon-hand-"+index,0,"Plains",false))
        }
        verify(testRulesPrompt.applySnapshot(state))
        table.priority.setFullControl(true)
        prompt("chooseAction",{options:[{responseId:"$pass",kind:"pass",label:"Pass"}]})
        table.forceActiveFocus()
        mouseMove(item("forgeGameMenu"))
        waitForRendering(table)
        const source=item("forgeCard-creature-0-0"), preview=item("rulesCardHoverPreview")
        const sourceBefore=source.mapToItem(table,0,0)
        mouseMove(source,source.width/2,source.height/2)
        tryCompare(table.inspector,"previewCardId","creature-0-0")
        waitForRendering(table)
        tryCompare(preview,"visible",true)
        verify(preview.inspectionRequired,"The crowded production fixture must expose an inspection control: "
            +JSON.stringify({inspectionRequired:preview.inspectionRequired, width:preview.width, height:preview.height,
                faceWidth:preview.placement.faceWidth, x:preview.x, y:preview.y}))
        compare(source.mapToItem(table,0,0),sourceBefore)
        const button=item("rulesCardHoverInspect")
        mouseMove(button)
        wait(450)
        verify(button.visible)
        compare(table.inspector.previewCardId,"creature-0-0")
        mouseClick(button)
        tryCompare(table.inspector,"pinnedCardId","creature-0-0")
        compare(item("rulesCardInspectorGallery").faceCount,2)
        compare(transport.responses.length,0)
        mouseClick(item("clearRulesCardInspectorButton"))
        tryCompare(source,"activeFocus",true)
        mouseMove(item("forgeGameMenu"))
        item("forgeGameMenu").forceActiveFocus()
        tryCompare(table.inspector,"previewCardId","")
        mouseMove(source,source.width/2,source.height/2)
        tryCompare(preview,"visible",true)
        mouseMove(item("forgeGameMenu"))
        tryCompare(table.inspector,"previewCardId","",1000)
        verify(!preview.visible)
        const hidden=state.zones.find(zone=>zone.zone==="battlefield" && zone.ownerSeat===0).cards[0]
        hidden.faceDown=true; hidden.identity={name:"SECRET"}
        catalog.faceRequests=[]
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        mouseMove(source,source.width/2,source.height/2)
        tryCompare(preview,"visible",true)
        verify(!table.inspector.hasIdentity)
        verify(!item("rulesCardHoverPreviewGallery").visible)
        mouseMove(button)
        wait(450)
        mouseClick(button)
        tryCompare(table.inspector,"pinnedCardId","creature-0-0")
        verify(!table.inspector.hasIdentity)
        verify(!item("rulesCardInspectorGallery").visible)
        verify(!item("rulesCardInspectorTitle").text.includes("SECRET"))
        verify(!catalog.faceRequests.includes("SECRET"))
        compare(transport.responses.length,0)
    }
    function test_hoverClearsOnAuthorityLossAndHidesFaceDownIdentity() {
        action("playLand", "hand-0")
        mouseMove(item("forgeHandCard-hand-0"), 20, 40)
        tryCompare(item("rulesCardHoverPreview"), "visible", true)
        room.role = "spectator"
        tryCompare(item("rulesCardHoverPreview"), "visible", false)
        compare(table.inspector.previewCardId, "")
        const state = snapshot()
        state.zones[4].cards[0] = {id:"own-0", ownerSeat:0, controllerSeat:0, visible:false, faceDown:true,
            power:"2", toughness:"2"}
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        mouseMove(item("forgeCard-own-0"), 20, 30)
        tryCompare(table.inspector, "previewCardId", "own-0")
        tryCompare(item("rulesCardHoverPreview"), "visible", true)
        verify(!table.inspector.hasIdentity)
        compare(item("rulesCardHoverPreviewArt").source, table.cardBackSource)
        transport.inRoom = false
        tryCompare(item("rulesCardHoverPreview"), "visible", false)
    }
    function test_priorityPhaseCombatAndManaStayReadable() {
        const state = snapshot(1, 2)
        state.step = "declare_attackers"
        state.prioritySeat = 1
        state.zones[4].cards[1].attacking = true
        state.zones[4].cards[1].attackingPlayer = 1
        verify(testRulesPrompt.applySnapshot(state))
        prompt("", {pending:false, supported:false})
        const banner = item("forgeOpponentDeciding")
        tryCompare(banner, "visible", true)
        compare(item("forgeOpponentDecidingText").text, "Opponent is deciding")
        const track = item("forgePhaseTrack")
        verify(waitForPolish(window)); waitForRendering(table)
        fuzzyCompare(banner.y + banner.height / 2, table.presentation.battlefieldMiddle, 0.1,
                     "The public deciding banner remains on the central seam")
        const phasePaint = track.compactMode ? item("forgeCurrentPhase") : track
        verify(!rectsOverlap(banner, phasePaint), "The phase moves independently of the deciding banner")
        assertDuelPublicFieldAllocation()
        verifyOverlayReadoutsClear(state, banner, "The deciding banner")
        verifyOverlayReadoutsClear(state, phasePaint, "The phase strip below the deciding banner")
        assertPublicPhaseAnchor()
        const exposed = battlefieldReadoutRects(state)
        for (const id of ["own-0", "own-1"]) {
            verify(exposed.some(row => row.label.objectName === "forgeCardName-" + id),
                   "The attacking and idle copies each expose their title")
            verify(exposed.some(row => row.label.objectName === "forgeCardStats-" + id),
                   "Both separate P/T readouts remain part of the clearance check")
        }
        verify(!item("forgeRecentActions").visible)
        verify(track.y + track.height <= item("forgeHand").y)
        const attack = item("forgePhase-declare_attackers")
        const draw = item("forgePhase-draw")
        compare(attack.current, true)
        compare(draw.past, true)
        compare(item("forgePhase-end").past, false)
        const mover = item("forgeCard-own-1").parent
        const stayed = item("forgeCard-own-0").parent
        verify(mover.y < stayed.y)

        state.prioritySeat = 0
        state.step = "main1"
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        tryCompare(banner, "visible", false)
        compare(item("forgeHand").y, table.presentation.handTop)
        compare(item("forgeHandPriorityGlow").opacity, 1)
        compare(item("rulesYieldMenuButton").compact, false)
        compare(findChild(item("rulesActionBar"), "rulesPromptOption-$pass").compact, false)

        prompt("payManaCost", {title:"Pay Mana Cost: {G}",
            detail:"Forest — {T}: Add {G}.",
            contextText:"Forest — {T}: Add {G}.",
            contextCards:[{id:"context-card:0", name:"Forest"}],
            options:[{responseId:"ability", cardId:"own-0", kind:"activateAbility", label:"Forest"}]})
        compare(item("rulesPromptTitle").text, "Pay Mana Cost: {G}")
        compare(item("rulesPromptDetail").visible, false)
        compare(item("rulesPromptContext").visible, false)
        compare(item("rulesYieldMenuButton").visible, false)
        compare(item("forgeCardInteractionHint-own-0").text, "Tap for mana")
    }
    function test_lifeReadoutSettlesOnRapidChanges() {
        Theme.motionEnabled = true
        const state = snapshot()
        state.players[0].life = 17
        verify(testRulesPrompt.applySnapshot(state))
        state.players[0].life = 15
        verify(testRulesPrompt.applySnapshot(state))
        compare(item("forgeLifeDelta-0").text, "-2")
        tryCompare(item("forgeLifeValue-0"), "text", "15")
        wait(Theme.motionNormal + 60)
        compare(item("forgeLifeValue-0").text, "15")
        state.players[0].life = 12
        verify(testRulesPrompt.applySnapshot(state))
        Theme.finishMotion()
        compare(item("forgeLifeValue-0").text, "12")
        state.players[0].life = 18
        verify(testRulesPrompt.applySnapshot(state))
        Theme.motionEnabled = false
        state.players[0].life = 10
        verify(testRulesPrompt.applySnapshot(state))
        compare(item("forgeLifeValue-0").text, "10")
        wait(Theme.motionNormal + 60)
        compare(item("forgeLifeValue-0").text, "10")
    }
    function test_turnCalloutDoesNotReflowCardsOrInterceptInput() {
        window.width = 1920; window.height = 1011
        const state = snapshot()
        verify(testRulesPrompt.applySnapshot(state))
        action("activateAbility", "own-0")
        const callout = item("forgeTurnCallout")
        tryCompare(table.presentation, "width", window.width)
        verify(waitForPolish(window))
        function geometry(card) {
            const point = card.mapToItem(table, 0, 0)
            return [point.x, point.y, card.width, card.height]
        }
        const own = item("forgeCard-own-0"), opponent = item("forgeCard-opponent")
        const ownBefore = geometry(own), opponentBefore = geometry(opponent)
        state.activeSeat = 1; state.prioritySeat = 1
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(callout, "message", "Opponent's turn")
        verify(callout.visible && callout.opacity > 0)
        verify(!callout.enabled)
        compare(geometry(own), ownBefore)
        compare(geometry(opponent), opponentBefore)
        mouseClick(own)
        compare(transport.responses.length, 1)
        compare(transport.responses[0].response, "opaque-play")
    }
    function test_turnCalloutRetainsCentralComposition_data() {
        return [{tag:"own", activeSeat:0, seats:2}, {tag:"opponent", activeSeat:1, seats:2},
            {tag:"three-own", activeSeat:0, seats:3}, {tag:"three-opponent", activeSeat:2, seats:3},
            {tag:"four-own", activeSeat:0, seats:4}, {tag:"four-opponent", activeSeat:3, seats:4}]
    }
    function test_turnCalloutRetainsCentralComposition(data) {
        window.width = 1920; window.height = 1011
        const seats = Array.from({length:data.seats}, (_, index) => index)
        const state = data.seats > 2 ? edhSnapshot(seats, 0, 1) : snapshot()
        if (data.seats > 2) { room.format = "edh"; room.maxSeats = 4 }
        state.activeSeat = data.activeSeat; state.prioritySeat = data.activeSeat
        verify(testRulesPrompt.applySnapshot(state))
        const board = table.presentation, callout = item("forgeTurnCallout")
        tryCompare(board, "width", window.width)
        tryVerify(() => callout.visible && callout.opacity > 0)
        verify(waitForPolish(window))
        const centerY = data.seats === 3 ? board.battlefieldMiddle : board.height / 2
        fuzzyCompare(callout.x + callout.width / 2, board.width / 2, 1,
                     "The public turn announcement is centered on the table")
        const label = item("forgeTurnCalloutText")
        compare(label.font.pixelSize, Math.round(44 * board.unit))
        fuzzyCompare(callout.width, Math.min(board.width * 0.72, label.implicitWidth + 72 * board.unit), 0.1,
                     "Local vertical clearance preserves the public horizontal styling")
        const fullHeight = Math.min(label.implicitHeight + 36 * board.unit, board.height - 24 * board.unit)
        const originalCenter = board.mapToItem(table, board.width / 2, centerY)
        const originalRect = Qt.rect(originalCenter.x - callout.width / 2,
            originalCenter.y - fullHeight / 2, callout.width, fullHeight)
        const clearance = 2 * board.unit
        const originalOverlaps = battlefieldReadoutRects(state, true).some(readout => {
            const rect = readout.rect
            return originalRect.x < rect.x + rect.width + clearance
                && originalRect.x + originalRect.width > rect.x - clearance
                && originalRect.y < rect.y + rect.height + clearance
                && originalRect.y + originalRect.height > rect.y - clearance
        })
        if (!originalOverlaps) {
            fuzzyCompare(callout.y + callout.height / 2, centerY, 1,
                         "An unobstructed announcement retains the original center")
            fuzzyCompare(callout.height, fullHeight, 0.1,
                         "An unobstructed announcement retains the full 36-unit vertical padding")
        } else {
            fuzzyCompare(callout.height, label.implicitHeight + 4 * board.unit, 0.1,
                         "Only colliding announcements reduce their vertical padding")
            verify(Math.abs(callout.y + callout.height / 2 - centerY) <= 12 * board.unit + 1,
                   "Local clearance stays within 12 units of the public center")
        }
        if (data.seats === 4) {
            verify(!originalOverlaps, "The original four-seat center already has room")
            fuzzyCompare(callout.y + callout.height / 2, centerY, 1)
            fuzzyCompare(callout.height, fullHeight, 0.1)
        }
        // The public 12-unit seam can leave less art-to-art space than the
        // unchanged 44-unit text plus minimum padding. A transient backdrop
        // may touch art; actual names and P/T must remain completely clear.
        verifyOverlayReadoutsClear(state, callout, "The turn announcement")
        verify(!callout.enabled, "The transient announcement never intercepts input")
    }
    function test_turnCalloutReadoutCacheFollowsGeometryAndVisibility() {
        window.width = 1920; window.height = 1011
        verify(testRulesPrompt.applySnapshot(snapshot()))
        const board = table.presentation, callout = item("forgeTurnCallout")
        tryCompare(board, "width", window.width)
        function verifyPublishedReadouts() {
            verify(waitForPolish(window))
            const expected = board.collectOverlayReadouts()
            const actual = board.overlayCardReadoutRects
            compare(actual.length, expected.length)
            for (let i = 0; i < expected.length; ++i) {
                fuzzyCompare(actual[i].x, expected[i].x, 0.01)
                fuzzyCompare(actual[i].y, expected[i].y, 0.01)
                fuzzyCompare(actual[i].width, expected[i].width, 0.01)
                fuzzyCompare(actual[i].height, expected[i].height, 0.01)
            }
        }
        callout.present("Readout cache")
        verifyPublishedReadouts()
        verify(board.overlayCardReadoutRects.length > 0)
        const before = board.overlayCardReadoutRects
        window.width = 1700; window.height = 950
        window.width = 1600; window.height = 900
        tryCompare(board, "width", window.width)
        verifyPublishedReadouts()
        verify(board.overlayCardReadoutRects.some((rect, i) =>
            rect.x !== before[i].x || rect.y !== before[i].y
            || rect.width !== before[i].width || rect.height !== before[i].height))

        callout.opacity = 0
        verifyPublishedReadouts()
        compare(board.overlayCardReadoutRects.length, 0)
        // Hidden callouts stop observing card geometry. Showing one again must
        // collect the current geometry and reconnect those dependencies.
        window.width = 1800; window.height = 980
        tryCompare(board, "width", window.width)
        callout.present("Readout cache refreshed")
        verifyPublishedReadouts()
        verify(board.overlayCardReadoutRects.length > 0)
    }
    function test_publicPhaseStripKeepsSingleLineDensity_data() {
        return [{tag:"english", language:"en"}, {tag:"chinese", language:"zh"}]
    }
    function test_publicPhaseStripKeepsSingleLineDensity(data) {
        window.width = 1920; window.height = 1011
        testTranslations.setLanguage(data.language)
        verify(testRulesPrompt.applySnapshot(snapshot()))
        const track = item("forgePhaseTrack"), label = item("forgePhaseLabel-main1")
        tryCompare(table.presentation, "width", window.width)
        verify(waitForPolish(window))
        verify(!track.compactMode)
        verify(track.height <= Math.max(18 * table.presentation.unit,
                Math.ceil(label.implicitHeight) + Theme.size(6)),
               "A single-line phase strip must not reserve a second text row: " + track.height)
        verify(label.paintedHeight <= label.height + 0.1)
    }
    function test_stackTextStartsBesideTheCard() {
        const state = snapshot()
        state.stack = [{id:"bolt", controllerSeat:1, identity:{name:"Lightning Bolt"},
            text:"Deal 3 damage to any target."}]
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        const entry = item("forgeStackEntry-bolt")
        const card = item("forgeStackCard-bolt")
        const name = item("forgeStackName-bolt")
        verify(Math.abs(card.width - 86 * table.presentation.unit) <= 1,
               "Stack face width is " + card.width + " at unit " + table.presentation.unit)
        const nameAt = name.mapToItem(entry, 0, 0)
        const cardAt = card.mapToItem(entry, 0, 0)
        verify(nameAt.x >= cardAt.x + card.width - 1,
               "Name x " + nameAt.x + " starts inside the face ending at " + (cardAt.x + card.width))
        verify(nameAt.x + name.width <= entry.width + 1)
        compare(name.text, "Lightning Bolt")
    }
    function test_liveBo3Summary_data() {
        return [{tag:"host", role:"player", seat:0, expected:"Game 2 · 1–0"},
            {tag:"opponent", role:"player", seat:1, expected:"Game 2 · 0–1"},
            {tag:"spectator", role:"spectator", seat:-1, expected:"Game 2 · 1–0"}]
    }
    function test_liveBo3Summary(data) {
        room.role = data.role; room.seatIndex = data.seat
        room.matchMode = "bo3"; match.gameNumber = 2; match.score = [1, 0]
        waitForRendering(table)
        const summary = item("forgeMatchSummary")
        verify(summary.visible)
        compare(item("forgeMatchSummaryText").text, data.expected)
        const settings = item("forgeGameMenu")
        verify(summary.y >= settings.y + settings.height)
        verify(summary.x + summary.width <= table.width)
        const plate = item("rulesPlayerTarget1")
        verify(summary.x >= plate.x + plate.width,
               "Match score must not cover opponent identity, life or action clock")
        match.gameNumber = 3; match.score = [1, 1]
        tryCompare(item("forgeMatchSummaryText"), "text", "Game 3 · 1–1")
        match.sideboarding = true
        tryCompare(summary, "visible", false)
        match.sideboarding = false
        tryCompare(summary, "visible", true)
        room.matchMode = "bo1"
        tryCompare(summary, "visible", false)
    }
    function test_liveBo3SummaryDoesNotReserveMultiplayerFields() {
        room.matchMode = "bo3"
        room.format = "edh"; room.deckFormat = "commander"; room.maxSeats = 4
        verify(testRulesPrompt.applySnapshot(edhSnapshot([0, 1, 2, 3], 0)))
        tryCompare(table.presentation, "multiplayer", true)
        verify(!item("forgeMatchSummary").visible)
    }
    function test_liveBo3SummaryKeepsClockAndDefaultStackClear_data() {
        return [{tag:"maximized-scale-100", width:1920, height:1011, scale:1},
            {tag:"maximized-scale-150", width:1920, height:1011, scale:1.5},
            {tag:"compact", width:1024, height:768, scale:1}]
    }
    function test_liveBo3SummaryKeepsClockAndDefaultStackClear(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        room.matchMode = "bo3"; room.actionClockEnabled = true
        room.actionClockMs = [60000, 60000]; room.actionClockRunning = 0
        const state = snapshot()
        state.stack = [{id:"bo3-stack", controllerSeat:1, identity:{name:"Lightning Bolt"},
            text:"Deal 3 damage to any target."}]
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        const summary = item("forgeMatchSummary")
        const opponent = item("rulesPlayerTarget1")
        const stack = item("forgeStack")
        verify(summary.visible)
        verify(summary.x >= opponent.x + opponent.width)
        verify(summary.y + summary.height <= stack.y,
               "Default floating stack must not cover the BO3 score")
        verify(summary.y + summary.height <= table.height)
    }
    function test_playerIdentityStaysAboveLifeDisc_data() {
        const rows = []
        for (const role of [{role:"player", seat:0}, {role:"player", seat:1},
                            {role:"spectator", seat:-1}])
            for (const clock of [false, true])
                for (const scale of [1, 1.5])
                    rows.push({tag:role.role + "-" + role.seat + "-clock-" + clock + "-scale-" + scale,
                        role:role.role, seat:role.seat, clock:clock, scale:scale})
        return rows
    }
    function test_farLifePlateStaysClearOfDenseSupportRows_data() {
        return [{tag:"maximized", width:1920, height:1011, scale:1},
            {tag:"maximized-large-controls", width:1920, height:1011, scale:1.8},
            {tag:"compact-large-controls", width:900, height:620, scale:1.8}]
    }
    function test_farLifePlateStaysClearOfDenseSupportRows(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        testTranslations.setLanguage("zh")
        room.actionClockEnabled = true
        room.actionClockMs = [180000, 165000]
        const state = snapshot()
        state.players[1].name = "中文名字较长的远端玩家"
        const permanents = [], types = {}
        for (let index = 0; index < 64; ++index)
            permanents.push(card("far-creature-" + index, 1, "Creature " + index, true))
        for (const type of ["Land", "Artifact"])
            for (let index = 0; index < 12; ++index) {
                const name = type + " " + index
                types[name] = type
                permanents.push(card("far-" + type + "-" + index, 1, name, false))
            }
        catalog.typeOverrides = types
        state.zones[5].cards = permanents
        state.zones[5].count = permanents.length
        verify(testRulesPrompt.applySnapshot(state))
        verify(waitForPolish(window)); verify(waitForRendering(table))
        const plate = item("rulesPlayerTarget1")
        const faces = item("forgeOpponentCreatures").visibleCards.concat(
            item("forgeOpponentLands").visibleCards, item("forgeOpponentOther").visibleCards)
        compare(faces.length, permanents.length)
        for (const face of faces)
            verify(!rectsOverlap(plate, face),
                "The far identity, reserved life-change area and disc must stay clear of " + face.cardId)
    }
    function test_playerIdentityStaysAboveLifeDisc(data) {
        window.width = 1920; window.height = 1011; Theme.uiScale = data.scale
        room.role = data.role; room.seatIndex = data.seat
        room.actionClockEnabled = data.clock
        room.actionClockMs = [180000, 165000]; room.actionClockRunning = -1
        waitForRendering(table)
        function checkPlates(clockVisible) {
            for (const seat of [0, 1]) {
                const plate = item("rulesPlayerTarget" + seat)
                const disc = item("forgeLifeDisc-" + seat)
                const clock = item("forgeActionClock-" + seat)
                compare(clock.visible, clockVisible)
                for (const name of ["forgePlayerName-", "forgeActionClock-", "forgePlayerZones-"]) {
                    const row = item(name + seat)
                    if (!row.visible) continue
                    verify(!rectsOverlap(row, disc), name + seat + " overlaps the life disc")
                    const at = row.mapToItem(plate, 0, 0)
                    verify(at.y >= 0 && at.y + row.height <= disc.y,
                           "Every visible identity row must end above the life disc")
                }
                const at = disc.mapToItem(plate, 0, 0)
                verify(at.x >= 0 && at.y >= 0)
                verify(at.x + disc.width <= plate.width + 0.5)
                verify(at.y + disc.height <= plate.height + 0.5,
                       "The player target must contain its entire life disc")
                compare(plate.lifeCenterY, at.y + disc.height / 2)
                const absolute = plate.mapToItem(table, 0, 0)
                verify(absolute.x >= 0 && absolute.y >= 0)
                verify(absolute.x + plate.width <= table.width + 0.5)
                verify(absolute.y + plate.height <= table.height + 0.5)
            }
        }
        checkPlates(data.clock)
        // A room projection can turn public clocks on or off in the same
        // presentation. Both identities must reflow with the changed row.
        room.actionClockEnabled = !data.clock
        waitForRendering(table)
        checkPlates(!data.clock)
        if (data.role === "player") {
            const far = item("rulesPlayerTarget" + table.presentation.topSeat)
            prompt("chooseBoardTargets", {minSelections:1, maxSelections:1,
                targets:[{responseId:"far-player", kind:"player", seat:far.seat, label:far.name}]})
            mouseClick(far, far.width / 2, far.lifeCenterY)
            compare(transport.responses.length, 1)
            compare(transport.responses[0].targets, ["far-player"])
        }
    }
    function test_ownNameSitsAboveTheHand() {
        verify(testRulesPrompt.applySnapshot(snapshot()))
        waitForRendering(table)
        const zones = item("forgePlayerZones-0")
        const hand = item("forgeHand")
        const zonesBottom = zones.mapToItem(table, 0, zones.height).y
        verify(zonesBottom <= hand.y + 1,
               "Own identity ends at " + zonesBottom + " inside the hand at " + hand.y)
        const plate = item("rulesPlayerTarget0")
        verify(plate.y + plate.height > hand.y + 1, "Life disc should still meet the hand")
        verify(plate.y + plate.height <= hand.y + 26 * table.presentation.unit + 1,
               "Life disc covers the hand faces")
        const track = item("forgePhaseTrack")
        verify(item("forgePlayerName-1").mapToItem(table, 0, 0).y + item("forgePlayerName-1").height
               <= track.y + 1)
    }
    function test_phaseLabelsStayReadableAtScaledSizes_data() {
        return [{tag:"wide-english", width:1920, height:1011, scale:1.25, seats:2, pin:false, language:"en"},
            {tag:"wide-chinese", width:1920, height:1011, scale:1.25, seats:2, pin:false, language:"zh"},
            {tag:"compact-pin", width:900, height:620, scale:1.5, seats:2, pin:true, language:"en"},
            {tag:"compact-pin-chinese", width:900, height:620, scale:1.5, seats:2, pin:true, language:"zh"},
            {tag:"compact-pin-german", width:900, height:620, scale:1.5, seats:2, pin:true, language:"de"},
            {tag:"four-normal", width:1920, height:1011, scale:1, seats:4, pin:false, language:"en"},
            {tag:"four-scaled-pin", width:1920, height:1011, scale:1.9, seats:4, pin:true, language:"en"}]
    }
    function test_phaseLabelsStayReadableAtScaledSizes(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        testTranslations.setLanguage(data.language)
        const state = data.seats === 4 ? edhSnapshot([0,1,2,3], 0, 1) : snapshot(1, 1)
        if (data.seats === 4) { room.format = "edh"; room.maxSeats = 4 }
        state.activeSeat = 0; state.prioritySeat = 0
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        if (data.pin) table.openCardDetails(data.seats === 4 ? "creature-0-0" : "own-0")
        verify(waitForPolish(window))
        const track = item("forgePhaseTrack")
        const steps = ["untap", "upkeep", "draw", "main1", "begin_combat", "declare_attackers",
            "declare_blockers", "combat_damage", "end_combat", "main2", "end", "cleanup"]
        // These assertions inspect polished layout properties. An unchanged
        // phase scene need not render another frame before they can be checked.
        const phaseHeight = track.height
        const bandHeight = table.presentation.centerBandHeight
        verify(track.width > 0)
        verify(bandHeight < table.height * 0.25, "Phase information must not consume the battlefield")
        function assertLabel(label) {
            verify(label.visible, "The phase label must remain visible")
            verify(label.font.pixelSize >= Theme.fontSize(11), "Phase text must keep a readable scaled font")
            verify(!label.truncated, "The phase name must not be elided")
            verify(label.paintedWidth <= label.width + 0.5 && label.paintedHeight <= label.height + 0.5,
                   "The complete phase name must fit: " + label.text + " painted " + label.paintedWidth + "×"
                   + label.paintedHeight + " in " + label.width + "×" + label.height)
        }
        for (let index = 0; index < steps.length; ++index) {
            state.step = steps[index]
            verify(testRulesPrompt.applySnapshot(state))
            verify(waitForPolish(window))
            compare(track.height, phaseHeight, "Changing phases must not move the battlefield")
            compare(table.presentation.centerBandHeight, bandHeight)
            if (track.compactMode) {
                const current = item("forgeCurrentPhaseLabel")
                compare(current.text, I18n.gamePhaseLabel(steps[index]))
                assertLabel(current)
            } else {
                for (const step of steps) {
                    const cell = item("forgePhase-" + step)
                    const label = cell.children.find(child => typeof child.text === "string")
                    assertLabel(label)
                    compare(label.text, I18n.gamePhaseLabel(step))
                    compare(cell.current, step === steps[index])
                    verify(cell.x >= 0 && cell.x + cell.width <= track.width + 0.5)
                }
            }
        }
        if (track.compactMode) {
            // Advancing the fixture through priority steps may run its
            // existing automatic pass policy before the overview opens.
            const responseCount = transport.responses.length
            const disclosure = item("forgeCurrentPhase")
            const overview = item("forgePhaseOverview")
            disclosure.forceActiveFocus(); keyClick(Qt.Key_Return)
            tryCompare(overview, "opened", true)
            tryCompare(table.presentation, "modalOpen", true)
            compare(transport.responses.length, responseCount)
            verify(!item("rulesCardHoverPreview").visible)
            const list = findChild(overview.contentItem, "forgePhaseOverviewList")
            verify(list !== null)
            compare(list.count, steps.length)
            try {
                for (let index = 0; index < steps.length; ++index) {
                    state.step = steps[index]
                    verify(testRulesPrompt.applySnapshot(state))
                    tryCompare(list, "currentIndex", index)
                    verify(waitForPolish(window))
                    const label = findChild(list, "forgePhaseOverviewLabel-" + steps[index])
                    verify(label !== null)
                    compare(label.text, table.stepLabel(steps[index]))
                    assertLabel(label)
                    const at = label.mapToItem(list, 0, 0)
                    verify(at.y >= -0.5 && at.y + label.height <= list.height + 0.5,
                           "The current phase must remain visible in the read-only overview")
                    mouseClick(label)
                    compare(transport.responses.length, responseCount, "Viewing phases must not submit a game response")
                }
                keyClick(Qt.Key_Escape)
                tryCompare(overview, "visible", false)
                compare(table.rulesSession.step, "cleanup")
                compare(transport.responses.length, responseCount)
            } finally { overview.close() }
        }
    }
    function test_phaseOverviewClosesWithItsTableContext_data() {
        return [{tag:"disconnect"}, {tag:"viewer"}, {tag:"new-game"}, {tag:"opening"}, {tag:"sideboarding"}]
    }
    function test_phaseOverviewClosesWithItsTableContext(data) {
        window.width = 900; window.height = 620; Theme.uiScale = 1.5
        const state = snapshot(1, 1)
        verify(testRulesPrompt.applySnapshot(state))
        table.openCardDetails("own-0")
        waitForRendering(table)
        verify(item("forgePhaseTrack").compactMode)
        const overview = item("forgePhaseOverview")
        mouseClick(item("forgeCurrentPhase"))
        tryCompare(overview, "opened", true)
        try {
            if (data.tag === "disconnect") transport.inRoom = false
            else if (data.tag === "viewer") room.seatIndex = 1
            else if (data.tag === "sideboarding") match.sideboarding = true
            else {
                if (data.tag === "new-game") state.gameId = "phase-overview-next-game"
                else { state.turn = 0; state.activeSeat = -1 }
                verify(testRulesPrompt.applySnapshot(state))
            }
            tryCompare(overview, "visible", false)
            compare(table.presentation.modalOpen, false)
        } finally { overview.close() }
    }
    function test_combatLinesKeepPhaseAndPlayerTextReadable_data() {
        return [{tag:"normal", width:1920, height:1011, scale:1, seats:2, pin:false},
            {tag:"compact-pin", width:900, height:620, scale:1.5, seats:2, pin:true},
            {tag:"four-scaled", width:1920, height:1011, scale:1.9, seats:4, pin:false},
            {tag:"opponent-deciding", width:1920, height:1011, scale:1, seats:2, pin:false, deciding:true}]
    }
    function test_combatLinesKeepPhaseAndPlayerTextReadable(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        const state = data.seats === 4 ? edhSnapshot([0,1,2,3], 0, 1) : snapshot(1, 1)
        if (data.seats === 4) { room.format = "edh"; room.maxSeats = 4 }
        const attackingSeat = data.seats === 4 ? 2 : 1
        const attacker = state.zones.find(zone => zone.ownerSeat === attackingSeat && zone.zone === "battlefield").cards[0]
        attacker.attacking = true; attacker.attackingPlayer = 0
        state.activeSeat = 0; state.prioritySeat = data.deciding ? 1 : 0; state.step = "declare_blockers"
        verify(testRulesPrompt.applySnapshot(state))
        if (data.deciding) prompt("", {pending:false, supported:false})
        else prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        testGameTable.applySnapshot({log:[{id:1, kind:"cast", text:"Plains tapped", seat:1}]})
        if (data.pin) table.openCardDetails("own-0")
        mouseMove(table, 1, 1)
        renderTable()
        const arrow = item("forgeRelationship-attack-" + attacker.id + "-")
        verify(arrow.visible && arrow.validAnchors)
        const endpoint = arrow.endPoint
        compare(endpoint, table.presentation.playerPoint(0))
        // Compare the arrow only after the independent transient announcement
        // has finished; its fade is not a change in arrow/text layering.
        tryCompare(item("forgeTurnCallout"), "visible", false, 5000)
        renderTable()
        const withArrow = grabImage(table)
        arrow.visible = false
        renderTable()
        const withoutArrow = grabImage(table)
        verify(!withArrow.equals(withoutArrow), "The complete-table capture must contain the real attack line")
        const phaseTrack = item("forgePhaseTrack")
        const phasePaint = phaseTrack.compactMode ? item("forgeCurrentPhase") : phaseTrack
        const phaseChanges = textRegionChangedPixels(withArrow, withoutArrow, phasePaint)
        const identityChanges = data.seats === 2 ? textRegionChangedPixels(withArrow, withoutArrow, item("forgePlayerName-0").parent) : 0
        const status = item(data.deciding ? "forgeOpponentDecidingText" : "forgeRecentActionText")
        verify(status.visible)
        const statusChanges = textRegionChangedPixels(withArrow, withoutArrow, status)
        compare(phaseChanges + identityChanges + statusChanges, 0,
                "Attack lines must stay behind text surfaces; changed phase pixels=" + phaseChanges
                + ", player identity pixels=" + identityChanges + ", public status pixels=" + statusChanges)
        arrow.visible = true
        compare(arrow.endPoint, endpoint, "Text protection must not change the attack target")
    }
    function test_combatCurvesAvoidPublicCardReadouts_data() {
        return [{tag:"two-seat", seats:2}, {tag:"four-seat-pinned", seats:4}]
    }
    function test_combatCurvesAvoidPublicCardReadouts(data) {
        window.width = 1920; window.height = 1011
        const state = data.seats === 4 ? edhSnapshot([0,1,2,3], 0, 1) : snapshot(1,1)
        if (data.seats === 4) { room.format="edh"; room.maxSeats=4; Theme.uiScale=1.5 }
        const own = state.zones.find(zone => zone.zone === "battlefield" && zone.ownerSeat === 0)
        const other = state.zones.find(zone => zone.zone === "battlefield" && zone.ownerSeat === 1)
        const source = own.cards[0], target = other.cards[0]
        source.blocking = [target.id]; source.damage = 1
        source.enteredThisTurn = true; source.summoningSick = true
        target.attacking = true; target.attackingPlayer = 0
        const attached = card("readout-attachment", 0, "Rancor", false)
        attached.attachedTo = source.id; own.cards.push(attached); own.count++
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"$pass",kind:"pass",label:"Pass"}]})
        if (data.seats === 4) table.openCardDetails(source.id)
        mouseMove(table,1,1); verify(waitForPolish(window)); verify(waitForRendering(table))
        const arrow = item("forgeRelationship-block-" + source.id + "-" + target.id)
        verify(arrow.visible && arrow.validAnchors)
        verify(arrow.excludedRects.length > 0)
        const regions = [item("forgeCardName-"+source.id), item("forgeCardStats-"+source.id),
            item("forgeCardInteractionHint-"+source.id), item("forgeAttachmentName-readout-attachment")]
        const stateText = item("forgeCardState-"+source.id)
        verify(stateText.text.includes("Summoning sickness"))
        // Exercise the actual visible lines, not the unused area of a
        // bottom-aligned state label's allocated rectangle.
        const stateRegion = createTemporaryObject(readoutRegion, stateText, {
            y:stateText.height-Math.min(stateText.height,stateText.implicitHeight),
            width:stateText.width,height:Math.min(stateText.height,stateText.implicitHeight)})
        regions.push(stateRegion)
        for (const region of regions) {
            verify(region.visible && region.width > 0 && region.height > 0)
            const rect=region.mapToItem(table.presentation,0,0,region.width,region.height)
            // Use the real relationship renderer to probe a curve crossing
            // each public readout. These positions never submit a game action.
            arrow.startPoint=Qt.point(rect.x-35,rect.y+rect.height/2)
            arrow.endPoint=Qt.point(rect.x+rect.width+35,rect.y+rect.height/2)
            const start=arrow.startPoint,end=arrow.endPoint
            arrow.excludedRects=[]
            verify(waitForRendering(table)); const uncovered=grabImage(table)
            arrow.visible=false
            verify(waitForRendering(table)); const without=grabImage(table)
            verify(textRegionChangedPixels(uncovered,without,region)>0,
                "The probe must reproduce the reported text crossing")
            arrow.excludedRects=Qt.binding(()=>table.presentation.arrowTextRects)
            arrow.visible=true
            verify(waitForRendering(table)); const protectedImage=grabImage(table)
            compare(textRegionChangedPixels(protectedImage,without,region),0,
                "Curves must leave public card text unchanged: "+region.objectName)
            compare(arrow.startPoint,start); compare(arrow.endPoint,end)
        }
        compare(transport.responses.length,0)
    }
    function test_arrowReadoutsTrackVisibleCardsAndStayIdleWithoutLines() {
        const board=table.presentation
        compare(board.hasVisibleArrows,false); compare(board.arrowTextRects.length,0)
        const state=snapshot(1,70,true)
        state.zones[5].cards[0].attacking=true; state.zones[5].cards[0].attackingPlayer=0
        verify(testRulesPrompt.applySnapshot(state)); waitForRendering(table)
        const lane=item("forgeOwnCreatures"), viewport=lane.scrollArea
        tryCompare(board,"hasVisibleArrows",true)
        verify(viewport.contentHeight>viewport.height)
        function covers(point) {
            return board.arrowTextRects.some(rect=>point.x>=rect.x && point.x<=rect.x+rect.width
                && point.y>=rect.y && point.y<=rect.y+rect.height)
        }
        const first=item("forgeCardName-own-0")
        verify(covers(first.mapToItem(board,first.width/2,first.height/2)))
        verify(lane.reveal("own-69")); waitForRendering(table)
        const last=item("forgeCardName-own-69")
        verify(covers(last.mapToItem(board,last.width/2,last.height/2)))
        const clip=viewport.mapToItem(board,0,0,viewport.width,viewport.height)
        for (const rect of lane.readoutRects(board)) {
            verify(rect.x>=clip.x-0.1 && rect.y>=clip.y-0.1)
            verify(rect.x+rect.width<=clip.x+clip.width+0.1 && rect.y+rect.height<=clip.y+clip.height+0.1)
        }
        const slot=lane.itemFor("own-69"), before=last.mapToItem(board,last.width/2,last.height/2)
        slot.visualDx=12; slot.visualDy=-5
        waitForRendering(table)
        const moved=last.mapToItem(board,last.width/2,last.height/2)
        compare(moved.x,before.x+12); compare(moved.y,before.y-5); verify(covers(moved))
        slot.visualDx=0; slot.visualDy=0
        const requests=catalog.faceRequests.length
        state.zones[4].cards[69].visible=false; state.zones[4].cards[69].identity={name:"SECRET"}
        verify(testRulesPrompt.applySnapshot(state)); waitForRendering(table)
        verify(!catalog.faceRequests.includes("SECRET")); verify(!catalog.nameRequests.includes("SECRET"))
        compare(catalog.faceRequests.length,requests)
        compare(item("forgeCardName-own-69").text,"Hidden card")
        compare(transport.responses.length,0)
    }
    function test_arrowReadoutsMergeClosedPilesAndPreserveExpandedStrips() {
        const state=snapshot(1,40,false)
        state.zones[5].cards[0].attacking=true; state.zones[5].cards[0].attackingPlayer=0
        verify(testRulesPrompt.applySnapshot(state)); waitForRendering(table)
        const board=table.presentation,lane=item("forgeOwnCreatures")
        tryCompare(lane,"stackCount",1)
        verify(lane.readoutRects(board).length<=4,"Closed copies must not generate per-copy text obstacles")
        lane.openFan(0); tryCompare(lane.scrollArea,"clip",true)
        lane.scrollArea.contentY=lane.slotY(0)+20*lane.unit; waitForRendering(table)
        const clip=lane.scrollArea.mapToItem(board,0,0,lane.scrollArea.width,lane.scrollArea.height)
        verify(lane.readoutRects(board).some(rect=>rect.y<clip.y-5),
            "An unclipped fan must retain visible text beyond its original lane")
        lane.closeFan(); lane.scrollArea.contentY=0
    }

    function test_animatedCombatResizePublishesCompleteReadouts() {
        Theme.motionEnabled=true
        window.width=1920;window.height=1011;Theme.uiScale=1.5
        room.format="edh";room.maxSeats=4
        const state=edhSnapshot([0,1,2,3],0,2)
        for (const zone of state.zones.filter(zone=>zone.zone==="battlefield")) {
            zone.cards.filter(card=>card.power).forEach((card,index)=>{
                card.attacking=true;card.attackingPlayer=(zone.ownerSeat+index+1)%4
            })
        }
        state.step="declare_blockers"
        verify(testRulesPrompt.applySnapshot(state)); wait(Theme.motionNormal+100)
        table.openCardDetails("creature-0-0")
        tryCompare(table.presentation,"sidePanelOpen",true)
        wait(Theme.motionNormal+100)
        mouseClick(item("clearRulesCardInspectorButton"))
        tryCompare(table.presentation,"sidePanelOpen",false)
        wait(Theme.motionNormal+100)
        const board=table.presentation
        const changes=createTemporaryObject(readoutChanges,table,{target:board})
        verify(changes.valid)
        window.width=900;window.height=620
        compare(changes.count,0,"Resize must finish its related geometry changes before publishing arrow readouts")
        verify(waitForPolish(window));verify(waitForRendering(table))
        tryVerify(()=>changes.count>0)
        verify(changes.count<=8,"One rendered resize must not publish thousands of intermediate readouts")
        wait(Theme.motionNormal+100)
        for (const seat of [0,1,2,3]) {
            const label=item("forgeCardName-creature-"+seat+"-0")
            const point=label.mapToItem(board,label.width/2,label.height/2)
            verify(board.arrowTextRects.some(rect=>point.x>=rect.x && point.x<=rect.x+rect.width
                && point.y>=rect.y && point.y<=rect.y+rect.height),
                "The final compact card name must remain protected")
            const arrow=item("forgeRelationship-attack-creature-"+seat+"-0-")
            verify(arrow.visible && arrow.validAnchors && arrow.geometry.path.length>0)
            compare(arrow.endPoint,board.playerPoint((seat+1)%4))
        }
        room.format="modern";room.maxSeats=2
        verify(testRulesPrompt.applySnapshot(snapshot(7,2,true)))
        wait(Theme.motionNormal+100)
        compare(board.hasVisibleArrows,false);tryCompare(board,"arrowTextRects",[])
        compare(transport.responses.length,0)
    }

}
