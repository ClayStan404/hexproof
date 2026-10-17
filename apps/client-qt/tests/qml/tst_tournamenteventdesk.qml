// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "TournamentEventDesk"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 640
        height: 720
        visible: true

        TournamentEventDesk {
            id: eventDesk
            width: 330
            height: parent.height
            lobbyController: mockLobby
            tournamentModel: mockTournament
            limitedModel: mockLimited
            wsModel: mockWs
            cancelDialogTarget: mockCancelDialog
        }
    }

    QtObject {
        id: mockLobby
        property bool isParticipant: false
        property bool selfCheckedIn: false
        property bool isOrganizer: true
        property var selfParticipant: null
    }

    QtObject {
        id: mockTournament
        property string coordinator: "swiss"
        property string organizerName: "Owner"
        property string status: "registration"
        property string stage: "registration"
        property string eventType: "cube_draft"
        property string roundStartedAt: ""
        property int roundMinutes: 50
        property int currentRound: 0
        property int plannedRounds: 3
        property int registered: 4
        property int checkedIn: 4
        property int minimumPlayers: 2
        property bool canRegister: false
        property bool roundComplete: false
        property var participants: []
        property var pairings: []
    }

    QtObject {
        id: mockLimited
        property bool allDecksSubmitted: false
        property var participants: []
    }

    QtObject {
        id: mockWs
        property int startCalls: 0
        property var chosenPlayers: []
        function registerTournament() { }
        function setTournamentCheckedIn() { }
        function unregisterTournament() { }
        function startTournament() { ++startCalls }
        function startNextTournamentRound() { }
        function dropTournament() { }
        function createLimitedCasualMatch(a, b) { chosenPlayers = [a, b] }
    }

    QtObject {
        id: mockCancelDialog
        function open() { }
    }

    function init() {
        mockTournament.coordinator = "swiss"
        mockTournament.status = "registration"
        mockTournament.stage = "registration"
        mockTournament.participants = []
        mockTournament.pairings = []
        mockLimited.allDecksSubmitted = false
        mockLimited.participants = []
        mockTournament.eventType = "cube_draft"
        mockTournament.registered = 4
        mockTournament.checkedIn = 4
        mockTournament.minimumPlayers = 2
        mockTournament.roundStartedAt = ""
        mockTournament.roundMinutes = 50
        mockWs.startCalls = 0
        mockWs.chosenPlayers = []
    }

    function test_cubeDraftStartsWithTwoCheckedInPlayers() {
        const startButton = findChild(eventDesk, "startTournamentButton")
        verify(startButton !== null)
        verify(startButton.visible)
        compare(eventDesk.minimumCheckedIn, 2)

        mockTournament.checkedIn = 1
        verify(!startButton.enabled)
        mockTournament.checkedIn = 2
        verify(startButton.enabled)
        startButton.clicked()
        compare(mockWs.startCalls, 1)
    }

    function test_casualCompetitionRequiresAllDecksAndExcludesReservedPlayers() {
        mockTournament.coordinator = "casual"
        mockTournament.status = "running"
        mockTournament.stage = "deck_building"
        const open = findChild(eventDesk, "openLimitedCompetitionButton")
        verify(!open.visible)
        mockLimited.allDecksSubmitted = true
        verify(open.visible)
        open.clicked()
        compare(mockWs.startCalls, 1)

        mockTournament.stage = "competition"
        mockTournament.participants = [1, 2, 3, 4].map(n => ({
            participantId: "p" + n, displayName: "Player " + n,
            online: n !== 4, competing: true, dropped: false
        }))
        mockLimited.participants = [1, 2, 3, 4].map(n => ({
            participantId: "p" + n, deckSubmitted: true
        }))
        compare(eventDesk.casualReadyPlayers.length, 3)
        const create = findChild(eventDesk, "createCasualTableButton")
        tryVerify(() => create.enabled)
        create.clicked()
        compare(mockWs.chosenPlayers, ["p1", "p2"])
        mockTournament.pairings = [{playerAId: "p1", playerBId: "p2", roomId: ""}]
        compare(eventDesk.casualReadyPlayers.length, 1)
        compare(eventDesk.casualReadyPlayers[0].participantId, "p3")
        tryVerify(() => !create.enabled)
        mockTournament.pairings = []
        compare(eventDesk.casualReadyPlayers.length, 3)
        tryVerify(() => create.enabled)
    }

    function test_setDraftStartsWithTwoCheckedInPlayers() {
        const startButton = findChild(eventDesk, "startTournamentButton")
        verify(startButton !== null)
        mockTournament.eventType = "set_draft"
        mockTournament.registered = 2
        mockTournament.checkedIn = 1
        compare(eventDesk.minimumCheckedIn, 2)
        verify(!startButton.enabled)

        mockTournament.checkedIn = 2
        verify(startButton.enabled)
    }

    function test_setSealedStartsWithTwoCheckedInPlayers() {
        const startButton = findChild(eventDesk, "startTournamentButton")
        verify(startButton !== null)
        mockTournament.eventType = "set_sealed"
        mockTournament.registered = 2
        mockTournament.checkedIn = 1
        compare(eventDesk.minimumCheckedIn, 2)
        verify(!startButton.enabled)

        mockTournament.checkedIn = 2
        verify(startButton.enabled)
    }

    function test_oldServerSnapshotFallsBackToConstructedMinimum() {
        mockTournament.eventType = "constructed"
        mockTournament.minimumPlayers = 0
        compare(eventDesk.minimumCheckedIn, 4)
    }

    function test_roundClockUsesTournamentSnapshot() {
        mockTournament.roundStartedAt = "2026-09-02T12:00:00Z"
        eventDesk.clockNow = Date.parse("2026-09-02T12:00:00Z")
        compare(eventDesk.roundSecondsRemaining, 3000)
        compare(eventDesk.roundClock, "50:00")

        eventDesk.clockNow = Date.parse("2026-09-02T12:50:01Z")
        compare(eventDesk.roundSecondsRemaining, 0)
    }
}
