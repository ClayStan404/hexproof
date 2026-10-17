// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "TableRuntimeSyncController"

    QtObject {
        id: fakeWs
        property int seatIndex: 1
        signal libraryDumped(var cards, int sourceSeat,
                             string approvalId, int topCount)
        signal libraryAccessRequested(string approvalId,
                                      string requesterName,
                                      int requesterSeat, int topCount)
        signal publicZoneMoveRequested(string approvalId,
                                       string requesterName,
                                       int requesterSeat,
                                       string sourceZone, int cardCount,
                                       string toZone)
        signal gameSnapshotChanged()
        signal gameRestarted()
        signal commandQueued(string requestId, string commandType,
                             var payload)
        signal commandFailed(string requestId, string commandType,
                             var payload, string error)
    }

    QtObject {
        id: fakeRoomSession
        property int seatIndex: fakeWs.seatIndex
        property string phase: "started"
        property string role: "player"
    }

    QtObject {
        id: fakeGameSession
        property int gameNumber: 1
        property bool finished: false
        property bool sideboarding: false
        property var turnOrder: []
    }

    QtObject {
        id: fakeOptimisticModel
        property int timeoutMs: 0
        property int clearCount: 0
        signal cardMovesChanged()
        signal valuesExpired(int count)
        function clear() { ++clearCount }
    }

    QtObject {
        id: fakeCatalog
        signal languageChanged()
        signal imageRevisionChanged()
    }

    QtObject {
        id: fakeGameTable
        property bool hasSnapshot: true
        property int landPlaysThisTurn: 1
        signal snapshotChanged()
    }

    QtObject {
        id: fakeWindow
        property string banner: ""
        function showBanner(message) { banner = message }
    }

    QtObject {
        id: fakeTable
        property var wsModel: fakeWs
        property var roomSession: fakeRoomSession
        property var gameSession: fakeGameSession
        property bool ownEliminated: false
        property var gameTableModel: fakeGameTable
        property var optimisticCommandModel: fakeOptimisticModel
        property var cardCatalogModel: fakeCatalog
        property var appWindow: fakeWindow
        property var selection: selectionController
        property int optimisticValueTimeoutMs: 2500
        property int restartResetCount: 0
        property bool isEDH: true
        property var authoritativeSeats: []
        property var turnOrder: fakeGameSession.turnOrder
        property var authoritativeOwnHand: []
        property var pendingCardMoves: ({})
        function resetGameInteractions() { ++restartResetCount }
    }

    QtObject {
        id: libraryPopup
        property var lastCards: []
        property int lastSourceSeat: -1
        property string requesterLabel: ""
        property string sourceLabel: ""
        property int invalidationCount: 0
        function invalidate() { ++invalidationCount; lastCards = [] }
        function showCards(cards, sourceSeat, approvalId,
                           requesterSeat, requesterName,
                           sourceName, topCount) {
            lastCards = cards
            lastSourceSeat = sourceSeat
            requesterLabel = requesterName
            sourceLabel = sourceName
        }
    }

    QtObject {
        id: accessPopup
        property int openCount: 0
        function close() {}
        function open() { ++openCount }
    }

    QtObject {
        id: publicZoneMovePopup
        property int openCount: 0
        function close() {}
        function open() { ++openCount }
    }

    QtObject {
        id: optimisticController
        property int queuedCount: 0
        property int failedCount: 0
        property int reconciledLandPlayCount: -1
        function trackQueuedCommand(requestId, commandType, payload) {
            ++queuedCount
        }
        function rollbackFailedCommand(requestId, commandType, payload) {
            ++failedCount
        }
        function reconcileLandPlayCount(count) {
            reconciledLandPlayCount = count
        }
    }

    QtObject {
        id: cardMoveController
        property bool committed: true
        property int clearCount: 0
        function pendingBattlefieldMoveCommitted() { return committed }
        function clearPendingBattlefieldMove() { ++clearCount }
    }

    QtObject {
        id: projectionController
        property int battlefieldCount: 0
        property int handCount: 0
        function syncBattlefieldSeats() { ++battlefieldCount }
        function syncDisplayedOwnHand() { ++handCount }
    }

    property bool useActualProjection: false

    Component {
        id: seatStateComponent
        QtObject {
            property int seat: -1
            function updateFrom(snapshot) { seat = snapshot.seat }
        }
    }

    TableProjectionSyncController {
        id: actualProjection
        tableRoot: fakeTable
        seatStateComponent: seatStateComponent
    }

    QtObject {
        id: zoneController
        property int reconcileCount: 0
        function reconcilePendingCardMoves() { ++reconcileCount }
    }

    QtObject {
        id: gameValueController
        property int reconcileCount: 0
        property int untapFailureCount: 0
        property var untapFailureCommandType: ""
        property var untapFailurePayload: ({})
        function reconcile() { ++reconcileCount }
        function reconcileUntapBatchFailure(commandType, payload) {
            ++untapFailureCount
            untapFailureCommandType = commandType
            untapFailurePayload = payload
        }
    }

    QtObject {
        id: sceneController
        property int refreshCount: 0
        function schedulePointRefresh() { ++refreshCount }
    }

    QtObject {
        id: sessionController
        property int resultCount: 0
        property int counterCount: 0
        function maybeShowGameResult() { ++resultCount }
        function syncOwnCounterCount() { ++counterCount }
    }

    QtObject {
        id: sharedController
        property int reconcileCount: 0
        function reconcileSelection() { ++reconcileCount }
        function displayNameForSeat(seat) { return "Seat " + seat }
    }

    QtObject {
        id: selectionController
        property int reconcileCount: 0
        function reconcileBattlefieldSelection() { ++reconcileCount }
    }

    QtObject {
        id: transientController
        property int reconcileCount: 0
        property string approvalId: ""
        property int topCount: 0
        property string publicMoveApprovalId: ""
        function reconcile() { ++reconcileCount }
        function clearPendingLibraryApproval() { approvalId = "" }
        function clearPendingPublicZoneMoveApproval() { publicMoveApprovalId = "" }
        function clearLibraryMoveDestination() {}
        function setLibraryApproval(id, requester, count) {
            approvalId = id
            topCount = count
        }
        function setPublicZoneMoveApproval(id, requester, sourceZone,
                                           count, toZone) {
            publicMoveApprovalId = id
        }
    }

    QtObject {
        id: presentationController
        property int prioritizeCount: 0
        property int invalidateCount: 0
        property bool emitRevisionOnPrioritize: false
        function prioritizeVisibleCards() {
            ++prioritizeCount
            if (emitRevisionOnPrioritize && prioritizeCount < 20)
                fakeCatalog.imageRevisionChanged()
        }
        function invalidatePriorities() { ++invalidateCount }
    }

    TableRuntimeSyncController {
        id: controller
        autoInitialize: false
        deferInitialReconcile: false
        tableRoot: fakeTable
        librarySearchPopup: libraryPopup
        libraryAccessConfirmation: accessPopup
        publicZoneMoveConfirmation: publicZoneMovePopup
        optimisticController: optimisticController
        cardMoveController: cardMoveController
        projectionController: testCase.useActualProjection
                              ? actualProjection : projectionController
        zoneController: zoneController
        gameValueController: gameValueController
        battlefieldSceneController: sceneController
        sessionController: sessionController
        sharedController: sharedController
        transientController: transientController
        presentationController: presentationController
    }

    function init() {
        useActualProjection = false
        actualProjection.reset()
        fakeTable.authoritativeSeats = []
        fakeGameSession.turnOrder = []
        fakeGameSession.gameNumber = 1
        fakeGameSession.finished = false
        fakeGameSession.sideboarding = false
        fakeRoomSession.role = "player"
        fakeRoomSession.phase = "started"
        fakeWs.seatIndex = 1
        fakeTable.restartResetCount = 0
        fakeGameTable.hasSnapshot = true
        fakeOptimisticModel.timeoutMs = 0
        fakeOptimisticModel.clearCount = 0
        fakeWindow.banner = ""
        accessPopup.openCount = 0
        publicZoneMovePopup.openCount = 0
        optimisticController.queuedCount = 0
        optimisticController.failedCount = 0
        optimisticController.reconciledLandPlayCount = -1
        cardMoveController.clearCount = 0
        projectionController.battlefieldCount = 0
        projectionController.handCount = 0
        zoneController.reconcileCount = 0
        gameValueController.reconcileCount = 0
        gameValueController.untapFailureCount = 0
        gameValueController.untapFailureCommandType = ""
        gameValueController.untapFailurePayload = ({})
        sceneController.refreshCount = 0
        sessionController.resultCount = 0
        sessionController.counterCount = 0
        sharedController.reconcileCount = 0
        selectionController.reconcileCount = 0
        transientController.reconcileCount = 0
        transientController.approvalId = ""
        transientController.topCount = 0
        transientController.publicMoveApprovalId = ""
        presentationController.prioritizeCount = 0
        presentationController.invalidateCount = 0
        presentationController.emitRevisionOnPrioritize = false
        controller.deferInitialReconcile = false
        controller.observedGameNumber = -1
    }

    function test_reconcilesSnapshotAcrossControllers() {
        fakeGameTable.snapshotChanged()
        compare(projectionController.battlefieldCount, 1)
        compare(projectionController.handCount, 1)
        compare(cardMoveController.clearCount, 1)
        compare(zoneController.reconcileCount, 1)
        compare(gameValueController.reconcileCount, 1)
        compare(optimisticController.reconciledLandPlayCount, 1)
        compare(sceneController.refreshCount, 1)
        compare(sessionController.resultCount, 1)
        compare(sessionController.counterCount, 1)
        compare(sharedController.reconcileCount, 1)
        compare(selectionController.reconcileCount, 1)
        compare(transientController.reconcileCount, 1)
        compare(presentationController.prioritizeCount, 1)
    }

    function test_wsSnapshotFinalizesSessionStateWithoutRebuildingTable() {
        fakeWs.gameSnapshotChanged()

        compare(projectionController.handCount, 1)
        compare(gameValueController.reconcileCount, 1)
        compare(sessionController.resultCount, 1)
        compare(sessionController.counterCount, 1)
        compare(transientController.reconcileCount, 1)
        compare(projectionController.battlefieldCount, 1)
        compare(zoneController.reconcileCount, 0)
        compare(sceneController.refreshCount, 0)
    }

    function test_finalSessionSignalAppliesRolledVisualOrder_data() {
        return [
            {tag: "four-seat-0", viewer: 0, order: [2, 1, 3, 0], expected: [2, 1, 0, 3]},
            {tag: "four-seat-1", viewer: 1, order: [2, 1, 3, 0], expected: [3, 0, 1, 2]},
            {tag: "four-seat-2", viewer: 2, order: [2, 1, 3, 0], expected: [1, 3, 2, 0]},
            {tag: "four-seat-3", viewer: 3, order: [2, 1, 3, 0], expected: [0, 2, 3, 1]},
            {tag: "four-spectator", viewer: -1, order: [2, 1, 3, 0], expected: [1, 3, 2, 0]},
            {tag: "three-seat-0", viewer: 0, order: [1, 3, 0], expected: [1, 3, 0]},
            {tag: "three-seat-3", viewer: 3, order: [1, 3, 0], expected: [0, 1, 3]},
            {tag: "three-spectator", viewer: -1, order: [1, 3, 0], expected: [3, 0, 1]}
        ]
    }

    function test_finalSessionSignalAppliesRolledVisualOrder(data) {
        useActualProjection = true
        fakeWs.seatIndex = data.viewer
        fakeRoomSession.role = data.viewer < 0 ? "spectator" : "player"
        fakeTable.authoritativeSeats = data.order.slice().sort().map(
                    seat => ({seat: seat}))
        // GameSessionState emits typed snapshotDataChanged first. Its scalar
        // QML bindings notify later through WsClient.gameSnapshotChanged.
        fakeGameTable.snapshotChanged()
        compare(zoneController.reconcileCount, 1)
        compare(actualProjection.battlefieldSeats.length, data.order.length)

        // No typed zone/seat data changes here: only the rolled turn order
        // becomes visible at the final session signal.
        const typedSeats = fakeTable.authoritativeSeats
        fakeGameSession.turnOrder = data.order
        fakeWs.gameSnapshotChanged()
        compare(actualProjection.battlefieldSeats.map(state => state.seat),
                data.expected)
        compare(fakeTable.authoritativeSeats, typedSeats)
        compare(zoneController.reconcileCount, 1)
        compare(sceneController.refreshCount, 1)

        const states = actualProjection.battlefieldSeats.slice()
        fakeWs.gameSnapshotChanged()
        for (let index = 0; index < states.length; ++index)
            compare(actualProjection.battlefieldSeats[index], states[index])
    }

    function test_finalSessionOrderWaitsUntilBattlefieldDragFinishes() {
        useActualProjection = true
        fakeWs.seatIndex = 0
        fakeTable.authoritativeSeats = [
            {seat: 0}, {seat: 1}, {seat: 2}, {seat: 3}
        ]
        fakeGameTable.snapshotChanged()
        const originalStates = actualProjection.battlefieldSeats.slice()
        actualProjection.activeBattlefieldDragCardId = "dragged-card"
        fakeGameSession.turnOrder = [2, 1, 3, 0]
        fakeWs.gameSnapshotChanged()

        verify(actualProjection.battlefieldSeatSyncDeferred)
        compare(actualProjection.activeBattlefieldDragCardId, "dragged-card")
        for (let index = 0; index < originalStates.length; ++index)
            compare(actualProjection.battlefieldSeats[index], originalStates[index])
        compare(actualProjection.battlefieldSeats.map(state => state.seat),
                [1, 2, 0, 3])

        actualProjection.finishBattlefieldDrag()
        verify(!actualProjection.battlefieldSeatSyncDeferred)
        compare(actualProjection.activeBattlefieldDragCardId, "")
        compare(actualProjection.battlefieldSeats.map(state => state.seat),
                [2, 1, 0, 3])
        compare(zoneController.reconcileCount, 1)
    }

    function test_restartWithIdenticalTypedZonesFinalizesProjectionOnce() {
        controller.observedGameNumber = 1
        fakeWs.gameRestarted()
        compare(fakeTable.restartResetCount, 1)
        compare(projectionController.battlefieldCount, 0)

        fakeWs.gameSnapshotChanged()
        compare(projectionController.battlefieldCount, 1)
        compare(zoneController.reconcileCount, 0)
        compare(fakeTable.restartResetCount, 1)
    }

    function test_newGameFinalizesProjectionAfterInteractionReset() {
        controller.observedGameNumber = 1
        fakeGameSession.gameNumber = 2
        fakeWs.gameSnapshotChanged()
        compare(fakeTable.restartResetCount, 1)
        compare(projectionController.battlefieldCount, 1)
        compare(zoneController.reconcileCount, 0)
        compare(controller.observedGameNumber, 2)
    }

    function test_routesLibraryAndCommandEvents() {
        controller.handleLibraryDumped([{"id": "card"}], 2,
                                       "approval", 4)
        compare(libraryPopup.lastSourceSeat, 2)
        compare(libraryPopup.requesterLabel, "Seat 1")
        compare(libraryPopup.sourceLabel, "Seat 2")

        controller.handleLibraryAccessRequested("approval", "Alice", 3)
        compare(transientController.approvalId, "approval")
        compare(transientController.topCount, 3)
        compare(accessPopup.openCount, 1)

        controller.handlePublicZoneMoveRequested(
                    "public-move", "Alice", "graveyard", 2, "battlefield")
        compare(transientController.publicMoveApprovalId, "public-move")
        compare(publicZoneMovePopup.openCount, 1)

        controller.handleCommandQueued("request", "game.draw", ({}))
        controller.handleCommandFailed("request", "game.draw", ({}),
                                       "failed")
        compare(optimisticController.queuedCount, 1)
        compare(optimisticController.failedCount, 1)
        compare(gameValueController.untapFailureCount, 1)
        compare(gameValueController.untapFailureCommandType, "game.draw")
        compare(fakeWindow.banner, "failed")
    }

    function test_refreshesPresentationOnModelChanges() {
        controller.handleCardMovesChanged()
        compare(projectionController.handCount, 1)
        compare(sharedController.reconcileCount, 1)
        compare(selectionController.reconcileCount, 1)
        compare(transientController.reconcileCount, 1)
        compare(presentationController.prioritizeCount, 1)

        controller.handleLanguageChanged()
        compare(presentationController.invalidateCount, 1)
        compare(presentationController.prioritizeCount, 2)
    }

    function test_catalogCacheHitsDoNotReprioritizeInALoop() {
        presentationController.emitRevisionOnPrioritize = true
        fakeGameTable.snapshotChanged()
        compare(presentationController.prioritizeCount, 1)
        fakeCatalog.imageRevisionChanged()
        compare(presentationController.prioritizeCount, 1)
    }

    function test_initializeConfiguresOptimisticModel() {
        controller.initialize()
        compare(fakeOptimisticModel.clearCount, 1)
        compare(fakeOptimisticModel.timeoutMs, 2500)
        compare(projectionController.battlefieldCount, 1)
        compare(projectionController.handCount, 1)
    }

    function test_initializeSkipsProjectionWithoutSnapshot() {
        fakeGameTable.hasSnapshot = false

        controller.initialize()

        compare(fakeOptimisticModel.clearCount, 1)
        compare(fakeOptimisticModel.timeoutMs, 2500)
        compare(projectionController.battlefieldCount, 0)
        compare(projectionController.handCount, 0)
        compare(sessionController.resultCount, 0)
        compare(presentationController.prioritizeCount, 0)
    }

    function test_snapshotCancelsDeferredInitialReconciliation() {
        controller.deferInitialReconcile = true
        controller.initialize()
        compare(projectionController.battlefieldCount, 1)

        fakeGameTable.snapshotChanged()
        compare(projectionController.battlefieldCount, 2)
        compare(sessionController.resultCount, 1)

        wait(1)
        compare(sessionController.resultCount, 1)
        compare(sharedController.reconcileCount, 1)
        compare(transientController.reconcileCount, 1)
        compare(presentationController.prioritizeCount, 1)
    }

    function test_reportsOptimisticTimeoutRollback() {
        fakeOptimisticModel.valuesExpired(2)
        compare(fakeWindow.banner,
                "2 changes could not be synchronized and were restored.")
    }
}
