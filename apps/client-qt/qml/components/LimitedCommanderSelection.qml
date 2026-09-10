// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma Translator: "TournamentLobby"
import QtQuick

QtObject {
    function sanitize(ids, cards) {
        if (!ids || typeof ids === "string" || typeof ids.length !== "number") return []
        const byId = new Map(cards.map(card => [card.instanceId, card]))
        const seen = new Set()
        const result = []
        for (const id of ids) {
            const card = byId.get(id)
            if (!card) continue
            if (seen.has(id)) continue
            seen.add(id)
            result.push(id)
            if (result.length === 2) break
        }
        return result
    }

    function canSelect(id, ids, cards) {
        if (ids.indexOf(id) >= 0) return true
        if (ids.length >= 2) return false
        return cards.some(card => card.instanceId === id)
    }

    function isPiper(card) {
        return String(card.name || "").trim().toLowerCase() === "the prismatic piper"
    }

    function colorFor(instanceId, colors) {
        const choice = (colors || []).find(value => value && value.instanceId === instanceId)
        return choice && /^[WUBRG]$/.test(String(choice.color || "")) ? choice.color : ""
    }

    function sanitizeColors(colors, ids, cards) {
        const values = colors && typeof colors !== "string" && typeof colors.length === "number" ? colors : []
        return cards.filter(card => ids.indexOf(card.instanceId) >= 0 && isPiper(card))
            .map(card => ({instanceId: card.instanceId, color: colorFor(card.instanceId, values)}))
            .filter(choice => choice.color).sort((left, right) => left.instanceId.localeCompare(right.instanceId))
    }

    function colorsValid(colors, ids, cards) {
        return cards.filter(card => ids.indexOf(card.instanceId) >= 0 && isPiper(card))
            .every(card => colorFor(card.instanceId, colors) !== "")
    }

    function withColor(card, colors) {
        if (!isPiper(card)) return card
        const color = colorFor(card.instanceId, colors)
        // Keep the printed colorless frame and {5} cost in deck-building rows.
        // The pregame choice sets its color/identity, not colored mana demand.
        return Object.assign({}, card, {
            typeLine: card.typeLine || "Legendary Creature — Shapeshifter",
            manaCost: "{5}", manaValue: 5, cardColors: "", colors: color,
            commanderColor: color
        })
    }

    function advisory(cards, ids, basics, colors) {
        cards = cards.map(card => withColor(card, colors))
        const commanders = cards.filter(card => ids.indexOf(card.instanceId) >= 0)
        if (!commanders.length) return []
        const messages = []
        const atypical = commanders.filter(card => !/legendary/i.test(String(card.typeLine || ""))
            || !/creature/i.test(String(card.typeLine || "")))
        if (atypical.length) {
            messages.push(qsTranslate("TournamentLobby", "Confirm that your group allows these commanders: %1.")
                .arg(atypical.map(card => card.displayName || card.name).join(", ")))
        }
        if (commanders.length === 2 && !commanders.every(card => isPiper(card)))
            messages.push(qsTranslate("TournamentLobby", "Confirm the partner or other two-commander rules with your group."))
        // An unanswered Piper choice is incomplete setup, not a colorless
        // identity that should label the whole deck as out of color.
        if (commanders.some(card => isPiper(card) && !card.commanderColor)) return messages
        // Catalog 'colors' is Commander identity. 'cardColors' is only the
        // face color used for rows/land demand and must not stand in for it.
        const known = card => card.colors !== undefined && card.colors !== null
        if (commanders.some(card => !known(card))) {
            messages.push(qsTranslate("TournamentLobby", "Commander color identity is unavailable in the local database; check it manually."))
            return messages
        }
        const identity = new Set(commanders.map(card => String(card.colors).toUpperCase()).join("").match(/[WUBRG]/g) || [])
        let outside = 0
        let unknown = 0
        for (const card of cards) {
            if (!known(card)) { unknown++; continue }
            if ((String(card.colors).toUpperCase().match(/[WUBRG]/g) || []).some(color => !identity.has(color))) outside++
        }
        const basicColors = {Plains: "W", Island: "U", Swamp: "B", Mountain: "R", Forest: "G"}
        for (const name of Object.keys(basicColors)) {
            if (!identity.has(basicColors[name])) outside += Math.max(0, Number(basics[name] || 0))
        }
        if (outside)
            messages.push(qsTranslate("TournamentLobby", "%1 cards are outside the commanders' color identity. This is a reminder, not a submission restriction.").arg(outside))
        if (unknown)
            messages.push(qsTranslate("TournamentLobby", "%1 cards have no local color-identity data; check them manually.").arg(unknown))
        return messages
    }
}
