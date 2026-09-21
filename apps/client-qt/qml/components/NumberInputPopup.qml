// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

AppPopup {
    id: root

    property string titleText: ""
    property string message: ""
    property string placeholderText: ""
    property string confirmText: qsTr("Apply")
    property int minimumValue: 0
    property int maximumValue: 2147483647
    signal valueRequested(int value)

    width: Math.min(Theme.size(420), parent.width - Theme.size(48))

    function showFor(value) {
        valueField.text = String(value)
        open()
        valueField.forceActiveFocus()
        valueField.selectAll()
    }

    function submit() {
        if (!valueField.acceptableInput)
            return
        const value = valueField.numberValue()
        valueRequested(value)
        close()
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(14)

        AppPopupHeader {
            titleText: root.titleText
            subtitleText: root.message
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
