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
}
