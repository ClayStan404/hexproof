// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

// Edit blocker assignments for two attackers. Room and prompt setup are a fixture.
// Clicks, highlights and captures use the maximized native client.
Item {
    id: driver
    property var steps: []
    property var assertions: []
    property var screenshots: []
    property int index: 0
    property bool acted: false
    property bool dispatching: false
    property bool finished: false
    property bool projectionPending: false
    property double stepStarted: Date.now()

    function require(value, message) {
        if (!value)
            throw new Error(message + (auditProbe.lastError ? "; " + auditProbe.lastError : ""))
    }
    function find(name) {
        return auditProbe.find(auditWindow, name)
    }
    function add(name, action, check, timeout) {
        steps.push({name: name, action: action, check: check || (() => true), timeout: timeout || 20000})
    }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }
    function card(id, seat, name, setCode, number, extra) {
        return Object.assign({id: id, ownerSeat: seat, controllerSeat: seat, visible: true,
            identity: {name: name, setCode: setCode, collectorNumber: number}}, extra || {})
    }
    function creature(id, seat, name, setCode, number, extra) {
        return card(id, seat, name, setCode, number, Object.assign({power: "2", toughness: "2"}, extra || {}))
    }
    function duelTable() {
        return find("forgeDuelTable")
    }
    function arrow(name) {
        const board = duelTable()
        return board ? board.children.find(child => child.objectName === name) : null
    }
    function combat() {
        const board = duelTable()
        return board && board.tableController ? board.tableController.combatInteraction : null
    }
    function finish(error) {
        if (finished)
            return
        finished = true
        if (error && auditProbe.capture(auditWindow, "failure"))
            screenshots.push("failure.png")
        const geometry = auditProbe.observe(auditWindow)
        auditProbe.record("window-geometry", geometry)
        auditProbe.record("result", {
            status: error ? "failed" : "passed",
            scenario: "forge-blocker-choice",
            evidence: auditProbe.environment("AUDIT_OS_INPUT_HELPER") ? "system-input" : "native-qt-input",
            roomAndDeckSetup: "fixture",
            engineSubmission: false,
            error: error || "",
            pendingStep: index < steps.length ? steps[index].name : "",
            assertions: assertions,
            requiredScreenshots: screenshots,
            requestedWindowMode: geometry.requestedWindowMode,
            windowMode: geometry.windowMode,
            width: geometry.width,
            height: geometry.height,
            dpr: geometry.dpr,
            screenGeometry: geometry.screenGeometry
        })
        auditProbe.finish(error ? 1 : 0)
    }

    property var fixtureRoom: ({})
    property var fixtureSnapshot: ({})
    function prompt() {
        return {roomId: "FIX001", gameId: "blocker-choice", promptId: 7, pending: true, supported: true,
            kind: "chooseBlockers", title: "Declare blockers", detail: "",
            choices: [], cards: [], targets: [], contextCards: [], contextTargets: [],
            damageTargets: [], scryDestinations: [], options: [], totalDamage: 0,
            combatSources: [0, 1].map(i => ({responseId: "block-" + i, objectId: "own-" + i,
                label: i === 0 ? "Grizzly Bears" : "Serra Angel",
                name: i === 0 ? "Grizzly Bears" : "Serra Angel",
                validTargetIds: ["atk-a", "atk-b"], maxAssignments: 1})),
            combatTargets: [
                {responseId: "atk-a", kind: "attacker", objectId: "atk-a", label: "Raging Goblin",
                    name: "Raging Goblin", maxAssignments: 2},
                {responseId: "atk-b", kind: "attacker", objectId: "atk-b", label: "Runeclaw Bear",
                    name: "Runeclaw Bear", maxAssignments: 2}]}
    }
    function plan() {
        add("Dismiss first-launch notices", () => {
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                const item = find(name)
                if (item) {
                    require(auditProbe.click(item), "Cannot dismiss notice")
                    return false
                }
            }
            return !!find("mainMenuSettingsButton")
        })
        add("Open two attackers and two blockers", () => {
            preferences.tableBackground = "astral"
            preferences.uiLanguage = "zh"
            fixtureRoom = {roomId: "FIX001", name: "Forge blocker choice", format: "modern",
                deckFormat: "modern", rulesMode: "forge", hostingMode: "server", hostConnected: true,
                maxSeats: 2, phase: "started", matchMode: "bo1", role: "player", seatIndex: 0, host: true,
                seats: [{occupied: true, displayName: "Player", host: true, deckSelected: true, ready: true, loaded: true},
                    {occupied: true, displayName: "Opponent", deckSelected: true, ready: true, loaded: true}]}
            const own = [creature("own-0", 0, "Grizzly Bears", "LEA", "199"),
                creature("own-1", 0, "Serra Angel", "M10", "29", {power: "4", toughness: "4"}),
                card("walker", 0, "Liliana of the Veil", "ISD", "105"),
                card("forest", 0, "Forest", "M21", "272")]
            const theirs = [creature("atk-a", 1, "Raging Goblin", "M10", "153",
                    {attacking: true, attackingTarget: "walker", power: "1", toughness: "1"}),
                creature("atk-b", 1, "Runeclaw Bear", "M10", "203",
                    {attacking: true, attackingTarget: "walker"})]
            fixtureSnapshot = {roomId: "FIX001", gameId: "blocker-choice", turn: 4, step: "declare_blockers",
                activeSeat: 1, prioritySeat: 0,
                players: [{seat: 0, name: "Player", life: 19, status: "playing"},
                    {seat: 1, name: "Opponent", life: 20, status: "playing"}],
                zones: [{zone: "hand", ownerSeat: 0, count: 0, cards: []},
                    {zone: "hand", ownerSeat: 1, count: 5, cards: []},
                    {zone: "library", ownerSeat: 0, count: 40, cards: []},
                    {zone: "library", ownerSeat: 1, count: 40, cards: []},
                    {zone: "battlefield", ownerSeat: 0, count: own.length, cards: own},
                    {zone: "battlefield", ownerSeat: 1, count: theirs.length, cards: theirs}],
                stack: []}
            // Deliver the projection after setup leaves the JS stack, like an
            // incoming room message, before inspecting live delegates.
            projectionPending = true
            Qt.callLater(function() {
                try {
                    driver.require(auditProbe.applyRulesTableFixture(driver.fixtureRoom, driver.fixtureSnapshot), "Cannot apply fixture")
                    auditWindow.showTable()
                    driver.require(auditProbe.updateRulesTableFixture(driver.fixtureSnapshot, driver.prompt()), "Cannot publish blockers")
                } catch (error) {
                    driver.finish(String(error))
                } finally {
                    driver.projectionPending = false
                }
            })
        }, () => !projectionPending && find("forgeCard-own-0") && find("forgeCard-own-1")
            && find("forgeCard-atk-a") && find("forgeCard-atk-b")
            && !!(arrow("forgeRelationship-attack-atk-a-walker")
                  && arrow("forgeRelationship-attack-atk-a-walker").validAnchors)
            && !!(arrow("forgeRelationship-attack-atk-b-walker")
                  && arrow("forgeRelationship-attack-atk-b-walker").validAnchors))
        add("Settle the maximized board", () => {
            const geometry = auditProbe.observe(auditWindow)
            require(geometry.windowMode === "maximized", "Primary check must be maximized")
            require(auditProbe.hover(find("rulesPlayerTarget1")), "Cannot clear hover")
        }, () => Date.now() - stepStarted > 700 && !arrow("forgeTurnCallout").visible)
        add("Both attackers are selectable before a blocker is chosen", () => {
            const state = combat()
            require(state && state.active && !state.attacking, "Blocker choice is not active")
            require(state.offered("atk-a") && state.offered("atk-b"), "An attacker is not offered")
            require(!find("rulesCombatCandidates-blockers"), "The assignment list is open")
            const instruction = find("rulesCombatInstruction-blockers")
            require(instruction && instruction.text.length > 0, "Missing board instruction")
            auditProbe.record("offered-hints", {
                atkA: find("forgeCardInteractionHint-atk-a").text,
                atkB: find("forgeCardInteractionHint-atk-b").text,
                instruction: instruction.text
            })
            capture("both-attackers-selectable")
        })
        add("Select the second attacker first", () => {
            require(auditProbe.click(find("forgeCard-atk-b")), "Cannot select Runeclaw Bear")
        }, () => combat().pendingAttacker === "atk-b")
        add("Capture the selected attacker", () => {
            auditProbe.record("pending-attacker", {
                pending: combat().pendingAttacker,
                hint: find("forgeCardInteractionHint-atk-b").text,
                instruction: find("rulesCombatInstruction-blockers").text
            })
            capture("attacker-selected-first")
        })
        add("Block the selected attacker with Grizzly Bears", () => {
            require(auditProbe.click(find("forgeCard-own-0")), "Cannot assign Grizzly Bears")
        }, () => combat().assignments["block-0"] === "atk-b" && combat().pendingAttacker === "")
        add("Select Serra Angel, then the other attacker", () => {
            if (combat().selectedSource !== "block-1") {
                require(auditProbe.click(find("forgeCard-own-1")), "Cannot select Serra Angel")
                return false
            }
            require(auditProbe.click(find("forgeCard-atk-a")), "Cannot assign Raging Goblin")
            return true
        }, () => combat().assignments["block-0"] === "atk-b" && combat().assignments["block-1"] === "atk-a")
        add("Both blocker links have visible endpoints", () => {}, () => {
            const bears = arrow("forgeCombatArrow-own-0-atk-b")
            const angel = arrow("forgeCombatArrow-own-1-atk-a")
            return Date.now() - stepStarted > 700 && bears && angel
                && bears.visible && angel.visible && bears.validAnchors && angel.validAnchors
        })
        add("Capture both blocks", () => {
            auditProbe.record("assignments", {
                bears: combat().assignments["block-0"],
                angel: combat().assignments["block-1"]
            })
            capture("both-attackers-blocked")
        })
        add("Clear preview and inspect both relationship lines", () => {
            require(auditProbe.hover(find("forgeGameMenu")), "Cannot clear the final card preview")
        }, () => Date.now() - stepStarted > 400)
        add("Capture the unobscured assignments", () => capture("both-blocks-without-preview"))
    }

    Component.onCompleted: plan()
    Timer {
        interval: 60
        repeat: true
        running: !driver.finished
        onTriggered: {
            if (driver.dispatching)
                return
            driver.dispatching = true
            try {
                if (driver.index >= driver.steps.length) {
                    driver.finish("")
                    return
                }
                if (auditWindow.stack.busy)
                    return
                const step = driver.steps[driver.index]
                if (!driver.acted) {
                    if (step.action() === false) {
                        driver.require(Date.now() - driver.stepStarted < step.timeout, "Cannot reach: " + step.name)
                        return
                    }
                    driver.acted = true
                }
                if (step.check()) {
                    driver.assertions.push({step: step.name, elapsedMs: Date.now() - driver.stepStarted})
                    driver.index++
                    driver.acted = false
                    driver.stepStarted = Date.now()
                } else {
                    driver.require(Date.now() - driver.stepStarted < step.timeout, "Timed out: " + step.name)
                }
            } catch (error) {
                driver.finish(String(error))
            } finally {
                driver.dispatching = false
            }
        }
    }
}
