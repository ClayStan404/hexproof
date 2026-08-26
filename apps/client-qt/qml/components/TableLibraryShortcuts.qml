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
    required property var drawCardsEditor
    required property var libraryTopCountEditor
    required property var shuffleConfirmation
    readonly property var tableRoot: shortcutState.tableRoot

    ConfigurableShortcut {
        actionId: "table.library.drawX"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseLibrary()
        onActivated: root.drawCardsEditor.showFor(2)
    }

    ConfigurableShortcut {
        actionId: "table.library.drawOne"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseLibrary()
        onActivated: root.tableRoot.wsModel.drawCards(1)
    }

    ConfigurableShortcut {
        actionId: "table.library.search"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseLibrary()
        onActivated: root.tableRoot.wsModel.dumpLibrary(
                         root.tableRoot.roomSession.seatIndex)
    }

    ConfigurableShortcut {
        actionId: "table.library.viewTopX"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseLibrary()
        onActivated: root.libraryTopCountEditor.showForLibrary(
                         root.tableRoot.roomSession.seatIndex,
                         root.tableRoot.ownSeatData.libraryCount,
                         Math.min(5, root.tableRoot.ownSeatData.libraryCount))
    }

    ConfigurableShortcut {
        actionId: "table.library.viewTop"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseLibrary()
        onActivated: root.tableRoot.wsModel.dumpLibrary(
                         root.tableRoot.roomSession.seatIndex, 1)
    }

    ConfigurableShortcut {
        actionId: "table.sideboard.view"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseGameAction()
                 && root.tableRoot.ownSeatData.sideboardCount > 0
        onActivated: root.tableRoot.publicZoneBrowser.showZone(
                         root.tableRoot.ownSeatData.displayName,
                         root.tableRoot.roomSession.seatIndex, "sideboard")
    }

    ConfigurableShortcut {
        actionId: "table.library.millX"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseLibrary()
        onActivated:
            root.tableRoot.sessionUi.showLibraryMoveCardsEditor("graveyard")
    }

    ConfigurableShortcut {
        actionId: "table.library.exileX"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseLibrary()
        onActivated: root.tableRoot.sessionUi.showLibraryMoveCardsEditor("exile")
    }

    ConfigurableShortcut {
        actionId: "table.library.shuffle"
        context: Qt.WindowShortcut
        available: root.shortcutState.canUseGameAction()
        onActivated: root.shuffleConfirmation.open()
    }
}
