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
    }

    QtObject {
        id: mockLimited
        property bool allDecksSubmitted: false
        property var participants: []
    }

    QtObject {
        id: mockWs
        property int startCalls: 0
        function registerTournament() { }
        function setTournamentCheckedIn() { }
        function unregisterTournament() { }
        function startTournament() { ++startCalls }
        function startNextTournamentRound() { }
        function dropTournament() { }
        function createLimitedCasualMatch() { }
    }

    QtObject {
        id: mockCancelDialog
        function open() { }
    }

    function init() {
        mockTournament.coordinator = "swiss"
        mockTournament.status = "registration"
        mockTournament.eventType = "cube_draft"
        mockTournament.registered = 4
        mockTournament.checkedIn = 4
        mockTournament.minimumPlayers = 2
        mockTournament.roundStartedAt = ""
        mockTournament.roundMinutes = 50
        mockWs.startCalls = 0
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
