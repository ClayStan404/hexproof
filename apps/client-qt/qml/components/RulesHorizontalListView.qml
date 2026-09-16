// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic

ListView {
    id: root

    property Flickable outerFlickable: null
    readonly property bool overflowing: contentWidth > width
    readonly property real scrollBarInset: overflowing ? Theme.size(14) : 0
    readonly property real itemHeight: Math.max(0, height - scrollBarInset)
    readonly property Item focusedItem: Window.activeFocusItem

    orientation: ListView.Horizontal
    clip: true
    activeFocusOnTab: true
    cacheBuffer: width * 2

    function scrollTarget(target, delta) {
        const previous = target.contentX
        target.cancelFlick()
        target.contentX = Math.max(target.originX, Math.min(
            Math.max(target.originX, target.originX + target.contentWidth - target.width), previous + delta))
        return target.contentX !== previous
    }

    function scrollBy(delta) { return scrollTarget(root, delta) }

    function revealFocusedItem() {
        let tile = focusedItem
        while (tile && tile.parent !== contentItem)
            tile = tile.parent
        if (!tile)
            return
        const item = tile.width <= width ? tile : focusedItem
        const left = item.mapToItem(contentItem, 0, 0).x
        if (left < contentX)
            scrollBy(left - contentX)
        else if (left + item.width > contentX + width)
            scrollBy(left + item.width - contentX - width)
    }

    onFocusedItemChanged: revealFocusedItem()
    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Left: event.accepted = scrollBy(-width * 0.8); break
        case Qt.Key_Right: event.accepted = scrollBy(width * 0.8); break
        case Qt.Key_Home: event.accepted = scrollBy(originX - contentX); break
        case Qt.Key_End: event.accepted = scrollBy(originX + contentWidth - width - contentX); break
        }
    }

    ScrollBar.horizontal: ScrollBar {
        objectName: root.objectName + "ScrollBar"
        policy: root.overflowing ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
        active: true
    }

    WheelHandler {
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const delta = event.pixelDelta.x || event.pixelDelta.y
                          || event.angleDelta.x || event.angleDelta.y
            // At an edge, let an enclosing pile or prompt handle the wheel.
            event.accepted = delta !== 0 && (root.scrollBy(-delta)
                    || (root.outerFlickable && root.scrollTarget(root.outerFlickable, -delta)))
        }
    }
}
