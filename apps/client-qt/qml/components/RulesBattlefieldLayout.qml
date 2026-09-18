// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

QtObject {
    id: root

    property string gameId: ""
    property var customPositions: ({})
    property int latestOrder: 0
    readonly property bool hasCustomPositions: Object.keys(customPositions).length > 0

    onGameIdChanged: reset()

    function key(seat, cardId) {
        return JSON.stringify([seat, String(cardId)])
    }

    function bounded(value, maximum) {
        return Math.max(0, Math.min(Math.max(0, maximum), value))
    }

    function category(card, catalog) {
        // Projected P/T also puts animated lands and face-down creatures on
        // the combat row without consulting a hidden printed identity.
        if (String(card.power || "").length || String(card.toughness || "").length)
            return "creature"
        if (!card.visibleIdentity || card.faceDown || !card.name || !catalog
                || typeof catalog.cardTypeLine !== "function")
            return "other"
        let typeLine = String(catalog.cardTypeLine(
            card.name, card.setCode || "", card.collectorNumber || "")).toLowerCase()
        typeLine = typeLine.split(" // ")[0].split(/[—–～〜]/)[0]
        return /\bland\b/.test(typeLine) || typeLine.includes("地") ? "land" : "other"
    }

    // Battlefield copies that share a public face and public state occupy one
    // pile. Hidden, face-down, and zone-browser cards stay unique so a viewer
    // can still pick one of several identical objects by id.
    function stackKey(card, zone) {
        const id = String(card && card.cardId ? card.cardId : "")
        if (!card || (zone && zone !== "battlefield"))
            return "id:" + id
        if (!card.visibleIdentity || card.faceDown || !card.name)
            return "id:" + id
        return [String(card.name).trim().toLocaleLowerCase(),
                card.token === true ? "token" : "card",
                card.tapped === true ? "tapped" : "untapped",
                card.attacking === true ? "attacking" : "ready",
                String(card.power || ""),
                String(card.toughness || ""),
                String(card.countersSummary || ""),
                String(card.damage || 0),
                String(card.attachedTo || ""),
                String(card.exiledCardCount || 0)].join("\u001f")
    }

    function remember(seat, cardId, x, y, availableWidth, availableHeight) {
        const positions = Object.assign({}, customPositions)
        positions[key(seat, cardId)] = {
            x: availableWidth > 0 ? bounded(x, availableWidth) / availableWidth : 0,
            y: availableHeight > 0 ? bounded(y, availableHeight) / availableHeight : 0,
            order: ++latestOrder
        }
        customPositions = positions
    }

    function position(seat, cardId, automatic, availableWidth, availableHeight) {
        const saved = customPositions[key(seat, cardId)]
        return saved ? {x: bounded(saved.x * availableWidth, availableWidth),
                        y: bounded(saved.y * availableHeight, availableHeight)}
                     : automatic || {x: 0, y: 0}
    }

    function hasSeatPositions(seat) {
        return Object.keys(customPositions).some(value => JSON.parse(value)[0] === seat)
    }

    function stackingOrder(seat, cardId) {
        const saved = customPositions[key(seat, cardId)]
        return saved ? saved.order + 1 : 1
    }

    function reset(seat) {
        if (seat === undefined) {
            customPositions = ({})
            latestOrder = 0
            return
        }
        const positions = Object.assign({}, customPositions)
        Object.keys(positions).forEach(value => {
            if (JSON.parse(value)[0] === seat)
                delete positions[value]
        })
        customPositions = positions
    }

    function retain(cardKeys) {
        const positions = ({})
        let changed = false
        Object.keys(customPositions).forEach(value => {
            if (cardKeys[value])
                positions[value] = customPositions[value]
            else
                changed = true
        })
        if (changed)
            customPositions = positions
    }

    function arrange(cards, width, height, footprint, gap, frontAtTop) {
        const groups = {creature: [], land: [], other: []}
        cards.forEach(card => groups[card.category || "other"].push(card))
        Object.keys(groups).forEach(group => groups[group].sort((a, b) => {
            const names = String(a.sortName || "").localeCompare(String(b.sortName || ""))
            return names || String(a.cardId).localeCompare(String(b.cardId))
        }))
        const columns = Math.max(1, Math.floor((width + gap) / (footprint + gap)))
        const rearCount = groups.land.length + groups.other.length
        let landColumns = groups.land.length ? columns : 0
        if (groups.land.length && groups.other.length && columns > 1) {
            landColumns = Math.max(1, Math.min(groups.land.length, columns - 1,
                Math.round(columns * groups.land.length / rearCount)))
        }
        const otherColumns = groups.other.length ? Math.max(1, columns - landColumns) : 0
        const stackedRear = groups.land.length && groups.other.length && columns === 1
        const labelHeight = gap * 2
        const rowHeight = footprint + gap
        const frontRows = Math.ceil(groups.creature.length / columns)
        const landRows = landColumns ? Math.ceil(groups.land.length / landColumns) : 0
        const otherRows = otherColumns ? Math.ceil(groups.other.length / otherColumns) : 0
        const frontHeight = frontRows ? frontRows * rowHeight + labelHeight : 0
        const rearRows = stackedRear ? landRows + otherRows : Math.max(landRows, otherRows)
        const rearHeight = rearRows ? rearRows * rowHeight + labelHeight * (stackedRear ? 2 : 1) : 0
        const contentHeight = Math.max(height, frontHeight + rearHeight + (frontRows && rearRows ? gap : 0))
        const frontY = frontAtTop ? 0 : contentHeight - frontHeight
        const rearY = frontAtTop ? contentHeight - rearHeight : 0
        const positions = ({})
        const sections = []

        function place(group, count, x, y, sectionWidth) {
            if (!groups[group].length)
                return
            sections.push({category: group, x: x, y: y, width: sectionWidth})
            groups[group].forEach((card, index) => {
                positions[card.cardId] = {
                    x: x + (index % count) * (footprint + gap),
                    y: y + labelHeight + Math.floor(index / count) * rowHeight
                }
            })
        }
        place("creature", columns, 0, frontY, width)
        place("land", landColumns || 1, 0, rearY,
              groups.other.length && !stackedRear ? landColumns * rowHeight - gap : width)
        place("other", otherColumns || 1,
              groups.land.length && !stackedRear ? landColumns * rowHeight : 0,
              rearY + (stackedRear ? landRows * rowHeight + labelHeight : 0),
              groups.land.length && !stackedRear ? width - landColumns * rowHeight : width)
        return {positions: positions, sections: sections, contentHeight: contentHeight}
    }
}
