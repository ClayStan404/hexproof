// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    property string playerName: ""
    property string counterKey: ""
    property string currentLabel: ""
    signal labelRequested(string counterKey, string label)

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

    function showFor(displayName, key, label) {
        playerName = displayName
        counterKey = key
        currentLabel = label
        labelField.text = label
        open()
        labelField.forceActiveFocus()
        labelField.selectAll()
    }

    function submit() {
        const label = labelField.text.trim()
        if (label.length === 0 || label.length > 24)
            return
        close()
        labelRequested(counterKey, label)
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(16)

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.playerName + " · " + qsTr("Rename counter")
            color: Theme.text
            font.pixelSize: Theme.fontSize(20)
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Everyone at the table sees this label and count.")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(12)
            wrapMode: Text.WordWrap
        }

        AppTextField {
            id: labelField
            objectName: "counterLabelField"
            Layout.fillWidth: true
            maximumLength: 24
            placeholderText: qsTr("Counter label")
            onAccepted: root.submit()
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(10)

            Item { Layout.fillWidth: true }

            AppButton {
                objectName: "cancelCounterLabelButton"
                compact: true
                variant: "ghost"
                text: qsTr("Cancel")
                onClicked: root.close()
            }

            AppButton {
                objectName: "confirmCounterLabelButton"
                compact: true
                variant: "primary"
                text: qsTr("Rename")
                enabled: labelField.text.trim().length > 0
                onClicked: root.submit()
            }
        }
    }
}
