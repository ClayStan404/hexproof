// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Rectangle {
    id: root

    property string text: ""
    property color statusColor: Theme.textMuted
    property real maximumWidth: Number.POSITIVE_INFINITY

    implicitWidth: Math.min(pillLabel.implicitWidth + Theme.size(40),
                            maximumWidth)
    implicitHeight: Theme.size(30)
    radius: height / 2
    color: Qt.rgba(statusColor.r, statusColor.g, statusColor.b, 0.11)
    border.width: 1
    border.color: Qt.rgba(statusColor.r, statusColor.g, statusColor.b, 0.25)

    Row {
        id: pillContent
        anchors.fill: parent
        anchors.leftMargin: Theme.size(11)
        anchors.rightMargin: Theme.size(11)
        spacing: Theme.size(7)

        Rectangle {
            width: Theme.size(7)
            height: Theme.size(7)
            radius: Theme.size(4)
            color: root.statusColor
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            textFormat: Text.PlainText
            id: pillLabel

            width: Math.max(0, pillContent.width
                               - pillContent.spacing
                               - Theme.size(7))
            text: root.text
            color: root.statusColor
            font.pixelSize: Theme.fontSize(12)
            font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
        }
    }
}
