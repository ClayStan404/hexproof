// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

AppPopup {
    id: root

    property string playerName: ""
    property int currentValue: 20
    signal lifeRequested(int value)

    width: Math.min(Theme.size(420), parent.width - Theme.size(48))

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
        const value = lifeField.numberValue()
        close()
        lifeRequested(value)
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(16)

        AppPopupHeader {
            titleText: root.playerName + " · " + qsTr("Set life total")
            subtitleText: qsTr("Enter an exact value. Life may go below zero.")
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
