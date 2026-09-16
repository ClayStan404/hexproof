// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: root

    property bool elevated: true
    property color stroke: "transparent"
    property int strokeWidth: 0
    property real radius: Theme.radiusXLarge

    LiquidGlass {
        anchors.fill: parent
        radius: root.radius
        elevated: root.elevated
        visible: Theme.useGlass
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        antialiasing: true
        visible: !Theme.useGlass
        color: root.elevated ? Theme.surfaceElevated : Theme.surface
        border.width: 1
        border.color: Theme.border
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        antialiasing: true
        color: "transparent"
        border.width: root.strokeWidth
        border.color: root.stroke
        visible: root.strokeWidth > 0
    }
}
