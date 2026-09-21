// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

AppPopup {
    id: root

    signal rollRequested(int sides, int count)

    width: Math.min(Theme.size(420), parent.width - Theme.size(48))

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
        const sides = sidesField.numberValue()
        const count = countField.numberValue()
        close()
        rollRequested(sides, count)
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(14)

        AppPopupHeader {
            titleText: qsTr("Roll dice")
            subtitleText: qsTr("Choose 1–20 dice with 2–1,000 sides.")
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
