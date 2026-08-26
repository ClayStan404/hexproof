// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: root

    required property var tableController
    required property var drawCardsEditorPopup
    required property var publicZoneBrowserPopup
    required property var libraryTopCountEditorPopup
    required property var tokenPickerPopup
    required property var handLibraryPositionEditorPopup
    required property var cardCounterEditorPopup
    required property var libraryPositionEditorPopup
    required property var discardHandConfirmation

    readonly property alias ownLibraryMenu: libraryMenus.ownLibraryMenu
    readonly property alias opponentLibraryMenu: libraryMenus.opponentLibraryMenu
    readonly property alias battlefieldAreaMenu: areaMenus.battlefieldAreaMenu
    readonly property alias handAreaMenu: areaMenus.handAreaMenu
    readonly property alias handCardMenu: areaMenus.handCardMenu
    readonly property alias cardToolsMenu: cardToolsMenu

    TableLibraryMenus {
        id: libraryMenus
        anchors.fill: parent
        tableController: root.tableController
        drawCardsEditorPopup: root.drawCardsEditorPopup
        publicZoneBrowserPopup: root.publicZoneBrowserPopup
        libraryTopCountEditorPopup: root.libraryTopCountEditorPopup
    }

    TableAreaMenus {
        id: areaMenus
        anchors.fill: parent
        tableController: root.tableController
        tokenPickerPopup: root.tokenPickerPopup
        handLibraryPositionEditorPopup: root.handLibraryPositionEditorPopup
        discardHandConfirmation: root.discardHandConfirmation
    }

    TableCardToolsMenu {
        id: cardToolsMenu
        tableController: root.tableController
        cardCounterEditorPopup: root.cardCounterEditorPopup
        libraryPositionEditorPopup: root.libraryPositionEditorPopup
    }
}
