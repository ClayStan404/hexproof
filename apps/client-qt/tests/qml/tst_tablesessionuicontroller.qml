// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "TableSessionUiController"

    QtObject {
        id: fakeWs
        property int setCounterCountCalls: 0
        property int lastCounterCount: -1

        function setCounterCount(value) {
            ++setCounterCountCalls
            lastCounterCount = value
        }
    }

    QtObject {
        id: fakeRoomSession
        property string role: "player"
        property int seatIndex: 0
        property string matchMode: "bo3"
        property string roomId: "PAIR01"
    }

    QtObject {
        id: fakeGameSession
        property bool sideboarding: false
        property int gameNumber: 1
        property var score: [1, 0]
        property int drawnGames: 0
        property var result: ({
            "winnerSeat": 0,
            "concededSeat": 1,
            "reason": "concede",
            "matchFinished": true
        })
    }

    QtObject {
        id: fakeSettingsPopup
        property int calls: 0
        property var capturedArgs: []
        function showFor() {
            ++calls
            capturedArgs = Array.prototype.slice.call(arguments)
        }
    }

    QtObject {
        id: fakeResultPopup
        property int openCalls: 0
        function open() { ++openCalls }
    }

    QtObject {
        id: fakeChatInput
        property bool activeFocus: false
    }

    QtObject {
        id: fakeCounterLabelEditor
        property int calls: 0
        property var capturedArgs: []
        function showFor() {
            ++calls
            capturedArgs = Array.prototype.slice.call(arguments)
        }
    }

    QtObject {
        id: fakeCounterValueEditor
        property int calls: 0
        property int value: -1
        function showFor(next) { ++calls; value = next }
    }

    QtObject {
        id: fakeLibraryMoveEditor
        property int calls: 0
        property int value: -1
        function showFor(next) { ++calls; value = next }
    }

    QtObject {
        id: fakePreferences
        property bool tableShowGameLog: true
        property bool tableShowPlayers: true
        property bool tableShowShared: true
        property bool tableShowInspector: true
        property int tableCounterCount: 0
    }

    QtObject {
        id: fakeTournament
        property bool inTournament: false
        property string lastRoomId: ""
        property var lastSeats: []
        property int lastDrawn: -1
        function rememberTabletopScore(roomId, seats, drawnGames) {
            lastRoomId = roomId
            lastSeats = seats
            lastDrawn = drawnGames
        }
    }

    QtObject {
        id: fakeTable
        property var transientState: fakeTable
        property var optimisticCommands: fakeTable
        property var seatState: fakeTable
        property var battlefieldScene: fakeTable
        property var wsModel: fakeWs
        property var roomSession: fakeRoomSession
        property var gameSession: fakeGameSession
        property var preferencesModel: fakePreferences
        property var tournamentModel: fakeTournament
        property bool tableModalOpen: false
        property bool gameFinished: false
        property bool compactLayout: false
        property bool compactChromeTouched: false
        property var ownSeatData: ({"seat": 0, "counterCount": 2})
        property var winnerData: ({"displayName": "Alice"})
        property var concededData: ({"displayName": "Bob"})
        property var authoritativeSeats: [{
            "displayName": "Alice"
        }, {
            "displayName": "Bob"
        }]
        property int selectedCounterSeat: 0
        property string selectedCounterKey: "energy"
        property string libraryMoveDestination: ""
        property bool showPlayerColumn: true
        property bool showSharedColumn: true
        property bool showInspectorColumn: true
        property bool showGameLogRail: true
        property int visibleCounterCount: 2
        property int counterCountRequestGame: -1
        property int counterCountRequestValue: -1
        property int clearCounterCalls: 0
        property int resetCounterRequestCalls: 0
        property int pointRefreshCalls: 0
        property var seats: ({
            "0": {
                "displayName": "Alice",
                "counters": [{
                    "key": "energy",
                    "label": "Energy",
                    "value": 3
                }]
            }
        })

        function seatData(seat) { return seats[String(seat)] || ({}) }
        function clearCounterSelection() { ++clearCounterCalls }
        function resetCounterCountRequest() { ++resetCounterRequestCalls }
        function schedulePointRefresh() { ++pointRefreshCalls }
    }

    TableSessionUiController {
        id: controller
        tableRoot: fakeTable
        settingsPopup: fakeSettingsPopup
        resultPopup: fakeResultPopup
        chatInput: fakeChatInput
        counterLabelEditor: fakeCounterLabelEditor
        counterValueEditor: fakeCounterValueEditor
        libraryMoveCardsEditor: fakeLibraryMoveEditor
        gameLabel: "Game"
        gameDrawnLabel: "Game drawn"
        playerLabel: "Player"
        winsGameTemplate: "%1 wins Game %2"
        winsMatchTemplate: "%1 wins the match"
        drawDetailLabel: "The game ended in a draw."
        scoreLabel: "Score"
        leftMatchTemplate: "%1 left the match"
        concededTemplate: "%1 conceded"
        detailScoreTemplate: "%1 · Score %2"
    }

    function init() {
        controller.reset()
        fakeRoomSession.role = "player"
        fakeRoomSession.seatIndex = 0
        fakeRoomSession.matchMode = "bo3"
        fakeGameSession.sideboarding = false
        fakeGameSession.gameNumber = 1
        fakeGameSession.score = [1, 0]
        fakeGameSession.drawnGames = 0
        fakeGameSession.result = ({
            "winnerSeat": 0,
            "concededSeat": 1,
            "reason": "concede",
            "matchFinished": true
        })
        fakeWs.setCounterCountCalls = 0
        fakeWs.lastCounterCount = -1
        fakeTable.tableModalOpen = false
        fakeTable.gameFinished = false
        fakeTable.compactLayout = false
        fakeTable.compactChromeTouched = false
        fakeTable.showPlayerColumn = true
        fakeTable.showSharedColumn = true
        fakeTable.showInspectorColumn = true
        fakeTable.showGameLogRail = true
        fakeTable.ownSeatData = {"seat": 0, "counterCount": 2}
        fakeTable.winnerData = {"displayName": "Alice"}
        fakeTable.concededData = {"displayName": "Bob"}
        fakeTable.selectedCounterSeat = 0
        fakeTable.selectedCounterKey = "energy"
        fakeTable.libraryMoveDestination = ""
        fakeTable.visibleCounterCount = 2
        fakeTable.counterCountRequestGame = -1
        fakeTable.counterCountRequestValue = -1
        fakeTable.clearCounterCalls = 0
        fakeTable.resetCounterRequestCalls = 0
        fakeTable.pointRefreshCalls = 0
        fakeSettingsPopup.calls = 0
        fakeResultPopup.openCalls = 0
        fakeTournament.inTournament = false
        fakeTournament.lastRoomId = ""
        fakeTournament.lastSeats = []
        fakeTournament.lastDrawn = -1
        fakeCounterLabelEditor.calls = 0
        fakeCounterValueEditor.calls = 0
        fakeLibraryMoveEditor.calls = 0
        fakeChatInput.activeFocus = false
    }

    function test_opensCounterEditorsAndLibraryMoveEditor() {
        controller.openSelectedCounterLabelEditor()
        controller.openSelectedCounterValueEditor()
        controller.showLibraryMoveCardsEditor("exile")
        compare(fakeCounterLabelEditor.calls, 1)
        compare(fakeCounterLabelEditor.capturedArgs[2], "Energy")
        compare(fakeCounterValueEditor.value, 3)
        compare(fakeTable.libraryMoveDestination, "exile")
        compare(fakeLibraryMoveEditor.value, 1)
    }

    function test_appliesSettingsAndSynchronizesCounterCount() {
        controller.applyTableSettings(false, false, true, 4, false)
        verify(!fakeTable.showPlayerColumn)
        verify(!fakeTable.showSharedColumn)
        verify(fakeTable.showInspectorColumn)
        verify(!fakeTable.showGameLogRail)
        compare(fakeTable.visibleCounterCount, 4)
        compare(fakeWs.lastCounterCount, 4)
        compare(fakeTable.pointRefreshCalls, 1)
    }

    function test_compactChromeHidesRailsWithoutPersistingPreferences() {
        fakeTable.compactLayout = true
        fakePreferences.tableShowShared = true
        fakePreferences.tableShowGameLog = true
        controller.applyCompactChrome()
        verify(!fakeTable.showSharedColumn)
        verify(!fakeTable.showGameLogRail)
        verify(fakePreferences.tableShowShared)
        verify(fakePreferences.tableShowGameLog)
        controller.setGameLogRailVisible(true)
        verify(fakeTable.showGameLogRail)
        verify(fakeTable.compactChromeTouched)
        verify(fakePreferences.tableShowGameLog)
        controller.setSharedColumnVisible(true)
        verify(fakeTable.showSharedColumn)
        verify(fakePreferences.tableShowShared)
        fakeTable.compactLayout = false
        controller.applyCompactChrome()
        verify(fakeTable.showSharedColumn)
        verify(fakeTable.showGameLogRail)
        verify(!fakeTable.compactChromeTouched)
    }

    function test_resultPopupOnlyOpensOncePerResult() {
        fakeTable.gameFinished = true
        controller.maybeShowGameResult()
        controller.maybeShowGameResult()
        compare(fakeResultPopup.openCalls, 1)
        compare(controller.resultTitle(), "Alice wins the match")
        compare(controller.resultOutcome(), "win")
        compare(controller.resultDetail(), "Bob conceded · Score 1–0")
        compare(fakeTournament.lastRoomId, "")
    }

    function test_remembersTournamentTabletopScoreForOpenPairing() {
        fakeTable.gameFinished = true
        fakeTournament.inTournament = true
        fakeGameSession.score = [2, 1]
        controller.maybeShowGameResult()
        compare(fakeTournament.lastRoomId, "PAIR01")
        compare(fakeTournament.lastSeats.length, 2)
        compare(fakeTournament.lastSeats[0].displayName, "Alice")
        compare(fakeTournament.lastSeats[0].wins, 2)
        compare(fakeTournament.lastSeats[1].displayName, "Bob")
        compare(fakeTournament.lastSeats[1].wins, 1)
        compare(fakeTournament.lastDrawn, 0)
    }

    function test_prefillsBO3DrawnGamesFromMatchStatistic() {
        fakeTable.gameFinished = true
        fakeTournament.inTournament = true
        fakeGameSession.score = [2, 1]
        fakeGameSession.drawnGames = 1
        fakeGameSession.result = ({
            "winnerSeat": 0,
            "concededSeat": 1,
            "reason": "concede",
            "matchFinished": true
        })
        controller.maybeShowGameResult()
        compare(fakeTournament.lastSeats[0].wins, 2)
        compare(fakeTournament.lastSeats[1].wins, 1)
        compare(fakeTournament.lastDrawn, 1)
    }

    function test_shortcutBlockingAndScoreForSpectator() {
        verify(!controller.counterShortcutBlocked())
        fakeChatInput.activeFocus = true
        verify(controller.counterShortcutBlocked())
        fakeChatInput.activeFocus = false
        fakeRoomSession.role = "spectator"
        fakeGameSession.score = [2, 1]
        compare(controller.matchScoreSummary(), "2–1")
        compare(controller.resultOutcome(), "neutral")
    }
}
