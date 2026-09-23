// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Reach graveyard targeting through natural draws and end-step discards, then
// cancel twice and resolve a real Goryo's Vengeance through production controls.
.import "ForgeBorosStudy.js" as Common
.import "ForgePersistentStateStudy.js" as Persistent

var cancelled = 0;
var selected = 0;
var spell = "";
var target = "";
var paid = false;
var finished = false;
var targetPrompts = {};

function deck(driver) { return Persistent.deck(driver); }
function finish(driver) {
    finished = true;
    auditProbe.record("result", {status:"passed", scenario:"forge-graveyard-payment",
        evidence:auditProbe.environment("AUDIT_OS_INPUT_HELPER") ? "system-input" : "native-qt-input",
        scope:"bounded target-to-payment and reanimation study, not a completed match", seat:driver.seat,
        cancelled:cancelled, selected:selected, resolvedTarget:target,
        requiredScreenshots:["opening.png", "reanimated.png"].concat(driver.seat === 1
            ? ["graveyard-target-1.png", "graveyard-target-2.png", "graveyard-target-3.png",
               "payment-1.png", "payment-2.png", "payment-3.png"] : [])});
    auditProbe.finish(0);
}
function tick(driver) {
    if (finished) return true;
    if (driver.seat === 2) {
        var shared = auditProbe.readShared("graveyard-payment") || {};
        if (!shared.target) return false;
        var card = driver.session.cardForInspection(shared.target);
        if (card.zone !== "battlefield" || card.name !== "Atraxa, Grand Unifier") return true;
        target = card.cardId;
        driver.require(auditProbe.hover(driver.item("forgeGameMenu")), "Cannot move away from the hand preview");
        driver.capture("reanimated");
        auditProbe.share("graveyard-payment-observer", {done:true}); finish(driver);
        return true;
    }
    if (!paid || driver.session.stackObjectIds().length !== 0) return false;
    // A resolving trigger can already be off the stack while its human menu
    // remains pending. Complete Atraxa's reveal/selection before recording done.
    if (ws.rulesResponsePending || !driver.session.promptPending || driver.session.promptKind !== "chooseAction") return false;
    var reanimated = Persistent.board(driver).find(c => c.name === "Atraxa, Grand Unifier"
        && c.controllerSeat === ws.roomSession.seatIndex);
    if (!reanimated) return false;
    driver.require(cancelled === 2 && selected === 3 && reanimated.cardId === target
        && driver.session.cardForInspection(spell).zone === "graveyard",
        "Goryo's Vengeance did not resolve the explicitly selected creature");
    driver.require(auditProbe.hover(driver.item("forgeGameMenu")), "Cannot move away from the hand preview");
    driver.capture("reanimated");
    auditProbe.record("resolved-priority", {promptId:driver.session.promptId, kind:driver.session.promptKind,
        responsePending:ws.rulesResponsePending, stack:driver.session.stackObjectIds(), creature:reanimated});
    auditProbe.share("graveyard-payment", {target:target});
    if ((auditProbe.readShared("graveyard-payment-observer") || {}).done) finish(driver);
    return true;
}
function act(driver) {
    var s = driver.session, options = s.promptOptionItems();
    if (s.promptKind === "chooseAction") {
        if (driver.seat === 2 || paid) { driver.click("rulesPromptOption-$pass"); return true; }
        var mana = Persistent.board(driver).filter(c => c.controllerSeat === ws.roomSession.seatIndex
            && c.name === "Swamp" && !c.tapped).length;
        var land = mana < 2 && options.find(o => o.kind === "playLand");
        if (land) { driver.cardAction(land); return true; }
        var top = s.topPublicZoneCard(ws.roomSession.seatIndex, "graveyard");
        var cast = mana >= 2 && top.name === "Atraxa, Grand Unifier" && options.find(o => o.kind === "cast"
            && s.cardForInspection(o.cardId).name === "Goryo's Vengeance");
        if (cast) {
            if (cancelled > 0) driver.require(s.cardForInspection(spell).zone === "hand"
                && s.cardForInspection(target).zone === "graveyard", "Cancelled targeted cast changed zones");
            spell = cast.cardId; driver.cardAction(cast); return true;
        }
        driver.click("rulesPromptOption-$pass"); return true;
    }
    if (s.promptKind === "chooseBoardTargets") {
        driver.require(driver.seat === 1 && s.promptDetail.includes("Goryo's Vengeance"), "Unexpected target input");
        var legal = s.boardTargetCandidates();
        driver.require(legal.length === 1 && legal.every(c => s.cardForInspection(c.objectId).name === "Atraxa, Grand Unifier"
            && s.cardForInspection(c.objectId).zone === "graveyard"), "Target picker exposed an ineligible creature");
        if (!targetPrompts[s.promptId]) {
            targetPrompts[s.promptId] = true; selected++;
            target = legal[0].objectId;
            driver.capture("graveyard-target-" + (cancelled + 1));
            auditProbe.record("graveyard-target-" + (cancelled + 1), {candidates:legal, selectedTarget:target});
        }
        if (driver.table.interaction.selectedCount >= s.promptMinSelections) {
            var chosen = legal.find(c => driver.table.interaction.selectedTargetIds[c.responseId]);
            driver.require(!!chosen, "Missing explicit graveyard target");
            target = chosen.objectId;
            driver.capture("graveyard-target-" + (cancelled + 1));
            driver.click("rulesConfirmTargets");
        } else Common.chooseTarget(driver);
        return true;
    }
    if (s.promptKind === "payManaCost") {
        driver.require(driver.seat === 1 && s.promptDetail.includes("Atraxa, Grand Unifier")
            && s.promptTitle.includes("{1}{B}"), "Target or live cost was lost during payment transition");
        driver.capture("payment-" + (cancelled + 1));
        auditProbe.record("payment-" + (cancelled + 1), {title:s.promptTitle, detail:s.promptDetail,
            target:target, observation:auditProbe.observe(auditWindow)});
        if (cancelled < 2) {
            if (driver.click("rulesPromptOption-$cancel")) cancelled++;
        } else if (driver.click("rulesPromptOption-$auto-pay")) paid = true;
        return true;
    }
    if (s.promptKind === "chooseCards") {
        var list = driver.item("rulesCardCandidates"), confirm = driver.item("rulesConfirmCards");
        if (driver.seat === 1 && !paid && list) {
            var rows = Array.from({length:list.count}, (_, i) => list.itemAtIndex(i)).filter(c => c);
            var count = rows.filter(c => c.selected).length;
            var atraxa = rows.find(c => c.name === "Atraxa, Grand Unifier" && !c.selected);
            if (count < s.promptMinCardSelections && atraxa) { driver.click(atraxa.objectName); return true; }
            if (confirm && confirm.enabled && count >= s.promptMinCardSelections) {
                driver.click("rulesConfirmCards"); return true;
            }
        }
        Common.chooseCards(driver); return true;
    }
    if (s.promptKind === "chooseAttackers") { driver.click("rulesConfirmCombat-attackers"); return true; }
    if (["chooseBoolean", "chooseFromSelection", "chooseColor"].includes(s.promptKind)) {
        Common.chooseScalar(driver); return true;
    }
    return false;
}
