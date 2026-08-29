// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root

    readonly property var appWindow: ApplicationWindow.window

    background: AppBackground { }
    Component.onCompleted: ws.requestReplayList()

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Theme.size(22)
        anchors.bottomMargin: Theme.size(28)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        spacing: Theme.size(16)

        ScreenHeader {
            Layout.fillWidth: true
            title: qsTr("Retained replays")
            subtitle: qsTr("Replay the public table log; hidden cards stay private")
            onBackRequested: root.appWindow.popScreen()
        }

        RowLayout {
            Layout.fillWidth: true
            Text {
                textFormat: Text.PlainText
                text: qsTr("Saved on this hub for up to seven days")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(13)
            }
            Item { Layout.fillWidth: true }
            AppButton {
                objectName: "refreshReplayListButton"
                compact: true
                text: qsTr("Refresh")
                leadingText: "↻"
                onClicked: ws.requestReplayList()
            }
        }

        Surface {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.surfaceMuted

            ColumnLayout {
                anchors.centerIn: parent
                visible: ws.replayList.length === 0
                spacing: Theme.size(10)

                Text {
                    textFormat: Text.PlainText
                    text: qsTr("No retained games are available.")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(16)
                    font.weight: Font.DemiBold
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Only unexpired public logs from this hub appear here.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(12)
                    Layout.alignment: Qt.AlignHCenter
                }
                AppButton {
                    Layout.alignment: Qt.AlignHCenter
                    variant: "primary"
                    text: qsTr("Refresh")
                    leadingText: "↻"
                    onClicked: ws.requestReplayList()
                }
            }

            ListView {
                objectName: "replayList"
                anchors.fill: parent
                anchors.margins: Theme.size(14)
                model: ws.replayList
                spacing: Theme.size(10)
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                delegate: Surface {
                    id: replayRow
                    required property var modelData
                    width: ListView.view.width
                    height: Theme.size(104)
                    color: Theme.surfaceElevated
                    interactive: true

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.size(16)
                        spacing: Theme.size(14)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.size(5)
                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: replayRow.modelData.roomName
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(16)
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: I18n.playersLabel(replayRow.modelData.players)
                                      + " · "
                                      + I18n.formatLabel(replayRow.modelData.deckFormat
                                                         || replayRow.modelData.format)
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSize(12)
                                elide: Text.ElideRight
                            }
                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: root.savedLabel(replayRow.modelData.savedAt)
                                      + " · "
                                      + replayRow.modelData.logEntryCount + " "
                                      + qsTr("events")
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSize(11)
                                elide: Text.ElideRight
                            }
                        }

                        AppButton {
                            compact: true
                            variant: "primary"
                            text: qsTr("Open replay")
                            onClicked: ws.loadReplay(replayRow.modelData.replayId)
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: ws.replayTotal > ws.replayList.length || ws.replayOffset > 0

            AppButton {
                compact: true
                text: qsTr("Previous")
                enabled: ws.replayOffset > 0
                onClicked: ws.requestReplayPage(Math.max(0, ws.replayOffset - ws.replayLimit))
            }
            Item { Layout.fillWidth: true }
            Text {
                textFormat: Text.PlainText
                text: qsTr("%1–%2 of %3")
                          .arg(ws.replayTotal === 0 ? 0 : ws.replayOffset + 1)
                          .arg(Math.min(ws.replayOffset + ws.replayList.length,
                                        ws.replayTotal))
                          .arg(ws.replayTotal)
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
            }
            Item { Layout.fillWidth: true }
            AppButton {
                compact: true
                text: qsTr("Next")
                enabled: ws.replayHasMore
                onClicked: ws.requestReplayPage(ws.replayOffset + ws.replayList.length)
            }
        }
    }

    Connections {
        target: ws
        function onReplayLoaded() {
            root.appWindow.pushScreen("screens/ReplayViewer.qml", {
                "replayPayload": ws.loadedReplay
            })
        }
        function onLastErrorChanged() {
            if (ws.lastError && ws.lastError.length > 0)
                root.appWindow.showBanner(I18n.status(ws.lastError))
        }
    }

    function savedLabel(savedAt) {
        const date = new Date(savedAt)
        return isNaN(date.getTime()) ? savedAt : date.toLocaleString()
    }
}
