// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "LibrarySearchPopup"

import QtQuick
import QtQuick.Controls.Basic

Menu {
    id: root

    required property var popupController
    objectName: "libraryCardMenu"

    MenuItem {
        objectName: "libraryContextLocalHand"
        text: root.popupController.localDisplayName + " · " + qsTr("Hand")
        onTriggered: root.popupController.completeContextSearch("hand", root.popupController.localSeat, false)
    }
    MenuItem {
        objectName: "libraryContextLocalBattlefieldFaceDown"
        text: root.popupController.localDisplayName + " · " + qsTr("Battlefield face down")
        onTriggered: root.popupController.completeContextSearch("battlefield", root.popupController.localSeat, false, true)
    }
    MenuItem {
        objectName: "libraryContextLocalBattlefield"
        text: root.popupController.localDisplayName + " · " + qsTr("Battlefield")
        onTriggered: root.popupController.completeContextSearch("battlefield", root.popupController.localSeat, false)
    }
    MenuItem {
        objectName: "libraryContextLocalGraveyard"
        text: root.popupController.localDisplayName + " · " + qsTr("Graveyard")
        onTriggered: root.popupController.completeContextSearch("graveyard", root.popupController.localSeat, false)
    }
    MenuItem {
        objectName: "libraryContextLocalExile"
        text: root.popupController.localDisplayName + " · " + qsTr("Exile")
        onTriggered: root.popupController.completeContextSearch("exile", root.popupController.localSeat, false)
    }
    MenuSeparator {
        visible: root.popupController.remoteSource
    }
    MenuItem {
        objectName: "libraryContextSourceHand"
        visible: root.popupController.remoteSource
        text: root.popupController.sourceDisplayName + " · " + qsTr("Hand")
        onTriggered: root.popupController.completeContextSearch("hand", root.popupController.sourceSeat, false)
    }
    MenuItem {
        objectName: "libraryContextSourceBattlefield"
        visible: root.popupController.remoteSource
        text: root.popupController.sourceDisplayName + " · " + qsTr("Battlefield")
        onTriggered: root.popupController.completeContextSearch("battlefield", root.popupController.sourceSeat, false)
    }
    MenuItem {
        objectName: "libraryContextSourceGraveyard"
        visible: root.popupController.remoteSource
        text: root.popupController.sourceDisplayName + " · " + qsTr("Graveyard")
        onTriggered: root.popupController.completeContextSearch("graveyard", root.popupController.sourceSeat, false)
    }
    MenuItem {
        objectName: "libraryContextSourceExile"
        visible: root.popupController.remoteSource
        text: root.popupController.sourceDisplayName + " · " + qsTr("Exile")
        onTriggered: root.popupController.completeContextSearch("exile", root.popupController.sourceSeat, false)
    }
    MenuSeparator {
        visible: !root.popupController.topCardMode
    }
    MenuItem {
        objectName: "libraryContextSourceTopOrdered"
        visible: !root.popupController.topCardMode
        text: qsTr("Top of library · in order")
        onTriggered: root.popupController.completeContextSearch("library_top", root.popupController.sourceSeat, false)
    }
    MenuItem {
        objectName: "libraryContextSourceTopRandom"
        visible: !root.popupController.topCardMode
        text: qsTr("Top of library · random order")
        onTriggered: root.popupController.completeContextSearch("library_top", root.popupController.sourceSeat, true)
    }
    MenuItem {
        objectName: "libraryContextSourceBottomOrdered"
        visible: !root.popupController.topCardMode
        text: qsTr("Bottom of library · in order")
        onTriggered: root.popupController.completeContextSearch("library_bottom", root.popupController.sourceSeat, false)
    }
    MenuItem {
        objectName: "libraryContextSourceBottomRandom"
        visible: !root.popupController.topCardMode
        text: qsTr("Bottom of library · random order")
        onTriggered: root.popupController.completeContextSearch("library_bottom", root.popupController.sourceSeat, true)
    }
}
