// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic

Menu {
    id: control

    padding: Theme.size(6)
    overlap: Theme.size(4)
    delegate: AppMenuItem {}
    implicitWidth: {
        let widest = Theme.size(160)
        const total = count
        for (let index = 0; index < total; ++index) {
            const item = itemAt(index)
            if (!item || !item.visible)
                continue
            widest = Math.max(widest, item.implicitWidth)
        }
        return widest + leftPadding + rightPadding
    }
    width: implicitWidth

    background: Surface {
        elevated: true
        radius: Theme.radiusMedium
        implicitWidth: Theme.size(180)
        implicitHeight: Theme.size(36)
        color: Theme.useGlass ? Theme.tableHandFill : Theme.surfaceElevated
        border.color: Theme.borderStrong
    }
}
