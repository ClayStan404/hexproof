// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
.pragma library

function card(id, key, name, kind, cost, stats, counters) {
    return { id: id, key: key, name: name, kind: kind, cost: cost || "",
             stats: stats || "", counters: counters || "" }
}

function ownCreatures() {
    return [card("ragavan", "ragavan", "Ragavan, Nimble Pilferer", "Creature", "R", "2 / 1"),
            card("guide", "guide", "Guide of Souls", "Creature", "W", "1 / 2"),
            card("ajani", "ajani", "Ajani, Nacatl Pariah", "Creature", "1 W", "1 / 2"),
            card("ocelot", "ocelot", "Ocelot Pride", "Creature", "W", "1 / 1")]
}

function opponentCreatures() {
    return [card("ravager", "ravager", "Arcbound Ravager", "Artifact creature", "2", "3 / 3", "+1/+1 · 3"),
            card("ballista", "ballista", "Walking Ballista", "Artifact creature", "X X", "2 / 2", "+1/+1 · 2"),
            card("walker", "walker", "Hangarback Walker", "Artifact creature", "X X", "1 / 1", "+1/+1 · 1")]
}

function ownLands() {
    return [card("foundry", "foundry", "Sacred Foundry", "Land", "R W"),
            card("mountain", "mountain", "Mountain", "Land", "R"),
            card("plains", "plains", "Plains", "Land", "W")]
}

function opponentLands() {
    return [card("forest-a", "forest", "Forest", "Land", "G"),
            card("forest-b", "forest", "Forest", "Land", "G"),
            card("citadel", "citadel", "Darksteel Citadel", "Artifact land", "C")]
}

function hand() {
    return [card("bolt", "bolt", "Lightning Bolt", "Instant", "R"),
            card("discharge", "discharge", "Galvanic Discharge", "Instant", "R"),
            card("ajani-hand", "ajani", "Ajani, Nacatl Pariah", "Creature", "1 W"),
            card("plains-hand", "plains", "Plains", "Land"),
            card("ranger", "ranger", "Ranger-Captain of Eos", "Creature", "1 W W"),
            card("phlage", "phlage", "Phlage, Titan of Fire's Fury", "Creature", "1 R W")]
}

function ability() {
    return { id: "ballista-ability", key: "ballista", name: "Walking Ballista",
             kind: "Activated ability", owner: "Opponent", targetId: "guide",
             targetName: "Guide of Souls", description: "Deal 1 damage to Guide of Souls." }
}

function spell(targetId, targetName) {
    return { id: "bolt-spell", key: "bolt", name: "Lightning Bolt", kind: "Instant",
             owner: "You", targetId: targetId, targetName: targetName,
             description: "Deal 3 damage to " + targetName + "." }
}

function combatCreatures() {
    return [card("own-ravager", "ravager", "Arcbound Ravager", "Artifact creature", "2", "6 / 6", "+1/+1 · 6")]
        .concat(ownCreatures().slice(0, 3))
}

function commander() {
    return card("isamaru", "isamaru", "Isamaru, Hound of Konda", "Legendary creature", "W", "2 / 2")
}

function opposingCommander() {
    return card("thalia", "thalia", "Thalia, Guardian of Thraben", "Legendary creature", "1 W", "2 / 1")
}

function duelCreatures(opponent) {
    return opponent
        ? [card("duel-ranger", "ranger", "Ranger-Captain of Eos", "Creature", "1 W W", "3 / 3")]
        : [card("guide", "guide", "Guide of Souls", "Creature", "W", "1 / 2"),
           card("ocelot", "ocelot", "Ocelot Pride", "Creature", "W", "1 / 1")]
}

function duelLands(prefix) {
    return [1, 2, 3].map(i => card(prefix + i, "plains", "Plains", "Land", "W"))
}

function duelHand() {
    return [card("duel-hand-ranger", "ranger", "Ranger-Captain of Eos", "Creature", "1 W W"),
            card("duel-hand-plains", "plains", "Plains", "Land"),
            card("duel-hand-plains-2", "plains", "Plains", "Land")]
}

function crowdedCreatures(opponent) {
    const result = opponent ? opponentCreatures() : ownCreatures()
    const count = opponent ? 20 : 24
    // Individual copy tokens keep distinct identities even when their art matches.
    for (let i = result.length; i < count; ++i) {
        const key = opponent ? "ocelot" : "guide"
        const name = opponent ? "Ocelot Pride" : "Guide of Souls"
        const entry = card((opponent ? "enemy-token-" : "token-") + i, key, name,
            "Creature token · copy", "", opponent ? "1 / 1" : "1 / 2", "Token · " + (i + 1))
        result.push(entry)
    }
    return result
}

function crowdedHand() {
    const result = hand()
    for (let i = result.length; i < 15; ++i) {
        const entry = Object.assign({}, hand()[i % 6])
        entry.id = "extra-hand-" + i
        result.push(entry)
    }
    return result
}

function crowdedStack() {
    const result = []
    for (let i = 0; i < 8; ++i) {
        result.push({id: "busy-ability-" + i, key: "ballista", name: "Walking Ballista",
            kind: "Activated ability", owner: "Opponent", targetId: "token-23",
            targetName: "Guide of Souls · token 24", description: "Deal 1 damage to the selected token."})
    }
    return result
}
