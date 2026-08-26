// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root
    visible: false
    width: 0
    height: 0

    required property var shortcutState
    readonly property var tableRoot: shortcutState.tableRoot

    ConfigurableShortcut {
        actionId: "table.selection.playLand"
        context: Qt.WindowShortcut
        available: !root.shortcutState.blocked()
                 && root.shortcutState.selectionDomain() === "hand"
                 && root.tableRoot.isActivePlayer
        onActivated: root.tableRoot.landPlay.requestSelectedHandCard()
    }

    ConfigurableShortcut {
        actionId: "table.selection.battlefieldFaceUp"
        context: Qt.WindowShortcut
        available: root.shortcutState.selectionDomain() === "hand"
                 && root.shortcutState.canUseSelection()
        onActivated: root.shortcutState.moveSelection("battlefield")
    }

    ConfigurableShortcut {
        actionId: "table.selection.battlefieldFaceDown"
        context: Qt.WindowShortcut
        available: root.shortcutState.selectionDomain() === "hand"
                 && root.shortcutState.canUseSelection()
        onActivated: root.tableRoot.cardMoveCommands.moveSelectedHandCard(
                         "battlefield", true)
    }

    ConfigurableShortcut {
        actionId: "table.selection.moveHand"
        context: Qt.WindowShortcut
        available: root.shortcutState.canMoveSelection("hand")
        onActivated: root.shortcutState.moveSelection("hand")
    }

    ConfigurableShortcut {
        actionId: "table.selection.moveGraveyard"
        context: Qt.WindowShortcut
        available: root.shortcutState.canMoveSelection("graveyard")
        onActivated: root.shortcutState.moveSelection("graveyard")
    }

    ConfigurableShortcut {
        actionId: "table.selection.moveExile"
        context: Qt.WindowShortcut
        available: root.shortcutState.canMoveSelection("exile")
        onActivated: root.shortcutState.moveSelection("exile")
    }

    ConfigurableShortcut {
        actionId: "table.selection.moveLibraryTop"
        context: Qt.WindowShortcut
        available: root.shortcutState.canMoveSelection("library-top")
        onActivated: root.shortcutState.moveSelection("library-top")
    }

    ConfigurableShortcut {
        actionId: "table.selection.moveLibraryBottom"
        context: Qt.WindowShortcut
        available: root.shortcutState.canMoveSelection("library-bottom")
        onActivated: root.shortcutState.moveSelection("library-bottom")
    }

    ConfigurableShortcut {
        actionId: "table.selection.randomLibraryTop"
        context: Qt.WindowShortcut
        available: root.shortcutState.selectionDomain() === "battlefield"
                 && root.shortcutState.selectedBattlefieldCount() > 1
                 && root.shortcutState.canUseSelection()
        onActivated: root.shortcutState.moveSelection("library-top", true)
    }

    ConfigurableShortcut {
        actionId: "table.selection.randomLibraryBottom"
        context: Qt.WindowShortcut
        available: root.shortcutState.selectionDomain() === "battlefield"
                 && root.shortcutState.selectedBattlefieldCount() > 1
                 && root.shortcutState.canUseSelection()
        onActivated: root.shortcutState.moveSelection("library-bottom", true)
    }

    ConfigurableShortcut {
        actionId: "table.selection.toggleTap"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseBattlefieldSources()
        onActivated: root.shortcutState.toggleSelectedPermanents()
    }

    ConfigurableShortcut {
        actionId: "table.selection.toggleFaceDown"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseSingleBattlefieldCard()
        onActivated: root.shortcutState.toggleSelectedFaceDown()
    }

    ConfigurableShortcut {
        actionId: "table.selection.chooseFace"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseSingleBattlefieldCard()
                 && root.tableRoot.selectedBattlefieldFaces.length > 1
        onActivated:
            root.tableRoot.cardMoveCommands.requestBattlefieldFaceSelection()
    }

    ConfigurableShortcut {
        actionId: "table.selection.attach"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseSingleBattlefieldCard()
                 && root.tableRoot.attachmentUi.canAttachSelected()
        onActivated: root.tableRoot.attachmentUi.beginAttach()
    }

    ConfigurableShortcut {
        actionId: "table.selection.detach"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseSingleBattlefieldCard()
                 && root.tableRoot.attachmentUi.canDetachSelected()
        onActivated: root.tableRoot.attachmentUi.detachSelected()
    }

    ConfigurableShortcut {
        actionId: "table.selection.target"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseBattlefieldSources()
        onActivated: root.tableRoot.selection.beginRelationTarget("arrow")
    }

    ConfigurableShortcut {
        actionId: "table.selection.clearTarget"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseBattlefieldSources()
                 && root.shortcutState.selectedHasArrow(["target"])
        onActivated: root.shortcutState.clearSelectedArrows(["target"])
    }

    ConfigurableShortcut {
        actionId: "table.selection.attack"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseBattlefieldSources()
                 && root.tableRoot.isActivePlayer
                 && root.tableRoot.gameSession.currentPhase
                    === "declare_attackers"
        onActivated: root.tableRoot.selection.beginRelationTarget("attack")
    }

    ConfigurableShortcut {
        actionId: "table.selection.block"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseBattlefieldSources()
                 && root.tableRoot.gameSession.currentPhase
                    === "declare_blockers"
                 && root.shortcutState.hasIncomingAttacker()
        onActivated: root.tableRoot.selection.beginRelationTarget("block")
    }

    ConfigurableShortcut {
        actionId: "table.selection.clearCombat"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseBattlefieldSources()
                 && root.shortcutState.selectedHasArrow(["attack", "block"])
        onActivated:
            root.shortcutState.clearSelectedArrows(["attack", "block"])
    }

    ConfigurableShortcut {
        actionId: "table.selection.addNumberCounter"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseSingleBattlefieldCard()
        onActivated: root.tableRoot.cardActions.addNumberCounter()
    }

    ConfigurableShortcut {
        actionId: "table.selection.numberCounterDecrease"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseSingleBattlefieldCard()
                 && root.tableRoot.cardActions.numberCounterValue(
                     root.tableRoot.selectedBattlefieldCard.counters
                     ? root.tableRoot.selectedBattlefieldCard.counters : []) > 0
        onActivated: root.tableRoot.cardActions.adjustNumberCounter(-1)
    }

    ConfigurableShortcut {
        actionId: "table.selection.numberCounterIncrease"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseSingleBattlefieldCard()
        onActivated: root.tableRoot.cardActions.adjustNumberCounter(1)
    }

    ConfigurableShortcut {
        actionId: "table.selection.addAbilityCounter"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseSingleBattlefieldCard()
        onActivated: root.tableRoot.cardCounterEditor.showNewAbility(
                         root.tableRoot.selectedBattlefieldCard.name)
    }

    ConfigurableShortcut {
        actionId: "table.selection.setNumberCounter"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseSingleBattlefieldCard()
        onActivated: root.tableRoot.cardCounterEditor.showNumber(
                         root.tableRoot.selectedBattlefieldCard.name,
                         root.tableRoot.cardActions.numberCounterValue(
                             root.tableRoot.selectedBattlefieldCard.counters
                             ? root.tableRoot.selectedBattlefieldCard.counters
                             : []))
    }

    ConfigurableShortcut {
        actionId: "table.selection.createTokenCopy"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseSingleBattlefieldSelection()
        onActivated: root.tableRoot.cardActions.createSelectedTokenCopy()
    }
}
