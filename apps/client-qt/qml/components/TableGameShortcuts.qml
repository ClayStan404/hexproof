// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root
    visible: false
    width: 0
    height: 0

    required property var shortcutState
    required property var tokenPicker
    required property var mulliganConfirmation
    required property var concedeConfirmation
    readonly property var tableRoot: shortcutState.tableRoot

    ConfigurableShortcut {
        actionId: "table.untapAll"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseGameAction()
                 && root.tableRoot.gameValues.hasTappedOwnPermanent()
        onActivated: root.tableRoot.gameValues.untapOwnBattlefield()
    }

    ConfigurableShortcut {
        actionId: "table.arrangeBattlefield"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseGameAction()
                 && root.tableRoot.zoneState.zoneCardCount(
                     root.tableRoot.roomSession.seatIndex,
                     "battlefield") > 0
        onActivated: root.tableRoot.cardMoveCommands.arrangeOwnBattlefield()
    }

    ConfigurableShortcut {
        actionId: "table.createToken"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseGameAction()
        onActivated: root.tokenPicker.open()
    }

    ConfigurableShortcut {
        actionId: "table.mulligan"
        context: Qt.WindowShortcut
        available: root.shortcutState.canMulligan()
        onActivated: root.mulliganConfirmation.open()
    }

    ConfigurableShortcut {
        actionId: "table.toggleHandReveal"
        context: Qt.WindowShortcut
        available: root.shortcutState.canToggleHand()
        onActivated: root.tableRoot.cardActions.toggleHandReveal()
    }

    ConfigurableShortcut {
        actionId: "table.discardRandom"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseGameAction()
                 && root.tableRoot.projectionSync.visibleOwnHandCount() > 0
        onActivated: root.tableRoot.wsModel.discardHand(false)
    }

    ConfigurableShortcut {
        actionId: "table.discardAll"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseGameAction()
                 && root.tableRoot.projectionSync.visibleOwnHandCount() > 0
        onActivated: root.tableRoot.discardHandConfirmation.open()
    }

    ConfigurableShortcut {
        actionId: "table.rollDice"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseGameAction()
        onActivated: root.tableRoot.diceRollPopup.showFor(20, 1)
    }

    ConfigurableShortcut {
        actionId: "table.flipCoin"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseGameAction()
        onActivated: root.tableRoot.wsModel.flipCoin()
    }

    ConfigurableShortcut {
        actionId: "table.randomPlayer"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseGameAction()
        onActivated: root.tableRoot.wsModel.randomSelectPlayer()
    }

    ConfigurableShortcut {
        actionId: "table.randomBattlefield"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseGameAction()
                 && root.tableRoot.selection.allCardIds().length > 0
        onActivated: {
            const selected = Object.keys(root.tableRoot.selectedBattlefieldCardIds)
            root.tableRoot.wsModel.randomSelectCards(
                        selected.length > 1
                        ? selected : root.tableRoot.selection.allCardIds())
            root.tableRoot.selection.clear()
        }
    }

    ConfigurableShortcut {
        actionId: "table.declareDraw"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseGameAction()
                 && !root.tableRoot.isPlaytest
        onActivated: root.tableRoot.drawConfirmation.open()
    }

    ConfigurableShortcut {
        actionId: "table.restartGame"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseGameAction()
                 && root.tableRoot.roomSession.host
        onActivated: root.tableRoot.restartConfirmation.open()
    }

    ConfigurableShortcut {
        actionId: "table.setLife"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseGameAction()
                 && root.tableRoot.roomSession.seatIndex >= 0
        onActivated: root.tableRoot.lifeEditor.showFor(
                         root.tableRoot.ownSeatData.displayName,
                         root.tableRoot.gameValues.displayedLife(
                             root.tableRoot.ownSeatData))
    }

    ConfigurableShortcut {
        actionId: "table.life.decrease"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseGameAction()
        onActivated: root.shortcutState.adjustOwnLife(-1)
    }

    ConfigurableShortcut {
        actionId: "table.life.increase"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseGameAction()
        onActivated: root.shortcutState.adjustOwnLife(1)
    }

    ConfigurableShortcut {
        actionId: "table.commanderDamage"
        context: Qt.WindowShortcut
        available: !root.shortcutState.blocked()
                 && root.tableRoot.isCommanderFormat
        onActivated: root.tableRoot.commanderDamagePopup.open()
    }

    ConfigurableShortcut {
        actionId: "table.concede"
        context: Qt.WindowShortcut
        available: root.shortcutState.canConcede()
        onActivated: root.concedeConfirmation.open()
    }

    ConfigurableShortcut {
        actionId: "table.leave"
        context: Qt.WindowShortcut
        available: !root.shortcutState.blocked()
        onActivated: root.tableRoot.leaveRoomConfirmation.open()
    }

    ConfigurableShortcut {
        actionId: "table.returnToRoom"
        context: Qt.WindowShortcut
        available: !root.shortcutState.blocked() && root.tableRoot.gameFinished
                 && root.tableRoot.gameSession.result.matchFinished === true
                 && !root.tableRoot.gameSession.sideboarding
        onActivated: root.tableRoot.wsModel.returnToRoom()
    }
}
