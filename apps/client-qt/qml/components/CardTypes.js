// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

.pragma library

function frontTypeLine(card) {
    return String(card.typeLine || "").split("//")[0].trim()
}

function typeParts(card) {
    return frontTypeLine(card).split(/[—–~～－]/)
}

function hasType(card, name) {
    const types = typeParts(card)[0]
    const localized = {Creature: ["生物"], Planeswalker: ["鹏洛客", "鵬洛客", "旅法师", "旅法師"],
        Instant: ["瞬间", "瞬間"], Sorcery: ["法术", "巫術"], Artifact: ["神器"],
        Enchantment: ["结界", "結界"], Battle: ["战役", "戰役"], Land: ["地"],
        Legendary: ["传奇", "傳奇"]}
    return new RegExp("\\b" + name + "\\b", "i").test(types)
        || (localized[name] || []).some(value => types.includes(value))
}

function subtypes(card) {
    return typeParts(card).slice(1).join(" ")
}
