// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: root

    required property var tableController
    required property var tokenPickerPopup
    required property var handLibraryPositionEditorPopup
    required property var discardHandConfirmation

    readonly property alias battlefieldAreaMenu: battlefieldAreaMenu
    readonly property alias handAreaMenu: handAreaMenu
    readonly property alias handCardMenu: handCardMenu

    AppMenu {
        id: battlefieldAreaMenu
        objectName: "battlefieldAreaMenu"

        AppMenuItem {
            objectName: "untapAllBattlefieldAction"
            text: qsTr("Untap all")
            shortcutId: "table.untapAll"
            enabled: root.tableController.canAct
                     && root.tableController.gameValues.hasTappedOwnPermanent()
            onTriggered: root.tableController.gameValues.untapOwnBattlefield()
        }
        AppMenuItem {
            objectName: "arrangeBattlefieldAction"
            text: qsTr("Arrange battlefield")
            shortcutId: "table.arrangeBattlefield"
            enabled: root.tableController.canAct
                     && root.tableController.zoneState.zoneCardCount(
                         root.tableController.roomSession.seatIndex,
                         "battlefield") > 0
            onTriggered:
                root.tableController.cardMoveCommands.arrangeOwnBattlefield()
        }
        AppMenuSeparator { }
        AppMenuItem {
            objectName: "createTokenAction"
            text: qsTr("Tokens and emblems")
            shortcutId: "table.createToken"
            enabled: root.tableController.canAct
            onTriggered: root.tokenPickerPopup.open()
        }
        AppMenu {
            title: qsTr("Random tools")
            enabled: root.tableController.canAct

            AppMenuItem {
                objectName: "rollDiceAction"
                text: qsTr("Roll dice…")
                shortcutId: "table.rollDice"
                onTriggered: root.tableController.diceRollPopup.showFor(20, 1)
            }
            AppMenuItem {
                objectName: "flipCoinAction"
                text: qsTr("Flip a coin")
                shortcutId: "table.flipCoin"
                onTriggered: root.tableController.wsModel.flipCoin()
            }
            AppMenuItem {
                objectName: "randomPlayerAction"
                text: qsTr("Random player")
                shortcutId: "table.randomPlayer"
                onTriggered: root.tableController.wsModel.randomSelectPlayer()
            }
            AppMenuItem {
                objectName: "randomBattlefieldCardAction"
                text: qsTr("Random battlefield card")
                shortcutId: "table.randomBattlefield"
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
            text: qsTr("Declare draw")
            shortcutId: "table.declareDraw"
            enabled: root.tableController.canAct
            onTriggered: root.tableController.drawConfirmation.open()
        }
        AppMenuItem {
            objectName: "restartGameAction"
            text: qsTr("Restart game")
            shortcutId: "table.restartGame"
            enabled: root.tableController.canAct
                     && root.tableController.roomSession.host
            onTriggered: root.tableController.restartConfirmation.open()
        }
        ConditionalMenuItem {
            objectName: "concedeAction"
            visible: !root.tableController.isPlaytest
            text: qsTr("Concede")
            shortcutId: "table.concede"
            enabled: !root.tableController.gameFinished
                     && !root.tableController.ownEliminated
                     && !root.tableController.gameSession.sideboarding
            onTriggered: root.tableController.concedeConfirmation.open()
        }
    }

    AppMenu {
        id: handAreaMenu
        objectName: "handAreaMenu"

        AppMenuItem {
            objectName: "manageHandCardsAction"
            text: qsTr("Select and move hand cards…")
            enabled: root.tableController.canAct
                     && root.tableController.projectionSync.visibleOwnHandCount() > 0
            onTriggered: root.tableController.publicZoneBrowser.showZone(
                             root.tableController.ownSeatData.displayName || "",
                             root.tableController.roomSession.seatIndex, "hand")
        }
        AppMenuItem {
            objectName: "revealHandAction"
            text: root.tableController.ownRevealedCards.length > 0
                  ? qsTr("Recall hand")
                  : qsTr("Reveal hand")
            shortcutId: "table.toggleHandReveal"
            enabled: root.tableController.canAct
                     && (root.tableController.projectionSync.visibleOwnHandCount() > 0
                         || root.tableController.ownRevealedCards.length > 0)
                     && !root.tableController.zoneState.handRevealTransitionPending()
            onTriggered: root.tableController.cardActions.toggleHandReveal()
        }
        AppMenuSeparator { }
        AppMenuItem {
            objectName: "discardRandomHandCardAction"
            text: qsTr("Discard a random card")
            shortcutId: "table.discardRandom"
            enabled: root.tableController.canAct
                     && root.tableController.projectionSync.visibleOwnHandCount() > 0
            onTriggered: root.tableController.wsModel.discardHand(false)
        }
        AppMenuItem {
            objectName: "discardEntireHandAction"
            text: qsTr("Discard entire hand…")
            shortcutId: "table.discardAll"
            enabled: root.tableController.canAct
                     && root.tableController.projectionSync.visibleOwnHandCount() > 0
            onTriggered: root.discardHandConfirmation.open()
        }
        AppMenuSeparator { }
        AppMenuItem {
            objectName: "mulliganAction"
            text: qsTr("Mulligan")
            shortcutId: "table.mulligan"
            enabled: root.tableController.canAct
                     && root.tableController.authoritativeSeats.length > 0
            onTriggered: root.tableController.mulliganConfirmation.open()
        }
    }

    AppMenu {
        id: handCardMenu
        objectName: "handCardMenu"

        AppMenuItem {
            objectName: "playLandAction"
            text: qsTr("Play land…")
            shortcutId: "table.selection.playLand"
            enabled: root.tableController.isActivePlayer
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered: root.tableController.landPlay.requestSelectedHandCard()
        }
        AppMenuSeparator { }
        AppMenuItem {
            text: qsTr("Move to battlefield")
            shortcutId: "table.selection.battlefieldFaceUp"
            enabled: root.tableController.canAct
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedHandCard("battlefield")
        }
        AppMenuItem {
            text: qsTr("Move to battlefield face down")
            shortcutId: "table.selection.battlefieldFaceDown"
            enabled: root.tableController.canAct
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered: root.tableController.cardMoveCommands.moveSelectedHandCard(
                             "battlefield", true)
        }
        AppMenuItem {
            text: qsTr("Move to graveyard")
            shortcutId: "table.selection.moveGraveyard"
            enabled: root.tableController.canAct
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedHandCard("graveyard")
        }
        AppMenuItem {
            text: qsTr("Move to exile")
            shortcutId: "table.selection.moveExile"
            enabled: root.tableController.canAct
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered:
                root.tableController.cardMoveCommands.moveSelectedHandCard("exile")
        }
        AppMenuSeparator { }
        AppMenuItem {
            text: qsTr("Move to top of library")
            shortcutId: "table.selection.moveLibraryTop"
            enabled: root.tableController.canAct
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered: root.tableController.cardMoveCommands.moveSelectedHandToLibrary(
                             "top", -1)
        }
        AppMenuItem {
            text: qsTr("Move to library position…")
            enabled: root.tableController.canAct
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered: root.handLibraryPositionEditorPopup.showFor(
                             root.tableController.selectedHandCard.name)
        }
        AppMenuItem {
            text: qsTr("Move to bottom of library")
            shortcutId: "table.selection.moveLibraryBottom"
            enabled: root.tableController.canAct
                     && !!root.tableController.selectedHandCard
                     && !!root.tableController.selectedHandCard.id
            onTriggered: root.tableController.cardMoveCommands.moveSelectedHandToLibrary(
                             "bottom", -1)
        }
    }
}
