// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic

Item {
    id: root

    required property var tableController
    required property var tokenPickerPopup
    required property var handLibraryPositionEditorPopup
    required property var discardHandConfirmation

    readonly property alias battlefieldAreaMenu: battlefieldAreaMenu
    readonly property alias handAreaMenu: handAreaMenu
    readonly property alias handCardMenu: handCardMenu

    Menu {
        id: battlefieldAreaMenu
        objectName: "battlefieldAreaMenu"

        MenuItem {
            objectName: "untapAllBattlefieldAction"
            text: qsTr("Untap all") + " · Ctrl+U"
            enabled: root.tableController.canAct
                     && root.tableController.gameValues.hasTappedOwnPermanent()
            onTriggered: root.tableController.gameValues.untapOwnBattlefield()
        }
        MenuItem {
            objectName: "arrangeBattlefieldAction"
            text: qsTr("Arrange battlefield") + " · Ctrl+Shift+A"
            enabled: root.tableController.canAct
                     && root.tableController.zoneState.zoneCardCount(
                         root.tableController.roomSession.seatIndex,
                         "battlefield") > 0
            onTriggered:
                root.tableController.cardMoveCommands.arrangeOwnBattlefield()
        }
        MenuSeparator { }
        MenuItem {
            objectName: "createTokenAction"
            text: qsTr("Create token") + " · Ctrl+T"
            enabled: root.tableController.canAct
            onTriggered: root.tokenPickerPopup.open()
        }
        Menu {
            title: qsTr("Random tools")
            enabled: root.tableController.canAct

            MenuItem {
                objectName: "rollDiceAction"
                text: qsTr("Roll dice…") + " · Ctrl+R"
                onTriggered: root.tableController.diceRollPopup.showFor(20, 1)
            }
            MenuItem {
                objectName: "flipCoinAction"
                text: qsTr("Flip a coin") + " · Ctrl+Shift+C"
                onTriggered: root.tableController.wsModel.flipCoin()
            }
            MenuItem {
                objectName: "randomPlayerAction"
                text: qsTr("Random player") + " · Ctrl+Alt+P"
                onTriggered: root.tableController.wsModel.randomSelectPlayer()
            }
            MenuItem {
                objectName: "randomBattlefieldCardAction"
                text: qsTr("Random battlefield card") + " · Ctrl+Alt+R"
                enabled: root.tableController.selection.allCardIds().length > 0
                onTriggered: root.tableController.wsModel.randomSelectCards(
                                 root.tableController.selection.allCardIds())
            }
        }
        ConditionalMenuSeparator {
            visible: !root.tableController.isPlaytest
        }
        ConditionalMenuItem {
            objectName: "declareDrawAction"
            visible: !root.tableController.isPlaytest
            text: qsTr("Declare draw") + " · Ctrl+Shift+D"
            enabled: root.tableController.canAct
            onTriggered: root.tableController.drawConfirmation.open()
        }
        MenuItem {
            objectName: "restartGameAction"
            text: qsTr("Restart game") + " · Ctrl+Shift+R"
            enabled: root.tableController.canAct
                     && root.tableController.roomSession.host
            onTriggered: root.tableController.restartConfirmation.open()
        }
        ConditionalMenuItem {
            objectName: "concedeAction"
            visible: !root.tableController.isPlaytest
            text: qsTr("Concede") + " · Ctrl+Shift+Q"
            enabled: !root.tableController.gameFinished
                     && !root.tableController.ownEliminated
                     && !root.tableController.gameSession.sideboarding
            onTriggered: root.tableController.concedeConfirmation.open()
        }
    }

    Menu {
        id: handAreaMenu
        objectName: "handAreaMenu"

        MenuItem {
            objectName: "revealHandAction"
            text: (root.tableController.ownRevealedCards.length > 0
                   ? qsTr("Recall hand")
                   : qsTr("Reveal hand")) + " · Ctrl+H"
            enabled: root.tableController.canAct
                     && (root.tableController.projectionSync.visibleOwnHandCount() > 0
                         || root.tableController.ownRevealedCards.length > 0)
                     && !root.tableController.zoneState.handRevealTransitionPending()
            onTriggered: root.tableController.cardActions.toggleHandReveal()
        }
        MenuSeparator { }
        MenuItem {
            objectName: "discardRandomHandCardAction"
            text: qsTr("Discard a random card") + " · Ctrl+Alt+X"
            enabled: root.tableController.canAct
                     && root.tableController.projectionSync.visibleOwnHandCount() > 0
            onTriggered: root.tableController.wsModel.discardHand(false)
        }
        MenuItem {
            objectName: "discardEntireHandAction"
            text: qsTr("Discard entire hand…") + " · Ctrl+Shift+X"
            enabled: root.tableController.canAct
                     && root.tableController.projectionSync.visibleOwnHandCount() > 0
            onTriggered: root.discardHandConfirmation.open()
        }
        MenuSeparator { }
        MenuItem {
            objectName: "mulliganAction"
            text: qsTr("Mulligan") + " · Ctrl+M"
            enabled: root.tableController.canAct
                     && root.tableController.authoritativeSeats.length > 0
            onTriggered: root.tableController.mulliganConfirmation.open()
        }
    }

    Menu {
        id: handCardMenu
        objectName: "handCardMenu"

        MenuItem {
            objectName: "playLandAction"
            text: qsTr("Play land…") + " · P"
            enabled: root.tableController.isActivePlayer
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered: root.tableController.landPlay.requestSelectedHandCard()
        }
        MenuSeparator { }
        MenuItem {
            text: qsTr("Move to battlefield") + " · Alt+B"
            enabled: root.tableController.canAct
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedHandCard("battlefield")
        }
        MenuItem {
            text: qsTr("Move to battlefield face down") + " · Alt+Shift+B"
            enabled: root.tableController.canAct
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered: root.tableController.cardMoveCommands.moveSelectedHandCard(
                             "battlefield", true)
        }
        MenuItem {
            text: qsTr("Move to graveyard") + " · Alt+G"
            enabled: root.tableController.canAct
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedHandCard("graveyard")
        }
        MenuItem {
            text: qsTr("Move to exile") + " · Alt+E"
            enabled: root.tableController.canAct
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedHandCard("exile")
        }
        MenuSeparator { }
        MenuItem {
            text: qsTr("Move to top of library") + " · Alt+Up"
            enabled: root.tableController.canAct
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered: root.tableController.cardMoveCommands.moveSelectedHandToLibrary(
                             "top", -1)
        }
        MenuItem {
            text: qsTr("Move to library position…")
            enabled: root.tableController.canAct
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered: root.handLibraryPositionEditorPopup.showFor(
                             root.tableController.selectedHandCard.name)
        }
        MenuItem {
            text: qsTr("Move to bottom of library") + " · Alt+Down"
            enabled: root.tableController.canAct
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered: root.tableController.cardMoveCommands.moveSelectedHandToLibrary(
                             "bottom", -1)
        }
    }
}
