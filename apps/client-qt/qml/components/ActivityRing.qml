// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Canvas {
    id: root

    property color ringColor: Theme.primary

    implicitWidth: Theme.size(18)
    implicitHeight: Theme.size(18)
    onRingColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    Connections {
        target: Theme
        function onUiScaleChanged() { root.requestPaint() }
    }

    onPaint: {
        const context = getContext("2d")
        context.clearRect(0, 0, width, height)
        context.strokeStyle = ringColor
        context.lineWidth = Theme.size(2)
        context.lineCap = "round"
        context.beginPath()
        context.arc(width / 2, height / 2,
                    Math.max(1, width / 2 - Theme.size(2)), 0, Math.PI * 1.48)
        context.stroke()
    }

    RotationAnimation on rotation {
        running: root.visible
        loops: Animation.Infinite
        from: 0
        to: 360
        duration: 850
    }
}
