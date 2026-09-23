// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Bounded interaction regression using actual human Forge prompts and native
// production controls. It deliberately stops before completing a match.
.import "ForgeBorosStudy.js" as Common

var fixture = null;
var phase = "prepare";
var sourceId = "";
var baseline = [];
var selectedIds = [];
var pileName = "";
var toggleStep = 0;
var paid = false;
var cancellations = 0;
var finished = false;

function deck(driver) {
    if (!fixture) {
        fixture = JSON.parse(auditProbe.readText(auditProbe.environment("HEXPROOF_AUDIT_DECK_MANIFEST")));
        driver.require(fixture.mainboard.reduce((sum, c) => sum + c.count, 0) === 60,
            "Improvise fixture requires 60 registered cards");
    }
    return fixture;
}
function ours(driver) {
    return Common.lanes(driver).filter(c => c.controllerSeat === ws.roomSession.seatIndex);
}
function observe(driver, name) {
    var neutral = driver.item("forgeGameMenu");
    if (neutral) driver.require(auditProbe.hover(neutral), "Cannot move hover away from the selected cards");
    driver.capture(name);
    auditProbe.record(name, {phase:phase, cancellations:cancellations, sourceId:sourceId,
        targets:driver.session.boardTargetCandidates(), selectedIds:selectedIds, pileName:pileName,
        board:Common.lanes(driver), prompt:driver.session.promptDetail});
}
function finish(driver, screenshots, extra) {
    finished = true;
    auditProbe.record("result", Object.assign({status:"passed", scenario:"forge-improvise",
        evidence:auditProbe.environment("AUDIT_OS_INPUT_HELPER") ? "system-input" : "native-qt-input",
        scope:"bounded Kappa casting regression, not a completed match",
        seat:driver.seat, requiredScreenshots:["opening.png"].concat(screenshots)}, extra));
    auditProbe.finish(0);
}
function tick(driver) {
    if (finished) return true;
    var shared = auditProbe.readShared("improvise-review") || {};
    if (driver.seat === 2) {
        if (shared.done) {
            // Wait until the observer has received the resulting battlefield.
            var board = Common.lanes(driver);
            if (!shared.selectedIds.every(id => board.some(c => c.cardId === id && c.tapped))) return true;
            driver.require(driver.session.boardTargetCandidates().length === 0,
                "Opponent received the owner's private improvise candidates");
            observe(driver, "opponent-confirmed");
            finish(driver, ["opponent-confirmed.png"], {privateSelections:false, confirmedTaps:true});
            auditProbe.share("improvise-observed", {done:true});
            return true;
        }
        return false;
    }
    var s = driver.session;
    if (phase === "rollback" && s.promptPending && s.promptKind === "chooseAction") {
        var board = ours(driver);
        driver.require(baseline.every(before => board.some(c => c.cardId === before.cardId && c.tapped === before.tapped)),
            "Cancellation did not restore the exact pre-cast tap states");
        driver.require(s.cardForInspection(sourceId).zone === "hand", "Cancelled Kappa did not return to hand");
        cancellations++;
        observe(driver, "cancel-restored-" + cancellations);
        phase = "prepare";
    }
    if (phase === "success") {
        var source = s.cardForInspection(sourceId);
        if (source.zone !== "stack" && source.zone !== "battlefield") return false;
        var current = ours(driver);
        driver.require(selectedIds.every(id => current.some(c => c.cardId === id && c.tapped)),
            "Successful casting refunded its improvise taps");
        driver.require(current.some(c => c.name === "Island" && c.tapped), "Successful casting omitted blue mana");
        observe(driver, "successful-cast");
        auditProbe.share("improvise-review", {done:true, selectedIds:selectedIds});
        phase = "observer";
    }
    if (phase === "observer") {
        if ((auditProbe.readShared("improvise-observed") || {}).done)
            finish(driver, ["selected-artifacts.png", "deselected-artifact.png", "confirmed-taps.png",
                "cancel-restored-1.png", "cancel-restored-2.png", "successful-cast.png"],
                {cancellations:cancellations, selectedIds:selectedIds, pileName:pileName,
                    selectionToggle:true, successfulRetry:true});
        return true;
    }
    return false;
}
function act(driver) {
    var s = driver.session, options = s.promptOptionItems();
    if (driver.seat === 2) {
        if (s.promptKind === "chooseAction") { driver.click("rulesPromptOption-$pass"); return true; }
        if (s.promptKind === "chooseAttackers") { driver.click("rulesConfirmCombat-attackers"); return true; }
        return false;
    }
    if (s.promptKind === "chooseAction") {
        var board = ours(driver);
        var island = board.find(c => c.name === "Island");
        var land = !island && options.find(o => o.kind === "playLand");
        if (land) { driver.cardAction(land); return true; }
        var zero = options.find(o => o.kind === "cast" && s.cardForInspection(o.cardId).name !== "Kappa Cannoneer");
        if (zero) { driver.cardAction(zero); return true; }
        var kappa = options.find(o => o.kind === "cast" && s.cardForInspection(o.cardId).name === "Kappa Cannoneer");
        var duplicate = board.find(c => c.name !== "Island" && !c.tapped
            && board.filter(other => other.name === c.name && !other.tapped).length > 1);
        if (kappa && duplicate && island && !island.tapped && board.filter(c => c.name !== "Island" && !c.tapped).length >= 5) {
            if (driver.cardAction(kappa)) {
                sourceId = kappa.cardId; baseline = board; selectedIds = []; toggleStep = 0; paid = false;
                pileName = duplicate.name;
                phase = "select";
            }
            return true;
        }
        driver.click("rulesPromptOption-$pass"); return true;
    }
    if (s.promptKind === "chooseBoardTargets" && phase === "select") {
        var candidates = s.boardTargetCandidates();
        var reserved = candidates.filter(c => c.nativeSelected);
        driver.require(reserved.length === selectedIds.length
            && reserved.every(c => selectedIds.includes(c.objectId)), "Native selection marker disagrees with clicks");
        driver.require(ours(driver).filter(c => selectedIds.includes(c.cardId)).every(c => !c.tapped),
            "Unconfirmed selections tapped the battlefield");
        for (var candidate of reserved) {
            var tile = driver.item("forgeCard-" + candidate.objectId);
            // Buried members are represented by their selected pile's front.
            if (tile && tile.card.stackFront)
                driver.require(tile.nativeSelected && tile.selected, "Selected artifact lacks its visible marker");
        }
        if (cancellations === 0 && toggleStep === 0 && selectedIds.length === 2) {
            observe(driver, "selected-artifacts");
            var front = reserved.find(c => {
                var tile = driver.item("forgeCard-" + c.objectId);
                return tile && tile.card.stackFront;
            });
            driver.require(!!front, "Selected pile has no reachable front");
            if (driver.click("forgeCard-" + front.objectId)) {
                selectedIds = selectedIds.filter(id => id !== front.objectId); toggleStep = 1;
            }
            return true;
        }
        if (toggleStep === 1) { observe(driver, "deselected-artifact"); toggleStep = 2; }
        var count = cancellations < 2 ? 2 : 5;
        if (selectedIds.length < count) {
            var next = candidates.find(c => !c.nativeSelected
                && (cancellations === 2 || c.name === pileName) && driver.item("forgeCard-" + c.objectId));
            driver.require(!!next, "No reachable unselected artifact");
            if (driver.click("forgeCard-" + next.objectId)) selectedIds.push(next.objectId);
            return true;
        }
        if (driver.click("rulesConfirmTargets")) phase = "pay";
        return true;
    }
    if (s.promptKind === "payManaCost" && phase === "pay") {
        driver.require(selectedIds.every(id => ours(driver).some(c => c.cardId === id && c.tapped)),
            "Confirmed improvise did not tap its chosen artifacts");
        if (!paid) {
            if (cancellations === 0) observe(driver, "confirmed-taps");
            var mana = options.find(o => o.kind === "activateAbility" && s.cardForInspection(o.cardId).name === "Island");
            driver.require(!!mana, "Blue mana source unavailable");
            if (driver.cardAction(mana)) { paid = true; if (cancellations === 2) phase = "success"; }
        } else {
            driver.require(options.some(o => o.responseId === "$cancel"), "Insufficient payment lacks Cancel");
            if (driver.click("rulesPromptOption-$cancel")) phase = "rollback";
        }
        return true;
    }
    if (s.promptKind === "chooseAttackers") { driver.click("rulesConfirmCombat-attackers"); return true; }
    return false;
}
