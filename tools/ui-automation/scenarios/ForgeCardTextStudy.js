// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Natural draws and production casting controls; this bounded fixture is not
// a tournament list or a completed game. Cancel each inspected spell's payment.
.import "ForgeBorosStudy.js" as Common
.import "ForgePersistentStateStudy.js" as Persistent

var observed = {};
var current = null;
var optionalCost = false;
var finished = false;
var partialPayment = false;
var partialSource = "";
var labels = {"Duress":"duress", "Deadly Cover-Up":"deadly-cover-up", "Shallow Grave":"shallow-grave"};
var costs = {"Duress":1, "Deadly Cover-Up":5, "Shallow Grave":2};
var paymentCosts = {"Duress":"{B}", "Deadly Cover-Up":"{3}{B}{B}", "Shallow Grave":"{1}{B}"};

function deck(driver) { return Persistent.deck(driver); }
function finish(driver) {
    finished = true;
    auditProbe.record("result", {status:"passed", scenario:"forge-card-text",
        evidence:auditProbe.environment("AUDIT_OS_INPUT_HELPER") ? "system-input" : "native-qt-input",
        scope:"bounded payment text and modal context regression, not a completed match", seat:driver.seat,
        payments:observed, optionalCost:optionalCost, partialPayment:partialPayment,
        requiredScreenshots:["opening.png"].concat(driver.seat === 1
            ? ["duress.png", "deadly-cover-up.png", "shallow-grave.png", "shallow-grave-partial.png", "optional-cost.png"] : [])});
    auditProbe.finish(0);
}
function tick(driver) {
    if (finished) return true;
    if (driver.seat === 2) {
        if ((auditProbe.readShared("card-text") || {}).done) {
            auditProbe.share("card-text-observer", {done:true});
            finish(driver);
            return true;
        }
        return false;
    }
    if (current && observed[current.name] && driver.session.promptKind === "chooseAction"
            && driver.session.promptPending && !ws.rulesResponsePending) {
        driver.require(driver.session.cardForInspection(current.id).zone === "hand"
            && driver.session.stackObjectIds().length === 0, "Cancelled payment changed card zones");
        if (current.name === "Shallow Grave")
            driver.require(partialPayment && !driver.session.cardForInspection(partialSource).tapped,
                "Cancelled partial payment did not restore the mana source");
        current = null;
    }
    if (Object.keys(observed).length !== 3 || !optionalCost || !partialPayment || current) return false;
    auditProbe.share("card-text", {done:true});
    if ((auditProbe.readShared("card-text-observer") || {}).done) finish(driver);
    return true;
}
function act(driver) {
    var s = driver.session, options = s.promptOptionItems();
    if (s.promptKind === "chooseAction") {
        if (driver.seat === 2) { driver.click("rulesPromptOption-$pass"); return true; }
        var land = options.find(o => o.kind === "playLand");
        if (land) { driver.cardAction(land); return true; }
        var mana = Persistent.board(driver).filter(c => c.controllerSeat === ws.roomSession.seatIndex
            && c.name === "Swamp" && !c.tapped).length;
        var spell = options.find(o => o.kind === "cast" && !observed[s.cardForInspection(o.cardId).name]
            && mana >= costs[s.cardForInspection(o.cardId).name]);
        if (spell) {
            current = {id:spell.cardId, name:s.cardForInspection(spell.cardId).name};
            driver.cardAction(spell);
            return true;
        }
        driver.click("rulesPromptOption-$pass"); return true;
    }
    if (s.promptKind === "payManaCost") {
        driver.require(driver.seat === 1 && current !== null, "Unexpected payment in the card text fixture");
        var text = s.promptDetail;
        driver.require(!/Card\.nonCreature|Card\.OppCtrl|Remembered\.sameName|Creature\.TopGraveyardCreature/.test(text),
            "Internal selector reached payment UI: " + text);
        driver.require(text.includes("Pay Mana Cost:"), "Payment text lost the live cost");
        if (current.name === "Duress") driver.require(text.includes("noncreature, nonland"), "Duress restriction missing");
        if (current.name === "Deadly Cover-Up") driver.require(text.includes("If evidence was collected")
            && !text.includes("up to zero"), "Evidence condition is misleading");
        if (current.name === "Shallow Grave") driver.require(text.includes("top creature card")
            && text.split("gains haste").length === 2, "Shallow Grave description is incomplete or duplicated");
        var detail = driver.item("rulesPromptDetail");
        driver.require(detail && detail.visible && detail.text.includes(text), "Readable description is absent from the visible label");
        var title = driver.item("rulesPromptTitle");
        var remaining = current.name === "Shallow Grave" && partialSource ? "{1}" : paymentCosts[current.name];
        driver.require(title && title.visible && !title.truncated && title.text.includes(remaining),
            "Live mana cost is missing from the visible payment heading");
        if (current.name === "Shallow Grave" && partialSource) {
            driver.require(!title.text.includes("{B}") && s.cardForInspection(partialSource).tapped,
                "Payment heading retained the paid black mana");
            driver.capture("shallow-grave-partial"); partialPayment = true;
            auditProbe.record("shallow-grave-partial", {title:title.text, detail:text, source:partialSource});
            driver.click("rulesPromptOption-$cancel"); return true;
        }
        var name = labels[current.name];
        driver.capture(name);
        observed[current.name] = text;
        auditProbe.record(name, {detail:text, observation:auditProbe.observe(auditWindow)});
        driver.require(options.some(o => o.responseId === "$cancel"), "Payment must be cancellable");
        if (current.name === "Shallow Grave") {
            var mana = options.find(o => o.kind === "activateAbility" && s.cardForInspection(o.cardId).name === "Swamp");
            driver.require(!!mana, "Partial payment needs an explicit Swamp mana action");
            if (driver.cardAction(mana)) partialSource = mana.cardId;
            return true;
        }
        driver.click("rulesPromptOption-$cancel"); return true;
    }
    if (s.promptKind === "chooseFromSelection" && s.promptTitle === "Choose optional costs") {
        driver.require(current && current.name === "Deadly Cover-Up" && s.promptDetail.length === 0,
            "Optional-cost dialog inherited another decision's text");
        driver.capture("optional-cost"); optionalCost = true;
        auditProbe.record("optional-cost", {title:s.promptTitle, detail:s.promptDetail, options:options});
        driver.click("rulesConfirmChoices"); return true;
    }
    if (s.promptKind === "chooseCards") { Common.chooseCards(driver); return true; }
    if (s.promptKind === "chooseAttackers") { driver.click("rulesConfirmCombat-attackers"); return true; }
    return false;
}
