// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root

    readonly property var appWindow: ApplicationWindow.window

    property string roomCode: ""
    property bool asSpectator: false
    property string roomPassword: ""
    property string hostingMode: ""
    property var wsModel: ws

    background: AppBackground { }

    ScreenHeader {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(22)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        title: qsTr("Join room")
        subtitle: qsTr("Enter the six-character code shared by the host")
        onBackRequested: root.appWindow.popScreen()
    }

    Flickable {
        id: formBody
        objectName: "joinRoomBody"
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(14)
        anchors.bottomMargin: Theme.size(28)
        contentWidth: width
        contentHeight: Math.max(height, formCard.height)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Surface {
            id: formCard
            width: Math.min(Theme.size(600), formBody.width - Theme.size(72))
            height: joinForm.implicitHeight + Theme.size(64)
            x: Math.round((formBody.width - width) / 2)
            y: Math.max(0, Math.round((formBody.height - height) / 2))
            elevated: true

            ColumnLayout {
                id: joinForm
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.size(32)
                spacing: Theme.size(10)

                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Find your table")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(28)
                    font.weight: Font.DemiBold
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    Layout.bottomMargin: Theme.size(16)
                    text: qsTr("Join by code or select a room from this hub. No account required.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(14)
                    wrapMode: Text.WordWrap
                }

                Text {
                    textFormat: Text.PlainText
                    text: qsTr("ROOM CODE")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                    font.weight: Font.Bold
                    font.letterSpacing: 1.1
                }

                AppTextField {
                    id: roomCodeField
                    objectName: "joinRoomCodeField"
                    Layout.fillWidth: true
                    implicitHeight: Theme.size(60)
                    placeholderText: "ABC123"
                    text: root.roomCode
                    maximumLength: 16
                    horizontalAlignment: TextInput.AlignHCenter
                    font.pixelSize: Theme.fontSize(22)
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    inputMethodHints: Qt.ImhUppercaseOnly | Qt.ImhNoPredictiveText
                    onTextEdited: root.roomCode = text.toUpperCase()
                    onAccepted: root.submit()
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.topMargin: Theme.size(12)
                    text: qsTr("JOIN AS")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                    font.weight: Font.Bold
                    font.letterSpacing: 1.1
                }

                SegmentedControl {
                    Layout.fillWidth: true
                    options: [qsTr("Player"), qsTr("Spectator")]
                    currentIndex: root.asSpectator ? 1 : 0
                    onActivated: index => root.asSpectator = index === 1
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.topMargin: Theme.size(12)
                    text: qsTr("PASSWORD · OPTIONAL")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                    font.weight: Font.Bold
                    font.letterSpacing: 1.1
                }

                AppTextField {
                    id: passwordField
                    Layout.fillWidth: true
                    placeholderText: qsTr("Only needed for protected rooms")
                    echoMode: TextInput.Password
                    maximumLength: 72
                    maximumUtf8Bytes: 72
                    text: root.roomPassword
                    onTextEdited: root.roomPassword = text
                    onAccepted: root.submit()
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.hostingMode === "player"
                    textFormat: Text.PlainText
                    text: qsTr("Player-hosted Forge: the creator runs the rules engine and can access hidden cards or change its behavior. Use this mode with people you trust.")
                    color: Theme.warning
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSize(12)
                }
                AppToggle {
                    id: trustHost
                    objectName: "trustPlayerHost"
                    Layout.fillWidth: true
                    visible: root.hostingMode === "player"
                    text: qsTr("I trust this host")
                }
                InfoBanner {
                    id: errorBanner
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(4)
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(12)
                    spacing: Theme.size(10)

                    AppButton {
                        variant: "ghost"
                        text: qsTr("Cancel")
                        onClicked: root.appWindow.popScreen()
                    }

                    Item { Layout.fillWidth: true }

                    AppButton {
                        objectName: "joinRoomSubmitButton"
                        variant: "primary"
                        text: root.asSpectator ? qsTr("Watch room") : qsTr("Join table")
                        leadingText: "→"
                        enabled: root.roomCode.trim().length > 0
                                 && passwordField.withinUtf8ByteLimit
                                 && (root.hostingMode !== "player" || trustHost.checked)
                        onClicked: root.submit()
                    }
                }
            }
        }
    }

    function submit() {
        if (hostingMode === "player" && !trustHost.checked) return
        if (roomCode.trim().length === 0)
            return
        if (!passwordField.withinUtf8ByteLimit) {
            errorBanner.message =
                qsTr("Password cannot exceed 72 UTF-8 bytes.")
            return
        }
        errorBanner.message = ""
        root.wsModel.joinRoom(roomCode.trim().toUpperCase(), asSpectator, roomPassword, trustHost.checked)
    }

    Connections {
        target: root.wsModel
        function onLastErrorChanged() {
            if (String(root.wsModel.lastError).indexOf("player_host_trust_required:") === 0)
                root.hostingMode = "player"
            if (!root.wsModel.inRoom)
                errorBanner.message = I18n.status(root.wsModel.lastError)
        }
    }
}
