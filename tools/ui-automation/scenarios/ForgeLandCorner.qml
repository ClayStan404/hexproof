// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

// Deterministic maximized layout fixture. Room and snapshot setup are
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
    function token(id, seat, name, setCode, number) {
        const row = card(id, seat, name, setCode, number)
        row.identity.token = true
        row.power = "1"
        row.toughness = "1"
        return row
    }
    function duelTable() {
        return find("forgeDuelTable")
    }
    function mapPoint(item, x, y) {
        return item.mapToItem(duelTable(), x, y)
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
            scenario: "forge-land-corner",
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

    function plan() {
        add("Dismiss first-launch notices", () => {
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                const item = find(name)
                if (item) {
                    require(auditProbe.click(item), "Cannot dismiss " + name)
                    return false
                }
            }
            return !!find("mainMenuSettingsButton")
        })
        add("Open the production Forge table", () => {
            preferences.tableBackground = "astral"
            require(auditProbe.applyRulesTableFixture({
                roomId: "LAND01", name: "Land corner review", format: "duel",
                deckFormat: "commander", rulesMode: "forge", hostingMode: "server",
                hostConnected: true, maxSeats: 2, phase: "started", matchMode: "bo1",
                role: "player", seatIndex: 0, host: true,
                seats: [
                    {occupied: true, displayName: "Alice", host: true,
                     deckSelected: true, ready: true, loaded: true},
                    {occupied: true, displayName: "Bob", host: false,
                     deckSelected: true, ready: true, loaded: true}
                ]
            }, {
                roomId: "LAND01", gameId: "land-corner", turn: 3, step: "main1",
                activeSeat: 0, prioritySeat: 0,
                players: [
                    {seat: 0, name: "Alice", life: 20, status: "playing",
                     commanders: [{name: "Engineered Explosives", casts: 1, tax: 2,
                                   zone: "battlefield", objectId: "relic"}]},
                    {seat: 1, name: "Bob", life: 20, status: "playing"}
                ],
                zones: [
                    {zone: "hand", ownerSeat: 0, count: 4, cards: [
                        card("hand-0", 0, "Lightning Bolt", "LEA", "161"),
                        card("hand-1", 0, "Lightning Bolt", "LEA", "161"),
                        card("hand-2", 0, "Sol Ring", "C16", "272"),
                        card("hand-3", 0, "Sol Ring", "C16", "272")
                    ]},
                    {zone: "hand", ownerSeat: 1, count: 5, cards: []},
                    {zone: "library", ownerSeat: 0, count: 50, cards: []},
                    {zone: "library", ownerSeat: 1, count: 49, cards: []},
                    {zone: "graveyard", ownerSeat: 0, count: 0, cards: []},
                    {zone: "exile", ownerSeat: 0, count: 0, cards: []},
                    {zone: "command", ownerSeat: 0, count: 0, cards: []},
                    {zone: "battlefield", ownerSeat: 0, count: 5, cards: [
                        card("land-1", 0, "Fiery Islet", "MH1", "238"),
                        card("land-2", 0, "Fiery Islet", "MH1", "238"),
                        card("relic", 0, "Engineered Explosives", "5DN", "118"),
                        token("token-1", 0, "Goblin Token", "TDM", "1"),
                        token("token-2", 0, "Goblin Token", "TDM", "1")
                    ]},
                    {zone: "battlefield", ownerSeat: 1, count: 0, cards: []}
                ],
                stack: []
            }), "Cannot apply the Forge table fixture")
            auditWindow.showTable()
        }, () => {
            const board = duelTable()
            const lands = find("forgeOwnLands")
            const creatures = find("forgeOwnCreatures")
            return board && lands && lands.visibleCards && lands.visibleCards.length === 2
                && lands.stackCount === 1
                && creatures && creatures.visibleCards && creatures.visibleCards.length === 2
                && creatures.stackCount === 1
                && find("forgeCard-land-2") && find("forgeCard-relic")
                && find("forgeCard-token-2")
        })
        add("Capture the maximized land corner", () => {
            const geometry = auditProbe.observe(auditWindow)
            require(geometry.windowMode === "maximized", "Window is " + geometry.windowMode)
            require(geometry.width >= 1600 && geometry.height >= 900,
                    "Maximized window is " + geometry.width + "x" + geometry.height)
            capture("land-corner")
            require(auditProbe.hover(find("forgeCard-land-2")), "Cannot hover the stacked land")
        })
        add("Assert compact lands sit above the hand-row piles", () => {
            const table = duelTable()
            const land2 = find("forgeCard-land-2")
            const relic = find("forgeCard-relic")
            const lands = find("forgeOwnLands")
            const creatures = find("forgeOwnCreatures")
            const piles = find("forgeOwnZoneStrip")
            const library = find("forgeZone-library")
            const hand = find("forgeHand")
            const unit = table.unit
            const buried = lands.visibleCards[0]
            const front = lands.visibleCards[1]
            require(!land2.fullFace, "Lands must use cropped faces")
            require(front.width <= 112 * unit, "Land width grew to " + front.width)
            require(buried.width <= 112 * unit, "Buried land width grew to " + buried.width)
            require(relic.width <= 120 * unit, "Other permanent width grew to " + relic.width)
            require(library.width >= 96 * unit, "Zone piles stayed too small: " + library.width)
            require(lands.stackCount === 1, "Matching lands must share one pile")
            require(creatures.stackCount === 1 && creatures.visibleCards.length === 2,
                    "Matching tokens must share one pile")
            require(front.stackSize === 2 && front.stackFront, "Stacked land is missing its count")
            const landPoint = mapPoint(land2, 0, 0)
            const pilePoint = mapPoint(piles, 0, 0)
            require(piles.y >= hand.y - 4 * unit, "Own piles are not in the hand row")
            require(hand.x >= piles.x + piles.width - 4 * unit, "Hand does not start after the piles")
            require(Math.abs(buried.x - front.x) <= 12 * unit, "Matching lands are not stacked")
            require(Math.abs(buried.y - front.y) <= 12 * unit, "Matching lands are not stacked vertically")
            require(landPoint.x <= lands.x + 28 * unit, "Lands are not at the left of the battlefield")
            require(landPoint.y + land2.height <= pilePoint.y + 8 * unit,
                    "Lands still occupy the hand-row piles")
            auditProbe.record("land-geometry", {
                landWidth: land2.width, landHeight: land2.height, landX: landPoint.x, landY: landPoint.y,
                relicWidth: relic.width, pileX: pilePoint.x, pileY: pilePoint.y,
                pileWidth: library.width, pileHeight: library.height, unit: unit,
                landStackCount: lands.stackCount, tokenStackCount: creatures.stackCount,
                stackOffsetX: front.x - buried.x, stackOffsetY: front.y - buried.y,
                tableWidth: table.width, tableHeight: table.height
            })
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
