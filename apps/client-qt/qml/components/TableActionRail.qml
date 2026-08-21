// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "Table"

import QtQuick
import QtQuick.Layouts

Surface {
    id: root

    required property var tableController
    required property var leaveRoomConfirmation

    objectName: "tableActionRail"
    Layout.minimumWidth: root.tableController.actionRailWidth
    Layout.preferredWidth: root.tableController.actionRailWidth
    Layout.maximumWidth: root.tableController.actionRailWidth
    Layout.fillHeight: true
    color: Theme.surfaceMuted
    radius: 0
    border.width: 0

    Rectangle {
        objectName: "primaryColumnDivider"
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Theme.size(2)
        color: Theme.borderStrong
        z: 20
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(3)
        spacing: Theme.size(2)

        Text {
            textFormat: Text.PlainText
            objectName: "tableRoomName"
            Layout.fillWidth: true
            text: root.tableController.roomSession.roomName
            color: Theme.text
            font.pixelSize: Theme.fontSize(10)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            textFormat: Text.PlainText
            objectName: "tableRoomCode"
            Layout.fillWidth: true
            visible: !root.tableController.isPlaytest
            text: qsTr("ROOM CODE") + " · "
                  + root.tableController.roomSession.roomId
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(9)
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
        Text {
            textFormat: Text.PlainText
            objectName: "tableGameNumber"
            Layout.fillWidth: true
            text: root.tableController.sessionUi.gameSummary()
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(9)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
        Text {
            textFormat: Text.PlainText
            objectName: "startingPlayerSummary"
            Layout.fillWidth: true
            visible: root.tableController.gameSession.startingSeat >= 0
            text: {
                const seat = root.tableController.seatState.seatData(
                                 root.tableController.gameSession.startingSeat)
                const name = seat.displayName ? seat.displayName
                                             : qsTr("Seat %1").arg(
                                                   root.tableController
                                                   .gameSession.startingSeat + 1)
                return qsTr("First player · %1").arg(name)
            }
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(9)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
        Text {
            textFormat: Text.PlainText
            objectName: "tableMatchScore"
            Layout.fillWidth: true
            visible: root.tableController.roomSession.matchMode === "bo3"
                     && root.tableController.gameSession.score.length >= 2
            text: root.tableController.sessionUi.matchScoreSummary()
            color: Theme.text
            font.pixelSize: Theme.fontSize(15)
            font.weight: Font.Bold
            horizontalAlignment: Text.AlignHCenter
        }
        AppButton {
            objectName: "tableSettingsButton"
            Layout.fillWidth: true
            compact: true
            variant: "secondary"
            text: "⚙ " + qsTr("Settings")
            onClicked: root.tableController.sessionUi.openTableSettings()
        }
        AppButton {
            objectName: "tableShortcutHelpButton"
            Layout.fillWidth: true
            compact: true
            variant: "ghost"
            text: root.tableController.compactLayout
                  ? "?" : "? " + qsTr("Shortcuts")
            onClicked: root.tableController.shortcutHelp.open()
        }
        AppButton {
            objectName: "commanderDamageButton"
            Layout.fillWidth: true
            compact: true
            variant: "secondary"
            visible: root.tableController.isCommanderFormat
            text: qsTr("Commander damage")
            onClicked: root.tableController.commanderDamagePopup.open()
        }
        AppButton {
            objectName: "returnToRoomButton"
            Layout.fillWidth: true
            compact: true
            variant: "primary"
            text: qsTr("Return to room")
            visible: root.tableController.gameFinished
                     && root.tableController.gameSession.result.matchFinished === true
                     && !root.tableController.gameSession.sideboarding
            enabled: visible
            onClicked: root.tableController.wsModel.returnToRoom()
        }
        AppButton {
            objectName: "leaveRoomButton"
            Layout.fillWidth: true
            compact: true
            variant: "secondary"
            text: root.tableController.isPlaytest
                  ? qsTr("End playtest")
                  : qsTr("Leave room")
            onClicked: root.leaveRoomConfirmation.open()
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.borderStrong
        }

        TableTurnBar {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.tableController.gameSession.sideboarding
                     && !root.tableController.gameFinished
            tableController: root.tableController
        }
    }
}
