// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "Table"

import QtQuick
import QtQuick.Layouts

Surface {
    id: root

    required property var tableController

    objectName: "handSurface"
    Layout.fillWidth: true
    Layout.preferredHeight: tableController.handAreaHeight
    color: Theme.tableHandFill
    radius: 0
    border.width: 0

    Rectangle {
        visible: Theme.useGlass
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: Theme.playmatStitch
        z: 8
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        enabled: root.tableController.canAct
                 && !root.tableController.tableModalOpen
        onTapped: function(point) {
            const position = root.mapToItem(
                root.tableController, point.position.x, point.position.y)
            const handItem = handViewLoader.item as HandView
            if (handItem
                    && handItem.cardAtTablePoint(position.x, position.y)) {
                return
            }
            root.tableController.handAreaMenu.x = position.x
            root.tableController.handAreaMenu.y = position.y
            root.tableController.handAreaMenu.open()
        }
    }

    Loader {
        id: handViewLoader
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right:
            root.tableController.roomSession.role === "player"
            ? ownZoneDock.left : parent.right
        sourceComponent:
            root.tableController.roomSession.role === "player"
            ? playerHandComponent
            : root.tableController.roomSession.role === "spectator"
              ? spectatorHandComponent : null
    }

    Component {
        id: playerHandComponent

        HandView {
            anchors.fill: parent
            tableController: root.tableController
            cardMenu: root.tableController.handCardMenu
        }
    }

    Component {
        id: spectatorHandComponent

        SpectatorHandView {
            anchors.fill: parent
            visible:
                root.tableController.roomSession.spectatorsSeeHands === true
            tableController: root.tableController
        }
    }

    Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        visible: root.tableController.roomSession.role === "spectator"
                 && root.tableController.roomSession.spectatorsSeeHands !== true
        text: qsTranslate("Table", "Hands are hidden from spectators in this room")
        color: Theme.textMuted
        font.pixelSize: Theme.fontSize(12)
    }

    TableOwnZoneDock {
        id: ownZoneDock
        visible: root.tableController.roomSession.role === "player"
        tableController: root.tableController
    }
}
