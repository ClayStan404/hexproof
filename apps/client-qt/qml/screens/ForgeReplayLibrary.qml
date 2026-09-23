// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import "../components"

Page {
    id: root
    property var service: ws.replays
    readonly property var appWindow: ApplicationWindow.window
    property bool openAfterDownload: false
    background: AppBackground { }
    function showReplay() {
        root.appWindow.pushScreen("screens/ForgeReplay.qml", {service: root.service})
    }
    Connections {
        target: root.service
        function onStatusChanged() {
            if (root.openAfterDownload && !root.service.busy) {
                root.openAfterDownload = false
                if (!root.service.error.length && root.service.count > 0) root.showReplay()
            }
        }
    }
    FileDialog {
        id: importDialog
        title: qsTr("Open Forge replay")
        nameFilters: [qsTr("Hexproof replay (*.hpr)")]
        onAccepted: if (root.service.importFile(selectedFile)) root.showReplay()
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pageMargin
        spacing: Theme.size(16)
        RowLayout {
            Layout.fillWidth: true
            AppButton { text: qsTr("Back"); onClicked: root.appWindow.popScreen() }
            Text {
                textFormat: Text.PlainText
                text: qsTr("Forge replays")
                color: Theme.text
                font.pixelSize: Theme.fontSize(24)
                Layout.fillWidth: true
            }
            AppButton { text: qsTr("Open file"); enabled: !root.service.busy; onClicked: importDialog.open() }
        }
        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("After the whole match ends, its players can download a replay with both hands. Downloaded replays work offline.")
            color: Theme.textSecondary
        }
        Text {
            textFormat: Text.PlainText
            visible: root.service.error.length > 0 || root.service.busy
            text: root.service.busy ? qsTr("Downloading replay…") : root.service.error
            color: Theme.textSecondary
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
        Text {
            textFormat: Text.PlainText
            visible: root.service.entries.length === 0
            text: qsTr("No recorded Forge matches yet.")
            color: Theme.textMuted
        }
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.size(10)
            model: root.service.entries
            ScrollBar.vertical: ScrollBar { }
            delegate: Surface {
                required property var modelData
                width: list.width
                height: row.implicitHeight + Theme.size(28)
                RowLayout {
                    id: row
                    anchors.fill: parent
                    anchors.margins: Theme.size(14)
                    ColumnLayout {
                        Layout.fillWidth: true
                        Text {
                            textFormat: Text.PlainText
                            text: modelData.roomName || qsTr("Forge match")
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(16)
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: (modelData.players || []).join(" · ") + " — "
                                + (modelData.local ? qsTr("Saved locally")
                                   : modelData.finished ? qsTr("Ready to download") : qsTr("Available after the match"))
                            color: Theme.textSecondary
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                    AppButton {
                        text: modelData.local ? qsTr("Watch") : qsTr("Download")
                        enabled: !root.service.busy
                        onClicked: {
                            if (modelData.local) {
                                if (root.service.open(modelData.replayId)) root.showReplay()
                            } else {
                                root.openAfterDownload = true
                                root.service.download(modelData.replayId)
                            }
                        }
                    }
                }
            }
        }
    }
}
