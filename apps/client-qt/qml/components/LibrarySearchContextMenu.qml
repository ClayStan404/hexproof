// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "LibrarySearchPopup"

import QtQuick

AppMenu {
    id: root

    required property var popupController
    objectName: "libraryCardMenu"

    ConditionalMenuItem {
        visible: root.popupController.reorderMode
        enabled: false
        text: qsTr("Assign cards") + " · " + root.popupController.contextCardIdList().length
    }
    ConditionalMenuSeparator { visible: root.popupController.reorderMode }

    AppMenuItem {
        objectName: "libraryContextLocalHand"
        text: root.popupController.localDisplayName + " · " + qsTranslate("LibrarySearchPopup", "Hand")
        onTriggered: root.popupController.completeContextSearch("hand", root.popupController.localSeat, false)
    }
    AppMenuItem {
        objectName: "libraryContextLocalBattlefieldFaceDown"
        text: root.popupController.localDisplayName + " · " + qsTranslate("LibrarySearchPopup", "Battlefield face down")
        onTriggered: root.popupController.completeContextSearch("battlefield", root.popupController.localSeat, false, true)
    }
    AppMenuItem {
        objectName: "libraryContextLocalBattlefield"
        text: root.popupController.localDisplayName + " · " + qsTranslate("LibrarySearchPopup", "Battlefield")
        onTriggered: root.popupController.completeContextSearch("battlefield", root.popupController.localSeat, false)
    }
    AppMenuItem {
        objectName: "libraryContextLocalGraveyard"
        text: (root.popupController.reorderMode ? root.popupController.sourceDisplayName
                                               : root.popupController.localDisplayName)
              + " · " + qsTranslate("LibrarySearchPopup", "Graveyard")
        onTriggered: root.popupController.completeContextSearch("graveyard", root.popupController.localSeat, false)
    }
    AppMenuItem {
        objectName: "libraryContextLocalExile"
        text: (root.popupController.reorderMode ? root.popupController.sourceDisplayName
                                               : root.popupController.localDisplayName)
              + " · " + qsTranslate("LibrarySearchPopup", "Exile")
        onTriggered: root.popupController.completeContextSearch("exile", root.popupController.localSeat, false)
    }
    ConditionalMenuSeparator {
        visible: root.popupController.remoteSource && !root.popupController.reorderMode
    }
    ConditionalMenuItem {
        objectName: "libraryContextSourceHand"
        visible: root.popupController.remoteSource && !root.popupController.reorderMode
        text: root.popupController.sourceDisplayName + " · " + qsTranslate("LibrarySearchPopup", "Hand")
        onTriggered: root.popupController.completeContextSearch("hand", root.popupController.sourceSeat, false)
    }
    ConditionalMenuItem {
        objectName: "libraryContextSourceBattlefield"
        visible: root.popupController.remoteSource && !root.popupController.reorderMode
        text: root.popupController.sourceDisplayName + " · " + qsTranslate("LibrarySearchPopup", "Battlefield")
        onTriggered: root.popupController.completeContextSearch("battlefield", root.popupController.sourceSeat, false)
    }
    ConditionalMenuItem {
        objectName: "libraryContextSourceGraveyard"
        visible: root.popupController.remoteSource && !root.popupController.reorderMode
        text: root.popupController.sourceDisplayName + " · " + qsTranslate("LibrarySearchPopup", "Graveyard")
        onTriggered: root.popupController.completeContextSearch("graveyard", root.popupController.sourceSeat, false)
    }
    ConditionalMenuItem {
        objectName: "libraryContextSourceExile"
        visible: root.popupController.remoteSource && !root.popupController.reorderMode
        text: root.popupController.sourceDisplayName + " · " + qsTranslate("LibrarySearchPopup", "Exile")
        onTriggered: root.popupController.completeContextSearch("exile", root.popupController.sourceSeat, false)
    }
    AppMenuSeparator { }
    AppMenuItem {
        objectName: "libraryContextSourceTopOrdered"
        text: qsTranslate("LibrarySearchPopup", "Top of library · in order")
        onTriggered: root.popupController.completeContextSearch("library_top", root.popupController.sourceSeat, false)
    }
    ConditionalMenuItem {
        objectName: "libraryContextSourceTopRandom"
        visible: !root.popupController.topCardMode
        text: qsTranslate("LibrarySearchPopup", "Top of library · random order")
        onTriggered: root.popupController.completeContextSearch("library_top", root.popupController.sourceSeat, true)
    }
    AppMenuItem {
        objectName: "libraryContextSourceBottomOrdered"
        text: qsTranslate("LibrarySearchPopup", "Bottom of library · in order")
        onTriggered: root.popupController.completeContextSearch("library_bottom", root.popupController.sourceSeat, false)
    }
    ConditionalMenuItem {
        objectName: "libraryContextSourceBottomRandom"
        visible: !root.popupController.topCardMode
        text: qsTranslate("LibrarySearchPopup", "Bottom of library · random order")
        onTriggered: root.popupController.completeContextSearch("library_bottom", root.popupController.sourceSeat, true)
    }
    ConditionalMenuSeparator { visible: root.popupController.reorderMode }
    ConditionalMenuItem {
        visible: root.popupController.reorderMode
        text: qsTr("Use remainder destination")
        onTriggered: root.popupController.useRemainderForTopCards(
                         root.popupController.contextCardIdList())
    }
}
