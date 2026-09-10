// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

WheelHandler {
    id: root
    required property Flickable innerFlickable
    required property Flickable outerFlickable

    target: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    acceptedModifiers: Qt.NoModifier
    onWheel: event => {
        const delta = event.pixelDelta.y
                      || event.angleDelta.y / 120 * Theme.size(48)
        if (!delta) {
            event.accepted = false
            return
        }
        const inner = root.innerFlickable
        const atTop = inner.contentY <= inner.originY + 0.5
        const atBottom = inner.contentY >= inner.originY
                         + inner.contentHeight - inner.height - 0.5
        const scrollTarget = (delta > 0 ? atTop : atBottom)
                             ? root.outerFlickable : inner
        const minimum = scrollTarget.originY
        const previous = scrollTarget.contentY
        scrollTarget.cancelFlick()
        scrollTarget.contentY = Math.max(minimum, Math.min(
            Math.max(minimum, minimum + scrollTarget.contentHeight - scrollTarget.height),
            previous - delta))
        event.accepted = scrollTarget.contentY !== previous
    }
}
