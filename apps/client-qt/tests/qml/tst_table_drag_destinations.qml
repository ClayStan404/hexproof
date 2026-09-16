// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "TableDragDestinations"
    when: windowShown

    readonly property alias testWindow: harness.testWindowObject
    readonly property alias tableHost: harness.tableHostObject
    readonly property alias mockWs: harness.mockWsObject
    readonly property alias tableComponent: harness.tableComponentObject

    MatchLoadingTestHarness {
        id: harness
        testCase: testCase
    }

    function init() { verify(harness.reset()) }
    function cleanup() { harness.cleanupHarness() }

    function test_fastDragsPreserveTheGrabPointAndDestination_data() {
        return [{tag: "battlefield-center", zone: "battlefield"},
                {tag: "tapped-battlefield-edge", zone: "battlefield", edge: true, tapped: true},
                {tag: "stack-edge", zone: "stack", edge: true},
                {tag: "reveal-divider-edge", zone: "reveal", edge: true}]
    }

    function test_fastDragsPreserveTheGrabPointAndDestination(data) {
        const seats = JSON.parse(JSON.stringify(mockWs.gameSeats))
        const identity = {id: "position-proof", name: "Grizzly Bears", ownerSeat: 0,
                          typeLine: "Creature — Bear", tapped: data.tapped === true,
                          position: {x: 0.72, y: 0.55}}
        seats[0].battlefield = data.zone === "battlefield" ? [identity] : []
        mockWs.gameSeats = seats
        mockWs.gameStack = data.zone === "stack" ? [identity] : []
        mockWs.gameRevealed = data.zone === "reveal"
            ? [identity, {id: "other-reveal", name: "Island", ownerSeat: 1}]
            : []
        const table = tableComponent.createObject(tableHost, {width: testWindow.width, height: testWindow.height})
        verify(table !== null)
        const battlefield = data.zone === "battlefield"
        let source = null
        tryVerify(() => {
            const area = battlefield ? findChild(table, "battlefieldDrag" + identity.id)
                                     : findChild(table, "sharedCard0")
            source = battlefield && area ? area.parent : area
            return source && source.width > 0 && source.height > 0
        })
        const target = findChild(table, battlefield ? "sharedDropArea" : "ownHand")
        verify(target !== null)
        tryVerify(() => target.width > 0 && target.height > 0)
        wait(100)
        compare(source.modelData.id, identity.id)
        if (data.tapped) tryCompare(source, "rotation", 90)
        if (data.zone === "reveal") verify(source.revealDividerHeight > 0, "The reveal fixture must include its owner divider")
        const pressX = data.edge ? source.width - 2 : source.width / 2
        const pressY = data.edge ? (source.revealDividerHeight || 0) + 2 : source.height / 2
        const press = source.mapToItem(table, pressX, pressY)
        const drop = target.mapToItem(table, battlefield ? target.width / 2 : 10,
                                     battlefield && data.edge ? 10 : target.height / 2)
        mousePress(table, press.x, press.y, Qt.LeftButton)
        wait(20)
        for (let step = 1; step <= 12; ++step) {
            mouseMove(table, press.x + (drop.x - press.x) * step / 12,
                      press.y + (drop.y - press.y) * step / 12, 0, Qt.LeftButton)
            wait(20)
        }
        const hotspot = source.mapToItem(table, source.Drag.hotSpot.x, source.Drag.hotSpot.y)
        mouseRelease(table, drop.x, drop.y, Qt.LeftButton)
        tryCompare(mockWs, "moveCount", 1)
        compare(mockWs.lastMove.cardId, identity.id)
        compare(mockWs.lastMove.fromZone, data.zone)
        compare(mockWs.lastMove.toZone, battlefield ? "stack" : "hand",
                "The pointer's destination must determine the receiving zone")
        verify(Math.abs(hotspot.x - drop.x) <= 1.5 && Math.abs(hotspot.y - drop.y) <= 1.5,
               "Dragging must preserve the actual grab point through threshold, lift and reparenting: hotspot="
               + hotspot + ", pointer=" + drop)
        table.destroy()
    }
}
