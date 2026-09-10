// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    visible: false
    width: 0
    height: 0

    required property var tableRoot
    required property var librarySearchPopup
    required property var libraryAccessConfirmation
    required property var publicZoneMoveConfirmation
    required property var optimisticController
    required property var cardMoveController
    required property var projectionController
    required property var zoneController
    required property var gameValueController
    required property var battlefieldSceneController
    required property var sessionController
    required property var sharedController
    required property var transientController
    required property var presentationController

    property bool autoInitialize: false
    property bool deferInitialReconcile: true
    property int initializationGeneration: 0
    property int observedGameNumber: -1
    property bool restartProjectionPending: false

    function invalidateConsent() {
        transientController.clearPendingLibraryApproval()
        transientController.clearPendingPublicZoneMoveApproval()
        transientController.clearLibraryMoveDestination()
        libraryAccessConfirmation.close()
        publicZoneMoveConfirmation.close()
        librarySearchPopup.invalidate()
    }

    function reconcileConsent() {
        const game = tableRoot.gameSession
        const number = game.gameNumber
        if ((observedGameNumber >= 0 && number !== observedGameNumber)
                || tableRoot.wsModel.inRoom === false
                || tableRoot.roomSession.phase !== "started"
                || game.finished || game.sideboarding || tableRoot.ownEliminated) {
            invalidateConsent()
        }
        observedGameNumber = number
    }

    function initialize() {
        const table = tableRoot
        if (!table || !table.optimisticCommandModel)
            return
        observedGameNumber = table.gameSession.gameNumber
        table.optimisticCommandModel.clear()
        table.optimisticCommandModel.timeoutMs = table.optimisticValueTimeoutMs
        const generation = ++initializationGeneration
        if (!table.gameTableModel || !table.gameTableModel.hasSnapshot)
            return
        projectionController.syncBattlefieldSeats()
        projectionController.syncDisplayedOwnHand()

        if (!deferInitialReconcile)
            return
        Qt.callLater(function() {
            if (generation !== initializationGeneration)
                return
            sessionController.maybeShowGameResult()
            sessionController.syncOwnCounterCount()
            sharedController.reconcileSelection()
            transientController.reconcile()
            presentationController.prioritizeVisibleCards()
        })
    }

    function reconcileSnapshot() {
        ++initializationGeneration
        projectionController.syncBattlefieldSeats()
        if (cardMoveController.pendingBattlefieldMoveCommitted())
            cardMoveController.clearPendingBattlefieldMove()
        zoneController.reconcilePendingCardMoves()
        tableRoot.selection.reconcileBattlefieldSelection()
        projectionController.syncDisplayedOwnHand()
        gameValueController.reconcile()
        optimisticController.reconcileLandPlayCount(
                    tableRoot.gameTableModel.landPlaysThisTurn)
        battlefieldSceneController.schedulePointRefresh()
        sessionController.maybeShowGameResult()
        sessionController.syncOwnCounterCount()
        sharedController.reconcileSelection()
        transientController.reconcile()
        presentationController.prioritizeVisibleCards()
    }

    function reconcileSessionSnapshot() {
        // WsClient owns scalar match state that is intentionally not copied
        // into GameTableModel: phase, score, result, sideboarding, and room
        // lifecycle. Its notification follows snapshotDataChanged, so use it
        // as the final synchronization point without rebuilding typed zones.
        if (observedGameNumber > 0 && tableRoot.gameSession.gameNumber > 0
                && observedGameNumber !== tableRoot.gameSession.gameNumber) {
            tableRoot.resetGameInteractions()
            restartProjectionPending = true
        }
        reconcileConsent()
        if (restartProjectionPending) {
            restartProjectionPending = false
            // Identical typed zones may not emit snapshotDataChanged after
            // restart, but their delegates still need to be recreated.
            projectionController.syncBattlefieldSeats()
        }
        projectionController.syncDisplayedOwnHand()
        gameValueController.reconcile()
        sessionController.maybeShowGameResult()
        sessionController.syncOwnCounterCount()
        transientController.reconcile()
    }

    function handleLibraryDumped(cards, sourceSeat, approvalId, topCount) {
        librarySearchPopup.showCards(
                    cards, sourceSeat, approvalId,
                    tableRoot.roomSession.seatIndex,
                    sharedController.displayNameForSeat(
                        tableRoot.roomSession.seatIndex),
                    sharedController.displayNameForSeat(sourceSeat),
                    topCount)
    }

    function handleLibraryAccessRequested(approvalId, requesterName,
                                          topCount) {
        transientController.setLibraryApproval(
                    approvalId, requesterName, topCount)
        libraryAccessConfirmation.open()
    }

    function handlePublicZoneMoveRequested(approvalId, requesterName,
                                           sourceZone, cardCount, toZone) {
        transientController.setPublicZoneMoveApproval(
                    approvalId, requesterName, sourceZone, cardCount, toZone)
        publicZoneMoveConfirmation.open()
    }

    function handleCommandQueued(requestId, commandType, payload) {
        optimisticController.trackQueuedCommand(
                    requestId, commandType, payload)
    }

    function handleCommandFailed(requestId, commandType, payload, error) {
        optimisticController.rollbackFailedCommand(
                    requestId, commandType, payload)
        gameValueController.reconcileUntapBatchFailure(
                    commandType, payload)
        if (tableRoot.appWindow
                && typeof tableRoot.appWindow.showBanner === "function"
                && error && String(error).length > 0) {
            tableRoot.appWindow.showBanner(I18n.status(String(error)))
        }
    }

    function handleCardMovesChanged() {
        projectionController.syncDisplayedOwnHand()
        tableRoot.selection.reconcileBattlefieldSelection()
        sharedController.reconcileSelection()
        transientController.reconcile()
        presentationController.prioritizeVisibleCards()
    }

    function handleLanguageChanged() {
        presentationController.invalidatePriorities()
        presentationController.prioritizeVisibleCards()
    }

    function updateOptimisticTimeout() {
        if (tableRoot.optimisticCommandModel) {
            tableRoot.optimisticCommandModel.timeoutMs =
                tableRoot.optimisticValueTimeoutMs
        }
    }

    function handleOptimisticValuesExpired(count) {
        if (!tableRoot.appWindow
                || typeof tableRoot.appWindow.showBanner !== "function")
            return
        const message = count === 1
                      ? qsTr("A change could not be synchronized and was restored.")
                      : qsTr("%1 changes could not be synchronized and were restored.")
                        .arg(count)
        tableRoot.appWindow.showBanner(message)
    }

    Connections {
        target: root.tableRoot ? root.tableRoot.wsModel : null

        function onLibraryDumped(cards, sourceSeat, approvalId, topCount) {
            root.handleLibraryDumped(
                        cards, sourceSeat, approvalId, topCount)
        }

        function onLibraryAccessRequested(approvalId, requesterName,
                                          requesterSeat, topCount) {
            root.handleLibraryAccessRequested(
                        approvalId, requesterName, topCount)
        }

        function onPublicZoneMoveRequested(approvalId, requesterName,
                                           requesterSeat, sourceZone,
                                           cardCount, toZone) {
            root.handlePublicZoneMoveRequested(
                        approvalId, requesterName, sourceZone,
                        cardCount, toZone)
        }

        function onGameSnapshotChanged() {
            root.reconcileSessionSnapshot()
        }

        function onGameRestarted() {
            root.invalidateConsent()
            root.restartProjectionPending = true
            root.tableRoot.resetGameInteractions()
        }

        function onCommandQueued(requestId, commandType, payload) {
            root.handleCommandQueued(requestId, commandType, payload)
        }

        function onCommandFailed(requestId, commandType, payload, error) {
            root.handleCommandFailed(
                        requestId, commandType, payload, error)
        }
    }

    Connections {
        target: root.tableRoot ? root.tableRoot.gameTableModel : null

        function onSnapshotChanged() {
            root.reconcileSnapshot()
        }
    }

    Connections {
        target: root.tableRoot
                ? root.tableRoot.optimisticCommandModel : null

        function onCardMovesChanged() {
            root.handleCardMovesChanged()
        }

        function onValuesExpired(count) {
            root.handleOptimisticValuesExpired(count)
        }
    }

    Connections {
        target: root.tableRoot ? root.tableRoot.cardCatalogModel : null
        ignoreUnknownSignals: true

        function onLanguageChanged() {
            root.handleLanguageChanged()
        }
        // Do not re-prioritize on imageRevisionChanged: prioritizeCards cache
        // hits emit that signal synchronously and would recurse until the
        // JS stack overflows. Table Image.source bindings already read
        // imageRevision.
    }

    Connections {
        target: root.tableRoot

        function onOptimisticValueTimeoutMsChanged() {
            root.updateOptimisticTimeout()
        }
    }

    Component.onCompleted: {
        if (autoInitialize)
            initialize()
    }
    Component.onDestruction: ++initializationGeneration
}
