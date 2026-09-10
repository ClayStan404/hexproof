// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

QtObject {
    property string query: ""
    property var colors: []
    property var types: []
    property var manaValues: []
    property var rarities: []
    readonly property int activeCount: colors.length + types.length + manaValues.length + rarities.length
    readonly property bool active: activeCount > 0 || query.trim().length > 0

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
        const text = [card.name, card.displayName, card.typeLine, card.setCode, card.category].join(" ").toLowerCase()
        if (query.trim() && !text.includes(query.trim().toLowerCase())) return false
        const color = String(card.colors === undefined || (!card.colors && card.manaValue < 0)
                             ? "?" : card.colors).toUpperCase()
        if (colors.length && !colors.some(value => value === "C" ? color === ""
                : value === "M" ? color !== "?" && color.length > 1 : color.includes(value))) return false
        const type = String(card.typeLine || "").toLowerCase().split(/[—–]/)[0]
        const localized = {Creature: "生物", Planeswalker: "鹏洛客", Instant: "瞬间",
            Sorcery: "法术", Artifact: "神器", Enchantment: "结界", Battle: "战役", Land: "地"}
        if (types.length && !types.some(value => type.includes(value.toLowerCase())
                || (localized[value] && type.includes(localized[value])))) return false
        const mana = card.manaValue === undefined || Number(card.manaValue) < 0
                     ? "unknown" : Number(card.manaValue) >= 7 ? "7+" : String(Number(card.manaValue))
        if (manaValues.length && !manaValues.includes(mana)) return false
        if (rarities.length && !rarities.includes(String(card.rarity || "unknown").toLowerCase())) return false
        return true
    }
    function filter(cards) { return cards.filter(card => matches(card)) }
}
