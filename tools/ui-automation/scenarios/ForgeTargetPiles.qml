// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

// Snapshot/prompt setup is a fixture; clicks and captures use the native table.
Item {
    id: driver
    property var steps: []
    property var assertions: []
    property var screenshots: []
    property var snapshot: ({})
    property int index: 0
    property bool acted: false
    property bool dispatching: false
    property bool finished: false
    property double stepStarted: Date.now()

    function require(value, message) {
        if (!value) throw new Error(message + (auditProbe.lastError ? "; " + auditProbe.lastError : ""))
    }
    function find(name) { return auditProbe.find(auditWindow, name) }
    function interaction() { return find("forgeDuelTable").tableController.interaction }
    function add(name, action, check) { steps.push({name, action, check:check || (() => true)}) }
    function click(name) { require(auditProbe.click(find(name)), "Cannot click " + name) }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }
    function targets(ids, promptId) {
        const candidates = ids.map(id => ({responseId:"target-" + id, kind:"card", objectId:"copy-" + id,
            label:"Grizzly Bears", name:"Grizzly Bears"}))
        // Keep the single-permanent probe in multi-select mode without sending
        // a response to the disconnected fixture transport.
        if (ids.length === 1) candidates.push({responseId:"player", kind:"player", seat:0, label:"Alice"})
        require(auditProbe.updateRulesTableFixture(snapshot, {
            roomId:"TGT001", gameId:"target-piles", promptId:promptId,
            pending:ids.length > 0, supported:true, kind:"chooseBoardTargets",
            title:"Choose targets", minSelections:ids.length, maxSelections:candidates.length,
            targets:candidates, options:[], choices:[], cards:[], contextCards:[], contextTargets:[],
            combatSources:[], combatTargets:[], damageTargets:[], scryDestinations:[], totalDamage:0
        }), "Cannot update target fixture")
    }
    function finish(error) {
        if (finished) return
        finished = true
        if (error && auditProbe.capture(auditWindow, "failure")) screenshots.push("failure.png")
        const geometry = auditProbe.observe(auditWindow)
        auditProbe.record("window-geometry", geometry)
        auditProbe.record("result", {
            status:error ? "failed" : "passed", scenario:"forge-target-piles",
            evidence:"native-qt-input", roomAndDeckSetup:"fixture", error:error || "",
            pendingStep:index < steps.length ? steps[index].name : "",
            assertions:assertions, requiredScreenshots:screenshots,
            requestedWindowMode:geometry.requestedWindowMode, windowMode:geometry.windowMode,
            width:geometry.width, height:geometry.height, dpr:geometry.dpr,
            screenGeometry:geometry.screenGeometry
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
        add("Open two identical opposing permanents", () => {
            preferences.uiLanguage = "zh"
            const room = {roomId:"TGT001", name:"Target selection verification", format:"modern",
                deckFormat:"modern", rulesMode:"forge", hostingMode:"server", hostConnected:true,
                maxSeats:2, phase:"started", matchMode:"bo1", role:"player", seatIndex:0, host:true,
                seats:[{occupied:true, displayName:"Alice", host:true, ready:true, loaded:true},
                    {occupied:true, displayName:"Bob", ready:true, loaded:true}]}
            snapshot = {roomId:"TGT001", gameId:"target-piles", turn:3, step:"main1",
                activeSeat:0, prioritySeat:0,
                players:[{seat:0, name:"Alice", life:20}, {seat:1, name:"Bob", life:20}],
                zones:[{zone:"hand", ownerSeat:0, count:0, cards:[]},
                    {zone:"hand", ownerSeat:1, count:5, cards:[]},
                    {zone:"library", ownerSeat:0, count:45, cards:[]},
                    {zone:"library", ownerSeat:1, count:43, cards:[]},
                    {zone:"battlefield", ownerSeat:0, count:0, cards:[]},
                    {zone:"battlefield", ownerSeat:1, count:2, cards:[0, 1].map(i => ({
                        id:"copy-" + i, ownerSeat:1, controllerSeat:1, visible:true,
                        identity:{name:"Grizzly Bears", setCode:"M10", collectorNumber:"183"},
                        power:"2", toughness:"2"}))}], stack:[]}
            require(auditProbe.applyRulesTableFixture(room, snapshot), "Cannot apply table fixture")
            auditWindow.showTable()
        }, () => find("forgeOpponentCreatures") && find("forgeOpponentCreatures").stackCount === 1)
        add("Capture resting pile", () => {
            require(auditProbe.observe(auditWindow).windowMode === "maximized", "Expected maximized window")
            capture("resting-pile")
            targets([0, 1], 1)
        }, () => find("forgeOpponentCreatures").stackCount === 2)
        add("Select the first copy", () => click("forgeCard-copy-1"), () => interaction().selectedCount === 1)
        add("Select the previously covered copy", () => click("forgeCard-copy-0"), () => interaction().selectedCount === 2)
        add("Verify both distinct targets", () => {
            require(find("forgeCard-copy-0").selected && find("forgeCard-copy-1").selected,
                "Both physical copies must remain selected")
            require(find("rulesConfirmTargets").enabled, "Two-target confirmation must be enabled")
            require(Object.keys(interaction().selectedTargetIds).sort().join() === "target-0,target-1",
                "Target response ids must be distinct")
            require(auditProbe.hover(find("rulesPlayerTarget0")), "Cannot clear card hover")
        })
        add("Capture both selected copies", () => capture("both-copies-selected"))
        add("Deselect only the first copy", () => click("forgeCard-copy-1"), () => interaction().selectedCount === 1)
        add("Reselect the first copy", () => click("forgeCard-copy-1"), () => interaction().selectedCount === 2)
        add("Only the formerly covered copy is a legal permanent", () => targets([0], 2),
            () => interaction().selectedCount === 0 && find("forgeCard-copy-0").actionable)
        add("Select the sole legal copy", () => {
            require(!find("forgeCard-copy-1").actionable, "Ineligible copy must not accept target input")
            click("forgeCard-copy-0")
        }, () => interaction().selectedTargetIds["target-0"] === true)
        add("End target selection", () => targets([], 3),
            () => find("forgeOpponentCreatures").stackCount === 1 && interaction().selectedCount === 0)
        add("Capture restored grouping", () => capture("restored-pile"))
    }
    Component.onCompleted: plan()
    Timer {
        interval:100; repeat:true; running:!driver.finished
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
                    driver.assertions.push({step:step.name, elapsedMs:Date.now() - driver.stepStarted})
                    driver.index++; driver.acted = false; driver.stepStarted = Date.now()
                } else driver.require(Date.now() - driver.stepStarted < 20000, "Timed out: " + step.name)
            } catch (error) { driver.finish(String(error)) }
            finally { driver.dispatching = false }
        }
    }
}
