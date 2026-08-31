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
    required property var gameLogModel
    property alias chatInput: chatInputField

    objectName: "gameLogRail"
    Layout.minimumWidth: root.tableController.gameLogRailWidth
    Layout.preferredWidth: root.tableController.gameLogRailWidth
    Layout.maximumWidth: root.tableController.gameLogRailWidth
    Layout.fillHeight: true
    visible: root.tableController.showGameLogRail
    color: Theme.surfaceMuted
    radius: 0
    border.width: 0

    Rectangle {
        objectName: "gameLogColumnDivider"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: Theme.size(2)
        color: Theme.borderStrong
        z: 20
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(6)
        spacing: Theme.size(5)

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.size(44)
            text: qsTr("Game log")
            color: Theme.text
            font.pixelSize: Theme.fontSize(13)
            font.weight: Font.DemiBold
            verticalAlignment: Text.AlignVCenter
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.border
        }
        ListView {
            id: gameLogList
            objectName: "gameLog"
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: root.gameLogModel
            spacing: Theme.size(7)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {
                objectName: "gameLogScrollBar"
                policy: ScrollBar.AsNeeded
                interactive: true
            }
            onCountChanged: Qt.callLater(function() {
                if (gameLogList)
                    gameLogList.positionViewAtEnd()
            })

            delegate: Text {
                textFormat: Text.PlainText
                required property string entryText
                required property string entryKind
                width: ListView.view.width
                text: I18n.status(entryText)
                color: entryKind === "chat"
                       ? Theme.text : Theme.textSecondary
                font.pixelSize: Theme.fontSize(10)
                font.weight: entryKind === "chat"
                             ? Font.Medium : Font.Normal
                wrapMode: Text.WordWrap
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(5)

            TextField {
                id: chatInputField
                objectName: "gameChatInput"
                Layout.fillWidth: true
                implicitHeight: Theme.size(36)
                enabled: root.tableController.canChat
                maximumLength: 500
                placeholderText: qsTr("Message…")
                selectByMouse: true
                font.pixelSize: Theme.fontSize(10)
                onAccepted: root.tableController.cardActions.submitChatMessage()
            }
            AppButton {
                objectName: "sendGameChatButton"
                compact: true
                implicitWidth: Theme.size(54)
                implicitHeight: Theme.size(36)
                leftPadding: Theme.size(5)
                rightPadding: Theme.size(5)
                text: qsTr("Send")
                enabled: root.tableController.canChat
                         && chatInputField.text.trim().length > 0
                onClicked: root.tableController.cardActions.submitChatMessage()
            }
        }
    }
}
