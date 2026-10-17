// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic

Rectangle {
    id: root
    required property var tableController
    required property var inspector
    readonly property var sourceItem: inspector.previewSource
    objectName: "rulesCardHoverPreview"
    TextMetrics {
        id: inspectionMetrics
        text: qsTr("Inspect card")
        font.pixelSize: Theme.fontSize(14)
        font.weight: Font.DemiBold
    }
    readonly property real inspectionButtonWidth: Math.max(Theme.size(112),
        inspectionMetrics.advanceWidth + Theme.size(34))
    readonly property real inspectionIconSize: Theme.size(38)
    readonly property real galleryGap: Theme.size(8)
    property var placement: ({x:0, y:0, size:{width:0, height:0, columns:1},
        artSize:{width:0, height:0, columns:1}, faceWidth:0, fallback:false, inspectionRequired:false,
        cardId:"", source:null})
    // A source or pin change can invalidate several board geometries in the
    // same event. Coalesce their calculated result before publishing sizes to
    // the scene, so downstream layout cannot re-enter a half-updated result.
    Binding {
        target: root
        property: "placement"
        value: root.calculatePlacement()
        delayed: true
    }
    function calculatePlacement() {
        if (sourceGeometry.source !== sourceItem) {
            return {x:0, y:0, size:{width:0, height:0, columns:1},
                artSize:{width:0, height:0, columns:1}, faceWidth:0, fallback:false,
                inspectionRequired:false, cardId:inspector.previewCardId, source:sourceItem}
        }
        const art = fittedPlacement()
        const inspect = inspector.previewCardId.length > 0 && contentRects.length > 0
            && art.faceWidth < Theme.size(180) - 0.1
        const result = inspect ? hintPlacement() : art
        result.inspectionRequired = inspect
        result.artSize = art.size
        result.cardId = inspector.previewCardId
        result.source = sourceItem
        return result
    }
    readonly property bool inspectionRequired: placement.inspectionRequired
    readonly property bool inspectionIconOnly: inspectionRequired && placement.iconOnly === true
    readonly property var gallerySize: placement.artSize
    readonly property bool previewHeld: previewHover.hovered || inspectButton.activeFocus
    readonly property bool previewAllowed: tableController.roomConnected && !tableController.sideboarding
        && !tableController.priorityInputBlocked
    x: placement.x
    y: placement.y
    width: placement.size.width
    height: placement.size.height
    radius: Theme.radiusMedium
    color: Theme.surfaceElevated
    border.color: Theme.primary
    clip: true
    enabled: visible
    // In a crowded fallback, the actual combat arrows remain above the art.
    z: placement.fallback && !inspectionRequired ? 50 : 1000
    // Ordinary inspection keeps the hand and live combat context available.
    // Fit inside actual free space, preserving full-size faces when they fit.
    property rect obstacle: Qt.rect(0, 0, 0, 0)
    property var avoidRects: []
    property var protectedRects: []
    property var contentRects: []
    opacity: 1
    property bool fadeOpacity: false
    visible: inspector.previewCardId.length > 0 && inspector.hasCard
        && placement.cardId === inspector.previewCardId && placement.source === sourceItem
        && !!sourceGeometry && sourceGeometry.visible && previewAllowed
        && width > 0 && height > 0
    onPreviewAllowedChanged: if (!previewAllowed && inspector.previewCardId.length) inspector.hidePreview()
    onPreviewHeldChanged: inspector.previewHeld = previewHeld
    Binding {
        target: root.inspector
        property: "previewNeedsInspection"
        value: root.inspectionRequired
    }
    Behavior on opacity {
        enabled: fadeOpacity && Theme.motionEnabled && !Theme.motionSnap
        NumberAnimation { duration: Theme.motionFast; easing.type: Easing.OutCubic }
    }
    Timer {
        id: revealDelay
        interval: 120
        onTriggered: {
            if (root.visible)
                root.opacity = 1
        }
    }

    function beginReveal() {
        if (!visible)
            return
        if (!Theme.motionEnabled || Theme.motionSnap) {
            revealDelay.stop()
            fadeOpacity = false
            opacity = 1
            return
        }
        fadeOpacity = false
        opacity = 0
        fadeOpacity = true
        revealDelay.restart()
    }
    function edgeDistance(a, b) {
        return Math.max(0, a.x - b.x - b.width, b.x - a.x - a.width)
            + Math.max(0, a.y - b.y - b.height, b.y - a.y - a.height)
    }
    function boundedAreas(areas) {
        if (areas.length <= 24) return areas
        const faceLimit = inspector.hasIdentity ? Theme.size(360)
            : Math.min(Theme.size(360), parent.width * 0.42)
        const candidates = areas.map(area => {
            const size = fittedSize(faceLimit, area.width, area.height)
            return {area:area, capacity:(size.width - (size.columns - 1) * galleryGap) / size.columns}
        })
        const largest = candidates.slice().sort((a, b) => b.capacity - a.capacity)
        const bounds = sourceGeometry.bounds
        const nearest = candidates.slice().sort((a, b) => edgeDistance(a.area, bounds) - edgeDistance(b.area, bounds)
            || b.capacity - a.capacity)
        // Nearby unreadable slivers must not displace nearby readable faces.
        // Keep small regions too, for the inspection button or magnifier.
        const kept = nearest.filter(candidate => candidate.capacity >= Theme.size(180) - 0.1)
            .slice(0, 8).map(candidate => candidate.area)
        for (const candidate of nearest.slice(0, 8)) {
            if (!kept.includes(candidate.area)) kept.push(candidate.area)
        }
        for (const candidate of largest) {
            if (!kept.includes(candidate.area)) kept.push(candidate.area)
            if (kept.length === 24) break
        }
        return kept
    }
    function freeAreas(protectCombat) {
        if (!parent) return []
        const gap = Theme.size(12)
        let areas = [Qt.rect(gap, gap, Math.max(0, parent.width - 2 * gap),
                             Math.max(0, parent.height - 2 * gap))]
        const rects = [obstacle, sourceGeometry ? sourceGeometry.bounds : null]
            .concat(avoidRects).concat(contentRects).concat(protectCombat ? protectedRects : [])
        for (const rect of rects) {
            if (!rect || rect.width <= 0 || rect.height <= 0) continue
            const remaining = []
            for (const area of areas) {
                const left = Math.max(area.x, rect.x - gap)
                const top = Math.max(area.y, rect.y - gap)
                const right = Math.min(area.x + area.width, rect.x + rect.width + gap)
                const bottom = Math.min(area.y + area.height, rect.y + rect.height + gap)
                if (left >= right || top >= bottom) { remaining.push(area); continue }
                if (top > area.y) remaining.push(Qt.rect(area.x, area.y, area.width, top - area.y))
                if (bottom < area.y + area.height)
                    remaining.push(Qt.rect(area.x, bottom, area.width, area.y + area.height - bottom))
                if (left > area.x) remaining.push(Qt.rect(area.x, area.y, left - area.x, area.height))
                if (right < area.x + area.width)
                    remaining.push(Qt.rect(right, area.y, area.x + area.width - right, area.height))
            }
            // Removing contained rectangles bounds the search when several
            // combat links share endpoints or overlap in the same lane.
            areas = remaining.filter((area, index) => !remaining.some((other, otherIndex) =>
                otherIndex !== index && other.x <= area.x && other.y <= area.y
                && other.x + other.width >= area.x + area.width
                && other.y + other.height >= area.y + area.height
                && (otherIndex < index || other.width > area.width || other.height > area.height)))
            // Every retained area is checked against all following obstacles.
            areas = boundedAreas(areas)
        }
        return areas
    }
    function fittedSize(maxFaceWidth, availableWidth, availableHeight) {
        if (inspector.hasIdentity) {
            // Measure from explicit inputs, not the gallery item whose
            // width, height and visibility depend on this placement result.
            const count = Math.max(1, inspector.facePreview.displayFaces.length)
            const cols = count > 1 && availableWidth >= 2 * Theme.size(180) + galleryGap ? 2 : 1
            const rows = Math.ceil(count / cols)
            const faceWidth = Math.max(0, Math.min(maxFaceWidth,
                (availableWidth - (cols - 1) * galleryGap) / cols,
                (availableHeight - (rows - 1) * galleryGap) * 63 / 88 / rows))
            return {width:faceWidth * cols + (cols - 1) * galleryGap,
                height:faceWidth * 88 / 63 * rows + (rows - 1) * galleryGap, columns:cols}
        }
        // A concealed object is always one back, even after inspecting a DFC.
        const cardWidth = Math.max(0, Math.min(maxFaceWidth, availableWidth,
                                               availableHeight * 63 / 88))
        return {width:cardWidth, height:cardWidth * 88 / 63, columns:1}
    }
    function fitAreas(areas, maximumFaceWidth) {
        const empty = {x:0, y:0, size:{width:0, height:0, columns:1}, faceWidth:0, fallback:false}
        if (!sourceItem || !parent || !sourceGeometry) return empty
        const gap = Theme.size(12), bounds = sourceGeometry.bounds
        const faceLimit = maximumFaceWidth === undefined ? Theme.size(360) : maximumFaceWidth
        const candidates = []
        for (const area of areas) {
            const size = fittedSize(inspector.hasIdentity ? faceLimit
                : Math.min(faceLimit, parent.width * 0.42), area.width,
                area.height)
            if (size.width <= 0 || size.height <= 0) continue
            const right = bounds.x + bounds.width + gap
            const left = bounds.x - size.width - gap
            const preferredX = right + size.width <= parent.width - gap ? right : left
            const preferredY = bounds.y + bounds.height > parent.height * 0.72
                ? bounds.y - size.height - gap : bounds.y
            const px = Math.max(area.x, Math.min(area.x + area.width - size.width, preferredX))
            const py = Math.max(area.y, Math.min(area.y + area.height - size.height, preferredY))
            const faceWidth = (size.width - (size.columns - 1) * galleryGap) / size.columns
            candidates.push({placement:{x:px, y:py, size:size, faceWidth:faceWidth, fallback:false},
                faceWidth:faceWidth,
                distance:edgeDistance(Qt.rect(px, py, size.width, size.height), bounds),
                anchorDistance:Math.abs(px - preferredX) + Math.abs(py - preferredY)})
        }
        const readable = candidates.filter(candidate => candidate.faceWidth >= Theme.size(180) - 0.1)
        const nearest = readable.length ? Math.min(...readable.map(candidate => candidate.distance)) : Infinity
        // Fit readable art beside its source before seeking extra size across
        // the table. A fixed nearby band makes selection independent of order.
        const pool = readable.length ? readable.filter(candidate => candidate.distance <= nearest + Theme.size(48)) : candidates
        pool.sort((a, b) => b.faceWidth - a.faceWidth
            || a.distance - b.distance || a.anchorDistance - b.anchorDistance)
        return pool.length ? pool[0].placement : empty
    }
    function fittedPlacement() {
        if (!inspector.previewCardId.length)
            return {x:0, y:0, size:{width:0, height:0, columns:1}, faceWidth:0, fallback:false}
        const preferred = fitAreas(freeAreas(true))
        if (!parent || !protectedRects.length) return preferred
        const readable = fittedSize(Theme.size(180),
            parent.width - Theme.size(24), parent.height - Theme.size(32))
        const readableFace = (readable.width - (readable.columns - 1) * galleryGap) / readable.columns
        if (preferred.faceWidth >= readableFace - 0.1) return preferred
        // Keep a readable inspection in a busy battle without covering most
        // public permanents merely because relaxing curves exposes more space.
        const fallback = fitAreas(freeAreas(false), Theme.size(180))
        if (fallback.faceWidth > preferred.faceWidth + 0.1) {
            fallback.fallback = true
            return fallback
        }
        return preferred
    }
    function hintPlacement() {
        const empty = {x:0, y:0, size:{width:0, height:0, columns:1}, faceWidth:0, fallback:false}
        if (!inspector.previewCardId.length || !sourceGeometry) return empty
        // Prefer an unobscured button near the source over an unreadably small
        // gallery. Only replace its complete label with an accessible magnifier
        // when no full button fits; both retain normal control target sizes.
        const protectedAreas = freeAreas(true), relaxedAreas = freeAreas(false)
        for (const iconOnly of [false, true]) {
            const hintWidth = iconOnly ? inspectionIconSize : inspectionButtonWidth
            const hintHeight = iconOnly ? inspectionIconSize : Theme.controlHeight
            for (const protectCombat of [true, false]) {
                let best = empty, distance = Infinity
                for (const area of protectCombat ? protectedAreas : relaxedAreas) {
                    if (area.width < hintWidth || area.height < hintHeight) continue
                    const bounds = sourceGeometry.bounds
                    const px = Math.max(area.x, Math.min(area.x + area.width - hintWidth,
                        bounds.x + bounds.width + Theme.size(12)))
                    const py = Math.max(area.y, Math.min(area.y + area.height - hintHeight, bounds.y))
                    const candidate = Math.abs(px - bounds.x) + Math.abs(py - bounds.y)
                    if (candidate < distance) {
                        best = {x:px, y:py, size:{width:hintWidth, height:hintHeight, columns:1},
                            faceWidth:0, fallback:!protectCombat, iconOnly:iconOnly}
                        distance = candidate
                    }
                }
                if (best.size.width > 0) return best
            }
        }
        return empty
    }
    property var sourceGeometry: ({origin:Qt.point(0, 0), bounds:Qt.rect(0, 0, 0, 0), visible:false, source:null})
    property bool sourceGeometryReady: false
    property var sourceTransforms: []
    property var sourceGeometryInputs: []
    Binding {
        target: root
        property: "sourceGeometryInputs"
        value: root.calculateSourceGeometryInputs()
        delayed: true
    }
    function calculateSourceGeometryInputs() {
        if (!sourceGeometryReady) return []
        const inputs = [sourceItem, parent]
        if (parent) inputs.push(parent.width, parent.height)
        // Item positions and painted transforms can change independently while
        // a pile glides. Subscribe to both without depending on a lane type.
        for (let item = sourceItem; item; item = item.parent) {
            inputs.push(item, item.x, item.y, item.width, item.height,
                item.scale, item.rotation, item.transformOrigin, item.visible, item.clip)
        }
        for (const transformation of sourceTransforms) {
            if (!transformation) continue
            for (const propertyName of ["x", "y", "z", "angle", "origin", "axis", "xScale", "yScale", "zScale", "matrix"]) {
                if (propertyName in transformation) inputs.push(transformation[propertyName])
            }
        }
        return inputs
    }
    onSourceGeometryInputsChanged: Qt.callLater(refreshSourceGeometry)
    Component.onCompleted: Qt.callLater(startSourceGeometryTracking)
    Component.onDestruction: sourceGeometryReady = false
    function startSourceGeometryTracking() {
        sourceGeometryReady = true
        refreshSourceGeometry()
    }
    function refreshSourceGeometry() {
        if (!sourceGeometryReady) return
        // The transform list has no notification signal. Collect its stable
        // objects outside a binding, then subscribe to their actual values.
        const transforms = []
        for (let item = sourceItem; item; item = item.parent) {
            for (const transformation of item.transform) transforms.push(transformation)
        }
        if (transforms.length !== sourceTransforms.length
                || transforms.some((transformation, index) => transformation !== sourceTransforms[index])) {
            sourceTransforms = transforms
        }
        // Defer the map itself: transform notifications can precede the scene
        // matrix update. Deferring only assignment would keep the stale map.
        sourceGeometry = calculateSourceGeometry()
    }
    function calculateSourceGeometry() {
        if (!sourceItem || !parent)
            return {origin: Qt.point(0, 0), bounds:Qt.rect(0, 0, 0, 0), visible:false, source:sourceItem}
        const clips = []
        for (let item = sourceItem; item; item = item.parent) {
            if (!item.visible)
                return {origin: Qt.point(0, 0), bounds:Qt.rect(0, 0, 0, 0), visible:false, source:sourceItem}
            if (item.clip)
                clips.push(item)
        }
        const origin = sourceItem.mapToItem(parent, 0, 0)
        const bounds = sourceItem.mapToItem(parent, 0, 0, sourceItem.width, sourceItem.height)
        let left = Math.max(0, bounds.x), top = Math.max(0, bounds.y)
        let right = Math.min(parent.width, bounds.x + bounds.width)
        let bottom = Math.min(parent.height, bounds.y + bounds.height)
        for (const clip of clips) {
            const rect = clip.mapToItem(parent, 0, 0, clip.width, clip.height)
            left = Math.max(left, rect.x); top = Math.max(top, rect.y)
            right = Math.min(right, rect.x + rect.width)
            bottom = Math.min(bottom, rect.y + rect.height)
        }
        return {origin: origin, bounds:Qt.rect(left, top, Math.max(0, right - left),
                Math.max(0, bottom - top)), visible:right > left && bottom > top, source:sourceItem}
    }
    onVisibleChanged: {
        if (visible)
            beginReveal()
        else
            revealDelay.stop()
    }
    onSourceItemChanged: if (visible) beginReveal()
    Connections {
        target: root.inspector
        function onPreviewCardIdChanged() {
            if (root.visible)
                root.beginReveal()
        }
    }
    Connections {
        target: Theme
        function onMotionEpochChanged() {
            revealDelay.stop()
            root.fadeOpacity = false
            if (root.visible)
                root.opacity = 1
        }
    }
    CardFacePreviewGallery {
        id: gallery
        objectName: "rulesCardHoverPreviewGallery"
        controller: root.inspector.facePreview
        artObjectName: "rulesCardHoverPreviewArt"
        fallbackObjectName: "rulesCardHoverPreviewFallback"
        width: root.gallerySize.width
        height: root.gallerySize.height
        columns: root.gallerySize.columns
        gap: root.galleryGap
        visible: root.inspector.hasIdentity && !root.inspectionRequired
    }
    Image {
        id: hiddenArt
        objectName: !root.inspector.hasIdentity ? "rulesCardHoverPreviewArt" : ""
        width: parent.width
        height: parent.height
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        visible: !root.inspector.hasIdentity && !root.inspectionRequired
        source: root.visible && !root.inspector.hasIdentity ? root.tableController.cardBackSource : ""
    }
    Text {
        objectName: !root.inspector.hasIdentity ? "rulesCardHoverPreviewFallback" : ""
        textFormat: Text.PlainText
        anchors.fill: parent
        anchors.margins: Theme.size(18)
        visible: !root.inspector.hasIdentity && !root.inspectionRequired && hiddenArt.status !== Image.Ready
        text: qsTranslate("ForgeCard", "Hidden card")
        color: Theme.text
        font.pixelSize: Theme.fontSize(18)
        fontSizeMode: Text.Fit
        minimumPixelSize: Theme.fontSize(11)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
    }
    AppButton {
        id: inspectButton
        objectName: "rulesCardHoverInspect"
        anchors.fill: parent
        visible: root.inspectionRequired
        enabled: visible
        compact: root.inspectionIconOnly
        text: root.inspectionIconOnly ? "" : inspectionMetrics.text
        accessibleName: inspectionMetrics.text
        implicitWidth: root.inspectionIconOnly ? root.inspectionIconSize : root.inspectionButtonWidth
        ToolTip.text: inspectionMetrics.text
        ToolTip.visible: root.inspectionIconOnly && hovered
        ToolTip.delay: 350
        onClicked: root.tableController.openCardDetails(root.inspector.previewCardId, root.sourceItem)
        Item {
            objectName: "rulesCardHoverInspectIcon"
            anchors.centerIn: parent
            width: Theme.size(20)
            height: width
            visible: root.inspectionIconOnly
            Rectangle {
                width: Theme.size(14)
                height: width
                radius: width / 2
                color: "transparent"
                border.width: Theme.size(2)
                border.color: inspectButton.foregroundColor
            }
            Rectangle {
                x: Theme.size(12)
                y: Theme.size(12)
                width: Theme.size(9)
                height: Theme.size(2)
                radius: height / 2
                rotation: 45
                transformOrigin: Item.Left
                color: inspectButton.foregroundColor
            }
        }
    }
    HoverHandler { id: previewHover }
}
