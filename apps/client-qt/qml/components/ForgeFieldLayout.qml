// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick

QtObject {
    id: root
    required property real width
    required property real height
    required property real unit
    required property bool nearSide
    required property var creatureLane
    required property var landLane
    required property var otherLane
    property var planeswalkerLane: null
    // Local rectangles already include the caller's safety margins.
    property var obstacles: []
    property var widthForBand: null
    property bool preferCenteredRows: false
    readonly property real gap: 8 * unit
    readonly property var options: listOptions()
    property var placement: emptyPlacement()
    onOptionsChanged: applyPlacement()
    Component.onCompleted: applyPlacement()

    function rect(x, y, w, h) {
        return Qt.rect(x, y, Math.max(0, w), Math.max(0, h))
    }
    function emptyPlacement() {
        const empty = rect(0, 0, 0, 0)
        return {creatures:empty, lands:empty, planeswalkers:empty, others:empty,
            flow:"", key:"", visible:0, covered:0, full:0, score:0, creatureFace:0}
    }
    function count(lane) { return lane ? lane.stackCount : 0 }
    function budget(lane) {
        return lane ? typeof lane.layoutStackCount === "number" && lane.layoutStackCount >= 0
            ? lane.layoutStackCount : Math.max(lane.stackCount, (lane.hostCards || []).length) : 0
    }
    function minimumWidth(lane) {
        if (!count(lane)) return 0
        return typeof lane.layoutMinimumWidth === "function" ? lane.layoutMinimumWidth()
            : (lane.startInset || 0) + (budget(lane) > 1 ? 9 : 0) * unit + 86 * unit
    }
    function overlaps(a, b) {
        return a.width > 0 && a.height > 0 && b.width > 0 && b.height > 0
            && a.x < b.x + b.width - 1e-7 && a.x + a.width > b.x + 1e-7
            && a.y < b.y + b.height - 1e-7 && a.y + a.height > b.y + 1e-7
    }
    function contains(a, b) {
        return a.x <= b.x + 1e-7 && a.y <= b.y + 1e-7
            && a.x + a.width >= b.x + b.width - 1e-7
            && a.y + a.height >= b.y + b.height - 1e-7
    }
    function freeRects(area, anchor, exclusions) {
        let found = [area]
        for (const obstacle of exclusions || obstacles) {
            const next = []
            for (const part of found) {
                if (!overlaps(part, obstacle)) {
                    next.push(part)
                    continue
                }
                const right = part.x + part.width, bottom = part.y + part.height
                if (obstacle.x > part.x)
                    next.push(rect(part.x, part.y, obstacle.x - part.x, part.height))
                if (obstacle.x + obstacle.width < right)
                    next.push(rect(obstacle.x + obstacle.width, part.y,
                        right - obstacle.x - obstacle.width, part.height))
                if (obstacle.y > part.y)
                    next.push(rect(part.x, part.y, part.width, obstacle.y - part.y))
                if (obstacle.y + obstacle.height < bottom)
                    next.push(rect(part.x, obstacle.y + obstacle.height,
                        part.width, bottom - obstacle.y - obstacle.height))
            }
            found = next.filter((part, index) => part.width > 0 && part.height > 0
                && !next.some((other, otherIndex) => otherIndex !== index && contains(other, part)
                    && (otherIndex < index || !contains(part, other))))
            // Bound the maximal rectangles before fitting crowded lanes.
            found.sort((a, b) => anchorDistance(a, area, anchor) - anchorDistance(b, area, anchor)
                || b.width * b.height - a.width * a.height)
            found = found.slice(0, 16)
        }
        return found
    }
    function anchorDistance(area, original, anchor) {
        if (anchor === "left") return Math.abs(area.x - original.x)
        if (anchor === "right") return Math.abs(area.x + area.width - original.x - original.width)
        return Math.abs(area.x + area.width / 2 - original.x - original.width / 2)
    }
    // Work from the combat front towards the player's rear. Only that axis
    // mirrors for the far player; left/right and the creature center never do.
    function mirrored(area) {
        return nearSide ? area : rect(area.x, height - area.y - area.height, area.width, area.height)
    }
    function scoreLane(lane, area) {
        if (!count(lane) || area.width <= 0 || area.height <= 0)
            return {visible:0, area:0, face:0, covered:0, full:0}
        const available = Math.max(0, area.height - lane.headerHeight)
        const fit = lane.layoutGrid(area.width, available)
        const rows = Math.max(0, Math.floor((available - lane.pileLead - lane.edgeSpace)
            / (fit.face * lane.faceRatio + lane.layoutCellExtra) + 1e-7))
        const readable = fit.face >= 80 * unit - 1e-7
        const visible = readable ? Math.min(lane.stackCount, rows * fit.columns) : 0
        return {visible:visible, area:visible * fit.face * fit.face, face:fit.face,
            covered:readable && available >= fit.face * lane.faceRatio / 2 + 1e-7 ? 1 : 0,
            full:readable && available >= fit.face * lane.faceRatio - 1e-7 ? 1 : 0}
    }
    function naturalWidth(lane) {
        if (!count(lane)) return 0
        const face = Math.min(108 * unit, lane.maxFaceWidth > 0 ? lane.maxFaceWidth : 108 * unit)
        return minimumWidth(lane) - 80 * unit + budget(lane) * (face + gap) - gap
    }
    function minimumRowHeight(lane) {
        if (!count(lane)) return 0
        const cell = 80 * unit * lane.faceRatio + lane.layoutCellExtra
        return lane.layoutMinimumHeight(minimumWidth(lane)) - (budget(lane) - 1) * cell
    }
    function rowHeight(lane, availableWidth, faceCeiling) {
        if (!count(lane)) return 0
        const available = availableWidth - minimumWidth(lane) + 80 * unit
        if (available < 80 * unit - 1e-7) return Infinity
        // Horizontal order is structural. Use the fewest rows possible at the
        // readable floor, then grow faces inside those rows. A taller neighbor
        // must not turn five lands into a column merely to enlarge their art.
        const columnsAtFloor = Math.max(1, Math.floor((available + gap) / (80 * unit + gap) + 1e-7))
        const rows = Math.ceil(budget(lane) / columnsAtFloor)
        const columns = Math.ceil(budget(lane) / rows)
        const face = Math.min((faceCeiling || 108) * unit, lane.maxFaceWidth > 0 ? lane.maxFaceWidth : 108 * unit,
            (available - (columns - 1) * gap) / columns)
        return lane.layoutMinimumHeight(availableWidth) + rows * (face - 80 * unit) * lane.faceRatio
    }
    function support(lane, area, rear, exclusions, limit, frontReserve, faceCeiling) {
        if (!count(lane)) return rect(0, 0, 0, 0)
        const anchor = lane === landLane ? "left" : "right"
        let best = null, bestScore = null, bestEdge = Infinity, bestEnd = Infinity
        for (const free of freeRects(area, anchor, exclusions)) {
            if (free.width < minimumWidth(lane) - 1e-7) continue
            const wanted = rowHeight(lane, free.width, faceCeiling)
            const usableHeight = rear && frontReserve > 0
                ? free.height - Math.min(free.height / 2, frontReserve + gap) : free.height
            const extent = Math.min(usableHeight, wanted, limit)
            const placed = rect(free.x, rear ? free.y + free.height - extent : free.y, free.width, extent)
            const score = scoreLane(lane, placed)
            const edge = anchorDistance(placed, area, anchor)
            const end = rear ? height - placed.y - placed.height : placed.y
            // Full cards first; then the requested edge, then front/rear.
            // Capacity may alter rows inside this region, never its compass.
            if (!best || score.full > bestScore.full
                || score.full === bestScore.full && (edge < bestEdge - 1e-7
                    || Math.abs(edge - bestEdge) < 1e-7 && (end < bestEnd - 1e-7
                        || Math.abs(end - bestEnd) < 1e-7 && score.visible > bestScore.visible))) {
                best = placed; bestScore = score; bestEdge = edge; bestEnd = end
            }
        }
        return best || rect(area.x, area.y, 0, 0)
    }
    function centeredCreature(exclusions) {
        if (!count(creatureLane)) return rect(0, 0, 0, 0)
        const whole = rect(0, 0, width, height)
        let best = null, bestScore = null
        for (const free of freeRects(whole, "center", exclusions)) {
            // A control or right wing may narrow the creature row, but the
            // resulting interval must remain symmetric about the whole field.
            const radius = Math.min(width / 2 - free.x, free.x + free.width - width / 2)
            if (2 * radius < minimumWidth(creatureLane) - 1e-7) continue
            const placed = rect(width / 2 - radius, free.y, 2 * radius, free.height)
            const score = scoreLane(creatureLane, placed)
            if (!best || score.full > bestScore.full
                || score.full === bestScore.full && (score.visible > bestScore.visible
                    || score.visible === bestScore.visible && (score.area > bestScore.area + 1e-7
                        || Math.abs(score.area - bestScore.area) < 1e-7 && placed.y < best.y))) {
                best = placed; bestScore = score
            }
        }
        return best || rect(width / 2, 0, 0, 0)
    }
    function padded(area) {
        return rect(area.x - gap / 2, area.y - gap / 2, area.width + gap, area.height + gap)
    }
    function effectiveObstacles() {
        if (obstacles.length || !widthForBand) return obstacles
        // Compatibility for the old monotonic right-edge exclusion callback.
        // Production callers provide exact rectangles, including center plates.
        const right = widthForBand(0, height)
        if (right >= width) return []
        let low = 0, high = height
        for (let step = 0; step < 24; ++step) {
            const middle = (low + high) / 2
            if (widthForBand(0, middle) < width) high = middle
            else low = middle
        }
        return [rect(right, low, width - right, height - low)]
    }
    function fixedLayout(faceCeiling) {
        const empty = rect(0, 0, 0, 0)
        const exclusions = effectiveObstacles().map(area => mirrored(area))
        const c = count(creatureLane), l = count(landLane), p = count(planeswalkerLane), o = count(otherLane)
        // Support rows share the rear width, not the entire field height. With
        // only one rear group the unused half is immediately returned to it.
        const rearWidth = Math.max(0, width - (l && o ? gap : 0))
        const naturalLand = naturalWidth(landLane), naturalOther = naturalWidth(otherLane)
        const share = naturalLand / Math.max(1, naturalLand + naturalOther)
        const landWidth = l && o ? Math.max(minimumWidth(landLane), Math.min(rearWidth - minimumWidth(otherLane),
            rearWidth * Math.max(0.35, Math.min(0.65, share)))) : l ? width : 0
        const otherWidth = o ? rearWidth - landWidth : 0
        const minimumFront = minimumRowHeight(creatureLane)
        const rearLimit = c || p ? Math.max(0, height - Math.min(height / 2,
            Math.max(minimumFront, p ? 80 * unit * planeswalkerLane.faceRatio : 0)) - gap) : height
        const wingWidth = c ? Math.min(naturalWidth(planeswalkerLane), Math.max(minimumWidth(planeswalkerLane),
            Math.min(width * 0.32, (width - minimumWidth(creatureLane)) / 2 - gap / 2))) : width
        const reserveFront = Math.max(minimumFront, p ? Math.min(height / 2, rowHeight(planeswalkerLane, wingWidth, faceCeiling)) : 0)
        const lands = support(landLane, rect(0, 0, landWidth, height), true, exclusions, rearLimit, minimumFront, faceCeiling)
        const others = support(otherLane, rect(width - otherWidth, 0, otherWidth, height), true, exclusions, rearLimit, reserveFront, faceCeiling)
        const rightExclusions = exclusions.concat(l ? [padded(lands)] : [], o ? [padded(others)] : [])
        const planeswalkers = support(planeswalkerLane, rect(width - wingWidth, 0, wingWidth, height), false,
            rightExclusions, height, 0, faceCeiling)
        // Exclude the stable lane allocations, not their live pile footprints.
        // Splitting ready/spent copies must not move the unrelated combat row.
        const occupied = [[landLane, lands], [otherLane, others], [planeswalkerLane, planeswalkers]]
            .filter(pair => count(pair[0])).map(pair => padded(pair[1]))
        const creatures = centeredCreature(exclusions.concat(occupied))
        const result = {creatures:mirrored(creatures), lands:l ? mirrored(lands) : empty,
            planeswalkers:p ? mirrored(planeswalkers) : empty, others:o ? mirrored(others) : empty,
            flow:"rows", key:"fixed-rows:" + faceCeiling, visible:0, covered:0, full:0, score:0,
            creatureFace:0, creatureVisible:0, supportFace:faceCeiling}
        for (const pair of [[creatureLane, creatures], [landLane, lands],
            [planeswalkerLane, planeswalkers], [otherLane, others]]) {
            const score = scoreLane(pair[0], pair[1])
            result.visible += score.visible; result.covered += score.covered; result.full += score.full
            result.score += score.area
            if (pair[0] === creatureLane) {
                result.creatureFace = score.face
                result.creatureVisible = score.visible
            }
        }
        return result
    }
    function listOptions() {
        // Face sizes can adapt inside the fixed rows. Prefer a useful combat
        // row before spending spare height on larger support art.
        return [108, 100, 92, 80].map(face => fixedLayout(face))
    }
    function applyPlacement() {
        let best = null
        for (const option of options) {
            // A 180-unit creature is already comfortably readable. Beyond
            // that, keep support cards at their shared size instead of trading
            // a visibly smaller land row for a slightly larger combat face.
            // This is a scoring target; spare room still permits 200-unit faces.
            const comfortable = Math.min(option.creatureFace, 180 * unit)
            const previous = best ? Math.min(best.creatureFace, 180 * unit) : 0
            if (!best || option.full > best.full
                || option.full === best.full && (option.creatureVisible > best.creatureVisible
                    || option.creatureVisible === best.creatureVisible && (comfortable > previous + 1e-7
                        || Math.abs(comfortable - previous) < 1e-7 && option.supportFace > best.supportFace)))
                best = option
        }
        if (best) placement = best
    }
}
