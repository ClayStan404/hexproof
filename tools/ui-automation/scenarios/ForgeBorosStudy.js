// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// This bounded test player reads the viewer projection and uses production
// controls. It qualifies interactions, not competitive AI play or card coverage.
var attempted = {};
var lastAction = null;
var captured = {};
var reviewDue = {};
var fixtureDeck = null;
var paymentAttempts = {};
var policyOrder = [
    "Ragavan, Nimble Pilferer", "Guide of Souls", "Ocelot Pride", "Ajani, Nacatl Pariah",
    "Seasoned Pyromancer", "Ranger-Captain of Eos", "Voice of Victory", "Goblin Bombardment",
    "Blood Moon", "Galvanic Discharge", "Thraben Charm", "Solitude"
];

function deck(driver) {
    if (!fixtureDeck) {
        var path = auditProbe.environment("HEXPROOF_AUDIT_DECK_MANIFEST");
        driver.require(path.length > 0, "The real-deck study requires an explicit manifest");
        fixtureDeck = JSON.parse(auditProbe.readText(path));
        driver.require(fixtureDeck.mainboard.reduce((sum, card) => sum + card.count, 0) === 60
            && fixtureDeck.sideboard.reduce((sum, card) => sum + card.count, 0) === 15,
            "The real-deck study requires the unmodified 60/15 list");
    }
    return fixtureDeck;
}

function lanes(driver) {
    var result = [];
    if (driver.table && driver.table.presentation) {
        for (var child of driver.table.presentation.children) {
            if (!child.visibleCards || child.category === undefined) continue;
            result = result.concat(child.visibleCards.map(card => ({
                cardId: card.cardId, name: card.name, controllerSeat: card.controllerSeat,
                tapped: card.tapped, category: card.category, power: card.power,
                toughness: card.toughness, countersSummary: card.countersSummary,
                damage: card.damage, attacking: card.attacking
            })));
        }
    }
    return result;
}

function scalarChoices(list) {
    var result = [];
    if (list) {
        for (var index = 0; index < list.count; ++index) {
            var row = list.itemAtIndex(index);
            if (row) result.push(row);
        }
    }
    return result;
}

function snapshot(driver) {
    var session = driver.session;
    return {
        board: lanes(driver), cards: session.promptCards.items(),
        choices: scalarChoices(driver.item("rulesScalarCandidates")).map(row => ({
            label: row.label, id: row.responseId, count: row.count
        })),
        context: session.promptContextText, contextCards: session.promptContextCards.items(), minNumber: session.promptMinNumber,
        maxNumber: session.promptMaxNumber, minCards: session.promptMinCardSelections,
        maxCards: session.promptMaxCardSelections, targets: session.boardTargetCandidates(),
        lastAction: lastAction
    };
}

function save(driver, name) {
    if (captured[name]) return;
    driver.capture(name);
    captured[name] = true;
}

function chooseAction(driver, options) {
    var session = driver.session;
    var own = ws.roomSession.seatIndex;
    var board = lanes(driver);
    var ours = board.filter(card => card.controllerSeat === own);
    var land = !captured["surveil-card"] && options.find(option => option.kind === "playLand"
        && option.label.startsWith("Elegant Parlor"));
    land = land || options.find(option => option.kind === "playLand");
    if (land) {
        if (driver.cardAction(land)) driver.lands++;
        return;
    }
    var fetch = !board.some(card => card.name === "Blood Moon") && options.find(option => option.kind === "activateAbility"
        && /^(Arid Mesa|Flooded Strand|Marsh Flats)/.test(option.label));
    if (fetch) {
        driver.cardAction(fetch);
        return;
    }
    var mana = ours.filter(card => card.category === "land" && !card.tapped
        && !/^(Arid Mesa|Flooded Strand|Marsh Flats)$/.test(card.name)).length;
    var specs = deck(driver).mainboard;
    var spells = options.filter(option => option.kind === "cast").sort((a, b) =>
        policyOrder.findIndex(name => a.label.startsWith(name))
        - policyOrder.findIndex(name => b.label.startsWith(name)));
    for (var option of spells) {
        var card = session.cardForInspection(option.cardId);
        var spec = specs.find(value => card.name === value.name || card.name === value.catalogName);
        if (!spec || spec.manaValue > mana) continue;
        if (spec.typeLine.includes("Legendary") && ours.some(value => value.name === card.name)) continue;
        if (spec.typeLine.includes("Instant")
            && !board.some(value => value.controllerSeat !== own && value.category === "creature")) continue;
        // Printed costs only guide attempts. Forge owns affordability and payment;
        // do not retry an unaffordable cast until the turn or available lands change.
        var key = session.turn + ":" + option.cardId + ":" + mana;
        if (attempted[key]) continue;
        attempted[key] = true;
        lastAction = {name: card.name, manaCost: spec.manaCost, manaAvailable: mana};
        if (driver.cardAction(option)) driver.casts++;
        return;
    }
    driver.click("rulesPromptOption-$pass");
}

