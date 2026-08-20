// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "Table"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    objectName: "tableShortcutHelp"
    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(560), parent.width - Theme.size(48))
    height: Math.min(Theme.size(620), parent.height - Theme.size(56))
    padding: Theme.size(22)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    Overlay.modal: Rectangle { color: "#A6050B09" }

    background: Rectangle {
        color: Theme.surfaceElevated
        radius: Theme.radiusLarge
        border.width: 1
        border.color: Theme.borderStrong
    }

    readonly property var shortcutRows: [
        {"keys": "F1 / ?", "action": qsTr("Show or hide this list")},
        {"keys": "F11", "action": qsTr("Toggle full screen")},
        {"keys": "Ctrl+,", "action": qsTr("Open table settings")},
        {"keys": "Ctrl+G", "action": qsTr("Show or hide game log")},
        {"keys": "Ctrl+Shift+V", "action": qsTr("Show or hide stack / reveal tray")},
        {"keys": "Ctrl+Right", "action": qsTr("Advance phase")},
        {"keys": "Ctrl+Return", "action": qsTr("Advance turn")},
        {"keys": "Ctrl+D", "action": qsTr("Draw X cards")},
        {"keys": "Ctrl+Alt+D", "action": qsTr("Draw one card")},
        {"keys": "Ctrl+F", "action": qsTr("Search own library")},
        {"keys": "Ctrl+L", "action": qsTr("View the top X library cards")},
        {"keys": "Ctrl+Shift+L", "action": qsTr("View the top library card")},
        {"keys": "Ctrl+B", "action": qsTr("View sideboard")},
        {"keys": "Ctrl+Shift+G", "action": qsTr("Put top X library cards into graveyard")},
        {"keys": "Ctrl+Shift+E", "action": qsTr("Put top X library cards into exile")},
        {"keys": "Ctrl+Shift+S", "action": qsTr("Confirm shuffle of own library")},
        {"keys": "Ctrl+U", "action": qsTr("Untap all own permanents")},
        {"keys": "Ctrl+Shift+A", "action": qsTr("Arrange own battlefield")},
        {"keys": "Ctrl+T", "action": qsTr("Create token")},
        {"keys": "Ctrl+R", "action": qsTr("Roll dice")},
        {"keys": "Ctrl+Shift+C", "action": qsTr("Flip a coin")},
        {"keys": "Ctrl+Alt+P", "action": qsTr("Select a random player")},
        {"keys": "Ctrl+Alt+R", "action": qsTr("Select a random battlefield card")},
        {"keys": "Ctrl+M", "action": qsTr("Confirm mulligan")},
        {"keys": "Ctrl+H", "action": qsTr("Reveal or recall hand")},
        {"keys": "Ctrl+Alt+X", "action": qsTr("Discard a random card")},
        {"keys": "Ctrl+Shift+X", "action": qsTr("Confirm discard entire hand")},
        {"keys": "Ctrl+Shift+H", "action": qsTr("Set life total")},
        {"keys": "Ctrl+K", "action": qsTr("Open commander damage")},
        {"keys": "Ctrl+Shift+D", "action": qsTr("Confirm declare draw")},
        {"keys": "Ctrl+Shift+R", "action": qsTr("Confirm restart game")},
        {"keys": "Ctrl+Shift+Q", "action": qsTr("Concede")},
        {"keys": "Ctrl+Shift+W", "action": qsTr("Leave room or end playtest")},
        {"keys": "Ctrl+Backspace", "action": qsTr("Return to room after the match")},
        {"keys": "I", "action": qsTr("Rename the selected player counter")},
        {"keys": "S", "action": qsTr("Set the selected player counter value")},
        {"keys": "[ / ]", "action": qsTr("Decrease / increase selected player counter")},
        {"keys": "Alt+- / Alt+=", "action": qsTr("Decrease / increase own life")},
        {"keys": "P", "action": qsTr("Play selected hand card as land")},
        {"keys": "Alt+B / Alt+Shift+B", "action": qsTr("Move selected hand card to battlefield face up / down")},
        {"keys": "Alt+H / Alt+G / Alt+E", "action": qsTr("Move selected card(s) to hand / graveyard / exile")},
        {"keys": "Alt+Up / Alt+Down", "action": qsTr("Move selected card(s) to library top / bottom")},
        {"keys": "Alt+Shift+Up / Down", "action": qsTr("Move selected battlefield cards to library in random order")},
        {"keys": "T", "action": qsTr("Tap or untap selected permanents")},
        {"keys": "F / V", "action": qsTr("Turn selected permanent face down / choose face")},
        {"keys": "A / Shift+A", "action": qsTr("Attach / detach selected permanent")},
        {"keys": "R / Shift+R", "action": qsTr("Choose / clear target for selected cards")},
        {"keys": "X / Shift+X", "action": qsTr("Attack a permanent / block an attacker")},
        {"keys": "Shift+C", "action": qsTr("Clear selected combat declaration")},
        {"keys": "N / Shift+N", "action": qsTr("Add a number / ability counter to selected permanent")},
        {"keys": "Ctrl+N", "action": qsTr("Set selected permanent's number counter")},
        {"keys": "Alt+C", "action": qsTr("Create a token copy of selected permanent")},
        {"keys": "Ctrl + wheel", "action": qsTr("Adjust battlefield card size")},
        {"keys": "← / → / Home / End", "action": qsTr("Move between hand cards")},
        {"keys": "Enter", "action": qsTr("Open the focused hand card menu")}
    ]

    contentItem: ColumnLayout {
        spacing: Theme.size(12)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(12)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(3)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Table shortcuts")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(20)
                    font.weight: Font.DemiBold
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Shortcuts are paused while a text field or modal editor is open.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(11)
                    wrapMode: Text.WordWrap
                }
            }

            AppButton {
                objectName: "closeShortcutHelpButton"
                compact: true
                variant: "ghost"
                text: "×"
                accessibleName: qsTr("Close")
                Layout.preferredWidth: Theme.size(40)
                onClicked: root.close()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.divider
        }

        ListView {
            id: shortcutList
            objectName: "tableShortcutHelpList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: Theme.size(2)
            model: root.shortcutRows

            delegate: RowLayout {
                id: shortcutRow
                required property var modelData
                width: ListView.view.width
                spacing: Theme.size(12)

                Text {
                    textFormat: Text.PlainText
                    text: shortcutRow.modelData.keys
                    color: Theme.accent
                    font.pixelSize: Theme.fontSize(12)
                    font.weight: Font.DemiBold
                    Layout.preferredWidth: Theme.size(168)
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: shortcutRow.modelData.action
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(12)
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
