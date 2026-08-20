// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root

    required property var replayPayload
    readonly property var replay: replayPayload.replay
                                  ? replayPayload.replay : ({})
    readonly property var logEntries: replayPayload.log
                                      ? replayPayload.log : []
    property int visibleCount: logEntries.length > 0 ? 1 : 0
    property bool playing: false
    property real playbackSpeed: 1
    readonly property var speedOptions: [0.5, 1, 2, 4]
    readonly property var appWindow: ApplicationWindow.window

    background: AppBackground { }

    Timer {
        id: playbackTimer
        interval: Math.max(80, Math.round(700 / Math.max(0.25, root.playbackSpeed)))
        repeat: true
        running: root.playing
        onTriggered: {
            if (root.visibleCount >= root.logEntries.length) {
                root.playing = false
                return
            }
            root.visibleCount += 1
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Theme.size(22)
        anchors.bottomMargin: Theme.size(28)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        spacing: Theme.size(16)

        ScreenHeader {
            Layout.fillWidth: true
            title: root.replay.roomName
                   ? root.replay.roomName : qsTr("Replay")
            subtitle: qsTr("Public activity playback · no hidden card identities")
            onBackRequested: root.appWindow.popScreen()
        }

        Surface {
            Layout.fillWidth: true
            implicitHeight: Theme.size(82)
            color: Theme.surfaceElevated

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.size(16)
                spacing: Theme.size(18)
                ColumnLayout {
                    Layout.fillWidth: true
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: I18n.playersLabel(root.replay.players)
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(15)
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: root.metadataLabel()
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(11)
                        elide: Text.ElideRight
                    }
                }
                StatusPill {
                    text: root.visibleCount + " / " + root.logEntries.length
                    statusColor: Theme.accent
                }
            }
        }

        Surface {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.surfaceMuted

            ListView {
                id: replayLog
                objectName: "replayLog"
                anchors.fill: parent
                anchors.margins: Theme.size(18)
                model: root.logEntries.slice(0, root.visibleCount)
                spacing: Theme.size(10)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                onCountChanged: Qt.callLater(function() {
                    if (replayLog.count > 0)
                        replayLog.positionViewAtEnd()
                })

                delegate: Surface {
                    id: logRow
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: logText.implicitHeight + Theme.size(24)
                    color: Theme.surfaceElevated

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.size(12)
                        spacing: Theme.size(12)
                        Text {
                            textFormat: Text.PlainText
                            text: (logRow.index < 9 ? "0" : "")
                                  + String(logRow.index + 1)
                            color: Theme.primary
                            font.pixelSize: Theme.fontSize(11)
                            font.weight: Font.Bold
                        }
                        Text {
                            textFormat: Text.PlainText
                            id: logText
                            Layout.fillWidth: true
                            text: I18n.status(logRow.modelData.text)
                            color: logRow.modelData.kind === "chat"
                                   ? Theme.text : Theme.textSecondary
                            font.pixelSize: Theme.fontSize(13)
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(8)
            AppButton {
                compact: true
                text: qsTr("Reset")
                enabled: root.visibleCount > 1
                onClicked: {
                    root.playing = false
                    root.visibleCount = root.logEntries.length > 0 ? 1 : 0
                }
            }
            AppButton {
                compact: true
                text: qsTr("Previous")
                enabled: root.visibleCount > 1
                onClicked: {
                    root.playing = false
                    root.visibleCount -= 1
                }
            }
            Item { Layout.fillWidth: true }
            Repeater {
                model: root.speedOptions
                delegate: AppButton {
                    required property real modelData
                    objectName: "replaySpeed" + String(modelData).replace(".", "_")
                    compact: true
                    variant: root.playbackSpeed === modelData ? "primary" : "ghost"
                    text: modelData + "×"
                    onClicked: root.playbackSpeed = modelData
                }
            }
            AppButton {
                objectName: "replayPlayButton"
                compact: true
                variant: "primary"
                text: root.playing ? qsTr("Pause") : qsTr("Play")
                enabled: root.logEntries.length > 0
                         && (root.visibleCount < root.logEntries.length
                             || root.playing)
                onClicked: root.playing = !root.playing
            }
            AppButton {
                compact: true
                text: qsTr("Next")
                enabled: root.visibleCount < root.logEntries.length
                onClicked: {
                    root.playing = false
                    root.visibleCount += 1
                }
            }
        }
    }

    Shortcut {
        sequence: "Space"
        context: Qt.WindowShortcut
        enabled: root.logEntries.length > 0
        onActivated: {
            if (root.visibleCount >= root.logEntries.length && !root.playing)
                return
            root.playing = !root.playing
        }
    }
    Shortcut {
        sequence: "Left"
        context: Qt.WindowShortcut
        enabled: root.visibleCount > 1
        onActivated: {
            root.playing = false
            root.visibleCount -= 1
        }
    }
    Shortcut {
        sequence: "Right"
        context: Qt.WindowShortcut
        enabled: root.visibleCount < root.logEntries.length
        onActivated: {
            root.playing = false
            root.visibleCount += 1
        }
    }
    Shortcut {
        sequence: "Home"
        context: Qt.WindowShortcut
        enabled: root.visibleCount > 1
        onActivated: {
            root.playing = false
            root.visibleCount = root.logEntries.length > 0 ? 1 : 0
        }
    }
    Shortcut {
        sequence: "1"
        context: Qt.WindowShortcut
        onActivated: root.playbackSpeed = 0.5
    }
    Shortcut {
        sequence: "2"
        context: Qt.WindowShortcut
        onActivated: root.playbackSpeed = 1
    }
    Shortcut {
        sequence: "3"
        context: Qt.WindowShortcut
        onActivated: root.playbackSpeed = 2
    }
    Shortcut {
        sequence: "4"
        context: Qt.WindowShortcut
        onActivated: root.playbackSpeed = 4
    }

    function metadataLabel() {
        const game = qsTr("Game") + " " + Math.max(1, replay.gameNumber || 1)
        return I18n.formatLabel(replay.deckFormat || replay.format) + " · " + game
    }
}
