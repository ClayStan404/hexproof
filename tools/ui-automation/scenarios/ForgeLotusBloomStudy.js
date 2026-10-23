// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Natural hands, draws, suspend counters and resolutions. Only the room and
// registered deck are fixtures; every game decision uses production controls
// with the default Smart priority and no phase stops, holds or yields.
.import "ForgeBorosStudy.js" as Common
.import "ForgeNecrodominanceStudy.js" as Input

var fixture = null;
var phase = "opening";
var mulligans = 0;
var bloomId = "";
var spellId = "";
var spellName = "";
var before = null;
var evidence = {};
var captures = [];
var finished = false;
var pendingAction = null;

function deck(driver) {
    if (!fixture) {
        fixture = JSON.parse(auditProbe.readText(auditProbe.environment("HEXPROOF_AUDIT_DECK_MANIFEST")));
        driver.require(fixture.mainboard.reduce((sum, card) => sum + card.count, 0) === 60
            && fixture.mainboard.find(card => card.name === "Lotus Bloom").count === 4
            && fixture.mainboard.every(card => card.typeLine.startsWith("Basic Land") || card.count <= 4)
            && fixture.mainboard.filter(card => card.typeLine.includes("Land"))
                .every(card => card.name === "Plains"),
            "Lotus Bloom study requires its legal 60-card four-copy fixture with Plains as the only lands");
    }
    return fixture;
}
function state() {
    return {phase:phase, mulligans:mulligans, bloomId:bloomId, spellId:spellId,
        spellName:spellName, before:before, evidence:evidence};
}
function startingPlayerChoice(session, currentPhase, sourceId) {
    return currentPhase === "opening" && !sourceId && session.promptKind === "chooseBoolean"
        && session.promptTitle === "Confirm decision"
        && /won the coin toss\.[\s\S]*Would you like to play or draw\?/.test(session.promptDetail);
}
function smartPriority(priority) {
    return !priority.fullControl && !priority.holdNextPriority && !priority.heldPrompt && !priority.yieldMode
        && Object.keys(priority.phaseStops || {}).every(key => priority.phaseStops[key] !== true);
}
function expectedBlueSurplus(registeredDeck, name) {
    var card = registeredDeck.mainboard.find(entry => entry.name === name);
    return card && card.manaCost.includes("U") ? 3 - card.manaValue : -1;
}
function setupLandAllowed(variant, currentPhase) {
    // Upstream AI conserves Lotus Bloom for three-mana spells once three or
    // more sources exist. The automatic study needs only Bloom's three mana.
    return variant !== "lotus-bloom-auto" && ["wait-bloom", "ready"].includes(currentPhase);
}
function floatedCastPaid(session, currentPhase, producedAmount, spellZone, poolAmount) {
    return currentPhase === "pay-spell" && producedAmount === 3 && poolAmount === 0
        && ["stack", "battlefield", "graveyard"].includes(spellZone)
        && (!session.promptPending || ["chooseAction", "scry"].includes(session.promptKind));
}
function standaloneColorSkipped(session, currentPhase, selectedColor, sourceZone) {
    return currentPhase === "activate" && !selectedColor && sourceZone === "graveyard"
        && session.promptPending && session.promptKind === "chooseAction";
}
function paymentTransition(session, currentPhase, selectedColor, sourceZone, spellZone, blueAmount, surplus, name) {
    var scalar = session.promptPending && ["chooseBoolean", "chooseFromSelection", "chooseColor"]
        .includes(session.promptKind);
    var completedInput = session.promptPending
        && ["chooseAction", "payManaCost", "scry"].includes(session.promptKind);
    var resolvedSpell = ["battlefield", "graveyard"].includes(spellZone);
    if (currentPhase === "activate" && !selectedColor && sourceZone === "graveyard" && !scalar
            && (completedInput || blueAmount > 0 || resolvedSpell))
        return "missing-color";
    if (currentPhase !== "after-color") return "waiting";
    if (session.promptPending && session.promptKind === "payManaCost") return "payment-open";
    // Forge has already popped a resolving Opt from the stack while its scry
    // callback waits. Its card may therefore be absent from all rendered zones.
    if (selectedColor && sourceZone === "graveyard" && name === "Opt"
            && session.promptPending && session.promptKind === "scry" && surplus === 2 && blueAmount === 2)
        return "paid";
    // InputPayManaCost may finish immediately after the mana source pays the
    // entire cost. A second payment prompt is not required for this path.
    if (sourceZone === "graveyard" && ["stack", "battlefield", "graveyard"].includes(spellZone) && !scalar
            && (completedInput || resolvedSpell || (surplus > 0 && blueAmount === surplus)))
        return "paid";
    return "waiting";
}
function hand(driver) {
    var lane = Common.laneItems(driver, true).find(item => item.objectName === "forgeHand");
    return lane ? lane.visibleCards : [];
}
function counts(driver, seat) {
    var s = driver.session;
    return {hand:s.zoneCount(seat, "hand"), library:s.zoneCount(seat, "library"),
        exile:s.zoneCount(seat, "exile"), graveyard:s.zoneCount(seat, "graveyard")};
}
function manaForPresentation(presentation, seat) {
    for (var name of ["forgeField-" + seat, "rulesPlayerTarget" + seat]) {
        var item = Input.find(presentation, name);
        if (item && item.manaPool && typeof item.manaPool.length === "number"
                && typeof item.manaPool.filter === "function") return item.manaPool;
    }
    return [];
}
function mana(driver, seat) {
    return manaForPresentation(driver.table.presentation, seat);
}
function blue(driver, seat) {
    return mana(driver, seat).filter(entry => entry.color === "U")
        .reduce((sum, entry) => sum + entry.amount, 0);
}
function save(driver, name) {
    if (captures.includes(name)) return;
    driver.capture(name); captures.push(name);
    auditProbe.record(name, Object.assign(state(), {promptKind:driver.session.promptKind,
        title:driver.session.promptTitle, detail:driver.session.promptDetail,
        counts:counts(driver, 0), mana:mana(driver, 0)}));
}
function finish(driver) {
    finished = true;
    save(driver, "lotus-finished");
    auditProbe.record("result", {status:"passed", scenario:driver.variant, seat:driver.seat,
        evidence:auditProbe.environment("AUDIT_OS_INPUT_HELPER") ? "system-input" : "native-qt-input",
        scope:"bounded naturally suspended Lotus Bloom mana regression; not a completed match",
        roomAndDeckSetup:"fixture", gameActions:"production-controls", review:evidence,
        requiredScreenshots:["opening.png"].concat(captures.map(name => name + ".png"))});
    auditProbe.finish(0);
}
function requirePrivateProjection(driver, shared) {
    var s = driver.session;
    driver.require(!s.promptPending && s.promptOptionItems().length === 0
        && s.promptCards.items().length === 0 && s.promptContextCards.items().length === 0
        && s.boardTargetCandidates().length === 0,
        "Opponent received the owner's private Lotus Bloom decision");
    driver.require(shared.handIds.every(id => {
        var card = s.cardForInspection(id);
        return !card.visibleIdentity && !card.name;
    }), "Opponent received a private owner hand identity");
}
function tick(driver) {
    if (finished) return true;
    var s = driver.session;
    driver.require(smartPriority(driver.table.priority),
        "Lotus Bloom study requires default Smart priority without phase stops, holds or yields");
    driver.require(s.turn <= 80, "Natural Lotus Bloom study exceeded its bounded draw/turn budget");
    if (Input.recoverPassMenu(driver, () => auditProbe.key(Qt.Key_Escape))) return true;
    if (driver.seat !== 1) {
        var color = auditProbe.readShared("lotus-color") || {};
        if (color.bloomId && !(auditProbe.readShared("lotus-color-observer") || {}).done) {
            if (s.cardForInspection(color.bloomId).zone !== "graveyard") return true;
            requirePrivateProjection(driver, color);
            save(driver, "lotus-private-color-observer");
            auditProbe.share("lotus-color-observer", {done:true});
        }
        var shared = auditProbe.readShared("lotus-complete") || {};
        if (!shared.done) return false;
        if (s.cardForInspection(shared.spellId).zone !== shared.spellZone
                || s.cardForInspection(shared.bloomId).zone !== "graveyard") return true;
        requirePrivateProjection(driver, shared);
        driver.require(s.cardForInspection(shared.bloomId).visibleIdentity
            && s.cardForInspection(shared.spellId).visibleIdentity,
            "Opponent projection lost the public sacrificed Bloom or resolved spell");
        // Smart priority may already have advanced to a later natural draw.
        // The public spell/zone result and private identities remain the proof.
        evidence = Object.assign({}, shared, {opponentObservedCounts:counts(driver, 0)});
        save(driver, "lotus-public-result-observer");
        auditProbe.share("lotus-observer", {done:true}); finish(driver); return true;
    }
    if (ws.rulesResponsePending) return false;
    if (driver.variant === "lotus-bloom-manual"
            && standaloneColorSkipped(s, phase, !!evidence.explicitBlueChoice, s.cardForInspection(bloomId).zone)) {
        save(driver, "lotus-missing-standalone-color");
        driver.require(false, "Outside-payment Lotus Bloom returned to priority after sacrifice without offering its mana color choice");
    }
    if (driver.variant === "lotus-bloom-manual"
            && floatedCastPaid(s, phase, evidence.manualBlueMana,
                s.cardForInspection(spellId).zone, mana(driver, 0).reduce((sum, entry) => sum + entry.amount, 0))) {
        evidence.paymentCompletedFromFloatingMana = true;
        evidence.blueAfterPayment = blue(driver, 0);
        save(driver, "lotus-floated-mana-paid"); phase = "wait-spell";
    }
    if (driver.variant === "lotus-bloom-payment") {
        var surplus = expectedBlueSurplus(fixture, spellName);
        var transition = paymentTransition(s, phase, !!evidence.explicitBlueChoice,
            s.cardForInspection(bloomId).zone, s.cardForInspection(spellId).zone, blue(driver, 0), surplus, spellName);
        if (transition === "missing-color") {
            save(driver, "lotus-missing-payment-color");
            driver.require(false, "Manual Lotus Bloom payment completed or resumed without offering its mana color choice");
        }
        if (transition === "payment-open") phase = "pay-spell";
        if (transition === "paid") {
            driver.require(surplus >= 0 && blue(driver, 0) === surplus,
                "The chosen blue spell did not consume its registered mana cost from the three selected blue mana");
            evidence.expectedBlueSurplus = surplus;
            evidence.blueAfterPayment = blue(driver, 0);
            evidence.paymentCompletedAfterColor = true;
            save(driver, "lotus-paid-mana"); phase = "wait-spell";
        }
    }
    if (phase === "wait-bloom") {
        var bloom = s.cardForInspection(bloomId);
        if (bloom.zone === "exile") {
            evidence.naturalSuspend = true;
            save(driver, "lotus-suspended");
        }
        if (bloom.zone === "battlefield") {
            driver.require(evidence.naturalSuspend && !bloom.tapped,
                "Lotus Bloom did not reach the battlefield through its real suspend resolution");
            save(driver, "lotus-battlefield"); phase = "ready";
        }
    }
    if (phase === "wait-mana" && s.promptPending && s.promptKind === "chooseAction") {
        driver.require(s.cardForInspection(bloomId).zone === "graveyard"
            && blue(driver, 0) === 3 && mana(driver, 0).reduce((sum, entry) => sum + entry.amount, 0) === 3,
            "Manual Lotus Bloom did not sacrifice itself and add exactly three blue mana");
        evidence.manualBlueMana = 3;
        save(driver, "lotus-three-blue-mana"); phase = "cast-floated";
    }
    if (phase === "wait-spell" && s.stackObjectIds().length === 0) {
        var spell = s.cardForInspection(spellId), now = counts(driver, 0);
        var expectedZone = ["Divination", "Opt"].includes(spellName) ? "graveyard" : "battlefield";
        if (spell.zone !== expectedZone || s.cardForInspection(bloomId).zone !== "graveyard") return false;
        if (spellName === "Divination") {
            driver.require(now.hand === before.hand + 1 && now.library === before.library - 2,
                "The actual Divination did not resolve and draw exactly two cards after casting");
            evidence.drawnCards = 2;
        }
        if (spellName === "Opt") {
            driver.require(now.hand === before.hand && now.library === before.library - 1,
                "The actual Opt did not resolve its draw after the explicit blue payment");
            evidence.drawnCards = 1;
        }
        driver.require(driver.variant === "lotus-bloom-payment"
            || ["Divination", "Spiketail Drakeling"].includes(spellName),
            "The manual/auto-pay study did not resolve its blue spell");
        evidence.bloomId = bloomId; evidence.spellId = spellId; evidence.spellName = spellName;
        evidence.spellZone = expectedZone; evidence.handCount = now.hand;
        evidence.handIds = hand(driver).map(card => card.cardId);
        evidence.blueAtResolution = blue(driver, 0); evidence.realSpellResolved = true;
        evidence.smartMode = true;
        if (driver.variant === "lotus-bloom-auto")
            driver.require(evidence.autoPayManaSources.length === 1 && evidence.autoPayManaSources[0] === bloomId
                && evidence.autoPayStartingPoolEmpty && evidence.paymentControl === "$auto-pay"
                && !evidence.explicitBlueChoice,
                "The automatic study did not pay its actual blue spell using only Lotus Bloom");
        if (driver.variant === "lotus-bloom-payment")
            driver.require(evidence.blueAfterPayment === expectedBlueSurplus(fixture, spellName),
                "Manual payment did not preserve the expected surplus from its selected blue mana");
        save(driver, "lotus-spell-resolved"); phase = "done";
    }
    if (phase === "done") {
        auditProbe.share("lotus-complete", Object.assign({done:true}, evidence));
        if ((auditProbe.readShared("lotus-observer") || {}).done) finish(driver);
        return true;
    }
    return false;
}
function cards(driver) {
    var s = driver.session, list = driver.item("rulesCardCandidates");
    if (!list) return;
    var rows = Common.scalarChoices(list).filter(row => row.selectable);
    var selected = rows.filter(row => row.selected);
    if (selected.length === s.promptMinCardSelections) {
        driver.click("rulesConfirmCards"); return;
    }
    var next = rows.find(row => !row.selected && row.name === "Plains")
        || rows.find(row => !row.selected && row.cardId !== bloomId
            && !["Divination", "Spiketail Drakeling", "Opt"].includes(row.name))
        || rows.find(row => !row.selected && row.cardId !== bloomId);
    driver.require(!!next, "Cannot retain Lotus Bloom through natural London bottom/discard choices");
    if (!driver.click(next.objectName))
        driver.require(auditProbe.wheel(list, -160), "Cannot reach the native London bottom/discard candidate");
}
function startAction(driver, option, nextPhase) {
    if (!driver.cardAction(option)) return false;
    if (driver.table.cardActionPicker.opened) {
        pendingAction = {option:option, nextPhase:nextPhase}; return true;
    }
    if (nextPhase) phase = nextPhase;
    return true;
}
function chooseColor(driver) {
    var s = driver.session, list = driver.item("rulesScalarCandidates");
    if (!list) return;
    var rows = Common.scalarChoices(list);
    var colors = rows.map(row => row.label.toUpperCase()).sort();
    driver.require(JSON.stringify(colors) === JSON.stringify(["BLACK", "BLUE", "GREEN", "RED", "WHITE"]),
        "Lotus Bloom did not offer exactly the five mana colors in its rendered native chooser");
    driver.require(rows.every(row => driver.item("rulesScalarChoice-" + row.responseId)),
        "A Lotus Bloom color option is not visible and reachable");
    evidence.colorLabels = rows.map(row => row.label);
    evidence.colorPromptKind = s.promptKind;
    save(driver, "lotus-five-colors");
    auditProbe.share("lotus-color", {bloomId:bloomId, handIds:hand(driver).map(card => card.cardId)});
    if (!(auditProbe.readShared("lotus-color-observer") || {}).done) return;
    var chosen = rows.find(row => row.label.toUpperCase() === "BLUE");
    if (driver.click("rulesScalarChoice-" + chosen.responseId)) {
        evidence.explicitBlueChoice = true;
        phase = driver.variant === "lotus-bloom-manual" ? "wait-mana" : "after-color";
    }
}
function act(driver) {
    var s = driver.session, options = s.promptOptionItems();
    if (!Input.inputLayoutReady(driver, Date.now(), ws.rulesResponsePending)) return true;
    if (startingPlayerChoice(s, phase, bloomId)) { Common.chooseScalar(driver); return true; }
    if (pendingAction) {
        if (driver.click("rulesCardAction-" + pendingAction.option.responseId)) {
            if (pendingAction.nextPhase) phase = pendingAction.nextPhase;
            pendingAction = null;
        }
        return true;
    }
    if (s.promptKind === "mulligan") {
        if (driver.seat !== 1) { driver.click("rulesPromptOption-$keep"); return true; }
        var bloom = hand(driver).find(card => card.name === "Lotus Bloom");
        if (!bloom) {
            driver.require(mulligans < 5, "No Lotus Bloom after five actual ordinary mulligans");
            if (driver.click("rulesPromptOption-$mulligan")) mulligans++;
        } else {
            bloomId = bloom.cardId;
            if (driver.click("rulesPromptOption-$keep")) phase = "prepare";
        }
        return true;
    }
    if (["mulliganPutBack", "chooseCards"].includes(s.promptKind)) { cards(driver); return true; }
    if (s.promptKind === "chooseAction") {
        if (driver.seat !== 1 || s.stackObjectIds().length) {
            driver.click("rulesPromptOption-$pass"); return true;
        }
        if (phase === "prepare") {
            var suspend = options.find(option => option.kind === "activateAbility" && option.cardId === bloomId);
            driver.require(!!suspend, "The naturally retained Lotus Bloom has no suspend action");
            startAction(driver, suspend, "wait-bloom"); return true;
        }
        if (phase === "ready") {
            var wanted = driver.variant === "lotus-bloom-payment"
                ? ["Opt", "Spiketail Drakeling", "Divination"] : ["Spiketail Drakeling", "Divination"];
            var cast = null;
            for (var name of wanted) {
                cast = options.find(option => option.kind === "cast"
                    && s.cardForInspection(option.cardId).name === name);
                if (cast) break;
            }
            if (cast) {
                spellId = cast.cardId; spellName = s.cardForInspection(spellId).name;
                before = counts(driver, 0);
                if (driver.variant === "lotus-bloom-manual") {
                    var ability = options.find(option => option.kind === "activateAbility" && option.cardId === bloomId);
                    driver.require(!!ability && blue(driver, 0) === 0, "The resolved Bloom has no mana ability");
                    startAction(driver, ability, "activate");
                } else startAction(driver, cast, "pay-spell");
                return true;
            }
        }
        if (phase === "cast-floated") {
            var floated = options.find(option => option.kind === "cast" && option.cardId === spellId);
            driver.require(!!floated, "The blue spell is no longer castable after choosing three blue mana");
            startAction(driver, floated, "pay-spell"); return true;
        }
        var land = options.find(option => option.kind === "playLand");
        if (land && setupLandAllowed(driver.variant, phase)) { startAction(driver, land, ""); return true; }
        driver.click("rulesPromptOption-$pass"); return true;
    }
    if (s.promptKind === "payManaCost") {
        if (driver.seat !== 1 || phase === "wait-bloom") { Common.pay(driver, options); return true; }
        driver.require(phase === "pay-spell", "Unexpected Lotus Bloom payment state");
        save(driver, "lotus-payment");
        if (driver.variant === "lotus-bloom-payment" && !evidence.explicitBlueChoice) {
            var source = options.find(option => option.kind === "activateAbility" && option.cardId === bloomId);
            driver.require(!!source, "Lotus Bloom is absent from the actual spell payment's mana actions");
            startAction(driver, source, "activate"); return true;
        }
        var pay = options.find(option => option.responseId === "$pay")
            || options.find(option => option.responseId === "$auto-pay");
        driver.require(!!pay, "The Lotus Bloom spell payment has no confirmation or auto-pay control");
        if (driver.variant === "lotus-bloom-auto") {
            driver.require(options.some(option => option.responseId === "$auto-pay"), "Auto-pay is absent");
            var sources = options.filter(option => option.kind === "activateAbility" && option.cardId);
            driver.require(sources.length === 1 && sources[0].cardId === bloomId && mana(driver, 0).length === 0,
                "Automatic Lotus Bloom qualification must start with only Bloom and no floating mana");
            evidence.autoPayManaSources = sources.map(option => option.cardId);
            evidence.autoPayStartingPoolEmpty = true;
            pay = options.find(option => option.responseId === "$auto-pay");
        }
        if (driver.click("rulesPromptOption-" + pay.responseId)) {
            evidence.paymentControl = pay.responseId; driver.payments++;
            phase = driver.variant === "lotus-bloom-payment" ? "after-color" : "wait-spell";
        }
        return true;
    }
    if (s.promptKind === "chooseBoolean") {
        var rows = Common.scalarChoices(driver.item("rulesScalarCandidates"));
        var yes = rows.find(row => row.label === "Yes");
        driver.require(!!yes && ["wait-bloom", "activate", "pay-spell", "wait-spell"].includes(phase),
            "Unexpected Lotus Bloom native confirmation");
        if (phase === "activate") save(driver, "lotus-sacrifice-confirmation");
        driver.click("rulesScalarChoice-" + yes.responseId); return true;
    }
    if (["chooseFromSelection", "chooseColor"].includes(s.promptKind)) {
        driver.require(driver.seat === 1 && phase === "activate", "Unexpected Lotus Bloom scalar choice");
        chooseColor(driver); return true;
    }
    if (s.promptKind === "scry") {
        driver.require(driver.seat === 1 && spellName === "Opt" && phase === "wait-spell",
            "Unexpected native scry outside the actual paid Opt resolution");
        save(driver, "lotus-opt-scry");
        driver.click("confirmScryButton"); return true;
    }
    if (s.promptKind === "chooseAttackers") { driver.click("rulesConfirmCombat-attackers"); return true; }
    return false;
}
