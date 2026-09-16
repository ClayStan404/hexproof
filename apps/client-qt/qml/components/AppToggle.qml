// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic

CheckBox {
    id: control

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    spacing: Theme.size(12)
    implicitHeight: Math.max(Theme.size(32), implicitContentHeight + topPadding + bottomPadding)

    indicator: Item {
        implicitWidth: Theme.size(42)
        implicitHeight: Theme.size(24)
        x: 0
        y: (control.height - height) / 2

        LiquidGlass {
            anchors.fill: parent
            radius: height / 2
            compact: true
            elevated: control.hovered || control.activeFocus
            visible: Theme.useGlass && !control.checked
        }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            antialiasing: true
            color: control.checked
                   ? Theme.primaryStrong
                   : (Theme.useGlass ? "transparent" : Theme.surfaceMuted)
            border.width: Theme.useGlass
                          ? (control.activeFocus ? 1 : 0)
                          : 1
            border.color: Theme.useGlass
                          ? Theme.primary
                          : (control.activeFocus
                             ? Theme.primary
                             : (control.checked ? Theme.primaryStrong : Theme.borderStrong))

            Rectangle {
                width: Theme.size(18)
                height: Theme.size(18)
                radius: Theme.size(9)
                antialiasing: true
                y: Theme.size(2)
                x: control.checked ? parent.width - width - Theme.size(3) : Theme.size(3)
                color: control.checked
                       ? Theme.primaryInk
                       : (Theme.useGlass ? Theme.text : Theme.textSecondary)

                Behavior on x {
                    NumberAnimation { duration: Theme.motionNormal; easing.type: Easing.OutCubic }
                }
            }

            Behavior on color { ColorAnimation { duration: Theme.motionFast } }
        }
    }

    contentItem: Text {
        textFormat: Text.PlainText
        leftPadding: control.indicator.width + control.spacing
        text: control.text
        color: control.enabled ? Theme.textSecondary : Theme.textDisabled
        font.pixelSize: Theme.fontSize(14)
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
    }
}
