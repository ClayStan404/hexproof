// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    property string titleText: qsTr("Confirm action")
    property string message: ""
    property string confirmText: qsTr("Confirm")
    property bool dangerous: false
    property bool confirmedForClose: false
    signal confirmed()
    signal cancelled()

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(420), parent.width - Theme.size(48))
    padding: Theme.size(24)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onOpened: confirmedForClose = false
    onClosed: {
        if (!confirmedForClose)
            cancelled()
        confirmedForClose = false
    }

    Overlay.modal: Rectangle { color: "#A6050B09" }

    background: Rectangle {
        color: Theme.surfaceElevated
        radius: Theme.radiusLarge
        border.width: 1
        border.color: Theme.borderStrong
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(18)

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.titleText
            color: Theme.text
            font.pixelSize: Theme.fontSize(20)
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.message
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(14)
            lineHeight: 1.35
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.size(4)
            spacing: Theme.size(10)

            Item { Layout.fillWidth: true }

            AppButton {
                objectName: "cancelButton"
                compact: true
                variant: "ghost"
                text: qsTr("Cancel")
                onClicked: root.close()
            }

            AppButton {
                objectName: "confirmButton"
                compact: true
                variant: root.dangerous ? "danger" : "primary"
                text: root.confirmText
                onClicked: {
                    root.confirmedForClose = true
                    root.close()
                    root.confirmed()
                }
            }
        }
    }
}
