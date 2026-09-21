// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Rectangle {
    id: root

    property bool elevated: false
    property bool interactive: false
    property bool compact: false
    property bool quiet: !compact && height > 0 && height < Theme.size(200)

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
        compact: root.compact
        quiet: root.quiet
        elevated: root.elevated || (root.interactive && hoverHandler.hovered)
        visible: Theme.useGlass && root.border.width > 0
    }

    HoverHandler {
        id: hoverHandler
        enabled: parent.interactive
    }
}
