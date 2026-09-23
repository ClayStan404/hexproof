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
    function observed(name, parent) {
        const item = parent || auditWindow.contentItem
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const found = observed(name, child)
            if (found) return found
        }
        return null
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
            scenario: "issue-table-review",
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
        roomId: "ISSUE1", name: "Issue table review", format: "modern",
        deckFormat: "limited", rulesMode: "forge", hostingMode: "server",
        hostConnected: true, maxSeats: 2, phase: "started", matchMode: "bo3",
        role: "player", seatIndex: 0, host: true,
        seats: [{occupied:true, displayName:"Alice", host:true, deckSelected:true, ready:true, loaded:true},
                {occupied:true, displayName:"Bob", host:false, deckSelected:true, ready:true, loaded:true}]
    })
    property var boardFixture: ({})
    function plan() {
        add("Open the production Forge table with 35 cards and colored mana", () => {
            const hand = []
            for (let i = 0; i < 35; ++i)
                hand.push(card("hand-" + i, 0, i % 2 ? "Sol Ring" : "Lightning Bolt", i % 2 ? "C16" : "LEA", i % 2 ? "272" : "161"))
            boardFixture = {
                roomId:"ISSUE1", gameId:"issue-game", turn:3, step:"main1", activeSeat:0, prioritySeat:0,
                players:[{seat:0, name:"Alice", life:20, status:"playing", manaPool:[{name:"U", value:2}, {name:"R", value:1}, {name:"C", value:3}]},
                         {seat:1, name:"Bob", life:18, status:"playing"}],
                zones:[{zone:"hand", ownerSeat:0, count:hand.length, cards:hand},
                       {zone:"hand", ownerSeat:1, count:7, cards:[]},
                       {zone:"library", ownerSeat:0, count:20, cards:[]},
                       {zone:"library", ownerSeat:1, count:45, cards:[]},
                       {zone:"battlefield", ownerSeat:0, count:1, cards:[card("land-0", 0, "Fiery Islet", "MH1", "238")]},
                       {zone:"battlefield", ownerSeat:1, count:1, cards:[card("relic-1", 1, "Sol Ring", "C16", "272")]},
                       {zone:"graveyard", ownerSeat:1, count:1, cards:[card("known-spell", 1, "Lightning Bolt", "LEA", "161")]},
                       {zone:"exile", ownerSeat:1, count:1, cards:[{id:"hidden", ownerSeat:1, controllerSeat:1, visible:false, faceDown:true}]}],
                stack:[]
            }
            require(auditProbe.applyRulesTableFixture(roomFixture, boardFixture), "Cannot apply table fixture")
            auditWindow.showTable()
        }, () => find("forgeHand") && find("forgeHand").visibleCards.length === 35 && find("forgeMana-0-U"))
        add("Inspect colored unused mana and crowded hand", () => {
            require(find("forgeMana-0-U").modelData.amount === 2, "Blue mana missing")
            require(find("forgeMana-0-R").modelData.amount === 1, "Red mana missing")
            require(find("forgeMana-0-C").modelData.amount === 3, "Colorless mana missing")
            require(observed("forgeHandScrollBar").visible, "Hand scrollbar unavailable")
            capture("mana-and-crowded-hand")
        })
        add("Scroll the hand with native wheel input to its final card", () => {
            const view = observed("forgeHandViewport")
            if (view.contentX >= view.contentWidth - view.width - 2) return true
            require(auditProbe.wheel(view, view.width / 4, 75, -960), "Cannot scroll hand")
            return false
        }, () => {
            const view = observed("forgeHandViewport")
            const last = observed("forgeHandCard-hand-34")
            if (!last) return false
            const p = last.mapToItem(view, 0, 0)
            return p.x >= -1 && p.x + last.width <= view.width + 1
        })
        add("Inspect the fully reachable last card", () => capture("last-hand-card"))
        add("Show one blue mana remaining after spending one", () => {
            boardFixture.players[0].manaPool[0].value = 1
            require(auditProbe.applyRulesTableFixture(roomFixture, boardFixture), "Cannot update mana")
        }, () => observed("forgeMana-0-U") && observed("forgeMana-0-U").modelData.amount === 1)
        add("Enter Limited sideboarding with the finished public board", () => {
            boardFixture.gameOver = true
            boardFixture.winnerSeat = 1
            require(auditProbe.applyRulesTableFixture(roomFixture, boardFixture, {
                gameNumber:1, score:[0,1], result:{winnerSeat:1, matchFinished:false},
                sideboard:{deadlineUnixMs:Date.now()+300000,
                    seats:[{seat:0, ready:false, mainboardCount:40, sideboardCount:10}, {seat:1, ready:false, mainboardCount:40, sideboardCount:10}],
                    mainboard:[{name:"Lightning Bolt", count:23, setCode:"LEA", collectorNumber:"161", typeLine:"Instant"},
                               {name:"Island", count:17, setCode:"EOE", collectorNumber:"267", typeLine:"Basic Land", virtualBasic:true}],
                    sideboard:[{name:"Sol Ring", count:10, setCode:"C16", collectorNumber:"272", typeLine:"Artifact"}]}
            }), "Cannot apply sideboard fixture")
        }, () => !!find("sideboardReviewButton"))
        add("Capture sideboard controls", () => capture("limited-sideboard-controls"))
        add("Open public previous-game inspection", () => {
            require(auditProbe.click(find("sideboardReviewButton")), "Cannot open review")
        }, () => !!find("sideboardReviewCards"))
        add("Verify only known public cards appear", () => {
            const review = {reviewCards:ws.rulesSession.publicReviewCards}
            require(review.reviewCards.length === 3, "Private hand or hidden exile leaked into review")
            require(review.reviewCards.some(c => c.name === "Lightning Bolt" && c.zone === "graveyard"), "Known opponent spell missing")
            const grid = find("sideboardReviewCards")
            require(grid && grid.count === 3 && grid.width > grid.parent.width / 2,
                    "Preview artwork collapsed the public-card grid")
            capture("public-board-review")
        })
        add("Return to sideboarding", () => {
            require(auditProbe.click(find("sideboardReviewClose")), "Cannot close review")
        }, () => !find("sideboardReviewClose"))
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
