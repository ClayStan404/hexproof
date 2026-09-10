// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

.pragma library

function details(catalog, card) {
    card = card || {}
    let localized = {}
    if (catalog) {
        // Bind callers to both language changes and metadata-only cache updates.
        void catalog.language
        void catalog.imageRevision
        void catalog.tokenCatalogInstalled
        if (card.name && typeof catalog.tokenDetails === "function")
            localized = catalog.tokenDetails(card.name, card.setCode || "", card.collectorNumber || "") || {}
        else if (card.name && typeof catalog.tokenDisplayName === "function")
            localized.displayName = catalog.tokenDisplayName(card.name, card.setCode || "", card.collectorNumber || "")
    }
    // Presentation stays separate from canonical identities and saved metadata.
    return {displayName: localized.displayName || card.displayName || card.name || "",
            typeLine: localized.typeLine || card.typeLine || "",
            oracleText: localized.oracleText || card.oracleText || ""}
}

function summary(catalog, card, includePrinting) {
    const value = details(catalog, card)
    const parts = []
    if (card.power && card.toughness) parts.push(card.power + "/" + card.toughness)
    if (value.typeLine) parts.push(value.typeLine)
    if (value.oracleText) parts.push(value.oracleText.trim().replace(/\s*\n\s*/g, " · "))
    if (includePrinting)
        parts.push(String(card.setCode || "").toUpperCase() + " #" + String(card.collectorNumber || ""))
    return parts.join(" · ")
}

function fullText(value) {
    return [value.displayName, value.typeLine, value.oracleText].filter(part => part).join("\n\n")
}

function prioritize(catalog, card) {
    if (!catalog || !card || !card.name) return
    const kind = card.kind === "emblem" || /emblem|徽记/i.test(card.typeLine || "") ? "emblem" : "token"
    const request = Object.assign({}, card, {kind: kind})
    // Explicit inspection must not wait behind the picker's background batch.
    if (typeof catalog.prioritizeCards === "function") catalog.prioritizeCards([request])
    else if (typeof catalog.cacheToken === "function") catalog.cacheToken(request)
}
