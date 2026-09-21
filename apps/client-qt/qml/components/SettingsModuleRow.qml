// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Layouts

Surface {
    id: root

    property string title: ""
    property string subtitle: ""
    property string statusText: ""
    property color statusColor: Theme.warning
    signal activated()

    implicitHeight: row.implicitHeight + Theme.size(32)
    elevated: true
    opacity: enabled ? 1 : 0.55

    Accessible.role: Accessible.Button
    Accessible.name: title
    Accessible.description: subtitle
    Accessible.onPressAction: if (root.enabled) root.activated()

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: Theme.size(16)
        spacing: Theme.size(14)

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.size(4)
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.title
                color: Theme.text
                font.pixelSize: Theme.fontSize(16)
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                visible: root.subtitle.length > 0
                text: root.subtitle
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.WordWrap
            }
        }

        StatusPill {
            visible: root.statusText.length > 0
            text: root.statusText
            statusColor: root.statusColor
        }

        Text {
            textFormat: Text.PlainText
            text: "›"
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize(22)
        }
    }

    HoverHandler {
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        enabled: root.enabled
        onTapped: root.activated()
    }
}
