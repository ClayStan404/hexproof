// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Fixed, exact-printing decks exercise the production Forge path. Costs guide
// only the test player's choices; the native engine validates every action.
var costs = {"Arc Trail":2, "Lightning Bolt":1, "Goblin Piker":2, "Borderland Marauder":2,
    "Hill Giant":4, "Falkenrath Reaver":2, "Counterspell":2, "Negate":2, "Cancel":3,
    "Air Elemental":5, "Wind Drake":3, "Watercourser":3}
var counterGame = ""
var counterAttempts = {}

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

function counterContext(driver, cardId) {
    if (counterGame !== driver.session.gameId) {
        counterGame = driver.session.gameId
        counterAttempts = {}
    }
    return JSON.stringify({gameId:counterGame, turn:driver.session.turn, step:driver.session.step,
        cardId:cardId, mana:driver.availableMana(), stack:driver.session.stackObjectIds().map(function(id) {
            var object = driver.session.cardForInspection(id)
            return [id, object.sourceId, object.controllerSeat, object.name, object.rulesText]
        })})
}

function castAllowed(driver, name, cardId) {
    if (!["Counterspell", "Negate", "Cancel"].includes(name)) return true
    var candidate = driver.session.stackObjectIds().some(function(id) {
        var object = driver.session.cardForInspection(id)
        if (object.controllerSeat < 0 || object.controllerSeat === ws.roomSession.seatIndex) return false
        // The public projection has no spell/ability flag. A visible source
        // still outside the stack identifies an ability, such as an attack or
        // ETB trigger. A missing source is inconclusive: real spell cards are
        // absent from the ordinary zone models while they are on the stack.
        var source = driver.session.cardForInspection(object.sourceId)
        if (source.zone && source.zone !== "stack") return false
        return name !== "Negate"
            || ["Arc Trail", "Lightning Bolt", "Counterspell", "Negate", "Cancel"].includes(object.name)
    })
    if (!candidate) return false
    var context = counterContext(driver, cardId)
    var attempt = counterAttempts[cardId]
    if (!attempt || attempt.context !== context || attempt.count < 3
        || Date.now() - attempt.started < 1000) return true
    if (!attempt.reported) {
        auditProbe.record("counterspell-no-progress-" + driver.session.promptId,
            {reason:"no observable action progress", cardId:cardId, name:name,
                attempts:attempt.count, priorPromptId:attempt.promptId, promptId:driver.session.promptId,
                observation:JSON.parse(context),
                limit:"Same observed turn, step, available mana and stack; this does not identify why the action did not progress."})
        attempt.reported = true
        driver.capture("counterspell-no-progress")
    }
    return false
}

function castCard(driver, option) {
    var card = driver.session.cardForInspection(option.cardId)
    if (!["Counterspell", "Negate", "Cancel"].includes(card.name)) return driver.cardAction(option)
    // Capture before native input pumps events. Allow a picker to open and
    // select an action, but bound retries even if the prompt ID never changes.
    var context = counterContext(driver, option.cardId)
    var promptId = driver.session.promptId
    var previous = counterAttempts[option.cardId]
    if (previous && previous.context === context && previous.count >= 3) return false
    var accepted = driver.cardAction(option)
    if (accepted) {
        if (!previous || previous.context !== context)
            counterAttempts[option.cardId] = {context:context, promptId:promptId, count:1, started:Date.now(), reported:false}
        else {
            previous.promptId = promptId
            previous.count++
        }
    }
    return accepted
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
        auditProbe.record("target-selection-" + driver.session.promptId,
            {selectedIds:Object.keys(interaction.selectedTargetIds)})
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
    // A legal card can be buried in a closed pile without a fallback tile.
    // Keep the coverage preference, then try the other legal native controls.
    var ordered = [target].concat(candidates.filter(function(candidate) {
        return candidate.responseId !== target.responseId
    }))
    auditProbe.record("target-candidates-" + driver.session.promptId,
        {preferred:target, candidates:ordered})
    for (var candidate of ordered) {
        var name = candidate.kind === "player" ? "rulesPlayerTarget" + candidate.seat
            : (candidate.kind === "spell" ? "forgeStackCard-" : "forgeCard-") + candidate.objectId
        if (driver.click(name) || driver.click("rulesTarget-" + candidate.responseId)) return
    }
}
