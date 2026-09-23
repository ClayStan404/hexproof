// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: root

    required property var tableController
    required property var drawCardsEditorPopup
    required property var publicZoneBrowserPopup
    required property var libraryTopCountEditorPopup

    readonly property alias ownLibraryMenu: ownLibraryMenu
    readonly property alias opponentLibraryMenu: opponentLibraryMenu

    AppMenu {
        id: ownLibraryMenu

        AppMenuItem {
            id: drawCardsMenuItem
            objectName: "drawCardsAction"
            text: qsTr("Draw X cards")
            shortcutId: "table.library.drawX"
            enabled: root.tableController.ownSeatData.libraryCount > 0
            onTriggered: root.drawCardsEditorPopup.showFor(2)
        }
        AppMenuItem {
            id: shuffleLibraryMenuItem
            objectName: "shuffleLibraryAction"
            text: qsTr("Shuffle")
            shortcutId: "table.library.shuffle"
            onTriggered: root.tableController.shuffleConfirmation.open()
        }
        AppMenuSeparator { }
        AppMenuItem {
            id: searchLibraryMenuItem
            text: qsTr("Search library")
            shortcutId: "table.library.search"
            enabled: root.tableController.ownSeatData.libraryCount > 0
            onTriggered: root.tableController.wsModel.dumpLibrary(
                             root.tableController.roomSession.seatIndex)
        }
        AppMenuItem {
            id: viewSideboardMenuItem
            objectName: "viewSideboardAction"
            text: qsTr("View sideboard")
            shortcutId: "table.sideboard.view"
            extra: String(root.tableController.ownSeatData.sideboardCount
                          ? root.tableController.ownSeatData.sideboardCount : 0)
            enabled: root.tableController.canAct
                     && root.tableController.ownSeatData.sideboardCount > 0
            onTriggered: root.publicZoneBrowserPopup.showZone(
                             root.tableController.ownSeatData.displayName,
                             root.tableController.roomSession.seatIndex,
                             "sideboard")
        }
        AppMenuSeparator { }
        AppMenuItem {
            objectName: "revealLibraryTopContinuouslyAction"
            text: checked ? qsTr("Stop revealing library top")
                          : qsTr("Play with library top revealed")
            checkable: true
            checked: root.tableController.ownSeatData.libraryTopRevealed === true
            enabled: root.tableController.canAct
            onTriggered: root.tableController.wsModel.setLibraryTopRevealed(
                             !root.tableController.ownSeatData.libraryTopRevealed)
        }
        AppMenuItem {
            id: viewTopCardMenuItem
            objectName: "viewLibraryTopCardAction"
            text: qsTr("View top card")
            shortcutId: "table.library.viewTop"
            enabled: root.tableController.ownSeatData.libraryCount > 0
            onTriggered: root.tableController.wsModel.dumpLibrary(
                             root.tableController.roomSession.seatIndex, 1)
        }
        AppMenuItem {
            id: viewTopCardsMenuItem
            objectName: "viewLibraryTopCardsAction"
            text: qsTr("View top X cards…")
            shortcutId: "table.library.viewTopX"
            enabled: root.tableController.ownSeatData.libraryCount > 0
            onTriggered: root.libraryTopCountEditorPopup.showForLibrary(
                             root.tableController.roomSession.seatIndex,
                             root.tableController.ownSeatData.libraryCount,
                             Math.min(5,
                                      root.tableController.ownSeatData.libraryCount))
        }
        AppMenuItem {
            id: moveTopToGraveyardMenuItem
            objectName: "moveLibraryTopToGraveyardAction"
            text: qsTr("Put top X cards into graveyard…")
            shortcutId: "table.library.millX"
            enabled: root.tableController.ownSeatData.libraryCount > 0
            onTriggered:
                root.tableController.sessionUi.showLibraryMoveCardsEditor("graveyard")
        }
        AppMenuItem {
            id: moveTopToExileMenuItem
            objectName: "moveLibraryTopToExileAction"
            text: qsTr("Put top X cards into exile…")
            shortcutId: "table.library.exileX"
            enabled: root.tableController.ownSeatData.libraryCount > 0
            onTriggered:
                root.tableController.sessionUi.showLibraryMoveCardsEditor("exile")
        }
        AppMenuItem {
            id: exileTopFaceDownMenuItem
            objectName: "exileLibraryTopFaceDownAction"
            text: qsTr("Exile top card face down (no player may look)")
            enabled: root.tableController.canAct
                     && root.tableController.ownSeatData.libraryCount > 0
            onTriggered: root.tableController.cardMoveCommands.exileLibraryTopFaceDown()
        }
    }

    AppMenu {
        id: opponentLibraryMenu
        objectName: "opponentLibraryMenu"
        property int sourceSeat: -1
        property int sourceLibraryCount: 0

        AppMenuItem {
            objectName: "opponentLibrarySearchAction"
            text: qsTr("Search library")
            enabled: root.tableController.canAct
                     && opponentLibraryMenu.sourceSeat >= 0
                     && opponentLibraryMenu.sourceLibraryCount > 0
            onTriggered: root.tableController.wsModel.dumpLibrary(
                             opponentLibraryMenu.sourceSeat)
        }
        AppMenuSeparator { }
        AppMenuItem {
            objectName: "opponentLibraryViewTopCardAction"
            text: qsTr("View top card")
            enabled: root.tableController.canAct
                     && opponentLibraryMenu.sourceSeat >= 0
                     && opponentLibraryMenu.sourceLibraryCount > 0
            onTriggered: root.tableController.wsModel.dumpLibrary(
                             opponentLibraryMenu.sourceSeat, 1)
        }
        AppMenuItem {
            objectName: "opponentLibraryViewTopCardsAction"
            text: qsTr("View top X cards…")
            enabled: root.tableController.canAct
                     && opponentLibraryMenu.sourceSeat >= 0
                     && opponentLibraryMenu.sourceLibraryCount > 0
            onTriggered: root.libraryTopCountEditorPopup.showForLibrary(
                             opponentLibraryMenu.sourceSeat,
                             opponentLibraryMenu.sourceLibraryCount,
                             Math.min(5,
                                      opponentLibraryMenu.sourceLibraryCount))
        }
    }
}
