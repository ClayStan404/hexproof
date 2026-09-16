// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Exercise candidate filtering and a Ragavan exile cast with the unchanged real
// deck. All decisions use native controls; waiting for coverage changes only the
// test player's strategy, never the engine's cards, shuffle, or result.
var observed = {};
var exileAttempts = [];
var attempted = {};
var review = null;
var captures = {};
var due = {};
var mulligans = 0;

function state() { return {coverage:observed, exileAttempts:exileAttempts, selection:review, mulligans:mulligans}; }
function seen(name) {
    for (var seat of [1, 2]) {
        var record = auditProbe.readShared("boros-choices-seat-" + seat) || {};
        if (record[name]) return record[name];
    }
    return null;
}
function complete() { return !!(seen("libraryFilter") && seen("multipleFilteredCards") && seen("exileCast")); }
function note(driver, name, value) {
    observed[name] = value;
    auditProbe.share("boros-choices-seat-" + driver.seat, observed);
    auditProbe.record("card-choice-" + name, value);
}
function capture(driver, name) {
    if (captures[name]) return false;
    if (!due[name]) due[name] = Date.now() + 750;
    if (Date.now() < due[name]) return true;
    driver.capture(name);
    captures[name] = true;
    return false;
}
function board(driver) {
    var cards = [];
    for (var lane of driver.table.presentation.children)
        if (lane.visibleCards && lane.category !== undefined) cards = cards.concat(lane.visibleCards);
    return cards;
}
function allowAttack(name) {
    return complete() || (!seen("exileCast") && name === "Ragavan, Nimble Pilferer");
}
function actionOptions(driver) {
    return driver.session.promptOptionItems().filter(option => seen("exileCast")
        || option.kind !== "cast" || !/^(Galvanic Discharge|Thraben Charm)/.test(option.label));
}
function observeExile(driver) {
    if (observed.exileCast) return false;
    var own = ws.roomSession.seatIndex;
    for (var attempt of exileAttempts) {
        var card = driver.session.cardForInspection(attempt.cardId);
        if (card.zone === "battlefield" && card.controllerSeat === own) {
            driver.require(card.ownerSeat === attempt.fromSeat, "Casting the opponent's exiled card changed its owner");
            note(driver, "exileCast", Object.assign({}, attempt, {destination:card.zone,
                ownerSeat:card.ownerSeat, controllerSeat:card.controllerSeat, resolvedTurn:driver.session.turn}));
            return capture(driver, "exile-card-resolved");
        }
    }
    return false;
}
function chooseExileAction(driver) {
    var session = driver.session;
    var options = session.promptOptionItems();
    if (options.some(option => option.kind === "playLand")) return false;
    var own = ws.roomSession.seatIndex;
    var ours = board(driver).filter(card => card.controllerSeat === own);
    var mana = ours.filter(card => !card.tapped && (card.category === "land"
        || card.name === "Treasure Token")).length;
    for (var option of options) {
        if (option.kind !== "cast") continue;
        var card = session.cardForInspection(option.cardId);
        if (card.zone !== "exile" || card.zoneOwnerSeat === own) continue;
        var spec = driver.deck().mainboard.find(value => value.name === card.name || value.catalogName === card.name);
        // Ragavan also exposes noncreature permanents. Track those casts before
        // the general deck pilot consumes them, then verify the same object on
        // the battlefield with its original owner and new controller.
        if (!spec || !/(Creature|Artifact|Enchantment|Planeswalker|Battle)/.test(spec.typeLine)
            || spec.manaValue > mana) continue;
        if (spec.typeLine.includes("Legendary") && ours.some(value => value.name === card.name)) continue;
        var key = session.turn + ":" + option.cardId;
        if (attempted[key]) continue;
        if (capture(driver, "exile-action-offered")) return true;
        var attempt = {cardId:option.cardId, name:card.name, fromZone:card.zone,
            fromSeat:card.zoneOwnerSeat, promptId:session.promptId, responseId:option.responseId, turn:session.turn};
        if (!driver.click("rulesZoneAction-" + option.responseId)) return true;
        attempted[key] = true;
        exileAttempts.push(attempt);
        auditProbe.record("exile-cast-attempt-" + exileAttempts.length, exileAttempts[exileAttempts.length - 1]);
        driver.casts++;
        return true;
    }
    // Keep mana available for the card Ragavan may expose during combat.
    if (!seen("exileCast") && session.step === "main1"
        && ours.some(card => card.name === "Ragavan, Nimble Pilferer")) {
        driver.click("rulesPromptOption-$pass");
        return true;
    }
    return false;
}
function chooseCards(driver) {
    var session = driver.session;
    var chooser = driver.item("rulesCardSelectionPrompt");
    var field = driver.item("rulesCardFilter");
    var list = driver.item("rulesCardCandidates");
    if (!chooser || !field || !list) return true;
    var all = session.promptCards.items();
    if (driver.seat === 1 && !driver.privateChoiceResumed) {
        driver.interrupt("private-choice");
        return true;
    }
    if (!review || review.promptId !== session.promptId) {
        // Native London put-back also uses chooseCards and mentions the library
        // in its detail. It must not satisfy the separate library-search check.
        var search = session.turn > 0 && session.promptKind === "chooseCards"
            && /from (your |the )?library|search/i.test(session.promptTitle);
        var wanted = Math.min(all.length, search ? Math.max(1, session.promptMinCardSelections) : session.promptMinCardSelections);
        var pool = all.slice();
        var preferred = search ? ["Sacred Foundry", "Elegant Parlor", "Plains", "Mountain", "Guide of Souls"] : [];
        if (search && !seen("exileCast")) preferred.unshift("Ragavan, Nimble Pilferer");
        var lands = driver.deck().mainboard.filter(card => card.typeLine.includes("Land")).map(card => card.name);
        pool.sort((a, b) => {
            var ai = preferred.indexOf(a.name), bi = preferred.indexOf(b.name);
            if (!search) return (a.name === "Ragavan, Nimble Pilferer" ? 2 : session.turn === 0 && lands.includes(a.name) ? 1 : 0)
                - (b.name === "Ragavan, Nimble Pilferer" ? 2 : session.turn === 0 && lands.includes(b.name) ? 1 : 0);
            return (ai < 0 ? 99 : ai) - (bi < 0 ? 99 : bi);
        });
        var plan = [];
        while (plan.length < wanted) {
            var next = pool.find(card => !plan.some(value => value.name === card.name)) || pool[0];
            plan.push(next);
            pool = pool.filter(card => card.cardId !== next.cardId);
        }
        review = {promptId:session.promptId, search:search, total:all.length, plan:plan, index:0, filtered:false};
    }
    if (capture(driver, review.search ? "library-candidate-grid" : "card-candidate-grid")) return true;
    while (review.index < review.plan.length && chooser.selectedIds[review.plan[review.index].cardId]) review.index++;
    if (review.index === review.plan.length) {
        var ids = review.plan.map(card => card.cardId);
        driver.require(chooser.validSelection && chooser.selectedCount === ids.length
            && ids.every(id => chooser.selectedIds[id] === true), "Filtered selection lost a card or changed native bounds");
        var evidence = {promptId:session.promptId, kind:session.promptKind, title:session.promptTitle,
            cards:review.plan, minimum:session.promptMinCardSelections,
            maximum:session.promptMaxCardSelections, selected:ids, candidates:all.length};
        if (review.search && review.filtered && !observed.libraryFilter) note(driver, "libraryFilter", evidence);
        if (ids.length >= 2 && review.plan.some(card => card.name !== review.plan[0].name)) {
            if (capture(driver, "cards-selected-across-filters")) return true;
            if (!observed.multipleFilteredCards) note(driver, "multipleFilteredCards", evidence);
        }
        driver.click("rulesConfirmCards");
        return true;
    }
    var next = review.plan[review.index];
    if (field.text !== next.name) {
        driver.require(auditProbe.click(field) && auditProbe.key(Qt.Key_A, Qt.ControlModifier)
            && auditProbe.text(next.name), "Cannot enter a native card-name filter");
        review.readyAt = Date.now() + 350;
        return true;
    }
    if (Date.now() < review.readyAt) return true;
    var matches = all.filter(card => card.name.toLocaleLowerCase().includes(next.name.toLocaleLowerCase()));
    driver.require(list.count === matches.length, "The filter did not retain exactly the authorized matching candidates");
    if (list.count < all.length) review.filtered = true;
    if (review.search && capture(driver, "library-filtered")) return true;
    if (!driver.click("rulesCardCandidate-" + next.cardId))
        driver.require(auditProbe.wheel(list, -180), "Cannot reach a filtered card");
    return true;
}
function act(driver) {
    if (observeExile(driver)) return true;
    if (observed.exileCast && capture(driver, "exile-card-resolved")) return true;
    // Two normal London mulligans provide a real multi-card decision without
    // waiting for a randomly drawn Pyromancer or manufacturing an opening hand.
    if (driver.seat === 1 && driver.session.promptKind === "mulligan" && mulligans < 2) {
        var promptId = driver.session.promptId;
        if (driver.click("rulesPromptOption-$mulligan")) {
            mulligans++;
            auditProbe.record("card-choice-mulligan-" + mulligans, {promptId:promptId});
        }
        return true;
    }
    if (driver.session.promptKind === "chooseAction") return chooseExileAction(driver);
    if (driver.session.promptKind === "chooseCards" || driver.session.promptKind === "mulliganPutBack") return chooseCards(driver);
    if (driver.session.promptKind === "revealCards") return capture(driver, "revealed-candidate-grid");
    return false;
}
