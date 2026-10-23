// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

WheelHandler {
    id: root
    required property Flickable innerFlickable
    required property Flickable outerFlickable
    property real wheelStep: Theme.size(48)
    readonly property bool scrolling: active || innerAnimation.running || outerAnimation.running
    // Animate proxies so scrollbar and restored contentY positions can cancel
    // pending wheel travel without cancelling frames written by this handler.
    property bool applyingScrollPosition: false
    property real innerAnimatedPosition: 0
    property real outerAnimatedPosition: 0
    onInnerAnimatedPositionChanged: applyAnimatedPosition(innerFlickable, innerAnimatedPosition)
    onOuterAnimatedPositionChanged: applyAnimatedPosition(outerFlickable, outerAnimatedPosition)

    property NumberAnimation innerAnimation: NumberAnimation {
        target: root
        property: "innerAnimatedPosition"
        duration: Theme.motionFast
        easing.type: Easing.OutCubic
    }
    property NumberAnimation outerAnimation: NumberAnimation {
        target: root
        property: "outerAnimatedPosition"
        duration: Theme.motionFast
        easing.type: Easing.OutCubic
    }
    property Connections innerChanges: Connections {
        target: root.innerFlickable
        function onContentYChanged() {
            if (root.positionWasOverridden(root.innerFlickable, root.innerAnimatedPosition))
                root.innerAnimation.stop()
        }
        function onDraggingChanged() {
            if (root.innerFlickable.dragging)
                root.stopScrolling()
        }
        function onContentHeightChanged() { root.clampAnimation(root.innerFlickable, root.innerAnimation) }
        function onHeightChanged() { root.clampAnimation(root.innerFlickable, root.innerAnimation) }
        function onOriginYChanged() { root.clampAnimation(root.innerFlickable, root.innerAnimation) }
    }
    property Connections outerChanges: Connections {
        target: root.outerFlickable
        function onContentYChanged() {
            if (root.positionWasOverridden(root.outerFlickable, root.outerAnimatedPosition))
                root.outerAnimation.stop()
        }
        function onDraggingChanged() {
            if (root.outerFlickable.dragging)
                root.stopScrolling()
        }
        function onContentHeightChanged() { root.clampAnimation(root.outerFlickable, root.outerAnimation) }
        function onHeightChanged() { root.clampAnimation(root.outerFlickable, root.outerAnimation) }
        function onOriginYChanged() { root.clampAnimation(root.outerFlickable, root.outerAnimation) }
    }

    target: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    acceptedModifiers: Qt.NoModifier
    onEnabledChanged: if (!enabled) stopScrolling()
    onInnerFlickableChanged: stopScrolling()
    onOuterFlickableChanged: stopScrolling()
    onWheel: event => scrollWheel(event)

    function stopScrolling() {
        if (innerAnimation)
            innerAnimation.stop()
        if (outerAnimation)
            outerAnimation.stop()
    }

    function applyAnimatedPosition(view, position) {
        if (!view)
            return
        applyingScrollPosition = true
        view.contentY = position
        applyingScrollPosition = false
    }

    function positionWasOverridden(view, animatedPosition) {
        // Views can report a deferred, pixel-rounded version of our own write
        // during polish. Only a different position cancels the wheel gesture.
        return !applyingScrollPosition && Math.abs(view.contentY - animatedPosition) > 0.5
    }

    function animatePosition(view, animation, destination) {
        animation.stop()
        if (animation === innerAnimation)
            innerAnimatedPosition = view.contentY
        else
            outerAnimatedPosition = view.contentY
        animation.from = view.contentY
        animation.to = destination
        animation.restart()
    }

    function boundedPosition(view, position) {
        const minimum = view.originY
        return Math.max(minimum, Math.min(
            Math.max(minimum, minimum + view.contentHeight - view.height), position))
    }

    function clampAnimation(view, animation) {
        if (view && animation && animation.running) {
            const bounded = boundedPosition(view, animation.to)
            if (bounded !== animation.to)
                animatePosition(view, animation, bounded)
        }
    }

    function scrollWheel(event) {
        if (!enabled || !innerFlickable || !outerFlickable) {
            event.accepted = false
            return
        }
        const pixelScroll = event.pixelDelta.y !== 0
        const delta = event.pixelDelta.y
                      || event.angleDelta.y / 120 * wheelStep
        if (!delta) {
            event.accepted = false
            return
        }
        if (pixelScroll)
            stopScrolling()
        const inner = root.innerFlickable
        // Accumulate wheel notches from the pending destination. Reading only
        // contentY loses most input when more notches arrive during animation.
        const innerPosition = innerAnimation.running ? innerAnimation.to : inner.contentY
        const atTop = innerPosition <= inner.originY + 0.5
        const atBottom = innerPosition >= inner.originY
                         + inner.contentHeight - inner.height - 0.5
        const scrollTarget = (delta > 0 ? atTop : atBottom)
                             ? root.outerFlickable : inner
        const animation = scrollTarget === inner ? innerAnimation : outerAnimation
        const previous = animation.running ? animation.to : scrollTarget.contentY
        const destination = boundedPosition(scrollTarget, previous - delta)
        // Keep ownership while travelling to a boundary; bubbling another
        // notch would let the ancestor's native wheel handling interrupt it.
        event.accepted = destination !== previous || animation.running
        if (destination === previous)
            return
        scrollTarget.cancelFlick()
        if (pixelScroll) {
            scrollTarget.contentY = destination
        } else {
            animatePosition(scrollTarget, animation, destination)
        }
    }
}
