// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic

ScrollBar {
    id: control

    property bool prominent: true

    implicitWidth: prominent ? Theme.size(14) : Theme.size(8)
    implicitHeight: prominent ? Theme.size(14) : Theme.size(8)
    policy: prominent
            ? (size > 0 && size < 1 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff)
            : ScrollBar.AsNeeded

    contentItem: Rectangle {
        implicitWidth: control.prominent ? Theme.size(10) : Theme.size(6)
        implicitHeight: control.prominent ? Theme.size(10) : Theme.size(6)
        radius: (control.horizontal ? height : width) / 2
        color: control.pressed ? Theme.primary
               : control.hovered ? Theme.primaryHover
               : (control.prominent ? Theme.borderStrong : Theme.withAlpha(Theme.text, 0.45))
        opacity: control.prominent || control.active || control.hovered ? 1 : 0.4
    }

    background: Rectangle {
        implicitWidth: control.prominent ? Theme.size(14) : Theme.size(8)
        implicitHeight: control.prominent ? Theme.size(14) : Theme.size(8)
        visible: control.prominent && control.size < 1
        color: Theme.surfaceMuted
        radius: (control.horizontal ? height : width) / 2
        border.width: 1
        border.color: Theme.border
    }
}
