// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Bounded visible-information test player, not a competitive Magic agent.
// Forge decides legality and pays costs; every response uses production UI.
.import "ForgeBorosStudy.js" as Common

var fixture = null;
var attempted = {};
var lastSpell = null;
var lastAction = null;
var seen = {};
var metadata = {};
var games = {};
var sideboardStage = 0;
var sideboardBefore = null;
var movedCard = null;
var basicName = "";
var blockerPrompt = -1;
var blockPlan = [];
var copyReplacementAnswers = {};
var copyReplacementDeclines = 0;
var mulligans = {};

function state(driver) {
    return {source: fixture ? fixture.source || "catalog fixture" : "submitted Limited pool",
        lastSpell: lastSpell, lastAction: lastAction, seen: Object.keys(seen), games: Object.keys(games), sideboardStage: sideboardStage,
        copyReplacementDeclines:copyReplacementDeclines,
        mulligans:mulligans,
        choices: driver ? Common.scalarChoices(driver.item("rulesScalarCandidates")).map(c => ({id:c.responseId, label:c.label})) : []};
}

function deck(driver) {
    if (!fixture) {
        const path = auditProbe.environment("HEXPROOF_AUDIT_DECK_MANIFEST");
        driver.require(path.length > 0, "Format match requires an explicit deck manifest");
        const data = JSON.parse(auditProbe.readText(path));
        fixture = data.formats ? data.formats[driver.deckFormat]
            : data.decks ? data.decks[(driver.seat - 1) % data.decks.length] : data;
        driver.require(fixture.mainboard && fixture.deckFormat === driver.deckFormat,
            "Deck manifest does not match the selected format");
    }
    return fixture;
}

function spec(card) {
    const key = card.name + "|" + card.setCode + "|" + card.collectorNumber;
    if (!metadata[key]) {
        metadata[key] = Array.from(cardCatalog.enrichLimitedCards([card]))[0] || card;
        if (fixture) {
            const recorded = fixture.mainboard.concat(fixture.sideboard || []).find(c =>
                c.name === card.name || c.catalogName === card.name);
            if (recorded) metadata[key] = recorded;
        }
    }
    return metadata[key];
}

function chooseAction(driver, options) {
    const s = driver.session, own = ws.roomSession.seatIndex;
    const board = Common.lanes(driver), ours = board.filter(c => c.controllerSeat === own);
    const land = options.find(o => o.kind === "playLand");
    if (land) {
        if (driver.cardAction(land)) { lastAction = land; driver.lands++; }
        return;
    }
    const mana = ours.filter(c => !c.tapped && (c.category === "land"
        || /^(Sol Ring|Mox |Llanowar Elves|Elvish Mystic|Birds of Paradise)/.test(c.name))).length;
    const fetch = options.find(o => o.kind === "activateAbility"
        && /^(Fabled Passage|Evolving Wilds|Terramorphic Expanse|Arid Mesa|Flooded Strand|Polluted Delta|Misty Rainforest|Scalding Tarn|Windswept Heath|Wooded Foothills|Prismatic Vista)/.test(o.label));
    if (fetch && !attempted[s.turn + ":fetch:" + fetch.cardId]) {
        if (driver.cardAction(fetch)) { lastAction = fetch; attempted[s.turn + ":fetch:" + fetch.cardId] = true; }
        return;
    }
    const spells = options.filter(o => o.kind === "cast").map(o => ({option:o, card:s.cardForInspection(o.cardId)}));
    spells.sort((a, b) => Number(spec(a.card).manaValue || 0) - Number(spec(b.card).manaValue || 0));
    for (const entry of spells) {
        const card = entry.card, data = spec(card), type = data.typeLine || "";
        let cost = Number(data.manaValue || 0);
        if (/affinity for artifacts/i.test(card.rulesText || ""))
            cost = Math.max(1, cost - ours.filter(c => /Artifact/.test(spec(s.cardForInspection(c.cardId)).typeLine || "")).length);
        if (card.zone === "command") cost += 2 * Math.max(0, driver.maximumTax / 2);
        if (cost > mana) continue;
        if (/Legendary/.test(type) && ours.some(c => c.name === card.name)) continue;
        if (/counter target/i.test(card.rulesText || "") && !s.stackObjectIds().length) continue;
        const key = s.gameId + ":" + s.turn + ":" + card.cardId + ":" + mana;
        if (attempted[key]) continue;
        if (driver.cardAction(entry.option)) {
            lastAction = entry.option;
            attempted[key] = true;
            lastSpell = {name:card.name, manaCost:data.manaCost || "", cost:cost};
            seen[card.name] = true;
            driver.casts++;
        }
        return;
    }
    driver.click("rulesPromptOption-$pass");
}

