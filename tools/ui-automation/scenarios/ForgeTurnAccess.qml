// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

// Deterministic maximized control, library and arrival UI fixture. Setup is
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
    property int stage: 0
    property bool busy: false
    property var tableSurface: null

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
        return tableSurface || find("forgeDuelTable")
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
            scenario: "forge-turn-access",
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

    property var roomFixture: ({
        roomId:"TURN01", name:"Turn access review", format:"modern", deckFormat:"custom",
        rulesMode:"forge", hostingMode:"server", hostConnected:true, maxSeats:2,
        phase:"started", matchMode:"bo1", role:"player", seatIndex:0, host:true,
        seats:[{occupied:true, displayName:"Alice", host:true, ready:true, loaded:true},
               {occupied:true, displayName:"Bob", host:false, ready:true, loaded:true}]
    })
    property var state: ({})
    function apply() {
        require(auditProbe.applyRulesTableFixture(roomFixture, state), "Cannot apply table fixture")
    }
    function plan() {
        add("Dismiss first-launch notices", () => {
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                const item = find(name)
                if (item) { require(auditProbe.click(item), "Cannot dismiss notice"); return false }
            }
            return !!find("mainMenuSettingsButton")
        })
        add("Show permitted library top and distinct new permanents", () => {
            preferences.tableBackground = "astral"
            const oldBear = card("old-bear", 0, "Grizzly Bears", "10E", "268")
            oldBear.power = "2"; oldBear.toughness = "2"
            const newBear = Object.assign({}, oldBear, {id:"new-bear", enteredThisTurn:true, summoningSick:true})
            const land = card("old-land", 0, "Island", "M21", "263")
            const newLand = Object.assign({}, land, {id:"new-land", enteredThisTurn:true})
            const chocobo = card("chocobo", 0, "Traveling Chocobo", "FIN", "210")
            chocobo.power = "3"; chocobo.toughness = "3"
            state = {
                roomId:"TURN01", gameId:"turn-access", turn:3, step:"main1", activeSeat:0, prioritySeat:0,
                players:[{seat:0, name:"Alice", life:20}, {seat:1, name:"Bob", life:20}],
                zones:[
                    {zone:"hand", ownerSeat:0, count:1, cards:[card("our-hand",0,"Island","M21","263")]},
                    {zone:"hand", ownerSeat:1, count:1, cards:[]},
                    {zone:"library", ownerSeat:0, count:45, cards:[card("top",0,"Island","M21","263")]},
                    {zone:"library", ownerSeat:1, count:46, cards:[]},
                    {zone:"battlefield", ownerSeat:0, count:5, cards:[oldBear,newBear,land,newLand,chocobo]},
                    {zone:"battlefield", ownerSeat:1, count:1, cards:[card("other-land",1,"Island","M21","263")]}
                ], stack:[]
            }
            apply(); auditWindow.showTable()
        }, () => find("forgeOwnCreatures") && find("forgeOwnCreatures").stackCount === 3
            && find("forgeOwnLands").stackCount === 2 && find("forgeZone-library").showsPublicFace)
        add("Inspect new permanent labels at native size", () => {
            tableSurface = duelTable()
            const geometry = auditProbe.observe(auditWindow)
            require(geometry.windowMode === "maximized", "Window is not maximized")
            require(find("forgeCard-new-bear").persistentSummary.includes("Summoning sickness"), "Missing sickness")
            require(find("forgeCard-new-land").persistentSummary.includes("Entered this turn"), "Missing new land marker")
            capture("library-top-and-new-permanents")
            require(auditProbe.click(find("forgeZone-library")), "Cannot open library")
        }, () => duelTable().modalOpen && find("forgeZoneCards") && find("forgeZoneCards").visibleCards.length === 1)
        add("Inspect only the authorized top in the library browser", () => {
            require(find("forgeZoneCards").visibleCards[0].cardId === "top", "Wrong top card")
            capture("library-browser")
            require(auditProbe.click(find("forgeCloseZonePopup")), "Cannot close library")
        }, () => !duelTable().modalOpen)
        add("Switch to the controlled opponent's hand", () => {
            state.activeSeat = 1; state.prioritySeat = 1
            state.players[1].controllingSeat = 0
            state.zones[1].cards = [card("controlled-hand",1,"Island","M21","263")]
            apply()
        }, () => find("forgeHand") && find("forgeHand").visibleCards.length === 1
            && find("forgeHand").visibleCards[0].cardId === "controlled-hand"
            && find("forgePlayerControlStatus").visible)
        add("Inspect controlled turn orientation", () => {
            require(duelTable().bottomSeat === 1, "Controlled battlefield did not move to near side")
            capture("controlled-turn")
            delete state.players[1].controllingSeat
            state.zones[1].cards = []
            state.zones[2].cards = []
            apply()
        }, () => find("forgeHand") && find("forgeHand").visibleCards.length === 1
            && find("forgeHand").visibleCards[0].cardId === "our-hand"
            && duelTable().tableController.controlledTurnSeat < 0 && !find("forgeZone-library").showsPublicFace)
        add("Inspect restored hand and revoked top visibility", () => {
            require(!ws.rulesSession.cardForInspection("controlled-hand").cardId, "Controlled hand remains inspectable")
            require(!ws.rulesSession.cardForInspection("top").cardId, "Old library top remains inspectable")
            capture("control-and-look-ended")
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
