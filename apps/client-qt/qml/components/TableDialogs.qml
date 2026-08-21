// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic

Item {
    id: root

    required property var tableController
    property int approvalTimeoutSeconds:
        tableController.approvalTimeoutSeconds !== undefined
        ? tableController.approvalTimeoutSeconds : 90
    property int libraryApprovalRemaining: approvalTimeoutSeconds
    property int publicMoveApprovalRemaining: approvalTimeoutSeconds

    readonly property alias diceRollPopup: diceRollPopup
    readonly property alias leaveRoomConfirmation: leaveRoomConfirmation
    readonly property alias libraryAccessConfirmation:
        libraryAccessConfirmation
    readonly property alias publicZoneMoveConfirmation:
        publicZoneMoveConfirmation
    readonly property alias concedeConfirmation: concedeConfirmation
    readonly property alias shuffleConfirmation: shuffleConfirmation
    readonly property alias mulliganConfirmation: mulliganConfirmation
    readonly property alias discardHandConfirmation: discardHandConfirmation
    readonly property alias drawConfirmation: drawConfirmation
    readonly property alias restartConfirmation: restartConfirmation
    readonly property alias rulesWarningDialog: rulesWarningDialog
    readonly property alias combatDeclarationPopup:
        combatDeclarationPopup
    readonly property alias gameResultPopup: gameResultPopup
    readonly property alias landPlayPopup: landPlayPopup

    Timer {
        interval: 1000
        repeat: true
        running: libraryAccessConfirmation.opened
        onTriggered: {
            root.libraryApprovalRemaining =
                Math.max(0, root.libraryApprovalRemaining - 1)
            if (root.libraryApprovalRemaining > 0)
                return
            libraryAccessConfirmation.close()
            root.showBanner(qsTr("The library access request expired."))
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: publicZoneMoveConfirmation.opened
        onTriggered: {
            root.publicMoveApprovalRemaining =
                Math.max(0, root.publicMoveApprovalRemaining - 1)
            if (root.publicMoveApprovalRemaining > 0)
                return
            publicZoneMoveConfirmation.close()
            root.showBanner(qsTr("The public-zone move request expired."))
        }
    }

    function showBanner(message) {
        if (root.tableController.appWindow
                && typeof root.tableController.appWindow.showBanner
                === "function") {
            root.tableController.appWindow.showBanner(message)
        }
    }

    DiceRollPopup {
        id: diceRollPopup
        objectName: "diceRollPopup"
        onRollRequested: (sides, count) =>
            root.tableController.wsModel.rollDice(sides, count)
    }

    LandPlayPopup {
        id: landPlayPopup
        objectName: "landPlayPopup"
        cardCatalogModel: root.tableController.cardCatalogModel
        onPlayRequested: faceName =>
            root.tableController.landPlay.commit(faceName)
        onClosed: root.tableController.landPlay.cancel()
    }

    ConfirmDialog {
        id: leaveRoomConfirmation
        objectName: "leaveRoomConfirmation"
        titleText: root.tableController.isPlaytest
                   ? qsTr("End this playtest?")
                   : (root.tableController.roomSession.host
                      ? qsTr("Disband the room?")
                      : qsTr("Leave this room?"))
        message: {
            if (root.tableController.isPlaytest)
                return qsTr("This ends the current playtest and returns to the main menu.")
            if (root.tableController.roomSession.host)
                return qsTr("Leaving as host disbands the room for every player and spectator.")
            if (root.tableController.roomSession.role === "spectator")
                return qsTr("You will stop spectating and return to the main menu.")
            if (root.tableController.gameFinished)
                return qsTr("You will leave the finished table and return to the main menu.")
            if (root.tableController.isEDH)
                return qsTr("Leaving now eliminates you; the remaining Commander players continue.")
            return qsTr("Leaving now forfeits the match to your opponent.")
        }
        confirmText: root.tableController.isPlaytest
                     ? qsTr("End playtest")
                     : (root.tableController.roomSession.host
                        ? qsTr("Disband")
                        : qsTr("Leave room"))
        dangerous: true
        onConfirmed: root.tableController.wsModel.leaveRoom()
    }

    ConfirmDialog {
        id: libraryAccessConfirmation
        objectName: "libraryAccessConfirmation"
        titleText: qsTr("Library access request")
        message: {
            const requester = root.tableController.transientState
                                  .pendingLibraryRequesterName
            const topCount = root.tableController.transientState
                                 .pendingLibraryTopCount
            if (topCount === 1) {
                return qsTr("%1 wants to view the top card of your library. Allow access?")
                    .arg(requester) + "\n"
                    + qsTr("Expires in %1s").arg(
                        root.libraryApprovalRemaining)
            }
            if (topCount > 1) {
                return qsTr("%1 wants to view the top %2 cards of your library. Allow access?")
                    .arg(requester).arg(topCount) + "\n"
                    + qsTr("Expires in %1s").arg(
                        root.libraryApprovalRemaining)
            }
            return qsTr("%1 wants to search your library. Allow access?")
                .arg(requester) + "\n"
                + qsTr("Expires in %1s").arg(
                    root.libraryApprovalRemaining)
        }
        confirmText: qsTr("Allow")
        closePolicy: Popup.NoAutoClose
        onOpened: root.libraryApprovalRemaining =
                  root.approvalTimeoutSeconds
        onConfirmed: {
            root.tableController.wsModel.respondZoneDump(
                        root.tableController.transientState.pendingLibraryApprovalId, true)
            root.tableController.transientState.clearPendingLibraryApproval()
        }
        onCancelled: {
            root.tableController.wsModel.respondZoneDump(
                        root.tableController.transientState.pendingLibraryApprovalId, false)
            root.tableController.transientState.clearPendingLibraryApproval()
        }
    }

    ConfirmDialog {
        id: publicZoneMoveConfirmation
        objectName: "publicZoneMoveConfirmation"
        titleText: qsTr("Public zone move request")
        message: qsTr("%1 wants to move %2 card(s) from your %3 to %4. Allow this move?")
                 .arg(root.tableController.transientState
                      .pendingPublicZoneMoveRequesterName)
                 .arg(root.tableController.transientState
                      .pendingPublicZoneMoveCardCount)
                 .arg(I18n.zoneLabel(root.tableController.transientState
                                     .pendingPublicZoneMoveSourceZone))
                 .arg(I18n.zoneLabel(root.tableController.transientState
                                     .pendingPublicZoneMoveToZone))
                 + "\n" + qsTr("Expires in %1s").arg(
                     root.publicMoveApprovalRemaining)
        confirmText: qsTr("Allow")
        closePolicy: Popup.NoAutoClose
        onOpened: root.publicMoveApprovalRemaining =
                  root.approvalTimeoutSeconds
        onConfirmed: {
            root.tableController.wsModel.respondPublicZoneMove(
                        root.tableController.transientState
                        .pendingPublicZoneMoveApprovalId, true)
            root.tableController.transientState
                .clearPendingPublicZoneMoveApproval()
        }
        onCancelled: {
            root.tableController.wsModel.respondPublicZoneMove(
                        root.tableController.transientState
                        .pendingPublicZoneMoveApprovalId, false)
            root.tableController.transientState
                .clearPendingPublicZoneMoveApproval()
        }
    }

    ConfirmDialog {
        id: concedeConfirmation
        objectName: "concedeConfirmation"
        titleText: qsTr("Concede this game?")
        message: root.tableController.isEDH
                 ? qsTr("Conceding eliminates you; the remaining Commander players continue.")
                 : qsTr("This immediately gives your opponent the game. This cannot be undone.")
        confirmText: qsTr("Concede")
        dangerous: true
        onConfirmed: root.tableController.wsModel.concede()
    }

    ConfirmDialog {
        id: shuffleConfirmation
        objectName: "shuffleConfirmation"
        titleText: qsTr("Shuffle your library?")
        message: qsTr("This randomizes the remaining hidden cards in your library. Card counts stay the same, and nobody sees the new order.")
        confirmText: qsTr("Shuffle")
        onConfirmed: root.tableController.wsModel.shuffleLibrary()
    }

    ConfirmDialog {
        id: mulliganConfirmation
        objectName: "mulliganConfirmation"
        titleText: qsTr("Mulligan this hand?")
        message: qsTr("Your hand returns to the library, the library is shuffled, and you draw up to seven cards. This cannot be undone.")
        confirmText: qsTr("Mulligan")
        dangerous: true
        onConfirmed: root.tableController.wsModel.mulligan()
    }

    ConfirmDialog {
        id: discardHandConfirmation
        objectName: "discardHandConfirmation"
        titleText: qsTr("Discard your entire hand?")
        message: qsTr("Every card in your hand will move to its owner's graveyard. This cannot be undone.")
        confirmText: qsTr("Discard all")
        dangerous: true
        onConfirmed: root.tableController.wsModel.discardHand(true)
    }

    ConfirmDialog {
        id: drawConfirmation
        objectName: "drawConfirmation"
        titleText: qsTr("Declare this game a draw?")
        message: root.tableController.roomSession.matchMode === "bo3"
                 ? qsTr("The score stays unchanged and sideboarding begins.")
                 : qsTr("This ends the match without a winner.")
        confirmText: qsTr("Declare draw")
        onConfirmed: root.tableController.wsModel.declareDraw()
    }

    ConfirmDialog {
        id: restartConfirmation
        objectName: "restartConfirmation"
        titleText: qsTr("Restart this game?")
        message: qsTr("The current table is replaced by newly shuffled decks and opening hands. The score and starting player stay unchanged.")
        confirmText: qsTr("Restart game")
        dangerous: true
        onConfirmed: root.tableController.wsModel.restartGame()
    }

    ConfirmDialog {
        id: rulesWarningDialog
        objectName: "rulesWarningDialog"
        titleText: root.tableController.rulesAssist.warningTitle
        message: root.tableController.rulesAssist.warningMessage
        confirmText: root.tableController.rulesAssist.warningConfirmText
        onConfirmed:
            root.tableController.rulesAssist.confirmPendingNavigation()
        onCancelled:
            root.tableController.rulesAssist.cancelPendingNavigation()
    }

    CombatDeclarationPopup {
        id: combatDeclarationPopup
        objectName: "combatDeclarationPopup"
        onDeclarationRequested: function(kind, sourceCardIds,
                                         targetCardId, targetSeat,
                                         tappedSourceCardIds) {
            root.tableController.rulesAssist.commitCombatDeclaration(
                        kind, sourceCardIds, targetCardId,
                        targetSeat, tappedSourceCardIds)
        }
    }

    GameResultPopup {
        id: gameResultPopup
        objectName: "gameResultPopup"
        titleText: root.tableController.sessionUi.resultTitle()
        detailText: root.tableController.sessionUi.resultDetail()
        outcome: root.tableController.sessionUi.resultOutcome()
        onReturnRequested: root.tableController.wsModel.returnToRoom()
    }
}
