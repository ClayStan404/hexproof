// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    signal rollRequested(int sides, int count)

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(420), parent.width - Theme.size(48))
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

    function showFor(sides, count) {
        sidesField.text = String(sides)
        countField.text = String(count)
        open()
        sidesField.forceActiveFocus()
        sidesField.selectAll()
    }

    function submit() {
        if (!sidesField.acceptableInput || !countField.acceptableInput)
            return
        const sides = Number(sidesField.text)
        const count = Number(countField.text)
        close()
        rollRequested(sides, count)
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(14)

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Roll dice")
            color: Theme.text
            font.pixelSize: Theme.fontSize(19)
            font.weight: Font.DemiBold
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Choose 1–20 dice with 2–1,000 sides.")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(11)
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(10)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(5)

                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Sides")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(11)
                }
                AppTextField {
                    id: sidesField
                    objectName: "diceSidesField"
                    Layout.fillWidth: true
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator { bottom: 2; top: 1000 }
                    onAccepted: root.submit()
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(5)

                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Dice")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(11)
                }
                AppTextField {
                    id: countField
                    objectName: "diceCountField"
                    Layout.fillWidth: true
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator { bottom: 1; top: 20 }
                    onAccepted: root.submit()
                }
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
                objectName: "rollDiceButton"
                compact: true
                variant: "primary"
                text: qsTr("Roll")
                enabled: sidesField.acceptableInput
                         && countField.acceptableInput
                onClicked: root.submit()
            }
        }
    }
}
