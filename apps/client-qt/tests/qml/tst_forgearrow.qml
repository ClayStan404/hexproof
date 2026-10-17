// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"
import "../../qml/components/ForgeArrowGeometry.js" as Geometry

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
            property alias label: label
            property int clicks: 0
            MouseArea {
                anchors.fill: parent
                onClicked: scene.clicks++
            }
            Text {
                id: label
                x: 139; y: 157; width: 110; height: 32
                text: "Attacking"
                color: "white"
                font.pixelSize: 18
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                visible: false
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

    function test_protectedTextHasNoArrowPixels_data() {
        return [{tag:"solid", dashed:false, preview:false, unit:1},
                {tag:"dashed", dashed:true, preview:false, unit:1},
                {tag:"aiming-scaled", dashed:false, preview:true, unit:1.8}]
    }
    function test_protectedTextHasNoArrowPixels(data) {
        const scene = createTemporaryObject(sceneComponent, testCase)
        scene.label.visible = true
        scene.arrow.dashed = data.dashed; scene.arrow.preview = data.preview; scene.arrow.unit = data.unit
        const start = scene.arrow.startPoint, end = scene.arrow.endPoint, control = scene.arrow.controlPoint
        scene.arrow.excludedRects = [Qt.rect(scene.label.x, scene.label.y, scene.label.width, scene.label.height)]
        verify(waitForRendering(scene))
        const withArrow = grabImage(scene)
        verify(arrowNear(withArrow, scene, Geometry.pointAt(start, control, end, 0.2)))
        verify(arrowNear(withArrow, scene, Geometry.pointAt(start, control, end, 0.8)))
        verify(arrowNear(withArrow, scene, end), "The ordinary target must keep its arrowhead")
        compare(scene.arrow.startPoint, start); compare(scene.arrow.endPoint, end)
        compare(scene.arrow.controlPoint, control)
        scene.arrow.visible = false
        verify(waitForRendering(scene))
        const withoutArrow = grabImage(scene)
        verify(!withArrow.equals(withoutArrow), "Exclusion must not erase the whole arrow")
        const scale = withArrow.width / scene.width
        for (let y = Math.ceil(scene.label.y * scale); y < Math.floor((scene.label.y + scene.label.height) * scale); ++y) {
            for (let x = Math.ceil(scene.label.x * scale); x < Math.floor((scene.label.x + scene.label.width) * scale); ++x) {
                compare(withArrow.pixel(x, y), withoutArrow.pixel(x, y), "An arrow painted over public text")
            }
        }
        scene.arrow.visible = true
        mouseClick(scene, scene.label.x + 20, scene.label.y + 10)
        compare(scene.clicks, 1, "Clipped paths must remain passive")
    }

    function test_tipOnlyDisappearsWhenItMeetsText() {
        const scene = createTemporaryObject(sceneComponent, testCase)
        scene.arrow.excludedRects = [Qt.rect(190, 160, 20, 25)]
        verify(scene.arrow.geometry.tipVisible)
        scene.label.x = 311; scene.label.y = 34; scene.label.width = 20; scene.label.height = 24
        scene.label.visible = true
        scene.arrow.excludedRects = [Qt.rect(311, 34, 20, 24)]
        verify(!scene.arrow.geometry.tipVisible)
        verify(waitForRendering(scene))
        const clipped = grabImage(scene)
        scene.arrow.visible = false
        verify(waitForRendering(scene))
        const hidden = grabImage(scene), scale = clipped.width / scene.width
        for (let y = Math.ceil(34 * scale); y < Math.floor(58 * scale); ++y)
            for (let x = Math.ceil(311 * scale); x < Math.floor(331 * scale); ++x)
                compare(clipped.pixel(x, y), hidden.pixel(x, y), "Arrowhead crossed protected text")
        scene.arrow.visible = true
        scene.arrow.excludedRects = []
        verify(scene.arrow.geometry.tipVisible)
        verify(waitForRendering(scene))
        verify(arrowNear(grabImage(scene), scene, scene.arrow.endPoint))
    }

    function test_exactCurveRestrictions_data() {
        return [
            {tag:"overlapping-boxes", start:{x:10,y:20}, control:{x:150,y:200}, end:{x:290,y:20},
             rects:[{x:90,y:80,width:75,height:80},{x:135,y:70,width:70,height:100}]},
            {tag:"vertical", start:{x:100,y:10}, control:{x:100,y:100}, end:{x:100,y:230},
             rects:[{x:95,y:70,width:10,height:50}]},
            {tag:"horizontal", start:{x:10,y:100}, control:{x:150,y:100}, end:{x:290,y:100},
             rects:[{x:100,y:90,width:40,height:20}]},
            {tag:"two-crossings", start:{x:10,y:10}, control:{x:150,y:300}, end:{x:290,y:10},
             rects:[{x:0,y:85,width:300,height:25}]},
            {tag:"tangent", start:{x:10,y:10}, control:{x:150,y:210}, end:{x:290,y:10},
             rects:[{x:60,y:110,width:180,height:50}]},
            {tag:"along-edge", start:{x:10,y:100}, control:{x:150,y:100}, end:{x:290,y:100},
             rects:[{x:100,y:100,width:40,height:20}]},
            {tag:"offscreen-rectangle", start:{x:10,y:10}, control:{x:150,y:200}, end:{x:290,y:20},
             rects:[{x:-200,y:-50,width:50,height:40}]},
            {tag:"fully-contained", start:{x:10,y:10}, control:{x:150,y:200}, end:{x:290,y:20},
             rects:[{x:0,y:0,width:300,height:300}]},
            {tag:"no-rectangles", start:{x:10,y:10}, control:{x:150,y:200}, end:{x:290,y:20},rects:[]}
        ]
    }
    function test_exactCurveRestrictions(data) {
        const intervals = Geometry.visibleIntervals(data.start, data.control, data.end, data.rects)
        let priorEnd = -1
        for (const interval of intervals) {
            verify(interval[0] >= 0 && interval[1] <= 1 && interval[0] < interval[1])
            verify(interval[0] >= priorEnd); priorEnd = interval[1]
            const part = Geometry.segment(data.start, data.control, data.end, interval[0], interval[1])
            for (let i = 0; i <= 20; ++i) {
                const local = i / 20, t = interval[0] + local * (interval[1] - interval[0])
                const original = Geometry.pointAt(data.start, data.control, data.end, t)
                const cut = Geometry.pointAt(part.start, part.control, part.end, local)
                verify(Math.abs(original.x - cut.x) < 1e-7 && Math.abs(original.y - cut.y) < 1e-7,
                       "A cut segment must follow the original quadratic exactly")
            }
        }
        // Independent point sampling checks the visible set, including both
        // visits through one rectangle and unions of overlapping rectangles.
        for (let i = 0; i < 997; ++i) {
            const t = (i + 0.5) / 997, u = 1 - t
            const x = u*u*data.start.x + 2*u*t*data.control.x + t*t*data.end.x
            const y = u*u*data.start.y + 2*u*t*data.control.y + t*t*data.end.y
            const inside = data.rects.some(r => x > r.x + 1e-7 && x < r.x+r.width-1e-7
                && y > r.y + 1e-7 && y < r.y+r.height-1e-7)
            const onEdge = data.rects.some(r => x >= r.x-1e-7 && x <= r.x+r.width+1e-7
                && y >= r.y-1e-7 && y <= r.y+r.height+1e-7 && !inside)
            if (onEdge) continue
            compare(intervals.some(v => t > v[0] && t < v[1]), !inside)
        }
        if (data.tag === "fully-contained") compare(intervals.length, 0)
        if (data.tag === "no-rectangles" || data.tag === "offscreen-rectangle" || data.tag === "tangent") {
            compare(intervals.length, 1); compare(intervals[0][0], 0); compare(intervals[0][1], 1)
        }
    }

    function test_invalidExclusionsAndInputsAreSafe() {
        const start = {x:10,y:10}, control = {x:150,y:100}, end = {x:290,y:20}
        const normal = Geometry.clippedArrow(start, control, end, [], 2.4, 11, 1)
        const invalid = Geometry.clippedArrow(start, control, end,
            [null, {x:NaN,y:0,width:2,height:2}, {x:0,y:0,width:-4,height:2},
             {x:0,y:0,width:2,height:Infinity}, {x:0,y:0,width:0,height:2}], 2.4, 11, 1)
        compare(invalid.path, normal.path); compare(invalid.tipVisible, normal.tipVisible)
        for (const rects of [null, 42, "invalid", {}])
            compare(Geometry.clippedArrow(start,control,end,rects,2.4,11,1).path, normal.path)
        for (const input of [[start,control,start,2.4,11], [{x:NaN,y:0},control,end,2.4,11],
                             [start,{x:2,y:Infinity},end,2.4,11], [start,control,end,NaN,11],
                             [start,control,end,2.4,0]]) {
            const result = Geometry.clippedArrow(input[0],input[1],input[2],[],input[3],input[4],1)
            compare(result.path, ""); compare(result.tipVisible, false)
        }
        const scene = createTemporaryObject(sceneComponent, testCase)
        scene.arrow.unit = NaN
        verify(waitForRendering(scene))
        compare(scene.arrow.geometry.path, "")
    }

    function test_arrowheadProtectionUsesTheFilledTriangle() {
        const points = [{x:100,y:100},{x:90,y:96},{x:90,y:104}]
        verify(Geometry.triangleMeetsRect(points, {x:93,y:99,width:1,height:1}),
               "Text contained inside the head needs protection")
        verify(Geometry.triangleMeetsRect(points, {x:94.5,y:94,width:1,height:12}),
               "Crossing an edge needs protection even with no contained vertices")
        verify(Geometry.triangleMeetsRect(points, {x:89,y:103,width:2,height:2}),
               "A head corner cannot paint over text")
        verify(!Geometry.triangleMeetsRect(points, {x:98,y:103,width:1,height:1}),
               "Bounding boxes alone must not hide a head that misses the text")
    }

    function test_movingExclusionRestoresTheOriginalLine() {
        const scene = createTemporaryObject(sceneComponent, testCase)
        verify(waitForRendering(scene))
        const original = grabImage(scene)
        scene.arrow.excludedRects = [Qt.rect(130,150,120,45)]
        verify(waitForRendering(scene))
        verify(!grabImage(scene).equals(original))
        scene.arrow.excludedRects = [Qt.rect(-200,-100,20,20)]
        verify(waitForRendering(scene))
        verify(grabImage(scene).equals(original), "Leaving labels must restore the complete original curve")
        scene.arrow.excludedRects = []
        // Removing an already off-curve box leaves identical render data and
        // correctly does not require the scene graph to schedule another frame.
        wait(0)
        verify(grabImage(scene).equals(original))
    }

    function test_fullyCoveredCurveHasNoResidualCapOrHead() {
        const scene = createTemporaryObject(sceneComponent, testCase)
        scene.arrow.excludedRects = [Qt.rect(0,0,scene.width,scene.height)]
        verify(waitForRendering(scene))
        const excluded = grabImage(scene)
        compare(scene.arrow.geometry.intervals.length, 0)
        verify(!scene.arrow.geometry.tipVisible)
        scene.arrow.visible = false
        wait(0)
        verify(excluded.equals(grabImage(scene)), "An empty path must not leave a stroke cap or arrowhead")
    }
}
