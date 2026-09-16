// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Catalog-eligible mechanism decks, with ordinary four-copy limits. These are
// test strategies, not competitive lists; all game decisions use native UI.
var costs = {"Lightning Bolt":1, "Firebolt":1, "Ghitu Lavarunner":1,
    "Firebrand Archer":2, "Falkenrath Reaver":2, "Borderland Marauder":2,
    "Counterspell":2, "Preordain":1, "Mulldrifter":5, "Cloudkin Seer":3,
    "Wind Drake":3, "Watercourser":3};
var pendingDraw = null;
var observed = {};
var flashback = null;

function deck(seat) {
    var cards = seat === 1 ? [
        ["Mountain", "LEA", "293", "Basic Land — Mountain", 36],
        ["Lightning Bolt", "LEA", "161", "Instant"], ["Firebolt", "ODY", "193", "Sorcery"],
        ["Ghitu Lavarunner", "DOM", "127", "Creature"], ["Firebrand Archer", "HOU", "92", "Creature"],
        ["Falkenrath Reaver", "EMN", "127", "Creature"], ["Borderland Marauder", "M15", "131", "Creature"]
    ] : [
        ["Island", "LEA", "288", "Basic Land — Island", 36],
        ["Counterspell", "LEA", "54", "Instant"], ["Preordain", "M11", "70", "Sorcery"],
        ["Mulldrifter", "LRW", "76", "Creature"], ["Cloudkin Seer", "M20", "54", "Creature"],
        ["Wind Drake", "POR", "77", "Creature"], ["Watercourser", "M13", "78", "Creature"]];
    return {name:"Native Pauper " + (seat === 1 ? "burn and flashback" : "scry and draw"),
        format:"modern", deckFormat:"pauper", mainboard:cards.map(card => ({
            name:card[0], setCode:card[1], collectorNumber:card[2], typeLine:card[3],
            count:card[4] || 4})), sideboard:[]};
}
function note(driver, kind, value) {
    observed[kind] = value;
    auditProbe.share("pauper-" + driver.seat, observed);
    auditProbe.record("pauper-" + kind, value);
    driver.capture("pauper-" + kind);
}
function complete() {
    var a = auditProbe.readShared("pauper-1") || {};
    var b = auditProbe.readShared("pauper-2") || {};
    return a.flashback && b.scryDraw && b.etbDraw;
}
function cost(card) { return card.name === "Firebolt" && card.zone === "graveyard" ? 5 : costs[card.name]; }
function trackCast(driver, option) {
    var card = driver.session.cardForInspection(option.cardId);
    if (card.name === "Firebolt" && card.zone === "graveyard")
        flashback = {cardId:option.cardId, turn:driver.session.turn, sawStack:false};
}
function drawBefore(driver, kind, amount, stackId) {
    var own = ws.roomSession.seatIndex;
    pendingDraw = {kind:kind, amount:amount, stackId:stackId,
        hand:driver.session.zoneCount(own, "hand"), library:driver.session.zoneCount(own, "library")};
}
function observe(driver) {
    var session = driver.session;
    var own = ws.roomSession.seatIndex;
    var ids = session.stackObjectIds();
    // The pinned Preordain script uses a card subset followed by a reorder
    // callback. Its real-game UI path differs from the standalone scry callback.
    if (!pendingDraw && session.promptKind === "chooseCards"
        && /bottom of your library/i.test(session.promptTitle)
        && ids.some(id => session.cardForInspection(id).name === "Preordain")) {
        drawBefore(driver, "scryDraw", 1, ids.find(id => session.cardForInspection(id).name === "Preordain"));
        auditProbe.record("pauper-scry-candidates", session.promptCards.items());
        driver.capture("pauper-scry");
    }
    if (pendingDraw && !ids.includes(pendingDraw.stackId) && session.promptKind === "chooseAction") {
        var hand = session.zoneCount(own, "hand"), library = session.zoneCount(own, "library");
        driver.require(hand === pendingDraw.hand + pendingDraw.amount
            && library === pendingDraw.library - pendingDraw.amount, "Native draw changed the wrong number of cards");
        note(driver, pendingDraw.kind, Object.assign({}, pendingDraw, {handAfter:hand, libraryAfter:library}));
        pendingDraw = null;
    }
    if (!pendingDraw && !observed.etbDraw && ids.length) {
        var top = session.cardForInspection(ids[0]);
        if (top.controllerSeat === own && ["Cloudkin Seer", "Mulldrifter"].includes(top.name)
            && /draw (a|one|two|1|2) cards?/i.test(top.rulesText || ""))
            drawBefore(driver, "etbDraw", top.name === "Mulldrifter" ? 2 : 1, ids[0]);
    }
    if (flashback && !observed.flashback) {
        var card = session.cardForInspection(flashback.cardId);
        if (ids.some(id => session.cardForInspection(id).name === "Firebolt")) flashback.sawStack = true;
        if (flashback.sawStack && card.zone === "exile") {
            driver.require(card.ownerSeat === own, "Flashback changed the spell's owner");
            note(driver, "flashback", Object.assign({}, flashback, {destination:card.zone}));
        }
    }
}
function scry(driver) {
    if (!pendingDraw) {
        var ids = driver.session.stackObjectIds();
        driver.require(ids.length > 0, "Preordain scry has no resolving spell");
        drawBefore(driver, "scryDraw", 1, ids[0]);
        auditProbe.record("pauper-scry-candidates", driver.session.promptCards.items());
        driver.capture("pauper-scry");
    }
    driver.click("confirmScryButton");
}
