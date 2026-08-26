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
    required property var shortcutHelp
    readonly property var tableRoot: shortcutState.tableRoot

    ConfigurableShortcut {
        actionId: "table.help"
        context: Qt.WindowShortcut
        available: !root.tableRoot.sessionUi.counterShortcutBlocked()
                 || root.shortcutHelp.opened
        onActivated: {
            if (root.shortcutHelp.opened)
                root.shortcutHelp.close()
            else
                root.shortcutHelp.open()
        }
    }

    ConfigurableShortcut {
        actionId: "table.advancePhase"
        context: Qt.WindowShortcut
        available: root.shortcutState.canAdvanceTurn()
        onActivated: root.tableRoot.rulesAssist.requestAdvancePhase()
    }

    ConfigurableShortcut {
        actionId: "table.advanceTurn"
        context: Qt.WindowShortcut
        available: root.shortcutState.canAdvanceTurn()
        onActivated: root.tableRoot.rulesAssist.requestAdvanceTurn()
    }

    ConfigurableShortcut {
        actionId: "table.openSettings"
        context: Qt.WindowShortcut
        available: !root.shortcutState.blocked()
        onActivated: root.tableRoot.sessionUi.openTableSettings()
    }

    ConfigurableShortcut {
        actionId: "table.toggleGameLog"
        context: Qt.WindowShortcut
        available: !root.shortcutState.blocked()
        onActivated: root.tableRoot.sessionUi.setGameLogRailVisible(
                         !root.tableRoot.showGameLogRail)
    }

    ConfigurableShortcut {
        actionId: "table.toggleShared"
        context: Qt.WindowShortcut
        available: !root.shortcutState.blocked()
        onActivated: root.tableRoot.sessionUi.setSharedColumnVisible(
                         !root.tableRoot.showSharedColumn)
    }

    ConfigurableShortcut {
        actionId: "table.counter.rename"
        context: Qt.WindowShortcut
        available: root.shortcutState.canEditSelectedCounter()
        onActivated: root.tableRoot.sessionUi.openSelectedCounterLabelEditor()
    }

    ConfigurableShortcut {
        actionId: "table.counter.set"
        context: Qt.WindowShortcut
        available: root.shortcutState.canEditSelectedCounter()
        onActivated: root.tableRoot.sessionUi.openSelectedCounterValueEditor()
    }

    ConfigurableShortcut {
        actionId: "table.counter.decrease"
        context: Qt.WindowShortcut
        available: root.shortcutState.canEditSelectedCounter()
        onActivated: root.shortcutState.adjustSelectedPlayerCounter(-1)
    }

    ConfigurableShortcut {
        actionId: "table.counter.increase"
        context: Qt.WindowShortcut
        available: root.shortcutState.canEditSelectedCounter()
        onActivated: root.shortcutState.adjustSelectedPlayerCounter(1)
    }
}
