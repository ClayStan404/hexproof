// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Rectangle {
    property bool elevated: false
    property bool interactive: false

    color: elevated ? Theme.surfaceElevated : Theme.surface
    radius: Theme.radiusLarge
    border.width: 1
    border.color: interactive && hoverHandler.hovered ? Theme.borderStrong : Theme.border

    Behavior on border.color {
        ColorAnimation { duration: Theme.motionFast }
    }

    HoverHandler {
        id: hoverHandler
        enabled: parent.interactive
    }
}
