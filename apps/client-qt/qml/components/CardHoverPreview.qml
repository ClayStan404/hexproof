// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import "TokenPresentation.js" as TokenPresentation

Item {
    id: root
    objectName: "cardHoverPreview"
    required property var catalogModel
    property var card: ({})
    property var sourceItem: null
    property var placementBoundary: null
    property var avoidItems: []
    property bool tokenArt: false
    readonly property string cardLanguage: tokenArt && catalogModel ? catalogModel.language || "en" : ""
    onCardLanguageChanged: if (tokenArt && visible && faceState.hasIdentity) TokenPresentation.prioritize(catalogModel, faceState.viewedCard)
    onSourceItemChanged: if (!sourceItem) visible = false
    property string artObjectName: "cardHoverPreviewArt"
    property alias facePreview: faceState
    property bool sourceActive: false
    readonly property bool previewHeld: previewHover.hovered
    readonly property var placement: fittedPlacement()
    readonly property var previewSize: placement.size
    width: previewSize.width
    height: previewSize.height
    visible: false
    enabled: visible && faceState.canSwitch
    z: 1000
    CardFacePreviewController {
        id: faceState
        catalogModel: root.catalogModel
        card: root.card
        sourceItem: root.sourceItem
        tokenArt: root.tokenArt
        active: root.visible
    }
    CardFacePreviewGallery {
        id: faceGallery
        objectName: "cardHoverPreviewFaces"
        controller: faceState
        anchors.fill: parent
        columns: root.previewSize.columns
        artObjectName: root.artObjectName
    }
    HoverHandler { id: previewHover }
    onPreviewHeldChanged: {
        if (previewHeld) departure.stop()
        else if (!sourceActive) departure.restart()
    }
    Timer {
        id: departure
        interval: 350
        onTriggered: if (!root.sourceActive && !root.previewHeld) root.hide()
    }
    onVisibleChanged: if (!visible) departure.stop()
    Connections {
        target: faceState
        function onHasIdentityChanged() { if (!faceState.hasIdentity) root.hide() }
    }
    function inspect(value, item) {
        if (!value || !value.name || value.faceDown === true || value.visibleIdentity === false || value.visible === false || !item || !parent) return
        if (tokenArt) TokenPresentation.prioritize(catalogModel, value)
        card = value
        sourceItem = item
        sourceActive = true
        departure.stop()
        reposition()
        visible = true
    }
    function reposition() {
        if (!sourceItem || !parent) return
        x = placement.x
        y = placement.y
    }
    onPlacementChanged: if (visible) reposition()
    function itemBounds(item) {
        if (!item || !parent) return null
        // Subscribe to scrolling/resizing ancestors as well as the item itself.
        for (let ancestor = item; ancestor; ancestor = ancestor.parent) {
            void ancestor.x; void ancestor.y; void ancestor.width; void ancestor.height
            void ancestor.scale; void ancestor.rotation
            if (!ancestor.visible) return null
        }
        return item.mapToItem(parent, 0, 0, item.width, item.height)
    }
    function availableAreas() {
        if (!parent) return []
        let areas = [Qt.rect(0, 0, parent.width, parent.height)]
        const gap = Theme.size(12)
        for (const item of avoidItems) {
            const bounds = itemBounds(item)
            if (!bounds || bounds.width <= 0 || bounds.height <= 0) continue
            const obstacle = Qt.rect(bounds.x - gap, bounds.y - gap,
                bounds.width + 2 * gap, bounds.height + 2 * gap)
            const remaining = []
            for (const area of areas) {
                const left = Math.max(area.x, obstacle.x)
                const top = Math.max(area.y, obstacle.y)
                const right = Math.min(area.x + area.width, obstacle.x + obstacle.width)
                const bottom = Math.min(area.y + area.height, obstacle.y + obstacle.height)
                if (left >= right || top >= bottom) { remaining.push(area); continue }
                if (top > area.y) remaining.push(Qt.rect(area.x, area.y, area.width, top - area.y))
                if (bottom < area.y + area.height)
                    remaining.push(Qt.rect(area.x, bottom, area.width, area.y + area.height - bottom))
                // These free rectangles may overlap. Keep their full spans so a
                // tall preview beside the obstacle is not restricted to its height.
                if (left > area.x) remaining.push(Qt.rect(area.x, area.y, left - area.x, area.height))
                if (right < area.x + area.width)
                    remaining.push(Qt.rect(right, area.y, area.x + area.width - right, area.height))
            }
            areas = remaining
        }
        return areas
    }
    function fittedPlacement() {
        const empty = {x: 0, y: 0, size: {width: 0, height: 0, columns: 1}}
        if (!parent) return empty
        const anchor = itemBounds(placementBoundary || sourceItem) || Qt.rect(0, 0, 0, 0)
        const source = itemBounds(sourceItem) || anchor
        const gap = Theme.size(12)
        const candidates = []
        for (const area of availableAreas()) {
            const size = faceGallery.fittedSize(Theme.size(380),
                Math.min(area.width, parent.width - 2 * gap),
                Math.min(area.height, parent.height - 2 * gap))
            if (size.width <= 0 || size.height <= 0) continue
            const right = anchor.x + anchor.width + gap
            const preferredX = right + size.width <= area.x + area.width
                ? right : anchor.x - size.width - gap
            const px = Math.max(area.x, Math.min(area.x + area.width - size.width, preferredX))
            const py = Math.max(area.y, Math.min(area.y + area.height - size.height, source.y))
            const faceWidth = (size.width - (size.columns - 1) * faceGallery.gap) / size.columns
            const dx = Math.max(0, source.x - px - size.width, px - source.x - source.width)
            const dy = Math.max(0, source.y - py - size.height, py - source.y - source.height)
            candidates.push({placement: {x: px, y: py, size: size}, faceWidth: faceWidth,
                distance: Math.hypot(dx, dy),
                anchorDistance: Math.abs(px - preferredX) + Math.abs(py - source.y)})
        }
        const readable = candidates.filter(candidate => candidate.faceWidth >= faceGallery.minimumFaceWidth - 0.1)
        const nearest = readable.length ? Math.min(...readable.map(candidate => candidate.distance)) : Infinity
        // Preserve the source-adjacent composition when full readable faces
        // fit there; a larger remote pocket does not justify moving away.
        const pool = readable.length ? readable.filter(candidate => candidate.distance <= nearest + Theme.size(48)) : candidates
        pool.sort((a, b) => b.faceWidth - a.faceWidth
            || a.distance - b.distance || a.anchorDistance - b.anchorDistance)
        return pool.length ? pool[0].placement : empty
    }
    FrameAnimation { running: root.visible; onTriggered: root.reposition() }
    function hide(item) {
        if (item && sourceItem && item !== sourceItem) return
        if (item && faceState.canSwitch) {
            sourceActive = false
            if (!previewHeld) departure.restart()
            return
        }
        departure.stop()
        sourceActive = false
        visible = false
        sourceItem = null
        faceState.resetFace()
    }
}
