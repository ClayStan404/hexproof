// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "ForgeFieldLayout"

    Component {
        id: mockLane
        QtObject {
            property int stackCount: 0
            property var hostCards: []
            property int layoutStackCount: -1
            property string category: "other"
            property bool alignBottom: false
            property bool alignRight: false
            property real maxFaceWidth: category === "creature" ? 200 : 108
            property real headerHeight: 0
            property real pileLead: 0
            property real edgeSpace: 5
            property real faceRatio: 0.93
            property real layoutCellExtra: 10
            property real startInset: 0
            property real minimumAllocationWidth: 86

            // A small independent rectangular-grid model: the solver chooses
            // zones, while this test double only fits cards inside one zone.
            function layoutGrid(w, h) {
                const available = Math.max(0, w - minimumAllocationWidth + 80)
                const floor = Math.min(80, available)
                let face = floor
                for (let columns = 1; columns <= Math.max(1, stackCount); ++columns) {
                    const rows = Math.ceil(stackCount / columns)
                    const fitted = Math.min(maxFaceWidth, (available - (columns - 1) * 8) / columns,
                        ((h - edgeSpace) / Math.max(1, rows) - layoutCellExtra) / faceRatio)
                    if (fitted >= floor) face = Math.max(face, fitted)
                }
                const columns = Math.max(1, Math.floor((available + 8) / (face + 8)))
                const used = Math.min(stackCount, columns) * (face + 8) - 8
                const extent = Math.ceil(stackCount / columns) * (face * faceRatio + layoutCellExtra) + edgeSpace
                return {face:face, columns:columns, height:extent,
                    lead:alignRight ? Math.max(0, w - used - 6)
                        : category === "creature" ? Math.max(0, (w - used) / 2 - 3) : 0,
                    top:alignBottom ? Math.max(0, h - extent) : 0}
            }
            function layoutFootprint(w, h) {
                const grid = layoutGrid(w, h)
                if (stackCount > grid.columns || grid.height > h + 1e-7) return null
                return Qt.rect(3 + grid.lead, grid.top,
                    stackCount * (grid.face + 8) - 8, grid.height)
            }
            function layoutMinimumHeight(w) {
                if (!stackCount) return 0
                const columns = Math.floor((w - minimumAllocationWidth + 80 + 8) / 88)
                return columns > 0
                    ? Math.ceil((layoutStackCount >= 0 ? layoutStackCount : Math.max(stackCount, hostCards.length)) / columns) * (80 * faceRatio + 10) + 5
                    : Infinity
            }
            function layoutMinimumWidth() { return minimumAllocationWidth }
        }
    }
    Component {
        id: layoutComponent
        ForgeFieldLayout {}
    }
    function fixture(counts, nearSide, dimensions, obstacles) {
        const lanes = {}
        for (const key of ["creatures", "lands", "planeswalkers", "others"]) {
            const count = counts[key] || 0
            lanes[key] = createTemporaryObject(mockLane, testCase, {
                stackCount:count, hostCards:Array.from({length:count}, (_, index) => index),
                category:key === "creatures" ? "creature" : key,
                alignBottom:key === "creatures" || key === "planeswalkers" ? !nearSide : nearSide,
                alignRight:key === "planeswalkers" || key === "others"
            })
            verify(lanes[key] !== null)
        }
        const layout = createTemporaryObject(layoutComponent, testCase, {
            width:dimensions ? dimensions.width : 1000, height:dimensions ? dimensions.height : 440,
            unit:1, nearSide:nearSide, creatureLane:lanes.creatures, landLane:lanes.lands,
            planeswalkerLane:lanes.planeswalkers, otherLane:lanes.others,
            obstacles:obstacles || [], preferCenteredRows:true
        })
        verify(layout !== null)
        return {layout:layout, lanes:lanes}
    }
    function occupied(fixture, key) {
        const area = fixture.layout.placement[key], lane = fixture.lanes[key]
        const footprint = lane.layoutFootprint(area.width, area.height)
        return footprint ? Qt.rect(area.x + footprint.x, area.y + footprint.y,
            footprint.width, footprint.height) : area
    }
    function intersects(a, b) {
        return a.width > 0 && b.width > 0 && a.height > 0 && b.height > 0
            && a.x < b.x + b.width - 0.01 && a.x + a.width > b.x + 0.01
            && a.y < b.y + b.height - 0.01 && a.y + a.height > b.y + 0.01
    }
    function verifySafe(fixture) {
        const layout = fixture.layout, keys = ["creatures", "lands", "planeswalkers", "others"]
        for (let index = 0; index < keys.length; ++index) {
            const key = keys[index], lane = fixture.lanes[key]
            if (!lane.stackCount) continue
            const area = layout.placement[key], body = occupied(fixture, key)
            verify(Number.isFinite(area.x + area.y + area.width + area.height), key + " finite allocation")
            verify(area.width >= 86 && area.height >= 32, key + " retains a readable scrolling viewport: " + JSON.stringify(area))
            verify(body.x >= -0.01 && body.y >= -0.01
                && body.x + body.width <= layout.width + 0.01
                && body.y + body.height <= layout.height + 0.01, key + " stays inside the field")
            verify(lane.layoutGrid(area.width, area.height).face >= 80, key + " keeps the readable floor")
            for (const obstacle of layout.obstacles)
                verify(!intersects(body, obstacle), key + " avoids " + JSON.stringify(obstacle) + ": " + JSON.stringify(body))
            for (let other = index + 1; other < keys.length; ++other)
                if (fixture.lanes[keys[other]].stackCount)
                    verify(!intersects(body, occupied(fixture, keys[other])), key + " does not overlap " + keys[other])
        }
    }
    function test_compassPositions_data() {
        return [{tag:"near", nearSide:true}, {tag:"far", nearSide:false},
            {tag:"dense-near", nearSide:true, dense:true}, {tag:"dense-far", nearSide:false, dense:true}]
    }
    function test_compassPositions(data) {
        const f = fixture(data.dense ? {creatures:24, lands:12, planeswalkers:4, others:12}
            : {creatures:2, lands:2, planeswalkers:1, others:2}, data.nearSide)
        verifySafe(f)
        const c = occupied(f, "creatures"), l = occupied(f, "lands")
        const p = occupied(f, "planeswalkers"), o = occupied(f, "others")
        verify(l.x < o.x, "Lands remain on the left of other permanents")
        verify(c.x + c.width / 2 < p.x + p.width / 2, "Planeswalkers remain to the right of creatures")
        verify(data.nearSide ? p.y < o.y : p.y > o.y, "Only the front/rear axis mirrors")
    }
    function test_rightWingNeverMovesSingleCreatureAxis_data() {
        return [{tag:"near-wide", nearSide:true, width:1800},
            {tag:"far-wide", nearSide:false, width:1800},
            {tag:"near-compact", nearSide:true, width:430},
            {tag:"far-compact", nearSide:false, width:430}]
    }
    function test_rightWingNeverMovesSingleCreatureAxis(data) {
        const f = fixture({creatures:1, lands:5, planeswalkers:2, others:3}, data.nearSide,
            {width:data.width, height:340})
        verifySafe(f)
        const body = occupied(f, "creatures")
        fuzzyCompare(body.x + body.width / 2, data.width / 2, 0.01)
        for (const group of ["planeswalkers", "others"]) {
            const area = f.layout.placement[group]
            fuzzyCompare(area.x + area.width, data.width, 0.01,
                "An unobstructed right wing remains attached to the field edge")
        }
    }
    function test_absentCategoriesLeaveNoOverlappingRegions_data() {
        return Array.from({length:15}, (_, index) => ({tag:"groups-" + (index + 1), mask:index + 1}))
    }
    function test_absentCategoriesLeaveNoOverlappingRegions(data) {
        const counts = {}
        const keys = ["creatures", "lands", "planeswalkers", "others"]
        for (let index = 0; index < keys.length; ++index)
            counts[keys[index]] = data.mask & (1 << index) ? 4 : 0
        const f = fixture(counts, true, {width:700, height:340})
        verifySafe(f)
        for (let index = 0; index < keys.length; ++index)
            for (let next = index + 1; next < keys.length; ++next)
                verify(!intersects(f.layout.placement[keys[index]], f.layout.placement[keys[next]]),
                    keys[index] + " and " + keys[next] + " keep separate lane allocations")
    }
    function test_readableCreatureKeepsAllSupportCategoriesAtTheirSharedSize_data() {
        return [{tag:"near", nearSide:true}, {tag:"far", nearSide:false}]
    }
    function test_readableCreatureKeepsAllSupportCategoriesAtTheirSharedSize(data) {
        const f = fixture({creatures:1, lands:5, planeswalkers:2, others:3}, data.nearSide,
            {width:1800, height:306})
        verifySafe(f)
        compare(f.layout.placement.supportFace, 108)
        verify(f.layout.placement.creatureFace >= 180 && f.layout.placement.creatureFace < 200,
            "A readable creature need not reach its maximum at the expense of every support row")
        for (const key of ["lands", "planeswalkers", "others"]) {
            const area = f.layout.placement[key]
            fuzzyCompare(f.lanes[key].layoutGrid(area.width, area.height).face, 108, 0.01,
                key + " retains the normal support size")
        }
    }
    function test_emptyZonesReleaseSpace() {
        const f = fixture({creatures:1}, true)
        compare(f.layout.placement.creatures, Qt.rect(0, 0, 1000, 440))
        const body = occupied(f, "creatures")
        fuzzyCompare(body.width, 200, 0.01)
        fuzzyCompare(body.x + body.width / 2, 500, 0.01)
        f.layout.planeswalkerLane = null
        compare(f.layout.placement.creatures, Qt.rect(0, 0, 1000, 440))
    }
    function test_centerObstaclePreservesItsRightPocket_data() {
        return [{tag:"near", nearSide:true}, {tag:"far", nearSide:false}]
    }
    function test_centerObstaclePreservesItsRightPocket(data) {
        const obstacle = Qt.rect(410, data.nearSide ? 270 : 0, 180, 170)
        const f = fixture({creatures:2, lands:2, planeswalkers:1, others:2}, data.nearSide, null, [obstacle])
        verifySafe(f)
        const other = occupied(f, "others")
        verify(other.x >= obstacle.x + obstacle.width, "Rear right cards use the life plate's right side: " + JSON.stringify(other))
    }
    function test_dockKeepsOtherPermanentsOnTheRight_data() {
        return [{tag:"sparse", count:2}, {tag:"dense", count:18}]
    }
    function test_dockKeepsOtherPermanentsOnTheRight(data) {
        const dock = Qt.rect(670, 265, 330, 175)
        const f = fixture({creatures:8, lands:5, planeswalkers:2, others:data.count}, true, null, [dock])
        verifySafe(f)
        const other = occupied(f, "others")
        const land = occupied(f, "lands")
        verify(other.x >= land.x + land.width, "Other permanents keep the right of the usable rear area")
        if (data.count === 2) {
            verify(other.x + other.width / 2 > 500, "Sparse right groups retain the field's right side")
            verify(other.y + other.height <= dock.y + 0.01, "A sparse right group fits above the dock")
        } else {
            const area = f.layout.placement.others, right = area.x + area.width
            verify(Math.abs(right - dock.x) < 0.01 || Math.abs(right - f.layout.width) < 0.01,
                "Dense right groups keep the available right edge beside or above the dock")
            compare(f.layout.placement.full, 4)
        }
    }
    function test_crowdedCreaturesPreserveTheWholeFieldCenter() {
        const f = fixture({creatures:16}, true, {width:1000, height:240}, [Qt.rect(750, 100, 250, 140)])
        verifySafe(f)
        const area = f.layout.placement.creatures
        fuzzyCompare(area.x + area.width / 2, 500, 0.01,
            "A taller side pocket cannot move the combat row away from the field center")
        compare(f.layout.placement.full, 1)
    }
    function test_rightDockRetainsCenteredCreaturesAndCompleteRightWing() {
        const f = fixture({creatures:1, lands:5, planeswalkers:2, others:3}, true,
            {width:924.55, height:299.08}, [Qt.rect(450, 220, 500, 100)])
        f.lanes.lands.hostCards = [0, 1, 2, 3, 4, 5]
        verifySafe(f)
        compare(f.layout.placement.covered, 4)
        compare(f.layout.placement.full, 4)
        const c = occupied(f, "creatures"), l = occupied(f, "lands")
        const p = occupied(f, "planeswalkers"), o = occupied(f, "others")
        fuzzyCompare(c.x + c.width / 2, f.layout.width / 2, 0.01)
        fuzzyCompare(f.layout.placement.others.x + f.layout.placement.others.width, f.layout.width, 0.01)
        fuzzyCompare(f.layout.placement.others.y + f.layout.placement.others.height, 220, 0.01)
        verify(l.x + l.width / 2 < o.x + o.width / 2)
        verify(p.y < o.y)
        for (const key of ["creatures", "lands", "planeswalkers", "others"]) {
            const area = f.layout.placement[key], lane = f.lanes[key]
            verify(area.height >= lane.layoutGrid(area.width, area.height).face * lane.faceRatio,
                key + " must reveal a complete card instead of just its name")
        }
    }
    function test_matchingLandsStayHorizontalOnBothSides() {
        const counts = {creatures:1, lands:5, planeswalkers:2, others:3}
        const near = fixture(counts, true, {width:1800, height:440}, [Qt.rect(825, 315, 150, 125)])
        const far = fixture(counts, false, {width:1800, height:440}, [Qt.rect(825, 0, 150, 125)])
        for (const f of [near, far]) {
            verifySafe(f)
            const area = f.layout.placement.lands
            const grid = f.lanes.lands.layoutGrid(area.width, area.height)
            verify(grid.columns >= 5, "Five lands keep one horizontal row despite a taller right wing")
            const creature = occupied(f, "creatures")
            fuzzyCompare(creature.x + creature.width / 2, 900, 0.01,
                "Right-front planeswalkers do not shift the creature axis")
        }
        fuzzyCompare(near.layout.placement.lands.width, far.layout.placement.lands.width, 0.01)
        fuzzyCompare(near.layout.placement.lands.height, far.layout.placement.lands.height, 0.01)
    }
    function test_singleRightGroupPrefersACompleteFaceToANameStrip_data() {
        return [{tag:"planeswalker", key:"planeswalkers"}, {tag:"artifact", key:"others"}]
    }
    function test_singleRightGroupPrefersACompleteFaceToANameStrip(data) {
        const counts = {}; counts[data.key] = 1
        const f = fixture(counts, true, {width:1000, height:300}, [Qt.rect(670, 33, 330, 267)])
        verifySafe(f)
        compare(f.layout.placement.full, 1)
        const body = occupied(f, data.key)
        verify(body.height > 33 && body.x + body.width <= 670,
            "The complete card uses the available side pocket instead of the short top strip")
    }
    function test_compactFieldRetainsAllFourGroups_data() {
        return [{tag:"near", nearSide:true}, {tag:"far", nearSide:false}]
    }
    function test_compactFieldRetainsAllFourGroups(data) {
        const f = fixture({creatures:16, lands:8, planeswalkers:3, others:8}, data.nearSide,
            {width:430, height:300}, [Qt.rect(310, 220, 120, 80)])
        verifySafe(f)
        compare(f.layout.placement.covered, 4)
    }
    function test_publicHostBudgetKeepsUnrelatedCreatureStill_data() {
        return [{tag:"near", nearSide:true}, {tag:"far", nearSide:false}]
    }
    function test_shortFieldKeepsCardCentersReachable_data() {
        return [{tag:"near", nearSide:true}, {tag:"far", nearSide:false}]
    }
    function test_shortFieldKeepsCardCentersReachable(data) {
        const f = fixture({creatures:1, lands:5, planeswalkers:2, others:4}, data.nearSide,
            {width:850, height:110})
        for (const key of ["creatures", "lands", "planeswalkers", "others"]) {
            const area = f.layout.placement[key], lane = f.lanes[key]
            const face = lane.layoutGrid(area.width, area.height).face
            verify(area.height > face * lane.faceRatio / 2,
                "Revealing any card in " + key + " must expose its center: " + JSON.stringify(area))
        }
    }
    function test_rightAlignedPilesReceiveTheirWholeWidthBudget() {
        const f = fixture({creatures:1, lands:1, planeswalkers:3, others:3}, true,
            {width:300, height:340})
        f.lanes.planeswalkers.minimumAllocationWidth = 103
        f.lanes.others.minimumAllocationWidth = 103
        for (const option of f.layout.options)
            for (const key of ["creatures", "lands", "planeswalkers", "others"])
                verify(option[key].width >= f.lanes[key].layoutMinimumWidth() - 0.01,
                    option.key + " reserves the complete readable pile width for " + key)
        verifySafe(f)
    }
    function test_publicHostBudgetKeepsUnrelatedCreatureStill(data) {
        const f = fixture({creatures:1, lands:1, others:1}, data.nearSide, {width:300, height:340})
        f.lanes.lands.hostCards = [0, 1]
        f.lanes.lands.edgeSpace = 11
        const before = occupied(f, "creatures")
        for (const count of [2, 1]) {
            f.lanes.lands.stackCount = count
            f.lanes.lands.edgeSpace = count === 2 ? 7 : 11
            const after = occupied(f, "creatures")
            for (const key of ["x", "y", "width", "height"])
                fuzzyCompare(after[key], before[key], 0.01, "Pile split cannot change creature " + key)
        }
    }
    function test_creaturePileChangesKeepCrowdedRearRowsStill() {
        const f = fixture({creatures:1, lands:20, others:20}, true, {width:1000, height:220})
        f.lanes.creatures.hostCards = [0, 1]
        const lands = f.layout.placement.lands, others = f.layout.placement.others
        f.lanes.creatures.stackCount = 2
        f.lanes.creatures.pileLead = 9
        f.lanes.creatures.edgeSpace = 11
        compare(f.layout.placement.lands, lands, "A creature pile split cannot resize crowded land rows")
        compare(f.layout.placement.others, others, "A creature pile split cannot resize other support rows")
    }
    function test_largeIdenticalPileOnlyBudgetsReadyAndSpentSlots() {
        const f = fixture({creatures:2, lands:1, others:1}, true, {width:1000, height:340})
        f.lanes.lands.hostCards = Array.from({length:100}, (_, index) => index)
        f.lanes.lands.layoutStackCount = 2
        verifySafe(f)
        const before = f.layout.placement.creatures, land = f.layout.placement.lands
        verify(land.height < 130, "A hundred identical lands still use a single rear row")
        verify(f.lanes.creatures.layoutGrid(before.width, before.height).face >= 150,
            "A large collapsed pile cannot consume the creature row")
        f.lanes.lands.stackCount = 2
        compare(f.layout.placement.creatures, before, "The first spent copy uses the already reserved slot")
    }
    function test_legacyBandCallbackRemainsSupported() {
        const f = fixture({others:6}, true, {width:700, height:300})
        f.layout.widthForBand = function(y, height) { return y + height > 180 ? 320 : 700 }
        verify(!intersects(occupied(f, "others"), Qt.rect(320, 180, 380, 120)),
            "The legacy callback still excludes its occupied lower-right corner")
        f.layout.obstacles = [Qt.rect(400, 180, 150, 120)]
        verifySafe(f)
        const area = f.layout.placement.others
        fuzzyCompare(area.x + area.width, 700, 0.01, "Local obstacles keep the field's right edge available")
        verify(area.width > 320 || area.x >= 550, "The legacy left-only limit no longer cuts away free right space")
    }
}
