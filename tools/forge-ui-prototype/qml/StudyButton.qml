// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick
import QtQuick.Controls.Basic

Button {
    id: root
    property bool primary: false
    property bool quiet: false
    property real unit: 1
    implicitWidth: Math.max(90 * unit, label.implicitWidth + 28 * unit)
    implicitHeight: 40 * unit
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true
    contentItem: Text {
        id: label
        textFormat: Text.PlainText
        text: root.text
        color: !root.enabled ? "#65737e" : root.primary ? "#161b20" : "#d8e2e8"
        font.pixelSize: 13 * root.unit
        font.weight: root.primary ? Font.DemiBold : Font.Medium
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        radius: 8 * root.unit
        color: !root.enabled ? "#1b242e" : root.primary ? (root.down ? "#bc9657" : root.hovered ? "#eed39c" : "#dbbb80")
                       : root.hovered || root.checked ? "#263a46" : root.quiet ? "transparent" : "#1c2a35"
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? "#d9bd85" : root.checked ? "#698b99" : root.quiet ? "transparent" : "#334550"
    }
}
