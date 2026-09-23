// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// An explicit human-input policy for the owner's unchanged 60/15 Eldrazi list.
// It reads only this viewer's projection. It does not call rules response APIs.
.import "ForgeBorosStudy.js" as Common

var tried = {};
var activation = {};
var lastName = "";
var ordered = {};
var recorded = {};
var hoverUntil = 0;
var counters = {opening:0, digs:0, wishes:0, scries:0, reordered:0, linked:0};

function state() { return counters; }
function board(driver) { return Common.lanes(driver).map(c => driver.session.cardForInspection(c.cardId)); }
function ours(driver) { return board(driver).filter(c => c.controllerSeat === ws.roomSession.seatIndex); }
function save(driver, name) {
    if (recorded[name]) return;
    driver.capture("eldrazi-" + name); recorded[name] = true;
    auditProbe.record("eldrazi-" + name, Object.assign(Common.snapshot(driver), {coverage:state()}));
}
function available(driver, creature) {
    var cards = ours(driver), names = cards.map(c => c.name);
    var tron = ["Urza's Tower", "Urza's Mine", "Urza's Power Plant"].every(n => names.includes(n));
    return cards.reduce((sum, c) => {
        if (c.tapped) return sum;
        if (c.name === "Ugin's Labyrinth") return sum + (c.exiledCardCount > 0 ? 2 : 1);
        if (c.name === "Eldrazi Temple") return sum + (creature ? 2 : 1);
        if (c.name === "Urza's Tower") return sum + (tron ? 3 : 1);
        if (["Urza's Mine", "Urza's Power Plant"].includes(c.name)) return sum + (tron ? 2 : 1);
        return sum + (["Forest", "Abstergo Entertainment", "Talisman of Resilience"].includes(c.name) ? 1 : 0);
    }, 0);
}
function act(driver) {
    var session = driver.session, options = session.promptOptionItems();
    if (driver.table.cardActionPicker.opened) {
        var actions = driver.table.cardActionPicker.actions;
        var wish = lastName === "Karn, the Great Creator"
            && actions.find(a => /outside|exile|SubCounter|\[-2\]/i.test(a.label));
        var action = wish || actions.find(a => a.responseId === activation.current) || actions[0];
        return driver.click("rulesCardAction-" + action.responseId), true;
    }
    var linked = ours(driver).filter(c => c.name === "Ugin's Labyrinth" && c.exiledCardCount > 0);
    if (linked.length && !recorded.linked) {
        var tile = driver.item("forgeCard-" + linked[0].cardId);
        if (!hoverUntil && tile) {
            driver.require(auditProbe.hover(tile), "Cannot inspect the imprinted land");
            hoverUntil = Date.now() + 900;
        }
        if (hoverUntil && Date.now() < hoverUntil) return true;
        counters.linked++; save(driver, "linked");
    }
    switch (session.promptKind) {
    case "chooseAction": {
        var land = options.find(o => o.kind === "playLand");
        if (land) { if (driver.cardAction(land)) driver.lands++; return true; }
        var mana = available(driver, false), cards = ours(driver);
        var ability = options.find(o => o.kind === "activateAbility" && o.cardId
            && (session.cardForInspection(o.cardId).name === "Karn, the Great Creator"
                || session.cardForInspection(o.cardId).name === "Expedition Map" && mana >= 2)
            && !activation[session.turn + ":" + o.cardId]);
        if (ability) {
            activation[session.turn + ":" + ability.cardId] = true;
            activation.current = ability.responseId; lastName = session.cardForInspection(ability.cardId).name;
            driver.cardAction(ability); return true;
        }
        var specs = Common.deck(driver).mainboard.concat(Common.deck(driver).sideboard);
        var priority = ["Karn, the Great Creator", "Giant's Boulder", "Talisman of Resilience", "Expedition Map",
            "Ugin, Eye of the Storms", "Sowing Mycospawn", "Devourer of Destiny", "Sire of Seven Deaths", "Ulamog, the Ceaseless Hunger"];
        var spells = options.filter(o => o.kind === "cast").sort((a,b) => {
            var ai = priority.indexOf(session.cardForInspection(a.cardId).name), bi = priority.indexOf(session.cardForInspection(b.cardId).name);
            return (ai < 0 ? 99 : ai) - (bi < 0 ? 99 : bi);
        });
        for (var spell of spells) {
            var card = session.cardForInspection(spell.cardId), spec = specs.find(c => c.name === card.name);
            if (!spec || spec.manaValue > available(driver, spec.typeLine.includes("Creature"))) continue;
            if (spec.typeLine.includes("Legendary") && cards.some(c => c.name === card.name)) continue;
            if (spec.typeLine.includes("Instant")) continue;
            var key = session.turn + ":" + card.cardId + ":" + mana;
            if (tried[key]) continue;
            tried[key] = true; lastName = card.name;
            if (driver.cardAction(spell)) driver.casts++;
            return true;
        }
        driver.click("rulesPromptOption-$pass"); return true;
    }
    case "payManaCost": Common.pay(driver, options); return true;
    case "chooseCards": {
        var list = driver.item("rulesCardCandidates"), confirm = driver.item("rulesConfirmCards");
        if (!list) return true;
        var title = session.promptTitle + " " + session.promptDetail;
        var opening = /opening hand/i.test(title), dig = /top|library/i.test(title) && session.promptCards.items().length === 4;
        var wish = /outside|sideboard/i.test(title) || lastName === "Karn, the Great Creator";
        var tag = opening ? "opening" : dig ? "digs" : wish ? "wishes" : "cards";
        if (!recorded["prompt-" + session.promptId]) {
            recorded["prompt-" + session.promptId] = true;
            if (counters[tag] !== undefined) counters[tag]++;
            save(driver, tag);
        }
        var selected = [], candidates = [];
        for (var index = 0; index < list.count; index++) {
            var tile = list.itemAtIndex(index);
            if (!tile || !tile.selectable) continue;
            (tile.selected ? selected : candidates).push(tile);
        }
        var wanted = Math.min(session.promptMaxCardSelections, Math.max(1, session.promptMinCardSelections));
        if (selected.length >= wanted && confirm && confirm.enabled) {
            driver.click("rulesConfirmCards"); return true;
        }
        var needed = ["Urza's Tower", "Urza's Mine", "Urza's Power Plant"].filter(n => !ours(driver).some(c => c.name === n));
        var preferred = candidates.find(c => c.name === "Walking Ballista")
            || candidates.find(c => needed.includes(c.name)) || candidates[0];
        if (preferred && driver.click(preferred.objectName)) return true;
        driver.require(auditProbe.wheel(list, -160), "Cannot access the required card choice"); return true;
    }
    case "chooseFromSelection": {
        var list = driver.item("rulesScalarCandidates");
        if (!list) return true;
        var choices = Common.scalarChoices(list);
        if (choices.some(c => c.count > 0)) { driver.click("rulesConfirmChoices"); return true; }
        var wish = lastName === "Karn, the Great Creator" && choices.find(c => /outside|exile|\[-2\]/i.test(c.label));
        var chosen = wish || choices.find(c => /Add.*\{?C|Colorless/i.test(c.label))
            || choices.find(c => /^Cast|^Play/.test(c.label)) || choices[0];
        if (chosen) driver.click("rulesScalarChoice-" + chosen.responseId);
        return true;
    }
    case "chooseBoolean": {
        if (/Use triggered ability of Ugin's Labyrinth/.test(session.promptDetail)) {
            // Imprint with one copy and decline on later copies, so the board
            // must distinguish two identical lands with different linked state.
            driver.click("rulesScalarChoice-choice:" + (linked.length ? "0" : "1"));
            return true;
        }
        Common.chooseScalar(driver); return true;
    }
    case "chooseColor": Common.chooseScalar(driver); return true;
    case "scry": {
        var cards = session.promptCards.items();
        if (!ordered[session.promptId] && cards.length > 1) {
            save(driver, "scry-before");
            if (!driver.click("rulesScryLater-" + cards[0].cardId)) return true;
            ordered[session.promptId] = true; counters.reordered++;
            save(driver, "scry-after"); return true;
        }
        if (driver.click("confirmScryButton")) counters.scries++;
        return true;
    }
    case "revealCards": driver.click("acknowledgeRevealButton"); return true;
    case "chooseNumber": {
        var input = driver.item("rulesNumberInput");
        if (!input) return true;
        var wanted = Math.max(session.promptMinNumber, Math.min(session.promptMaxNumber,
            lastName === "Walking Ballista" ? Math.floor(available(driver, false) / 2) : 2));
        if (input.value !== wanted) {
            driver.require(auditProbe.click(input.value < wanted ? input.up.indicator : input.down.indicator),
                "Cannot adjust the native number control");
        } else driver.click("rulesConfirmNumber");
        return true;
    }
    default: return false;
    }
}
