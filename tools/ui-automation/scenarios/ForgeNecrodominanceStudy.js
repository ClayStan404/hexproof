// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Natural opening hands and draws. Room/deck setup is disclosed; all game
// decisions use production controls with Smart priority and no end-step stop.
.import "ForgeBorosStudy.js" as Common

var fixture = null;
var phase = "opening";
var mulligans = 0;
var necroId = "";
var instantId = "";
var before = null;
var drawAmount = 0;
var drawRounds = 0;
var stablePrompt = -1;
var stableUntil = 0;
var discardedIds = [];
var evidence = {};
var finished = false;
var inputLayoutKey = "";
var inputLayoutReadyAt = 0;

function deck(driver) {
    if (!fixture) {
        fixture = JSON.parse(auditProbe.readText(auditProbe.environment("HEXPROOF_AUDIT_DECK_MANIFEST")));
        driver.require(fixture.mainboard.reduce((sum, card) => sum + card.count, 0) === 60
            && fixture.mainboard.find(card => card.name === "Necrodominance").count === 4
            && fixture.mainboard.find(card => card.name === "Darkness").count === 4,
            "Necrodominance study requires its legal 60-card four-copy fixture");
    }
    return fixture;
}
function state() {
    return {phase:phase, mulligans:mulligans, necroId:necroId, instantId:instantId,
        before:before, drawAmount:drawAmount, drawRounds:drawRounds, stablePrompt:stablePrompt,
        discardedIds:discardedIds, evidence:evidence};
}
function find(item, name) {
    if (!item) return null;
    if (item.objectName === name) return item;
    for (var child of item.children || []) {
        var result = find(child, name);
        if (result) return result;
    }
    return null;
}
function counts(driver, seat) {
    var plate = find(driver.table.presentation, "forgeField-" + seat)
        || find(driver.table.presentation, "rulesPlayerTarget" + seat);
    driver.require(!!plate && typeof plate.life === "number", "Rendered player field has no numeric life role");
    return {hand:driver.session.zoneCount(seat, "hand"), library:driver.session.zoneCount(seat, "library"),
        exile:driver.session.zoneCount(seat, "exile"), graveyard:driver.session.zoneCount(seat, "graveyard"),
        life:plate.life};
}
function hand(driver) {
    var lane = Common.laneItems(driver, true).find(item => item.objectName === "forgeHand");
    return lane ? lane.visibleCards : [];
}
function requireSmart(driver) {
    var priority = driver.table.priority;
    driver.require(!priority.fullControl && !priority.hasStop("end", true)
        && !priority.hasStop("end", false) && !priority.holdNextPriority && !priority.heldPrompt
        && !priority.yieldMode, "Necrodominance study must use Smart priority without stops, holds or yields");
}
function lifePaymentPromptMatches(session, currentPhase, sourceId) {
    var source = session.cardForInspection(sourceId);
    return ["wait-trigger", "seek-next-trigger", "number-input"].includes(currentPhase)
        && session.step === "end" && session.activeSeat === 0
        && source.zone === "battlefield" && source.name === "Necrodominance"
        && session.promptTitle === "Choose X for Necrodominance";
}
function lifePaymentConfirmationMatches(session, currentPhase, sourceId, amount) {
    var source = session.cardForInspection(sourceId);
    return currentPhase === "wait-draw" && amount > 0
        && session.promptKind === "chooseBoolean" && session.step === "end" && session.activeSeat === 0
        && source.zone === "battlefield" && source.name === "Necrodominance"
        && session.promptTitle === "Confirm decision"
        && session.promptDetail === "Do you want to pay " + amount + " life?";
}
function confirmLifePayment(driver, currentPhase, sourceId, amount) {
    driver.require(lifePaymentConfirmationMatches(driver.session, currentPhase, sourceId, amount),
        "Unexpected Necrodominance life-payment confirmation");
    var yes = Common.scalarChoices(driver.item("rulesScalarCandidates")).find(row => row.label === "Yes");
    if (yes && driver.click("rulesScalarChoice-" + yes.responseId))
        evidence.confirmedLifePayments = (evidence.confirmedLifePayments || 0) + 1;
}
function resetInputLayout() {
    inputLayoutKey = "";
    inputLayoutReadyAt = 0;
}
function recoverPassMenu(driver, escape) {
    if (!driver.table.priority.passMenuOpen) return false;
    driver.require(escape(), "Cannot dismiss an unintended priority menu");
    resetInputLayout();
    evidence.dismissedPassMenus = (evidence.dismissedPassMenus || 0) + 1;
    return true;
}
function inputLayoutReady(driver, now, pending) {
    var view = driver.table.presentation;
    if (view.stagingMotion || pending || driver.table.priority.automaticallyPassing
            || driver.table.priority.passMenuOpen
            || (driver.table.priorityInputBlocked && !view.decisionDialogActive)) {
        resetInputLayout();
        return false;
    }
    var geometry = [driver.session.promptId, driver.session.promptKind,
        driver.table.width, driver.table.height];
    for (var name of ["rulesActionBar", "rulesPromptOption-$pass", "forgeHand",
            "rulesNumberInput", "rulesConfirmNumber", "rulesCardCandidates"]) {
        var control = driver.item(name);
        if (!control || !control.visible) continue;
        var point = control.mapToItem(driver.table, 0, 0);
        geometry.push(name, point.x, point.y, control.width, control.height);
    }
    var key = JSON.stringify(geometry);
    if (key !== inputLayoutKey) {
        inputLayoutKey = key;
        inputLayoutReadyAt = now + 500;
    }
    return now >= inputLayoutReadyAt;
}
function save(driver, name) {
    driver.capture(name);
    auditProbe.record(name, Object.assign(state(), {promptId:driver.session.promptId,
        promptKind:driver.session.promptKind, step:driver.session.step,
        autoPassEligible:driver.session.promptAutoPassEligible,
        automaticallyPassing:driver.table.priority.automaticallyPassing,
        fullControl:driver.table.priority.fullControl, counts:counts(driver, 0)}));
}
function finish(driver) {
    finished = true;
    save(driver, "necro-finished");
    auditProbe.record("result", {status:"passed", scenario:"necrodominance-smart", seat:driver.seat,
        evidence:auditProbe.environment("AUDIT_OS_INPUT_HELPER") ? "system-input" : "native-qt-input",
        scope:"bounded natural Necrodominance end-step regression; not a completed match",
        roomAndDeckSetup:"fixture", gameActions:"production-controls", review:evidence,
        requiredScreenshots:["opening.png", "necro-finished.png"].concat(driver.seat === 1
            ? ["necro-battlefield.png", "necro-life-payment.png", "necro-after-draw.png",
               "necro-retained-priority.png", "necro-instant-resolved.png", "necro-cleanup.png"] : [])});
    auditProbe.finish(0);
}
function tick(driver) {
    if (finished) return true;
    var s = driver.session;
    requireSmart(driver);
    // Native delivery can pump layout events between lookup and the click.
    // Closing the accidental menu does not select a yield or hold priority.
    if (recoverPassMenu(driver, () => auditProbe.key(Qt.Key_Escape))) return true;
    if (driver.seat !== 1) {
        var shared = auditProbe.readShared("necro-complete") || {};
        if (!shared.done) return false;
        var now = counts(driver, 0);
        if (now.hand !== 5 || now.exile !== shared.exileCount) return true;
        driver.require(now.graveyard === 0 && s.cardForInspection(shared.necroId).zone === "battlefield"
            && s.cardForInspection(shared.instantId).zone === "exile"
            && shared.discardedIds.every(id => s.cardForInspection(id).zone === "exile"),
            "Opponent projection did not observe the real instant and cleanup exile replacements");
        evidence = shared;
        auditProbe.share("necro-observer", {done:true}); finish(driver); return true;
    }
    if (ws.rulesResponsePending) return false;
    if (phase === "wait-necro" && s.cardForInspection(necroId).zone === "battlefield") {
        evidence.smartMode = true; evidence.noEndStopsHoldsOrYields = true;
        save(driver, "necro-battlefield"); phase = "wait-trigger";
    }
    if (phase === "wait-draw") {
        var drawn = counts(driver, 0);
        if (drawn.life !== before.life - drawAmount || drawn.hand !== before.hand + drawAmount) return false;
        driver.require(drawn.library === before.library - drawAmount, "Necrodominance draw changed the wrong library count");
        var darkness = hand(driver).find(card => card.name === "Darkness");
        evidence.drawAmount = drawAmount; evidence.handAfterDraw = drawn.hand;
        evidence.lifeAfterDraw = drawn.life;
        save(driver, "necro-after-draw");
        if (!darkness) {
            driver.require(drawRounds < 3, "No Darkness after three natural Necrodominance draws");
            phase = "seek-next-trigger"; return false;
        }
        instantId = darkness.cardId;
        driver.require(Common.basicMana(driver, 0) >= 1, "No reserved Swamp to cast the post-draw instant");
        phase = "wait-window";
    }
    if (phase === "wait-window" || phase === "stable-window") {
        if (s.step === "cleanup" || (s.promptPending && s.promptKind === "chooseCards")) {
            save(driver, "necro-skipped-priority");
            driver.require(false, "Smart priority skipped the payable post-Necrodominance end-step instant and reached cleanup");
        }
        if (!s.promptPending || s.promptKind !== "chooseAction") return false;
        driver.require(s.step === "end" && s.stackObjectIds().length === 0
            && s.promptOptionItems().some(option => option.kind === "cast" && option.cardId === instantId),
            "Post-draw end-step priority did not expose the actual Darkness cast");
        if (driver.table.presentation.stagingMotion || driver.table.priorityInputBlocked
                || ws.rulesResponsePending || driver.table.priority.automaticallyPassing) {
            phase = "wait-window";
            return true;
        }
        if (phase === "wait-window") {
            driver.require(s.promptAutoPassEligible === false, "Payable Darkness was incorrectly eligible for automatic passing");
            stablePrompt = s.promptId; stableUntil = Date.now() + 2000; phase = "stable-window";
        }
        // Let the old 80 ms auto-pass visibly advance to cleanup. The fixed
        // policy must retain the same prompt until the real hand-card click.
        if (Date.now() < stableUntil) return true;
        driver.require(s.promptId === stablePrompt && !driver.table.priority.automaticallyPassing,
            "Smart priority did not retain the post-draw action window");
        evidence.retainedPrompt = stablePrompt; evidence.stableWindowMs = 2000;
        save(driver, "necro-retained-priority"); phase = "cast-instant";
    }
    if (phase === "wait-instant" && s.cardForInspection(instantId).zone === "exile"
            && s.stackObjectIds().length === 0) {
        driver.require(evidence.instantCastStep === "end"
            && (s.step === "end" || (s.step === "cleanup" && s.promptKind === "chooseCards")),
            "Darkness did not resolve after its explicit end-step cast and before discarding");
        evidence.instantId = instantId; evidence.instantCastDuringEnd = true;
        evidence.instantResolvedBeforeDiscard = true;
        evidence.resolutionObservedStep = s.step;
        evidence.handBeforeCleanup = counts(driver, 0).hand;
        save(driver, "necro-instant-resolved"); phase = "wait-cleanup";
    }
    if (phase === "wait-cleanup-done" && discardedIds.every(id => s.cardForInspection(id).zone === "exile")) {
        var cleaned = counts(driver, 0);
        driver.require(cleaned.hand === 5 && cleaned.graveyard === 0,
            "Necrodominance cleanup did not discard to exactly five through its exile replacement");
        evidence.discardedIds = discardedIds; evidence.handAfterCleanup = cleaned.hand;
        evidence.exileCount = cleaned.exile; evidence.necroId = necroId;
        phase = "done";
    }
    if (phase === "done") {
        auditProbe.share("necro-complete", Object.assign({done:true}, evidence));
        if ((auditProbe.readShared("necro-observer") || {}).done) finish(driver);
        return true;
    }
    return false;
}
function selectCards(driver, keepNecro) {
    var s = driver.session, list = driver.item("rulesCardCandidates");
    if (!list) return;
    var rows = Common.scalarChoices(list).filter(row => row.selectable);
    var chosen = rows.filter(row => row.selected);
    if (chosen.length === s.promptMinCardSelections) {
        if (phase === "wait-cleanup") {
            discardedIds = chosen.map(row => row.cardId);
            driver.require(discardedIds.length === evidence.handBeforeCleanup - 5,
                "Cleanup requested the wrong maximum-hand-size discard count");
            save(driver, "necro-cleanup");
        }
        if (driver.click("rulesConfirmCards")) {
            if (phase === "bottom") phase = "play-necro";
            else if (phase === "wait-cleanup") phase = "wait-cleanup-done";
        }
        return;
    }
    var next = rows.find(row => !row.selected && row.name === "Necrodominance" && row.cardId !== necroId)
        || rows.find(row => !row.selected && row.name === "Swamp")
        || rows.find(row => !row.selected && (!keepNecro || row.cardId !== necroId));
    driver.require(!!next, "No reachable native discard/bottom candidate");
    if (!driver.click(next.objectName))
        driver.require(auditProbe.wheel(list, -160), "Cannot reach native discard/bottom candidate");
}
function act(driver) {
    var s = driver.session, options = s.promptOptionItems();
    // The target window already has its separate two-second tick observation.
    // Setup inputs wait for a settled prompt and rendered control geometry.
    if (phase !== "cast-instant" && !inputLayoutReady(driver, Date.now(), ws.rulesResponsePending)) return true;
    if (driver.seat !== 1) {
        if (s.promptKind === "mulligan") { driver.click("rulesPromptOption-$keep"); return true; }
        if (s.promptKind === "chooseAction") { driver.click("rulesPromptOption-$pass"); return true; }
        if (s.promptKind === "chooseAttackers") { driver.click("rulesConfirmCombat-attackers"); return true; }
        return false;
    }
    // Cost confirmation precedes the actual life loss/draw snapshot. Do not
    // manually advance priority or cleanup while waiting to observe that draw.
    if (phase === "wait-draw" && !["chooseNumber", "chooseBoolean"].includes(s.promptKind)) return true;
    if (s.promptKind === "mulligan") {
        var necro = hand(driver).find(card => card.name === "Necrodominance");
        if (!necro) {
            driver.require(mulligans < 5, "No Necrodominance after five actual ordinary mulligans");
            if (driver.click("rulesPromptOption-$mulligan")) mulligans++;
        } else {
            necroId = necro.cardId;
            if (driver.click("rulesPromptOption-$keep")) phase = mulligans ? "bottom" : "play-necro";
        }
        return true;
    }
    if (s.promptKind === "mulliganPutBack") { selectCards(driver, true); return true; }
    if (s.promptKind === "chooseAction") {
        if (phase === "cast-instant") {
            var instant = options.find(option => option.kind === "cast" && option.cardId === instantId);
            driver.require(!!instant && s.step === "end" && s.stackObjectIds().length === 0,
                "The retained instant is no longer offered at an empty end-step stack");
            if (driver.cardAction(instant)) {
                evidence.instantCastStep = s.step; phase = "wait-instant"; driver.casts++;
            }
            return true;
        }
        if (phase === "play-necro") {
            var land = options.find(option => option.kind === "playLand");
            if (land) { if (driver.cardAction(land)) driver.lands++; return true; }
            var spell = Common.basicMana(driver, 0) >= 4
                && options.find(option => option.kind === "cast" && option.cardId === necroId);
            if (spell) { if (driver.cardAction(spell)) { phase = "wait-necro"; driver.casts++; } return true; }
        }
        driver.click("rulesPromptOption-$pass"); return true;
    }
    if (s.promptKind === "payManaCost") { Common.pay(driver, options); return true; }
    if (s.promptKind === "chooseBoolean" && phase === "wait-draw") {
        confirmLifePayment(driver, phase, necroId, drawAmount);
        return true;
    }
    if (s.promptKind === "chooseNumber") {
        // NativeGuiGame.number deliberately has no sourceCard/contextCards.
        // Match its observed title and the real battlefield/phase instead.
        driver.require(lifePaymentPromptMatches(s, phase, necroId),
            "Unexpected life-payment numeric prompt");
        var input = driver.item("rulesNumberInput");
        if (!input) return true;
        if (!before || phase !== "number-input") {
            before = counts(driver, 0);
            drawAmount = Math.min([10, 5, 3][drawRounds] || 0, s.promptMaxNumber, before.life - 1);
            driver.require(drawAmount > 0 && drawAmount >= s.promptMinNumber, "No safe positive Necrodominance life payment");
            phase = "number-input";
        }
        if (input.value !== drawAmount) {
            driver.click("rulesNumberInput");
            driver.require(auditProbe.key(Qt.Key_A, Qt.ControlModifier) && auditProbe.type(String(drawAmount))
                && auditProbe.key(Qt.Key_Tab), "Cannot enter the native life-payment number");
            return true;
        }
        save(driver, "necro-life-payment");
        if (driver.click("rulesConfirmNumber")) { drawRounds++; phase = "wait-draw"; }
        return true;
    }
    if (s.promptKind === "chooseCards") { selectCards(driver, false); return true; }
    if (s.promptKind === "chooseAttackers") { driver.click("rulesConfirmCombat-attackers"); return true; }
    return false;
}
