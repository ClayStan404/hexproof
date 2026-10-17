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
    transformOrigin: Item.Center

    // Only Forge table dialogs ease in. There is no exit transition, because a
    // closing modal popup would swallow clicks.
    property bool eased: false
    readonly property int dialogMotion: eased && Theme.motionEnabled && !Theme.motionSnap ? Theme.motionFast : 0
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: control.dialogMotion; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: control.dialogMotion; easing.type: Easing.OutCubic }
    }

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
