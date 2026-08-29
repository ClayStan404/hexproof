// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    property bool canSetCounterCount: false
    signal settingsRequested(bool showPlayers, bool showShared,
                             bool showInspector, int counterCount,
                             bool showGameLog)

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(460), parent.width - Theme.size(48))
    padding: Theme.size(24)
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

    function showFor(showPlayers, showShared, showInspector, counterCount,
                     canSetCounters, showGameLog) {
        playersToggle.checked = false
        sharedToggle.checked = showShared
        inspectorToggle.checked = false
        gameLogToggle.checked = showGameLog !== false
        counterSpin.value = Math.max(0, Math.min(7, counterCount))
        canSetCounterCount = canSetCounters
        open()
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(14)

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Table layout")
            color: Theme.text
            font.pixelSize: Theme.fontSize(19)
            font.weight: Font.DemiBold
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Choose the optional table tools you want to keep visible.")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(11)
            wrapMode: Text.WordWrap
        }

        AppToggle {
            id: gameLogToggle
            objectName: "showGameLogToggle"
            Layout.fillWidth: true
            text: qsTr("Game log / chat rail")
        }

        AppToggle {
            id: playersToggle
            objectName: "showPlayersToggle"
            visible: false
            Layout.fillWidth: true
            text: qsTr("Player docks")
        }
        AppToggle {
            id: sharedToggle
            objectName: "showSharedToggle"
            Layout.fillWidth: true
            text: qsTr("Stack / reveal tray")
        }
        AppToggle {
            id: inspectorToggle
            objectName: "showInspectorToggle"
            visible: false
            Layout.fillWidth: true
            text: qsTr("Card detail / game log")
        }

        RowLayout {
            id: counterSettings
            Layout.fillWidth: true
            visible: root.canSetCounterCount
            spacing: Theme.size(12)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(2)
                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Your counter slots")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(13)
                    font.weight: Font.DemiBold
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Show zero to seven counters beside your hand.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(10)
                    wrapMode: Text.WordWrap
                }
            }
            SpinBox {
                id: counterSpin
                objectName: "counterCountSpinBox"
                from: 0
                to: 7
                editable: true
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(10)

            Item { Layout.fillWidth: true }

            AppButton {
                compact: true
                variant: "ghost"
                text: qsTr("Cancel")
                onClicked: root.close()
            }
            AppButton {
                objectName: "applyTableSettingsButton"
                compact: true
                variant: "primary"
                text: qsTr("Apply")
                onClicked: {
                    root.close()
                    root.settingsRequested(
                                false,
                                sharedToggle.checked,
                                false,
                                counterSpin.value,
                                gameLogToggle.checked)
                }
            }
        }
    }
}
