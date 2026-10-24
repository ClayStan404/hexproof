// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
//
// Advisory Forge GUI timings against the budgets declared below.
// Not part of the default qml CTest run, and
// timing never fails it; only the deterministic image check does.
//
// QT_QPA_PLATFORM=offscreen ./build/client-qt/hexproof_qml_test \
//   -input apps/client-qt/tests/bench/tst_forgesmoothness.qml \
//   -import apps/client-qt/qml ForgeSmoothness::test_reportBudgets

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"
import "../../qml/screens"

TestCase {
    id: bench
    name: "ForgeSmoothness"
    when: windowShown
    property int serial: 1000
    readonly property int samples: 30
    readonly property var budgets: ({quiet:4, structural:6, prompt:5, decision:10, crowded:8})
    readonly property var ownLandIds: ["own-land-0", "own-land-1", "own-land-2", "own-land-3",
        "own-land-4", "own-land-5", "own-land-6"]

    ApplicationWindow {
        id: window
        width: 1920
        height: 1010
        visible: true
        property var openedScreen: ({})
        function pushScreen(url, properties) { openedScreen = {url, properties} }
        QtObject {
            id: room
            property int maxSeats: 2
            property string roomId: "DUEL01"
            property string roomName: "Forge bench"
            property string role: "player"
            property int seatIndex: 0
            property bool host: true
            property string phase: "started"
            property string matchMode: "bo1"
            property string format: "modern"
            property string deckFormat: "modern"
            property string hostingMode: "server"
            property bool hostConnected: true
            property var hostStatus: ({migrating:false})
            property string aiSource: ""
            property var aiStatus: ({})
            property bool spectatorsSeeHands: false
            property var seats: []
        }
        QtObject {
            id: match
            property int gameNumber: 1
            property var score: [0, 0]
            property var result: ({})
            property var sideboard: ({})
            property bool sideboarding: false
        }
        QtObject {
            id: transport
            property var rulesSession: testRulesPrompt.session
            property var roomSession: room
            property var gameSession: match
            property bool inRoom: true
            property bool rulesResponsePending: false
            property string peerTransportState: "off"
            property bool peerTransportAvailable: true
            property bool directPeerEnabled: false
            property var peerRequests: []
            property string lastError: ""
            property var responses: []
            function respondRulesPrompt(id, response) {
                responses = responses.concat([{id:id, response:response}])
                rulesResponsePending = true
            }
            function respondRulesPromptWithTargets(id, response, targets) { respondRulesPrompt(id, response) }
            function respondRulesPromptWithCards(id, response, cards) { respondRulesPrompt(id, response) }
            function respondRulesPromptWithAssignments(id, assignments) { respondRulesPrompt(id, "") }
            function respondRulesPromptWithDamage(id, assignments) { respondRulesPrompt(id, "") }
            function respondRulesPromptWithChoices(id, choices) { respondRulesPrompt(id, "") }
            function respondRulesPromptWithNumber(id, value) { respondRulesPrompt(id, "") }
        }
        QtObject {
            id: catalog
            property string language: "en"
            property int imageRevision: 0
            property var requested: []
            signal cardAvailable(string requestedName, string localizedName, string typeLine,
                                 string imagePath, string setCode, string collectorNumber)
            function tableImageSource(name) { requested.push(name); return "" }
            function imageSource(name) { requested.push(name); return "" }
            function cardTypeLine(name) {
                if (/^(Plains|Island|Mountain|Forest|Swamp)$/.test(name)) return "Land"
                if (name.indexOf("Relic") === 0) return "Artifact"
                return "Creature"
            }
            function cardDisplayName(name) { return name }
            function cardRulesText() { return "" }
        }
        RulesTable {
            id: table
            anchors.fill: parent
            wsModel: transport
            cardCatalogModel: catalog
            gameTableModel: testGameTable
            sideboardTableModel: testSideboardTable
        }
    }

    function init() {
        Theme.motionEnabled = false
        Theme.uiScale = 1
    }
    function cleanup() { Theme.motionEnabled = false }

    function card(id, seat, name, extra) {
        return Object.assign({id:id, ownerSeat:seat, controllerSeat:seat, visible:true, identity:{name:name}},
            extra || {})
    }
    function creature(id, seat, name, extra) {
        return card(id, seat, name, Object.assign({power:"2", toughness:"2"}, extra || {}))
    }
    // The design's probe board; `crowded` adds eight lands and eight creatures per side.
    function board(opts) {
        opts = opts || {}
        const tapped = opts.tapped || []
        const creatures = opts.crowded ? 14 : 6
        const extraLands = opts.crowded ? 8 : 0
        const own = [], opp = []
        ;["Plains", "Plains", "Plains", "Island", "Island", "Island", "Forest"].forEach((name, i) =>
            own.push(card("own-land-" + i, 0, name, {tapped:tapped.includes("own-land-" + i)})))
        for (let i = 0; i < creatures; ++i)
            own.push(creature("own-c-" + i, 0, "Bear " + i, i === 0 ? {counters:[{name:"+1/+1", value:2}]} : {}))
        for (let i = 0; i < extraLands; ++i)
            own.push(card("own-xland-" + i, 0, ["Plains", "Island", "Forest"][i % 3]))
        own.push(card("own-relic-0", 0, "Relic of Ages"))
        own.push(card("own-relic-1", 0, "Relic of Dawn"))
        for (const extra of (opts.extraOwn || []))
            own.push(extra)
        ;["Mountain", "Mountain", "Mountain", "Mountain", "Swamp", "Swamp"].forEach((name, i) =>
            opp.push(card("opp-land-" + i, 1, name)))
        for (let i = 0; i < creatures - 1; ++i)
            opp.push(creature("opp-c-" + i, 1, "Goblin " + i))
        for (let i = 0; i < extraLands; ++i)
            opp.push(card("opp-xland-" + i, 1, ["Mountain", "Swamp"][i % 2]))
        opp.push(card("opp-relic-0", 1, "Relic of Night"))
        const hand = []
        const handCount = opts.handCount === undefined ? 6 : opts.handCount
        for (let i = 0; i < handCount; ++i)
            hand.push(creature("hand-" + i, 0, "Spell " + i))
        const grave0 = [card("g0-0", 0, "Spell X"), card("g0-1", 0, "Spell Y"), card("g0-2", 0, "Spell Z")]
        const grave1 = [card("g1-0", 1, "Bolt A"), card("g1-1", 1, "Bolt B")]
        return {roomId:"DUEL01", gameId:"bench", turn:7, step:opts.step || "main1", activeSeat:0,
            prioritySeat:opts.prioritySeat === undefined ? 0 : opts.prioritySeat,
            players:[{seat:0, name:"Alice", life:18}, {seat:1, name:"Bob", life:opts.life1 || 14}],
            zones:[{zone:"hand", ownerSeat:0, count:hand.length, cards:hand},
                {zone:"hand", ownerSeat:1, count:5, cards:[]},
                {zone:"library", ownerSeat:0, count:40, cards:[]},
                {zone:"library", ownerSeat:1, count:41, cards:[]},
                {zone:"graveyard", ownerSeat:0, count:grave0.length, cards:grave0},
                {zone:"graveyard", ownerSeat:1, count:grave1.length, cards:grave1},
                {zone:"battlefield", ownerSeat:0, count:own.length, cards:own},
                {zone:"battlefield", ownerSeat:1, count:opp.length, cards:opp}],
            stack:opts.stack || []}
    }
    function entered(opts) {
        return board(Object.assign({handCount:5, extraOwn:[creature("hand-5", 0, "Spell 5")]}, opts || {}))
    }
    function stacked(opts) {
        return board(Object.assign({handCount:5, stack:[{id:"stack-1", sourceId:"hand-5", controllerSeat:0,
            ownerSeat:0, identity:{name:"Spell 5"}}]}, opts || {}))
    }
    function prompt(kind, extra) {
        transport.rulesResponsePending = false
        verify(testRulesPrompt.applyPrompt(Object.assign({roomId:"DUEL01", gameId:"bench", pending:true,
            supported:true, promptId:++serial, kind:kind, title:"Choose", detail:"", options:[], choices:[],
            cards:[], targets:[], contextCards:[], contextTargets:[], combatSources:[], combatTargets:[],
            damageTargets:[], scryDestinations:[], totalDamage:0}, extra || {})))
    }
    function priority(untapped) {
        const options = []
        for (let i = 0; i < 6; ++i)
            options.push({responseId:"cast-" + i, kind:"cast", cardId:"hand-" + i, label:"Spell " + i + " — cast spell"})
        for (const id of (untapped || ownLandIds))
            options.push({responseId:"mana-" + id, kind:"activateAbility", cardId:id, label:"Land — Tap for mana"})
        options.push({responseId:"$pass", kind:"pass", label:"Pass"})
        return {kind:"chooseAction", extra:{options:options}}
    }
    function payment(untapped) {
        return {kind:"payManaCost", extra:{title:"Pay Mana Cost: {2}{W}", promptPaymentId:"pay-1",
            options:(untapped || ownLandIds).map(id => ({responseId:"pay-" + id, kind:"activateAbility",
                cardId:id, label:"Land — Tap for mana"}))}}
    }
    readonly property var passOnly: ({kind:"chooseAction", extra:{options:[{responseId:"$pass", kind:"pass", label:"Pass"}]}})
    readonly property var paymentWithoutCards: ({kind:"payManaCost", extra:{title:"Pay Mana Cost: {2}{W}", options:[
        {responseId:"$auto-pay", kind:"autoPay", label:"Auto-pay"}, {responseId:"$cancel", kind:"cancel", label:"Cancel"}]}})
    readonly property var boardTargets: ({kind:"chooseBoardTargets", extra:{title:"Choose target creature",
        minSelections:1, maxSelections:1, cancellable:true,
        targets:["opp-c-0", "opp-c-1", "opp-c-2", "own-c-1", "own-c-2"].map((id, i) =>
            ({responseId:"target:" + i, kind:"card", objectId:id, label:id, name:id}))}})

    function settle() { wait(0); wait(0); wait(0) }
    // Date.now() has millisecond resolution, so a trimmed mean over many samples
    // resolves fractions of a millisecond and drops scheduler outliers.
    function trimmedMean(values) {
        const sorted = values.slice().sort((a, b) => a - b)
        const drop = Math.floor(sorted.length / 10)
        const kept = sorted.slice(drop, sorted.length - drop)
        return kept.reduce((sum, value) => sum + value, 0) / kept.length
    }
    function idleCost() {
        const values = []
        for (let i = 0; i < samples; ++i) {
            const started = Date.now()
            settle()
            values.push(Date.now() - started)
        }
        return trimmedMean(values)
    }
    function prepare(state, decision) {
        Theme.finishMotion()
        verify(testRulesPrompt.applySnapshot(state))
        prompt(decision.kind, decision.extra)
        settle()
        Theme.finishMotion()
        waitForRendering(table)
        settle()
    }
    // Each sample is one update plus the event-loop passes it triggers, minus the
    // cost of the same passes when idle. Running motion is finished outside it.
    function measure(update) {
        const idle = idleCost()
        const values = []
        for (let i = 0; i < samples; ++i) {
            const started = Date.now()
            update(i)
            settle()
            values.push(Date.now() - started)
            Theme.finishMotion()
            settle()
        }
        return Math.max(0, trimmedMean(values) - idle)
    }
    function snapshots(states) {
        return measure(i => verify(testRulesPrompt.applySnapshot(states[i % states.length])))
    }
    function prompts(decisions) {
        return measure(i => { const decision = decisions[i % decisions.length]; prompt(decision.kind, decision.extra) })
    }
    function decisions(steps) {
        return measure(i => {
            const step = steps[i % steps.length]
            transport.rulesResponsePending = true
            settle()
            verify(testRulesPrompt.applySnapshot(step.state))
            settle()
            prompt(step.decision.kind, step.decision.extra)
        })
    }

    function runCases() {
        const results = []
        const add = (category, label, ms) => results.push({category, label, ms})
        const spent = ownLandIds.filter(id => id !== "own-land-0")

        prepare(board(), priority())
        add("quiet", "tap one land", snapshots([board({tapped:["own-land-0"]}), board()]))
        add("quiet", "step change", snapshots([board({step:"upkeep"}), board({step:"draw"})]))
        add("quiet", "priority seat change", snapshots([board({prioritySeat:1}), board()]))
        add("quiet", "life change", snapshots([board({life1:13}), board()]))
        add("structural", "card enters", snapshots([entered(), board()]))
        add("structural", "stack push", snapshots([stacked(), board()]))

        add("prompt", "priority ↔ payment", prompts([priority(), payment()]))
        add("prompt", "priority, new id", prompts([priority()]))
        add("prompt", "pass-only priority", prompts([passOnly]))
        add("prompt", "pass ↔ board targets", prompts([passOnly, boardTargets]))
        add("prompt", "pass ↔ payment without card options", prompts([passOnly, paymentWithoutCards]))

        prepare(board(), payment())
        add("decision", "payment step", decisions([{state:board({tapped:["own-land-0"]}), decision:payment(spent)},
            {state:board(), decision:payment()}]))
        prepare(board(), priority())
        add("decision", "cast step and back", decisions([{state:stacked(), decision:payment()},
            {state:board(), decision:priority()}]))

        prepare(board({crowded:true}), priority())
        add("crowded", "tap one land", snapshots([board({crowded:true, tapped:["own-land-0"]}), board({crowded:true})]))
        add("crowded", "step change", snapshots([board({crowded:true, step:"upkeep"}), board({crowded:true, step:"draw"})]))
        add("crowded", "card enters", snapshots([entered({crowded:true}), board({crowded:true})]))
        add("crowded", "priority ↔ payment", prompts([priority(), payment()]))
        prepare(board(), priority())
        return results
    }

    function test_reportBudgets() {
        prepare(board(), priority())
        const requestedBefore = catalog.requested.length
        catalog.imageRevision++
        settle()
        compare(catalog.requested.length, requestedBefore, "A global image revision must not request every card again")

        const off = runCases()
        Theme.motionEnabled = true
        const on = runCases()
        Theme.motionEnabled = false

        const lines = ["Forge smoothness advisory, ms per update (trimmed mean of " + samples
                       + " settled samples), motion off / on:"]
        const report = {}
        for (const category of Object.keys(budgets)) {
            let worst = 0
            lines.push("  " + category + " (budget " + budgets[category] + " ms)")
            off.forEach((row, i) => {
                if (row.category !== category)
                    return
                worst = Math.max(worst, row.ms, on[i].ms)
                lines.push("    " + row.label + ": " + row.ms.toFixed(2) + " / " + on[i].ms.toFixed(2))
            })
            report[category] = {budget:budgets[category], worst:Number(worst.toFixed(2))}
            lines.push("    worst " + worst.toFixed(2) + (worst <= budgets[category] ? " — within" : " — over"))
        }
        console.log(lines.join("\n"))
        console.log("FORGE_BENCH " + JSON.stringify(report))
        verify(off.length === on.length && off.length > 0)
    }
}
