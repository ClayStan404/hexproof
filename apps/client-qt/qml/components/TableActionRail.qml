// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "Table"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Surface {
    id: root

    required property var tableController
    required property var leaveRoomConfirmation
    readonly property bool compactNavigation: height < Theme.size(700)

    component NavigationButton: AppButton {
        Layout.fillWidth: true
        Layout.preferredWidth: root.compactNavigation ? Theme.size(26) : implicitWidth
        Layout.minimumWidth: 0
        compact: true
        implicitHeight: Theme.size(root.compactNavigation ? 30 : 38)
        leftPadding: Theme.size(root.compactNavigation ? 2 : 12)
        rightPadding: leftPadding
        ToolTip.visible: hovered
        ToolTip.text: accessibleName
    }

    objectName: "tableActionRail"
    Layout.minimumWidth: root.tableController.actionRailWidth
    Layout.preferredWidth: root.tableController.actionRailWidth
    Layout.maximumWidth: root.tableController.actionRailWidth
    Layout.fillHeight: true
    color: Theme.tableRailFill
    radius: 0
    border.width: 0

    Rectangle {
        objectName: "primaryColumnDivider"
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Theme.size(2)
        color: Theme.tableDivider
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
            text: qsTranslate("Table", "ROOM CODE") + " · "
                  + root.tableController.roomSession.roomId
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(9)
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
        Text {
            objectName: "tableServerTransport"
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: I18n.serverTransportLabel(root.tableController.wsModel.serverTransportState)
            visible: text.length > 0
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(9)
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
                                             : qsTranslate("Table", "Seat %1").arg(
                                                   root.tableController
                                                   .gameSession.startingSeat + 1)
                return qsTranslate("Table", "First player · %1").arg(name)
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
        GridLayout {
            Layout.fillWidth: true
            columns: root.compactNavigation ? 4 : 1
            columnSpacing: Theme.size(2)
            rowSpacing: Theme.size(2)

            NavigationButton {
                objectName: "tableSettingsButton"
                variant: "secondary"
                accessibleName: qsTranslate("Table", "Settings")
                text: root.compactNavigation ? "⚙" : "⚙ " + accessibleName
                onClicked: root.tableController.sessionUi.openTableSettings()
            }
            NavigationButton {
                objectName: "tableShortcutHelpButton"
                variant: "ghost"
                accessibleName: qsTranslate("Table", "Shortcuts")
                text: root.compactNavigation || root.tableController.compactLayout
                      ? "?" : "? " + qsTranslate("Table", "Shortcuts")
                onClicked: root.tableController.shortcutHelp.open()
            }
            NavigationButton {
                objectName: "restoreGameLogRailButton"
                visible: !root.tableController.showGameLogRail
                accessibleName: qsTranslate("Table", "Show game log")
                text: root.compactNavigation ? "☷" : accessibleName
                onClicked: root.tableController.sessionUi.setGameLogRailVisible(true)
            }
            NavigationButton {
                objectName: "leaveRoomButton"
                variant: "secondary"
                accessibleName: root.tableController.isPlaytest
                                ? qsTranslate("Table", "End playtest")
                                : qsTranslate("Table", "Leave room")
                text: root.compactNavigation ? "↩" : accessibleName
                onClicked: root.leaveRoomConfirmation.open()
            }
        }
        AppButton {
            id: commanderDamageControl
            objectName: "commanderDamageButton"
            Layout.fillWidth: true
            compact: true
            variant: "secondary"
            visible: root.tableController.isCommanderFormat
            text: qsTranslate("Table", "Commander damage")
            contentItem: Text {
                textFormat: Text.PlainText
                text: commanderDamageControl.text
                font: commanderDamageControl.font
                color: commanderDamageControl.foregroundColor
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            onClicked: root.tableController.commanderDamagePopup.open()
        }
        AppButton {
            objectName: "returnToRoomButton"
            Layout.fillWidth: true
            compact: true
            variant: "primary"
            text: qsTranslate("Table", "Return to room")
            visible: root.tableController.gameFinished
                     && root.tableController.gameSession.result.matchFinished === true
                     && !root.tableController.gameSession.sideboarding
            enabled: visible
            onClicked: root.tableController.wsModel.returnToRoom()
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
