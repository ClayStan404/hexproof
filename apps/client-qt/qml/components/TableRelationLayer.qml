// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    required property var tableController
    property var arrows: []
    property var cardPoints: ({})
    property var seatPoints: ({})
    property int localSeat: -1

    objectName: "tableRelationLayer"
    enabled: false
    z: 40

    onArrowsChanged: relationsCanvas.requestPaint()
    onCardPointsChanged: relationsCanvas.requestPaint()
    onSeatPointsChanged: relationsCanvas.requestPaint()

    function requestPaint() {
        relationsCanvas.requestPaint()
    }

    function drawsRelationArrow(relation) {
        return !(relation.kind === "attack"
                 && !relation.targetCardId
                 && relation.targetSeat !== undefined
                 && relation.targetSeat !== null
                 && relation.targetSeat >= 0)
    }

    function paintRelation(context, sourceId, targetId, color, arrowHead,
                           dashed) {
        paintRelationToPoint(context, cardPoints[sourceId],
                             cardPoints[targetId], color, arrowHead, dashed)
    }

    function paintRelationToPoint(context, from, to, color, arrowHead,
                                  dashed) {
        if (!from || !to)
            return
        const angle = Math.atan2(to.y - from.y, to.x - from.x)
        context.beginPath()
        context.strokeStyle = color
        context.lineWidth = arrowHead ? Theme.size(4) : Theme.size(3)
        context.globalAlpha = arrowHead ? 0.88 : 0.72
        context.setLineDash(dashed ? [Theme.size(8), Theme.size(5)] : [])
        context.moveTo(from.x, from.y)
        context.lineTo(to.x, to.y)
        context.stroke()
        if (arrowHead) {
            const size = Theme.size(13)
            context.beginPath()
            context.fillStyle = color
            context.moveTo(to.x, to.y)
            context.lineTo(
                        to.x - size * Math.cos(angle - Math.PI / 6),
                        to.y - size * Math.sin(angle - Math.PI / 6))
            context.lineTo(
                        to.x - size * Math.cos(angle + Math.PI / 6),
                        to.y - size * Math.sin(angle + Math.PI / 6))
            context.closePath()
            context.fill()
        }
        context.setLineDash([])
        context.globalAlpha = 1
    }

    Canvas {
        id: relationsCanvas
        anchors.fill: parent

        onWidthChanged:
            root.tableController.battlefieldScene.schedulePointRefresh()
        onHeightChanged:
            root.tableController.battlefieldScene.schedulePointRefresh()

        onPaint: {
            const context = getContext("2d")
            context.clearRect(0, 0, width, height)
            for (let index = 0; index < root.arrows.length; ++index) {
                const arrow = root.arrows[index]
                if (!root.drawsRelationArrow(arrow))
                    continue
                const target = arrow.targetCardId
                               ? root.cardPoints[arrow.targetCardId]
                               : root.seatPoints[arrow.targetSeat]
                const color = arrow.kind === "attack"
                              ? Theme.error
                              : arrow.kind === "block"
                                ? Theme.accent
                                : (arrow.seat === root.localSeat
                                   ? Theme.primary : Theme.warning)
                root.paintRelationToPoint(
                            context, root.cardPoints[arrow.sourceCardId],
                            target, color, true, arrow.kind === "block")
            }
        }
    }
}
