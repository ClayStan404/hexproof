// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    property string titleText: ""
    property string message: ""
    property string placeholderText: ""
    property string confirmText: qsTr("Apply")
    property int minimumValue: 0
    property int maximumValue: 2147483647
    signal valueRequested(int value)

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

    function showFor(value) {
        valueField.text = String(value)
        open()
        valueField.forceActiveFocus()
        valueField.selectAll()
    }

    function submit() {
        if (!valueField.acceptableInput)
            return
        const value = Number(valueField.text)
        valueRequested(value)
        close()
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(14)

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.titleText
            color: Theme.text
            font.pixelSize: Theme.fontSize(19)
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: root.message.length > 0
            text: root.message
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(11)
            wrapMode: Text.WordWrap
        }

        AppTextField {
            id: valueField
            objectName: "numberInputField"
            Layout.fillWidth: true
            placeholderText: root.placeholderText
            inputMethodHints: Qt.ImhPreferNumbers
            validator: IntValidator {
                bottom: root.minimumValue
                top: root.maximumValue
            }
            onAccepted: root.submit()
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
                compact: true
                variant: "primary"
                text: root.confirmText
                enabled: valueField.acceptableInput
                onClicked: root.submit()
            }
        }
    }
}
