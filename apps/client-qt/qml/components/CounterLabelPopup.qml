// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

AppPopup {
    id: root

    property string playerName: ""
    property string counterKey: ""
    property string currentLabel: ""
    signal labelRequested(string counterKey, string label)

    width: Math.min(Theme.size(420), parent.width - Theme.size(48))

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

        AppPopupHeader {
            titleText: root.playerName + " · " + qsTr("Rename counter")
            subtitleText: qsTr("Everyone at the table sees this label and count.")
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
