// SPDX-License-Identifier: GPL-3.0-or-later
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
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0
    width: parent ? Math.min(Theme.size(420), Math.max(0, parent.width - Theme.size(48))) : 0
    height: parent ? Math.min(implicitHeight, Math.max(0, parent.height - Theme.size(48))) : 0
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

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            implicitHeight: messageText.implicitHeight
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            Text {
                id: messageText
                textFormat: Text.PlainText
                width: parent.width
                text: root.message
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(14)
                lineHeight: 1.35
                wrapMode: Text.WordWrap
            }
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
