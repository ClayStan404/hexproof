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
        signal commandQueued(string requestId, string commandType,
                             var payload)
        signal commandFailed(string requestId, string commandType,
                             var payload, string error)
    }

    QtObject {
        id: fakeRoomSession
        property int seatIndex: fakeWs.seatIndex
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
        property var gameTableModel: fakeGameTable
        property var optimisticCommandModel: fakeOptimisticModel
        property var cardCatalogModel: fakeCatalog
        property var appWindow: fakeWindow
        property int optimisticValueTimeoutMs: 2500
    }

    QtObject {
        id: libraryPopup
        property var lastCards: []
        property int lastSourceSeat: -1
        property string requesterLabel: ""
        property string sourceLabel: ""
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
        function open() { ++openCount }
    }

    QtObject {
        id: publicZoneMovePopup
        property int openCount: 0
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
        property int logCount: 0
        property int handCount: 0
        function syncBattlefieldSeats() { ++battlefieldCount }
        function syncGameLog() { ++logCount }
        function syncDisplayedOwnHand() { ++handCount }
    }

    QtObject {
        id: zoneController
        property int reconcileCount: 0
        function reconcilePendingCardMoves() { ++reconcileCount }
    }

    QtObject {
        id: gameValueController
        property int reconcileCount: 0
        function reconcile() { ++reconcileCount }
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
        id: transientController
        property int reconcileCount: 0
        property string approvalId: ""
        property int topCount: 0
        property string publicMoveApprovalId: ""
        function reconcile() { ++reconcileCount }
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
        projectionController: projectionController
        zoneController: zoneController
        gameValueController: gameValueController
        battlefieldSceneController: sceneController
        sessionController: sessionController
        sharedController: sharedController
        transientController: transientController
        presentationController: presentationController
    }

    function init() {
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
        projectionController.logCount = 0
        projectionController.handCount = 0
        zoneController.reconcileCount = 0
        gameValueController.reconcileCount = 0
        sceneController.refreshCount = 0
        sessionController.resultCount = 0
        sessionController.counterCount = 0
        sharedController.reconcileCount = 0
        transientController.reconcileCount = 0
        transientController.approvalId = ""
        transientController.topCount = 0
        transientController.publicMoveApprovalId = ""
        presentationController.prioritizeCount = 0
        presentationController.invalidateCount = 0
        presentationController.emitRevisionOnPrioritize = false
    }

    function test_reconcilesSnapshotAcrossControllers() {
        fakeGameTable.snapshotChanged()
        compare(projectionController.battlefieldCount, 1)
        compare(projectionController.logCount, 1)
        compare(projectionController.handCount, 1)
        compare(cardMoveController.clearCount, 1)
        compare(zoneController.reconcileCount, 1)
        compare(gameValueController.reconcileCount, 1)
        compare(optimisticController.reconciledLandPlayCount, 1)
        compare(sceneController.refreshCount, 1)
        compare(sessionController.resultCount, 1)
        compare(sessionController.counterCount, 1)
        compare(sharedController.reconcileCount, 1)
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
        compare(projectionController.battlefieldCount, 0)
        compare(projectionController.logCount, 0)
        compare(zoneController.reconcileCount, 0)
        compare(sceneController.refreshCount, 0)
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
        compare(fakeWindow.banner, "failed")
    }

    function test_refreshesPresentationOnModelChanges() {
        controller.handleCardMovesChanged()
        compare(projectionController.handCount, 1)
        compare(sharedController.reconcileCount, 1)
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
        compare(projectionController.logCount, 1)
        compare(projectionController.handCount, 1)
    }

    function test_reportsOptimisticTimeoutRollback() {
        fakeOptimisticModel.valuesExpired(2)
        compare(fakeWindow.banner,
                "2 changes could not be synchronized and were restored.")
    }
}
