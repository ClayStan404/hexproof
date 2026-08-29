// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "TableHandArea"
    width: 1000
    height: 320

    QtObject {
        id: fakeWs
        property int seatIndex: 0
        property string roomRole: "player"
        property int drawCalls: 0
        property int dumpCalls: 0
        function drawCards() { ++drawCalls }
        function dumpLibrary() { ++dumpCalls }
    }

    QtObject {
        id: fakeRoomSession
        property int seatIndex: fakeWs.seatIndex
        property string role: fakeWs.roomRole
    }

    QtObject {
        id: fakeMenu
        property real x: 0
        property real y: 0
        property int openCalls: 0
        function open() { ++openCalls }
    }

    QtObject {
        id: fakeBrowser
        property int showCalls: 0
        property string lastZone: ""
        function showZone(displayName, seat, zone) {
            ++showCalls
            lastZone = zone
        }
    }

    QtObject {
        id: fakeMoves
        property int libraryDropCalls: 0
        property int publicDropCalls: 0
        function canMoveToHand() { return true }
        function moveCardToShared() {}
        function finishLibraryDrop() { ++libraryDropCalls }
        function finishPublicZoneDrop() { ++publicDropCalls }
    }

    QtObject {
        id: fakeProjection
        function visibleOwnHandCount() { return 0 }
        function finishHandDrag() {}
    }

    QtObject {
        id: fakeOptimistic
        function isCardPendingFrom() { return false }
    }

    QtObject {
        id: fakeSession
        function counterShortcutBlocked() { return false }
    }

    QtObject {
        id: fakePresentation
        property int inspectCalls: 0
        property int hideCalls: 0
        function tableCardImageSource() { return "" }
        function inspectCard() { ++inspectCalls }
        function hideCardPreview() { ++hideCalls }
    }

    QtObject {
        id: fakeZoneState
        property var graveyardCard: ({"id": "grave-1", "name": "Grave"})
        property var exileCard: ({"id": "exile-1", "name": "Exile"})
        property var commandCards: [{"id": "commander-1", "name": "Leader"}]
        function displayedPublicZoneTopCard(seat, zone) {
            return zone === "graveyard" ? graveyardCard : exileCard
        }
        function zoneCardCount(seat, zone) {
            if (zone === "command")
                return commandCards.length
            return 1
        }
        function zoneCardsForSeat(seat, zone) {
            return zone === "command" ? commandCards : []
        }
    }

    QtObject {
        id: fakeGameValues
        property int life: 20
        property int counterAdjustCalls: 0
        property int commanderAdjustCalls: 0
        function displayedCounterValue(seat, counter) {
            return counter.value
        }
        function adjustCounter() { ++counterAdjustCalls }
        function commanderTaxDisplayName(card, index) {
            return card && card.name ? card.name : "Commander " + (index + 1)
        }
        function displayedCommanderTax() { return 0 }
        function adjustCommanderTax() { ++commanderAdjustCalls }
        function displayedLife() { return life }
        function setLife(value) { life = value }
    }

    QtObject {
        id: fakeLifeEditor
        property int showCalls: 0
        function showFor() { ++showCalls }
    }

    Item {
        id: fakeTable
        width: testCase.width
        height: testCase.height

        property var wsModel: fakeWs
        property var roomSession: fakeRoomSession
        property var ownSeatData: ({
            "displayName": "Alice",
            "counters": [],
            "libraryCount": 12
        })
        property var ownCommanderCards: [{
            "id": "commander-1",
            "name": "Leader, Example"
        }]
        property var ownHand: []
        property var selectedHandCard: ({})
        property var gameValues: fakeGameValues
        property var zoneState: fakeZoneState
        property var presentation: fakePresentation
        property var cardMoveCommands: fakeMoves
        property var projectionSync: fakeProjection
        property var optimisticCommands: fakeOptimistic
        property var sessionUi: fakeSession
        property var ownLibraryMenu: fakeMenu
        property var handAreaMenu: fakeMenu
        property var handCardMenu: fakeMenu
        property var publicZoneBrowser: fakeBrowser
        property var lifeEditor: fakeLifeEditor
        property bool canAct: true
        property bool tableModalOpen: false
        property bool isCommanderFormat: true
        property bool hasPartnerCommanders: false
        property int visibleCounterCount: 0
        property int selectedCounterSeat: -1
        property string selectedCounterKey: ""
        property real handAreaHeight: 196
        property real handCardWidth: 86
        property url cardBackSource: ""
    }

    TableHandArea {
        id: handArea
        parent: fakeTable
        width: fakeTable.width
        height: 196
        tableController: fakeTable
    }

    function init() {
        fakeWs.drawCalls = 0
        fakeWs.dumpCalls = 0
        fakeBrowser.showCalls = 0
        fakeBrowser.lastZone = ""
        fakeGameValues.life = 20
        fakeLifeEditor.showCalls = 0
        fakeZoneState.graveyardCard = ({"id": "grave-1", "name": "Grave"})
        fakeZoneState.exileCard = ({"id": "exile-1", "name": "Exile"})
    }

    function test_composesHandAndOwnZones() {
        verify(findChild(handArea, "ownHand") !== null)
        verify(findChild(handArea, "ownZoneDock") !== null)
        verify(findChild(handArea, "ownLibraryCardBack") !== null)
        verify(findChild(handArea, "graveyardDragCard0") !== null)
        verify(findChild(handArea, "exileDragCard0") !== null)
        verify(findChild(handArea, "ownCommanderCard0") !== null)
    }

    function test_libraryActionsRemainWired() {
        findChild(handArea, "drawCardButton0").trigger()
        findChild(handArea, "searchLibraryButton0").trigger()
        compare(fakeWs.drawCalls, 1)
        compare(fakeWs.dumpCalls, 1)
    }

    function test_lifeControlsRemainWired() {
        findChild(handArea, "increaseLifeButton0").clicked()
        compare(fakeGameValues.life, 21)
        findChild(handArea, "decreaseLifeButton0").clicked()
        compare(fakeGameValues.life, 20)
        findChild(handArea, "setLifeButton0").clicked()
        compare(fakeLifeEditor.showCalls, 1)
    }

    function test_publicZoneBrowsersRemainWired() {
        const graveyard = findChild(handArea, "graveyardBrowserButton0")
        const exile = findChild(handArea, "exileBrowserButton0")
        graveyard.clicked(null)
        compare(fakeBrowser.lastZone, "graveyard")
        exile.clicked(null)
        compare(fakeBrowser.lastZone, "exile")
        compare(fakeBrowser.showCalls, 2)
    }
}
