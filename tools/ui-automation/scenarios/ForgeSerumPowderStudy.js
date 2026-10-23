// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Legal four-copy fixture; opening hands, London choices, casts and payments
// all come from the real engine and production desktop controls.
.import "ForgeBorosStudy.js" as Common

var fixture = null;
var phase = "opening";
var mulligans = 0;
var before = null;
var powderId = "";
var bottomed = [];
var spentSpell = "";
var finished = false;
var evidence = {};

function deck(driver) {
    if (!fixture) {
        fixture = JSON.parse(auditProbe.readText(auditProbe.environment("HEXPROOF_AUDIT_DECK_MANIFEST")));
        driver.require(fixture.mainboard.reduce((sum, card) => sum + card.count, 0) === 60
            && fixture.mainboard.find(card => card.name === "Serum Powder").count === 4
            && fixture.mainboard.every(card => card.typeLine.startsWith("Basic Land") || card.count <= 4),
            "Serum Powder regression requires a legal 60-card four-copy fixture");
    }
    return fixture;
}
function state() {
    return {phase:phase, mulligans:mulligans, powderId:powderId, bottomed:bottomed,
        before:before, spentSpell:spentSpell, evidence:evidence};
}
function hand(driver) {
    var lane = Common.laneItems(driver, true).find(item => item.objectName === "forgeHand");
    return lane ? lane.visibleCards : [];
}
function handIds(driver) { return hand(driver).map(card => card.cardId).sort(); }
function registeredCost(card, registeredDeck) {
    // The viewer's RulesCardModel intentionally carries identity/state rather
    // than catalog mana values. Use only this disclosed fixture's exact names.
    var entry = registeredDeck.mainboard.find(candidate => candidate.name === card.name);
    return entry && Number.isFinite(Number(entry.manaValue)) ? Number(entry.manaValue) : Infinity;
}
function cost(driver, id) { return registeredCost(driver.session.cardForInspection(id), fixture); }
function counts(driver) {
    var own = ws.roomSession.seatIndex;
    return {hand:driver.session.zoneCount(own, "hand"), library:driver.session.zoneCount(own, "library"),
        exile:driver.session.zoneCount(own, "exile")};
}
function findItem(item, name) {
    if (!item) return null;
    if (item.objectName === name) return item;
    for (var child of item.children || []) {
        var result = findItem(child, name);
        if (result) return result;
    }
    return null;
}
function colorless(driver) {
    var plate = findItem(driver.table.presentation, "rulesPlayerTarget" + ws.roomSession.seatIndex);
    return plate ? (plate.manaPool || []).filter(mana => mana.color === "C")
        .reduce((sum, mana) => sum + mana.amount, 0) : 0;
}
function save(driver, name) {
    driver.capture(name);
    auditProbe.record(name, state());
}
function complete(driver) {
    finished = true;
    save(driver, "serum-powder-finished");
    auditProbe.record("result", {status:"passed", scenario:driver.variant, seat:driver.seat,
        evidence:auditProbe.environment("AUDIT_OS_INPUT_HELPER") ? "system-input" : "native-qt-input",
        scope:"bounded real Serum Powder regression; not a completed match", roomAndDeckSetup:"fixture",
        gameActions:"production-controls", review:evidence,
        requiredScreenshots:["opening.png", "serum-powder-finished.png"].concat(driver.seat === 1
            ? driver.variant === "serum-powder-mulligan"
                ? ["powder-offered.png", "powder-confirmation.png", "powder-declined.png", "powder-bottom.png", "powder-redrawn.png"]
                : ["powder-on-battlefield.png", "powder-colorless-mana.png", "powder-mana-payment.png"] : [])});
    auditProbe.finish(0);
}
function tick(driver) {
    if (finished) return true;
    var s = driver.session;
    if (driver.seat !== 1) {
        var shared = auditProbe.readShared("serum-powder-complete") || {};
        if (!shared.done) return false;
        if (driver.variant === "serum-powder-mulligan") {
            if (s.zoneCount(0, "exile") !== shared.exileCount) return true;
            driver.require(shared.exiledIds.every(id => {
                var card = s.cardForInspection(id);
                return card.zone === "exile" && card.visibleIdentity;
            }), "Opponent projection lost public Powder exiles");
            driver.require(s.zoneCount(0, "hand") === shared.handCount,
                "Opponent received the wrong post-Powder hand count");
        } else {
            if (s.cardForInspection(shared.spellId).zone !== "battlefield") return true;
            driver.require(s.cardForInspection(shared.powderId).tapped,
                "Opponent did not observe Serum Powder's tap cost");
        }
        evidence = shared;
        auditProbe.share("serum-powder-observer", {done:true});
        complete(driver); return true;
    }
    if (phase === "wait-decline" && s.promptPending && s.promptKind === "mulligan") {
        driver.require(JSON.stringify(handIds(driver)) === JSON.stringify(before.ids)
            && JSON.stringify(counts(driver)) === JSON.stringify(before.counts),
            "Declining Serum Powder changed the hand or zones");
        driver.require(s.promptDetail === before.detail, "Declining Powder changed ordinary mulligan count");
        evidence.declineUnchanged = true;
        save(driver, "powder-declined"); phase = "retry";
    }
    if (phase === "wait-redraw" && s.promptPending && s.promptKind === "mulligan") {
        var exiled = before.ids.filter(id => !bottomed.includes(id)), now = counts(driver);
        driver.require(bottomed.length === mulligans && exiled.includes(powderId),
            "London bottom selection did not retain the requested Powder");
        driver.require(now.hand === exiled.length && now.exile === before.counts.exile + exiled.length
            && now.library === before.counts.library + bottomed.length - exiled.length,
            "Powder did not exile and replace the exact post-London hand");
        driver.require(exiled.every(id => s.cardForInspection(id).zone === "exile"),
            "An original post-bottom card was not exiled");
        driver.require(s.promptDetail === before.detail, "Powder increased the ordinary mulligan count");
        evidence.exiledIds = exiled; evidence.exileCount = now.exile; evidence.handCount = now.hand;
        evidence.bottomCount = bottomed.length; evidence.mulliganCountUnchanged = true;
        save(driver, "powder-redrawn"); phase = "keep-redrawn";
    }
    if (phase === "wait-kept" && s.promptKind === "mulliganPutBack")
        driver.require(false, "Keeping a Powder-redrawn hand asked for London bottom twice");
    if (phase === "wait-kept" && s.promptPending && s.promptKind === "chooseAction") {
        driver.require(counts(driver).hand === evidence.handCount, "Keeping Powder hand removed more cards");
        evidence.keepWithoutSecondBottom = true; phase = "done";
    }
    if (phase === "wait-powder" && s.cardForInspection(powderId).zone === "battlefield") {
        driver.require(!s.cardForInspection(powderId).tapped, "Resolved Powder entered tapped");
        save(driver, "powder-on-battlefield"); phase = "produce";
    }
    if (phase === "wait-mana" && s.promptPending && s.promptKind === "chooseAction") {
        driver.require(s.cardForInspection(powderId).tapped && colorless(driver) === 1,
            "Powder mana ability did not tap and add exactly one colorless mana");
        evidence.producedColorless = 1; save(driver, "powder-colorless-mana"); phase = "spend";
    }
    if (phase === "wait-spell" && s.cardForInspection(spentSpell).zone === "battlefield") {
        driver.require(colorless(driver) === 0 && s.cardForInspection(powderId).tapped,
            "Powder's colorless mana was not spent on the generic spell");
        evidence.spellId = spentSpell; evidence.powderId = powderId;
        evidence.colorlessSpent = true; save(driver, "powder-mana-payment"); phase = "done";
    }
    if (phase === "done") {
        auditProbe.share("serum-powder-complete", Object.assign({done:true}, evidence));
        if ((auditProbe.readShared("serum-powder-observer") || {}).done) complete(driver);
        return true;
    }
    return false;
}
function bottomCards(driver, owed, retainedId) {
    var s = driver.session, list = driver.item("rulesCardCandidates");
    if (!list) return;
    driver.require(s.promptMinCardSelections === owed && s.promptMaxCardSelections === owed,
        "London asked for a different number of owed cards");
    var rows = Common.scalarChoices(list).filter(row => row.selectable);
    var selected = rows.filter(row => row.selected);
    if (selected.length === owed) {
        bottomed = selected.map(row => row.cardId);
        driver.require(!bottomed.includes(retainedId), "Cannot bottom the Powder being used");
        save(driver, "powder-bottom");
        if (driver.click("rulesConfirmCards")) phase = driver.variant === "serum-powder-mulligan" ? "wait-redraw" : "play";
        return;
    }
    var next = rows.find(row => !row.selected && row.cardId !== retainedId && row.name !== "Plains")
        || rows.find(row => !row.selected && row.cardId !== retainedId);
    driver.require(!!next, "London has no selectable card besides the retained Powder");
    driver.click(next.objectName);
}
function act(driver) {
    var s = driver.session, options = s.promptOptionItems();
    if (driver.seat !== 1) {
        if (s.promptKind === "mulligan") { driver.click("rulesPromptOption-$keep"); return true; }
        if (s.promptKind === "chooseAction") { driver.click("rulesPromptOption-$pass"); return true; }
        if (s.promptKind === "chooseAttackers") { driver.click("rulesConfirmCombat-attackers"); return true; }
        return false;
    }
    if (s.promptKind === "mulligan") {
        if (phase === "keep-redrawn") {
            if (driver.click("rulesPromptOption-$keep")) phase = "wait-kept";
            return true;
        }
        if (["wait-decline", "wait-redraw", "wait-kept"].includes(phase)) return true;
        var powder = options.find(option => option.kind === "activateAbility"
            && s.cardForInspection(option.cardId).name === "Serum Powder");
        if ((phase === "opening" && mulligans === 0) || !powder) {
            driver.require(mulligans < 5, "No Powder offered after five actual ordinary mulligans");
            if (driver.click("rulesPromptOption-$mulligan")) mulligans++;
            return true;
        }
        powderId = powder.cardId;
        if (driver.variant === "serum-powder-mana") {
            if (driver.click("rulesPromptOption-$keep")) phase = "bottom-mana";
            return true;
        }
        if (phase === "opening") {
            before = {ids:handIds(driver), counts:counts(driver), detail:s.promptDetail};
            save(driver, "powder-offered");
        }
        var tile = driver.item("forgeHandCard-" + powderId);
        var face = findItem(tile, "forgeHandSurface-" + powderId);
        driver.require(!!face && face.actionable, "Offered mulligan Powder is not actionable on the hand");
        if (driver.cardAction(powder)) phase = phase === "retry" ? "confirm-yes" : "confirm-no";
        return true;
    }
    if (s.promptKind === "chooseBoolean" && ["confirm-no", "confirm-yes"].includes(phase)) {
        driver.require(s.promptContextCards.items().some(card => card.name === "Serum Powder"),
            "Powder confirmation lost its card context");
        save(driver, "powder-confirmation");
        var choice = Common.scalarChoices(driver.item("rulesScalarCandidates"))
            .find(row => row.label === (phase === "confirm-no" ? "No" : "Yes"));
        if (choice && driver.click("rulesScalarChoice-" + choice.responseId))
            phase = phase === "confirm-no" ? "wait-decline" : "bottom-powder";
        return true;
    }
    if (s.promptKind === "mulliganPutBack") {
        driver.require(["bottom-powder", "bottom-mana"].includes(phase), "Unexpected London bottom prompt");
        bottomCards(driver, mulligans, powderId); return true;
    }
    if (s.promptKind === "chooseAction") {
        if (s.stackObjectIds().length) { driver.click("rulesPromptOption-$pass"); return true; }
        if (phase === "produce") {
            var ability = options.find(option => option.kind === "activateAbility" && option.cardId === powderId);
            driver.require(!!ability && colorless(driver) === 0, "Resolved Powder has no offered mana ability");
            if (driver.cardAction(ability)) phase = "wait-mana";
            return true;
        }
        var spell;
        if (phase === "spend") {
            spell = options.find(option => option.kind === "cast" && option.cardId !== powderId
                && cost(driver, option.cardId) <= Common.basicMana(driver, 0) + colorless(driver));
            driver.require(!!spell, "No affordable generic spell to spend Powder mana");
            if (driver.cardAction(spell)) { spentSpell = spell.cardId; phase = "wait-spell"; driver.casts++; }
            return true;
        }
        var land = options.find(option => option.kind === "playLand");
        if (land) { if (driver.cardAction(land)) driver.lands++; return true; }
        if (phase === "play" && Common.basicMana(driver, 0) >= 3) {
            spell = options.find(option => option.kind === "cast" && option.cardId === powderId);
            if (spell) {
                // Reserve a second generic spell so the subsequent mana can be
                // spent before priority/phase changes empty the pool.
                if (options.some(option => option.kind === "cast" && option.cardId !== powderId
                    && cost(driver, option.cardId) <= Common.basicMana(driver, 0) - 2)
                    && driver.cardAction(spell)) { phase = "wait-powder"; driver.casts++; }
            }
        }
        if (phase !== "wait-powder") driver.click("rulesPromptOption-$pass");
        return true;
    }
    if (s.promptKind === "payManaCost") { Common.pay(driver, options); return true; }
    if (s.promptKind === "chooseAttackers") { driver.click("rulesConfirmCombat-attackers"); return true; }
    return false;
}
