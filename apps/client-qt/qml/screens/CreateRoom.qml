// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root

    readonly property var appWindow: ApplicationWindow.window
    readonly property var formatOptions: [
        {"label": I18n.formatLabel("custom"), "value": "custom", "tableMode": "modern"},
        {"label": I18n.formatLabel("standard"), "value": "standard", "tableMode": "modern"},
        {"label": I18n.formatLabel("pioneer"), "value": "pioneer", "tableMode": "modern"},
        {"label": I18n.formatLabel("modern"), "value": "modern", "tableMode": "modern"},
        {"label": I18n.formatLabel("legacy"), "value": "legacy", "tableMode": "modern"},
        {"label": I18n.formatLabel("vintage"), "value": "vintage", "tableMode": "modern"},
        {"label": I18n.formatLabel("pauper"), "value": "pauper", "tableMode": "modern"},
        {"label": I18n.formatLabel("duel"), "value": "duel", "tableMode": "duel"},
        {"label": I18n.formatLabel("commander"), "value": "commander", "tableMode": "edh"}
    ]

    property bool playtestMode: false
    property string roomName: ""
    property string roomFormat: "modern"
    property string deckFormat: "custom"
    property bool allowSpectators: true
    property string matchMode: "bo1"
    property string cardLoadMode: "preload"
    property string roomPassword: ""

    background: AppBackground { }

    ScreenHeader {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(22)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        title: root.playtestMode ? qsTr("Playtest") : qsTr("Create room")
        subtitle: root.playtestMode
                  ? qsTr("Practice alone on a full tabletop")
                  : qsTr("Set the table, then share its room code")
        onBackRequested: root.appWindow.popScreen()
    }

    ScrollView {
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(14)
        anchors.bottomMargin: Theme.size(24)
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Surface {
            width: Math.min(Theme.size(650), parent.width - Theme.size(72))
            height: form.implicitHeight + Theme.size(60)
            anchors.horizontalCenter: parent.horizontalCenter
            elevated: true

            ColumnLayout {
                id: form
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.size(30)
                spacing: Theme.size(10)

                RowLayout {
                    Layout.fillWidth: true

                    ColumnLayout {
                        spacing: Theme.size(3)
                        Text {
                            textFormat: Text.PlainText
                            text: root.playtestMode
                                  ? qsTr("Solo tabletop")
                                  : qsTr("New tabletop")
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(26)
                            font.weight: Font.DemiBold
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: root.playtestMode
                                  ? qsTr("Choose a format, then select any ready deck.")
                                  : qsTr("You will enter as the host in seat one.")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSize(13)
                        }
                    }

                    Item { Layout.fillWidth: true }

                    StatusPill {
                        text: root.playtestMode
                              ? qsTr("One player")
                              : qsTr("Connected")
                        statusColor: Theme.success
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.topMargin: Theme.size(16)
                    visible: !root.playtestMode
                    text: qsTr("ROOM NAME")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                    font.weight: Font.Bold
                    font.letterSpacing: 1.1
                }

                AppTextField {
                    id: nameField
                    Layout.fillWidth: true
                    visible: !root.playtestMode
                    placeholderText: qsTr("Friday game night")
                    maximumLength: 80
                    text: root.roomName
                    onTextEdited: root.roomName = text
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: !root.playtestMode
                    text: qsTr("Include the exact format in the room name so players know which card pool to bring.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(10)
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(10)
                    spacing: Theme.size(20)

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.size(8)

                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("FORMAT")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(11)
                            font.weight: Font.Bold
                            font.letterSpacing: 1.1
                        }

                        AppComboBox {
                            id: formatSelector
                            Layout.fillWidth: true
                            model: root.formatOptions
                            textRole: "label"
                            valueRole: "value"
                            currentIndex: 0
                            onActivated: index => {
                                root.deckFormat = root.formatOptions[index].value
                                root.roomFormat = root.formatOptions[index].tableMode
                                if (root.roomFormat === "edh")
                                    root.matchMode = "bo1"
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            visible: root.deckFormat === "custom"
                            text: qsTr("Custom 1v1 keeps manual deck construction and card-pool decisions.")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            visible: root.roomFormat === "duel"
                            text: qsTr("A two-player commander table at 20 life with command zones and manual commander tax.")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            visible: root.roomFormat === "edh"
                            text: qsTr("A four-seat Commander table that can start with three or four players.")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                            wrapMode: Text.WordWrap
                        }
                    }

                    ColumnLayout {
                        Layout.preferredWidth: Theme.size(170)
                        visible: !root.playtestMode
                        spacing: Theme.size(8)

                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("MATCH")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(11)
                            font.weight: Font.Bold
                            font.letterSpacing: 1.1
                        }

                        SegmentedControl {
                            Layout.fillWidth: true
                            options: root.roomFormat === "edh"
                                     ? [qsTr("BO 1")]
                                     : [qsTr("BO 1"),
                                        qsTr("BO 3")]
                            currentIndex: root.matchMode === "bo3" ? 1 : 0
                            onActivated: index => root.matchMode = index === 1 ? "bo3" : "bo1"
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            visible: root.roomFormat === "edh"
                            text: qsTr("Commander is a single multiplayer game.")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                InfoBanner {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(8)
                    visible: root.playtestMode
                    tone: "success"
                    message: qsTr("Playtest uses one private seat with no opponent or spectators. Commander-free 1v1 and Duel Commander start at 20 life; commander formats include a command zone.")
                }

                Surface {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(12)
                    visible: !root.playtestMode
                    implicitHeight: Theme.size(64)
                    radius: Theme.radiusMedium
                    color: Theme.surfaceMuted

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.size(16)
                        anchors.rightMargin: Theme.size(14)

                        ColumnLayout {
                            spacing: Theme.size(2)
                            Text {
                                textFormat: Text.PlainText
                                text: qsTr("Allow spectators")
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(14)
                                font.weight: Font.Medium
                            }
                            Text {
                                textFormat: Text.PlainText
                                text: qsTr("Up to eight people can watch public information.")
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSize(11)
                            }
                        }

                        Item { Layout.fillWidth: true }

                        AppToggle {
                            checked: root.allowSpectators
                            onToggled: root.allowSpectators = checked
                        }
                    }
                }

                Surface {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(4)
                    implicitHeight: cardLoadingColumn.implicitHeight + Theme.size(28)
                    radius: Theme.radiusMedium
                    color: Theme.surfaceMuted

                    ColumnLayout {
                        id: cardLoadingColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.size(14)
                        spacing: Theme.size(8)

                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("CARD IMAGES")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                            font.weight: Font.Bold
                            font.letterSpacing: 1.0
                        }

                        SegmentedControl {
                            Layout.fillWidth: true
                            options: [qsTr("Preload before game"),
                                      qsTr("Load in background")]
                            currentIndex: root.cardLoadMode === "background" ? 1 : 0
                            onActivated: index => root.cardLoadMode =
                                                         index === 1 ? "background" : "preload"
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: root.cardLoadMode === "background"
                                  ? qsTr("Enter immediately. Visible cards load first while the rest download in the background.")
                                  : qsTr("Wait until every player has downloaded all match card images.")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.topMargin: Theme.size(10)
                    visible: !root.playtestMode
                    text: qsTr("ROOM PASSWORD · OPTIONAL")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                    font.weight: Font.Bold
                    font.letterSpacing: 1.1
                }

                AppTextField {
                    id: passwordField
                    Layout.fillWidth: true
                    visible: !root.playtestMode
                    placeholderText: qsTr("Leave blank for code-only access")
                    echoMode: TextInput.Password
                    maximumLength: 72
                    maximumUtf8Bytes: 72
                    text: root.roomPassword
                    onTextEdited: root.roomPassword = text
                    onAccepted: root.submit()
                }

                InfoBanner {
                    id: errorBanner
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(4)
                }

                Text {
                    textFormat: Text.PlainText
                    objectName: "createRoomBlockerText"
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.createBlockerReason()
                    color: Theme.warning
                    font.pixelSize: Theme.fontSize(12)
                    horizontalAlignment: Text.AlignRight
                    wrapMode: Text.WordWrap
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
                        variant: "primary"
                        text: root.playtestMode
                              ? qsTr("Create playtest")
                              : qsTr("Create room")
                        leadingText: root.playtestMode ? "▶" : "+"
                        enabled: root.playtestMode
                                 || (root.roomName.trim().length > 0
                                     && passwordField.withinUtf8ByteLimit)
                        disabledReason: root.createBlockerReason()
                        onClicked: root.submit()
                    }
                }
            }
        }
    }

    function submit() {
        if (!playtestMode && roomName.trim().length === 0)
            return
        if (!playtestMode && !passwordField.withinUtf8ByteLimit) {
            errorBanner.message =
                qsTr("Password cannot exceed 72 UTF-8 bytes.")
            return
        }
        errorBanner.message = ""
        const submittedName = playtestMode
                              ? qsTr("Solo playtest")
                              : roomName.trim()
        ws.createRoom(submittedName, roomFormat, deckFormat,
                      playtestMode ? false : allowSpectators,
                      playtestMode ? "bo1" : matchMode,
                      cardLoadMode,
                      playtestMode ? "" : roomPassword,
                      playtestMode)
    }

    function createBlockerReason() {
        if (root.playtestMode)
            return ""
        if (root.roomName.trim().length === 0)
            return qsTr("Enter a room name")
        if (!passwordField.withinUtf8ByteLimit)
            return qsTr("Password cannot exceed 72 UTF-8 bytes.")
        return ""
    }

    Connections {
        target: ws
        function onLastErrorChanged() {
            if (!ws.inRoom)
                errorBanner.message = I18n.status(ws.lastError)
        }
    }
}
