// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma Translator: "TournamentLobby"

import QtQuick

QtObject {
    id: root

    property string mode: "mana"

    function typeKey(card) {
        const typeLine = card && card.typeLine ? card.typeLine : ""
        const normalized = String(typeLine).toLowerCase()
        if (normalized.indexOf("land") >= 0)
            return "land"
        if (normalized.indexOf("creature") >= 0)
            return "creature"
        if (normalized.indexOf("planeswalker") >= 0)
            return "planeswalker"
        if (normalized.indexOf("battle") >= 0)
            return "battle"
        if (normalized.indexOf("instant") >= 0)
            return "instant"
        if (normalized.indexOf("sorcery") >= 0)
            return "sorcery"
        if (normalized.indexOf("artifact") >= 0)
            return "artifact"
        if (normalized.indexOf("enchantment") >= 0)
            return "enchantment"
        return "other"
    }

    function manaKey(card) {
        if (typeKey(card) === "land")
            return "land"
        if (!card || card.manaValue === undefined)
            return "unknown"
        const value = Math.max(0, Number(card.manaValue || 0))
        if (value >= 7)
            return "7+"
        return String(Math.floor(value))
    }

    function manaRank(card) {
        const key = manaKey(card)
        if (key === "land")
            return 8
        if (key === "unknown")
            return 9
        if (key === "7+")
            return 7
        return Number(key)
    }

    function colorKey(card) {
        if (typeKey(card) === "land")
            return "land"
        if (!card || card.colors === undefined)
            return "unknown"
        const colors = String(card.colors || "").toUpperCase()
        if (colors.length === 0)
            return "colorless"
        if (colors.length > 1)
            return "multicolor"
        if ("WUBRG".indexOf(colors) >= 0)
            return colors
        return "unknown"
    }

    function rarityKey(card) {
        const rarity = card && card.rarity
                       ? String(card.rarity).toLowerCase() : ""
        if (rarity === "common" || rarity === "uncommon"
                || rarity === "rare" || rarity === "mythic") {
            return rarity
        }
        return "unknown"
    }

    function groupingKey(card) {
        if (mode === "mana")
            return manaKey(card)
        if (mode === "color")
            return colorKey(card)
        if (mode === "type")
            return typeKey(card)
        return "all"
    }

    function groupOrder() {
        if (mode === "mana")
            return ["0", "1", "2", "3", "4", "5", "6", "7+", "land", "unknown"]
        if (mode === "color")
            return ["W", "U", "B", "R", "G", "multicolor", "colorless",
                    "land", "unknown"]
        if (mode === "type")
            return ["creature", "planeswalker", "battle", "instant", "sorcery",
                    "artifact", "enchantment", "land", "other"]
        return ["all"]
    }

    function groupLabel(key) {
        const labels = {
            "0": qsTr("Mana value 0"), "1": qsTr("Mana value 1"),
            "2": qsTr("Mana value 2"), "3": qsTr("Mana value 3"),
            "4": qsTr("Mana value 4"), "5": qsTr("Mana value 5"),
            "6": qsTr("Mana value 6"), "7+": qsTr("Mana value 7+"),
            "W": qsTr("White"), "U": qsTr("Blue"), "B": qsTr("Black"),
            "R": qsTr("Red"), "G": qsTr("Green"),
            "multicolor": qsTr("Multicolor"),
            "colorless": qsTr("Colorless"),
            "creature": qsTr("Creatures"),
            "planeswalker": qsTr("Planeswalkers"),
            "battle": qsTr("Battles"), "instant": qsTr("Instants"),
            "sorcery": qsTr("Sorceries"), "artifact": qsTr("Artifacts"),
            "enchantment": qsTr("Enchantments"), "land": qsTr("Lands"),
            "other": qsTr("Other"), "unknown": qsTr("Unknown"),
            "all": qsTr("All cards")
        }
        return labels[key] || key
    }

    function compareCards(left, right) {
        if (mode === "color" || mode === "type") {
            const leftMana = manaRank(left)
            const rightMana = manaRank(right)
            if (leftMana !== rightMana)
                return leftMana - rightMana
        }
        return String(left.name || "").localeCompare(String(right.name || ""))
    }

    function matchesFilters(card, colorFilter, typeFilter, manaFilter,
                            rarityFilter) {
        if (colorFilter !== "all" && colorKey(card) !== colorFilter)
            return false
        if (typeFilter !== "all" && typeKey(card) !== typeFilter)
            return false
        if (manaFilter !== "all" && manaKey(card) !== manaFilter)
            return false
        return rarityFilter === "all" || rarityKey(card) === rarityFilter
    }

    function filterCards(cards, colorFilter, typeFilter, manaFilter,
                         rarityFilter) {
        const result = []
        for (let index = 0; index < cards.length; ++index) {
            if (matchesFilters(cards[index], colorFilter, typeFilter,
                               manaFilter, rarityFilter)) {
                result.push(cards[index])
            }
        }
        return result
    }

    function groupCards(cards) {
        const buckets = ({})
        for (let index = 0; index < cards.length; ++index) {
            const key = groupingKey(cards[index])
            if (!buckets[key])
                buckets[key] = []
            buckets[key].push(cards[index])
        }
        const groups = []
        const order = groupOrder()
        for (let index = 0; index < order.length; ++index) {
            const key = order[index]
            if (!buckets[key] || buckets[key].length === 0)
                continue
            buckets[key].sort((left, right) => root.compareCards(left, right))
            groups.push({"key": key, "label": groupLabel(key),
                         "cards": buckets[key]})
        }
        return groups
    }
}
