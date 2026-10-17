// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Fixed, exact-printing decks exercise the production Forge path. Costs guide
// only the test player's choices; the native engine validates every action.
var costs = {"Arc Trail":2, "Lightning Bolt":1, "Goblin Piker":2, "Borderland Marauder":2,
    "Hill Giant":4, "Falkenrath Reaver":2, "Counterspell":2, "Negate":2, "Cancel":3,
    "Air Elemental":5, "Wind Drake":3, "Watercourser":3}

function deck(seat) {
    var cards = seat === 1 ? [
        ["Mountain", "LEA", "293", "Basic Land — Mountain", 36],
        ["Arc Trail", "SOM", "81", "Sorcery"], ["Lightning Bolt", "LEA", "161", "Instant"],
        ["Goblin Piker", "P02", "102", "Creature"], ["Borderland Marauder", "M15", "131", "Creature"],
        ["Hill Giant", "LEA", "157", "Creature"], ["Falkenrath Reaver", "EMN", "127", "Creature"]
    ] : [
        ["Island", "LEA", "288", "Basic Land — Island", 36],
        ["Counterspell", "LEA", "54", "Instant"], ["Negate", "MOR", "43", "Instant"],
        ["Cancel", "TSP", "51", "Instant"], ["Air Elemental", "LEA", "46", "Creature"],
        ["Wind Drake", "POR", "77", "Creature"], ["Watercourser", "M13", "78", "Creature"]]
    return {name:"Native stack relationships " + seat, format:"modern", deckFormat:"modern",
        mainboard:cards.map(function(card) { return {name:card[0], setCode:card[1], collectorNumber:card[2],
            typeLine:card[3], count:card[4] || 4} }), sideboard:[]}
}

function complete(driver) {
    var seen = auditProbe.readShared("stack-coverage") || {}
    return seen.card && seen.player && seen.spell && seen.multiple
}

function castAllowed(driver, name) {
    if (!["Counterspell", "Negate", "Cancel"].includes(name)) return true
    return driver.session.stackObjectIds().some(function(id) {
        var spell = driver.session.cardForInspection(id)
        return spell.controllerSeat !== ws.roomSession.seatIndex && (name !== "Negate"
            || ["Arc Trail", "Lightning Bolt", "Counterspell", "Negate", "Cancel"].includes(spell.name))
    })
}

function observe(driver) {
    var session = driver.session
    var stack = driver.table.presentation.children.find(function(child) { return child.objectName === "forgeStack" })
    if (!stack) return false
    if (driver.stackReview) {
        var review = driver.stackReview
        driver.require(session.promptId === review.promptId && !ws.rulesResponsePending, "Inspecting a stack target submitted a rules decision")
        driver.require(stack.currentTarget && stack.currentTarget.kind === review.target.kind
            && stack.currentTarget.objectId === review.target.objectId && stack.currentTarget.seat === review.target.seat,
            "Stack target inspection located a different object")
        var seen = Object.assign({}, auditProbe.readShared("stack-coverage") || {})
        seen[review.target.kind] = true
        if (review.multiple) seen.multiple = true
        auditProbe.share("stack-coverage", seen)
        driver.stackObserved = Object.assign({}, driver.stackObserved)
        driver.stackObserved[review.target.kind] = true
        if (review.multiple) driver.stackObserved.multiple = true
        auditProbe.record("stack-relationship-" + review.target.kind, review)
        driver.capture("relationship-" + review.target.kind)
        driver.stackReview = null
        return true
    }
    var ids = session.stackObjectIds()
    for (var i = 0; i < ids.length; ++i) {
        var object = session.cardForInspection(ids[i])
        var targets = object.targets || []
        for (var j = 0; j < targets.length; ++j) {
            var target = targets[j]
            if (driver.stackObserved[target.kind] && (targets.length < 2 || driver.stackObserved.multiple)) continue
            if (!driver.click("forgeStackTarget-" + ids[i] + "-" + j)) continue
            driver.stackReview = {sourceId:ids[i], target:target, multiple:targets.length > 1, promptId:session.promptId}
            return true
        }
    }
    return false
}

function chooseTarget(driver) {
    var interaction = driver.table.interaction
    if (interaction.selectedCount >= driver.session.promptMinSelections && interaction.validTargets) {
        driver.click("rulesConfirmTargets"); return
    }
    var candidates = driver.session.boardTargetCandidates().filter(function(candidate) {
        return !interaction.selectedTargetIds[candidate.responseId]
    })
    var seen = auditProbe.readShared("stack-coverage") || {}
    var target = candidates.find(function(candidate) { return candidate.kind === "spell" })
    if (!target && !seen.card) target = candidates.find(function(candidate) {
        return candidate.kind === "card" && candidate.objectId
            && driver.session.cardForInspection(candidate.objectId).zone === "battlefield"
    })
    if (!target) target = candidates.find(function(candidate) { return candidate.kind === "player" && candidate.seat !== ws.roomSession.seatIndex })
    if (!target) target = candidates[0]
    driver.require(!!target, "No legal native target")
    var name = target.kind === "player" ? "rulesPlayerTarget" + target.seat
        : (target.kind === "spell" ? "forgeStackCard-" : "forgeCard-") + target.objectId
    if (!driver.click(name)) driver.click("rulesTarget-" + target.responseId)
}
