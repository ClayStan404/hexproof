// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic

Item {
    id: root

    required property var tableController
    required property var drawCardsEditorPopup
    required property var publicZoneBrowserPopup
    required property var libraryTopCountEditorPopup

    readonly property alias ownLibraryMenu: ownLibraryMenu
    readonly property alias opponentLibraryMenu: opponentLibraryMenu

    Menu {
        id: ownLibraryMenu
        readonly property real widestItemWidth: Math.max(
                                                    drawCardsMenuItem.implicitWidth,
                                                    shuffleLibraryMenuItem.implicitWidth,
                                                    searchLibraryMenuItem.implicitWidth,
                                                    viewSideboardMenuItem.implicitWidth,
                                                    viewTopCardMenuItem.implicitWidth,
                                                    viewTopCardsMenuItem.implicitWidth,
                                                    moveTopToGraveyardMenuItem.implicitWidth,
                                                    moveTopToExileMenuItem.implicitWidth)
        width: Math.min(root.width - Theme.size(24),
                        Math.max(Theme.size(420),
                                 widestItemWidth + leftPadding + rightPadding))

        MenuItem {
            id: drawCardsMenuItem
            objectName: "drawCardsAction"
            text: qsTr("Draw X cards") + " · Ctrl+D"
            enabled: root.tableController.ownSeatData.libraryCount > 0
            onTriggered: root.drawCardsEditorPopup.showFor(2)
        }
        MenuItem {
            id: shuffleLibraryMenuItem
            objectName: "shuffleLibraryAction"
            text: qsTr("Shuffle") + " · Ctrl+Shift+S"
            onTriggered: root.tableController.shuffleConfirmation.open()
        }
        MenuSeparator { }
        MenuItem {
            id: searchLibraryMenuItem
            text: qsTr("Search library") + " · Ctrl+F"
            enabled: root.tableController.ownSeatData.libraryCount > 0
            onTriggered: root.tableController.wsModel.dumpLibrary(
                             root.tableController.roomSession.seatIndex)
        }
        MenuItem {
            id: viewSideboardMenuItem
            objectName: "viewSideboardAction"
            text: qsTr("View sideboard") + " · Ctrl+B · "
                  + (root.tableController.ownSeatData.sideboardCount
                     ? root.tableController.ownSeatData.sideboardCount : 0)
            enabled: root.tableController.canAct
                     && root.tableController.ownSeatData.sideboardCount > 0
            onTriggered: root.publicZoneBrowserPopup.showZone(
                             root.tableController.ownSeatData.displayName,
                             root.tableController.roomSession.seatIndex,
                             "sideboard")
        }
        MenuSeparator { }
        MenuItem {
            id: viewTopCardMenuItem
            objectName: "viewLibraryTopCardAction"
            text: qsTr("View top card") + " · Ctrl+Shift+L"
            enabled: root.tableController.ownSeatData.libraryCount > 0
            onTriggered: root.tableController.wsModel.dumpLibrary(
                             root.tableController.roomSession.seatIndex, 1)
        }
        MenuItem {
            id: viewTopCardsMenuItem
            objectName: "viewLibraryTopCardsAction"
            text: qsTr("View top X cards…") + " · Ctrl+L"
            enabled: root.tableController.ownSeatData.libraryCount > 0
            onTriggered: root.libraryTopCountEditorPopup.showForLibrary(
                             root.tableController.roomSession.seatIndex,
                             root.tableController.ownSeatData.libraryCount,
                             Math.min(5,
                                      root.tableController.ownSeatData.libraryCount))
        }
        MenuItem {
            id: moveTopToGraveyardMenuItem
            objectName: "moveLibraryTopToGraveyardAction"
            text: qsTr("Put top X cards into graveyard…")
                  + " · Ctrl+Shift+G"
            enabled: root.tableController.ownSeatData.libraryCount > 0
            onTriggered:
                root.tableController.sessionUi.showLibraryMoveCardsEditor("graveyard")
        }
        MenuItem {
            id: moveTopToExileMenuItem
            objectName: "moveLibraryTopToExileAction"
            text: qsTr("Put top X cards into exile…")
                  + " · Ctrl+Shift+E"
            enabled: root.tableController.ownSeatData.libraryCount > 0
            onTriggered:
                root.tableController.sessionUi.showLibraryMoveCardsEditor("exile")
        }
    }

    Menu {
        id: opponentLibraryMenu
        objectName: "opponentLibraryMenu"
        property int sourceSeat: -1
        property int sourceLibraryCount: 0

        MenuItem {
            objectName: "opponentLibrarySearchAction"
            text: qsTr("Search library")
            enabled: root.tableController.canAct
                     && opponentLibraryMenu.sourceSeat >= 0
                     && opponentLibraryMenu.sourceLibraryCount > 0
            onTriggered: root.tableController.wsModel.dumpLibrary(
                             opponentLibraryMenu.sourceSeat)
        }
        MenuSeparator { }
        MenuItem {
            objectName: "opponentLibraryViewTopCardAction"
            text: qsTr("View top card")
            enabled: root.tableController.canAct
                     && opponentLibraryMenu.sourceSeat >= 0
                     && opponentLibraryMenu.sourceLibraryCount > 0
            onTriggered: root.tableController.wsModel.dumpLibrary(
                             opponentLibraryMenu.sourceSeat, 1)
        }
        MenuItem {
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
