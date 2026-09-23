// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "ForgeArrow"
    when: windowShown
    visible: true
    width: 360
    height: 280

    Component {
        id: sceneComponent
        Rectangle {
            id: scene
            width: 360
            height: 280
            color: "black"
            property alias arrow: arrow
            property int clicks: 0
            MouseArea {
                anchors.fill: parent
                onClicked: scene.clicks++
            }
            ForgeArrow {
                id: arrow
                anchors.fill: parent
                startPoint: Qt.point(40, 230)
                endPoint: Qt.point(320, 40)
                lineColor: "#ff6600"
            }
        }
    }

    function arrowNear(shot, scene, point) {
        const scale = shot.width / scene.width
        for (let y = Math.floor((point.y - 6) * scale); y <= Math.ceil((point.y + 6) * scale); ++y) {
            for (let x = Math.floor((point.x - 6) * scale); x <= Math.ceil((point.x + 6) * scale); ++x) {
                if (shot.red(x, y) > 120 && shot.blue(x, y) < 80)
                    return true
            }
        }
        return false
    }

    function test_endpointUpdatesWithoutLeavingOldArrow() {
        const scene = createTemporaryObject(sceneComponent, testCase)
        verify(waitForRendering(scene))
        verify(arrowNear(grabImage(scene), scene, Qt.point(318, 44)))

        scene.arrow.preview = true
        // Several input updates before one frame should draw only the latest position.
        for (let x = 300; x >= 90; x -= 10)
            scene.arrow.endPoint = Qt.point(x, 50)
        verify(waitForRendering(scene))
        const shot = grabImage(scene)
        verify(arrowNear(shot, scene, Qt.point(90, 54)))
        verify(!arrowNear(shot, scene, Qt.point(318, 44)))
        mouseClick(scene, 90, 54)
        compare(scene.clicks, 1, "The arrow must not intercept its target's click")
    }

    function test_missingAnchorsClearRenderedArrow_data() {
        return [
            {tag: "missing-source", source: Qt.point(0, 0), target: Qt.point(320, 40)},
            {tag: "missing-target", source: Qt.point(40, 230), target: Qt.point(0, 0)},
            {tag: "coincident", source: Qt.point(40, 230), target: Qt.point(40, 230)},
            {tag: "invalid-source", source: Qt.point(NaN, 230), target: Qt.point(320, 40)},
            {tag: "invalid-target", source: Qt.point(40, 230), target: Qt.point(320, Infinity)}
        ]
    }

    function test_pointerAtLeftEdgeStillRenders() {
        const scene = createTemporaryObject(sceneComponent, testCase)
        scene.arrow.endPoint = Qt.point(0, 40)
        verify(scene.arrow.validAnchors)
        verify(waitForRendering(scene))
        verify(arrowNear(grabImage(scene), scene, Qt.point(6, 44)))
    }

    function test_missingAnchorsClearRenderedArrow(data) {
        const scene = createTemporaryObject(sceneComponent, testCase)
        verify(waitForRendering(scene))
        verify(arrowNear(grabImage(scene), scene, Qt.point(318, 44)))
        scene.arrow.startPoint = data.source
        scene.arrow.endPoint = data.target
        verify(waitForRendering(scene))
        verify(!arrowNear(grabImage(scene), scene, Qt.point(318, 44)),
               "A hidden or stale endpoint must clear the previous rendered arrow")
    }
}
