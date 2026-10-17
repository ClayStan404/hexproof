// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
.pragma library

function finitePoint(point) {
    return !!point && Number.isFinite(point.x) && Number.isFinite(point.y)
}

function pointAt(start, control, end, t) {
    const u = 1 - t
    return {x:u * u * start.x + 2 * u * t * control.x + t * t * end.x,
            y:u * u * start.y + 2 * u * t * control.y + t * t * end.y}
}

function edgeRoots(start, control, end, edge) {
    const a = start - 2 * control + end
    const b = 2 * (control - start)
    const c = start - edge
    const epsilon = 1e-12 * Math.max(1, Math.abs(a), Math.abs(b), Math.abs(c))
    if (Math.abs(a) <= epsilon)
        return Math.abs(b) <= epsilon ? [] : [-c / b]
    const discriminant = b * b - 4 * a * c
    const tolerance = 1e-12 * Math.max(1, b * b, Math.abs(4 * a * c))
    if (discriminant < -tolerance) return []
    if (Math.abs(discriminant) <= tolerance) return [-b / (2 * a)]
    // This form avoids subtracting nearly equal terms for the small root.
    const q = -0.5 * (b + (b < 0 ? -1 : 1) * Math.sqrt(discriminant))
    return [q / a, c / q]
}

function expandedRects(rects, margin) {
    const result = []
    for (const rect of Array.isArray(rects) ? rects : []) {
        if (!rect || !Number.isFinite(rect.x) || !Number.isFinite(rect.y)
                || !Number.isFinite(rect.width) || !Number.isFinite(rect.height)
                || rect.width <= 0 || rect.height <= 0) continue
        const next = {x:rect.x - margin, y:rect.y - margin,
                      width:rect.width + 2 * margin, height:rect.height + 2 * margin}
        if (Number.isFinite(next.x + next.width) && Number.isFinite(next.y + next.height))
            result.push(next)
    }
    return result
}

function inside(point, rect) {
    return point.x >= rect.x && point.x <= rect.x + rect.width
        && point.y >= rect.y && point.y <= rect.y + rect.height
}

function visibleIntervals(start, control, end, rects) {
    const blocked = []
    const left = Math.min(start.x, control.x, end.x), right = Math.max(start.x, control.x, end.x)
    const top = Math.min(start.y, control.y, end.y), bottom = Math.max(start.y, control.y, end.y)
    for (const rect of rects) {
        // The quadratic stays in its control hull; most labels never meet it.
        if (rect.x > right || rect.x + rect.width < left
                || rect.y > bottom || rect.y + rect.height < top) continue
        const cuts = [0, 1]
        const roots = edgeRoots(start.x, control.x, end.x, rect.x)
            .concat(edgeRoots(start.x, control.x, end.x, rect.x + rect.width))
            .concat(edgeRoots(start.y, control.y, end.y, rect.y))
            .concat(edgeRoots(start.y, control.y, end.y, rect.y + rect.height))
        for (const t of roots)
            if (Number.isFinite(t) && t > 0 && t < 1) cuts.push(t)
        cuts.sort((a, b) => a - b)
        for (let i = 1; i < cuts.length; ++i) {
            const from = cuts[i - 1], to = cuts[i]
            if (to - from > 1e-10 && inside(pointAt(start, control, end, (from + to) / 2), rect))
                blocked.push([from, to])
        }
    }
    blocked.sort((a, b) => a[0] - b[0])
    const visible = []
    let cursor = 0
    for (const interval of blocked) {
        if (interval[0] > cursor + 1e-10) visible.push([cursor, interval[0]])
        cursor = Math.max(cursor, interval[1])
    }
    if (cursor < 1 - 1e-10) visible.push([cursor, 1])
    return visible
}

function segment(start, control, end, from, to) {
    const first = pointAt(start, control, end, from)
    const last = pointAt(start, control, end, to)
    // Exact restriction of the original quadratic, not a polyline fit.
    return {start:first, end:last, control:{
        x:first.x + (to - from) * ((1 - from) * (control.x - start.x) + from * (end.x - control.x)),
        y:first.y + (to - from) * ((1 - from) * (control.y - start.y) + from * (end.y - control.y))}}
}

function pathFor(start, control, end, intervals) {
    const commands = []
    for (const interval of intervals) {
        const part = segment(start, control, end, interval[0], interval[1])
        commands.push("M " + part.start.x + " " + part.start.y + " Q "
            + part.control.x + " " + part.control.y + " " + part.end.x + " " + part.end.y)
    }
    return commands.join(" ")
}

function triangleMeetsRect(points, rect) {
    if (rect.x > Math.max(points[0].x, points[1].x, points[2].x)
            || rect.x + rect.width < Math.min(points[0].x, points[1].x, points[2].x)
            || rect.y > Math.max(points[0].y, points[1].y, points[2].y)
            || rect.y + rect.height < Math.min(points[0].y, points[1].y, points[2].y)) return false
    const corners = [{x:rect.x, y:rect.y}, {x:rect.x + rect.width, y:rect.y},
                     {x:rect.x + rect.width, y:rect.y + rect.height}, {x:rect.x, y:rect.y + rect.height}]
    const axes = [{x:1, y:0}, {x:0, y:1}]
    for (let i = 0; i < 3; ++i) {
        const a = points[i], b = points[(i + 1) % 3]
        axes.push({x:a.y - b.y, y:b.x - a.x})
    }
    for (const axis of axes) {
        const triangle = points.map(point => point.x * axis.x + point.y * axis.y)
        const box = corners.map(point => point.x * axis.x + point.y * axis.y)
        if (Math.max(...triangle) < Math.min(...box) || Math.max(...box) < Math.min(...triangle))
            return false
    }
    return true
}

function clippedArrow(start, control, end, rects, strokeWidth, tipSize, clearance) {
    const empty = {path:"", intervals:[], tipVisible:false}
    if (!finitePoint(start) || !finitePoint(control) || !finitePoint(end)
            || (start.x === end.x && start.y === end.y)
            || !Number.isFinite(strokeWidth) || strokeWidth <= 0
            || !Number.isFinite(tipSize) || tipSize <= 0) return empty
    const margin = Number.isFinite(clearance) ? Math.max(0, clearance) : 1
    const intervals = visibleIntervals(start, control, end, expandedRects(rects, strokeWidth / 2 + margin))
    const angle = Math.atan2(end.y - control.y, end.x - control.x)
    const tip = [end,
        {x:end.x - tipSize * Math.cos(angle - 0.45), y:end.y - tipSize * Math.sin(angle - 0.45)},
        {x:end.x - tipSize * Math.cos(angle + 0.45), y:end.y - tipSize * Math.sin(angle + 0.45)}]
    // A normal target keeps its arrowhead. Suppress only a head whose filled
    // triangle itself meets protected text, including a corner-only overlap.
    const tipVisible = !expandedRects(rects, margin).some(rect => triangleMeetsRect(tip, rect))
    return {path:pathFor(start, control, end, intervals), intervals:intervals, tipVisible:tipVisible}
}
