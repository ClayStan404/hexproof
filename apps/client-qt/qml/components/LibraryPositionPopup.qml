// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    property string cardName: ""
    signal positionRequested(int position)

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(390), parent.width - Theme.size(48))
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

    function showFor(name) {
        cardName = name
        positionField.text = "1"
        open()
        positionField.forceActiveFocus()
        positionField.selectAll()
    }

    function submit() {
        if (!positionField.acceptableInput)
            return
        const position = Number(positionField.text)
        close()
        positionRequested(position)
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(14)

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.cardName + " · "
                  + qsTr("Move to library position")
            color: Theme.text
            font.pixelSize: Theme.fontSize(18)
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }
        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("1 is the top card. Larger positions are clamped to the bottom.")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(10)
            wrapMode: Text.WordWrap
        }
        AppTextField {
            id: positionField
            Layout.fillWidth: true
            inputMethodHints: Qt.ImhDigitsOnly
            validator: IntValidator {
                bottom: 1
                top: 2147483647
            }
            onAccepted: root.submit()
        }
        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            AppButton {
                compact: true
                variant: "ghost"
                text: qsTr("Cancel")
                onClicked: root.close()
            }
            AppButton {
                compact: true
                variant: "primary"
                text: qsTr("Move")
                enabled: positionField.acceptableInput
                onClicked: root.submit()
            }
        }
    }
}
