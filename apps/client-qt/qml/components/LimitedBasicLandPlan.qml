// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

QtObject {
    readonly property var colors: ["W", "U", "B", "R", "G"]
    readonly property var names: ["Plains", "Island", "Swamp", "Mountain", "Forest"]

    function emptyBasics() {
        return {Plains: 0, Island: 0, Swamp: 0, Mountain: 0, Forest: 0}
    }

    function cardQuantity(card) {
        const count = card.count === undefined ? 1 : Number(card.count)
        return Number.isFinite(count) ? Math.max(0, Math.min(1000, Math.floor(count))) : 0
    }

    function landType(card) {
        // A spell/land MDFC is still a spell in this conservative suggestion.
        return String(card.typeLine || "").split("//")[0]
    }

    function basicIndex(card) {
        return names.indexOf(String(card.name || "").replace(/^Snow-Covered /, ""))
    }

    function isLand(card) {
        return /\bland\b/i.test(landType(card)) || basicIndex(card) >= 0
    }

    function landSources(card) {
        if (!isLand(card)) return {isLand: false, known: false, colors: []}
        const type = landType(card)
        const subtype = type.split(/[—–]/).slice(1).join(" ")
        const ordinary = basicIndex(card)
        const typed = colors.filter((color, index) => ordinary === index
            || new RegExp("\\b" + names[index] + "\\b", "i").test(subtype))
        // Catalog source metadata is authoritative when supplied. Never use
        // card colors or Commander color identity as a mana-production hint.
        if (card.producedMana !== undefined && card.producedMana !== null) {
            const supplied = Array.isArray(card.producedMana)
                ? card.producedMana.join("") : String(card.producedMana)
            if (/^[WUBRGC]*$/i.test(supplied)) {
                const value = supplied.toUpperCase()
                return {isLand: true, known: true,
                    colors: colors.filter(color => value.indexOf(color) >= 0)}
            }
        }
        if (typed.length > 0) return {isLand: true, known: true, colors: typed}
        // Only plain, unconditional tap-for-literal-mana lines are recognized
        // without source metadata. Fetches, any-color, counters, sacrifices and
        // conditional/restricted abilities remain unknown, not invented fixing.
        const text = String(card.oracleText || "").split("//")[0]
        const mana = []
        let recognized = false
        let uncertain = false
        for (const line of text.split(/\n/)) {
            if (!/\badd\b/i.test(line)) continue
            const match = line.trim().match(/^\{T\}: Add (\{[WUBRGC]\}(?:(?:,? (?:or |and )?)?\{[WUBRGC]\})*)\.$/i)
            if (!match) {
                uncertain = true
                continue
            }
            recognized = true
            const symbols = match[1].toUpperCase().match(/\{[WUBRGC]\}/g) || []
            for (const symbol of symbols) {
                const color = symbol.slice(1, -1)
                if (colors.indexOf(color) >= 0 && mana.indexOf(color) < 0) mana.push(color)
            }
        }
        return {isLand: true, known: recognized && !uncertain,
            colors: recognized && !uncertain ? colors.filter(color => mana.indexOf(color) >= 0) : []}
    }

    function cardDemand(card) {
        const weights = [0, 0, 0, 0, 0]
        // An MDFC whose front is a spell is selected as a spell, not as a land.
        if (isLand(card)) return weights
        if (card.manaCost !== undefined && card.manaCost !== null) {
            const symbols = String(card.manaCost).toUpperCase().match(/\{[^}]+\}/g) || []
            for (const symbol of symbols) {
                const parts = symbol.slice(1, -1).split("/")
                const indexes = colors.map((color, index) => parts.indexOf(color) >= 0 ? index : -1)
                    .filter(index => index >= 0)
                // Hybrid alternatives share one pip. Generic, snow, colorless,
                // variable, and Phyrexian life symbols are not extra colors.
                for (const index of indexes) weights[index] += 1 / indexes.length
            }
        } else {
            // Actual card colors are a limited fallback; never use color identity.
            const value = Array.isArray(card.cardColors)
                ? card.cardColors.join("") : String(card.cardColors || "")
            const normalized = value.toUpperCase()
            if (!/^[WUBRG]*$/.test(normalized)) return weights
            const indexes = colors.map((color, index) => normalized.indexOf(color) >= 0 ? index : -1)
                .filter(index => index >= 0)
            for (const index of indexes) weights[index] += 1 / indexes.length
        }
        return weights
    }

    function selection(cards) {
        const weights = [0, 0, 0, 0, 0]
        let physicalCount = 0
        let physicalLandCount = 0
        let unknownSourceLandCount = 0
        const lands = []
        for (const card of cards || []) {
            const count = cardQuantity(card)
            physicalCount += count
            const demand = cardDemand(card)
            for (let index = 0; index < weights.length; ++index)
                weights[index] += demand[index] * count
            const land = landSources(card)
            if (!land.isLand) continue
            physicalLandCount += count
            if (!land.known) unknownSourceLandCount += count
            else lands.push({count: count, colors: land.colors})
        }
        const sources = [0, 0, 0, 0, 0]
        for (const land of lands) {
            const relevant = colors.map((color, index) => weights[index] > 0
                && land.colors.indexOf(color) >= 0 ? index : -1).filter(index => index >= 0)
            // A flexible land is one source, shared across demanded colors;
            // it must not be counted as several independent land cards.
            for (const index of relevant) sources[index] += land.count / relevant.length
        }
        return {weights: weights, sources: sources, physicalCount: physicalCount,
            physicalLandCount: physicalLandCount, unknownSourceLandCount: unknownSourceLandCount}
    }

    function recommend(cards, targetSize) {
        const basics = emptyBasics()
        const selected = selection(cards)
        const weights = selected.weights
        const target = Number.isFinite(targetSize) ? Math.max(0, Math.floor(targetSize)) : 40
        const needed = Math.max(0, target - selected.physicalCount)
        const totalWeight = weights.reduce((total, weight) => total + weight, 0)
        const result = Object.assign({}, selected,
            {basics: basics, needed: needed, hasColors: totalWeight > 0})
        if (totalWeight <= 0 || needed === 0)
            return result
        // Fill the weighted source deficits. Colors already oversupplied by
        // physical lands receive no extra basics, without ever cutting cards.
        let active = weights.map((weight, index) => weight > 0 ? index : -1).filter(index => index >= 0)
        let scale = 0
        for (let pass = 0; pass < colors.length; ++pass) {
            const activeWeight = active.reduce((total, index) => total + weights[index], 0)
            const existing = active.reduce((total, index) => total + selected.sources[index], 0)
            scale = (needed + existing) / activeWeight
            const deficits = active.filter(index => scale * weights[index] > selected.sources[index])
            if (deficits.length === active.length) break
            active = deficits
        }
        let assigned = 0
        const remainders = []
        for (const index of active) {
            const exact = Math.max(0, scale * weights[index] - selected.sources[index])
            const count = Math.floor(exact)
            basics[names[index]] = count
            assigned += count
            remainders.push({index: index, fraction: exact - count})
        }
        // Largest-remainder apportionment keeps the exact total. WUBRG order
        // is a stable tie break, independent of card and display sorting order.
        remainders.sort((left, right) => right.fraction - left.fraction || left.index - right.index)
        for (let index = 0; index < needed - assigned; ++index)
            basics[names[remainders[index % remainders.length].index]]++
        return result
    }

    function analyze(cards, basics, targetSize) {
        const selected = selection(cards)
        let virtualCount = 0
        for (const name of names) virtualCount += cardQuantity({count: (basics || {})[name] || 0})
        const totalCards = selected.physicalCount + virtualCount
        const landCount = selected.physicalLandCount + virtualCount
        const target = Number.isFinite(targetSize) ? Math.max(0, Math.floor(targetSize)) : 40
        // A deliberately conservative, nonblocking reminder, not a mana-base
        // or legality validator. It also catches keeping all 60 spell picks.
        const minimumSuggestedLands = Math.ceil(totalCards / 3)
        return {totalCards: totalCards, landCount: landCount,
            minimumSuggestedLands: minimumSuggestedLands,
            lowLandCount: totalCards >= target && landCount < minimumSuggestedLands,
            unknownSourceLandCount: selected.unknownSourceLandCount}
    }
}
