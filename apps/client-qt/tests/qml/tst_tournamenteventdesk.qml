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
        function roundClock() { return "50:00" }
        function roundSecondsRemaining() { return 3000 }
    }

    QtObject {
        id: mockTournament
        property string coordinator: "swiss"
        property string organizerName: "Owner"
        property string status: "registration"
        property string stage: "registration"
        property string eventType: "cube_draft"
        property int currentRound: 0
        property int plannedRounds: 3
        property int registered: 4
        property int checkedIn: 4
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
        mockWs.startCalls = 0
    }

    function test_cubeDraftStartsWithFourCheckedInPlayers() {
        const startButton = findChild(eventDesk, "startTournamentButton")
        verify(startButton !== null)
        verify(startButton.visible)
        compare(eventDesk.minimumCheckedIn, 4)

        mockTournament.checkedIn = 3
        verify(!startButton.enabled)
        mockTournament.checkedIn = 4
        verify(startButton.enabled)
        startButton.clicked()
        compare(mockWs.startCalls, 1)
    }

    function test_setDraftStillRequiresEightCheckedInPlayers() {
        const startButton = findChild(eventDesk, "startTournamentButton")
        verify(startButton !== null)
        mockTournament.eventType = "set_draft"
        mockTournament.registered = 8
        mockTournament.checkedIn = 7
        compare(eventDesk.minimumCheckedIn, 8)
        verify(!startButton.enabled)

        mockTournament.checkedIn = 8
        verify(startButton.enabled)
    }
}
