// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Choose, inspect and blink a real Dauntless Bodyguard's chosen creature.
.import "ForgeBorosStudy.js" as Common
.import "ForgePersistentStateStudy.js" as Persistent

var observed = {};
var stage = 0;
var finished = false;

function deck(driver) { return Persistent.deck(driver); }
function board(driver) { return Persistent.board(driver); }
function finish(driver) {
    finished = true;
    auditProbe.record("result", {status:"passed", scenario:"forge-chosen-card",
        evidence:auditProbe.environment("AUDIT_OS_INPUT_HELPER") ? "system-input" : "native-qt-input",
        scope:"bounded chosen-creature and blink regression, not a completed match", seat:driver.seat,
        chosenCard:observed.name, clearedAfterBlink:true,
        requiredScreenshots:["opening.png", "chosen-permanent.png", "chosen-link-cleared.png"]
            .concat(driver.seat === 1 ? ["chosen-card-selection.png"] : [])});
    auditProbe.finish(0);
}
function tick(driver) {
    if (finished) return true;
    var s = driver.session;
    if (stage === 0) {
        if (driver.seat === 1) {
            var source = board(driver).find(c => c.name === "Dauntless Bodyguard" && (c.chosenCardIds || []).length);
            if (!source) return false;
            var target = s.cardForInspection(source.chosenCardIds[0]);
            driver.require(target.visibleIdentity && target.zone === "battlefield", "Chosen creature is not visible");
            observed = {source:source.cardId, target:target.cardId, name:target.name};
        } else {
            observed = auditProbe.readShared("chosen-card") || {};
            if (!observed.source) return false;
            if (!(s.cardForInspection(observed.source).chosenCardIds || []).length) return true;
        }
        stage = 1;
    }
    if (stage === 1) {
        if (Persistent.hover(driver, observed.source, observed.name, "chosen-permanent")) {
            auditProbe.record("chosen-creature", observed);
            if (driver.seat === 1) auditProbe.share("chosen-card", observed);
            else auditProbe.share("chosen-card-observer", {checked:true});
            stage = 2;
        }
        return true;
    }
    if (stage === 2) {
        var observer = auditProbe.readShared("chosen-card-observer") || {};
        if (driver.seat === 1 && !observer.checked && !observer.done) return true;
        var source = s.cardForInspection(observed.source), target = s.cardForInspection(observed.target);
        if ((source.chosenCardIds || []).length || target.zone !== "battlefield") return false;
        driver.require(driver.item("forgeCard-" + observed.source).persistentSummary.length === 0,
            "Old choice reattached after the chosen creature blinked");
        driver.capture("chosen-link-cleared");
        auditProbe.record("chosen-link-cleared", {source:source, target:target});
        if (driver.seat === 1) {
            auditProbe.share("chosen-card-cleared", {done:true}); stage = 3;
        } else {
            auditProbe.share("chosen-card-observer", {done:true}); finish(driver);
        }
        return true;
    }
    if (stage === 3) {
        if ((auditProbe.readShared("chosen-card-observer") || {}).done) finish(driver);
        return true;
    }
    return false;
}
function act(driver) {
    var s = driver.session, options = s.promptOptionItems();
    if (s.promptKind === "chooseAttackers") { driver.click("rulesConfirmCombat-attackers"); return true; }
    if (s.promptKind === "chooseCards") {
        if (/Dauntless Bodyguard/.test(s.promptDetail)) {
            var list = driver.item("rulesCardCandidates");
            if (list && Array.from({length:list.count}, (_, i) => list.itemAtIndex(i)).some(c => c && c.selected))
                driver.capture("chosen-card-selection");
        }
        Common.chooseCards(driver); return true;
    }
    if (s.promptKind === "chooseAction") {
        if (driver.seat === 2) { driver.click("rulesPromptOption-$pass"); return true; }
        var ours = board(driver).filter(c => c.controllerSeat === ws.roomSession.seatIndex);
        var land = options.find(o => o.kind === "playLand");
        if (land) { driver.cardAction(land); return true; }
        var desired = stage === 2 ? ["Cloudshift"]
            : ours.filter(c => ["Ornithopter", "Memnite", "Silvercoat Lion"].includes(c.name)).length >= 2
              ? ["Dauntless Bodyguard"] : ["Ornithopter", "Memnite", "Silvercoat Lion"];
        var spell = options.find(o => o.kind === "cast" && desired.includes(s.cardForInspection(o.cardId).name));
        if (spell && driver.availableMana() >= (s.cardForInspection(spell.cardId).name === "Silvercoat Lion" ? 2 : 1)) {
            driver.cardAction(spell); return true;
        }
        driver.click("rulesPromptOption-$pass"); return true;
    }
    if (s.promptKind === "payManaCost") { Common.pay(driver, options); return true; }
    if (s.promptKind === "chooseBoardTargets" && stage === 2) {
        var target = s.boardTargetCandidates().find(c => c.objectId === observed.target);
        driver.require(!!target, "Blink must target the actual chosen creature");
        if (driver.table.interaction.selectedCount >= s.promptMinSelections)
            driver.click("rulesConfirmTargets");
        else driver.click("forgeCard-" + target.objectId);
        return true;
    }
    if (["chooseBoolean", "chooseFromSelection", "chooseColor"].includes(s.promptKind)) {
        Common.chooseScalar(driver); return true;
    }
    return false;
}
