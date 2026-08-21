// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root

    readonly property var appWindow: ApplicationWindow.window
    readonly property bool compactLayout: Theme.isCompactWidth(width)

    background: AppBackground { }

    RowLayout {
        id: topBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(26)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        spacing: Theme.size(12)

        BrandMark { markSize: Theme.size(36) }

        Text {
            textFormat: Text.PlainText
            text: "HEXPROOF"
            color: Theme.text
            font.pixelSize: Theme.fontSize(14)
            font.weight: Font.Bold
            font.letterSpacing: 2.2
        }

        Item { Layout.fillWidth: true }

        AppButton {
            variant: "ghost"
            compact: true
            text: qsTr("Settings")
            onClicked: root.appWindow.pushScreen("screens/Settings.qml")
        }

        StatusPill {
            text: ws.connected ? ws.displayName : qsTr("Offline")
            statusColor: ws.connected ? Theme.success : Theme.textMuted
        }

        AppButton {
            visible: ws.connected
            variant: "ghost"
            compact: true
            text: qsTr("Disconnect")
            onClicked: ws.disconnectFromHub()
        }
    }

    Flickable {
        id: menuBody
        objectName: "mainMenuBody"
        anchors.top: topBar.bottom
        anchors.bottom: footer.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(root.compactLayout ? 12 : 22)
        anchors.bottomMargin: Theme.size(18)
        anchors.leftMargin: root.compactLayout
                            ? Theme.pageMargin
                            : Math.max(Theme.size(48), root.width * 0.085)
        anchors.rightMargin: root.compactLayout
                             ? Theme.pageMargin
                             : Math.max(Theme.size(48), root.width * 0.085)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: Math.max(height, menuLayoutWrap.height)

        Item {
            id: menuLayoutWrap
            width: menuBody.width
            height: root.compactLayout ? menuLayout.implicitHeight : menuBody.height

            GridLayout {
                id: menuLayout
                objectName: "mainMenuLayout"
                anchors.fill: parent
                columns: root.compactLayout ? 1 : 2
                columnSpacing: Math.max(Theme.size(24), root.compactLayout ? 0 : root.width * 0.08)
                rowSpacing: Theme.size(18)

            ColumnLayout {
                objectName: "mainMenuHero"
                Layout.fillWidth: true
                Layout.fillHeight: !root.compactLayout
                Layout.maximumWidth: root.compactLayout ? menuBody.width
                                                        : Theme.size(600)
                spacing: 0

                Text {
                    textFormat: Text.PlainText
                    text: qsTr("MANUAL TABLETOP · NATIVE DESKTOP")
                    color: Theme.primary
                    font.pixelSize: Theme.fontSize(12)
                    font.weight: Font.Bold
                    font.letterSpacing: 1.8
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(root.compactLayout ? 10 : 18)
                    text: qsTr("Play Magic,\nyour way.")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(
                        root.compactLayout
                        ? Math.min(42, Math.max(32, root.width * 0.06))
                        : Math.min(64, Math.max(46, root.width * 0.052)))
                    font.weight: Font.DemiBold
                    font.letterSpacing: -1.8
                    lineHeight: 0.95
                    wrapMode: Text.WordWrap
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    Layout.maximumWidth: Theme.size(500)
                    Layout.topMargin: Theme.size(root.compactLayout ? 12 : 24)
                    text: qsTr("A focused multiplayer tabletop for real decks, human decisions, and games that feel like sitting across from friends.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(root.compactLayout ? 14 : 16)
                    lineHeight: 1.45
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    visible: !root.compactLayout
                    Layout.topMargin: Theme.size(34)
                    spacing: Theme.size(26)

                    Column {
                        spacing: Theme.size(4)
                        Text { textFormat: Text.PlainText; text: "1 / 2 / 4"; color: Theme.accent; font.pixelSize: Theme.fontSize(22); font.weight: Font.DemiBold }
                        Text { textFormat: Text.PlainText; text: qsTr("PLAYER TABLES"); color: Theme.textMuted; font.pixelSize: Theme.fontSize(10); font.letterSpacing: 1.2 }
                    }

                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: Theme.size(40)
                        color: Theme.divider
                    }

                    Column {
                        spacing: Theme.size(4)
                        Text { textFormat: Text.PlainText; text: "BO 1 / BO 3"; color: Theme.accent; font.pixelSize: Theme.fontSize(22); font.weight: Font.DemiBold }
                        Text { textFormat: Text.PlainText; text: qsTr("PLAYTEST · GENERIC 1V1 · DUEL COMMANDER · COMMANDER"); color: Theme.textMuted; font.pixelSize: Theme.fontSize(10); font.letterSpacing: 1.2 }
                    }
                }
            }

            Surface {
                objectName: "mainMenuPanel"
                Layout.fillWidth: true
                Layout.fillHeight: !root.compactLayout
                Layout.preferredWidth: root.compactLayout ? menuBody.width : Theme.size(410)
                Layout.minimumWidth: root.compactLayout ? menuBody.width : Theme.size(280)
                Layout.maximumWidth: root.compactLayout ? menuBody.width : Theme.size(430)
                Layout.maximumHeight: root.compactLayout ? Number.POSITIVE_INFINITY
                                                         : Theme.size(548)
                Layout.alignment: root.compactLayout ? Qt.AlignTop : Qt.AlignVCenter
                implicitHeight: panelContent.implicitHeight + Theme.size(56)
                elevated: true

            ColumnLayout {
                id: panelContent
                anchors.fill: parent
                anchors.margins: Theme.size(28)
                spacing: Theme.size(12)

                Text {
                    textFormat: Text.PlainText
                    text: ws.connected ? qsTr("Start a room") : qsTr("Start playing")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(24)
                    font.weight: Font.DemiBold
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    Layout.bottomMargin: Theme.size(10)
                    text: ws.connected
                          ? qsTr("Connected as %1. Choose how you want to play.")
                            .arg(ws.displayName)
                          : qsTr("Connect to a room hub, or manage your decks locally.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(13)
                    lineHeight: 1.35
                    wrapMode: Text.WordWrap
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Ready check: %1 · %2 · %3")
                          .arg(cardCatalog.installed
                               ? qsTr("card data installed")
                               : qsTr("card data missing"))
                          .arg(I18n.count("deck", deckLibrary.count))
                          .arg(ws.connected
                               ? qsTr("hub connected")
                               : qsTr("hub offline"))
                    color: cardCatalog.installed
                           && deckLibrary.count > 0
                           && ws.connected ? Theme.success : Theme.warning
                    font.pixelSize: Theme.fontSize(11)
                    wrapMode: Text.WordWrap
                }

                AppButton {
                    Layout.fillWidth: true
                    variant: ws.connected ? "secondary" : "primary"
                    text: ws.connected ? qsTr("Server connected") : qsTr("Connect to server")
                    leadingText: ws.connected ? "✓" : "↗"
                    enabled: !ws.connected
                    disabledReason: qsTr("Already connected to a server")
                    onClicked: root.appWindow.pushScreen("screens/Connect.qml")
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.size(8)

                    AppButton {
                        Layout.fillWidth: true
                        variant: ws.connected ? "primary" : "secondary"
                        text: qsTr("Create room")
                        leadingText: "+"
                        enabled: ws.connected && !ws.inRoom
                        disabledReason: root.serverActionBlockerReason()
                        onClicked: root.appWindow.pushScreen("screens/CreateRoom.qml")
                    }

                    AppButton {
                        Layout.fillWidth: true
                        variant: "secondary"
                        text: qsTr("Playtest")
                        leadingText: "▶"
                        enabled: ws.connected && !ws.inRoom
                        disabledReason: root.serverActionBlockerReason()
                        onClicked: root.appWindow.pushScreen(
                                       "screens/CreateRoom.qml",
                                       {"playtestMode": true})
                    }
                }

                AppButton {
                    Layout.fillWidth: true
                    text: qsTr("Join with room code")
                    leadingText: "→"
                    enabled: ws.connected && !ws.inRoom
                    disabledReason: root.serverActionBlockerReason()
                    onClicked: root.appWindow.pushScreen("screens/JoinRoom.qml")
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.size(8)

                    AppButton {
                        Layout.fillWidth: true
                        compact: true
                        text: qsTr("Browse hub")
                        leadingText: "⌘"
                        enabled: ws.connected && !ws.inRoom
                        disabledReason: root.serverActionBlockerReason()
                        onClicked: root.appWindow.pushScreen(
                                       "screens/RoomBrowser.qml")
                    }

                    AppButton {
                        Layout.fillWidth: true
                        compact: true
                        text: qsTr("Replays")
                        leadingText: "↺"
                        enabled: ws.connected && !ws.inRoom
                        disabledReason: root.serverActionBlockerReason()
                        onClicked: root.appWindow.pushScreen(
                                       "screens/ReplayBrowser.qml")
                    }
                }

                AppButton {
                    Layout.fillWidth: true
                    text: qsTr("Tournaments")
                    enabled: ws.connected && !ws.inRoom
                    disabledReason: root.serverActionBlockerReason()
                    onClicked: root.appWindow.pushScreen(
                                   "screens/TournamentBrowser.qml")
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(6)
                    Layout.bottomMargin: Theme.size(6)
                    implicitHeight: 1
                    color: Theme.divider
                }

                AppButton {
                    Layout.fillWidth: true
                    text: qsTr("Deck library")
                    leadingText: "◇"
                    onClicked: root.appWindow.pushScreen("screens/DeckLibrary.qml")
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: deckLibrary.count === 0
                          ? qsTr("Available offline · Import your first deck")
                          : I18n.count("deck", deckLibrary.count)
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                    horizontalAlignment: Text.AlignHCenter
                }

                Item { Layout.fillHeight: true }

                AppButton {
                    Layout.fillWidth: true
                    variant: "ghost"
                    compact: true
                    text: qsTr("Quit Hexproof")
                    onClicked: Qt.quit()
                }
            }
        }
            }
        }
    }

    RowLayout {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        anchors.bottomMargin: Theme.size(22)

        Text {
            textFormat: Text.PlainText
            text: "HEXPROOF " + Qt.application.version
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize(10)
            font.letterSpacing: 1.1
        }

        Item { Layout.fillWidth: true }

        Text {
            textFormat: Text.PlainText
            text: qsTr("No accounts · No rules engine")
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize(11)
        }
    }

    function serverActionBlockerReason() {
        if (!ws.connected)
            return qsTr("Connect to a server first")
        if (ws.inRoom)
            return qsTr("Leave the current room first")
        return ""
    }
}