function pay(driver, options) {
    for (var id of ["$auto-pay", "$pay"]) {
        if (options.some(option => option.responseId === id)) {
            driver.click("rulesPromptOption-" + id);
            driver.payments++;
            return;
        }
    }
    // A filter ability can ask for mana that this fixture cannot pay. After
    // canceling its nested cost, do not retry that same source indefinitely.
    var paymentState = driver.session.turn + ":" + driver.session.promptDetail + ":"
        + JSON.stringify(lanes(driver).map(c => [c.cardId, c.tapped, c.countersSummary]));
    var mana = options.find(option => option.kind === "activateAbility" && option.cardId
        && !paymentAttempts[paymentState + ":" + option.cardId]);
    if (mana) {
        paymentAttempts[paymentState + ":" + mana.cardId] = true;
        driver.cardAction(mana);
        driver.payments++;
        return;
    }
    driver.require(options.some(option => option.responseId === "$cancel"),
        "Payment requires review: " + JSON.stringify(options));
    driver.click("rulesPromptOption-$cancel");
}

function chooseScalar(driver) {
    var session = driver.session;
    var list = driver.item("rulesScalarCandidates");
    if (!list) return;
    var choices = scalarChoices(list);
    if (session.promptKind === "chooseBoolean"
            && choices.some(choice => choice.label === "Graveyard")
            && choices.some(choice => choice.label === "Library")) {
        var context = session.promptContextCards.items();
        driver.require(context.length === 1 && context[0].name.length > 0,
            "Native surveil must disclose its decision card");
        var art = driver.item("rulesPromptSourceArt");
        driver.require(art !== null, "Native surveil has no card image control");
        if (!captured["surveil-card"]) {
            if (!reviewDue.surveil) reviewDue.surveil = Date.now() + 5000;
            if (art.status !== 1 && Date.now() < reviewDue.surveil) return;
            driver.require(art.status === 1, "Native surveil card image did not load");
            save(driver, "surveil-card");
            auditProbe.record("surveil-card-context", {cards:context, text:session.promptContextText, image:art.source.toString()});
        }
    }
    var alternative = choices.some(choice => /Dash|Evoke/.test(choice.label));
    if (alternative) {
        var name = "ability-" + (lastAction ? lastAction.name : "choice").replace(/[^a-zA-Z0-9]+/g, "-");
        if (!captured[name]) {
            if (!reviewDue[name]) reviewDue[name] = Date.now() + 750;
            if (Date.now() < reviewDue[name]) return;
            save(driver, name);
        }
    }
    if (session.promptKind === "chooseFromSelection" && choices.some(choice => choice.count > 0)) {
        driver.click("rulesConfirmChoices");
        return;
    }
    var chosen = alternative ? choices.find(choice => !/Dash|Evoke/.test(choice.label)) : null;
    if (/energy/i.test(session.promptTitle) && choices.every(choice => /^\d+$/.test(choice.label)))
        chosen = choices[choices.length - 1];
    chosen = chosen
        || choices.find(choice => /\{W\}|Add W|White/.test(choice.label)
            && lastAction && lastAction.manaCost.includes("W"))
        || choices.find(choice => /\{R\}|Add R|Red/.test(choice.label)
            && lastAction && lastAction.manaCost.includes("R"))
        || choices.find(choice => /^(Cast|Play) /.test(choice.label) && !/Dash|Evoke/.test(choice.label));
    if (!chosen && /pay [12] life|pay.*energy|pay.*\{E\}/i.test(session.promptDetail)) chosen = choices[1];
    chosen = chosen || choices[0];
    if (chosen && !driver.click("rulesScalarChoice-" + chosen.responseId))
        driver.require(auditProbe.wheel(list, -160), "Cannot scroll native choices");
}

