// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"
import "../../qml/screens"
import "../../../../tools/ui-automation/scenarios/ForgeNecrodominanceStudy.js" as NecroStudy

// Battlefield layout, pile identity and visible card artwork.
ForgeDuelTestCase {
    id: testCase
    name: "ForgeDuelBattlefield"

    function test_edhSeatLayouts_data() {
        return [{tag:"two-in-four-seat-room", seats:[0,1], local:0, width:1600, height:1000},
            {tag:"two-sparse", seats:[1,3], local:3, width:1600, height:1000},
            {tag:"three-sparse", seats:[0,2,3], local:2, width:1600, height:1000},
            {tag:"four", seats:[0,1,2,3], local:0, width:1920, height:1010},
            {tag:"four-other-viewer", seats:[0,1,2,3], local:3, width:1280, height:720}]
    }
    function test_edhSeatLayouts(data) {
        room.format = "edh"; room.deckFormat = "commander"; room.maxSeats = 4; room.seatIndex = data.local
        window.width = data.width; window.height = data.height
        verify(testRulesPrompt.applySnapshot(edhSnapshot(data.seats, data.local)))
        tryCompare(table.presentation, "playerSeats", data.seats)
        compare(table.presentation.bottomSeat, data.local)
        compare(table.presentation.commanderFormat, true)
        compare(item("forgeHand").ownerSeat, data.local)
        for (const seat of data.seats) {
            compare(findChild(table, "forgeCommanders-" + seat), null)
            verify(item("rulesPlayerTarget" + seat).visible)
        }
        if (data.seats.length === 2) {
            compare(table.presentation.multiplayer, false)
            compare(item("forgeOpponentCreatures").ownerSeat, data.seats.find(s => s !== data.local))
            verify(item("forgeOwnZoneStrip").visible)
            return
        }
        compare(table.presentation.multiplayer, true)
        verify(!item("forgeHandCaption").visible)
        const board = item("forgeMultiplayerBattlefield")
        const near = item("forgeField-" + data.local)
        verify(near.y > 0)
        compare(near.x, 0)
        if (data.seats.length === 3) compare(near.width, board.width)
        else verify(Math.abs(near.width * 2 + board.gap - board.width) < 1)
        for (const seat of data.seats) {
            const field = item("forgeField-" + seat)
            verify(field.x >= 0 && field.y >= 0)
            verify(field.x + field.width <= board.width + 1)
            verify(field.y + field.height <= board.height + 1)
            const right = field.mapToItem(table.presentation, field.width, 0).x
            verify(right <= table.presentation.boardRight + 1)
            const lane = item("forgeCreatures-" + seat)
            tryCompare(lane, "stackCount", 3)
            const zones = item("forgeSeatZones-" + seat)
            const command = item("forgeSeatZone-" + seat + "-command")
            const exile = item("forgeSeatZone-" + seat + "-exile")
            verify(command.x > exile.x + exile.width)
            const zoneY = zones.mapToItem(field, 0, 0).y
            if (field.nearSide) verify(lane.y + lane.height <= zoneY)
            else verify(zoneY + zones.height <= lane.y)
            const surface = item("forgeCard-creature-" + seat + "-0")
            const cardPosition = surface.mapToItem(field, 0, 0)
            if (field.nearSide) verify(cardPosition.y < field.height * 0.1)
            else verify(cardPosition.y + surface.height + lane.layoutCellExtra > field.height * 0.9,
                "The far-side card and its reserved combat chrome stay toward the center seam")
            verify(field.headerHeight <= 64 * table.presentation.unit + field.lifeDeltaClearance,
                "Metadata keeps its compact height below the permanent life-change band")
            const lanes = [lane, item("forgeLands-" + seat), item("forgeOther-" + seat)]
            for (const group of lanes.filter(value => value.stackCount > 0)) {
                verify(group.x >= field.inset && group.y >= field.boardTop)
                verify(group.x + group.width <= field.width - field.inset + 1)
                verify(group.y + group.height <= field.boardTop + field.boardHeight + 1)
                verify(group.scrollArea.contentHeight <= group.height + 1)
            }
            verify(table.presentation.pointFor("creature-" + seat + "-0").x > 0)
            if (seat !== data.local) compare(item("forgeSeatZone-" + seat + "-library").showsPublicFace, false)
        }
    }
    function test_edhFieldsAllocateSpaceToPublicPiles_data() {
        return [{tag:"creatures-only", creatures:8, lands:0, others:0},
            {tag:"lands-only", creatures:0, lands:10, others:0},
            {tag:"support-only", creatures:0, lands:8, others:6},
            {tag:"balanced", creatures:8, lands:4, others:3},
            {tag:"support-heavy", creatures:2, lands:12, others:8, allowOverflow:true}]
    }
    function test_edhFieldsAllocateSpaceToPublicPiles(data) {
        room.format = "edh"; room.maxSeats = 4
        const state = edhSnapshot([0,1,2,3], 0, 0)
        for (const zone of state.zones.filter(value => value.zone === "battlefield")) {
            zone.cards = []
            for (let i = 0; i < data.creatures; ++i)
                zone.cards.push(card("front-" + zone.ownerSeat + "-" + i, zone.ownerSeat, "Bear " + i, true))
            for (let i = 0; i < data.lands; ++i) {
                const land = card("land-" + zone.ownerSeat + "-" + i, zone.ownerSeat, "Plains", false)
                land.counters = [{name:"charge", value:i + 1}]
                zone.cards.push(land)
            }
            for (let i = 0; i < data.others; ++i)
                zone.cards.push(card("support-" + zone.ownerSeat + "-" + i, zone.ownerSeat, "Artifact " + i, false))
            zone.count = zone.cards.length
        }
        verify(testRulesPrompt.applySnapshot(state))
        table.priority.setFullControl(true)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        for (const seat of [0,1,2,3]) {
            const field = item("forgeField-" + seat)
            const lanes = [item("forgeCreatures-" + seat), item("forgeLands-" + seat), item("forgeOther-" + seat)]
            for (let i = 0; i < lanes.length; ++i)
                tryCompare(lanes[i], "stackCount", [data.creatures, data.lands, data.others][i])
            const occupied = lanes.filter(lane => lane.stackCount > 0)
            if (occupied.length === 1) {
                const board = field.mapToItem(table.presentation, field.inset, field.boardTop,
                    field.width - 2 * field.inset, field.boardHeight)
                const obstructed = table.presentation.battlefieldObstacles.some(obstacle =>
                    board.x < obstacle.x + obstacle.width && board.x + board.width > obstacle.x
                    && board.y < obstacle.y + obstacle.height && board.y + board.height > obstacle.y)
                if (!obstructed) {
                    if (occupied[0].category === "creature")
                        compare(occupied[0].height, field.boardHeight)
                    else {
                        verify(occupied[0].height <= field.boardHeight)
                        fuzzyCompare(field.nearSide ? occupied[0].y + occupied[0].height : occupied[0].y,
                            field.nearSide ? field.boardTop + field.boardHeight : field.boardTop, 0.1,
                            "A single support category keeps the rear edge while releasing unused front space")
                    }
                    compare(occupied[0].width, field.width - 2 * field.inset)
                }
                for (const visible of occupied[0].inspectionRects(table.presentation))
                    for (const obstacle of table.presentation.battlefieldObstacles)
                        verify(!(visible.x < obstacle.x + obstacle.width - 0.5
                            && visible.x + visible.width > obstacle.x + 0.5
                            && visible.y < obstacle.y + obstacle.height - 0.5
                            && visible.y + visible.height > obstacle.y + 0.5),
                            "A single category uses free space around the fixed controls")
            }
            for (const lane of occupied) {
                verify(lane.cardWidth >= 80 * table.presentation.unit - 1)
                if (!data.allowOverflow)
                    verify(lane.scrollArea.contentHeight <= lane.height + 1, lane.objectName + " fits its piles")
                for (const peer of occupied.filter(value => value !== lane))
                    verify(lane.x + lane.width <= peer.x || peer.x + peer.width <= lane.x
                        || lane.y + lane.height <= peer.y || peer.y + peer.height <= lane.y)
                for (const slot of lane.visibleCards) {
                    verify(slot.x + slot.width <= lane.width + 1)
                    if (!data.allowOverflow) verify(slot.y + slot.height <= lane.height + 1)
                    verify(table.presentation.reveal(slot.cardId))
                    verify(table.presentation.pointFor(slot.cardId).x > 0)
                }
            }
        }
    }
    function test_edhControlChangesPreserveOtherCardsAndSeparatePriority() {
        room.format = "edh"; room.maxSeats = 4
        const state = edhSnapshot([0,1,2,3], 0)
        state.activeSeat = 2; state.prioritySeat = 3
        verify(testRulesPrompt.applySnapshot(state))
        const own = item("forgeCreatures-0"), other = item("forgeCreatures-1")
        tryCompare(own, "stackCount", 3); tryCompare(other, "stackCount", 3)
        const unchanged = item("forgeCard-creature-0-0")
        const turn = item("forgeField-2"), priority = item("forgeField-3")
        verify(turn.activeTurn && !turn.hasPriority)
        verify(priority.hasPriority && !priority.activeTurn)
        verify(turn.border.color !== priority.border.color)
        verify(item("forgeSeatStatus-2").text.includes("Current turn"))
        verify(item("forgeSeatStatus-3").text.includes("Priority"))
        state.zones.find(zone => zone.zone === "battlefield" && zone.ownerSeat === 1).cards[0].controllerSeat = 0
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(own, "cardCount", 4); tryCompare(other, "cardCount", 2)
        compare(item("forgeCard-creature-0-0"), unchanged)
        verify(own.itemFor("creature-1-0"))
        compare(other.itemFor("creature-1-0"), null)
        const command = item("forgeSeatZone-0-command")
        verify(command.summary)
        compare(String(command.faceSource), "")
        command.forceActiveFocus()
        keyClick(Qt.Key_Return)
        tryCompare(item("forgeZonePopup"), "visible", true)
        compare(item("forgeZonePopup").ownerSeat, 0)
    }
    function test_edhTargetsCommandersAndElimination() {
        room.format = "edh"; room.maxSeats = 4
        const data = edhSnapshot([0,1,2,3], 0)
        verify(testRulesPrompt.applySnapshot(data))
        tryCompare(table.presentation, "multiplayer", true)
        prompt("chooseBoardTargets", {minSelections:2, maxSelections:2, targets:[
            {responseId:"opaque-player-3", kind:"player", seat:3, label:"Player 3"},
            {responseId:"opaque-card-2", kind:"card", objectId:"creature-2-0", label:"Bear 0"}]})
        mouseClick(item("rulesPlayerTarget3"))
        mouseClick(item("forgeCard-creature-2-0"))
        compare(table.interaction.selectedCount, 2)
        mouseClick(item("rulesConfirmTargets"))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].targets.slice().sort(), ["opaque-card-2", "opaque-player-3"])
        action("cast", "cmd-0")
        mouseClick(item("forgeSeatZone-0-command"))
        tryCompare(item("forgeZonePopup"), "opened", true)
        tryCompare(item("forgeZoneCards"), "stackCount", 1)
        mouseClick(item("forgeCard-cmd-0"))
        compare(transport.responses.length, 2)
        item("forgeZonePopup").close()
        compare(transport.responses[1].response, "opaque-play")
        const field = item("forgeField-3")
        const location = Qt.point(field.x, field.y)
        data.players[3].status = "conceded"
        data.activeSeat = 2; data.prioritySeat = 2
        verify(testRulesPrompt.applySnapshot(data))
        tryCompare(field, "eliminated", true)
        compare(table.presentation.playerSeats.length, 4)
        compare(Qt.point(field.x, field.y), location)
        compare(item("forgeField-2").activeTurn, true)
    }
    function test_edhCrowdedBattlefieldAndSpectatorPrivacy() {
        room.format = "edh"; room.maxSeats = 4; room.role = "spectator"; room.seatIndex = -1
        verify(testRulesPrompt.applySnapshot(edhSnapshot([0,1,2,3], -1, 36)))
        tryCompare(table.presentation, "multiplayer", true)
        tryCompare(item("forgeHand"), "visibleCards", [])
        const lane = item("forgeCreatures-2")
        tryCompare(lane, "stackCount", 36)
        verify(lane.scrollArea.contentHeight > lane.scrollArea.height)
        const last = lane.visibleCards[lane.visibleCards.length - 1].cardId
        verify(table.presentation.reveal(last))
        verify(table.presentation.pointFor(last).x > 0)
        compare(item("forgeViewHand-2").visible, false)
        verify(!table.interaction.canRespond)
    }

    function test_floatingStackPreservesBattlefield_data() {
        return [{tag:"modern", format:"modern", seats:2}, {tag:"duel", format:"duel", seats:2},
            {tag:"edh-two", format:"edh", seats:2}, {tag:"edh-three", format:"edh", seats:3},
            {tag:"edh-four", format:"edh", seats:4}]
    }
    function test_floatingStackPreservesBattlefield(data) {
        room.format = data.format; room.maxSeats = data.format === "edh" ? 4 : 2
        const state = data.format === "edh" ? edhSnapshot([0,1,2,3].slice(0, data.seats), 0) : snapshot()
        verify(testRulesPrompt.applySnapshot(state))
        table.priority.setFullControl(true)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        const board = table.presentation, stack = item("forgeStack"), arrow = item("forgeStackTargetArrow")
        tryCompare(board, "multiplayer", data.seats > 2)
        verify(board.boardRight > board.width * 0.95)
        const lane = item(data.seats > 2 ? "forgeCreatures-1" : "forgeOpponentCreatures")
        tryCompare(lane, "stackCount", data.format === "edh" ? 3 : 1)
        if (data.seats > 2) tryCompare(item("forgeLands-1"), "stackCount", 1)
        const before = Qt.rect(lane.x, lane.y, lane.width, lane.height)
        verify(!stack.visible)
        state.stack = [{id:"bolt", controllerSeat:0, identity:{name:"Lightning Bolt"},
            targets:[{kind:"player", seat:data.seats - 1, label:"Opponent"}]}]
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(stack, "count", 1)
        tryVerify(() => stack.visible && arrow.visible)
        compare(Qt.rect(lane.x, lane.y, lane.width, lane.height), before)
        const startX = stack.x, startY = stack.y, arrowStart = Qt.point(arrow.startPoint.x, arrow.startPoint.y)
        const handle = item("forgeStackDragHandle")
        mouseDrag(handle, handle.width / 2, handle.height / 2, -160, 80)
        tryVerify(() => stack.x < startX - 100 && stack.y > startY + 40)
        tryVerify(() => Math.abs(arrow.startPoint.x - arrowStart.x) > 100)
        compare(arrow.startPoint, stack.pointFor("bolt", board))
        compare(transport.responses.length, 0)
        verify(!table.inspector.pinned)
        compare(Qt.rect(lane.x, lane.y, lane.width, lane.height), before)
        const moved = Qt.point(stack.x, stack.y)
        mouseClick(item("forgeStackToggle"))
        tryCompare(stack, "collapsed", true)
        compare(Qt.point(stack.x, stack.y), moved)
        mouseClick(item("forgeStackToggle"))
        tryCompare(stack, "collapsed", false)
        compare(Qt.point(stack.x, stack.y), moved)
        mouseClick(handle, 10, 10, Qt.RightButton)
        tryCompare(stack, "storedPosition", Qt.point(-1, -1))
        verify(!table.inspector.pinned)
        tryVerify(() => Math.abs(stack.x - startX) < 1 && Math.abs(stack.y - startY) < 1,
            1000, "Restored position " + stack.x + "," + stack.y + "; initial " + startX + "," + startY)
        mouseClick(item("forgeStackToggle"))
        tryCompare(stack, "collapsed", true)
        compare(stack.height, stack.headerHeight)
        verify(!arrow.visible)
        state.turn++
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        verify(stack.collapsed)
        item("forgeStackToggle").forceActiveFocus(); keyClick(Qt.Key_Space)
        tryCompare(stack, "collapsed", false)
        tryVerify(() => arrow.visible)
        if (data.seats > 2) {
            const command = item("forgeSeatZone-" + (data.seats - 1) + "-command")
            const covered = command.mapToItem(board, command.width / 2, command.height / 2)
            const offset = 12 * board.unit
            stack.moveTo(covered.x - offset, covered.y - offset)
            mouseClick(stack, offset, offset)
            verify(!item("forgeZonePopup").visible, "The floating stack covers player controls")
        }
        stack.moveTo(board.width, board.height)
        window.width = 1280; window.height = 720
        tryVerify(() => stack.x + stack.width <= board.boardRight + 1
            && stack.y + stack.height < board.handTop)
        mouseClick(item("forgeStackToggle"))
        tryCompare(stack, "collapsed", true)
        state.stack = []
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(stack, "visible", false)
        tryCompare(stack, "collapsed", false)
        state.stack = [{id:"new-spell", controllerSeat:0, identity:{name:"Opt"}}]
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(stack, "visible", true)
        verify(!stack.collapsed)
        state.gameId = "next-game"
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(stack, "storedPosition", Qt.point(-1, -1))
    }

    function test_edhDecisionOverlayKeepsVisibleTargetsReachable_data() {
        return [{tag:"three", seats:3, target:0}, {tag:"four", seats:4, target:1}]
    }
    function test_edhDecisionOverlayKeepsVisibleTargetsReachable(data) {
        room.format = "edh"; room.maxSeats = 4
        window.width = 1280; window.height = 720
        verify(testRulesPrompt.applySnapshot(edhSnapshot([0,1,2,3].slice(0, data.seats), 0, true)))
        tryCompare(table.presentation, "multiplayer", true)
        const id = "creature-" + data.target + "-17"
        const lane = item("forgeCreatures-" + data.target)
        const geometry = Qt.rect(lane.x, lane.y, lane.width, lane.height)
        prompt("chooseBoardTargets", {minSelections:1, maxSelections:2,
            targets:[{responseId:"target", kind:"card", objectId:id, label:"Bear"},
                {responseId:"player", kind:"player", seat:2, label:"Opponent"}]})
        verify(table.presentation.reveal(id))
        const face = item("forgeCard-" + id), dock = table.presentation.decisionDock
        compare(Qt.rect(lane.x, lane.y, lane.width, lane.height), geometry,
                "Opening the multiplayer dock keeps the lane geometry")
        verify(dock.height <= table.presentation.boardDecisionHeight)
        const center = face.mapToItem(table.presentation, face.width / 2, face.height / 2)
        verify(center.x < dock.x || center.y < dock.y, "The target has an exposed click point")
        mouseClick(face)
        compare(table.interaction.selectedCount, 1)
        compare(transport.responses.length, 0)
    }

    function test_edhOrdinaryDockLeavesHeaderZonesReadable_data() {
        return [
            {tag:"maximized", width:1920, height:1011, scale:1.25, local:0},
            {tag:"maximized-small-controls", width:1920, height:1011, scale:1, local:0},
            {tag:"laptop-other-viewer", width:1280, height:720, scale:1, local:3},
            {tag:"scaled-controls", width:1600, height:1000, scale:1.5, local:2},
            {tag:"compact", width:1024, height:768, scale:1, local:0}
        ]
    }
    function test_edhOrdinaryDockLeavesHeaderZonesReadable(data) {
        room.format = "edh"; room.deckFormat = "commander"; room.maxSeats = 4; room.seatIndex = data.local
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        verify(testRulesPrompt.applySnapshot(edhSnapshot([0,1,2,3], data.local)))
        table.priority.setFullControl(true)
        const seat = (data.local + 1) % 4
        const lane = item("forgeCreatures-" + seat)
        const geometry = Qt.rect(lane.x, lane.y, lane.width, lane.height)
        const face = item("forgeCard-creature-" + seat + "-0")
        const faceBefore = face.mapToItem(table.presentation, 0, 0)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        const dock = item("rulesDecisionDock"), zones = item("forgeSeatZones-" + seat)
        verify(dock.visible && !table.presentation.decisionCollapsible)
        const origin = zones.mapToItem(table.presentation, 0, 0)
        verify(origin.x + zones.width <= dock.x || origin.y + zones.height <= dock.y,
               "An ordinary priority dock must not paint over a player's zone labels")
        for (const zone of ["library", "graveyard", "exile", "command"]) {
            const button = item("forgeSeatZone-" + seat + "-" + zone)
            verify(button.width >= 40 * table.presentation.unit, "Zone labels keep readable width")
            mouseClick(button)
            tryCompare(item("forgeZonePopup"), "visible", true)
            compare(item("forgeZonePopup").ownerSeat, seat)
            compare(item("forgeZonePopup").zone, zone)
            mouseClick(item("forgeCloseZonePopup"))
            tryCompare(item("forgeZonePopup"), "visible", false)
        }
        const command = item("forgeSeatZone-" + seat + "-command")
        command.forceActiveFocus(); keyClick(Qt.Key_Return)
        tryCompare(item("forgeZonePopup"), "visible", true)
        compare(item("forgeZonePopup").ownerSeat, seat)
        mouseClick(item("forgeCloseZonePopup"))
        tryCompare(item("forgeZonePopup"), "visible", false)
        const zonesBefore = zones.mapToItem(table.presentation, 0, 0)
        prompt("payManaCost", {options:[{responseId:"$cancel", kind:"cancel", label:"Cancel"}]})
        compare(Qt.rect(lane.x, lane.y, lane.width, lane.height), geometry,
                "Making header controls accessible must not move battlefield lanes")
        compare(face.mapToItem(table.presentation, 0, 0), faceBefore)
        compare(zones.mapToItem(table.presentation, 0, 0), zonesBefore,
                "Board-decision changes keep the header stable")
    }

    function test_sparseCreatureRowsStayCenteredInBattlefield_data() {
        const rows = []
        for (const creatures of [1, 2, 3]) {
            for (const lands of [[], ["Plains", "Plains"], ["Plains", "Ugin's Labyrinth"]]) {
                rows.push({tag:creatures + "-creatures-" + (lands.length === 0 ? "no-lands"
                    : lands[0] === lands[1] ? "same-lands" : "distinct-lands"),
                    creatures:creatures, lands:lands})
            }
        }
        return rows
    }
    function test_sparseCreatureRowsStayCenteredInBattlefield(data) {
        window.width = 1920; window.height = 1011
        const state = snapshot()
        for (const seat of [0, 1]) {
            const cards = []
            for (let i = 0; i < data.creatures; ++i)
                cards.push(card("center-" + seat + "-" + i, seat, "Center Bear " + i, true))
            for (let i = 0; i < data.lands.length; ++i)
                cards.push(card("center-land-" + seat + "-" + i, seat, data.lands[i], false))
            state.zones[4 + seat].cards = cards
            state.zones[4 + seat].count = cards.length
        }
        verify(testRulesPrompt.applySnapshot(state))
        for (const seat of [0, 1]) {
            prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
            verify(waitForPolish(window))
            waitForRendering(table)
            const faces = []
            for (let i = 0; i < data.creatures; ++i) {
                const face = item("forgeCardFace-center-" + seat + "-" + i)
                faces.push(face.mapToItem(table.presentation, 0, 0, face.width, face.height))
            }
            const left = Math.min.apply(null, faces.map(face => face.x))
            const right = Math.max.apply(null, faces.map(face => face.x + face.width))
            const center = (left + right) / 2
            const expected = table.presentation.boardLeft + table.presentation.boardWidth / 2
            verify(Math.abs(center - expected) <= 2 * table.presentation.unit,
                "Seat " + seat + " sparse creature faces center on the battlefield: actual " + center
                + ", expected " + expected + ", face bounds " + JSON.stringify(faces))
            for (const face of faces)
                verify(Math.abs(face.y - faces[0].y) <= table.presentation.unit,
                    "A sparse creature row stays on one line")
            const targetId = "center-" + seat + "-0", responseId = "center-target-" + seat
            prompt("chooseBoardTargets", {minSelections:1, maxSelections:1,
                targets:[{responseId:responseId, kind:"card", objectId:targetId, label:"Center Bear 0"}]})
            for (let i = 0; i < data.creatures; ++i) {
                const face = item("forgeCardFace-center-" + seat + "-" + i)
                compare(face.mapToItem(table.presentation, 0, 0, face.width, face.height), faces[i],
                    "The target decision preserves the centered creature row")
            }
            mouseClick(item("forgeCard-" + targetId))
            compare(transport.responses.length, seat + 1)
            compare(transport.responses[seat].targets, [responseId],
                "The centered face remains directly clickable")
        }
    }

    function test_edhSparseCreatureRowsCenterInTheirOwnFields_data() {
        const rows = []
        for (const creatures of [1, 2, 3]) {
            for (const lands of [[], ["Plains", "Plains"], ["Plains", "Ugin's Labyrinth"]]) {
                rows.push({tag:creatures + "-creatures-" + (lands.length === 0 ? "no-lands"
                    : lands[0] === lands[1] ? "same-lands" : "distinct-lands"),
                    creatures:creatures, lands:lands, spent:false})
            }
            rows.push({tag:creatures + "-creatures-ready-spent-lands", creatures:creatures,
                lands:["Plains", "Plains"], spent:true})
        }
        return rows
    }
    function test_edhSparseCreatureRowsCenterInTheirOwnFields(data) {
        window.width = 1920; window.height = 1011
        room.format = "edh"; room.deckFormat = "commander"; room.maxSeats = 4
        const state = edhSnapshot([0, 1, 2, 3], 0)
        for (const zone of state.zones.filter(zone => zone.zone === "battlefield")) {
            zone.cards = []
            for (let i = 0; i < data.creatures; ++i)
                zone.cards.push(card("edh-center-" + zone.ownerSeat + "-" + i,
                    zone.ownerSeat, "Center Bear " + i, true))
            for (let i = 0; i < data.lands.length; ++i)
                zone.cards.push(Object.assign(card("edh-center-land-" + zone.ownerSeat + "-" + i,
                    zone.ownerSeat, data.lands[i], false), {tapped:data.spent && i === 0}))
            zone.count = zone.cards.length
        }
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        verify(waitForPolish(window))
        waitForRendering(table)
        for (const seat of [0, 1, 2, 3]) {
            const field = item("forgeField-" + seat)
            const faces = []
            for (let i = 0; i < data.creatures; ++i) {
                const face = item("forgeCardFace-edh-center-" + seat + "-" + i)
                faces.push(face.mapToItem(field, 0, 0, face.width, face.height))
            }
            const left = Math.min.apply(null, faces.map(face => face.x))
            const right = Math.max.apply(null, faces.map(face => face.x + face.width))
            verify(Math.abs((left + right) / 2 - field.width / 2) <= 2 * table.presentation.unit,
                "Seat " + seat + " creature faces center in their own field: "
                + JSON.stringify(faces) + ", field width " + field.width)
        }
    }

    function test_landsSitAsLeftTableRow() {
        const state = snapshot()
        state.zones[4].cards.push(card("land-2", 0, "Plains", false))
        state.zones[4].cards.push(card("relic", 0, "Sol Ring", false))
        state.zones[4].count += 2
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        const land = item("forgeCard-land")
        const land2 = item("forgeCard-land-2")
        const creature = item("forgeCard-own-0")
        const lane = item("forgeOwnLands")
        const piles = item("forgeOwnZoneStrip")
        tryCompare(land, "fullFace", false)
        compare(land.fullFace, creature.fullFace)
        verify(land.width <= 112 * table.presentation.unit)
        verify(land2.width <= 112 * table.presentation.unit)
        verify(land.width < creature.width, "Land " + land.width + " must remain smaller than creature " + creature.width)
        const landPoint = land.mapToItem(table, 0, 0)
        const pilePoint = piles.mapToItem(table, 0, 0)
        const hand = item("forgeHand")
        verify(piles.y >= hand.y - 4 * table.presentation.unit)
        verify(landPoint.x <= lane.x + 28 * table.presentation.unit)
        verify(landPoint.y + land.height <= pilePoint.y + 8 * table.presentation.unit)
        verify(lane.y + lane.height >= hand.y - 20 * table.presentation.unit)
        verify(lane.y > item("forgeOwnCreatures").y)
        compare(lane.visibleCards.length, 2)
        compare(lane.stackCount, 1)
        const stacked = land2.mapToItem(lane, 0, 0)
        const first = land.mapToItem(lane, 0, 0)
        verify(Math.abs(stacked.x - first.x) <= 12 * table.presentation.unit)
        verify(item("forgeCardStackCount-land-2").visible)
        compare(item("forgeCardStackCountLabel-land-2").text, "×2")
    }
    function test_playerPlateReservesSupportSpaceAcrossDecisions_data() {
        return [{tag:"maximized", w:1920, h:1011, scale:1, clock:false},
            {tag:"laptop-clock", w:1280, h:720, scale:1, clock:true},
            {tag:"large-controls", w:1600, h:1000, scale:1.35, clock:false}]
    }
    function test_playerPlateReservesSupportSpaceAcrossDecisions(data) {
        window.width = data.w; window.height = data.h; Theme.uiScale = data.scale
        room.actionClockEnabled = data.clock
        room.actionClockMs = data.clock ? [60000, 60000] : []
        const state = snapshot(1, 2, true)
        const supportIds = []
        for (let i = 0; i < 7; ++i) {
            const id = "support-" + i
            supportIds.push(id)
            state.zones[4].cards.push(card(id, 0, "Artifact " + i, false))
        }
        state.zones[4].count = state.zones[4].cards.length
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"pass", kind:"pass", label:"Pass"}]})
        const plate = item("rulesPlayerTarget0")
        const faceIds = ["own-0", "own-1", "land"].concat(supportIds)
        const positions = faceIds.map(id => {
            const face = item("forgeCard-" + id)
            const at = face.mapToItem(table.presentation, 0, 0)
            return Qt.rect(at.x, at.y, face.width, face.height)
        })
        for (const kind of ["chooseBoardTargets", "payManaCost", "chooseAction", ""]) {
            if (kind === "chooseBoardTargets")
                prompt(kind, {minSelections:1, maxSelections:1,
                    targets:supportIds.map(id => ({responseId:"target-" + id, kind:"card", objectId:id, label:id}))})
            else prompt(kind, {pending:kind.length > 0, supported:kind.length > 0,
                options:kind ? [{responseId:"pass", kind:"pass", label:"Pass"}] : []})
            for (let i = 0; i < faceIds.length; ++i) {
                const face = item("forgeCard-" + faceIds[i])
                const at = face.mapToItem(table.presentation, 0, 0)
                compare(Qt.rect(at.x, at.y, face.width, face.height), positions[i],
                    "Decision changes keep battlefield positions and sizes")
                verify(at.x + face.width <= plate.x || at.x >= plate.x + plate.width
                    || at.y + face.height <= plate.y || at.y >= plate.y + plate.height,
                    faceIds[i] + " must not sit under the player identity/life plate")
                verify(face.width >= 80 * table.presentation.unit - 0.1)
            }
        }
        prompt("chooseBoardTargets", {minSelections:1, maxSelections:1,
            targets:supportIds.map(id => ({responseId:"target-" + id, kind:"card", objectId:id, label:id}))})
        mouseClick(item("forgeCard-" + supportIds[0]))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].targets, ["target-" + supportIds[0]])
    }
    function test_equippedCreaturesUseAvailableBattlefield_data() {
        return [{tag:"laptop", w:1280, h:760, depth:1},
            {tag:"desktop", w:1600, h:1000, depth:2},
            {tag:"many-attachments", w:1920, h:1010, depth:5}]
    }
    function test_equippedCreaturesUseAvailableBattlefield(data) {
        window.width = data.w; window.height = data.h
        const state = snapshot(1, 5, true)
        for (let seat = 0; seat < 2; ++seat) {
            const zone = state.zones[4 + seat]
            zone.cards = Array.from({length:5}, (_, i) => card("creature-" + seat + "-" + i, seat, "Bear " + i, true))
            zone.cards.push(card("land-" + seat, seat, "Plains", false),
                card("land2-" + seat, seat, "Ugin's Labyrinth", false),
                card("drum-" + seat, seat, "Springleaf Drum", false))
            for (let host = 0; host < 2; ++host)
                for (let i = 0; i < data.depth; ++i) {
                    const equipment = card("equipment-" + seat + "-" + host + "-" + i, seat, "Bonesplitter", false)
                    equipment.attachedTo = "creature-" + seat + "-" + host
                    zone.cards.push(equipment)
                }
            zone.count = zone.cards.length
        }
        for (const step of ["main1", "declare_attackers", "main2"]) {
            state.step = step
            verify(testRulesPrompt.applySnapshot(state))
            if (step === "declare_attackers")
                prompt("chooseAttackers", {
                    combatSources:Array.from({length:5}, (_, i) => ({responseId:"source-" + i,
                        objectId:"creature-0-" + i, label:"Bear " + i, validTargetIds:["defender"], maxAssignments:1})),
                    combatTargets:[{responseId:"defender", kind:"player", seat:1, label:"Opponent", maxAssignments:5}]})
            else prompt("chooseAction", {options:[{responseId:"pass", kind:"pass", label:"Pass"}]})
            for (const side of ["Own", "Opponent"]) {
                const lane = item("forge" + side + "Creatures")
                tryCompare(lane, "stackCount", 5)
                compare(lane.attachmentDepth, data.depth)
                // The field contract guarantees an 80-unit readable floor.
                // Attachment strips and the reserved player controls may make
                // a five-creature row narrower than the preferred 180 units.
                verify(lane.cardWidth >= 80 * table.presentation.unit - 0.1,
                    side + " creatures remain readable in " + step + ": " + lane.cardWidth / table.presentation.unit)
                verify(lane.cardWidth <= 200 * table.presentation.unit + 0.1)
                verify(lane.scrollArea.contentHeight <= lane.height + 1, "An ordinary board needs no scrolling")
                for (const group of ["Lands", "Other"]) {
                    const support = item("forge" + side + group)
                    compare(support.attachmentDepth, 0)
                    compare(support.structuralBadge, false, "Unrelated support cards reserve no structural badges")
                    verify(support.scrollArea.contentHeight <= support.height + 1)
                    verify(lane.x + lane.width <= support.x || support.x + support.width <= lane.x
                        || lane.y + lane.height <= support.y || support.y + support.height <= lane.y)
                }
                const seat = side === "Own" ? 0 : 1
                for (let i = 0; i < 5; ++i) {
                    const face = item("forgeCard-creature-" + seat + "-" + i)
                    verify(table.presentation.pointFor(face.objectId).x > 0)
                    if (i < 2) {
                        const attachment = item("forgeCard-equipment-" + seat + "-" + i + "-" + (data.depth - 1))
                        compare(attachment.width, face.width)
                        const point = attachment.mapToItem(lane.scrollArea, 0, 0)
                        verify(point.y + attachment.height <= lane.scrollArea.height + 1)
                    }
                }
            }
            if (step === "declare_attackers")
                for (let i = 0; i < 5; ++i) {
                    mouseClick(item("forgeCard-creature-0-" + i))
                    mouseClick(item("rulesPlayerTarget1"))
                    compare(table.combatInteraction.assignments["source-" + i], "defender")
                }
        }
    }
    function test_shortCreatureLaneScrollsAtReadableSize() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 12, true)))
        const lane = createTemporaryObject(shortLane, window.contentItem)
        verify(lane !== null)
        tryCompare(lane, "stackCount", 12)
        verify(lane.cardWidth >= 80)
        verify(lane.scrollArea.contentHeight > lane.scrollArea.height)
        verify(lane.reveal("own-9"))
        verify(lane.scrollArea.contentY > 0)
    }
    function test_pileFrontsAndBadgesStayInsideTheirLane() {
        const state = snapshot(1, 0)
        const marked = (id, name, creature, fields) => Object.assign(card(id, 0, name, creature), fields)
        state.zones[4].cards = [
            marked("land-a", "Plains", false, {tapped:true}),
            card("land-b", 0, "Plains", false),
            card("land-c", 0, "Plains", false),
            marked("land-d", "Plains", false, {enteredThisTurn:true}),
            card("bear-a", 0, "Grizzly Bears", true),
            marked("bear-b", "Grizzly Bears", true, {tapped:true}),
            card("bear-c", 0, "Grizzly Bears", true)
        ]
        state.zones[4].count = state.zones[4].cards.length
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        const unit = table.presentation.unit
        for (const name of ["forgeOwnLands", "forgeOwnCreatures"]) {
            const lane = item(name)
            tryVerify(() => lane.stackCount === 2 && lane.pileLead > 0, 3000, name)
            const front = lane.visibleCards.find(slot => slot.stackFront && slot.stackSize > 1)
            verify(front && !front.tapped, name)
            const face = item("forgeCard-" + front.cardId)
            const at = face.mapToItem(lane.scrollArea, 0, 0)
            verify(at.x >= -0.5 && at.y >= -0.5, name + " front leaves its lane at " + at.x + "," + at.y)
            const badge = item("forgeCardStackCount-" + front.cardId)
            const label = item("forgeCardStackCountLabel-" + front.cardId)
            const on = badge.mapToItem(face, 0, 0)
            verify(on.x >= 0 && on.x + badge.width <= face.width + 0.5, name + " badge leaves its card")
            verify(label.contentWidth <= badge.width, name + " badge text overflows")
        }
        compare(item("forgeCardStackCountLabel-" + item("forgeOwnLands").visibleCards
            .find(slot => slot.stackFront && slot.stackSize > 1).cardId).text, "×3 · 1 new")
        const lands = item("forgeOwnLands")
        const lead = lands.pileLead, width = lands.cardWidth
        state.zones[4].cards[1].tapped = true
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        compare(lands.pileLead, lead, "Tapping keeps the reserved lead")
        compare(lands.cardWidth, width)
        verify(lead <= 9 * unit + 0.01)

        // The final two-copy pile can disappear entirely into ready/spent
        // singletons. Neither its lead nor its right-hand trail becomes room
        // for larger faces in a narrow lane.
        for (const alignRight of [false, true]) {
            const pair = snapshot(1, 0)
            pair.zones[4].cards = [card("pair-a", 0, "Plains", false),
                card("pair-b", 0, "Plains", false)]
            pair.zones[4].count = 2
            verify(testRulesPrompt.applySnapshot(pair))
            const probe = createTemporaryObject(shortLane, window.contentItem,
                {category:"land", width:105, height:250, alignRight:alignRight})
            verify(probe !== null); verify(waitForPolish(window))
            compare(probe.stackCount, 1)
            const faceWidth = probe.cardWidth
            verify(faceWidth >= 80)
            pair.zones[4].cards[0].tapped = true
            verify(testRulesPrompt.applySnapshot(pair)); verify(waitForPolish(window))
            compare(probe.stackCount, 2)
            compare(probe.cardWidth, faceWidth, "Ready/spent singletons keep their fitted face size")
            for (const slot of probe.hostCards) {
                const at = slot.mapToItem(probe.scrollArea, 0, 0)
                verify(at.x >= -0.01 && at.x + slot.width <= probe.scrollArea.width + 0.01,
                    "Both singletons stay inside the narrow lane")
            }
        }
    }
    function test_closedPileShowsOnlyTheFrontHint() {
        const state = snapshot(1, 0)
        const spent = card("land-a", 0, "Plains", false)
        spent.tapped = true
        state.zones[4].cards = [spent, card("land-b", 0, "Plains", false), card("land-c", 0, "Plains", false)]
        state.zones[4].count = 3
        verify(testRulesPrompt.applySnapshot(state))
        prompt("payManaCost", {title:"Pay Mana Cost: {W}",
            options:[{responseId:"action:0", cardId:"land-b", kind:"activateAbility", label:"Plains"},
                     {responseId:"action:1", cardId:"land-c", kind:"activateAbility", label:"Plains"},
                     {responseId:"undo-a", cardId:"land-a", kind:"undoMana", label:"Undo"}]})
        const lane = item("forgeOwnLands")
        const unit = table.presentation.unit
        tryVerify(() => lane.stackCount === 2)
        const ready = item("forgeCard-land-b").mapToItem(lane, 0, 0)
        const copy = item("forgeCard-land-c").mapToItem(lane, 0, 0)
        verify(Math.abs(ready.x - copy.x) <= 16 * unit + 1)
        const spentAt = item("forgeCard-land-a").mapToItem(lane, 0, 0)
        verify(Math.abs(spentAt.x - copy.x) > 20 * unit || Math.abs(spentAt.y - copy.y) > 20 * unit)
        verify(!item("forgeCardInteractionHint-land-b").visible, "A buried ready copy stays unlabeled")
        mouseClick(item("forgeCard-land-a"))
        compare(transport.responses[0].response, "undo-a")
    }
    function test_identicalPermanentsAndTokensStackTogether() {
        const state = snapshot(1, 0)
        const tappedLand = card("land-tapped", 0, "Plains", false)
        tappedLand.tapped = true
        const tappedBear = card("bear-tapped", 0, "Grizzly Bears", true)
        tappedBear.tapped = true
        state.zones[4].cards = [
            card("land-a", 0, "Plains", false),
            card("land-b", 0, "Plains", false),
            tappedLand,
            card("treasure-a", 0, "Treasure", false),
            card("treasure-b", 0, "Treasure", false),
            token("goblin-a", 0, "Goblin Token", true),
            token("goblin-b", 0, "Goblin Token", true),
            card("bear-real", 0, "Grizzly Bears", true),
            token("bear-token", 0, "Grizzly Bears", true),
            tappedBear
        ]
        state.zones[4].count = state.zones[4].cards.length
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        const lands = item("forgeOwnLands")
        const other = item("forgeOwnOther")
        const creatures = item("forgeOwnCreatures")
        const unit = table.presentation.unit
        tryVerify(() => lands.visibleCards.length === 3 && lands.stackCount === 2)
        tryVerify(() => other.visibleCards.length === 2 && other.stackCount === 1)
        tryVerify(() => creatures.visibleCards.length === 5 && creatures.stackCount === 4)
        const stackedLand = item("forgeCard-land-b").mapToItem(lands, 0, 0)
        const firstLand = item("forgeCard-land-a").mapToItem(lands, 0, 0)
        verify(Math.abs(stackedLand.x - firstLand.x) <= 16 * unit + 1)
        verify(Math.abs(stackedLand.y - firstLand.y) <= 16 * unit + 1)
        const splitLand = item("forgeCard-land-tapped").mapToItem(lands, 0, 0)
        verify(Math.abs(splitLand.x - firstLand.x) > 20 * unit
               || Math.abs(splitLand.y - firstLand.y) > 20 * unit,
               "A tapped copy leaves the ready pile")
        compare(item("forgeCardStackCountLabel-land-b").text, "×2")
        compare(item("forgeCardStackCountLabel-treasure-b").text, "×2")
        compare(item("forgeCardStackCountLabel-goblin-b").text, "×2")
        const printed = item("forgeCard-bear-real").mapToItem(creatures, 0, 0)
        const copied = item("forgeCard-bear-token").mapToItem(creatures, 0, 0)
        verify(Math.abs(printed.x - copied.x) > 20 * unit
               || Math.abs(printed.y - copied.y) > 20 * unit)
    }
    function test_permanentZonesKeepTheirSidesAndReachablePlaneswalkers_data() {
        return [{tag:"duel", seats:[0,1], local:0, width:1920, height:1011, scale:1},
            {tag:"duel-native-normal-controls", seats:[0,1], local:0, width:1920, height:1011,
                scale:1.2, otherCount:3},
            {tag:"duel-compact", seats:[0,1], local:0, width:1280, height:720, scale:1},
            {tag:"duel-large-controls", seats:[0,1], local:1, width:1920, height:1011, scale:1.5},
            {tag:"duel-spectator", seats:[0,1], local:-1, width:1280, height:720, scale:1},
            {tag:"three", seats:[0,1,2], local:0, width:1920, height:1011, scale:1},
            {tag:"four", seats:[0,1,2,3], local:0, width:1920, height:1011, scale:1},
            {tag:"four-compact", seats:[0,1,2,3], local:3, width:1280, height:720, scale:1},
            {tag:"four-large-controls", seats:[0,1,2,3], local:0, width:1920, height:1011, scale:1.5},
            {tag:"four-native-large-controls", seats:[0,1,2,3], local:0, width:1920, height:1011,
                scale:1.8, otherCount:3}]
    }
    function test_permanentZonesKeepTheirSidesAndReachablePlaneswalkers(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        room.seatIndex = data.local; room.role = data.local < 0 ? "spectator" : "player"
        if (data.seats.length > 2) { room.format = "edh"; room.deckFormat = "commander"; room.maxSeats = data.seats.length }
        const state = zonedSnapshot(data.seats, Math.max(0, data.local))
        if (data.otherCount === 3)
            for (const zone of state.zones.filter(zone => zone.zone === "battlefield")) {
                zone.cards = zone.cards.filter(card => card.identity.name !== "Testing Enchantment")
                zone.count = zone.cards.length
            }
        verify(testRulesPrompt.applySnapshot(state)); verify(waitForPolish(window)); verify(waitForRendering(table))
        const presentation = table.presentation, stable = []
        function bounds(target) { return target.mapToItem(presentation, 0, 0, target.width, target.height) }
        for (const seat of data.seats) {
            const near = data.seats.length > 2 ? item("forgeField-" + seat).nearSide : seat === presentation.bottomSeat
            const prefix = data.seats.length > 2 ? "" : near ? "Own" : "Opponent"
            function lane(kind) { return item("forge" + prefix + kind + (prefix ? "" : "-" + seat)) }
            const creatures = lane("Creatures"), lands = lane("Lands"), walkers = lane("Planeswalkers"), others = lane("Other")
            compare(creatures.stackCount, 1); compare(lands.stackCount, 5)
            compare(walkers.stackCount, 2); compare(others.stackCount, data.otherCount || 4)
            const l = bounds(lands), w = bounds(walkers), o = bounds(others)
            const landFaces = lands.hostCards.filter(slot => slot.stackFront)
                .sort((a, b) => a.stackIndex - b.stackIndex).map(slot => bounds(slot.faceItem))
            // The duplicate Temple may offset its pile front by four units.
            fuzzyCompare(landFaces[0].y, landFaces[1].y, 5 * presentation.unit,
                "Land piles progress along a horizontal row on either side of the table")
            verify(landFaces[1].x >= landFaces[0].x + landFaces[0].width - presentation.unit,
                "The second distinct land is to the right of the first")
            const creatureFace = bounds(item("forgeCardFace-z-creature-" + seat))
            const field = data.seats.length > 2 ? bounds(item("forgeField-" + seat))
                : Qt.rect(presentation.boardLeft, 0, presentation.boardWidth, 0)
            fuzzyCompare(creatureFace.x + creatureFace.width / 2, field.x + field.width / 2,
                2 * presentation.unit, "A lone creature centers on its whole field with both right-side categories occupied")
            const rightmostOther = Math.max.apply(null, others.hostCards.filter(slot => slot.stackFront)
                .map(slot => { const face = bounds(slot.faceItem); return face.x + face.width }))
            const rightInset = data.seats.length > 2 ? item("forgeField-" + seat).inset : 0
            fuzzyCompare(rightmostOther, field.x + field.width - rightInset,
                4 * presentation.unit, "Other permanents reach their field's right edge")
            verify(l.x + l.width / 2 < w.x + w.width / 2, "Planeswalkers stay to the right of lands")
            verify(l.x + l.width / 2 < o.x + o.width / 2, "Other permanents stay to the right of lands")
            verify(near ? w.y < o.y : w.y > o.y, "Planeswalkers keep the front of the right side")
            const groups = [creatures, lands, walkers, others]
            for (let index = 0; index < groups.length; ++index) {
                const group = groups[index]
                verify(group.cardWidth >= 80 * presentation.unit - 0.1, "Every group retains readable card sizes")
                for (const other of groups.slice(index + 1))
                    verify(!rectsOverlap(group, other), "Permanent categories have separate allocations")
                const first = group.hostCards.find(slot => slot.stackFront)
                verify(first !== undefined)
                verify(presentation.reveal(first.cardId))
                verify(waitForPolish(window))
                const face = first.faceItem, faceBody = findChild(face, "forgeCardFace-" + first.cardId)
                fuzzyCompare(faceBody.width, face.width, 0.01)
                fuzzyCompare(faceBody.height, face.height, 0.01)
                const point = presentation.pointFor(first.cardId)
                verify(point.x > 0 && point.y > 0, "Every category participates in exact-card targeting: "
                    + JSON.stringify({group:group.objectName, card:first.cardId, point:point,
                        face:bounds(faceBody), viewport:bounds(group.scrollArea), allocation:bounds(group)}))
                const body = bounds(faceBody), viewport = bounds(group.scrollArea)
                const left = Math.max(body.x, viewport.x), top = Math.max(body.y, viewport.y)
                const right = Math.min(body.x + body.width, viewport.x + viewport.width)
                const bottom = Math.min(body.y + body.height, viewport.y + viewport.height)
                const visible = Qt.rect(left, top, Math.max(0, right - left), Math.max(0, bottom - top))
                verify(visible.width > 0 && visible.height > 0, "Revealing a card exposes its face")
                fuzzyCompare(visible.width, body.width, 0.1, group.objectName + " exposes the full card width")
                fuzzyCompare(visible.height, body.height, 0.1, group.objectName + " exposes the full card height")
                for (const obstacle of presentation.battlefieldObstacles)
                    verify(!(visible.x < obstacle.x + obstacle.width - 0.5 && visible.x + visible.width > obstacle.x + 0.5
                        && visible.y < obstacle.y + obstacle.height - 0.5 && visible.y + visible.height > obstacle.y + 0.5),
                        "Visible cards avoid the reserved player and decision areas: " + JSON.stringify({
                            group:group.objectName, card:first.cardId, face:visible,
                            viewport:bounds(group.scrollArea), obstacle:obstacle, allocation:bounds(group)}))
                const last = group.hostCards.filter(slot => slot.stackFront).slice(-1)[0]
                verify(presentation.reveal(last.cardId))
                verify(waitForPolish(window))
                const lastPoint = presentation.pointFor(last.cardId)
                verify(lastPoint.x > 0 && lastPoint.y > 0,
                    "The last card in a scrolling category remains exactly targetable: "
                    + JSON.stringify({group:group.objectName, card:last.cardId, point:lastPoint,
                        face:bounds(last.faceItem), viewport:bounds(group.scrollArea)}))
                const lastBody = bounds(last.faceItem), lastViewport = bounds(group.scrollArea)
                verify(lastBody.x >= lastViewport.x - 0.1 && lastBody.y >= lastViewport.y - 0.1
                    && lastBody.x + lastBody.width <= lastViewport.x + lastViewport.width + 0.1
                    && lastBody.y + lastBody.height <= lastViewport.y + lastViewport.height + 0.1,
                    "The last exact card is fully revealable: " + JSON.stringify({group:group.objectName,
                        card:last.cardId, body:lastBody, viewport:lastViewport}))
            }
            const walkerId = "z-" + seat + "-Karn, the Great Creator"
            verify(presentation.reveal(walkerId))
            const walker = item("forgeCard-" + walkerId)
            const walkerBounds = bounds(walker)
            compare(item("forgeCardLoyaltyValue-" + walkerId).text, "4")
            verify(walkers.inspectionRects(presentation).some(rect => rect.x <= walkerBounds.x + 0.1
                && rect.x + rect.width >= walkerBounds.x + walkerBounds.width - 0.1))
            stable.push({items:groups, rects:groups.map(group => bounds(group))})
        }
        // Loyalty and ordinary target prompts cannot send walkers back into
        // another category or move any of the four permanent regions.
        for (const zone of state.zones.filter(zone => zone.zone === "battlefield"))
            for (const row of zone.cards)
                if (row.identity.name === "Karn, the Great Creator") row.counters = [{name:"LOYALTY", value:7}]
        verify(testRulesPrompt.applySnapshot(state)); verify(waitForPolish(window))
        for (const before of stable)
            before.items.forEach((group, index) => compare(bounds(group), before.rects[index]))
        for (const seat of data.seats)
            compare(item("forgeCardLoyaltyValue-z-" + seat + "-Karn, the Great Creator").text, "7")
        if (data.local >= 0) {
            const targetSeat = data.seats.find(seat => seat !== data.local)
            const targetId = "z-" + targetSeat + "-Karn, the Great Creator"
            prompt("chooseBoardTargets", {minSelections:1, maxSelections:1,
                targets:[{responseId:"walker-target", kind:"card", objectId:targetId, label:"Karn"}]})
            verify(waitForPolish(window))
            tryVerify(() => presentation.reveal(targetId), 5000, "The current target delegate becomes available")
            verify(waitForPolish(window))
            // Polishing may consume the dirty frame before the render wait
            // starts. Explicitly schedule the frame whose input we exercise.
            window.update()
            verify(waitForRendering(table), "The revealed target frame renders")
            mouseClick(item("forgeCard-" + targetId))
            compare(transport.responses.length, 1)
            compare(transport.responses[0].targets, ["walker-target"])
        }
    }
    function test_equalLandRowsMirrorVerticallyWithoutChangingDirection() {
        setupNativePermanentRegions()
        const board = table.presentation, rows = []
        for (const prefix of ["Own", "Opponent"]) {
            const lane = item("forge" + prefix + "Lands")
            const faces = lane.hostCards.filter(slot => slot.stackFront)
                .map(slot => slot.faceItem.mapToItem(board, 0, 0, slot.width, slot.height))
            compare(faces.length, 5)
            faces.sort((a, b) => a.x - b.x)
            for (let index = 1; index < faces.length; ++index) {
                fuzzyCompare(faces[index].y, faces[0].y, 5 * board.unit,
                    prefix + " lands form a horizontal rear row: " + JSON.stringify(faces))
                verify(faces[index].x >= faces[index - 1].x + faces[index - 1].width - board.unit,
                    "Distinct land piles progress horizontally without overlap")
            }
            rows.push(faces)
        }
        // Each field fits its own reserved controls. Mirroring preserves the
        // category directions, while face sizes adapt to the available space.
        for (const row of rows) {
            verify(row[0].width >= 80 * board.unit - 0.1)
            verify(row[0].width <= 108 * board.unit + 0.1)
        }
        for (const category of ["Planeswalkers", "Other"]) {
            const own = item("forgeOwn" + category), opponent = item("forgeOpponent" + category)
            for (const lane of [own, opponent]) {
                verify(lane.cardWidth >= 80 * board.unit - 0.1)
                verify(lane.cardWidth <= 108 * board.unit + 0.1)
            }
        }
    }
    function test_planeswalkerFlankDoesNotShiftCreatureCenter() {
        setupNativePermanentRegions()
        const board = table.presentation
        for (const seat of [0, 1]) {
            const face = item("forgeCardFace-z-creature-" + seat)
            const center = face.mapToItem(board, face.width / 2, face.height / 2)
            fuzzyCompare(center.x, board.boardLeft + board.boardWidth / 2, board.unit,
                "A lone creature remains on the battlefield axis with planeswalkers and artifacts present")
        }
    }
    function test_otherPermanentsReachRightRearAboveDecisionDock() {
        setupNativePermanentRegions()
        const board = table.presentation, dock = item("rulesDecisionDock")
        for (const prefix of ["Own", "Opponent"]) {
            const lane = item("forge" + prefix + "Other")
            const faces = lane.hostCards.filter(slot => slot.stackFront)
                .map(slot => slot.faceItem.mapToItem(board, 0, 0, slot.width, slot.height))
            compare(faces.length, 3)
            const right = Math.max.apply(null, faces.map(face => face.x + face.width))
            fuzzyCompare(right, board.boardRight, 4 * board.unit,
                "The right flank uses the field edge instead of stopping beside a phantom dock column")
            if (prefix === "Own") {
                const bottom = Math.max.apply(null, faces.map(face => face.y + face.height))
                const availableBottom = Math.min(board.battlefieldBottom, board.dockReservation.y - 12 * board.unit)
                verify(bottom <= dock.y - 12 * board.unit + board.unit,
                    "The rear artifact row stays above the visible decision controls")
                verify(availableBottom - bottom <= 24 * board.unit,
                    "The rear row aligns with the stable decision reservation without a second unused band: "
                    + JSON.stringify({bottom:bottom, availableBottom:availableBottom, dockY:dock.y}))
            }
        }
    }
    function test_exactRevealHidesExpandedDecisionWithoutLosingTargetDraft_data() {
        return [{tag:"duel", seats:[0, 1], targetSeat:0},
            {tag:"four", seats:[0, 1, 2, 3], targetSeat:1}]
    }
    function test_exactRevealHidesExpandedDecisionWithoutLosingTargetDraft(data) {
        setupNativePermanentRegions(data.seats)
        const names = ["Liquimetal Coating", "Relic of Progenitus", "Trinisphere"]
        const ids = names.map(name => "z-" + data.targetSeat + "-" + name)
        const baseline = boardGeometry(ids.concat(["z-creature-" + data.targetSeat]))
        prompt("chooseBoardTargets", {title:"Choose two or three target permanents", minSelections:2, maxSelections:3,
            targets:ids.map((id, index) => ({responseId:"support-target-" + index, kind:"card",
                objectId:id, label:names[index]}))})
        const board = table.presentation, dock = item("rulesDecisionDock"), toggle = item("forgeDecisionCollapse")
        verify(dock.height > board.dockReservedHeight, "The fixture exercises an expanded board decision")
        verify(toggle.visible && !dock.collapsed)
        verify(board.reveal("z-creature-" + data.targetSeat)); verify(waitForPolish(window))
        verify(!dock.collapsed, "Revealing an uncovered creature leaves the decision visible")
        const source = item("forgeCard-" + ids[0])
        const sourceBounds = source.mapToItem(board, 0, 0, source.width, source.height)
        verify(sourceBounds.x < dock.x + dock.width && sourceBounds.x + sourceBounds.width > dock.x
            && sourceBounds.y < dock.y + dock.height && sourceBounds.y + sourceBounds.height > dock.y,
            "The expanded choice initially covers the exact right-rear target")
        verify(board.reveal(ids[0])); verify(waitForPolish(window)); verify(waitForRendering(table))
        verify(dock.collapsed, "Exact-object reveal exposes a card covered by the expanded decision")
        mouseClick(source)
        compare(table.interaction.selectedCount, 1)
        compare(transport.responses.length, 0)
        mouseClick(toggle); verify(waitForRendering(table))
        verify(!dock.collapsed)
        compare(table.interaction.selectedCount, 1, "Showing the choice retains the first selected target")
        verify(board.reveal(ids[1])); verify(waitForPolish(window)); verify(waitForRendering(table))
        verify(dock.collapsed)
        mouseClick(item("forgeCard-" + ids[1]))
        compare(table.interaction.selectedCount, 2)
        compare(transport.responses.length, 0, "Hiding a decision never submits the draft")
        compare(boardGeometry(ids.concat(["z-creature-" + data.targetSeat])), baseline,
            "Hiding and restoring a choice never moves the permanent regions")
        mouseClick(toggle); verify(waitForRendering(table))
        const confirm = item("rulesConfirmTargets")
        verify(confirm.visible && confirm.enabled)
        const confirmAt = confirm.mapToItem(dock, 0, 0, confirm.width, confirm.height)
        verify(confirmAt.x >= -0.5 && confirmAt.y >= -0.5
            && confirmAt.x + confirmAt.width <= dock.width + 0.5
            && confirmAt.y + confirmAt.height <= dock.height + 0.5,
            "Restoring the choice exposes the complete confirmation action")
        mouseClick(confirm)
        compare(transport.responses.length, 1)
        compare(transport.responses[0].targets, ["support-target-0", "support-target-1"])
    }
    function test_compactMultiplayerOverlayKeepsFieldAndHeaderStill() {
        setupNativePermanentRegions([0, 1, 2, 3], {width:900, height:620, scale:1.35})
        const inspected = item("forgeCard-z-creature-0")
        mouseClick(inspected, inspected.width / 2, inspected.height / 2, Qt.RightButton)
        tryCompare(table.inspector, "pinnedCardId", "z-creature-0")
        verify(waitForPolish(window)); verify(waitForRendering(table))
        const field = item("forgeField-1"), dock = item("rulesDecisionDock")
        verify(field.headerAboveDock, "The narrow lower-right field exercises metadata above the dock: "
            + JSON.stringify({near:field.nearSide, x:field.x, y:field.y, width:field.width,
                height:field.height, header:field.headerTop, sideWidth:field.sideHeaderWidth,
                minimum:field.minimumHeaderWidth, dock:table.presentation.dockReservation}))
        const ids = ["z-creature-0", "z-creature-1", "z-creature-2", "z-creature-3",
            "z-1-Eldrazi Temple", "z-1-Karn, the Great Creator", "z-1-Trinisphere"]
        const baseline = boardGeometry(ids)
        const fieldBounds = Qt.rect(field.x, field.y, field.width, field.height)
        const boardBounds = Qt.rect(field.inset, field.boardTop, field.width - 2 * field.inset, field.boardHeight)
        const zones = item("forgeSeatZones-1")
        const headerBounds = zones.mapToItem(table.presentation, 0, 0, zones.width, zones.height)
        function remainsStill(stage) {
            verify(waitForPolish(window)); verify(waitForRendering(table))
            compare(boardGeometry(ids), baseline, stage + " preserves every permanent")
            compare(Qt.rect(field.x, field.y, field.width, field.height), fieldBounds)
            compare(Qt.rect(field.inset, field.boardTop, field.width - 2 * field.inset, field.boardHeight),
                boardBounds, stage + " preserves the lower-right battlefield height")
            compare(zones.mapToItem(table.presentation, 0, 0, zones.width, zones.height), headerBounds,
                stage + " preserves the metadata above the stable reservation")
        }
        prompt("chooseBoardTargets", {title:"Choose two target permanents", minSelections:2, maxSelections:3,
            targets:["z-1-Liquimetal Coating", "z-1-Relic of Progenitus", "z-1-Trinisphere"]
                .map((id, index) => ({responseId:"compact-target-" + index, kind:"card", objectId:id, label:id}))})
        remainsStill("Expanded targeting")
        verify(item("forgeDecisionCollapse").visible)
        mouseClick(item("forgeDecisionCollapse"))
        verify(dock.collapsed); remainsStill("Hidden targeting")
        mouseClick(item("forgeDecisionCollapse"))
        verify(!dock.collapsed); remainsStill("Restored targeting")
        prompt("chooseAttackers", {title:"Choose attackers for the defending player",
            detail:"Select an attacker, then its defending player. ".repeat(12),
            combatSources:[{responseId:"compact-attacker", objectId:"z-creature-0", label:"Grizzly Bears",
                validTargetIds:["compact-defender"], maxAssignments:1}],
            combatTargets:[{responseId:"compact-defender", kind:"player", seat:1, label:"Player 1", maxAssignments:1}]})
        remainsStill("Expanded combat")
        verify(item("forgeDecisionCollapse").visible)
        mouseClick(item("forgeDecisionCollapse"))
        verify(dock.collapsed); remainsStill("Hidden combat")
        mouseClick(item("forgeDecisionCollapse"))
        verify(!dock.collapsed); remainsStill("Restored combat")
        compare(transport.responses.length, 0)
    }
    function test_crowdedLanesAndHandRemainReachable() {
        verify(testRulesPrompt.applySnapshot(snapshot(20, 70, true)))
        const lane = item("forgeOwnCreatures"), hand = item("forgeHand")
        tryVerify(() => lane.visibleCards.length === 70 && hand.visibleCards.length === 20)
        verify(lane.scrollArea.contentHeight > lane.scrollArea.height)
        verify(hand.scrollArea.contentWidth > hand.scrollArea.width)
        item("forgeCard-own-69").forceActiveFocus()
        verify(lane.scrollArea.contentY > 0)
        item("forgeHandSurface-hand-19").forceActiveFocus()
        verify(hand.scrollArea.contentX > 0)
        const point = item("forgeHandSurface-hand-19").mapToItem(hand.scrollArea, 0, 0)
        verify(point.x >= 0 && point.x + hand.cardWidth <= hand.width + 1)
    }
    function test_newPermanentsShareASlotWhileStateLabelsRemain_data() {
        return [{tag:"english", chinese:false}, {tag:"chinese", chinese:true}]
    }
    function test_newPermanentsShareASlotWhileStateLabelsRemain(data) {
        if (data.chinese) testTranslations.setLanguage("zh")
        const state = snapshot(1, 2)
        const fresh = state.zones[4].cards[1]
        fresh.enteredThisTurn = true; fresh.summoningSick = true
        verify(testRulesPrompt.applySnapshot(state))
        const lane = item("forgeOwnCreatures")
        tryCompare(lane, "visibleStackIds", [["own-0", "own-1"]])
        const label = findChild(item("forgeCard-own-1"), "forgeCardState-own-1")
        verify(label.visible)
        compare(label.text, data.chinese ? "本回合进场 · 召唤失调" : "Entered this turn · Summoning sickness")
        compare(findChild(item("forgeCard-own-0"), "forgeCardState-own-0").text, "")
        fresh.enteredThisTurn = false
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(lane, "stackCount", 1)
        fresh.summoningSick = false
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(lane, "visibleStackIds", [["own-0", "own-1"]])
    }

    function test_compactHandReturnsSpaceToBattlefield() {
        verify(testRulesPrompt.applySnapshot(snapshot(7, 4)))
        const hand = item("forgeHand")
        tryVerify(() => hand.visibleCards.length === 7)
        verify(hand.height <= hand.faceHeight * 0.7)
        const creatures = item("forgeOwnCreatures"), lands = item("forgeOwnLands")
        fuzzyCompare(Math.min(creatures.y, lands.y), table.presentation.ownBattlefieldTop, 1)
        fuzzyCompare(Math.max(creatures.y + creatures.height, lands.y + lands.height),
                     table.presentation.battlefieldBottom, 1)
        verify(creatures.cardWidth >= 80 * table.presentation.unit)
        for (const slot of hand.visibleCards) {
            const center = slot.mapToItem(table, slot.width / 2, slot.height / 2)
            verify(center.y >= hand.y && center.y < table.height)
        }
        // Finish the new snapshot's hover hit testing before beginning the
        // separate keyboard inspection intent.
        verify(waitForPolish(window))
        mouseMove(table, table.width - 2, 2)
        verify(waitForPolish(window))
        grabImage(table)
        const focused = item("forgeHandSurface-hand-6")
        focused.forceActiveFocus()
        tryCompare(focused, "activeFocus", true)
        tryCompare(table.inspector, "previewCardId", "hand-6")
        tryCompare(item("rulesCardHoverPreview"), "visible", true)
        compare(table.inspector.previewCardId, "hand-6")
    }
    function test_permanentsFitWithoutScrolling_data() {
        return [{tag:"desktop", w:1600, h:1000}, {tag:"laptop", w:1280, h:800},
            {tag:"wide", w:1920, h:1011}, {tag:"duel", w:1600, h:1000, duel:true}]
    }
    function test_permanentsFitWithoutScrolling(data) {
        window.width = data.w; window.height = data.h
        room.format = data.duel ? "duel" : "modern"
        const state = snapshot(7, 20)
        for (let seat = 0; seat < 2; ++seat) {
            const zone = state.zones[4 + seat]
            zone.cards = zone.cards.filter(value => value.identity.name !== "Plains")
            for (let i = 0; i < 8; ++i) {
                zone.cards.push(card("land-" + seat + "-" + i, seat, "Plains", false))
                zone.cards.push(card("artifact-" + seat + "-" + i, seat, "Treasure", false))
            }
            zone.count = zone.cards.length
        }
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        for (const name of ["forgeOwnLands", "forgeOpponentLands", "forgeOwnOther", "forgeOpponentOther"]) {
            const lane = item(name)
            tryVerify(() => lane.visibleCards.length === 8 && lane.stackCount === 1)
            tryVerify(() => lane.scrollArea.contentHeight <= lane.scrollArea.height + 1,
                      5000, name + " should fit all eight exact permanents")
            for (const slot of lane.visibleCards)
                verify(slot.y + slot.height <= lane.scrollArea.height + 1)
        }
    }
    function test_creatureGridUsesExactFittedColumns_data() {
        return [20, 22, 26].map(count => ({tag:String(count), count:count}))
    }
    function test_creatureGridUsesExactFittedColumns(data) {
        window.width = 1920; window.height = 1011
        const state = snapshot(7, data.count, true)
        state.zones[5].cards = Array.from({length:data.count}, (_, i) => card("other-" + i, 1, "Bear " + i, true))
        state.zones[5].count = data.count
        verify(testRulesPrompt.applySnapshot(state))
        verify(waitForPolish(window)); verify(waitForRendering(table))
        for (const name of ["forgeOwnCreatures", "forgeOpponentCreatures"]) {
            const lane = item(name)
            tryVerify(() => lane.visibleCards.length === data.count)
            // Crowded rows retain full combat/readout reservations and may
            // scroll at the readable floor instead of squeezing 22 faces in.
            if (data.count <= 20)
                verify(lane.scrollArea.contentHeight <= lane.scrollArea.height + 1,
                    "The fitted grid should show this count without scrolling: " + JSON.stringify({
                        lane:name, count:data.count, width:lane.width, height:lane.height,
                        face:lane.cardWidth, columns:lane.columns, contentHeight:lane.scrollArea.contentHeight,
                        viewportHeight:lane.scrollArea.height, obstacles:table.presentation.battlefieldObstacles}))
            else verify(lane.cardWidth >= 80 * table.presentation.unit - 0.1,
                "A very crowded grid scrolls instead of shrinking below the readable floor")
            for (const slot of lane.visibleCards) {
                verify(slot.x + slot.width <= lane.scrollArea.width + 1)
                verify(slot.y + slot.height <= lane.scrollArea.contentHeight + 1)
                verify(lane.reveal(slot.cardId))
                const at = slot.mapToItem(lane.scrollArea, 0, 0)
                verify(at.y >= -0.1 && at.y + slot.height <= lane.scrollArea.height + 1,
                    "Every exact crowded-grid object remains fully revealable")
            }
        }
    }
    function test_playmatShowsThroughBattlefield() {
        const board = item("forgeDuelTable")
        compare(board.color.a, 0)
        const veil = findChild(board, "forgePlaymatVeil")
        verify(veil !== null)
        compare(veil.width, board.width)
        const library = item("forgeZone-library")
        compare(library.width, Math.round(library.width))
        compare(library.height, Math.round(library.height))
        const prompt = item("rulesPromptPanel")
        compare(prompt.color.a, 0)
        compare(prompt.border.width, 0)
        const picker = item("rulesCardActionPicker")
        compare(picker.color.a, 0)
        compare(picker.border.width, 0)
    }

    function test_handCaptionStaysReadableAcrossBattlefieldBorder_data() {
        return [{tag:"maximized", width:1920, height:1011},
            {tag:"compact-scaled", width:900, height:620, scale:1.5},
            {tag:"spectator-hidden", width:1920, height:1011, spectator:true},
            {tag:"spectator-read-only", width:1920, height:1011, spectator:true, hands:true}]
    }
    function test_handCaptionStaysReadableAcrossBattlefieldBorder(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale || 1
        if (data.spectator) {
            room.role = "spectator"; room.seatIndex = -1
            room.spectatorsSeeHands = data.hands === true
        }
        verify(testRulesPrompt.applySnapshot(snapshot(2, 1)))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        mouseMove(table, 1, 1)
        verify(waitForPolish(window)); verify(waitForRendering(table))
        const hand = item("forgeHand"), caption = item("forgeHandCaption")
        const battlefield = item("forgeActiveBattlefield")
        verify(caption.visible && battlefield.visible)
        compare(hand.y, table.presentation.handTop)
        compare(caption.y, -16 * hand.unit, "Readout protection must not move the hand or its caption")
        if (!data.spectator) compare(caption.text, "Hand · 2")
        else if (data.hands) compare(caption.text, table.matchUi.playerName(0) + " — hand (read only)")
        else {
            compare(caption.text, "Hands are hidden from spectators in this room")
            compare(hand.visibleCards.length, 0)
        }
        const withBorder = grabImage(table)
        const color = String(battlefield.border.color)
        battlefield.border.color = "transparent"
        const withoutBorder = grabImage(table)
        battlefield.border.color = color
        verify(!withBorder.equals(withoutBorder), "The actual battlefield border must be visible")
        compare(textRegionChangedPixels(withBorder, withoutBorder, caption), 0,
            "The battlefield edge must not run through the hand count or spectator wording")
        compare(transport.responses.length, 0)
    }

    function test_auraOnAPiledCopyStaysVisible() {
        const state = snapshot(1, 2)
        const aura = card("aura", 0, "Pacifism", true)
        aura.attachedTo = "own-1"
        state.zones[4].cards.push(aura)
        state.zones[4].count = state.zones[4].cards.length
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(item("forgeOwnCreatures"), "stackCount", 2)
        const host = item("forgeCard-own-1")
        const attached = item("forgeCard-aura")
        verify(attached.visible)
        verify(attached.parent === host.parent)
    }
    function test_eachStackedAttachmentRemainsSelectable_data() {
        return [{tag:"own-three", w:1920, h:1010, depth:3, seat:0},
            {tag:"opponent-three", w:1920, h:1010, depth:3, seat:1},
            {tag:"laptop-three", w:1280, h:729, depth:3, seat:0},
            {tag:"deep-stack", w:1920, h:1010, depth:12, seat:0}]
    }
    function test_eachStackedAttachmentRemainsSelectable(data) {
        window.width = data.w; window.height = data.h
        const hostId = attachmentBoard(data.depth, data.seat)
        const options = [{responseId:"host-action", kind:"activateAbility", cardId:hostId, label:"Host ability"}]
        for (let i = 0; i < data.depth; ++i)
            options.push({responseId:"attachment-action-" + i, kind:"activateAbility",
                cardId:"attached-" + i, label:"Attachment ability " + i})
        const lane = item(data.seat === 1 ? "forgeOpponentCreatures" : "forgeOwnCreatures")
        const viewport = lane.scrollArea
        for (let i = 0; i < data.depth; ++i) {
            prompt("chooseAction", {options:options})
            const attached = item("forgeCard-attached-" + i)
            const clickY = attached.height - 8 * attached.unit
            const point = attached.mapToItem(viewport, attached.width / 2, clickY)
            // Deep attachment stacks scroll at readable size. Bring each
            // exposed strip into view before testing its actual hit target.
            viewport.contentY = Math.max(0, Math.min(viewport.contentHeight - viewport.height,
                viewport.contentY + point.y - viewport.height / 2))
            waitForRendering(table)
            const visiblePoint = attached.mapToItem(viewport, attached.width / 2, clickY)
            verify(visiblePoint.y >= 8 * attached.unit
                && visiblePoint.y <= viewport.height - 8 * attached.unit,
                "The attachment strip must be visible before its click")
            mouseClick(attached, attached.width / 2, clickY)
            compare(transport.responses.length, i + 1, "Only one card responds to an attachment strip click")
            compare(transport.responses[i].response, "attachment-action-" + i,
                "Each exposed strip selects its own attachment, including the covered copies")
        }
        prompt("chooseAction", {options:options})
        verify(lane.reveal(hostId))
        waitForRendering(table)
        mouseClick(item("forgeCard-" + hostId))
        compare(transport.responses.length, data.depth + 1)
        compare(transport.responses[data.depth].response, "host-action", "Attachments do not answer a host click")
    }
    function test_attachmentTargetUsesTheClickedObject() {
        const hostId = attachmentBoard(3, 0)
        const ids = [hostId, "attached-0", "attached-1", "attached-2"]
        for (let i = 0; i < ids.length; ++i) {
            prompt("chooseBoardTargets", {minSelections:1, maxSelections:1,
                targets:ids.map(id => ({responseId:"target-" + id, kind:"card", objectId:id, label:id}))})
            const selected = item("forgeCard-" + ids[i])
            mouseClick(selected, selected.width / 2,
                i === 0 ? selected.height / 2 : selected.height - 8 * selected.unit)
            compare(transport.responses.length, i + 1)
            compare(transport.responses[i].targets, ["target-" + ids[i]])
        }
    }
    function test_largeFanStaysInTheWindowAndEscapeClosesIt() {
        window.width = 1280; window.height = 800
        const ids = []
        for (let i = 0; i < 14; ++i)
            ids.push("land-" + String(i).padStart(2, "0"))
        landBoard(ids)
        const lane = item("forgeOwnLands")
        tryCompare(lane, "stackCount", 1)
        const front = ids[ids.length - 1]
        showPile(front)
        compare(lane.fannedStack, 0)
        for (const id of ids) {
            const member = item("forgeCard-" + id)
            const left = member.mapToItem(table, 0, 0).x
            verify(left >= 0 && left + member.width <= table.width + 1, id)
        }
        table.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(lane.fannedStack, -1)
        showPile(front)
        compare(lane.fannedStack, 0)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        compare(lane.fannedStack, -1, "A new decision closes the fan")
    }
    function test_specialFramesCropOnlyArtwork_data() {
        return [
            {tag:"saga", frame:"saga", x:250, y:150, w:190, h:350},
            {tag:"class", frame:"class", x:55, y:90, w:175, h:430},
            {tag:"planeswalker", frame:"planeswalker", x:39, y:95, w:410, h:238},
            {tag:"battle", frame:"battle", x:70, y:80, w:195, h:570},
            {tag:"flip-front", frame:"flip", x:45, y:218, w:395, h:220},
            {tag:"flip-back", frame:"flip-back", x:45, y:218, w:395, h:220}]
    }
    function test_specialFramesCropOnlyArtwork(data) {
        const name = "Frame reference " + data.tag
        catalog.artFrames = ({[name]:data.frame})
        catalog.tableFaceImages = ({[name]:"data:image/svg+xml," + encodeURIComponent(
            '<svg xmlns="http://www.w3.org/2000/svg" width="488" height="680">'
            + '<rect width="488" height="680" fill="red"/>'
            + '<rect x="' + data.x + '" y="' + data.y + '" width="' + data.w
            + '" height="' + data.h + '" fill="lime"/></svg>')})
        const state = snapshot()
        state.zones.find(zone => zone.zone === "battlefield" && zone.ownerSeat === 0)
            .cards[0].identity = {name:name, setCode:"TST", collectorNumber:"1"}
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        verify(waitForRendering(table))
        const tile = item("forgeCard-own-0"), art = item("forgeCardArt-own-0")
        compare(tile.displayName, name)
        tryCompare(art, "status", Image.Ready)
        tryCompare(tile, "artFrame", data.frame)
        mouseMove(table, table.width - 2, 2)
        table.inspector.clear()
        // The centered row can be underneath the brief new-turn callout.
        // Sample the card artwork after that independent overlay has left.
        tryCompare(item("forgeTurnCallout"), "visible", false, 3000)
        verify(waitForPolish(window))
        const pixels = grabImage(table)
        for (const x of [0.3, 0.5, 0.7]) {
            for (const y of (data.frame === "planeswalker" ? [0.35,0.65,0.9] : [0.35,0.5,0.65])) {
                const point = tile.mapToItem(table, tile.width*x, tile.height*y)
                const px = Math.round(point.x), py = Math.round(point.y)
                verify(pixels.green(px, py) > pixels.red(px, py) * 2,
                       "Printed text outside the art region must not enter the cropped tile: "
                       + [data.frame, tile.width, tile.height, px, py, pixels.red(px, py), pixels.green(px, py),
                          art.width, art.height, art.rotation, art.implicitWidth, art.implicitHeight].join(","))
            }
        }
        const calls = catalog.artFrameRequests.length
        window.width -= 40
        verify(waitForRendering(tile))
        compare(catalog.artFrameRequests.length, calls, "Resizing must not repeat metadata lookups")
    }
    function test_hiddenFacesNeverRequestArtFrameMetadata() {
        const state = snapshot()
        const hidden = state.zones.find(zone => zone.zone === "battlefield" && zone.ownerSeat === 0).cards[0]
        hidden.identity = {name:"Secret face"}
        hidden.faceDown = true
        verify(testRulesPrompt.applySnapshot(state))
        verify(waitForRendering(table))
        const tile = item("forgeCard-own-0")
        verify(!tile.publicFace)
        compare(tile.artFrame, "full")
        verify(catalog.artFrameRequests.indexOf("Secret face") < 0)
        catalog.language = "zh"
        catalog.artCacheContentsChanged()
        verify(waitForRendering(tile))
        verify(catalog.artFrameRequests.indexOf("Secret face") < 0)
    }
}
