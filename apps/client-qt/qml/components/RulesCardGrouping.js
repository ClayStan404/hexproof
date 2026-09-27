// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

.pragma library

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
    // Stateful copies have separate choices/linked objects, even when their
    // public counts or printed names are identical.
    if (card.exiledCardCount > 0 || (card.annotations || []).length > 0
        || (card.chosenCardIds || []).length > 0)
        return "id:" + id
    return [String(card.name).trim().toLocaleLowerCase(),
            card.token === true ? "token" : "card",
            card.tapped === true ? "tapped" : "untapped",
            card.enteredThisTurn === true ? "entered" : "established",
            card.summoningSick === true ? "sick" : "ready",
            card.attacking === true ? "attacking" : "ready",
            String(card.power || ""),
            String(card.toughness || ""),
            String(card.countersSummary || ""),
            String(card.damage || 0),
            String(card.attachedTo || ""),
            String(card.exiledCardCount || 0)].join("\u001f")
}
