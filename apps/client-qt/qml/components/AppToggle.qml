// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic

CheckBox {
    id: control

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    spacing: Theme.size(12)
    implicitHeight: Theme.size(32)

    indicator: Rectangle {
        implicitWidth: Theme.size(42)
        implicitHeight: Theme.size(24)
        x: 0
        y: (control.height - height) / 2
        radius: height / 2
        color: control.checked ? Theme.primaryStrong : Theme.surfaceMuted
        border.width: 1
        border.color: control.activeFocus
                      ? Theme.primary
                      : (control.checked ? Theme.primaryStrong : Theme.borderStrong)

        Rectangle {
            width: Theme.size(18)
            height: Theme.size(18)
            radius: Theme.size(9)
            y: Theme.size(2)
            x: control.checked ? parent.width - width - Theme.size(3) : Theme.size(3)
            color: control.checked ? Theme.primaryInk : Theme.textSecondary

            Behavior on x {
                NumberAnimation { duration: Theme.motionNormal; easing.type: Easing.OutCubic }
            }
        }

        Behavior on color { ColorAnimation { duration: Theme.motionFast } }
    }

    contentItem: Text {
        textFormat: Text.PlainText
        leftPadding: control.indicator.width + control.spacing
        text: control.text
        color: control.enabled ? Theme.textSecondary : Theme.textDisabled
        font.pixelSize: Theme.fontSize(14)
        verticalAlignment: Text.AlignVCenter
    }
}
