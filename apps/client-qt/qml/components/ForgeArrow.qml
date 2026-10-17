// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick
import QtQuick.Shapes
import "ForgeArrowGeometry.js" as Geometry

Item {
    id: root
    property point startPoint: Qt.point(0, 0)
    property point endPoint: Qt.point(0, 0)
    property color lineColor: "#e1bd7f"
    property real unit: 1
    property bool preview: false
    property bool dashed: false
    property var excludedRects: []
    readonly property bool validAnchors: Number.isFinite(startPoint.x) && Number.isFinite(startPoint.y)
        && Number.isFinite(endPoint.x) && Number.isFinite(endPoint.y)
        && (startPoint.x !== 0 || startPoint.y !== 0) && (endPoint.x !== 0 || endPoint.y !== 0)
        && (startPoint.x !== endPoint.x || startPoint.y !== endPoint.y)
    readonly property point safeStart: validAnchors ? startPoint : Qt.point(0, 0)
    readonly property point safeEnd: validAnchors ? endPoint : Qt.point(0, 0)
    readonly property point controlPoint: Qt.point(safeStart.x + (safeEnd.x - safeStart.x) * 0.6,
                                                  safeStart.y + (safeEnd.y - safeStart.y) * 0.1)
    readonly property real tipAngle: Math.atan2(safeEnd.y - controlPoint.y, safeEnd.x - controlPoint.x)
    readonly property real safeUnit: Number.isFinite(unit) && unit > 0 ? unit : 0
    readonly property real lineWidth: (preview ? 3.2 : 2.4) * safeUnit
    readonly property real tipSize: (preview ? 13 : 11) * safeUnit
    readonly property var geometry: validAnchors
        ? Geometry.clippedArrow(safeStart, controlPoint, safeEnd, excludedRects,
                                lineWidth, tipSize, Math.max(0.75, safeUnit * 0.5))
        : ({path:"", intervals:[], tipVisible:false})
    enabled: false

    Shape {
        id: arrowShape
        anchors.fill: parent
        visible: root.validAnchors
        opacity: root.preview ? 1 : 0.9
        // Qt 6.5 uses scene-graph geometry; newer versions also provide smooth shader-based curves.
        Component.onCompleted: {
            if ("preferredRendererType" in arrowShape)
                arrowShape["preferredRendererType"] = Shape.CurveRenderer
        }

        ShapePath {
            strokeColor: root.lineColor
            strokeWidth: root.lineWidth
            strokeStyle: root.dashed ? ShapePath.DashLine : ShapePath.SolidLine
            dashPattern: [3, 2]
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"
            startX: root.safeStart.x
            startY: root.safeStart.y
            PathSvg { path: root.geometry.path }
        }
        ShapePath {
            strokeColor: "transparent"
            strokeWidth: 0
            fillColor: root.geometry.tipVisible ? root.lineColor : "transparent"
            startX: root.safeEnd.x
            startY: root.safeEnd.y
            PathLine {
                x: root.safeEnd.x - root.tipSize * Math.cos(root.tipAngle - 0.45)
                y: root.safeEnd.y - root.tipSize * Math.sin(root.tipAngle - 0.45)
            }
            PathLine {
                x: root.safeEnd.x - root.tipSize * Math.cos(root.tipAngle + 0.45)
                y: root.safeEnd.y - root.tipSize * Math.sin(root.tipAngle + 0.45)
            }
            PathLine {
                x: root.safeEnd.x
                y: root.safeEnd.y
            }
        }
    }
}
