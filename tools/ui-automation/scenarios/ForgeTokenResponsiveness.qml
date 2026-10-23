// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: driver
    property bool entered: false
    property int countIndex: 0
    property int iteration: 0
    property var counts: [0, 1, 2, 4, 8, 16]
    property var measurements: []
    property var timings: []
    property double previous: 0
    property var room: ({roomId: "TOK001", name: "Token responsiveness fixture",
        format: "modern", deckFormat: "modern", rulesMode: "forge", hostingMode: "server",
        hostConnected: true, maxSeats: 2, phase: "started", matchMode: "bo1",
        role: "player", seatIndex: 0, host: true,
        seats: [{occupied: true, displayName: "Token test A", host: true, ready: true, loaded: true},
                {occupied: true, displayName: "Token test B", ready: true, loaded: true}]})

    function apply() {
        const tokens = Array.from({length: counts[countIndex]}, (_, i) => ({
            id: "spawn-" + i, ownerSeat: 0, controllerSeat: 0, visible: true,
            identity: {name: "Eldrazi Spawn", setCode: "TMH3", collectorNumber: "2", token: true},
            power: "0", toughness: "1", tapped: iteration % 2 === 1}))
        const state = {roomId: "TOK001", gameId: "token-fixture", turn: 3, step: "main1",
            activeSeat: 0, prioritySeat: 0,
            players: [{seat: 0, name: "Token test A", life: 20}, {seat: 1, name: "Token test B", life: 20}],
            zones: [{zone: "hand", ownerSeat: 0, count: 0, cards: []},
                    {zone: "hand", ownerSeat: 1, count: 7, cards: []},
                    {zone: "library", ownerSeat: 0, count: 53, cards: []},
                    {zone: "library", ownerSeat: 1, count: 53, cards: []},
                    {zone: "battlefield", ownerSeat: 0, count: tokens.length, cards: tokens},
                    {zone: "battlefield", ownerSeat: 1, count: 0, cards: []}], stack: []}
        const prompt = {roomId: "TOK001", gameId: "token-fixture",
            promptId: 1000 + countIndex * 100 + iteration, pending: true, supported: true,
            kind: "chooseAction", title: "Choose an action", detail: "",
            // These labels intentionally match Forge's engine names, which differ
            // from the identities in the public snapshot and installed catalog.
            options: tokens.map((c, i) => ({responseId: "action:" + i, kind: "activateAbility",
                cardId: c.id, label: "Eldrazi Spawn Token — activate ability"}))
                .concat([{responseId: "$pass", kind: "pass", label: "Pass priority"}]),
            choices: [], cards: [], targets: [], contextCards: [], contextTargets: [],
            combatSources: [], combatTargets: [], damageTargets: [], scryDestinations: [], totalDamage: 0}
        if (!entered) {
            if (!auditProbe.applyRulesTableFixture(room, state)) throw Error(auditProbe.lastError)
            entered = true
        }
        previous = Date.now()
        if (!auditProbe.updateRulesTableFixture(state, prompt)) throw Error(auditProbe.lastError)
        timings.push({applyMs: Date.now() - previous})
    }
    function finish(error) {
        tick.stop()
        auditProbe.record("result", {status: error ? "failed" : "passed", error: error || "",
            measurements: measurements, requiredScreenshots: ["two-spawn.png"],
            evidence: "Native snapshot/prompt fixture, not a live match"})
        auditProbe.finish(error ? 1 : 0)
    }
    Timer {
        id: tick
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            try {
                if (!driver.entered) {
                    if (!cardCatalog.installed) throw Error("This probe requires an installed full catalog")
                    cardCatalog.language = "zh"
                    driver.apply()
                    return
                }
                driver.timings[driver.timings.length - 1].eventMs = Date.now() - driver.previous
                if (++driver.iteration >= 10) {
                    const result = {tokens: driver.counts[driver.countIndex], timings: driver.timings}
                    driver.measurements.push(result)
                    auditProbe.record("tokens-" + result.tokens, result)
                    if (result.tokens === 2) {
                        const front = auditProbe.find(auditWindow.contentItem, "forgeCard-spawn-1")
                        if (!front || !auditProbe.hover(front)) throw Error(auditProbe.lastError)
                        if (!auditProbe.capture(auditWindow, "two-spawn")) throw Error(auditProbe.lastError)
                    }
                    driver.iteration = 0
                    driver.timings = []
                    if (++driver.countIndex >= driver.counts.length) {
                        driver.finish("")
                        return
                    }
                }
                driver.apply()
            } catch (error) { driver.finish(String(error)) }
        }
    }
}
