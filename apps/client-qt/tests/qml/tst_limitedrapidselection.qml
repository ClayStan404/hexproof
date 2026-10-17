// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "LimitedRapidSelection"
    when: windowShown
    visible: true
    width: 640
    height: 700
    property var selected: []
    QtObject {
        id: catalog
        property int imageRevision: 0
        function tableImageSource() { return "" }
    }
    CardArtGrid {
        id: grid
        anchors.fill: parent
        catalogModel: catalog
        onCardActivated: card => {
            testCase.selected = testCase.selected.concat([card.instanceId])
            cards = cards.filter(c => c.instanceId !== card.instanceId)
        }
    }
    function test_rapidClicksSelectSuccessivePhysicalCardsAtSamePosition() {
        grid.cards = [
            {instanceId:"first", name:"Delver of Secrets", setCode:"ISD", collectorNumber:"51"},
            {instanceId:"second", name:"Delver of Secrets", setCode:"ISD", collectorNumber:"51"},
            {instanceId:"third", name:"Island", setCode:"ISD", collectorNumber:"253"}
        ]
        selected = []
        verify(waitForRendering(grid))
        const tile = findChild(grid, "workbenchCard-first")
        verify(tile)
        const point = tile.mapToItem(grid, tile.width / 2, tile.height / 2)
        mouseDoubleClickSequence(grid, point.x, point.y, Qt.LeftButton)
        compare(selected, ["first", "second"])
        compare(grid.cards.length, 1)
    }
    function populatedGrid(count) {
        selected = []
        grid.cards = Array.from({length: count || 24}, (_, index) => ({instanceId: String(index), name: "Card " + index}))
        grid.positionViewAtBeginning()
        verify(waitForRendering(grid))
    }
    function test_firstClickAfterWheelReachesBoundarySelectsTheVisibleCard() {
        populatedGrid(8)
        mouseWheel(grid, grid.width / 2, grid.height / 2, 0, -12000)
        tryVerify(() => grid.atYEnd && !grid.moving)
        const tile = findChild(grid, "workbenchCard-7")
        verify(tile)
        mouseClick(tile, tile.width / 2, tile.height / 2)
        compare(selected, ["7"])
    }
    function test_draggingCardsScrollsWithoutSelecting() {
        populatedGrid()
        const tile = findChild(grid, "workbenchCard-2")
        verify(tile)
        mouseDrag(tile, tile.width / 2, tile.height / 2, 0, -160, Qt.LeftButton)
        compare(selected.length, 0)
        verify(grid.contentY > 0)
        grid.cancelFlick()
    }
    function test_pausingAnActiveDragDoesNotReleaseTheScrollGrab() {
        populatedGrid()
        const tile = findChild(grid, "workbenchCard-2")
        verify(tile)
        const point = tile.mapToItem(grid, tile.width / 2, tile.height / 2)
        mousePress(grid, point.x, point.y, Qt.LeftButton)
        mouseMove(grid, point.x, point.y - 80, 40)
        mouseMove(grid, point.x, point.y - 160, 40)
        tryVerify(() => grid.dragging)
        const stoppedY = grid.contentY
        wait(250)
        compare(grid.contentY, stoppedY)
        verify(grid.dragging && grid.moving)
        mouseMove(grid, point.x, point.y - 220, 40)
        verify(grid.contentY > stoppedY)
        mouseRelease(grid, point.x, point.y - 220, Qt.LeftButton)
        compare(selected.length, 0)
        tryVerify(() => !grid.moving)
    }
    function test_secondPressCanScrollWithoutAddingTheNextCard() {
        populatedGrid()
        const tile = findChild(grid, "workbenchCard-2")
        verify(tile)
        const point = tile.mapToItem(grid, tile.width / 2, tile.height / 2)
        mouseClick(grid, point.x, point.y, Qt.LeftButton)
        compare(selected, ["2"])
        verify(waitForRendering(grid))
        mousePress(grid, point.x, point.y, Qt.LeftButton)
        mouseMove(grid, point.x, point.y - 80, 40)
        mouseMove(grid, point.x, point.y - 160, 40)
        tryVerify(() => grid.dragging)
        mouseRelease(grid, point.x, point.y - 160, Qt.LeftButton)
        compare(selected, ["2"])
        tryVerify(() => !grid.moving)
        const nextRow = Math.floor((grid.contentY - grid.originY) / grid.cellHeight) + 1
        const nextId = grid.cards[nextRow * grid.columns].instanceId
        const next = findChild(grid, "workbenchCard-" + nextId)
        verify(next)
        mouseClick(next, next.width / 2, next.height / 2)
        compare(selected, ["2", nextId])
    }
    function test_holdingCardWithoutDraggingStillAddsItOnRelease() {
        populatedGrid()
        const tile = findChild(grid, "workbenchCard-0")
        verify(tile)
        mousePress(tile, tile.width / 2, tile.height / 2, Qt.LeftButton)
        wait(1100)
        compare(selected.length, 0)
        mouseRelease(tile, tile.width / 2, tile.height / 2, Qt.LeftButton)
        compare(selected, ["0"])
    }
}
