// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "RulesMatchControls"
    when: windowShown
    property var controls: null

    ApplicationWindow {
        id: testWindow
        width: 1280
        height: 800
        visible: true

        TournamentScoreEditor {
            id: scoreEditor
            wsModel: fakeWs
        }
    }

    QtObject {
        id: room
        property string roomId: "FORGE1"
        property string role: "player"
        property int seatIndex: 0
        property bool host: true
        property var seats: []
        property var players: ["Replay Alice", "Replay Bob"]
    }

    QtObject {
        id: game
        property int gameNumber: 1
        property var score: [0, 0]
        property int drawnGames: 0
        property var result: ({})
        property bool sideboarding: false
    }

    QtObject {
        id: rules
        property bool active: true
        property bool gameOver: false
        property string gameId: "FORGE1-1"
    }

    QtObject {
        id: fakeWs
        property bool inRoom: true
        property int reports: 0
        function reportTournamentResult(pairing, a, b, drawn) { ++reports }
        function correctTournamentResult(pairing, a, b, drawn) { ++reports }
        function returnToRoom() {}
        function restartGame() {}
        function leaveRoom() {}
    }

    QtObject {
        id: tournament
        property bool inTournament: true
        property int calls: 0
        property string rememberedRoom: ""
        property var rememberedScore: ({})
        function rememberTabletopScore(roomId, seats, drawnGames) {
            ++calls
            rememberedRoom = roomId
            rememberedScore = JSON.parse(JSON.stringify({seats: seats, drawnGames: drawnGames}))
        }
    }

    QtObject {
        id: tableModel
        property var seats: []
        function seatData(seat) { return seats[seat] || ({}) }
    }

    QtObject {
        id: table
        property var wsModel: fakeWs
        property var roomSession: room
        property var gameSession: game
        property var rulesSession: rules
        property var gameTableModel: tableModel
        property var tournamentModel: tournament
        property bool replayMode: false
        readonly property bool roomConnected: fakeWs.inRoom
        readonly property int localSeat: room.role === "player" ? room.seatIndex : -1
    }

    Component {
        id: controlsComponent
        RulesMatchControls { tableController: table }
    }

    function init() {
        scoreEditor.close()
        room.role = "player"
        room.seatIndex = 0
        room.seats = [{displayName: "Bob"}, {displayName: "Alice"}]
        tableModel.seats = room.seats
        game.score = [0, 0]
        game.drawnGames = 0
        game.result = ({})
        game.gameNumber = 1
        game.sideboarding = false
        rules.gameOver = false
        fakeWs.inRoom = true
        fakeWs.reports = 0
        tournament.calls = 0
        tournament.rememberedRoom = ""
        tournament.rememberedScore = ({})
        tournament.inTournament = true
        table.tournamentModel = tournament
        table.replayMode = false
        controls = createTemporaryObject(controlsComponent, testWindow.contentItem)
        verify(controls !== null)
        wait(0)
    }

    function completeMatch(score, drawn) {
        game.score = score
        game.drawnGames = drawn
        rules.gameOver = true
        game.result = {winnerSeat: score[0] === score[1] ? -1 : score[0] > score[1] ? 0 : 1,
                       matchFinished: true, reason: "rules"}
    }

    function test_completedMatchPrefillsPairingOrder_data() {
        return [
            {tag: "bo1-seat-zero", score: [0, 1], drawn: 0, localSeat: 0,
             names: ["Bob", "Alice"], a: 1, b: 0},
            {tag: "bo1-seat-one", score: [0, 1], drawn: 0, localSeat: 1,
             names: ["Alice", "Bob"], a: 0, b: 1},
            {tag: "bo1-drawn", score: [0, 0], drawn: 1, localSeat: 0,
             names: ["Alice", "Bob"], a: 0, b: 0},
            {tag: "bo3-with-draw", score: [2, 1], drawn: 1, localSeat: 1,
             names: ["Bob", "Alice"], a: 1, b: 2}
        ]
    }

    function test_completedMatchPrefillsPairingOrder(data) {
        room.seatIndex = data.localSeat
        room.seats = [{displayName: data.names[0]}, {displayName: data.names[1]}]
        game.gameNumber = data.score[0] + data.score[1] + data.drawn
        completeMatch(data.score, data.drawn)
        tryCompare(tournament, "calls", 1)
        compare(tournament.rememberedRoom, "FORGE1")
        compare(tournament.rememberedScore.seats[0].displayName, data.names[0])
        compare(tournament.rememberedScore.seats[0].wins, data.score[0])
        compare(tournament.rememberedScore.seats[1].wins, data.score[1])
        compare(tournament.rememberedScore.drawnGames, data.drawn)
        findChild(controls, "rulesGameResultPopup").close()
        scoreEditor.openFor({pairingId: "r1-m1", playerAName: "Alice", playerBName: "Bob",
                             status: "open"}, false, tournament.rememberedScore)
        tryCompare(scoreEditor, "opened", true)
        verify(scoreEditor.prefilledFromTable)
        compare(findChild(scoreEditor, "playerAWinsField").text, String(data.a))
        compare(findChild(scoreEditor, "playerBWinsField").text, String(data.b))
        compare(findChild(scoreEditor, "drawnGamesField").text, String(data.drawn))
        compare(fakeWs.reports, 0)
        controls.synchronizeResult()
        compare(tournament.calls, 1)
    }

    function test_intermediateBO3GameAndSideboardDoNotCapture() {
        game.score = [1, 0]
        game.result = {winnerSeat: 0, matchFinished: false, reason: "rules"}
        rules.gameOver = true
        game.sideboarding = true
        controls.synchronizeResult()
        compare(tournament.calls, 0)
        game.gameNumber = 2
        game.sideboarding = false
        controls.synchronizeResult()
        compare(tournament.calls, 0)
        game.sideboarding = true
        completeMatch([2, 0], 0)
        compare(tournament.calls, 0)
        game.sideboarding = false
        tryCompare(tournament, "calls", 1)
        compare(tournament.rememberedScore.seats[0].wins, 2)
    }

    function test_nonParticipantViewsDoNotCapture_data() {
        return [{tag: "spectator"}, {tag: "replay"}, {tag: "no-event"},
                {tag: "no-model"}, {tag: "invalid-seat"}]
    }

    function test_nonParticipantViewsDoNotCapture(data) {
        if (data.tag === "spectator") room.role = "spectator"
        if (data.tag === "replay") table.replayMode = true
        if (data.tag === "no-event") tournament.inTournament = false
        if (data.tag === "no-model") table.tournamentModel = null
        if (data.tag === "invalid-seat") room.seatIndex = -1
        completeMatch([0, 1], 0)
        controls.synchronizeResult()
        compare(tournament.calls, 0)
    }

    function test_terminalReconnectCapturesAfterRoomRestored() {
        fakeWs.inRoom = false
        completeMatch([0, 1], 0)
        compare(tournament.calls, 0)
        fakeWs.inRoom = true
        tryCompare(tournament, "calls", 1)
        compare(tournament.rememberedScore.seats[1].wins, 1)
    }
}
