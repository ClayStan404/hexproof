// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root

    required property var tableRoot
    required property var settingsPopup
    required property var resultPopup
    required property var chatInput
    required property var counterLabelEditor
    required property var counterValueEditor
    required property var libraryMoveCardsEditor

    required property string gameLabel
    required property string gameDrawnLabel
    required property string playerLabel
    required property string winsGameTemplate
    required property string winsMatchTemplate
    required property string drawDetailLabel
    required property string scoreLabel
    required property string leftMatchTemplate
    required property string concededTemplate
    required property string detailScoreTemplate

    property string shownResultKey: ""

    function selectedCounter() {
        const player = tableRoot.seatState.seatData(tableRoot.selectedCounterSeat)
        const counters = player.counters ? player.counters : []
        for (let index = 0; index < counters.length; ++index) {
            if (counters[index].key === tableRoot.selectedCounterKey)
                return {"player": player, "counter": counters[index]}
        }
        return ({})
    }

    function openSelectedCounterLabelEditor() {
        const selection = selectedCounter()
        if (!selection.counter)
            return
        counterLabelEditor.showFor(
                    selection.player.displayName,
                    selection.counter.key,
                    selection.counter.label)
    }

    function openSelectedCounterValueEditor() {
        const selection = selectedCounter()
        if (selection.counter)
            counterValueEditor.showFor(selection.counter.value)
    }

    function counterShortcutBlocked() {
        return chatInput.activeFocus
                || tableRoot.tableModalOpen
                || tableRoot.gameSession.sideboarding
    }

    function showLibraryMoveCardsEditor(destination) {
        tableRoot.libraryMoveDestination = destination
        libraryMoveCardsEditor.showFor(1)
    }

    function openTableSettings() {
        settingsPopup.showFor(
                    tableRoot.showPlayerColumn,
                    tableRoot.showSharedColumn,
                    tableRoot.showInspectorColumn,
                    tableRoot.visibleCounterCount,
                    tableRoot.roomSession.role === "player",
                    tableRoot.showGameLogRail)
    }

    function applyCompactChrome() {
        if (!tableRoot.compactLayout) {
            tableRoot.compactChromeTouched = false
            tableRoot.showSharedColumn = tableRoot.preferencesModel
                    ? tableRoot.preferencesModel.tableShowShared : true
            tableRoot.showGameLogRail = tableRoot.preferencesModel
                    ? tableRoot.preferencesModel.tableShowGameLog : true
            return
        }
        if (tableRoot.compactChromeTouched)
            return
        tableRoot.showSharedColumn = false
        tableRoot.showGameLogRail = false
    }

    function rememberCompactChromeOverride() {
        if (tableRoot.compactLayout)
            tableRoot.compactChromeTouched = true
    }

    function setGameLogRailVisible(show) {
        tableRoot.showGameLogRail = show
        rememberCompactChromeOverride()
        if (tableRoot.preferencesModel && !tableRoot.compactLayout)
            tableRoot.preferencesModel.tableShowGameLog = show
    }

    function setSharedColumnVisible(show, scheduleRefresh) {
        tableRoot.showSharedColumn = show
        rememberCompactChromeOverride()
        if (tableRoot.preferencesModel && !tableRoot.compactLayout)
            tableRoot.preferencesModel.tableShowShared = show
        if (scheduleRefresh !== false)
            tableRoot.battlefieldScene.schedulePointRefresh()
    }

    function applyTableSettings(showPlayers, showShared,
                                showInspector, counterCount,
                                showGameLog) {
        tableRoot.showPlayerColumn = showPlayers
        setSharedColumnVisible(showShared, false)
        tableRoot.showInspectorColumn = showInspector
        rememberCompactChromeOverride()
        if (showGameLog !== undefined)
            setGameLogRailVisible(showGameLog)
        tableRoot.visibleCounterCount = Math.max(
                    0, Math.min(7, counterCount))
        if (tableRoot.preferencesModel) {
            tableRoot.preferencesModel.tableShowPlayers = showPlayers
            tableRoot.preferencesModel.tableShowInspector = showInspector
            tableRoot.preferencesModel.tableCounterCount =
                tableRoot.visibleCounterCount
        }
        if (tableRoot.visibleCounterCount === 0)
            tableRoot.transientState.clearCounterSelection()
        tableRoot.optimisticCommands.resetCounterCountRequest()
        syncOwnCounterCount()
        tableRoot.battlefieldScene.schedulePointRefresh()
    }

    function syncOwnCounterCount() {
        const ws = tableRoot.wsModel
        const room = tableRoot.roomSession
        const game = tableRoot.gameSession
        if (room.role !== "player" || tableRoot.gameFinished
                || game.sideboarding || game.gameNumber <= 0
                || tableRoot.ownSeatData.seat === undefined) {
            return
        }
        const authoritative = tableRoot.ownSeatData.counterCount !== undefined
                              ? tableRoot.ownSeatData.counterCount : 0
        if (authoritative === tableRoot.visibleCounterCount) {
            tableRoot.optimisticCommands.resetCounterCountRequest()
            return
        }
        if (tableRoot.counterCountRequestGame === game.gameNumber
                && tableRoot.counterCountRequestValue
                   === tableRoot.visibleCounterCount) {
            return
        }
        tableRoot.counterCountRequestGame = game.gameNumber
        tableRoot.counterCountRequestValue = tableRoot.visibleCounterCount
        ws.setCounterCount(tableRoot.visibleCounterCount)
    }

    function maybeShowGameResult() {
        const game = tableRoot.gameSession
        const result = game.result ? game.result : ({})
        if (!tableRoot.gameFinished || game.sideboarding
                || result.matchFinished !== true) {
            return
        }
        const key = String(game.gameNumber) + ":"
                    + String(result.winnerSeat) + ":"
                    + String(result.concededSeat)
        if (shownResultKey === key)
            return
        shownResultKey = key
        rememberTournamentTabletopScore()
        resultPopup.open()
    }

    function rememberTournamentTabletopScore() {
        const tournament = tableRoot.tournamentModel
        if (!tournament || !tournament.inTournament
                || typeof tournament.rememberTabletopScore !== "function") {
            return
        }
        const room = tableRoot.roomSession
        const game = tableRoot.gameSession
        const seats = tableRoot.authoritativeSeats
                      ? tableRoot.authoritativeSeats : []
        const score = game.score ? game.score : []
        const seatScores = []
        for (let index = 0; index < seats.length; ++index) {
            seatScores.push({
                "displayName": seats[index].displayName
                               ? seats[index].displayName : "",
                "wins": Number(score[index] || 0)
            })
        }
        const drawn = Number(game.drawnGames || 0)
        tournament.rememberTabletopScore(room.roomId, seatScores, drawn)
    }

    function gameSummary() {
        return gameLabel + " " + Math.max(1, tableRoot.gameSession.gameNumber)
    }

    function matchScoreSummary() {
        const room = tableRoot.roomSession
        const score = tableRoot.gameSession.score
        if (!score || score.length < 2)
            return ""
        if (room.role === "player"
                && room.seatIndex >= 0
                && room.seatIndex < score.length) {
            const otherSeat = room.seatIndex === 0 ? 1 : 0
            return score[room.seatIndex] + "–"
                    + score[otherSeat]
        }
        return score[0] + "–" + score[1]
    }

    function resultTitle() {
        const room = tableRoot.roomSession
        const game = tableRoot.gameSession
        const result = game.result ? game.result : ({})
        if (result.reason === "draw")
            return gameDrawnLabel
        const winner = tableRoot.winnerData.displayName
                       ? tableRoot.winnerData.displayName : playerLabel
        if (room.matchMode === "bo3"
                && result.matchFinished !== true) {
            return winsGameTemplate.arg(winner).arg(game.gameNumber)
        }
        return winsMatchTemplate.arg(winner)
    }

    function resultOutcome() {
        const room = tableRoot.roomSession
        const result = tableRoot.gameSession.result
                       ? tableRoot.gameSession.result : ({})
        if (room.role !== "player"
                || result.winnerSeat === undefined
                || result.winnerSeat < 0) {
            return "neutral"
        }
        return result.winnerSeat === room.seatIndex ? "win" : "loss"
    }

    function resultDetail() {
        const game = tableRoot.gameSession
        const result = game.result ? game.result : ({})
        const score = game.score ? game.score : []
        if (result.reason === "draw") {
            let detail = drawDetailLabel
            if (score.length === 2)
                detail += " · " + scoreLabel + " " + matchScoreSummary()
            return detail
        }
        const conceded = tableRoot.concededData.displayName
                          ? tableRoot.concededData.displayName : playerLabel
        let detail = result.reason === "departure"
                     ? leftMatchTemplate.arg(conceded)
                     : concededTemplate.arg(conceded)
        if (score.length === 2)
            detail = detailScoreTemplate.arg(detail).arg(matchScoreSummary())
        return detail
    }

    function reset() {
        shownResultKey = ""
    }
}
