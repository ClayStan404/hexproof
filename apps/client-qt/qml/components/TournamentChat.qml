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
    readonly property var sourceMessages: tournamentModel.chatMessages
    onInputTournamentIdChanged: {
        input.clear()
        messages.followEnd = true
        chatModel.clear()
        synchronizeMessages()
    }
    onSourceMessagesChanged: synchronizeMessages()
    Component.onCompleted: synchronizeMessages()

    ListModel { id: chatModel }

    function followLatestMessage() {
        if (messages.followEnd) messages.positionViewAtEnd()
    }

    function synchronizeMessages() {
        if (!chatModel || !sourceMessages) return
        // Keep retained delegates and their scroll anchors when the bounded
        // server history replaces its QVariantList after each incoming message.
        for (let index = 0; index < sourceMessages.length; ++index) {
            const message = sourceMessages[index]
            const entry = {sequence: Number(message.sequence),
                           displayName: String(message.displayName),
                           messageText: String(message.text)}
            while (index < chatModel.count
                    && chatModel.get(index).sequence < entry.sequence)
                chatModel.remove(index)
            if (index >= chatModel.count)
                chatModel.append(entry)
            else if (chatModel.get(index).sequence === entry.sequence) {
                const current = chatModel.get(index)
                if (current.displayName !== entry.displayName || current.messageText !== entry.messageText)
                    chatModel.set(index, entry)
            } else
                chatModel.insert(index, entry)
        }
        if (chatModel.count > sourceMessages.length)
            chatModel.remove(sourceMessages.length, chatModel.count - sourceMessages.length)
        if (messages.followEnd) Qt.callLater(root.followLatestMessage)
    }
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
            model: chatModel
            ScrollBar.vertical: ScrollBar {
                objectName: "tournamentChatScrollBar"
                onPressedChanged: messages.followEnd = !pressed && messages.atYEnd
            }
            onMovementStarted: followEnd = false
            onMovementEnded: followEnd = atYEnd
            onCountChanged: if (followEnd) Qt.callLater(root.followLatestMessage)
            onContentHeightChanged: if (followEnd) Qt.callLater(root.followLatestMessage)
            delegate: Column {
                id: row
                required property string displayName
                required property string messageText
                width: ListView.view.width
                spacing: Theme.size(3)
                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: row.displayName
                    color: Theme.accent
                    font.pixelSize: Theme.fontSize(11)
                    elide: Text.ElideRight
                }
                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: row.messageText
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
        function onInTournamentChanged() { input.clear() }
    }
}