function scalar(driver) {
    const s = driver.session, list = driver.item("rulesScalarCandidates");
    if (!list) return;
    const choices = Common.scalarChoices(list);
    if (s.promptKind === "chooseFromSelection" && choices.some(c => c.count > 0)
        && driver.click("rulesConfirmChoices")) return;
    const cost = lastSpell ? lastSpell.manaCost : "";
    let choice = choices.find(c => /command zone/i.test(c.label));
    const copyReplacement = /^Apply replacement effect of /.test(s.promptDetail)
        && /enter.*as a copy/.test(s.promptDetail);
    const copyContext = {detail:s.promptDetail, turn:s.turn, action:lastAction};
    const replacementKey = s.gameId + ":" + s.turn + ":"
        + (lastAction ? lastAction.cardId : "") + ":" + s.promptDetail;
    if (copyReplacement && copyReplacementAnswers[replacementKey])
        choice = choices.find(c => c.label === "No");
    if (!choice && lastAction && lastAction.kind === "playLand")
        choice = choices.find(c => /^Play\b/i.test(c.label) && !/channel|cycling/i.test(c.label));
    if (!choice && choices.some(c => /dash|evoke|disguise|morph/i.test(c.label)))
        choice = choices.find(c => !/dash|evoke|disguise|morph/i.test(c.label));
    for (const [symbol, name] of [["W","White"],["U","Blue"],["B","Black"],["R","Red"],["G","Green"]]) {
        if (!choice && cost.includes(symbol)) choice = choices.find(c => c.label.includes("{" + symbol + "}")
            || c.label === name || c.label.includes("Add " + symbol));
    }
    choice = choice || choices.find(c => /^(Cast|Play) /.test(c.label) && !/evoke|dash|disguise|morph/i.test(c.label))
        || choices.find(c => /^(Yes|Pay|Proceed|Keep)\b/.test(c.label)) || choices[0];
    if (choice) {
        if (driver.click("rulesScalarChoice-" + choice.responseId)) {
            if (copyReplacement) {
                copyReplacementAnswers[replacementKey] = true;
                if (choice.label === "No") {
                    copyReplacementDeclines++;
                    auditProbe.record("copy-replacement-declined-" + copyReplacementDeclines,
                        {detail:copyContext.detail, turn:copyContext.turn, action:copyContext.action,
                         reason:"Stop repeating the same optional copy choice"});
                }
            }
        } else {
            driver.require(auditProbe.wheel(list, -160), "Cannot scroll scalar choices");
        }
    }
}

