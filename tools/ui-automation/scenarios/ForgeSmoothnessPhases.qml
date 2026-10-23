// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

// Forge smoothness Phases 2-4 on the native table. Snapshots and prompts are
// fixtures; clicks, keys, hovers and captures use the native window. Without a
// hub no answer is sent, so queued payments are covered by a live game.
Item {
    id: driver
    property var steps: []
    property var assertions: []
    property var screenshots: []
    property var snapshot: ({})
    property var multiplayerGeometry: ({})
    property bool motion: false
    property int flightsSeen: 0
    property int index: 0
    property bool acted: false
    property bool dispatching: false
    property bool finished: false
    property double stepStarted: Date.now()

    function require(value, message) {
        if (!value) throw new Error(message + (auditProbe.lastError ? "; " + auditProbe.lastError : ""))
    }
    // find() returns only input targets; lookup() reads state from any item.
    function find(name) { return auditProbe.find(auditWindow, name) }
    function lookup(name) {
        const walk = item => {
            if (item.objectName === name && item.visible) return item
            for (const child of item.children) {
                const hit = walk(child)
                if (hit) return hit
            }
            return null
        }
        return walk(auditWindow.contentItem)
    }
    function table() { return lookup("forgeDuelTable") }
    function add(name, action, check) { steps.push({name, action, check:check || (() => true)}) }
    function click(name) { require(auditProbe.click(find(name)), "Cannot click " + name) }
    function clearHover() { require(auditProbe.hover(find("forgeGameMenu")), "Cannot clear card hover") }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }
    function waited(ms) { return Date.now() - driver.stepStarted > ms }
    function flights() {
        const host = lookup("forgeMotionFlights")
        return host ? host.children.length : 0
    }
    function finish(error) {
        if (finished) return
        finished = true
        if (error && auditProbe.capture(auditWindow, "failure")) screenshots.push("failure.png")
        const geometry = auditProbe.observe(auditWindow)
        auditProbe.record("window-geometry", geometry)
        auditProbe.record("result", {
            status:error ? "failed" : "passed", scenario:"forge-smoothness-phases",
            evidence:"native-qt-input", roomAndDeckSetup:"fixture", error:error || "",
            motion:motion, flightsSeen:flightsSeen,
            pendingStep:index < steps.length ? steps[index].name : "",
            assertions:assertions, requiredScreenshots:screenshots,
            requestedWindowMode:geometry.requestedWindowMode, windowMode:geometry.windowMode,
            width:geometry.width, height:geometry.height, dpr:geometry.dpr,
            screenGeometry:geometry.screenGeometry
        })
        auditProbe.finish(error ? 1 : 0)
    }

    function card(id, seat, name, set, number, extra) {
        return Object.assign({id:id, ownerSeat:seat, controllerSeat:seat, visible:true,
            identity:{name:name, setCode:set, collectorNumber:number}}, extra || {})
    }
    function bear(id, seat, extra) {
        return card(id, seat, "Grizzly Bears", "LEA", "199", Object.assign({power:"2", toughness:"2"}, extra || {}))
    }
    function plains(id, seat, extra) { return card(id, seat, "Plains", "M11", "230", extra) }
    function zone(name, seat, cards, count) {
        return {zone:name, ownerSeat:seat, count:count === undefined ? cards.length : count, cards:cards}
    }
    function landFront() {
        const front = lookup("forgeOwnLands").visibleCards.find(slot => slot.stackFront && slot.stackSize > 1)
        require(front, "No land pile front")
        return front.cardId
    }
    function battlefield(seat) { return snapshot.zones.find(z => z.zone === "battlefield" && z.ownerSeat === seat) }
    function hand(seat) { return snapshot.zones.find(z => z.zone === "hand" && z.ownerSeat === seat) }
    function duel(gameId) {
        const own = [plains("land-a", 0, {tapped:true}), plains("land-b", 0), plains("land-c", 0),
            plains("land-d", 0, {enteredThisTurn:true}), bear("bear-a", 0), bear("bear-b", 0, {tapped:true}),
            bear("bear-c", 0), card("angel", 0, "Serra Angel", "M10", "29", {power:"4", toughness:"4"}),
            card("sol", 0, "Sol Ring", "C16", "272")]
        const theirs = [plains("their-land-0", 1), plains("their-land-1", 1), plains("their-land-2", 1),
            bear("their-bear-0", 1), bear("their-bear-1", 1)]
        snapshot = {roomId:"SMOOTH", gameId:gameId, turn:5, step:"main1", activeSeat:0, prioritySeat:0,
            players:[{seat:0, name:"You", life:20, status:"playing", manaPool:[]},
                {seat:1, name:"Forge AI", life:18, status:"playing", manaPool:[]}],
            zones:[zone("battlefield", 0, own),
                zone("hand", 0, [card("hand-0", 0, "Swords to Plowshares", "C16", "78"),
                    card("hand-1", 0, "Serra Angel", "M10", "29", {power:"4", toughness:"4"}),
                    plains("hand-2", 0)]),
                zone("library", 0, [], 40), zone("graveyard", 0, [bear("gy-0", 0)]),
                zone("battlefield", 1, theirs), zone("hand", 1, [], 5), zone("library", 1, [], 41),
                zone("graveyard", 1, [])],
            stack:[]}
        const room = {roomId:"SMOOTH", name:"Forge smoothness", format:"modern", deckFormat:"modern",
            rulesMode:"forge", hostingMode:"server", hostConnected:true, maxSeats:2, phase:"started",
            matchMode:"bo1", role:"player", seatIndex:0, host:true,
            seats:[{index:0, occupied:true, displayName:"You", host:true, ready:true, loaded:true},
                {index:1, occupied:true, displayName:"Forge AI", ready:true, loaded:true}]}
        require(auditProbe.applyRulesTableFixture(room, snapshot), "Cannot apply duel fixture")
    }
    function multiplayer(count) {
        const names = ["You", "Meren", "Atraxa", "Krenko"], seats = [], players = [], zones = []
        for (let seat = 0; seat < count; ++seat) {
            seats.push({index:seat, occupied:true, displayName:names[seat], host:seat === 0, ready:true, loaded:true})
            players.push({seat:seat, name:names[seat], life:40 - seat * 3, status:"playing", manaPool:[], commanders:[]})
            const field = [bear("mp-bear-" + seat, seat), card("mp-angel-" + seat, seat, "Serra Angel", "M10", "29",
                {power:"4", toughness:"4"})]
            for (let i = 0; i < 5; ++i) field.push(plains("mp-land-" + seat + "-" + i, seat, {tapped:i < 2}))
            zones.push(zone("battlefield", seat, field),
                zone("hand", seat, seat === 0 ? [card("mp-hand-0", 0, "Swords to Plowshares", "C16", "78")] : [],
                    seat === 0 ? 1 : 6),
                zone("library", seat, [], 80), zone("graveyard", seat, []))
        }
        while (seats.length < 4) seats.push({occupied:false})
        snapshot = {roomId:"SMOOTH", gameId:"smooth-edh-" + count, turn:6, step:"main1", activeSeat:0,
            prioritySeat:0, players:players, zones:zones, stack:[]}
        const room = {roomId:"SMOOTH", name:"Forge smoothness", format:"edh", deckFormat:"commander",
            rulesMode:"forge", hostingMode:"server", hostConnected:true, maxSeats:4, phase:"started",
            matchMode:"bo1", role:"player", seatIndex:0, host:true, seats:seats}
        require(auditProbe.applyRulesTableFixture(room, snapshot), "Cannot apply multiplayer fixture")
    }
    function update(prompt) {
        require(auditProbe.updateRulesTableFixture(snapshot, prompt || {}), "Cannot update fixture")
    }
    function publish(kind, id, extra) {
        update(Object.assign({roomId:"SMOOTH", gameId:snapshot.gameId, promptId:id, pending:true,
            supported:true, kind:kind, options:[], choices:[], cards:[], targets:[], contextCards:[],
            contextTargets:[], combatSources:[], combatTargets:[], damageTargets:[], scryDestinations:[],
            totalDamage:0}, extra))
    }
    function priority(id) {
        publish("chooseAction", id, {options:[{responseId:"$pass", kind:"pass", label:"Pass priority"},
            {responseId:"action:0", kind:"cast", cardId:"hand-0", label:"Swords to Plowshares — cast spell"},
            {responseId:"action:1", kind:"playLand", cardId:"hand-2", label:"Plains — play land"}]})
    }
    function surveil(id) {
        publish("chooseBoolean", id, {title:"Confirm decision",
            detail:"Put Troll of Khazad-dûm on the top of library or graveyard?",
            contextCards:[{id:"context-card:0", name:"Troll of Khazad-dûm"}],
            contextText:"Troll of Khazad-dûm can't be blocked except by three or more creatures.\nSwampcycling {1}",
            minChoiceTotal:1, maxChoiceTotal:1,
            choices:[{responseId:"choice:0", label:"Graveyard", weight:1, canRepeat:false},
                {responseId:"choice:1", label:"Library", weight:1, canRepeat:false}]})
    }
    function payment(id) {
        publish("payManaCost", id, {title:"Pay Mana Cost: {W}", paymentId:"pay-swords-1",
            options:[{responseId:"action:0", kind:"activateAbility", cardId:"land-b", label:"Plains"},
                {responseId:"action:1", kind:"activateAbility", cardId:"land-c", label:"Plains"},
                {responseId:"action:2", kind:"activateAbility", cardId:"land-d", label:"Plains"},
                {responseId:"action:3", kind:"activateAbility", cardId:"sol", label:"Sol Ring"},
                {responseId:"undo-a", kind:"undoMana", cardId:"land-a", label:"Undo"},
                {responseId:"$auto-pay", kind:"pay", label:"Auto-pay"},
                {responseId:"$cancel", kind:"cancel", label:"Cancel"}]})
    }

    function blockers(id, multiple, all) {
        const targets = [{responseId:"attacker-1", kind:"attacker", objectId:"their-bear-1",
            label:"Grizzly Bears", minAssignments:0, maxAssignments:2}]
        if (multiple) targets.push({responseId:"attacker-0", kind:"attacker", objectId:"their-bear-0",
            label:"Other bear", minAssignments:0, maxAssignments:2})
        const sources = [{responseId:"block-angel", objectId:"angel", label:"Serra Angel", name:"Serra Angel",
            validTargetIds:targets.map(target => target.responseId), maxAssignments:1}]
        if (all) sources.push({responseId:"block-bear", objectId:"bear-c", label:"Grizzly Bears", name:"Grizzly Bears",
            validTargetIds:["attacker-1"], maxAssignments:1})
        publish("chooseBlockers", id, {combatSources:sources, combatTargets:targets})
    }
    function combat() { return table().tableController.combatInteraction }

    function plan() {
        add("Dismiss first-launch notices", () => {
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                if (find(name)) { click(name); return false }
            }
            return !!find("mainMenuSettingsButton")
        })
        add("Open two-seat Forge table", () => {
            preferences.uiLanguage = "zh"
            preferences.forgeFullControl = true
            driver.motion = auditProbe.environment("HEXPROOF_MOTION") !== "0"
            duel("smooth-duel")
            auditWindow.showTable()
        }, () => table() && find("forgeCard-angel") && lookup("forgeOwnLands").stackCount === 2)
        add("Offer priority", () => { priority(1); clearHover() }, () => waited(2200))
        add("Capture piles and badges", () => {
            require(auditProbe.observe(auditWindow).windowMode === "maximized", "Expected maximized window")
            const front = landFront()
            const label = lookup("forgeCardStackCountLabel-" + front)
            require(label && label.text.indexOf("3") >= 0, "Ready land pile badge must count three copies: " + (label ? label.text : ""))
            const ready = lookup("forgeCard-" + front), spent = lookup("forgeCard-land-a")
            require(ready.card.stackSize === 3 && spent.card.stackSize === 1, "Tapped copies have a separate pile")
            require(spent.card.stackIndex === ready.card.stackIndex + 1, "Tapped pile follows the ready pile")
            require(spent.rotation === 0 && lookup("forgeCardTappedMark-land-a"), "Spent land stays upright with a tap mark")
            auditProbe.record("land-badge", {front:front, text:label.text, contentWidth:label.contentWidth,
                badgeWidth:lookup("forgeCardStackCount-" + front).width})
            capture("p2-piles-badges")
        })
        add("Fan the land pile from its badge", () => click("forgeCardStackCount-" + landFront()),
            () => lookup("forgeOwnLands").fannedStack >= 0)
        add("Capture fanned pile", () => { clearHover(); capture("p2-pile-fan") })
        add("Fold the pile with Escape", () => {
            const focus = auditWindow.activeFocusItem
            auditProbe.record("escape-focus", {objectName:focus ? focus.objectName : "",
                type:focus ? String(focus) : "none"})
            require(auditProbe.key(Qt.Key_Escape), "Cannot press Escape")
        }, () => lookup("forgeOwnLands").fannedStack < 0)
        add("Open a payment with a spent-pile undo", () => { payment(2); clearHover() },
            () => lookup("forgeCard-land-a") && waited(900))
        add("Capture payment and spent-pile undo", () => capture("p3-spent-pile-undo"))
        add("Offer a one-target blocker", () => { blockers(30, false, false); clearHover() },
            () => find("forgeCard-angel") && waited(500))
        add("Assign the blocker in one click", () => click("forgeCard-angel"),
            () => combat().assignments["block-angel"] === "attacker-1" && combat().selectedSource === "")
        add("Capture the blocking shortcut", () => { clearHover(); capture("p4-blocking-shortcut") })
        add("Undo the blocker in one click", () => click("forgeCard-angel"),
            () => !combat().assignments["block-angel"])
        add("Offer both attacking creatures", () => blockers(31, true, false), () => waited(500))
        add("Fan the attacking pile", () => {
            if (lookup("forgeOpponentCreatures").fannedStack < 0)
                click("forgeCardStackCount-their-bear-1")
        }, () => lookup("forgeOpponentCreatures").fannedStack >= 0)
        add("Choose the attacker first", () => click("forgeCard-their-bear-1"),
            () => combat().pendingAttacker === "their-bear-1")
        add("Choose the blocking creature", () => click("forgeCard-angel"),
            () => combat().assignments["block-angel"] === "attacker-1" && combat().pendingAttacker === "")
        add("Offer the all-blockers shortcut", () => blockers(32, false, true),
            () => !!find("rulesBlockWithAll") && waited(500))
        add("Block with all eligible creatures", () => click("rulesBlockWithAll"),
            () => combat().assignments["block-angel"] === "attacker-1"
                && combat().assignments["block-bear"] === "attacker-1")
        add("Capture all blockers", () => { clearHover(); capture("p4-block-with-all") })
        add("Open a covering decision", () => { clearHover(); surveil(3) },
            () => !!find("forgeDecisionCollapse"))
        add("Capture covering decision", () => capture("p4-covering-decision"))
        add("Hide the choice", () => click("forgeDecisionCollapse"),
            () => lookup("rulesDecisionDock").collapsed)
        add("Capture hidden choice", () => { clearHover(); capture("p4-hidden-choice") })
        add("Show the choice again", () => click("forgeDecisionCollapse"),
            () => !lookup("rulesDecisionDock").collapsed)
        add("Return to priority", () => priority(4), () => !lookup("forgeDecisionCollapse"))
        add("Opponent casts from hand", () => {
            hand(1).count = 4
            snapshot.prioritySeat = 1
            snapshot.stack = [{id:"their-bolt", controllerSeat:1, ownerSeat:1,
                identity:{name:"Lightning Bolt", setCode:"M11", collectorNumber:"149"},
                text:"Lightning Bolt deals 3 damage to any target.",
                targets:[{kind:"card", objectId:"bear-a", label:"Grizzly Bears"}]}]
            update()
        }, () => {
            driver.flightsSeen = Math.max(driver.flightsSeen, driver.flights())
            return lookup("forgeStackEntry-their-bolt") && (!driver.motion || driver.flightsSeen > 0)
        })
        add("Capture opponent marker", () => capture(driver.motion ? "p4-opponent-marker" : "p4-opponent-cast"))
        add("Spell resolves and the bear dies", () => {
            snapshot.stack = []
            snapshot.prioritySeat = 0
            const field = battlefield(0)
            field.cards = field.cards.filter(c => c.id !== "bear-a"); field.count = field.cards.length
            const yard = snapshot.zones.find(z => z.zone === "graveyard" && z.ownerSeat === 0)
            yard.cards.push(bear("bear-a", 0)); yard.count = yard.cards.length
            const theirs = snapshot.zones.find(z => z.zone === "graveyard" && z.ownerSeat === 1)
            theirs.cards.push(card("their-bolt", 1, "Lightning Bolt", "M11", "149")); theirs.count = 1
            update()
        }, () => {
            driver.flightsSeen = Math.max(driver.flightsSeen, driver.flights())
            return !lookup("forgeCard-bear-a") && !lookup("forgeStackEntry-their-bolt")
        })
        add("Capture staged resolution", () => capture("p4-staged-resolution"))
        add("Markers land", () => {}, () => driver.flights() === 0 && !lookup("forgeMotionOverlay").staging)
        add("Play a land", () => {
            const own = hand(0)
            own.cards = own.cards.filter(c => c.id !== "hand-2"); own.count = own.cards.length
            const field = battlefield(0)
            field.cards.push(plains("hand-2", 0, {enteredThisTurn:true})); field.count = field.cards.length
            update()
        }, () => lookup("forgeCard-hand-2") && driver.flights() === 0 && waited(600))
        add("Capture after own land", () => { clearHover(); capture("p4-own-land") })
        for (const count of [3, 4]) {
            add("Load " + count + " seats", () => multiplayer(count),
                () => lookup("forgeField-" + (count - 1)) && lookup("forgeCard-mp-bear-" + (count - 1)) && waited(700))
            add("Open a decision for " + count + " seats", () => {
                clearHover()
                const lane = lookup("forgeCreatures-" + (count - 1))
                driver.multiplayerGeometry = {x:lane.x, y:lane.y, width:lane.width, height:lane.height}
                surveil(10 + count)
            },
                () => lookup("rulesDecisionDock") && lookup("rulesDecisionDock").showsBody && waited(1500))
            add("Capture " + count + " seat dock", () => {
                require(lookup("forgeDecisionCollapse"), "A covering multiplayer decision can be hidden")
                const lane = lookup("forgeCreatures-" + (count - 1)), before = driver.multiplayerGeometry
                require(lane.x === before.x && lane.y === before.y && lane.width === before.width
                    && lane.height === before.height, "Multiplayer decisions keep battlefield geometry")
                auditProbe.record("multiplayer-" + count + "-geometry", before)
                capture("p4-" + count + "p-dock")
            })
            add("Hide the choice for " + count + " seats", () => click("forgeDecisionCollapse"),
                () => lookup("rulesDecisionDock").collapsed)
            add("Capture hidden choice for " + count + " seats", () => { clearHover(); capture("p4-" + count + "p-hidden") })
            add("Show the choice for " + count + " seats", () => click("forgeDecisionCollapse"),
                () => !lookup("rulesDecisionDock").collapsed)
        }
    }
    Component.onCompleted: plan()
    Timer {
        interval:50; repeat:true; running:!driver.finished
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
