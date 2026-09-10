// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "TournamentLobby"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Surface {
    id: root
    required property var tournamentModel
    required property var wsModel
    property string caption: qsTranslate("TournamentLobby", "Event chat · visible to everyone in this event")
    property string placeholderText: qsTranslate("TournamentLobby", "Message this event…")
    readonly property string inputTournamentId: tournamentModel.tournamentId
    onInputTournamentIdChanged: input.clear()
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(12)
        spacing: Theme.size(8)
        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.caption
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize(11)
            wrapMode: Text.WordWrap
        }
        ListView {
            id: messages
            objectName: "tournamentChatMessages"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.size(10)
            property bool followEnd: true
            model: root.tournamentModel.chatMessages
            ScrollBar.vertical: ScrollBar { }
            onMovementEnded: followEnd = atYEnd
            onCountChanged: if (followEnd) Qt.callLater(positionViewAtEnd)
            onContentHeightChanged: if (followEnd) Qt.callLater(positionViewAtEnd)
            delegate: Column {
                id: row
                required property var modelData
                width: ListView.view.width
                spacing: Theme.size(3)
                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: row.modelData.displayName
                    color: Theme.accent
                    font.pixelSize: Theme.fontSize(11)
                    elide: Text.ElideRight
                }
                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: row.modelData.text
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(13)
                    wrapMode: Text.Wrap
                }
            }
        }
        AppTextField {
            id: input
            objectName: "tournamentChatInput"
            Layout.fillWidth: true
            placeholderText: root.placeholderText
            maximumLength: 500
            enabled: root.wsModel.connected
            onAccepted: root.submit()
        }
        AppButton {
            objectName: "tournamentChatSendButton"
            Layout.fillWidth: true
            text: qsTranslate("TournamentLobby", "Send")
            variant: "primary"
            enabled: root.wsModel.connected && input.text.trim().length > 0
            onClicked: root.submit()
        }
    }
    function submit() {
        if (root.wsModel.connected && input.text.trim().length > 0
                && root.wsModel.sendTournamentChat(input.text))
            input.clear()
    }
    Connections {
        target: root.tournamentModel
        function onChatChanged() {
            if (messages.followEnd)
                Qt.callLater(messages.positionViewAtEnd)
        }
        function onInTournamentChanged() { input.clear() }
    }
}
