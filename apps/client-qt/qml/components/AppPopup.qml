// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic

Popup {
    id: control

    parent: Overlay.overlay
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0
    modal: true
    focus: true
    padding: Theme.size(24)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    Overlay.modal: Rectangle { color: Theme.modalScrim }

    background: Surface {
        elevated: true
        radius: Theme.radiusLarge
        implicitWidth: Theme.size(200)
        implicitHeight: Theme.size(80)
        color: Theme.useGlass ? Theme.tableHandFill : Theme.surfaceElevated
        border.color: Theme.borderStrong
    }
}
