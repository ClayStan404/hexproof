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
    color: Theme.surfaceMuted
    radius: 0
    border.width: 0

    TapHandler {
        acceptedButtons: Qt.RightButton
        enabled: root.tableController.canAct
                 && !root.tableController.tableModalOpen
        onTapped: function(point) {
            const position = root.mapToItem(
                root.tableController, point.position.x, point.position.y)
            if (handView.cardAtTablePoint(position.x, position.y))
                return
            root.tableController.handAreaMenu.x = position.x
            root.tableController.handAreaMenu.y = position.y
            root.tableController.handAreaMenu.open()
        }
    }

    HandView {
        id: handView
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: ownZoneDock.left
        visible: root.tableController.roomSession.role === "player"
        tableController: root.tableController
        cardMenu: root.tableController.handCardMenu
    }

    SpectatorHandView {
        anchors.fill: parent
        visible: root.tableController.roomSession.role === "spectator"
                 && root.tableController.roomSession.spectatorsSeeHands === true
        tableController: root.tableController
    }

    Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        visible: root.tableController.roomSession.role === "spectator"
                 && root.tableController.roomSession.spectatorsSeeHands !== true
        text: qsTr("Hands are hidden from spectators in this room")
        color: Theme.textMuted
        font.pixelSize: Theme.fontSize(12)
    }

    TableOwnZoneDock {
        id: ownZoneDock
        visible: root.tableController.roomSession.role === "player"
        tableController: root.tableController
    }
}