function chooseCards(driver) {
    var session = driver.session;
    var list = driver.item("rulesCardCandidates");
    var confirm = driver.item("rulesConfirmCards");
    if (!list) return;
    var selected = [], choices = [];
    for (var index = 0; index < list.count; ++index) {
        var card = list.itemAtIndex(index);
        if (!card) continue;
        choices.push(card);
        if (card.selected) selected.push(card);
    }
    var search = /search|library/i.test(session.promptTitle + " " + session.promptDetail);
    var target = /^Select target\b/.test(session.promptTitle);
    if (target) save(driver, "grouped-target");
    var wanted = search || target ? Math.min(session.promptMaxCardSelections,
        Math.max(1, session.promptMinCardSelections)) : session.promptMinCardSelections;
    if (confirm && confirm.enabled && selected.length >= wanted) {
        driver.click("rulesConfirmCards");
        return;
    }
    var preferred = search ? ["Sacred Foundry", "Elegant Parlor", "Plains", "Mountain", "Guide of Souls", "Ocelot Pride"] : [];
    if (search && !captured["surveil-card"]) preferred.unshift("Elegant Parlor");
    choices.sort((a, b) => {
        var ai = preferred.indexOf(a.name), bi = preferred.indexOf(b.name);
        return (ai < 0 ? 99 : ai) - (bi < 0 ? 99 : bi);
    });
    for (var card of choices)
        if (!card.selected && driver.click(card.objectName)) return;
    driver.require(auditProbe.wheel(list, -160), "Cannot scroll native card choices");
}

function chooseTarget(driver) {
    var session = driver.session;
    var interaction = driver.table.interaction;
    if (interaction.selectedCount >= session.promptMinSelections && interaction.validTargets) {
        driver.click("rulesConfirmTargets");
        return;
    }
    var candidates = session.boardTargetCandidates().filter(candidate =>
        !interaction.selectedTargetIds[candidate.responseId]);
    var own = ws.roomSession.seatIndex;
    var target = candidates.find(candidate => candidate.kind === "card"
        && session.cardForInspection(candidate.objectId).controllerSeat !== own)
        || candidates.find(candidate => candidate.kind === "player" && candidate.seat !== own)
        || candidates[0];
    driver.require(!!target, "Missing legal target");
    var name = target.kind === "player" ? "rulesPlayerTarget" + target.seat
        : (target.kind === "spell" ? "forgeStackCard-" : "forgeCard-") + target.objectId;
    if (!driver.click(name)) driver.click("rulesTarget-" + target.responseId);
}

function act(driver, offeredOptions) {
    var session = driver.session;
    var options = offeredOptions || session.promptOptionItems();
    if (session.promptKind !== "chooseAction") save(driver, "decision-" + session.promptKind);
    if (driver.table.cardActionPicker.opened) {
        var actions = driver.table.cardActionPicker.actions;
        var option = actions.find(action => !/dash|evoke|exert/i.test(action.label)) || actions[0];
        driver.click("rulesCardAction-" + option.responseId);
        return true;
    }
    switch (session.promptKind) {
    case "revealCards": driver.click("acknowledgeRevealButton"); return true;
    case "chooseAction": chooseAction(driver, options); return true;
    case "payManaCost": pay(driver, options); return true;
    case "chooseBoolean": case "chooseFromSelection": case "chooseColor":
        chooseScalar(driver); return true;
    case "chooseCards": case "mulliganPutBack": chooseCards(driver); return true;
    case "chooseBoardTargets": chooseTarget(driver); return true;
    case "scry": driver.click("confirmScryButton"); return true;
    case "chooseNumber": {
        var button = driver.item("rulesConfirmNumber");
        if (!button) return true;
        var input = button.parent.children.find(child => child.value !== undefined && child.from !== undefined);
        if (input && input.value < session.promptMaxNumber) {
            driver.require(auditProbe.click(input) && auditProbe.key(Qt.Key_Up), "Cannot choose a native amount");
            return true;
        }
        driver.click("rulesConfirmNumber");
        return true;
    }
    default: return false;
    }
}
