// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"
import "../../qml/components"

TestCase {
    id: testCase
    name: "ResponsiveForms"
    when: windowShown

    ApplicationWindow {
        id: window
        width: 900
        height: 620
        visible: true
        property string pushedScreen: ""
        function pushScreen(path) { pushedScreen = path }
        function popScreen() { }
        function showBanner(message) { }
    }
    QtObject {
        id: connection
        property bool inRoom: false
        property bool connected: true
        property var roomList: []
        property string joinedRoom: ""
        property string lastError: ""
        property int joins: 0
        property int eventRequests: 0
        property int roomRequests: 0
        property int eventEntries: 0
        function requestTournamentList() { eventRequests++ }
        function enterTournament(code) { eventEntries++ }
        function joinRoom(code, spectator, password) { joins++; joinedRoom = code }
        function hasCubeRoomCredential(code) { return true }
        function requestRoomList() { roomRequests++ }
    }
    QtObject {
        id: library
        signal deckImportFinished(bool success)
        property bool importingDeck: false
        property string importStage: ""
        property string lastError: ""
        property var lastImportWarnings: []
        property int imports: 0
        function clearLastError() { lastError = "" }
        function importDeckAsync(name, format, text) { imports++ }
    }
    Component {
        id: importComponent
        ImportDeck { property var deckLibrary: library }
    }
    Component {
        id: joinComponent
        JoinRoom { property var ws: connection }
    }
    Component {
        id: confirmComponent
        ConfirmDialog { }
    }
    Component {
        id: roomsComponent
        RoomBrowser { property var ws: connection }
    }
    Component {
        id: headerComponent
        ScreenHeader { }
    }
    QtObject {
        id: eventModel
        property var historicalTournamentList: []
        property var activeTournamentList: []
    }
    Component {
        id: eventsComponent
        TournamentBrowser {
            property var ws: connection
            property var tournament: eventModel
        }
    }
    function init() {
        connection.lastError = ""
        connection.connected = true
        connection.roomRequests = 0
        connection.eventEntries = 0
        connection.joins = 0
        library.imports = 0
        window.pushedScreen = ""
        connection.eventRequests = 0
        connection.roomList = []
        testTranslations.setLanguage("zh")
    }
    function cleanup() {
        Theme.uiScale = 1
        testTranslations.setLanguage("en")
    }
    function test_import_data() {
        return [
            {tag: "minimum", w: 900, h: 620, scale: 1},
            {tag: "scaled", w: 1280, h: 800, scale: 1.25},
            {tag: "large-text", w: 900, h: 620, scale: 1.5}
        ]
    }
    function test_browsersOfferConnectionAfterDisconnect() {
        window.width = 900; window.height = 620; Theme.uiScale = 1.5
        const rooms = createTemporaryObject(roomsComponent, window.contentItem,
                                            {width: 900, height: 620})
        const events = createTemporaryObject(eventsComponent, window.contentItem,
                                             {width: 900, height: 620})
        compare(connection.roomRequests, 1)
        compare(connection.eventRequests, 1)
        connection.connected = false
        waitForRendering(events)
        for (const name of ["tournamentRefreshButton", "tournamentCreateButton", "tournamentHistoryButton"])
            compare(findChild(events, name).enabled, false, name)
        const code = findChild(events, "tournamentCodeField")
        code.text = "ABC123"
        code.forceActiveFocus()
        keyClick(Qt.Key_Return)
        events.openEvent("ABC123")
        compare(connection.eventEntries, 0)
        mouseClick(findChild(events, "tournamentBrowserConnectButton"))
        compare(window.pushedScreen, "screens/Connect.qml")
        events.visible = false
        compare(findChild(rooms, "emptyRoomCreateButton").visible, false)
        compare(findChild(rooms, "emptyRoomRefreshButton").visible, false)
        rooms.joinRoom({roomId: "ABC123", hasPassword: false}, false)
        compare(connection.joins, 0)
        window.pushedScreen = ""
        const body = findChild(rooms, "roomBrowserBody")
        body.contentY = Math.max(0, body.contentHeight - body.height)
        waitForRendering(rooms)
        mouseClick(findChild(rooms, "roomBrowserConnectButton"))
        compare(window.pushedScreen, "screens/Connect.qml")
    }
    function test_browsersDoNotRequestListsWhileOffline() {
        connection.connected = false
        const rooms = createTemporaryObject(roomsComponent, window.contentItem,
                                            {width: 900, height: 620})
        const events = createTemporaryObject(eventsComponent, window.contentItem,
                                             {width: 900, height: 620})
        verify(rooms !== null && events !== null)
        compare(connection.roomRequests, 0)
        compare(connection.eventRequests, 0)
    }
    function test_longHeaderWrapsWithinWindow() {
        Theme.uiScale = 1.8
        testTranslations.setLanguage("en")
        const header = createTemporaryObject(headerComponent, window.contentItem,
                                             {width: 784,
                                              title: "A long saved deck name ".repeat(4),
                                              subtitle: "Detailed screen guidance ".repeat(6)})
        verify(header !== null)
        waitForRendering(header)
        for (const name of ["screenHeaderTitle", "screenHeaderSubtitle"]) {
            const text = findChild(header, name)
            verify(text.lineCount > 1)
            verify(text.paintedWidth <= text.width + 1)
            const point = text.mapToItem(header, 0, 0)
            verify(point.x + text.width <= header.width + 1)
            verify(point.y + text.height <= header.height + 1)
        }
    }
    function test_eventActionsStayInsideWindow_data() {
        return [
            {tag: "desktop", w: 1280, h: 800, scale: 1, language: "en"},
            {tag: "compact-zh", w: 900, h: 620, scale: 1.25, language: "zh"},
            {tag: "large-en", w: 900, h: 620, scale: 1.5, language: "en"},
            {tag: "large-zh", w: 900, h: 620, scale: 1.5, language: "zh"}
        ]
    }
    function test_eventActionsStayInsideWindow(data) {
        window.width = data.w; window.height = data.h; Theme.uiScale = data.scale
        testTranslations.setLanguage(data.language)
        const page = createTemporaryObject(eventsComponent, window.contentItem,
                                           {width: data.w, height: data.h})
        verify(page !== null)
        waitForRendering(page)
        const actions = ["tournamentCodeField", "tournamentOpenButton", "tournamentHistoryButton",
                         "tournamentRefreshButton", "tournamentCreateButton"]
        for (const name of actions) {
            const action = findChild(page, name)
            verify(action !== null)
            const point = action.mapToItem(page, 0, 0)
            verify(point.x >= 0 && point.x + action.width <= page.width, name + " horizontal bounds")
            verify(point.y >= 0 && point.y + action.height <= page.height, name + " vertical bounds")
        }
        mouseClick(findChild(page, "tournamentRefreshButton"))
        compare(connection.eventRequests, 2)
        mouseClick(findChild(page, "tournamentCreateButton"))
        compare(window.pushedScreen, "screens/TournamentCreate.qml")
    }
    function test_import(data) {
        window.width = data.w; window.height = data.h; Theme.uiScale = data.scale
        const page = createTemporaryObject(importComponent, window.contentItem,
                                           {width: data.w, height: data.h})
        verify(page !== null)
        const name = findChild(page, "importDeckName")
        const text = findChild(page, "importDeckText")
        name.text = "Audit deck"
        text.text = "Deck\n60 Island"
        const body = findChild(page, "importDeckBody")
        const button = findChild(page, "importDeckSubmitButton")
        waitForRendering(page)
        body.contentY = Math.max(0, body.contentHeight - body.height)
        waitForRendering(page)
        const point = button.mapToItem(body, 0, 0)
        verify(point.y >= -1 && point.y + button.height <= body.height + 1)
        verify(point.x >= -1 && point.x + button.width <= body.width + 1)
        mouseClick(button)
        compare(library.imports, 1)
        page.importCompleted = true
        page.importWarningMessage = "Warning\n".repeat(30)
        waitForRendering(page)
        verify(body.contentHeight > body.height)
    }
    function test_joinWithLongErrorAndScale() {
        window.width = 900; window.height = 620; Theme.uiScale = 1.5
        const page = createTemporaryObject(joinComponent, window.contentItem,
                                           {width: 900, height: 620, roomCode: "ABC123"})
        verify(page !== null)
        connection.lastError = "The room is unavailable. ".repeat(25)
        waitForRendering(page)
        const body = findChild(page, "joinRoomBody")
        const button = findChild(page, "joinRoomSubmitButton")
        verify(body.contentHeight > body.height)
        body.contentY = body.contentHeight - body.height
        waitForRendering(page)
        const point = button.mapToItem(body, 0, 0)
        verify(point.y >= -1 && point.y + button.height <= body.height + 1)
        mouseClick(button)
        compare(connection.joins, 1)
    }

    function test_roomActionsRemainReachable_data() {
        return [{tag: "large", scale: 1.5}, {tag: "maximum", scale: 1.8}]
    }
    function test_roomActionsRemainReachable(data) {
        window.width = 900; window.height = 620; Theme.uiScale = data.scale
        testTranslations.setLanguage("en")
        connection.roomList = [{roomId: "ABC123", name: "A long Commander Cube room name",
                                roomKind: "cube", format: "edh", matchMode: "bo1", phase: "free_play",
                                hasPassword: false, spectatorsSeeHands: true, playerCount: 4,
                                maxSeats: 8, spectatorCount: 2, playerJoinable: false,
                                spectatorJoinable: true}]
        const page = createTemporaryObject(roomsComponent, window.contentItem,
                                           {width: 900, height: 620})
        verify(page !== null)
        waitForRendering(page)
        const body = findChild(page, "roomBrowserBody")
        body.contentY = Math.max(0, body.contentHeight - body.height)
        waitForRendering(page)
        const join = findChild(page, "joinListedRoomButton")
        const point = join.mapToItem(page, 0, 0)
        verify(point.x >= 0 && point.x + join.width <= page.width)
        verify(point.y >= 0 && point.y + join.height <= page.height)
        mouseClick(join)
        compare(connection.joinedRoom, "ABC123")
        compare(connection.joins, 1)
        body.contentY = 0
        const search = findChild(page, "roomSearchField")
        search.text = "missing"
        search.textEdited()
        waitForRendering(page)
        body.contentY = Math.max(0, body.contentHeight - body.height)
        waitForRendering(page)
        verify(findChild(page, "filteredRoomEmptyState").visible)
    }

    function test_importWheelAcrossPage_data() {
        return [
            {tag: "left-gutter", target: "gutter", scale: 1},
            {tag: "name", target: "importDeckName", scale: 1},
            {tag: "format", target: "importDeckFormat", scale: 1},
            {tag: "short-list", target: "importDeckTextScroll", scale: 1},
            {tag: "scaled-list", target: "importDeckTextScroll", scale: 1.25},
            {tag: "small-scaled-margin", target: "gutter", scale: 1.25, width: 900}
        ]
    }

    function test_importWheelAcrossPage(data) {
        window.width = data.width || 1280; window.height = 620; Theme.uiScale = data.scale
        const page = createTemporaryObject(importComponent, window.contentItem,
                                           {width: window.width, height: window.height})
        verify(page !== null)
        const body = findChild(page, "importDeckBody")
        const text = findChild(page, "importDeckText")
        text.text = "Deck\n60 Island"
        text.cursorPosition = 0
        waitForRendering(page)
        verify(body.contentHeight > body.height + 20)
        body.contentY = 0
        if (data.target === "gutter") {
            const point = body.mapToItem(page, 0, 50)
            mouseWheel(page, Theme.pageMargin + 10, point.y, 0, -120)
        } else {
            const target = findChild(page, data.target)
            verify(target !== null)
            mouseWheel(target, target.width / 2, Math.min(20, target.height / 2), 0, -120)
        }
        tryVerify(() => body.contentY > 0, 1000,
                  "Wheel over " + data.target + " must scroll the form")
        compare(page.deckFormat, "modern", "Scrolling must not change the format")
    }

    function test_importLongListChainsAtBoundaries() {
        window.width = 1280; window.height = 700; Theme.uiScale = 1.25
        const page = createTemporaryObject(importComponent, window.contentItem,
                                           {width: window.width, height: window.height})
        const body = findChild(page, "importDeckBody")
        const editor = findChild(page, "importDeckTextScroll")
        const text = findChild(page, "importDeckText")
        text.text = "Deck\n" + "1 Island\n".repeat(100)
        text.cursorPosition = 0
        waitForRendering(page)
        const inner = editor.contentItem
        verify(inner.contentHeight > inner.height + 100)
        verify(body.contentHeight > body.height + 20)
        body.contentY = 0
        inner.contentY = 0
        mouseWheel(editor, editor.width / 2, 20, 0, -120)
        tryVerify(() => inner.contentY > 0)
        compare(body.contentY, 0, "The list scrolls before the page")
        inner.cancelFlick()
        inner.contentY = inner.contentHeight - inner.height
        mouseWheel(editor, editor.width / 2, 20, 0, -120)
        tryVerify(() => body.contentY > 0, 1000,
                  "The page must scroll when the list reaches its bottom")
        body.cancelFlick()
        body.contentY = Math.min(40, body.contentHeight - body.height)
        inner.contentY = 0
        const previous = body.contentY
        mouseWheel(editor, editor.width / 2, 20, 0, 120)
        tryVerify(() => body.contentY < previous, 1000,
                  "The page must scroll up when the list reaches its top")
    }

    function test_importListRetainsHorizontalScrolling() {
        window.width = 900; window.height = 620; Theme.uiScale = 1
        const page = createTemporaryObject(importComponent, window.contentItem,
                                           {width: window.width, height: window.height})
        const editor = findChild(page, "importDeckTextScroll")
        const text = findChild(page, "importDeckText")
        text.text = "1 " + "Long card name ".repeat(30)
        text.cursorPosition = 0
        waitForRendering(page)
        const inner = editor.contentItem
        verify(inner.contentWidth > inner.width + 100)
        inner.contentX = 0
        mouseWheel(editor, editor.width / 2, 20, -120, 0)
        tryVerify(() => inner.contentX > 0, 1000,
                  "Horizontal wheel still scrolls long, unwrapped lines")
    }
    function test_longConfirmationKeepsActionsVisible() {
        window.width = 900; window.height = 620; Theme.uiScale = 1.25
        const popup = createTemporaryObject(confirmComponent, window.contentItem,
                                            {message: "Detailed confirmation\n".repeat(40)})
        popup.open()
        tryCompare(popup, "opened", true)
        waitForRendering(popup.contentItem)
        verify(popup.y >= 0)
        verify(popup.y + popup.height <= window.height)
        const cancel = findChild(popup, "cancelButton")
        const point = cancel.mapToItem(window.contentItem, 0, 0)
        verify(point.y >= 0 && point.y + cancel.height <= window.height)
        mouseClick(cancel)
        tryCompare(popup, "opened", false)
    }
}
