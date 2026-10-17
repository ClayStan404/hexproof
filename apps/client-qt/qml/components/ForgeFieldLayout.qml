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
    property var widthForBand: null
    readonly property real gap: 8 * unit
    readonly property var placement: arrange()

    function box(x, y, w, h) {
        if (widthForBand) w = Math.min(w, widthForBand(y, h) - x)
        return Qt.rect(x, y, Math.max(0, w), Math.max(0, h))
    }
    function splitSupport(area, vertical) {
        const empty = box(area.x, area.y, 0, 0)
        if (!landLane.stackCount) return {lands:empty, others:area}
        if (!otherLane.stackCount) return {lands:area, others:empty}
        const columns = Math.max(1, Math.floor((area.width - 6 * unit + gap) / (80 * unit + gap)))
        const landWeight = vertical ? Math.ceil(landLane.stackCount / columns) : landLane.stackCount
        const otherWeight = vertical ? Math.ceil(otherLane.stackCount / columns) : otherLane.stackCount
        const extent = Math.max(0, (vertical ? area.height : area.width) - gap)
        const minimum = Math.min(extent / 2, 86 * unit)
        const first = Math.max(minimum, Math.min(extent - minimum,
            extent * landWeight / (landWeight + otherWeight)))
        return vertical
            ? {lands:box(area.x, area.y + (nearSide ? extent - first + gap : 0), area.width, first),
               others:box(area.x, area.y + (nearSide ? 0 : first + gap), area.width, extent - first)}
            : {lands:box(area.x, area.y, first, area.height),
               others:box(area.x + first + gap, area.y, extent - first, area.height)}
    }
    function scoreLane(lane, area) {
        if (!lane.stackCount || area.width <= 0 || area.height <= 0) return {visible:0, area:0}
        const face = lane.fittedCardWidth(area.width, area.height)
        const columns = Math.max(1, Math.floor((area.width - 6 * unit + lane.gap)
            / (face + lane.gap) + 1e-7))
        const rows = Math.max(0, Math.floor((area.height - lane.edgeSpace)
            / (face * lane.faceRatio + lane.cellExtra) + 1e-7))
        const visible = face >= 80 * unit - 1e-7 ? Math.min(lane.stackCount, rows * columns) : 0
        return {visible:visible, area:visible * face * face}
    }
    function candidate(front, support, vertical, flow) {
        const back = splitSupport(support, vertical)
        const frontScore = scoreLane(creatureLane, front)
        const landScore = scoreLane(landLane, back.lands)
        const otherScore = scoreLane(otherLane, back.others)
        return {creatures:front, lands:back.lands, others:back.others, flow:flow,
            visible:frontScore.visible + landScore.visible + otherScore.visible,
            score:2 * frontScore.area + landScore.area + otherScore.area}
    }
    function better(next, previous) {
        return !previous || next.visible > previous.visible
            || next.visible === previous.visible && next.score > previous.score + 1e-7
    }
    function arrange() {
        const whole = box(0, 0, width, height), empty = box(0, 0, 0, 0)
        if (!landLane.stackCount && !otherLane.stackCount)
            return candidate(whole, empty, false, "front")
        if (!creatureLane.stackCount) {
            const horizontal = candidate(empty, whole, false, "support")
            const vertical = candidate(empty, whole, true, "support")
            return better(vertical, horizontal) ? vertical : horizontal
        }
        // Prefer full-width ranks with creatures toward the table center.
        // Side columns can reclaim height for larger creature faces.
        // Evaluate the lane's actual fitter, including combat/attachment space.
        let best = null
        for (const share of [0.24, 0.32, 0.40, 0.48, 0.56, 0.64, 0.72]) {
            const rear = Math.max(0, (height - gap) * share)
            const frontHeight = Math.max(0, height - gap - rear)
            const next = candidate(box(0, nearSide ? 0 : rear + gap, width, frontHeight),
                box(0, nearSide ? frontHeight + gap : 0, width, rear), false, "rows")
            if (better(next, best)) best = next
        }
        for (const share of [0.10, 0.14, 0.18, 0.24, 0.30, 0.38, 0.46, 0.54, 0.62, 0.70, 0.78, 0.86]) {
            const rear = Math.max(0, (width - gap) * share)
            const next = candidate(box(rear + gap, 0, width - rear - gap, height),
                box(0, 0, rear, height), true, "columns")
            if (better(next, best)) best = next
        }
        return best
    }
}
