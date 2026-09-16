// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick

Canvas {
    id: root
    property point startPoint: Qt.point(0, 0)
    property point endPoint: Qt.point(0, 0)
    property color lineColor: "#e1bd7f"
    property real unit: 1
    onStartPointChanged: requestPaint()
    onEndPointChanged: requestPaint()
    onVisibleChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        if (!visible || startPoint.x === 0 || endPoint.x === 0)
            return
        const dx = endPoint.x - startPoint.x
        const dy = endPoint.y - startPoint.y
        const control = Qt.point(startPoint.x + dx * 0.6, startPoint.y + dy * 0.1)
        const angle = Math.atan2(endPoint.y - control.y, endPoint.x - control.x)
        const tip = 11 * unit
        ctx.strokeStyle = lineColor
        ctx.fillStyle = lineColor
        ctx.lineWidth = 2.4 * unit
        ctx.globalAlpha = 0.9
        ctx.beginPath()
        ctx.moveTo(startPoint.x, startPoint.y)
        ctx.quadraticCurveTo(control.x, control.y, endPoint.x, endPoint.y)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(endPoint.x, endPoint.y)
        ctx.lineTo(endPoint.x - tip * Math.cos(angle - 0.45), endPoint.y - tip * Math.sin(angle - 0.45))
        ctx.lineTo(endPoint.x - tip * Math.cos(angle + 0.45), endPoint.y - tip * Math.sin(angle + 0.45))
        ctx.closePath()
        ctx.fill()
    }
}
