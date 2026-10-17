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
    property point stackPosition: Qt.point(0, 0)
    property var stackView: null
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
    function finish(error) {
        if (finished) return
        finished = true
        if (error && auditProbe.capture(auditWindow, "failure")) screenshots.push("failure.png")
        const geometry = auditProbe.observe(auditWindow)
        auditProbe.record("window-geometry", geometry)
        auditProbe.record("result", {
            status:error ? "failed" : "passed", scenario:"forge-edh-layout",
            evidence:"native-qt-input", roomAndDeckSetup:"fixture", error:error || "",
            pendingStep:index < steps.length ? steps[index].name : "",
            assertions:assertions, requiredScreenshots:screenshots,
            requestedWindowMode:geometry.requestedWindowMode, windowMode:geometry.windowMode,
            width:geometry.width, height:geometry.height, dpr:geometry.dpr,
            screenGeometry:geometry.screenGeometry
        })
        auditProbe.finish(error ? 1 : 0)
    }
    function fixture(count, format) {
        format = format || "edh"
        const names = ["You · Isamaru", "Meren", "Atraxa", "Krenko"]
        const commanders = ["Isamaru, Hound of Konda", "Meren of Clan Nel Toth", "Atraxa, Praetors' Voice", "Krenko, Mob Boss"]
        function card(id, seat, name, set, number, power, toughness) {
            return {id:id, ownerSeat:seat, controllerSeat:seat, visible:true,
                identity:{name:name, setCode:set, collectorNumber:number}, power:power || "", toughness:toughness || ""}
        }
        const commanderPrintings = [["CHK","19"],["C15","49"],["C16","28"],["M13","138"]]
        const players = [], zones = [], seats = []
        for (let seat = 0; seat < count; ++seat) {
            seats.push({index:seat, occupied:true, displayName:names[seat], host:seat === 0, ready:true, loaded:true})
            players.push({seat:seat, name:names[seat], life:40 - seat * 3, status:"playing",
                manaPool:seat === 0 ? [{name:"W", value:2}] : [],
                commanders:[{name:commanders[seat], casts:seat, tax:seat * 2, zone:"command", objectId:"cmd-" + seat}]})
            const cards = [card("bear-" + seat, seat, "Grizzly Bears", "LEA", "199", "2", "2"),
                card("angel-" + seat, seat, "Serra Angel", "M10", "29", "4", "4"),
                card("sol-" + seat, seat, "Sol Ring", "C16", "272")]
            for (let i = 0; i < 5; ++i) cards.push(card("land-" + seat + "-" + i, seat, "Plains", "M11", "230"))
            const hand = seat === 0 ? [card("hand-0", 0, "Swords to Plowshares", "C16", "78"),
                card("hand-1", 0, "Serra Angel", "M10", "29", "4", "4"),
                card("hand-2", 0, "Sol Ring", "C16", "272"), card("hand-3", 0, "Plains", "M11", "230")] : []
            zones.push({zone:"battlefield", ownerSeat:seat, count:cards.length, cards:cards},
                {zone:"hand", ownerSeat:seat, count:seat === 0 ? 4 : 7, cards:hand},
                {zone:"library", ownerSeat:seat, count:82, cards:[]},
                {zone:"graveyard", ownerSeat:seat, count:1, cards:[card("gy-" + seat, seat, "Grizzly Bears", "LEA", "199", "2", "2")]},
                {zone:"command", ownerSeat:seat, count:1, cards:[card("cmd-" + seat, seat, commanders[seat], commanderPrintings[seat][0], commanderPrintings[seat][1])]})
        }
        while (seats.length < 4) seats.push({occupied:false})
        if (format === "modern") {
            for (const player of players) { player.life = 20; player.commanders = [] }
            for (let i = zones.length - 1; i >= 0; --i)
                if (zones[i].zone === "command") zones.splice(i, 1)
        }
        snapshot = {roomId:"TGT001", gameId:"layout-" + format + "-" + count, turn:6, step:"main1", activeSeat:count - 1,
            prioritySeat:0, players:players, zones:zones, stack:[]}
        const room = {roomId:"TGT001", name:"Forge layout", format:format, deckFormat:format === "edh" ? "commander" : format,
            rulesMode:"forge", hostingMode:"server", hostConnected:true, maxSeats:format === "edh" ? 4 : 2,
            phase:"started", matchMode:"bo1", role:"player", seatIndex:0, host:true, seats:seats}
        require(auditProbe.applyRulesTableFixture(room, snapshot), "Cannot apply Forge fixture")
        return room
    }
    function stackFixture(visible) {
        snapshot.stack = visible ? [{id:"swords", controllerSeat:0, sourceId:"hand-0",
            identity:{name:"Swords to Plowshares", setCode:"C16", collectorNumber:"78"},
            text:"Exile target creature. Its controller gains life equal to its power.",
            targets:[{kind:"card", objectId:"bear-1", label:"Grizzly Bears"}]}] : []
        require(auditProbe.updateRulesTableFixture(snapshot), "Cannot update stack fixture")
    }
    function densityFixture() {
        fixture(4)
        snapshot.gameId = "layout-edh-density"
        // Distinct public counters keep exact permanents in separate piles.
        const counts = [{creatures:8, lands:4, others:3}, {creatures:2, lands:12, others:8},
            {creatures:14, lands:2, others:2}, {creatures:0, lands:8, others:6}]
        for (const zone of snapshot.zones.filter(value => value.zone === "battlefield")) {
            const templates = [zone.cards[0], zone.cards[3], zone.cards[2]]
            zone.cards = []
            for (let category = 0; category < templates.length; ++category) {
                const count = counts[zone.ownerSeat][["creatures", "lands", "others"][category]]
                for (let i = 0; i < count; ++i) {
                    const permanent = JSON.parse(JSON.stringify(templates[category]))
                    permanent.id = "density-" + zone.ownerSeat + "-" + category + "-" + i
                    permanent.counters = [{name:category === 0 ? "+1/+1" : "charge", value:i + 1}]
                    if (category === 0) { permanent.power = String(3 + i); permanent.toughness = String(3 + i) }
                    zone.cards.push(permanent)
                }
            }
            zone.count = zone.cards.length
        }
        publishPrompt("chooseAction", 20, {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
    }
    function publishPrompt(kind, id, extra) {
        const prompt = Object.assign({roomId:"TGT001", gameId:snapshot.gameId,
            promptId:id, pending:true, supported:true, kind:kind,
            options:[], choices:[], cards:[], targets:[], contextCards:[], contextTargets:[],
            combatSources:[], combatTargets:[], damageTargets:[], scryDestinations:[], totalDamage:0}, extra)
        require(auditProbe.updateRulesTableFixture(snapshot, prompt), "Cannot publish " + kind)
    }
    function openingFixture() {
        snapshot.gameId = "layout-edh-opening"
        snapshot.turn = 0; snapshot.step = "untap"; snapshot.activeSeat = -1; snapshot.prioritySeat = 0
        for (const player of snapshot.players) {
            player.life = 40; player.manaPool = []
            for (const commander of player.commanders) { commander.casts = 0; commander.tax = 0 }
        }
        for (const zone of snapshot.zones.filter(value => value.zone !== "command")) {
            zone.cards = []; zone.count = zone.zone === "library" ? 99 : 0
        }
        publishPrompt("chooseBoardTargets", 21, {
            title:"Choose starting player", minSelections:1, maxSelections:1,
            targets:snapshot.players.map(player => ({responseId:"player-" + player.seat,
                kind:"player", seat:player.seat, label:player.name}))
        })
    }
    function plan() {
        add("Dismiss first-launch notices", () => {
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                if (find(name)) { click(name); return false }
            }
            return !!find("mainMenuSettingsButton")
        })
        add("Open two-seat Commander", () => {
            preferences.uiLanguage = "zh"
            preferences.forgeFullControl = true
            fixture(2)
            auditWindow.showTable()
        }, () => find("forgeDuelTable") && find("forgeCard-bear-1"))
        for (const count of [2,3,4]) {
            if (count > 2) add("Load " + count + " seats", () => fixture(count),
                () => find("forgeField-" + (count - 1)) && find("forgeCard-bear-" + (count - 1)))
            add("Wait for " + count + " seat presentation", () => {
                require(auditProbe.hover(find("forgeGameMenu")), "Cannot clear card hover")
            },
                () => Date.now() - driver.stepStarted > 2600)
            add("Capture " + count + " seat layout", () => {
                require(auditProbe.observe(auditWindow).windowMode === "maximized", "Expected maximized window")
                capture("edh-" + count + "-players")
            })
            add("Show " + count + " seat floating stack", () => stackFixture(true),
                () => { driver.stackView = find("forgeStack"); return driver.stackView && find("forgeStackEntry-swords") })
            add("Capture " + count + " seat floating stack", () => {
                require(auditProbe.hover(find("forgeStackDragHandle")), "Cannot clear hover")
                capture("edh-" + count + "-floating-stack")
            })
            add("Drag " + count + " seat stack", () => {
                const stack = driver.stackView
                driver.stackPosition = Qt.point(stack.x, stack.y)
                const destination = find(count === 2 ? "forgeOwnCreatures" : "forgeCreatures-0")
                require(auditProbe.drag(find("forgeStackDragHandle"), destination), "Cannot drag stack")
            }, () => Math.abs(driver.stackView.x - driver.stackPosition.x) > 100)
            add("Collapse " + count + " seat stack", () => click("forgeStackToggle"), () => driver.stackView.collapsed)
            if (count === 4) add("Capture collapsed stack", () => capture("edh-4-collapsed-stack"))
            add("Restore " + count + " seat stack", () => click("forgeStackToggle"), () => !driver.stackView.collapsed)
            add("Reset " + count + " seat stack position", () => {
                require(auditProbe.rightClick(find("forgeStackDragHandle")), "Cannot reset stack position")
            }, () => Math.abs(driver.stackView.x - driver.stackPosition.x) < 1)
            add("Clear " + count + " seat stack", () => stackFixture(false), () => !driver.stackView.visible)
        }
        add("Select targets across opponents", () => {
            require(auditProbe.updateRulesTableFixture(snapshot, {
                roomId:"TGT001", gameId:snapshot.gameId, promptId:10, pending:true, supported:true,
                kind:"chooseBoardTargets", title:"Choose targets", minSelections:2, maxSelections:2,
                targets:[{responseId:"player-2", kind:"player", seat:2, label:"Atraxa"},
                    {responseId:"card-3", kind:"card", objectId:"bear-3", name:"Grizzly Bears", label:"Grizzly Bears"}],
                options:[], choices:[], cards:[], contextCards:[], contextTargets:[], combatSources:[],
                combatTargets:[], damageTargets:[], scryDestinations:[], totalDamage:0
            }), "Cannot publish multiplayer target prompt")
        }, () => find("forgeCard-bear-3").actionable)
        add("Select player two", () => click("rulesPlayerTarget2"), () => interaction().selectedCount === 1)
        add("Select player three's permanent", () => click("forgeCard-bear-3"), () => interaction().selectedCount === 2)
        add("Capture target selection", () => capture("edh-four-targets"))
        add("Open another player's command zone", () => click("forgeSeatZone-2-command"), () => !!find("forgeCloseZonePopup"))
        add("Capture command zone", () => capture("edh-command-zone"))
        add("Close command zone", () => click("forgeCloseZonePopup"), () => !find("forgeCloseZonePopup"))
        add("Load four different crowded fields", () => densityFixture(),
            () => find("forgeCard-density-0-0-0") && find("forgeCard-density-3-1-0"))
        add("Wait for crowded presentation", () => {
            require(auditProbe.hover(find("forgeGameMenu")), "Cannot clear card hover")
        }, () => Date.now() - driver.stepStarted > 2600)
        add("Capture four crowded fields", () => capture("edh-4-density"))
        add("Expand hand over compact player controls", () => {
            require(auditProbe.hover(find("forgeHandViewport")), "Cannot hover hand")
        }, () => Date.now() - driver.stepStarted > 500)
        add("Open own command zone beside expanded hand", () => click("forgeSeatZone-0-command"),
            () => !!find("forgeCloseZonePopup"))
        add("Close own command zone", () => click("forgeCloseZonePopup"), () => !find("forgeCloseZonePopup"))
        add("Apply astral background and small controls", () => {
            preferences.tableBackground = "astral"; preferences.interfaceScale = 0.8
            require(auditProbe.hover(find("forgeGameMenu")), "Cannot clear card hover")
        }, () => Date.now() - driver.stepStarted > 1000)
        add("Capture crowded fields at eighty percent", () => capture("edh-4-density-80-astral"))
        add("Load empty opening fields", () => openingFixture(),
            () => find("forgeDuelTable") && !find("forgeDuelTable").turnReady)
        add("Capture compact opening", () => capture("edh-4-opening-80-astral"))
        add("Restore default presentation", () => {
            preferences.tableBackground = "default"; preferences.interfaceScale = 1
        })
        add("Open regular Forge 1v1", () => fixture(2, "modern"), () => find("forgeOpponentCreatures"))
        add("Wait for regular Forge 1v1", () => {}, () => Date.now() - driver.stepStarted > 2600)
        add("Capture regular Forge 1v1", () => capture("forge-1v1-battlefield"))
        add("Show regular Forge floating stack", () => stackFixture(true), () => find("forgeStack"))
        add("Capture regular Forge floating stack", () => capture("forge-1v1-floating-stack"))
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
