// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Published tournament lists, unchanged; deliberately simple visible-input play.
.import "ForgeBorosStudy.js" as Common

var fixture = null;
var attempted = {};
var lastName = "";
var tokenReview = null;
var tokens = 0;
var decision = {};

function deck(driver) {
    if (!fixture) {
        fixture = JSON.parse(auditProbe.readText(auditProbe.environment("HEXPROOF_AUDIT_DECK_MANIFEST")));
        var total = fixture.mainboard.reduce((sum, c) => sum + c.count, 0);
        driver.require(fixture.source && (fixture.deckFormat === "duel" ? total === 100 : total === 60),
            "A complete published tournament list is required");
    }
    return fixture;
}
function state() { return {source: fixture ? fixture.source : "", tokens: tokens, tokenReview: tokenReview, decision: decision}; }
function act(driver) {
    var s = driver.session, options = s.promptOptionItems(), own = ws.roomSession.seatIndex;
    decision = Common.snapshot(driver);
    var board = Common.lanes(driver).map(c => s.cardForInspection(c.cardId));
    var ours = board.filter(c => c.controllerSeat === own);
    var drone = board.find(c => c.name === "Drone" || c.name === "Drone Token");
    if (drone && (!tokenReview || !tokenReview.done)) {
        if (!tokenReview) {
            driver.require(drone.setCode === "TEOE" && drone.collectorNumber === "3", "Drone has an ordinary-card printing");
            var tile = driver.item("forgeCard-" + drone.cardId);
            if (!tile) return false;
            driver.require(auditProbe.hover(tile), "Cannot hover the real Drone token");
            tokenReview = {due:Date.now() + 10000, name:drone.name, setCode:drone.setCode, number:drone.collectorNumber};
            return true;
        }
        // The preview intentionally ignores input. Read the visible typed
        // child for inspection; input selectors correctly reject disabled art.
        var preview = driver.table.presentation.children.find(c => c.objectName === "rulesCardHoverPreview");
        var art = preview && preview.visible ? preview.children.find(c => c.objectName === "rulesCardHoverPreviewArt") : null;
        if (!art || art.status !== 1) {
            driver.require(Date.now() < tokenReview.due, "Drone preview image did not load");
            return true;
        }
        tokenReview.image = art.source.toString(); tokenReview.done = true; tokens++;
        driver.capture("tournament-drone-hover"); auditProbe.record("tournament-drone-hover", tokenReview);
    }
    if (driver.table.cardActionPicker.opened) {
        var actions = driver.table.cardActionPicker.actions;
        driver.click("rulesCardAction-" + actions[0].responseId); return true;
    }
    switch (s.promptKind) {
    case "chooseAction": {
        var land = options.find(o => o.kind === "playLand");
        if (land) { if (driver.cardAction(land)) driver.lands++; return true; }
        var fetch = options.find(o => o.kind === "activateAbility" && /^(Scalding Tarn|Flooded Strand|Polluted Delta|Misty Rainforest)/.test(o.label));
        if (fetch) { driver.cardAction(fetch); return true; }
        var specs = deck(driver).mainboard;
        var type = c => (specs.find(v => v.name === c.name) || {}).typeLine || "";
        var artifacts = ours.filter(c => type(c).includes("Artifact")).length;
        var mana = ours.filter(c => !c.tapped && (type(c).includes("Land") || c.name === "Mox Opal" && artifacts >= 3)).length;
        var priority = ["Pinnacle Emissary", "Phelia, Exuberant Shepherd", "Mox Opal", "Springleaf Drum", "Memnite", "Thoughtcast", "Weapons Manufacturing"];
        var spells = options.filter(o => o.kind === "cast").sort((a,b) => {
            var ai = priority.indexOf(s.cardForInspection(a.cardId).name), bi = priority.indexOf(s.cardForInspection(b.cardId).name);
            return (ai < 0 ? 99 : ai) - (bi < 0 ? 99 : bi);
        });
        for (var spell of spells) {
            var card = s.cardForInspection(spell.cardId), spec = specs.find(v => v.name === card.name || v.catalogName === card.name);
            if (!spec || ["Pithing Needle", "Disruptor Flute"].includes(card.name)) continue;
            if (spec.typeLine.includes("Legendary") && ours.some(c => c.name === card.name)) continue;
            var cost = spec.manaValue;
            if (["Thoughtcast", "Thought Monitor", "Kappa Cannoneer"].includes(card.name)) cost = Math.max(1, cost - artifacts);
            var commander = driver.commander();
            if (commander && commander.cardId === card.cardId) cost += commander.tax;
            if (cost > mana) continue;
            if (spec.typeLine.includes("Instant") && !board.some(c => c.controllerSeat !== own && c.power)) continue;
            var key = s.turn + ":" + card.cardId + ":" + mana + ":" + artifacts;
            if (attempted[key]) continue;
            attempted[key] = true; lastName = card.name;
            if (driver.cardAction(spell)) driver.casts++;
            return true;
        }
        driver.click("rulesPromptOption-$pass"); return true;
    }
    case "payManaCost": Common.pay(driver, options); return true;
    case "chooseCards": Common.chooseCards(driver); return true;
    case "chooseFromSelection": {
        var choices = Common.scalarChoices(driver.item("rulesScalarCandidates"));
        var land = choices.find(c => /^Play .*land|^Play land/i.test(c.label));
        if (land && !choices.some(c => c.count > 0)) driver.click("rulesScalarChoice-" + land.responseId);
        else Common.chooseScalar(driver);
        return true;
    }
    case "chooseBoolean": case "chooseColor": Common.chooseScalar(driver); return true;
    case "chooseBoardTargets": Common.chooseTarget(driver); return true;
    case "chooseNumber": {
        var input = driver.item("rulesNumberInput");
        if (!input) return true;
        if (input.value !== s.promptMinNumber)
            driver.require(auditProbe.click(input.down.indicator), "Cannot select the minimum X cost");
        else driver.click("rulesConfirmNumber");
        return true;
    }
    case "scry": driver.click("confirmScryButton"); return true;
    case "chooseCardName": {
        var input = driver.item("rulesCardNameInput");
        if (!input) return true;
        if (!input.text.length) {
            driver.click("rulesCardNameInput");
            driver.require(auditProbe.type("Karn, the Great Creator"), "Cannot enter a card name in the native input");
        } else driver.click("confirmCardNameButton");
        return true;
    }
    default: return false;
    }
}
