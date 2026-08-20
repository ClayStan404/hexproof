// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import "../components"

Page {
    id: root

    required property var wsModel
    required property var gameTableModel
    required property var optimisticCommandModel
    required property var sideboardTableModel
    required property var cardCatalogModel
    property var deckLibraryModel: null
    property var tournamentModel: null
    readonly property var appWindow: ApplicationWindow.window
    property var preferencesModel: null
    readonly property var roomSession: wsModel.roomSession
    readonly property var gameSession: wsModel.gameSession
    readonly property var authoritativeSeats: gameTableModel.seats
    readonly property var tableArrows: gameTableModel.arrows
    readonly property var tableAttachments: gameTableModel.attachments
    readonly property var tableCommanders: gameTableModel.commanders
    readonly property var tableCommanderDamage: gameTableModel.commanderDamage
    readonly property var tableGameLog: gameTableModel.gameLog
    readonly property var ownSeatData:
        seatStateController.seatData(roomSession.seatIndex)
    readonly property var authoritativeOwnHand:
        zoneStateController.zoneCardsForSeat(roomSession.seatIndex, "hand")
    property alias ownHand: projectionSyncController.ownHand
    property alias activeHandDragCardId:
        projectionSyncController.activeHandDragCardId
    property alias battlefieldSeats: projectionSyncController.battlefieldSeats
    property alias activeBattlefieldDragCardId:
        projectionSyncController.activeBattlefieldDragCardId
    readonly property var stackCards:
        zoneStateController.sharedZoneCards("stack")
    readonly property var revealedCards:
        zoneStateController.sharedZoneCards("reveal")
    readonly property var ownRevealedCards:
        zoneStateController.revealedCardsForSeat(roomSession.seatIndex)
    readonly property var sharedCards: sharedZoneController.cards
    readonly property bool gameFinished: gameSession.finished === true
    readonly property bool isEDH: roomSession.format === "edh"
    readonly property bool isCommanderFormat:
        roomSession.format === "duel" || isEDH
    readonly property var ownCommanderCards:
        isCommanderFormat ? gameValueController.commanderCards(ownSeatData) : []
    readonly property bool hasPartnerCommanders:
        ownCommanderCards.length > 1
    readonly property bool isPlaytest: roomSession.playtest === true
    readonly property bool usesEDHBattlefieldLayout: isEDH && !isPlaytest
    readonly property url cardBackSource:
        Qt.resolvedUrl("../assets/card-back.jpg")
    readonly property bool ownEliminated: ownSeatData.eliminated === true
    readonly property bool canAct: roomSession.role === "player"
                                    && (wsModel.inRoom === undefined
                                        || wsModel.inRoom)
                                    && !gameFinished
                                    && !gameSession.sideboarding
                                    && !ownEliminated
    readonly property bool canChat: roomSession.phase === "started"
                                    && (wsModel.inRoom === undefined
                                        || wsModel.inRoom)
                                    && (roomSession.role === "player"
                                        || roomSession.role === "spectator")
    readonly property var winnerData:
        gameFinished
        ? seatStateController.seatData(gameSession.result.winnerSeat) : ({})
    readonly property var concededData:
        gameFinished
        ? seatStateController.seatData(gameSession.result.concededSeat) : ({})
    property alias selectedSharedCard: sharedZoneController.selectedCard
    property alias selectedSharedZone: sharedZoneController.selectedZone
    property alias selectedCounterSeat: transientStateController.selectedCounterSeat
    property alias selectedCounterKey: transientStateController.selectedCounterKey
    readonly property var pendingBattlefieldMove:
        optimisticCommandModel.battlefieldMove
    property alias inspectedCard: cardPresentationController.inspectedCard
    property alias hoverPreviewVisible:
        cardPresentationController.hoverPreviewVisible
    property alias hoverPreviewX: cardPresentationController.hoverPreviewX
    property alias hoverPreviewY: cardPresentationController.hoverPreviewY
    property alias selectedBattlefieldCardId: selectionController.selectedCardId
    property alias selectedBattlefieldOwnerSeat: selectionController.selectedOwnerSeat
    property alias selectedBattlefieldCard: selectionController.selectedCard
    property alias selectedBattlefieldFaces: selectionController.selectedFaces
    property alias selectedBattlefieldCardIds: selectionController.selectedCardIds
    property alias selectedHandCard: transientStateController.selectedHandCard
    property alias battlefieldInteractionMode: selectionController.interactionMode
    readonly property string optimisticPhase:
        optimisticCommandModel.phase
    property alias pendingLibraryApprovalId:
        transientStateController.pendingLibraryApprovalId
    property alias pendingLibraryRequesterName:
        transientStateController.pendingLibraryRequesterName
    property alias libraryMoveDestination:
        transientStateController.libraryMoveDestination
    readonly property var pendingCardMoves:
        optimisticController.pendingCardMoves
    readonly property var optimisticLifeTotals:
        optimisticCommandModel.lifeValues
    readonly property var optimisticTappedCards:
        optimisticCommandModel.tappedValues
    readonly property var optimisticCounterValues:
        optimisticCommandModel.counterValues
    readonly property var optimisticCommanderTax:
        optimisticCommandModel.commanderTaxValues
    property int optimisticValueTimeoutMs: 2500
    property int approvalTimeoutSeconds: 90
    readonly property string displayedPhase:
        optimisticPhase.length > 0 ? optimisticPhase : gameSession.currentPhase
    readonly property var battlefieldCardPoints:
        battlefieldSceneController.cardPoints
    readonly property var battlefieldSeatPoints:
        battlefieldSceneController.seatPoints
    readonly property var cardMoveCommands: cardMoveController
    readonly property var battlefieldLayout: battlefieldGeometry
    readonly property var cardActions: cardActionController
    readonly property var optimisticCommands: optimisticController
    readonly property var gameValues: gameValueController
    readonly property var rulesAssist: rulesAssistController
    readonly property var landPlay: landPlayController
    readonly property var attachmentUi: attachmentController
    readonly property var zoneState: zoneStateController
    readonly property var battlefieldScene: battlefieldSceneController
    readonly property var projectionSync: projectionSyncController
    readonly property var sharedZones: sharedZoneController
    readonly property var presentation: cardPresentationController
    readonly property var transientState: transientStateController
    readonly property var sessionUi: sessionUiController
    readonly property var selection: selectionController
    readonly property var seatState: seatStateController
    readonly property var chatInput: sceneShell.chatInput
    readonly property var librarySearchPopup: sceneShell.librarySearchPopup
    readonly property var publicZoneBrowser: sceneShell.publicZoneBrowser
    readonly property var lifeEditor: sceneShell.lifeEditor
    readonly property var drawCardsEditor: sceneShell.drawCardsEditor
    readonly property var libraryTopCountEditor: sceneShell.libraryTopCountEditor
    readonly property var libraryMoveCardsEditor: sceneShell.libraryMoveCardsEditor
    readonly property var counterLabelEditor: sceneShell.counterLabelEditor
    readonly property var playerCounterValueEditor:
        sceneShell.playerCounterValueEditor
    readonly property var cardCounterEditor: sceneShell.cardCounterEditor
    readonly property var cardFacePicker: sceneShell.cardFacePicker
    readonly property var libraryPositionEditor:
        sceneShell.libraryPositionEditor
    readonly property var handLibraryPositionEditor:
        sceneShell.handLibraryPositionEditor
    readonly property var tokenPicker: sceneShell.tokenPicker
    readonly property var tableSettingsPopup: sceneShell.tableSettingsPopup
    readonly property var shortcutHelp: sceneShell.shortcutHelp
    property bool suppressBattlefieldAreaMenu: false
    property string edhBattlefieldLayout: "grid"
    property int edhFocusedSeat: -1
    readonly property bool edhFocusLayout:
        usesEDHBattlefieldLayout && edhBattlefieldLayout === "focus"
    readonly property bool compactLayout: Theme.isCompactWidth(width)
    readonly property real actionRailWidth: Theme.size(compactLayout ? 120 : 144)
    readonly property real sharedZoneRailWidth: Theme.size(92)
    readonly property real gameLogRailWidth: Theme.size(compactLayout ? 148 : 176)
    readonly property real battlefieldCardWidth:
        Theme.size(compactLayout ? 72 : 80) * battlefieldLayout.cardScale
    readonly property real battlefieldCardHeight:
        Theme.size(compactLayout ? 100 : 112) * battlefieldLayout.cardScale
    readonly property real handAreaHeight:
        Theme.size(compactLayout
                   ? (root.isCommanderFormat ? 168 : 148)
                   : (root.isCommanderFormat ? 196 : 176))
    readonly property real handCardWidth: Theme.size(compactLayout ? 78 : 86)
    property bool compactChromeTouched: false
    property bool showPlayerColumn:
        preferencesModel ? preferencesModel.tableShowPlayers : true
    property bool showSharedColumn:
        preferencesModel ? preferencesModel.tableShowShared : true
    property bool showInspectorColumn:
        preferencesModel ? preferencesModel.tableShowInspector : true
    property bool showGameLogRail:
        preferencesModel ? preferencesModel.tableShowGameLog : true
    property int visibleCounterCount:
        preferencesModel ? preferencesModel.tableCounterCount : 0
    property alias counterCountRequestGame:
        optimisticController.counterCountRequestGame
    property alias counterCountRequestValue:
        optimisticController.counterCountRequestValue
    readonly property var diceRollPopup: sceneShell.diceRollPopup
    readonly property var leaveRoomConfirmation:
        sceneShell.leaveRoomConfirmation
    readonly property var libraryAccessConfirmation:
        sceneShell.libraryAccessConfirmation
    readonly property var publicZoneMoveConfirmation:
        sceneShell.publicZoneMoveConfirmation
    readonly property var concedeConfirmation:
        sceneShell.concedeConfirmation
    readonly property var shuffleConfirmation:
        sceneShell.shuffleConfirmation
    readonly property var mulliganConfirmation:
        sceneShell.mulliganConfirmation
    readonly property var discardHandConfirmation:
        sceneShell.discardHandConfirmation
    readonly property var drawConfirmation: sceneShell.drawConfirmation
    readonly property var restartConfirmation:
        sceneShell.restartConfirmation
    readonly property var rulesWarningDialog:
        sceneShell.rulesWarningDialog
    readonly property var combatDeclarationPopup:
        sceneShell.combatDeclarationPopup
    readonly property var gameResultPopup: sceneShell.gameResultPopup
    readonly property var landPlayPopup: sceneShell.landPlayPopup
    readonly property var commanderDamagePopup: sceneShell.commanderDamagePopup
    readonly property var ownLibraryMenu: sceneShell.ownLibraryMenu
    readonly property var opponentLibraryMenu: sceneShell.opponentLibraryMenu
    readonly property var battlefieldAreaMenu:
        sceneShell.battlefieldAreaMenu
    readonly property var handAreaMenu: sceneShell.handAreaMenu
    readonly property var handCardMenu: sceneShell.handCardMenu
    readonly property var cardToolsMenu: sceneShell.cardToolsMenu
    readonly property bool tableModalOpen: sceneShell.modalOpen
    readonly property bool selectedSharedOwned:
        sharedZoneController.selectedOwned
    readonly property bool isActivePlayer: root.canAct
                                                   && roomSession.seatIndex
                                                      === gameSession.activeSeat
    background: Rectangle { color: Theme.surfaceMuted }
    Component.onCompleted: {
        runtimeSyncController.initialize()
        sessionUi.applyCompactChrome()
    }
    onCompactLayoutChanged: sessionUi.applyCompactChrome()
    TableSeatStateController {
        id: seatStateController
        gameTableModel: root.gameTableModel
    }

    TableSelectionController {
        id: selectionController
        tableRoot: root
    }

    TableBattlefieldGeometry {
        id: battlefieldGeometry
        tableRoot: root
    }

    TableOptimisticCommandController {
        id: optimisticController
        model: root.optimisticCommandModel
        wsModel: root.wsModel
    }

    TableCardMoveController {
        id: cardMoveController
        tableRoot: root
    }

    TableCardActionController {
        id: cardActionController
        tableRoot: root
        chatInput: root.chatInput
    }

    TableGameValueController {
        id: gameValueController
        tableRoot: root
    }

    TableRulesAssistController {
        id: rulesAssistController
        tableRoot: root
        warningDialog: root.rulesWarningDialog
        combatPopup: root.combatDeclarationPopup
    }

    TableLandPlayController {
        id: landPlayController
        tableRoot: root
        popup: root.landPlayPopup
    }

    TableAttachmentController {
        id: attachmentController
        tableRoot: root
    }

    TableZoneStateController {
        id: zoneStateController
        tableRoot: root
    }

    TableBattlefieldSceneController {
        id: battlefieldSceneController
        tableRoot: root
        sceneView: sceneShell
    }

    TableProjectionSyncController {
        id: projectionSyncController
        tableRoot: root
        seatStateComponent: battlefieldSeatStateComponent
        gameLogModel: stableGameLogModel
    }

    TableSharedZoneController {
        id: sharedZoneController
        tableRoot: root
        playerLabel: qsTr("Player")
        revealedLabel: qsTr("Revealed")
    }

    TableCardPresentationController {
        id: cardPresentationController
        tableRoot: root
    }

    TableTransientStateController {
        id: transientStateController
        tableRoot: root
    }

    TableSessionUiController {
        id: sessionUiController
        tableRoot: root
        settingsPopup: root.tableSettingsPopup
        resultPopup: root.gameResultPopup
        chatInput: root.chatInput
        counterLabelEditor: root.counterLabelEditor
        counterValueEditor: root.playerCounterValueEditor
        libraryMoveCardsEditor: root.libraryMoveCardsEditor
        gameLabel: qsTr("Game")
        gameDrawnLabel: qsTr("Game drawn")
        playerLabel: qsTr("Player")
        winsGameTemplate: qsTr("%1 wins Game %2")
        winsMatchTemplate: qsTr("%1 wins the match")
        drawDetailLabel: qsTr("The game ended in a draw.")
        scoreLabel: qsTr("Score")
        leftMatchTemplate: qsTr("%1 left the match")
        concededTemplate: qsTr("%1 conceded")
        detailScoreTemplate: qsTr("%1 · Score %2")
    }

    TableRuntimeSyncController {
        id: runtimeSyncController
        tableRoot: root
        librarySearchPopup: root.librarySearchPopup
        libraryAccessConfirmation: root.libraryAccessConfirmation
        publicZoneMoveConfirmation: root.publicZoneMoveConfirmation
        optimisticController: optimisticController
        cardMoveController: cardMoveController
        projectionController: projectionSyncController
        zoneController: zoneStateController
        gameValueController: gameValueController
        battlefieldSceneController: battlefieldSceneController
        sessionController: sessionUiController
        sharedController: sharedZoneController
        transientController: transientStateController
        presentationController: cardPresentationController
    }

    Component {
        id: battlefieldSeatStateComponent

        BattlefieldSeatState {
            tableRoot: root
        }
    }

    ListModel {
        id: stableGameLogModel
        dynamicRoles: true
    }

    TableSceneShell {
        id: sceneShell
        tableController: root
        gameLogModel: stableGameLogModel
    }

}
