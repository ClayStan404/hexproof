// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"

TestCase {
    name: "TableSessionBindings"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 1400
        height: 900
        visible: true
        function showBanner(message) { }
        function pushScreen(url) { }
    }

    QtObject {
        id: mockRoomSession
        property string roomId: "ABCDEF"
        property string roomName: "Friday Night"
        property string format: "edh"
        property bool playtest: false
        property string matchMode: "bo1"
        property string cardLoadMode: "preload"
        property int maxSeats: 4
        property string phase: "started"
        property bool host: true
        property string role: "player"
        property int seatIndex: 0
        property string selectedDeckName: "Elves"
        property var seats: []
        property var spectators: []
    }

    QtObject {
        id: mockGameSession
        property int gameNumber: 1
        property int startingSeat: 0
        property var turnOrder: [0, 1, 2, 3]
        property int activeSeat: 0
        property string currentPhase: "precombat_main"
        property var score: [0, 0]
        property var result: ({})
        property var sideboard: ({})
        property bool sideboarding: false
        property bool finished: false
    }

    QtObject {
        id: mockWs
        property var roomSession: mockRoomSession
        property var gameSession: mockGameSession
        property bool inRoom: true
        property string lastError: ""
        property string roomId: "FACADE"
        property string roomName: "Facade Room"
        property int seatIndex: -1
        property int gameNumber: 99
        property string format: "duel"
        property string roomRole: "spectator"
        property var sideboardState: ({})
        property string matchMode: "bo3"
        property var matchScore: [9, 9]
        property var gameResult: ({})
        property bool playtest: true
        property bool youAreHost: false
        signal libraryDumped(var cards, int sourceSeat,
                             string approvalId, int topCount)
        signal libraryAccessRequested(string approvalId,
                                      string requesterName,
                                      int requesterSeat, int topCount)
        signal publicZoneMoveRequested(string approvalId,
                                       string requesterName,
                                       int requesterSeat,
                                       string sourceZone, int cardCount,
                                       string toZone)
        signal gameSnapshotChanged()
        signal commandQueued(string requestId, string commandType,
                             var payload)
        signal commandFailed(string requestId, string commandType,
                             var payload, string error)
        function leaveRoom() { }
        function setReady(ready) { }
        function drawCards(count) { }
        function mulligan() { }
        function nextTurn() { }
        function setPhase(phase) { }
        function chat(text) { }
        function returnToRoom() { }
        function concede() { }
        function declareDraw() { }
        function restartGame() { }
        function rollDice(sides, count) { }
        function flipCoin() { }
        function randomPlayer() { }
        function setCounterCount(count) { }
    }

    QtObject {
        id: mockCatalog
        property bool tokenCatalogInstalled: true
        property bool tokenSearching: false
        property bool busy: false
        property string status: ""
        property var tokenSearchResults: []
        function imageSource(name, setCode, collectorNumber) { return "" }
        function cardFaces(name, setCode, collectorNumber) { return [] }
        function cardTypeLine(name, setCode, collectorNumber) { return "" }
        function matchesCardQuery(name, setCode, collectorNumber, query) {
            return false
        }
        function searchTokens(query) { }
        function cacheToken(token) { }
    }

    QtObject {
        id: mockPreferences
        property bool tableShowPlayers: true
        property bool tableShowShared: true
        property bool tableShowInspector: true
        property bool tableShowGameLog: true
        property int tableCounterCount: 7
    }

    property var table: null

    Component {
        id: tableComponent
        Table {
            wsModel: mockWs
            gameTableModel: testGameTable
            optimisticCommandModel: testOptimisticCommands
            sideboardTableModel: testSideboardTable
            cardCatalogModel: mockCatalog
            preferencesModel: mockPreferences
        }
    }

    function init() {
        mockRoomSession.format = "edh"
        mockRoomSession.playtest = false
        mockRoomSession.phase = "started"
        mockRoomSession.role = "player"
        mockRoomSession.seatIndex = 0
        mockGameSession.finished = false
        mockGameSession.sideboarding = false
        mockGameSession.currentPhase = "precombat_main"
        mockGameSession.activeSeat = 0
        mockGameSession.result = ({})
        mockWs.inRoom = true
        mockWs.roomName = "Facade Room"
        mockWs.roomId = "FACADE"
        mockWs.youAreHost = false
        mockRoomSession.roomName = "Friday Night"
        mockRoomSession.roomId = "ABCDEF"
        mockRoomSession.matchMode = "bo1"
        mockRoomSession.host = true
        mockWs.format = "duel"
        mockWs.roomRole = "spectator"
        mockWs.seatIndex = -1
        mockWs.gameNumber = 99
        mockWs.sideboardState = ({})
        mockGameSession.gameNumber = 1
        mockGameSession.sideboard = ({})
        testGameTable.clear()
        table = tableComponent.createObject(testWindow.contentItem, {
            "width": testWindow.width,
            "height": testWindow.height
        })
        verify(table !== null)
    }

    function cleanup() {
        if (table !== null)
            table.destroy()
        table = null
        testGameTable.clear()
        wait(1)
    }

    function test_derivesCanActAndCanChatFromSessionModels() {
        verify(table.canAct)
        verify(table.canChat)
        verify(table.isEDH)
        verify(!table.isPlaytest)
        verify(!table.gameFinished)
        compare(table.displayedPhase, "precombat_main")
        verify(table.isActivePlayer)
    }

    function test_spectatorsCannotAct() {
        mockRoomSession.role = "spectator"
        verify(!table.canAct)
        verify(table.canChat)
    }

    function test_finishedGameBlocksActions() {
        mockGameSession.finished = true
        mockGameSession.result = {"winnerSeat": 0}
        verify(table.gameFinished)
        verify(!table.canAct)
    }

    function test_actionRailBindsRoomIdentityFromSession() {
        const name = findChild(table, "tableRoomName")
        const code = findChild(table, "tableRoomCode")
        const score = findChild(table, "tableMatchScore")
        const gameNumber = findChild(table, "tableGameNumber")
        verify(name !== null)
        verify(code !== null)
        verify(score !== null)
        verify(gameNumber !== null)
        compare(name.text, "Friday Night")
        compare(code.text, "ROOM CODE · ABCDEF")
        verify(!score.visible)
        compare(gameNumber.text, "Game 1")
    }

    function test_leaveDialogUsesSessionHostRole() {
        const dialog = findChild(table, "leaveRoomConfirmation")
        verify(dialog !== null)
        compare(dialog.titleText, "Disband the room?")
        compare(dialog.confirmText, "Disband")
    }

    function test_sideboardPanelFollowsGameSession() {
        const panel = findChild(table, "sideboardPanel")
        verify(panel !== null)
        verify(!panel.visible)
        mockGameSession.sideboarding = true
        verify(panel.visible)
    }

    function test_responseStatusUsesSessionSeatIndex() {
        mockWs.seatIndex = -1
        mockRoomSession.seatIndex = 0
        const button = findChild(table, "responseStatusButton")
        verify(button !== null)
        verify(button.visible)
    }

    function test_restartActionUsesSessionHost() {
        mockWs.youAreHost = false
        mockRoomSession.host = true
        const action = findChild(table, "restartGameAction")
        verify(action !== null)
        verify(action.enabled)
    }

    function test_sideboardDeckChangesUsesSessionFormat() {
        mockWs.format = "duel"
        mockRoomSession.format = "edh"
        const panel = findChild(table, "sideboardPanel")
        verify(panel !== null)
        verify(panel.deckChangesAllowed)
    }

    function test_sideboardPlayerUsesSessionRole() {
        mockWs.roomRole = "spectator"
        mockRoomSession.role = "player"
        mockGameSession.sideboarding = true
        const panel = findChild(table, "sideboardPanel")
        const tables = findChild(panel, "sideboardTables")
        verify(panel !== null)
        verify(panel.isPlayer)
        verify(tables !== null)
        verify(tables.visible)
    }

    function test_sideboardReadyUsesSessionSeatAndSideboard() {
        mockWs.seatIndex = 1
        mockWs.sideboardState = {
            "seats": [{"seat": 1, "ready": false}]
        }
        mockRoomSession.seatIndex = 0
        mockGameSession.sideboard = {
            "seats": [
                {"seat": 0, "ready": true},
                {"seat": 1, "ready": false}
            ]
        }
        const panel = findChild(table, "sideboardPanel")
        verify(panel !== null)
        verify(panel.ownReady)
    }

    function test_sideboardTitleUsesSessionGameNumber() {
        mockWs.gameNumber = 99
        mockGameSession.gameNumber = 2
        const title = findChild(table, "sideboardGameTitle")
        verify(title !== null)
        compare(title.text, "Sideboard · Game 2 → 3")
    }

    function test_ownLibraryActionsUseSessionSeatIndex() {
        mockWs.seatIndex = -1
        mockRoomSession.seatIndex = 0
        verify(findChild(table, "drawCardButton0") !== null)
        verify(findChild(table, "searchLibraryButton0") !== null)
        verify(findChild(table, "drawCardButton-1") === null)
    }

    function test_ownLifeControlsUseSessionRoleAndSeat() {
        mockWs.roomRole = "spectator"
        mockWs.seatIndex = -1
        mockRoomSession.role = "player"
        mockRoomSession.seatIndex = 0
        const decrease = findChild(table, "decreaseLifeButton0")
        verify(decrease !== null)
        verify(decrease.visible)
        verify(findChild(table, "decreaseLifeButton-1") === null)
    }
}
