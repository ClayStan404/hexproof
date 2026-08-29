// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: root

    property int markSize: Theme.size(38)

    implicitWidth: markSize
    implicitHeight: markSize
    onMarkSizeChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        Connections {
            target: Theme
            function onUiScaleChanged() { canvas.requestPaint() }
        }

        onPaint: {
            const context = getContext("2d")
            const centerX = width / 2
            const centerY = height / 2
            const radius = Math.min(width, height) / 2 - Theme.size(1)
            context.clearRect(0, 0, width, height)
            context.beginPath()
            for (let i = 0; i < 6; ++i) {
                const angle = Math.PI / 3 * i - Math.PI / 2
                const x = centerX + radius * Math.cos(angle)
                const y = centerY + radius * Math.sin(angle)
                if (i === 0)
                    context.moveTo(x, y)
                else
                    context.lineTo(x, y)
            }
            context.closePath()
            context.fillStyle = Theme.primary
            context.fill()
        }
    }

    Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -Theme.size(1)
        text: "H"
        color: Theme.primaryInk
        font.pixelSize: Math.round(root.markSize * 0.46)
        font.weight: Font.Black
    }
}
