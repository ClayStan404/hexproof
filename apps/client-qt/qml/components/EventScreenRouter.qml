// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

QtObject {
    id: root
    required property var wsModel
    required property var tournamentModel
    property string displayedEventId: ""
    property bool displayedCubeRoom: false
    signal screenRequested(string screen)

    function reset() {
        displayedEventId = ""
        displayedCubeRoom = false
    }

    function showEventOrMenu() {
        // Entry acknowledgements arrive before the authoritative kind/stage.
        if (tournamentModel.inTournament && tournamentModel.stage.length === 0) return
        displayedEventId = tournamentModel.tournamentId
        displayedCubeRoom = tournamentModel.cubeRoom
        screenRequested(tournamentModel.inTournament
            ? (tournamentModel.cubeRoom ? "screens/CubeRoom.qml" : "screens/TournamentLobby.qml")
            : "screens/MainMenu.qml")
    }

    readonly property Connections sessionConnections: Connections {
        target: root.tournamentModel
        function onInTournamentChanged() {
            // Clearing membership while offline must invalidate the old route
            // too, or joining that same room after reconnect will be ignored.
            if (!root.tournamentModel.inTournament) root.reset()
            if (root.wsModel.connected && !root.wsModel.inRoom) root.showEventOrMenu()
        }
        function onSnapshotChanged() {
            if (root.tournamentModel.inTournament && root.tournamentModel.stage.length > 0
                    && root.wsModel.connected && !root.wsModel.inRoom
                    && (root.displayedEventId !== root.tournamentModel.tournamentId
                        || root.displayedCubeRoom !== root.tournamentModel.cubeRoom))
                root.showEventOrMenu()
        }
    }
    readonly property Connections connectionConnections: Connections {
        target: root.wsModel
        function onWelcomeReceived() {
            // Main returns to its home screen on a fresh welcome. A following
            // entry/snapshot must restore even the same previously viewed pod.
            root.reset()
        }
    }
}
