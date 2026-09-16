// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import "CardTypes.js" as CardTypes

QtObject {
    property string query: ""
    readonly property string normalizedQuery: query.trim().toLowerCase()
    property var colors: []
    property var types: []
    property var manaValues: []
    property var rarities: []
    readonly property int activeCount: colors.length + types.length + manaValues.length + rarities.length
    readonly property bool active: activeCount > 0 || normalizedQuery.length > 0

    function toggle(category, value) {
        const values = this[category].slice()
        const index = values.indexOf(value)
        if (index < 0) values.push(value)
        else values.splice(index, 1)
        this[category] = values
    }
    function reset() {
        colors = []; types = []; manaValues = []; rarities = []
    }
    function matches(card) {
        if (normalizedQuery.length > 0) {
            const text = [card.name, card.displayName, card.typeLine, card.setCode,
                          card.collectorNumber, card.category].join(" ").toLowerCase()
            if (!text.includes(normalizedQuery)) return false
        }
        if (colors.length > 0) {
            const color = String(card.colors === undefined || card.colors === null
                                 || (!card.colors && card.manaValue < 0)
                                 ? "?" : card.colors).toUpperCase()
            if (!colors.every(value => value === "C" ? color === ""
                    : value === "M" ? color !== "?" && color.length > 1 : color.includes(value))) return false
        }
        if (types.length && !types.some(value => CardTypes.hasType(card, value))) return false
        if (manaValues.length > 0) {
            const mana = card.manaValue === undefined || Number(card.manaValue) < 0
                         ? "unknown" : Number(card.manaValue) >= 7 ? "7+" : String(Number(card.manaValue))
            if (!manaValues.includes(mana)) return false
        }
        if (rarities.length && !rarities.includes(String(card.rarity || "unknown").toLowerCase())) return false
        return true
    }
    function filter(cards) {
        return active ? cards.filter(card => matches(card)) : cards
    }
}
