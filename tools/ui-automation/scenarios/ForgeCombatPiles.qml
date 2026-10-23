// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

// Identical tokens share piles only when their combat state and targets match.
// Snapshots are fixtures; clicks and captures are native.
Item {
    id: driver
    property var steps: []
    property var assertions: []
    property var screenshots: []
    property var snapshot: ({})
    property int promptSerial: 0
    property int index: 0
    property bool acted: false
    property bool dispatching: false
    property bool finished: false
    property double stepStarted: Date.now()

    function require(value, message) {
        if (!value)
            throw new Error(message + (auditProbe.lastError ? "; " + auditProbe.lastError : ""))
    }
    function find(name) { return auditProbe.find(auditWindow, name) }
    function overlay(name) { return find("forgeDuelTable").children.find(item => item.objectName === name) }
    function lane() { return find("forgeOwnCreatures") }
    function combat() { return find("forgeDuelTable").tableController.combatInteraction }
    function add(name, action, check) { steps.push({name, action, check: check || (() => true)}) }
    function click(name) { require(auditProbe.click(find(name)), "Cannot click " + name) }
    function shape(sizes) {
        return lane() && lane().visibleStackIds.map(ids => ids.length).sort((a, b) => a - b).join()
            === sizes.slice().sort((a, b) => a - b).join()
    }
    function assignedPair() {
        return shape([2, 8]) && lane().visibleStackIds.some(ids => ids.length === 2
            && ids.includes("spawn-0") && ids.includes("spawn-1"))
    }
    function rect(item) {
        const position = item.mapToItem(find("forgeDuelTable"), 0, 0)
        return {x: position.x, y: position.y, width: item.width, height: item.height}
    }
    function overlaps(a, b) {
        return a.x < b.x + b.width - 0.5 && b.x < a.x + a.width - 0.5
            && a.y < b.y + b.height - 0.5 && b.y < a.y + a.height - 0.5
    }
    function record(name) {
        const stacks = lane().visibleStackIds
        const cards = stacks.map(ids => Object.assign({ids: ids}, rect(lane().itemFor(ids[ids.length - 1]))))
        for (let i = 0; i < cards.length; ++i) {
            for (let j = i + 1; j < cards.length; ++j)
                require(!overlaps(cards[i], cards[j]), "Distinct pile front faces overlap: " + name)
        }
        const banner = overlay("forgeOpponentDeciding")
        const bannerRect = banner && banner.visible ? rect(banner) : null
        const titles = stacks.map(ids => rect(find("forgeCardName-" + ids[ids.length - 1])))
        const counts = stacks.filter(ids => ids.length > 1).map(ids => {
            const id = ids[ids.length - 1]
            const badge = lane().itemFor(id).children.find(item => item.objectName === "forgeCardStackCount-" + id)
            require(badge && badge.visible, "Pile count is not visible: " + name)
            return rect(badge)
        })
        if (bannerRect) {
            for (const readout of titles.concat(counts))
                require(!overlaps(bannerRect, readout), "Opponent deciding banner obscures a title or pile count: " + name)
        }
        const phase = overlay("forgePhaseTrack")
        const phasePaint = phase && phase.visible
            ? phase.compactMode ? phase.children.find(item => item.objectName === "forgeCurrentPhase") : phase : null
        const phaseRect = phasePaint ? rect(phasePaint) : null
        if (phaseRect) {
            for (const readout of titles.concat(counts))
                require(!overlaps(phaseRect, readout), "Phase strip obscures a title or pile count: " + name)
        }
        auditProbe.record(name, {
            stacks: stacks,
            assignments: combat().assignments,
            cards: cards,
            titles: titles,
            counts: counts,
            opponentDeciding: bannerRect,
            phasePaint: phaseRect
        })
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }
    function settledRecord(name) {
        add("Clear hover for " + name, () => {
            require(auditProbe.hover(find("forgeGameMenu")), "Cannot clear card hover")
        }, () => Date.now() - stepStarted > 700)
        add("Capture " + name, () => record(name))
    }
    function update(kind) {
        const choosing = kind === "chooseAttackers" || kind === "chooseBlockers"
        const attacking = kind === "chooseAttackers"
        const target = attacking
            ? {responseId: "defender", kind: "player", seat: 1, label: "Opponent", maxAssignments: 10}
            : {responseId: "attacker", kind: "attacker", objectId: "attacker", name: "Grizzly Bears",
                label: "Grizzly Bears", maxAssignments: 10}
        require(auditProbe.updateRulesTableFixture(snapshot, {
            roomId: "PIL001", gameId: "combat-piles", promptId: ++promptSerial,
            pending: choosing, supported: true, kind: kind || "chooseAction", title: "Choose", detail: "",
            choices: [], cards: [], targets: [], contextCards: [], contextTargets: [],
            damageTargets: [], scryDestinations: [], options: [], totalDamage: 0,
            combatSources: choosing ? Array.from({length: 10}, (_, i) => ({
                responseId: "source-" + i, objectId: "spawn-" + i, name: "Eldrazi Spawn",
                label: "Eldrazi Spawn", validTargetIds: [target.responseId], maxAssignments: 1})) : [],
            combatTargets: choosing ? [target] : []
        }), "Cannot update combat fixture")
    }
    function finish(error) {
        if (finished) return
        finished = true
        if (error && auditProbe.capture(auditWindow, "failure")) screenshots.push("failure.png")
        const geometry = auditProbe.observe(auditWindow)
        auditProbe.record("window-geometry", geometry)
        auditProbe.record("result", {
            status: error ? "failed" : "passed", scenario: "forge-combat-piles",
            evidence: auditProbe.environment("AUDIT_OS_INPUT_HELPER") ? "system-input" : "native-qt-input",
            roomAndDeckSetup: "fixture", engineSubmission: false, error: error || "",
            pendingStep: index < steps.length ? steps[index].name : "",
            assertions: assertions, requiredScreenshots: screenshots,
            requestedWindowMode: geometry.requestedWindowMode, windowMode: geometry.windowMode,
            width: geometry.width, height: geometry.height, dpr: geometry.dpr,
            screenGeometry: geometry.screenGeometry
        })
        auditProbe.finish(error ? 1 : 0)
    }
    function plan() {
        add("Dismiss first-launch notices", () => {
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                if (find(name)) { click(name); return false }
            }
            return !!find("mainMenuSettingsButton")
        })
        add("Open ten identical blockers", () => {
            preferences.uiLanguage = "zh"
            preferences.tableBackground = "astral"
            const room = {roomId: "PIL001", name: "Combat pile verification", format: "modern",
                deckFormat: "modern", rulesMode: "forge", hostingMode: "server", hostConnected: true,
                maxSeats: 2, phase: "started", matchMode: "bo1", role: "player", seatIndex: 0, host: true,
                seats: [{occupied: true, displayName: "Player", host: true, ready: true, loaded: true},
                    {occupied: true, displayName: "Opponent", ready: true, loaded: true}]}
            const tokens = Array.from({length: 10}, (_, i) => ({id: "spawn-" + i,
                ownerSeat: 0, controllerSeat: 0, visible: true,
                identity: {name: "Eldrazi Spawn", setCode: "TMH3", collectorNumber: "2", token: true},
                power: "0", toughness: "1"}))
            snapshot = {roomId: "PIL001", gameId: "combat-piles", turn: 4, step: "declare_blockers",
                activeSeat: 1, prioritySeat: 0,
                players: [{seat: 0, name: "Player", life: 20}, {seat: 1, name: "Opponent", life: 20}],
                zones: [{zone: "hand", ownerSeat: 0, count: 0, cards: []},
                    {zone: "hand", ownerSeat: 1, count: 5, cards: []},
                    {zone: "library", ownerSeat: 0, count: 43, cards: []},
                    {zone: "library", ownerSeat: 1, count: 44, cards: []},
                    {zone: "battlefield", ownerSeat: 0, count: tokens.length, cards: tokens},
                    {zone: "battlefield", ownerSeat: 1, count: 1, cards: [{
                        id: "attacker", ownerSeat: 1, controllerSeat: 1, visible: true,
                        identity: {name: "Grizzly Bears", setCode: "M10", collectorNumber: "183"},
                        power: "2", toughness: "2", attacking: true, attackingPlayer: 0}]}], stack: []}
            require(auditProbe.applyRulesTableFixture(room, snapshot), "Cannot apply table fixture")
            auditWindow.showTable()
            update("chooseBlockers")
        }, () => shape([10]) && combat().active)
        add("Check maximized native window", () => {
            require(auditProbe.observe(auditWindow).windowMode === "maximized", "Expected maximized window")
        })
        settledRecord("ten-idle-blockers")
        add("Block with one token from the pile", () => click("forgeCard-spawn-9"),
            () => shape([1, 9]) && combat().assignments["source-0"] === "attacker")
        settledRecord("one-draft-blocker-nine-idle")
        add("Cancel the separated blocker", () => click("forgeCard-spawn-0"),
            () => shape([10]) && !combat().assignments["source-0"])
        settledRecord("cancel-block-restores-pile")
        add("Assign the first blocker again", () => click("forgeCard-spawn-9"),
            () => shape([1, 9]) && combat().assignments["source-0"] === "attacker")
        add("Assign a second blocker to the same attacker", () => click("forgeCard-spawn-9"),
            () => assignedPair() && combat().assignments["source-1"] === "attacker")
        settledRecord("two-draft-blockers-eight-idle")
        add("Publish both blocker assignments", () => {
            snapshot.zones[4].cards[0].blocking = ["attacker"]
            snapshot.zones[4].cards[1].blocking = ["attacker"]
            snapshot.step = "combat_damage"
            update("")
        }, () => assignedPair() && !combat().active)
        settledRecord("two-public-blockers-eight-idle")
        add("Finish combat and regroup matching tokens", () => {
            for (const card of snapshot.zones[4].cards) card.blocking = []
            snapshot.zones[5].cards[0].attacking = false
            snapshot.step = "main2"
            update("")
        }, () => shape([10]))
        settledRecord("block-combat-ended")
        add("Offer ten identical attackers", () => {
            snapshot.step = "declare_attackers"
            snapshot.activeSeat = 0
            update("chooseAttackers")
        }, () => shape([10]) && combat().active && combat().attacking)
        add("Attack with one token from the pile", () => click("forgeCard-spawn-9"),
            () => shape([1, 9]) && combat().assignments["source-0"] === "defender")
        settledRecord("one-draft-attacker-nine-idle")
        add("Cancel the separated attacker", () => click("forgeCard-spawn-0"),
            () => shape([10]) && !combat().assignments["source-0"])
        settledRecord("cancel-attack-restores-pile")
        add("Assign the first attacker again", () => click("forgeCard-spawn-9"),
            () => shape([1, 9]) && combat().assignments["source-0"] === "defender")
        add("Assign a second attacker to the same player", () => click("forgeCard-spawn-9"),
            () => assignedPair() && combat().assignments["source-1"] === "defender")
        settledRecord("two-draft-attackers-eight-idle")
        add("Publish both attackers", () => {
            for (const card of snapshot.zones[4].cards.slice(0, 2)) {
                card.attacking = true
                card.attackingPlayer = 1
                card.tapped = true
            }
            snapshot.step = "declare_blockers"
            update("")
        }, () => assignedPair() && !combat().active)
        settledRecord("two-public-attackers-eight-idle")
        add("Give priority to the defending opponent", () => {
            snapshot.prioritySeat = 1
            update("")
        }, () => assignedPair() && overlay("forgeOpponentDeciding").visible)
        settledRecord("public-attackers-opponent-deciding")
        add("End combat with all tokens in matching state", () => {
            for (const card of snapshot.zones[4].cards) {
                card.attacking = false
                delete card.attackingPlayer
                card.tapped = false
            }
            snapshot.step = "main2"
            update("")
        }, () => shape([10]))
        settledRecord("attack-combat-ended")
        add("Three identical attackers with only one blocked", () => {
            const zone = snapshot.zones[4]
            zone.cards = zone.cards.slice(0, 3)
            zone.count = zone.cards.length
            for (const card of zone.cards) {
                card.attacking = true
                card.attackingPlayer = 1
                card.tapped = true
            }
            snapshot.zones[5].cards[0].blocking = ["spawn-0"]
            snapshot.step = "combat_damage"
            update("")
        }, () => shape([1, 2]) && lane().visibleStackIds.some(ids => ids.length === 1 && ids[0] === "spawn-0"))
        settledRecord("one-blocked-two-unblocked-attackers")
        add("Clear the blocking relationship and regroup matching attackers", () => {
            snapshot.zones[5].cards[0].blocking = []
            update("")
        }, () => shape([3]))
        settledRecord("three-unblocked-attackers-regrouped")
    }
    Component.onCompleted: plan()
    Timer {
        interval: 80; repeat: true; running: !driver.finished
        onTriggered: {
            if (driver.dispatching) return
            driver.dispatching = true
            try {
                if (driver.index >= driver.steps.length) { driver.finish(""); return }
                if (auditWindow.stack.busy) return
                const step = driver.steps[driver.index]
                if (!driver.acted) {
                    if (step.action() === false) {
                        driver.require(Date.now() - driver.stepStarted < 20000, "Cannot reach: " + step.name)
                        return
                    }
                    driver.acted = true
                }
                if (step.check()) {
                    driver.assertions.push({step: step.name, elapsedMs: Date.now() - driver.stepStarted})
                    driver.index++; driver.acted = false; driver.stepStarted = Date.now()
                } else driver.require(Date.now() - driver.stepStarted < 20000, "Timed out: " + step.name)
            } catch (error) { driver.finish(String(error)) }
            finally { driver.dispatching = false }
        }
    }
}
