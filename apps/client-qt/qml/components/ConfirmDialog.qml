// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

AppPopup {
    id: root

    property string titleText: qsTr("Confirm action")
    property string message: ""
    property string confirmText: qsTr("Confirm")
    property bool dangerous: false
    property bool confirmedForClose: false
    signal confirmed()
    signal cancelled()

    width: parent ? Math.min(Theme.size(420), Math.max(0, parent.width - Theme.size(48))) : 0
    height: parent ? Math.min(implicitHeight, Math.max(0, parent.height - Theme.size(48))) : 0
    onOpened: confirmedForClose = false
    onClosed: {
        if (!confirmedForClose)
            cancelled()
        confirmedForClose = false
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(18)

        AppPopupHeader {
            titleText: root.titleText
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
