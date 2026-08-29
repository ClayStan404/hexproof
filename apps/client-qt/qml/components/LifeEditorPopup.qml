// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    property string playerName: ""
    property int currentValue: 20
    signal lifeRequested(int value)

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

    function showFor(displayName, value) {
        playerName = displayName
        currentValue = value
        lifeField.text = String(value)
        open()
        lifeField.forceActiveFocus()
        lifeField.selectAll()
    }

    function submit() {
        if (!lifeField.acceptableInput)
            return
        const value = Number(lifeField.text)
        close()
        lifeRequested(value)
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(16)

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.playerName + " · " + qsTr("Set life total")
            color: Theme.text
            font.pixelSize: Theme.fontSize(20)
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Enter an exact value. Life may go below zero.")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(12)
            wrapMode: Text.WordWrap
        }

        AppTextField {
            id: lifeField
            objectName: "lifeEditorField"
            Layout.fillWidth: true
            placeholderText: qsTr("New life total")
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            validator: IntValidator {
                bottom: -2147483648
                top: 2147483647
            }
            onAccepted: root.submit()
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(10)

            Item { Layout.fillWidth: true }

            AppButton {
                objectName: "cancelLifeEditorButton"
                compact: true
                variant: "ghost"
                text: qsTr("Cancel")
                onClicked: root.close()
            }

            AppButton {
                objectName: "confirmLifeEditorButton"
                compact: true
                variant: "primary"
                text: qsTr("Set life")
                enabled: lifeField.acceptableInput
                onClicked: root.submit()
            }
        }
    }
}
