// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    required property var tableController
    readonly property var gameSession: tableController.gameSession
    readonly property bool matchFinished: gameSession.result.matchFinished === true
                                         && !gameSession.sideboarding
    readonly property bool canReturn: tableController.roomConnected && matchFinished
    readonly property bool canRestart: tableController.roomConnected
                                      && tableController.roomSession.host
                                      && tableController.rulesSession.active
                                      && !tableController.rulesSession.gameOver
                                      && !matchFinished
                                      && !gameSession.sideboarding
    property string shownResultKey: ""
    readonly property bool modalOpen: restartConfirmation.opened || leaveConfirmation.opened
        || resultPopup.opened

    function playerName(seat) {
        // The invokable lookup itself does not establish a model dependency.
        void tableController.gameTableModel.seats
        const player = tableController.gameTableModel.seatData(seat)
        if (player && player.displayName)
            return player.displayName
        return qsTr("Seat %1").arg(Number(seat) + 1)
    }

    function scoreSummary() {
        const score = gameSession.score || []
        if (score.length !== 2)
            return ""
        const ownSeat = tableController.localSeat
        return ownSeat === 1 ? score[1] + "–" + score[0]
                             : score[0] + "–" + score[1]
    }

    function resultTitle() {
        const result = gameSession.result
        return result.winnerSeat === undefined || result.winnerSeat < 0
                ? qsTr("Match drawn")
                : qsTr("%1 wins the match").arg(playerName(result.winnerSeat))
    }

    function resultDetail() {
        const score = scoreSummary()
        return score.length > 0 ? qsTr("Final score · %1").arg(score)
                               : qsTr("The match is complete.")
    }

    function resultOutcome() {
        const winner = gameSession.result.winnerSeat
        if (tableController.localSeat < 0 || winner === undefined || winner < 0)
            return "neutral"
        return winner === tableController.localSeat ? "win" : "loss"
    }

    function synchronizeResult() {
        if (!matchFinished) {
            shownResultKey = ""
            resultPopup.close()
            return
        }
        if (!tableController.roomConnected)
            return
        const result = gameSession.result
        const key = tableController.roomSession.roomId + ":" + gameSession.gameNumber
                    + ":" + result.winnerSeat + ":" + result.reason
        if (key === shownResultKey)
            return
        shownResultKey = key
        resultPopup.open()
    }

    function returnToRoom() {
        if (canReturn)
            tableController.wsModel.returnToRoom()
    }

    function openRestartConfirmation() {
        if (!canRestart)
            return
        restartConfirmation.gameId = tableController.rulesSession.gameId
        if (restartConfirmation.validForCurrentGame())
            restartConfirmation.open()
    }

    function openLeaveConfirmation() {
        if (tableController.roomConnected)
            leaveConfirmation.open()
    }

    onMatchFinishedChanged: synchronizeResult()
    Component.onCompleted: Qt.callLater(synchronizeResult)

    Connections {
        target: root.tableController.wsModel
        function onInRoomChanged() {
            if (!root.tableController.roomConnected) {
                restartConfirmation.close()
                leaveConfirmation.close()
                resultPopup.close()
            }
            root.synchronizeResult()
        }
    }

    GameResultPopup {
        id: resultPopup
        objectName: "rulesGameResultPopup"
        titleText: root.resultTitle()
        detailText: root.resultDetail()
        outcome: root.resultOutcome()
        returnEnabled: root.canReturn
        onReturnRequested: root.returnToRoom()
    }

    ConfirmDialog {
        id: restartConfirmation
        property string gameId: ""
        readonly property string liveGameId: root.tableController.rulesSession.gameId
        readonly property bool canAct: root.canRestart

        function validForCurrentGame() {
            return canAct && gameId.length > 0 && gameId === liveGameId
        }
        function invalidate() { gameId = ""; close() }
        onLiveGameIdChanged: invalidate()
        onCanActChanged: { if (!canAct) invalidate() }
        onCancelled: gameId = ""
        objectName: "rulesRestartConfirmation"
        titleText: qsTranslate("TableDialogs", "Restart this game?")
        message: qsTranslate("TableDialogs", "The current table is replaced by newly shuffled decks and opening hands. The score and starting player stay unchanged.")
        confirmText: qsTranslate("TableDialogs", "Restart game")
        dangerous: true
        onConfirmed: {
            const canSend = validForCurrentGame()
            gameId = ""
            if (canSend)
                root.tableController.wsModel.restartGame()
        }
    }

    ConfirmDialog {
        id: leaveConfirmation
        objectName: "rulesLeaveConfirmation"
        titleText: qsTr("Leave this room?")
        message: root.tableController.roomSession.host
                 ? qsTr("Leaving as host disbands the room for everyone.")
                 : root.tableController.roomSession.role === "player" && !root.matchFinished
                   ? qsTr("Leaving ends the current rules game and returns the other players to the waiting room.")
                   : qsTr("You will leave this room.")
        confirmText: qsTr("Leave room")
        dangerous: true
        onConfirmed: {
            if (root.tableController.roomConnected)
                root.tableController.wsModel.leaveRoom()
        }
    }
}
