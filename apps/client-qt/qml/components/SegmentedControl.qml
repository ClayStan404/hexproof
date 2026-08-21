// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic

Control {
    id: control

    property var options: []
    property int currentIndex: 0
    signal activated(int index)

    function activateRelative(delta) {
        if (options.length < 2)
            return
        const next = (currentIndex + delta + options.length)
                     % options.length
        currentIndex = next
        activated(next)
        const button = segmentRepeater.itemAt(next)
        if (button)
            button.forceActiveFocus()
    }

    padding: Theme.size(4)
    implicitHeight: Theme.size(48)
    implicitWidth: Theme.size(280)

    background: Rectangle {
        color: Theme.surfaceMuted
        radius: Theme.radiusMedium
        border.width: 1
        border.color: Theme.border
    }

    contentItem: Row {
        id: segments
        spacing: Theme.size(4)

        Repeater {
            id: segmentRepeater
            model: control.options

            delegate: Button {
                id: segmentButton

                required property int index
                required property var modelData

                width: (segments.width - Math.max(0, control.options.length - 1) * segments.spacing)
                       / Math.max(1, control.options.length)
                height: segments.height
                text: modelData
                hoverEnabled: true
                focusPolicy: Qt.StrongFocus
                checked: index === control.currentIndex
                font.pixelSize: Theme.fontSize(13)
                font.weight: checked ? Font.DemiBold : Font.Medium

                onClicked: {
                    control.currentIndex = index
                    control.activated(index)
                }
                Keys.onLeftPressed: event => {
                    control.activateRelative(-1)
                    event.accepted = true
                }
                Keys.onRightPressed: event => {
                    control.activateRelative(1)
                    event.accepted = true
                }

                contentItem: Text {
                    textFormat: Text.PlainText
                    text: segmentButton.text
                    color: segmentButton.checked ? Theme.text : Theme.textMuted
                    font: segmentButton.font
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Theme.radiusSmall
                    color: segmentButton.checked
                           ? Theme.surfaceElevated
                           : (segmentButton.hovered ? Theme.surfaceHover : "transparent")
                    border.width: segmentButton.activeFocus ? 1 : 0
                    border.color: Theme.primary

                    Behavior on color { ColorAnimation { duration: Theme.motionFast } }
                }
            }
        }
    }
}
