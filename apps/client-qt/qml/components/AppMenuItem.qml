// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic

MenuItem {
    id: control

    property var shortcutId
    property string extra: ""
    readonly property string shortcutLabel: shortcutId
                                            && shortcutId !== ""
                                            ? ShortcutHints.label(shortcutId)
                                            : ""

    implicitHeight: Theme.size(32)
    implicitWidth: leftPadding + rightPadding + contentItem.implicitWidth
    padding: 0
    leftPadding: Theme.size(10)
    rightPadding: Theme.size(10)
    topPadding: Theme.size(5)
    bottomPadding: Theme.size(5)
    hoverEnabled: true
    icon.width: 0
    icon.height: 0

    arrow: Item {
        implicitWidth: 0
        implicitHeight: 0
    }
    indicator: Item {
        implicitWidth: 0
        implicitHeight: 0
    }

    contentItem: Item {
        implicitWidth: labelText.implicitWidth
                       + (trailing.implicitWidth > 0
                          ? Theme.size(16) + trailing.implicitWidth : 0)
        implicitHeight: Math.max(labelText.implicitHeight,
                                 trailing.implicitHeight, Theme.size(18))

        Text {
            id: labelText
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - trailing.width
                            - (trailing.width > 0 ? Theme.size(16) : 0))
            text: control.text
            elide: Text.ElideRight
            color: control.enabled ? Theme.text : Theme.textDisabled
            font.pixelSize: Theme.fontSize(13)
        }

        Row {
            id: trailing
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.size(8)

            Rectangle {
                visible: control.extra.length > 0
                implicitWidth: extraLabel.implicitWidth + Theme.size(10)
                implicitHeight: Theme.size(18)
                radius: height / 2
                color: Theme.primaryMuted

                Text {
                    id: extraLabel
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: control.extra
                    color: control.enabled ? Theme.primary : Theme.textDisabled
                    font.pixelSize: Theme.fontSize(11)
                    font.weight: Font.DemiBold
                }
            }

            Text {
                textFormat: Text.PlainText
                visible: control.shortcutLabel.length > 0 && !control.subMenu
                text: control.shortcutLabel
                color: control.enabled ? Theme.textMuted : Theme.textDisabled
                font.pixelSize: Theme.fontSize(11)
            }

            Text {
                textFormat: Text.PlainText
                visible: control.subMenu
                text: "\u203A"
                color: control.enabled ? Theme.textMuted : Theme.textDisabled
                font.pixelSize: Theme.fontSize(14)
            }
        }
    }

    background: Rectangle {
        implicitWidth: Theme.size(120)
        implicitHeight: Theme.size(32)
        radius: Theme.radiusSmall
        color: control.highlighted
               ? (control.enabled ? Theme.highlightHover : Theme.surfaceHover)
               : "transparent"
    }
}
