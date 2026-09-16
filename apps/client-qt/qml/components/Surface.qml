// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Rectangle {
    id: root

    property bool elevated: false
    property bool interactive: false

    color: Theme.useGlass ? "transparent"
           : (elevated ? Theme.surfaceElevated : Theme.surface)
    radius: Theme.radiusLarge
    antialiasing: true
    border.width: 1
    border.color: Theme.useGlass ? "transparent"
                  : (interactive && hoverHandler.hovered ? Theme.borderStrong : Theme.border)

    Behavior on border.color {
        ColorAnimation { duration: Theme.motionFast }
    }

    LiquidGlass {
        anchors.fill: parent
        radius: root.radius
        elevated: root.elevated || (root.interactive && hoverHandler.hovered)
        visible: Theme.useGlass && root.border.width > 0
    }

    HoverHandler {
        id: hoverHandler
        enabled: parent.interactive
    }
}
