// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "EventScreenRouter"
    QtObject {
        id: connection
        signal welcomeReceived()
        property bool connected: true
        property bool inRoom: false
    }
    QtObject {
        id: session
        signal snapshotChanged()
        property bool inTournament: false
        property string tournamentId: ""
        property bool cubeRoom: false
        property string stage: ""
    }
    EventScreenRouter { id: router; wsModel: connection; tournamentModel: session }
    SignalSpy { id: requests; target: router; signalName: "screenRequested" }

    function init() {
        connection.connected = false
        connection.inRoom = false
        session.inTournament = false
        session.tournamentId = ""
        session.cubeRoom = false
        session.stage = ""
        router.reset()
        connection.connected = true
        requests.clear()
    }
    function enterAcknowledged(id) {
        session.stage = ""
        session.cubeRoom = false
        session.tournamentId = id
        session.inTournament = true
        session.snapshotChanged()
    }
    function snapshot(cube = true, stage = "registration") {
        session.cubeRoom = cube
        session.stage = stage
        session.snapshotChanged()
    }
    function requested(screen) {
        compare(requests.signalArguments[requests.count - 1][0], screen)
    }

    function test_entryWaitsForAuthoritativeKind() {
        enterAcknowledged("CUBE01")
        compare(requests.count, 0)
        snapshot()
        compare(requests.count, 1)
        requested("screens/CubeRoom.qml")
    }
    function test_sameSessionSnapshotsPreserveActiveEditorAndNavigation() {
        enterAcknowledged("CUBE01")
        snapshot()
        snapshot(true, "draft")
        snapshot(true, "deck_building")
        snapshot(true, "competition")
        compare(requests.count, 1, "Routine updates cannot replace the current workspace or its edits")
    }
    function test_switchingEventsWaitsForNewKind() {
        enterAcknowledged("CUBE01")
        snapshot()
        enterAcknowledged("SWISS1")
        compare(requests.count, 1)
        snapshot(false)
        compare(requests.count, 2)
        requested("screens/TournamentLobby.qml")
    }
    function test_offlineClearAllowsRejoiningSameCubeRoom() {
        enterAcknowledged("CUBE01")
        snapshot()
        connection.connected = false
        session.inTournament = false
        session.stage = ""
        session.tournamentId = ""
        session.snapshotChanged()
        compare(requests.count, 1, "Offline clearing does not navigate through unavailable session state")
        compare(router.displayedEventId, "")
        connection.connected = true
        enterAcknowledged("CUBE01")
        compare(requests.count, 1)
        snapshot()
        compare(requests.count, 2)
        requested("screens/CubeRoom.qml")
    }
    function test_freshWelcomeInvalidatesOldHomeScreenRoute() {
        enterAcknowledged("CUBE01")
        snapshot()
        connection.welcomeReceived()
        compare(router.displayedEventId, "")
        // Re-entry into the same still-known session may retain its metadata.
        session.snapshotChanged()
        compare(requests.count, 2)
        requested("screens/CubeRoom.qml")
    }
    function test_leavingOnlineReturnsHomeAndClearsIdentity() {
        enterAcknowledged("CUBE01")
        snapshot()
        session.tournamentId = ""
        session.cubeRoom = false
        session.stage = ""
        session.inTournament = false
        compare(requests.count, 2)
        requested("screens/MainMenu.qml")
        compare(router.displayedEventId, "")
    }
    function test_tableSnapshotsDoNotReplaceGameAndReturnRestoresPod() {
        enterAcknowledged("CUBE01")
        snapshot(true, "competition")
        connection.inRoom = true
        snapshot(true, "competition")
        compare(requests.count, 1)
        connection.inRoom = false
        router.showEventOrMenu()
        compare(requests.count, 2)
        requested("screens/CubeRoom.qml")
    }
}
