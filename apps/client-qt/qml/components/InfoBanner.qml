// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Rectangle {
    id: root

    property string message: ""
    property string tone: "error"
    readonly property color toneColor: tone === "success" ? Theme.success
                                       : (tone === "warning" ? Theme.warning : Theme.error)

    visible: message.length > 0
    implicitHeight: messageText.implicitHeight + Theme.size(24)
    radius: Theme.radiusMedium
    color: Qt.rgba(toneColor.r, toneColor.g, toneColor.b, 0.10)
    border.width: 1
    border.color: Qt.rgba(toneColor.r, toneColor.g, toneColor.b, 0.28)

    Row {
        anchors.fill: parent
        anchors.margins: Theme.size(12)
        spacing: Theme.size(10)

        Rectangle {
            width: Theme.size(7)
            height: Theme.size(7)
            radius: Theme.size(4)
            color: root.toneColor
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            textFormat: Text.PlainText
            id: messageText
            width: parent.width - Theme.size(17)
            text: root.message
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(13)
            wrapMode: Text.WordWrap
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
