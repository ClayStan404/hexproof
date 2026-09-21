// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

AppPopup {
    id: root

    property string cardName: ""
    signal positionRequested(int position)

    width: Math.min(Theme.size(390), parent.width - Theme.size(48))

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
        const position = positionField.numberValue()
        close()
        positionRequested(position)
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(14)

        AppPopupHeader {
            titleText: root.cardName + " · "
                       + qsTr("Move to library position")
            subtitleText: qsTr("1 is the top card. Larger positions are clamped to the bottom.")
        }
        AppTextField {
            id: positionField
            objectName: "libraryPositionField"
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