function chooseBlockers(driver) {
    const s = driver.session, combat = driver.table.combatInteraction;
    const sources = s.promptCombat.sourceItems();
    if (blockerPrompt !== s.promptId) {
        blockerPrompt = s.promptId;
        blockPlan = [];
        const covered = [];
        for (const source of sources) {
            const blocker = s.cardForInspection(source.objectId);
            const target = source.validTargets.find(target => {
                if (covered.includes(target.responseId)) return false;
                const attacker = s.cardForInspection(target.objectId);
                // A simple trade/survival policy. Forge remains authoritative;
                // multi-block requirements are exercised by dedicated studies.
                if (/menace|can't be blocked except by/i.test(attacker.rulesText || "")) return false;
                return Number(blocker.power) >= Number(attacker.toughness)
                    || Number(blocker.toughness) > Number(attacker.power);
            });
            if (target) { blockPlan.push({source:source, target:target}); covered.push(target.responseId); }
        }
        auditProbe.record("block-plan-" + s.promptId, blockPlan);
    }
    for (const pair of blockPlan) {
        if (combat.selectedTargets(pair.source.responseId).includes(pair.target.responseId)) continue;
        if (combat.selectedSource === pair.source.responseId) {
            const id = driver.combatInputId(pair.target.objectId);
            if (!id) continue;
            if (driver.click("forgeCard-" + id)) {
                driver.require(combat.selectedTargets(pair.source.responseId).includes(pair.target.responseId),
                    "Blocking selected a different attacker from its pile");
                driver.blocks++;
            } else driver.wheelToCard(id, false);
        } else {
            const id = driver.combatInputId(pair.source.objectId);
            if (!id) continue;
            if (!driver.clickCombatSource(pair.source, id)) driver.wheelToCard(id, false);
        }
        return;
    }
    if (combat.links.length) {
        driver.capture("blocking");
        if (!driver.capturedCombat) { driver.capture("combat"); driver.capturedCombat = true; }
    }
    driver.click("rulesConfirmCombat-blockers");
}

function chooseOpeningHand(driver) {
    const s = driver.session;
    const hand = driver.table.presentation.children.find(c => c.objectName === "forgeHand");
    if (!hand || !hand.visibleCards.length) return;
    const cards = hand.visibleCards.map(c => s.cardForInspection(c.cardId));
    const lands = cards.filter(c => /\bLand\b/.test(spec(c).typeLine || "")).length;
    const game = s.gameId, taken = mulligans[game] || 0;
    const retry = !driver.existingLimitedMatch && (lands < 2 || lands > 5) && taken < 2;
    if (driver.click("rulesPromptOption-" + (retry ? "$mulligan" : "$keep"))) {
        if (retry) mulligans[game] = taken + 1;
        auditProbe.record("opening-hand-" + game + "-" + taken,
            {lands:lands, cards:cards.map(c => c.name), action:retry ? "mulligan" : "keep"});
    }
}

function act(driver) {
    const s = driver.session, options = s.promptOptionItems();
    games[s.gameId] = true;
    if (driver.existingLimitedMatch && !driver.liveResumed
        && ["chooseAttackers", "chooseBlockers"].includes(s.promptKind)) {
        driver.interrupt("live"); return true;
    }
    if (driver.table.cardActionPicker.opened) {
        const actions = driver.table.cardActionPicker.actions;
        const action = actions.find(a => !/evoke|dash|disguise|morph|cycling/i.test(a.label)) || actions[0];
        if (action) driver.click("rulesCardAction-" + action.responseId);
        return true;
    }
    switch (s.promptKind) {
    case "mulligan":
        if (driver.existingLimitedMatch) {
            driver.require(s.zoneCount(ws.roomSession.seatIndex, "hand") === 7
                && s.zoneCount(ws.roomSession.seatIndex, "library") === 33,
                "Limited opening hand must be dealt from the locked 40-card deck");
            driver.capture("limited-opening-hand");
        }
        chooseOpeningHand(driver); return true;
    case "chooseAction": chooseAction(driver, options); return true;
    case "payManaCost": Common.pay(driver, options); return true;
    case "chooseBoolean": case "chooseFromSelection": case "chooseColor": scalar(driver); return true;
    case "chooseCards": case "mulliganPutBack": Common.chooseCards(driver); return true;
    case "chooseBoardTargets": Common.chooseTarget(driver); return true;
    case "chooseBlockers": chooseBlockers(driver); return true;
    case "scry": driver.click("confirmScryButton"); return true;
    case "chooseNumber": driver.click("rulesConfirmNumber"); return true;
    case "chooseCardName": {
        const input = driver.item("rulesCardNameInput");
        if (!input) return true;
        if (!input.text.length) {
            driver.click("rulesCardNameInput");
            driver.require(auditProbe.type("Island"), "Cannot enter a card name");
        } else driver.click("confirmCardNameButton");
        return true;
    }
    default: return false;
    }
}

function betweenGames(driver) {
    if (!ws.gameSession.sideboarding) return false;
    games[driver.session.gameId] = true;
    driver.require(ws.gameSession.result.concededSeat === -1, "Limited game must end naturally");
    const data = ws.gameSession.sideboard;
    const count = cards => cards.reduce((sum, c) => sum + c.count, 0);
    const key = c => [c.name, c.setCode || "", c.collectorNumber || ""].join("|");
    const partition = cards => cards.map(c => key(c) + "|" + c.count).sort().join(";");
    if (driver.existingLimitedMatch && sideboardStage < 8) {
        switch (sideboardStage) {
        case 0: {
            sideboardBefore = {main:partition(data.mainboard), side:partition(data.sideboard),
                mainCount:count(data.mainboard), sideCount:count(data.sideboard)};
            const source = driver.item("sideboardCard-sideboard-0"), target = driver.item("sideboardZone-mainboard");
            if (!source || !target) return true;
            movedCard = {name:source.name, setCode:source.setCode, collectorNumber:source.collectorNumber};
            driver.require(auditProbe.drag(source, target), "Cannot move a pool card into the Limited main deck");
            sideboardStage = 1; return true;
        }
        case 1:
            if (count(data.mainboard) !== sideboardBefore.mainCount + 1) return true;
            driver.require(count(data.sideboard) === sideboardBefore.sideCount - 1, "Sideboard move lost a pool card");
            driver.capture("limited-sideboard-edited");
            sideboardStage = 2; driver.interrupt("sideboard"); return true;
        case 2: {
            const findCard = node => {
                if (!node || !node.visible) return null;
                if ((node.objectName || "").startsWith("sideboardCard-mainboard-") && key(node) === key(movedCard)) return node;
                for (const child of node.children || []) { const found = findCard(child); if (found) return found; }
                return null;
            };
            const source = findCard(auditWindow.contentItem), target = driver.item("sideboardZone-sideboard");
            if (!source || !target) return true;
            driver.require(auditProbe.drag(source, target), "Cannot return the exact pool printing to the sideboard");
            sideboardStage = 3; return true;
        }
        case 3:
            if (count(data.mainboard) !== sideboardBefore.mainCount) return true;
            driver.require(partition(data.mainboard) === sideboardBefore.main && partition(data.sideboard) === sideboardBefore.side,
                "Sideboard round trip changed the exact card partition");
            basicName = (data.mainboard.find(c => !c.setCode && /^(Plains|Island|Swamp|Mountain|Forest)$/.test(c.name)) || {name:"Forest"}).name;
            if (driver.click("sideboardBasicLandsButton")) sideboardStage = 4;
            return true;
        case 4:
            if (driver.click("sideboardBasicAdd-" + basicName)) sideboardStage = 5;
            return true;
        case 5:
            if (count(data.mainboard) !== sideboardBefore.mainCount + 1) return true;
            driver.capture("limited-sideboard-basic-added");
            if (driver.click("sideboardBasicRemove-" + basicName)) sideboardStage = 6;
            return true;
        case 6:
            if (count(data.mainboard) !== sideboardBefore.mainCount) return true;
            driver.require(partition(data.mainboard) === sideboardBefore.main, "Basic-land adjustment changed pool cards");
            if (driver.item("sideboardToolsCloseButton")) driver.click("sideboardToolsCloseButton");
            else driver.click("sideboardBasicLandsButton");
            sideboardStage = 7; return true;
        case 7:
            driver.require(driver.sideboardResumed, "Edited Limited sideboard was not restored after reconnect");
            driver.capture("limited-sideboard");
            sideboardStage = 8; return true;
        }
    }
    if (!ws.gameSession.sideboard.seats.find(s => s.seat === ws.roomSession.seatIndex).ready)
        driver.click("sideboardReadyButton");
    return true;
}

function verifyComplete(driver) {
    if (!driver.existingLimitedMatch) return;
    driver.require(driver.liveResumed, "Limited match did not resume an actual combat decision");
    if (ws.roomSession.matchMode === "bo3")
        driver.require(Object.keys(games).length >= 2 && sideboardStage === 8 && driver.sideboardResumed,
            "Limited BO3 sideboarding, basic-land edits and next game were not exercised");
}
