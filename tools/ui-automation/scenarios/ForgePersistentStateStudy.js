// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Actual human Forge prompts through production desktop controls. This bounded
// regression observes persistent choices and linked exile, not a whole match.
.import "ForgeBorosStudy.js" as Common

var fixture = null;
var observed = {};
var hoverDue = 0;
var stage = 0;
var returned = false;
var finished = false;

function deck(driver) {
    if (!fixture) {
        fixture = JSON.parse(auditProbe.readText(auditProbe.environment("HEXPROOF_AUDIT_DECK_MANIFEST")));
        driver.require(fixture.mainboard.reduce((sum, c) => sum + c.count, 0) === 60,
            "Persistent state fixture requires 60 registered cards");
    }
    return fixture;
}
function board(driver) {
    return Common.lanes(driver).map(c => driver.session.cardForInspection(c.cardId));
}
function save(driver, name) {
    driver.capture(name);
    auditProbe.record(name, {board:board(driver), observed:observed, returned:returned});
}
function hover(driver, id, expected, name) {
    var tile = driver.item("forgeCard-" + id);
    driver.require(!!tile && tile.persistentSummary.includes(expected), "Battlefield summary missing " + expected);
    if (!hoverDue) {
        driver.require(auditProbe.hover(tile), "Cannot hover over the annotated permanent");
        hoverDue = Date.now() + 900;
    }
    if (Date.now() < hoverDue) return false;
    var preview = driver.table.presentation.children.find(c => c.objectName === "rulesCardHoverPreview");
    var label = preview && preview.children.find(c => c.objectName === "rulesCardHoverLinkedCards");
    driver.require(!!preview && preview.visible && !!label && label.visible && label.text.includes(expected),
        "Hover summary missing " + expected);
    save(driver, name); hoverDue = 0;
    return true;
}
function finish(driver) {
    finished = true;
    auditProbe.record("result", {status:"passed", scenario:"forge-persistent-state",
        evidence:auditProbe.environment("AUDIT_OS_INPUT_HELPER") ? "system-input" : "native-qt-input",
        scope:"bounded Pithing Needle and Ugin's Labyrinth regression, not a completed match", seat:driver.seat,
        namedCard:observed.namedCard, linkedCard:observed.linkedName, clearedAfterReturn:true,
        requiredScreenshots:["opening.png", "named-permanent.png", "linked-permanent.png", "link-cleared.png"]});
    auditProbe.finish(0);
}
function tick(driver) {
    if (finished) return true;
    var s = driver.session;
    if (driver.seat === 1 && stage === 0) {
        var ours = board(driver).filter(c => c.controllerSeat === ws.roomSession.seatIndex);
        var needle = ours.find(c => c.name === "Pithing Needle" && (c.annotations || []).length);
        var maze = ours.find(c => c.name === "Ugin's Labyrinth" && c.exiledCardCount > 0);
        if (!needle || !maze) return false;
        var linked = s.cardForInspection(maze.exiledCardIds[0]);
        driver.require(linked.zone === "exile" && linked.visibleIdentity, "Imprint identity unavailable");
        observed = {needleId:needle.cardId, namedCard:needle.annotations[0].value,
            mazeId:maze.cardId, linkedId:linked.cardId, linkedName:linked.name};
        stage = 1;
    }
    if (driver.seat === 2 && stage === 0) {
        observed = auditProbe.readShared("persistent-state") || {};
        if (!observed.mazeId) return false;
        if (!s.cardForInspection(observed.mazeId).exiledCardCount) return true;
        stage = 1;
    }
    if (stage === 1) {
        if (hover(driver, observed.needleId, observed.namedCard, "named-permanent")) stage = 2;
        return true;
    }
    if (stage === 2) {
        if (hover(driver, observed.mazeId, observed.linkedName, "linked-permanent")) {
            if (driver.seat === 1) auditProbe.share("persistent-state", observed);
            else auditProbe.share("persistent-state-observer", {linked:true});
            stage = 3;
        }
        return true;
    }
    if (stage === 3 && driver.seat === 1) {
        if (!(auditProbe.readShared("persistent-state-observer") || {}).linked) return true;
        if (!s.cardForInspection(observed.mazeId).exiledCardCount) {
            driver.require(s.cardForInspection(observed.linkedId).zone === "hand", "Returned imprint is not in hand");
            driver.require(!driver.item("forgeCard-" + observed.mazeId).persistentSummary.includes(observed.linkedName),
                "Returned card remains in the battlefield summary");
            returned = true; save(driver, "link-cleared");
            auditProbe.share("persistent-state-returned", {done:true}); stage = 4;
        }
    }
    if (stage === 3 && driver.seat === 2 && (auditProbe.readShared("persistent-state-returned") || {}).done) {
        if (s.cardForInspection(observed.mazeId).exiledCardCount) return true;
        driver.require(!driver.item("forgeCard-" + observed.mazeId).persistentSummary.includes(observed.linkedName),
            "Opponent retained the old linked identity");
        save(driver, "link-cleared");
        auditProbe.share("persistent-state-observer", {done:true}); finish(driver); return true;
    }
    if (stage === 4) {
        if ((auditProbe.readShared("persistent-state-observer") || {}).done) finish(driver);
        return true;
    }
    return false;
}
function act(driver) {
    var s = driver.session, options = s.promptOptionItems();
    if (driver.seat === 2) {
        if (s.promptKind === "chooseAction") { driver.click("rulesPromptOption-$pass"); return true; }
        if (s.promptKind === "chooseAttackers") { driver.click("rulesConfirmCombat-attackers"); return true; }
        if (s.promptKind === "chooseCards") { Common.chooseCards(driver); return true; }
        return false;
    }
    switch (s.promptKind) {
    case "chooseAction": {
        if (stage === 3 && !returned) {
            var ability = options.find(o => o.cardId === observed.mazeId && o.kind === "activateAbility");
            if (ability) { driver.cardAction(ability); return true; }
        }
        var ours = board(driver).filter(c => c.controllerSeat === ws.roomSession.seatIndex);
        var hand = driver.item("forgeHand").visibleCards;
        var hasBigCard = hand.some(c => ["Ugin, Eye of the Storms", "Ulamog, the Ceaseless Hunger"].includes(c.name));
        var land = hasBigCard && !ours.some(c => c.name === "Ugin's Labyrinth")
            && options.find(o => o.kind === "playLand" && s.cardForInspection(o.cardId).name === "Ugin's Labyrinth");
        land = land || options.find(o => o.kind === "playLand" && s.cardForInspection(o.cardId).name === "Plains");
        if (land) { driver.cardAction(land); return true; }
        var needle = !ours.some(c => c.name === "Pithing Needle") && driver.availableMana() > 0
            && options.find(o => o.kind === "cast" && s.cardForInspection(o.cardId).name === "Pithing Needle");
        if (needle) { driver.cardAction(needle); return true; }
        driver.click("rulesPromptOption-$pass"); return true;
    }
    case "payManaCost": Common.pay(driver, options); return true;
    case "chooseCardName": {
        var input = driver.item("rulesCardNameInput");
        if (!input) return true;
        if (!input.text.length) {
            driver.click("rulesCardNameInput");
            driver.require(auditProbe.type("Lightning Bolt"), "Cannot type a card name");
        } else driver.click("confirmCardNameButton");
        return true;
    }
    case "chooseBoolean":
        if (/Use triggered ability of Ugin's Labyrinth/.test(s.promptTitle + " " + s.promptDetail))
            driver.click("rulesScalarChoice-choice:1");
        else Common.chooseScalar(driver);
        return true;
    case "chooseFromSelection": {
        var choices = Common.scalarChoices(driver.item("rulesScalarCandidates"));
        var returnCard = stage === 3 && choices.find(c => /Return the exiled card/.test(c.label));
        if (returnCard && !choices.some(c => c.count > 0))
            driver.click("rulesScalarChoice-" + returnCard.responseId);
        else Common.chooseScalar(driver);
        return true;
    }
    case "chooseCards": {
        var list = driver.item("rulesCardCandidates"), confirm = driver.item("rulesConfirmCards");
        if (!list) return true;
        var rows = [];
        for (var i = 0; i < list.count; i++)
            if (list.itemAtIndex(i) && list.itemAtIndex(i).selectable) rows.push(list.itemAtIndex(i));
        var wanted = Math.max(1, s.promptMinCardSelections);
        if (rows.filter(c => c.selected).length >= wanted && confirm && confirm.enabled) {
            driver.click("rulesConfirmCards"); return true;
        }
        var next = rows.find(c => !c.selected && c.name === "Plains") || rows.find(c => !c.selected);
        if (next) driver.click(next.objectName);
        return true;
    }
    case "chooseAttackers": driver.click("rulesConfirmCombat-attackers"); return true;
    default: return false;
    }
}
