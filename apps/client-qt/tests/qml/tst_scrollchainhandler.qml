// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "ScrollChainHandler"
    when: windowShown
    property var fixture: null

    ApplicationWindow {
        id: testWindow
        width: 640
        height: 480
        visible: true
    }

    Component {
        id: fixtureComponent
        Flickable {
            id: outer
            width: 600
            height: 400
            contentWidth: width
            contentHeight: 1200
            boundsBehavior: Flickable.StopAtBounds
            property alias inner: inner
            property alias handler: handler

            Flickable {
                id: inner
                x: 20
                y: 20
                width: 500
                height: 300
                contentWidth: width
                contentHeight: 1800
                boundsBehavior: Flickable.StopAtBounds

                Rectangle {
                    width: inner.width
                    height: inner.contentHeight
                    color: "#142b25"
                }

                ScrollChainHandler {
                    id: handler
                    innerFlickable: inner
                    outerFlickable: outer
                    wheelStep: Theme.size(144)
                }
            }
        }
    }

    Component {
        id: listComponent
        ListView {
            id: list
            x: 20
            y: 20
            width: 500
            height: 300
            model: 100
            // Exercise the deferred pixel alignment performed by virtualized
            // views after a fractional contentY write, on every test backend.
            onContentYChanged: Qt.callLater(roundContentPosition)
            function roundContentPosition() { contentY = Math.round(contentY) }
            ScrollBar.vertical: AppScrollBar { }
            delegate: Rectangle {
                width: list.width
                height: 380
                color: "#142b25"
            }
            ScrollChainHandler {
                innerFlickable: list
                outerFlickable: testCase.fixture
                wheelStep: Theme.size(144)
            }
        }
    }

    function init() {
        Theme.uiScale = 1
        fixture = createTemporaryObject(fixtureComponent, testWindow.contentItem)
        verify(fixture !== null)
        waitForPolish(testWindow)
    }

    function cleanup() {
        fixture.handler.stopScrolling()
        Theme.uiScale = 1
    }

    function sendWheel(angleY, pixelY) {
        const event = {pixelDelta: Qt.point(0, pixelY || 0),
                       angleDelta: Qt.point(0, angleY || 0), accepted: false}
        fixture.handler.scrollWheel(event)
        return event.accepted
    }

    function test_mouseNotchesAnimateAndAccumulate() {
        // Use real wheel dispatch to cover event ownership as well as the
        // destination calculation, with several notches before the first settles.
        for (let index = 0; index < 4; ++index)
            mouseWheel(fixture.inner, 100, 100, 0, -120)
        verify(fixture.handler.scrolling)
        verify(fixture.inner.contentY < Theme.size(144) * 4,
               "Discrete wheel input should move smoothly between positions")
        tryCompare(fixture.inner, "contentY", Theme.size(144) * 4)
        compare(fixture.contentY, 0)
        tryCompare(fixture.handler, "scrolling", false)
    }

    function test_fractionalNotchesRespectInterfaceScale() {
        Theme.uiScale = 1.5
        verify(sendWheel(-60))
        tryCompare(fixture.inner, "contentY", Theme.size(144) / 2)
    }

    function test_continuousFineWheelDoesNotReverse_data() {
        return [{tag: "inner down", outer: false, delta: -15},
                {tag: "inner up", outer: false, delta: 15},
                {tag: "outer down", outer: true, delta: -15},
                {tag: "outer up", outer: true, delta: 15}]
    }

    function test_continuousFineWheelDoesNotReverse(data) {
        fixture.contentHeight = 20000
        fixture.inner.contentHeight = data.outer ? 200 : 20000
        const view = data.outer ? fixture : fixture.inner
        view.contentY = 3000
        let previous = view.contentY
        let greatestReverse = 0
        const direction = data.delta < 0 ? 1 : -1
        const recordPosition = () => {
            const position = view.contentY
            greatestReverse = Math.max(greatestReverse, (previous - position) * direction)
            previous = position
        }
        view.contentYChanged.connect(recordPosition)
        try {
            // Fine angle deltas can arrive several times between rendered
            // frames. Check the travel itself, not just its final destination.
            for (let index = 0; index < 100; ++index) {
                verify(sendWheel(data.delta))
                wait(5)
            }
            tryCompare(view, "contentY", 3000 - data.delta / 120 * Theme.size(144) * 100)
            compare(greatestReverse, 0,
                    "Same-direction wheel events must never animate in reverse")
        } finally {
            view.contentYChanged.disconnect(recordPosition)
        }
    }

    function test_deferredPixelAlignedListDoesNotCancelAnimation() {
        const list = createTemporaryObject(listComponent, fixture.contentItem)
        verify(list !== null)
        verify(waitForRendering(list))
        mouseWheel(list, 100, 100, 0, -120)
        tryCompare(list, "contentY", Theme.size(144))
    }

    function test_shortInnerAndBoundariesChainToOuter_data() {
        return [{tag: "short inner", innerHeight: 200, innerY: 0, outerY: 0, delta: -120},
                {tag: "inner bottom", innerHeight: 1800, innerY: 1500, outerY: 0, delta: -120},
                {tag: "inner top", innerHeight: 1800, innerY: 0, outerY: 300, delta: 120}]
    }

    function test_shortInnerAndBoundariesChainToOuter(data) {
        fixture.inner.contentHeight = data.innerHeight
        fixture.inner.contentY = data.innerY
        fixture.contentY = data.outerY
        verify(sendWheel(data.delta))
        tryCompare(fixture, "contentY", data.outerY - data.delta / 120 * Theme.size(144))
        compare(fixture.inner.contentY, data.innerY)
    }

    function test_pendingBoundaryChainsWithoutDroppingNextNotch() {
        fixture.inner.contentY = fixture.inner.contentHeight - fixture.inner.height - 30
        verify(sendWheel(-120))
        verify(sendWheel(-120))
        tryCompare(fixture.inner, "contentY", fixture.inner.contentHeight - fixture.inner.height)
        tryCompare(fixture, "contentY", Theme.size(144))
    }

    function test_pendingOuterBoundaryKeepsWheelEventOwnership() {
        fixture.inner.contentHeight = 200
        fixture.contentY = 750
        verify(sendWheel(-120))
        verify(sendWheel(-120), "A pending boundary must retain wheel event ownership")
        tryCompare(fixture, "contentY", 800)
        tryCompare(fixture.handler.outerAnimation, "running", false)
        verify(!sendWheel(-120), "A settled boundary can release wheel event ownership")
    }

    function test_externalInnerPositionOverridesPendingTravel_data() {
        return [{tag: "to bottom", position: 1500, delta: -120, outerY: 0},
                {tag: "to top", position: 0, delta: 120, outerY: 300}]
    }

    function test_externalInnerPositionOverridesPendingTravel(data) {
        fixture.inner.contentY = 300
        fixture.contentY = data.outerY
        verify(sendWheel(-120))
        fixture.inner.contentY = data.position
        verify(!fixture.handler.innerAnimation.running,
               "Scrollbar or restored positions must replace pending wheel travel")
        verify(sendWheel(data.delta))
        tryCompare(fixture, "contentY", data.outerY - data.delta / 120 * Theme.size(144))
        compare(fixture.inner.contentY, data.position)
    }

    function test_externalOuterPositionOverridesPendingTravel() {
        fixture.inner.contentY = 1500
        verify(sendWheel(-120))
        fixture.contentY = 500
        verify(!fixture.handler.outerAnimation.running)
        verify(sendWheel(-120))
        tryCompare(fixture, "contentY", 500 + Theme.size(144))
    }

    function test_pixelDeltaMovesImmediatelyWithoutMultiplication() {
        verify(sendWheel(-120, -19))
        compare(fixture.inner.contentY, 19)
        verify(!fixture.handler.innerAnimation.running)
        verify(sendWheel(120, 7))
        compare(fixture.inner.contentY, 12)
    }

    function test_pixelInputStopsPendingMouseAnimation() {
        verify(sendWheel(-120))
        const previous = fixture.inner.contentY
        verify(sendWheel(0, -11))
        compare(fixture.inner.contentY, previous + 11)
        wait(Theme.motionFast + 30)
        compare(fixture.inner.contentY, previous + 11)
    }

    function test_reverseDirectionReplacesPendingTravel() {
        fixture.inner.contentY = 300
        verify(sendWheel(-120))
        wait(40)
        const previous = fixture.inner.contentY
        verify(previous > 300)
        verify(sendWheel(120))
        wait(32)
        verify(fixture.inner.contentY < previous,
               "Reversing the wheel must reverse pending animation travel")
        tryCompare(fixture.inner, "contentY", 300)
        compare(fixture.contentY, 0)
    }

    function test_unscrollableOrHorizontalInputIsNotAccepted() {
        verify(!sendWheel(120))
        verify(!sendWheel(0))
        compare(fixture.inner.contentY, 0)
        compare(fixture.contentY, 0)
    }

    function test_disableStopsAnimation() {
        verify(sendWheel(-120))
        fixture.handler.enabled = false
        const previous = fixture.inner.contentY
        wait(Theme.motionFast + 30)
        compare(fixture.inner.contentY, previous)
        verify(!sendWheel(-120))
    }

    function test_pointerDragCancelsPendingWheelTravel() {
        verify(sendWheel(-120))
        mousePress(fixture.inner, 200, 200)
        mouseMove(fixture.inner, 200, 160, 10, Qt.LeftButton)
        mouseMove(fixture.inner, 200, 120, 10, Qt.LeftButton)
        tryVerify(() => fixture.inner.dragging)
        verify(!fixture.handler.innerAnimation.running,
               "A pointer drag must take over from wheel animation")
        mouseRelease(fixture.inner, 200, 120)
        fixture.inner.cancelFlick()
    }

    function test_replacingTargetCancelsPendingWheelTravel() {
        verify(sendWheel(-120))
        fixture.handler.innerFlickable = fixture
        verify(!fixture.handler.innerAnimation.running)
        compare(fixture.contentY, 0)
    }

    function test_shrinkingContentClampsPendingDestination() {
        verify(sendWheel(-120))
        fixture.inner.contentHeight = fixture.inner.height + 17
        tryCompare(fixture.inner, "contentY", 17)
    }
}
