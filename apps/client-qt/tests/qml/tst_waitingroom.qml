// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"
import "../../qml/components"

TestCase {
    name: "WaitingRoom"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 1400
        height: 900
        visible: true
        property string lastBanner: ""
        function showBanner(message) { lastBanner = message }
        function pushScreen(url) { }
    }

    QtObject {
        id: mockRoomSession
        property string roomId: "ABCDEF"
        property string roomName: "Friday Night"
        property string format: "modern"
        property string deckFormat: "modern"
        property bool playtest: false
        property string matchMode: "bo3"
        property string cardLoadMode: "preload"
        property int maxSeats: 2
        property string phase: "waiting"
        property bool host: true
        property string role: "player"
        property int seatIndex: 0
        property string selectedDeckName: "Burn"
        property var seats: [{
            "occupied": true,
            "displayName": "Alice",
            "host": true,
            "deckSelected": true,
            "ready": false
        }, {
            "occupied": false,
            "displayName": "",
            "host": false,
            "deckSelected": false,
            "ready": false
        }]
        property var spectators: []
    }

    QtObject {
        id: mockWs
        property var roomSession: mockRoomSession
        property string lastError: ""
        property int copyCount: 0
        property string lastCopied: ""
        function copyToClipboard(text) {
            ++copyCount
            lastCopied = text
        }
        function setReady(ready) { }
        function leaveRoom() { }
        function disbandRoom() { }
        function kickSeat(seat) { }
        function selectDeck(deck) { }
        function kickSpectator(index) { }
    }

    QtObject {
        id: mockDeckLibrary
        property var decks: []
        function deckForMatch() { return ({}) }
        function setActiveMatchDeck() { }
    }

    property var page: null

    Component {
        id: pageComponent
        WaitingRoom {
            wsModel: mockWs
            deckLibraryModel: mockDeckLibrary
        }
    }

    function init() {
        testWindow.lastBanner = ""
        mockWs.copyCount = 0
        mockWs.lastCopied = ""
        mockRoomSession.roomName = "Friday Night"
        mockRoomSession.roomId = "ABCDEF"
        mockRoomSession.format = "modern"
        mockRoomSession.deckFormat = "modern"
        mockRoomSession.maxSeats = 2
        mockRoomSession.playtest = false
        mockRoomSession.host = true
        mockRoomSession.role = "player"
        mockRoomSession.selectedDeckName = "Burn"
        mockRoomSession.seats = [{
            "occupied": true,
            "displayName": "Alice",
            "host": true,
            "deckSelected": true,
            "ready": false
        }, {
            "occupied": false,
            "displayName": "",
            "host": false,
            "deckSelected": false,
            "ready": false
        }]
        page = pageComponent.createObject(testWindow.contentItem)
        verify(page !== null)
        page.anchors.fill = testWindow.contentItem
    }

    function cleanup() {
        testWindow.width = 1400
        testWindow.height = 900
        if (page !== null)
            page.destroy()
        page = null
    }

    function test_showsRoomNameAndCodeFromSession() {
        const title = findChild(page, "waitingRoomTitle")
        const code = findChild(page, "waitingRoomCode")
        verify(title !== null)
        verify(code !== null)
        compare(title.text, "Friday Night")
        compare(code.text, "ABCDEF")
    }

    function test_fallsBackToUntitledRoomName() {
        mockRoomSession.roomName = ""
        const title = findChild(page, "waitingRoomTitle")
        verify(title !== null)
        compare(title.text, "Untitled room")
    }

    function test_copyRoomCodeUsesSessionId() {
        const copyButton = findChild(page, "copyRoomCodeButton")
        verify(copyButton !== null)
        mouseClick(copyButton)
        compare(mockWs.copyCount, 1)
        compare(mockWs.lastCopied, "ABCDEF")
        compare(testWindow.lastBanner, "Room code copied")
    }

    function test_readyBlockerExplainsMissingSeatAndDeck() {
        const reason = findChild(page, "readyBlockerText")
        const ready = findChild(page, "playerReadyButton")
        verify(reason !== null)
        verify(ready !== null)
        compare(reason.text, "Waiting for 1 more player")
        compare(ready.disabledReason, reason.text)

        mockRoomSession.seats = [{
            "occupied": true,
            "displayName": "Alice",
            "host": true,
            "deckSelected": false,
            "ready": false
        }, {
            "occupied": true,
            "displayName": "Bob",
            "host": false,
            "deckSelected": true,
            "ready": false
        }]
        tryCompare(reason, "text", "Select a deck before readying up")
        compare(ready.disabledReason, reason.text)
    }

    function test_edhCanReadyWithThreeOfFourPlayers() {
        mockRoomSession.format = "edh"
        mockRoomSession.deckFormat = "commander"
        mockRoomSession.maxSeats = 4
        mockRoomSession.seats = [{
            "occupied": true,
            "displayName": "Alice",
            "host": true,
            "deckSelected": true,
            "ready": false
        }, {
            "occupied": true,
            "displayName": "Bob",
            "host": false,
            "deckSelected": true,
            "ready": false
        }, {
            "occupied": false,
            "displayName": "",
            "host": false,
            "deckSelected": false,
            "ready": false
        }, {
            "occupied": false,
            "displayName": "",
            "host": false,
            "deckSelected": false,
            "ready": false
        }]
        const reason = findChild(page, "readyBlockerText")
        const ready = findChild(page, "playerReadyButton")
        const status = findChild(page, "waitingRoomSeatStatus")
        verify(reason !== null)
        verify(ready !== null)
        verify(status !== null)
        tryCompare(reason, "text", "Waiting for 1 more player")
        verify(!ready.enabled)

        const threeSeats = mockRoomSession.seats.slice()
        threeSeats[2] = {
            "occupied": true,
            "displayName": "Carol",
            "host": false,
            "deckSelected": true,
            "ready": false
        }
        mockRoomSession.seats = threeSeats
        tryCompare(reason, "text", "")
        tryVerify(() => ready.enabled)
        compare(status.text, "Ready to start")
    }

    function test_stacksDetailsBelowSeatsInCompactLayout() {
        testWindow.width = 900
        testWindow.height = 620
        tryVerify(() => page.compactLayout)
        const content = findChild(page, "waitingRoomContent")
        const seats = findChild(page, "waitingRoomSeats")
        const details = findChild(page, "waitingRoomDetails")
        verify(content !== null)
        verify(seats !== null)
        verify(details !== null)
        compare(content.columns, 1)
        tryVerify(() => details.y >= seats.y + seats.height - 1)
        tryVerify(() => seats.width >= content.width - 8)
        tryVerify(() => details.width >= content.width - 8)
        testWindow.width = 1400
        testWindow.height = 900
        tryVerify(() => !page.compactLayout)
        compare(content.columns, 2)
        tryVerify(() => details.x >= seats.x + seats.width - 1)
    }

    function seatRows(seatsItem) {
        const rows = []
        function walk(item) {
            if (!item || item.children === undefined)
                return
            for (let i = 0; i < item.children.length; ++i) {
                const child = item.children[i]
                if (child.objectName === "waitingRoomSeatRow")
                    rows.push(child)
                walk(child)
            }
        }
        walk(seatsItem)
        return rows
    }

    function test_sizesCompactSeatsToFitFourRows() {
        mockRoomSession.format = "edh"
        mockRoomSession.deckFormat = "commander"
        mockRoomSession.maxSeats = 4
        mockRoomSession.seats = [{
            "occupied": true,
            "displayName": "Alice",
            "host": true,
            "deckSelected": true,
            "ready": false
        }, {
            "occupied": true,
            "displayName": "Bob",
            "host": false,
            "deckSelected": true,
            "ready": false
        }, {
            "occupied": false,
            "displayName": "",
            "host": false,
            "deckSelected": false,
            "ready": false
        }, {
            "occupied": false,
            "displayName": "",
            "host": false,
            "deckSelected": false,
            "ready": false
        }]
        testWindow.width = 900
        testWindow.height = 620
        tryVerify(() => page.compactLayout)
        const seats = findChild(page, "waitingRoomSeats")
        verify(seats !== null)
        tryVerify(() => {
            const rows = seatRows(seats)
            if (rows.length !== 4)
                return false
            return rows.every(row => row.height >= Theme.size(66) - 1
                              && row.y + row.height <= seats.height + 1)
        })
        testWindow.width = 1400
        testWindow.height = 900
    }

    function test_movesSecondaryActionsIntoOverflowInCompactLayout() {
        testWindow.width = 900
        testWindow.height = 620
        tryVerify(() => page.compactLayout)
        const overflow = findChild(page, "waitingRoomOverflowButton")
        const deckLibrary = findChild(page, "waitingRoomDeckLibraryButton")
        const leave = findChild(page, "waitingRoomLeaveButton")
        const disband = findChild(page, "waitingRoomDisbandButton")
        const ready = findChild(page, "playerReadyButton")
        verify(overflow !== null)
        verify(deckLibrary !== null)
        verify(leave !== null)
        verify(disband !== null)
        verify(ready !== null)
        verify(overflow.visible)
        verify(!deckLibrary.visible)
        verify(!leave.visible)
        verify(!disband.visible)
        verify(ready.visible)
        overflow.clicked()
        const menu = findChild(page, "waitingRoomOverflowMenu")
        verify(menu !== null)
        tryVerify(() => menu.opened)
        const overflowLeave = findChild(page, "overflowLeaveAction")
        verify(overflowLeave !== null)
        verify(overflowLeave.visible)
        testWindow.width = 1400
        testWindow.height = 900
        tryVerify(() => !page.compactLayout)
        tryVerify(() => deckLibrary.visible)
        verify(!overflow.visible)
    }

    function test_keepsActionButtonsRightAlignedOnWideLayout() {
        tryVerify(() => !page.compactLayout)
        const host = findChild(page, "waitingRoomActionsHost")
        const actions = findChild(page, "waitingRoomActions")
        verify(host !== null)
        verify(actions !== null)
        verify(findChild(page, "waitingRoomSelectDeckButton") !== null)
        verify(findChild(page, "playerReadyButton") !== null)
        verify(findChild(page, "waitingRoomDeckLibraryButton") !== null)
        tryVerify(() => host.width > actions.width + 40)
        tryVerify(() => actions.x > host.width / 2)
        tryVerify(() => Math.abs((actions.x + actions.width) - host.width) <= 1)
    }
}
