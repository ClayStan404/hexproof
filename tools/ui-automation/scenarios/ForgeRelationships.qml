// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

// Deterministic maximized mana and permanent relationship fixture. Room and snapshot setup are
// recorded as fixtures; the window, table geometry and capture are native.
Item {
    id: driver
    property var steps: []
    property var assertions: []
    property var screenshots: []
    property int index: 0
    property bool acted: false
    property bool dispatching: false
    property bool finished: false
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
    function card(id, seat, name, setCode, number) {
        return {id: id, ownerSeat: seat, controllerSeat: seat, visible: true,
            identity: {name: name, setCode: setCode, collectorNumber: number}}
    }
    function duelTable() {
        return find("forgeDuelTable")
    }
    function read(name) {
        const board = duelTable()
        return board ? board.children.find(child => child.objectName === name) : null
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
            scenario: "forge-relationships",
            evidence: "native-qt-input",
            roomAndDeckSetup: "fixture",
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
    function apply() {
        require(auditProbe.applyRulesTableFixture(fixtureRoom, fixtureSnapshot), "Cannot apply fixture")
    }
    function plan() {
        add("Dismiss first-launch notices", () => {
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                const item = find(name)
                if (item) { require(auditProbe.click(item), "Cannot dismiss notice"); return false }
            }
            return !!find("mainMenuSettingsButton")
        })
        add("Open confirmed combat and attachments", () => {
            preferences.tableBackground = "astral"
            preferences.uiLanguage = "zh"
            fixtureRoom = {roomId:"FIX001", name:"Forge display verification", format:"modern", deckFormat:"modern",
                rulesMode:"forge", hostingMode:"server", hostConnected:true, maxSeats:2, phase:"started",
                matchMode:"bo1", role:"player", seatIndex:0, host:true,
                seats:[{occupied:true, displayName:"Alice", host:true, deckSelected:true, ready:true, loaded:true},
                       {occupied:true, displayName:"Bob", host:false, deckSelected:true, ready:true, loaded:true}]}
            const bear = (id, seat) => {
                const c = card(id, seat, "Grizzly Bears", "M10", "183")
                c.power = "2"; c.toughness = "2"; return c
            }
            const blocker = bear("blocker", 0); blocker.blocking = ["attacker"]
            const second = bear("blocker2", 0); second.blocking = ["attacker"]
            const attacker = bear("attacker", 1); attacker.attacking = true
            const other = bear("unblocked", 1); other.attacking = true
            const aura = card("aura", 0, "Rancor", "M13", "185"); aura.attachedTo = "attacker"
            const equipment = card("equipment", 0, "Bonesplitter", "MRD", "146"); equipment.attachedTo = "blocker"
            fixtureSnapshot = {roomId:"FIX001", gameId:"display-fixes", turn:4, step:"declare_blockers",
                activeSeat:1, prioritySeat:0,
                players:[{seat:0, name:"Alice", life:20, status:"playing", manaPool:
                    ["W", "U", "B", "R", "G", "C"].map((name, i) => ({name:name, value:i+1}))},
                    {seat:1, name:"Bob", life:20, status:"playing", manaPool:[{name:"C",value:2}]}],
                zones:[{zone:"hand",ownerSeat:0,count:7,cards:Array.from({length:7}, (_, i) =>
                        card("hand-"+i,0,"Lightning Bolt","M11","149"))},
                    {zone:"hand",ownerSeat:1,count:5,cards:[]},
                    {zone:"library",ownerSeat:0,count:43,cards:[]},
                    {zone:"library",ownerSeat:1,count:46,cards:[]},
                    {zone:"battlefield",ownerSeat:0,count:7,cards:[blocker,second,bear("idle",0),aura,equipment,
                        card("forest",0,"Forest","M21","272"),card("wastes",0,"Wastes","OGW","183")]},
                    {zone:"battlefield",ownerSeat:1,count:2,cards:[attacker,other]}],stack:[]}
            apply(); auditWindow.showTable()
        }, () => find("forgeCard-blocker") && find("forgeOwnCreatures").stackCount === 3
            && read("forgeRelationship-block-blocker-attacker") && find("forgeMana-0-C"))
        add("Clear initial pointer hover", () => {
            require(auditProbe.hover(find("rulesPlayerTarget1")), "Cannot move to the test player badge")
        }, () => !read("rulesCardHoverPreview").visible)
        add("Verify public links and distinct identical creatures", () => {
            const geometry = auditProbe.observe(auditWindow)
            require(geometry.windowMode === "maximized", "Primary check must be maximized")
            for (const name of ["forgeRelationship-block-blocker-attacker", "forgeRelationship-block-blocker2-attacker",
                               "forgeRelationship-attachment-equipment-blocker", "forgeRelationship-attachment-aura-attacker"])
                require(read(name).validAnchors, "Missing visible relationship: " + name)
            require(find("forgeOpponentCreatures").stackCount === 2, "Blocked and unblocked copies were merged")
            const pool = read("forgeManaPool-0")
            require(pool.manaPool.length === 6 && find("forgeMana-0-C").modelData.amount === 6, "Incomplete mana pool")
            require(pool.z > read("rulesCardHoverPreview").z, "Mana can be obscured by card preview")
            capture("confirmed-relations-and-six-mana")
            require(auditProbe.hover(find("forgeHandCard-hand-4")), "Cannot hover own hand")
        }, () => read("rulesCardHoverPreview").visible)
        add("Capture readable mana with a card preview", () => capture("mana-above-card-preview"))
        add("Move attachments and finish combat", () => {
            fixtureSnapshot.zones[4].cards[0].blocking = []
            fixtureSnapshot.zones[4].cards[1].blocking = []
            fixtureSnapshot.zones[4].cards[3].attachedTo = "idle"
            fixtureSnapshot.zones[4].cards[4].attachedTo = "idle"
            fixtureSnapshot.zones[5].cards[0].attacking = false
            fixtureSnapshot.zones[5].cards[1].attacking = false
            fixtureSnapshot.step = "main2"
            fixtureSnapshot.players[0].manaPool = []
            apply()
        }, () => !read("forgeRelationship-block-blocker-attacker")
            && read("forgeRelationship-attachment-equipment-idle")
            && !read("forgeManaPool-0").visible)
        add("Capture cleared combat and new attachment targets", () => {
            require(!read("forgeRelationship-attachment-aura-attacker"), "Old attachment persisted")
            require(read("forgeRelationship-attachment-aura-idle").validAnchors, "New attachment missing")
            capture("relationship-update-and-mana-clear")
        })
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
