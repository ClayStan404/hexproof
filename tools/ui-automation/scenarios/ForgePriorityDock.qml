// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

// Priority/zone-action occlusion regression in the production native client.
// Room, board and prompt setup are fixtures; input and geometry are native.
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
            scenario: "forge-priority-dock",
            evidence: "native-qt-input",
            roomAndDeckSetup: "fixture",
            interfaceScale: preferences.interfaceScale, uiLanguage: preferences.uiLanguage,
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
        roomId:"TURN01", name:"Priority dock review", format:"modern", deckFormat:"custom",
        rulesMode:"forge", hostingMode:"server", hostConnected:true, maxSeats:2,
        phase:"started", matchMode:"bo1", role:"player", seatIndex:0, host:true,
        seats:[{occupied:true, displayName:"Alice", host:true, ready:true, loaded:true},
               {occupied:true, displayName:"Bob", host:false, ready:true, loaded:true}]
    })
    property var state: ({})
    function apply() {
        require(auditProbe.applyRulesTableFixture(roomFixture, state), "Cannot apply table fixture")
    }
    property var initialFace: null
    property var initialGeometry: ({})
    property int promptSerial: 10
    function faceBounds() {
        const face = initialFace
        return face.mapToItem(duelTable(), 0, 0, face.width, face.height)
    }
    function overlaps(a, b) {
        return a.x < b.x + b.width && a.x + a.width > b.x
            && a.y < b.y + b.height && a.y + a.height > b.y
    }
    function priorityPrompt() {
        return {roomId:"TURN01",gameId:"turn-access",promptId:promptSerial,pending:true,
            supported:true,kind:"chooseAction",title:"Choose",detail:"",choices:[],cards:[],targets:[],
            contextCards:[],contextTargets:[],combatSources:[],combatTargets:[],damageTargets:[],
            scryDestinations:[],totalDamage:0,options:[
                {responseId:"$pass",kind:"pass",label:"Pass"},
                {responseId:"relic-action",kind:"activateAbility",cardId:"relic",label:"First relic ability"},
                {responseId:"relic-other",kind:"activateAbility",cardId:"relic",label:"Second relic ability"},
                {responseId:"yard-a",kind:"cast",cardId:"yard-1",label:"Cast from graveyard"},
                {responseId:"yard-b",kind:"cast",cardId:"yard-2",label:"Cast from graveyard"}]}
    }
    function plan() {
        add("Dismiss first-launch notices", () => {
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                const item = find(name)
                if (item) { require(auditProbe.click(item), "Cannot dismiss notice"); return false }
            }
            return !!find("mainMenuSettingsButton")
        })
        add("Prepare right-rear artifact with two graveyard actions", () => {
            preferences.uiLanguage = "zh"
            preferences.interfaceScale = 1.2
            preferences.tableBackground = "astral"
            const variant = auditProbe.environment("HEXPROOF_AUDIT_VARIANT")
            const count = variant === "four" ? 4 : variant === "three" ? 3 : 2
            roomFixture.maxSeats=count
            roomFixture.format=count>2 ? "edh" : "modern"
            roomFixture.seats=Array.from({length:count},(_,seat)=>({occupied:true,displayName:"Seat "+seat,host:seat===0,ready:true,loaded:true}))
            state = {roomId:"TURN01",gameId:"turn-access",turn:9,step:"main1",activeSeat:0,prioritySeat:0,
                players:[{seat:0,name:"Alice",life:20},{seat:1,name:"Bob",life:20}],
                zones:[{zone:"hand",ownerSeat:0,count:0,cards:[]},
                    {zone:"hand",ownerSeat:1,count:0,cards:[]},
                    {zone:"library",ownerSeat:0,count:40,cards:[]},
                    {zone:"library",ownerSeat:1,count:40,cards:[]},
                    {zone:"battlefield",ownerSeat:0,count:1,cards:[card("relic",0,"Engineered Explosives","5DN","118")]},
                    {zone:"battlefield",ownerSeat:1,count:0,cards:[]},
                    {zone:"graveyard",ownerSeat:0,count:2,cards:[card("yard-1",0,"Grizzly Bears","10E","268"),card("yard-2",0,"Grizzly Bears","10E","268")]}],stack:[]}
            if (count>2) {
                state.players=Array.from({length:count},(_,seat)=>({seat:seat,name:"Seat "+seat,life:40}))
                if (count===4) {
                    state.zones[4].cards=[];state.zones[4].count=0
                    state.zones[5].cards=[card("relic",1,"Engineered Explosives","5DN","118")];state.zones[5].count=1
                }
                for (let seat=2;seat<count;++seat)
                    state.zones.push({zone:"battlefield",ownerSeat:seat,count:0,cards:[]})
            }
            apply(); auditWindow.showTable()
        }, () => find("forgeCard-relic") !== null)
        add("Publish ordinary priority with the real zone-action list", () => {
            initialFace = find("forgeCard-relic")
            require(initialFace, "Missing artifact before priority")
            tableSurface = duelTable()
            require(auditProbe.updateRulesTableFixture(state, priorityPrompt()), "Cannot publish priority")
        }, () => find("rulesZoneActions") && find("rulesZoneActions").count === 2)
        add("Verify Hide choice above the compact reservation", () => {
            const dock = duelTable().decisionDock, rect = faceBounds()
            initialGeometry = {x:rect.x,y:rect.y,width:rect.width,height:rect.height}
            require(overlaps(rect,dock), "The fixture must exercise actual occlusion")
            require(duelTable().decisionCollapsible, "Hide choice is missing during ordinary priority")
            require(!dock.showsBody && !dock.expanded, "This must be ordinary priority")
            capture("priority-covered-with-hide")
            require(auditProbe.click(find("forgeDecisionCollapse")), "Cannot hide zone actions")
        }, () => duelTable().decisionDock.collapsed && !overlaps(faceBounds(),duelTable().decisionDock))
        add("Click the exposed artifact without submitting an action", () => {
            const dock=duelTable().decisionDock, rect=faceBounds()
            require(JSON.stringify(initialGeometry)===JSON.stringify({x:rect.x,y:rect.y,width:rect.width,height:rect.height}), "Hiding moved the permanent")
            require(find("forgeTurnIndicator"), "Turn information is inaccessible")
            capture("priority-hidden-card-exposed")
            require(auditProbe.click(find("forgeCard-relic")), "Cannot click exposed artifact")
        }, () => duelTable().decisionDock.actionPicker.opened)
        add("Close the action picker and restore the same priority", () => {
            require(auditProbe.key(Qt.Key_Escape), "Cannot close action picker")
            require(!duelTable().decisionDock.actionPicker.opened, "Action picker remains open")
            require(auditProbe.updateRulesTableFixture(state,priorityPrompt()), "Cannot restore priority")
        }, () => find("rulesZoneActions") && find("rulesZoneActions").count===2)
        add("Exact-card reveal also uncovers priority zone actions", () => {
            require(duelTable().reveal("relic"), "Cannot reveal exact artifact")
        }, () => duelTable().decisionDock.collapsed && !overlaps(faceBounds(),duelTable().decisionDock))
        add("Same decision republication keeps actions hidden", () => {
            require(auditProbe.updateRulesTableFixture(state,priorityPrompt()), "Cannot republish priority")
            require(duelTable().decisionDock.collapsed, "Same prompt reopened hidden choice")
            require(auditProbe.click(find("forgeDecisionCollapse")), "Cannot restore zone actions")
        }, () => !duelTable().decisionDock.collapsed && find("rulesZoneAction-yard-b"))
        add("The next decision restores zone actions", () => {
            require(auditProbe.click(find("forgeDecisionCollapse")), "Cannot hide choice again")
            ++promptSerial
            require(auditProbe.updateRulesTableFixture(state,priorityPrompt()), "Cannot publish next priority")
        }, () => !duelTable().decisionDock.collapsed && find("rulesZoneAction-yard-a") && find("rulesZoneAction-yard-b"))
        add("Start a pending battlefield selection", () => {
            const target=priorityPrompt()
            target.promptId=++promptSerial; target.kind="chooseBoardTargets"; target.options=[]
            target.title="Choose up to two target permanents";target.minSelections=1;target.maxSelections=2
            target.targets=[{responseId:"target-relic",kind:"card",objectId:"relic",label:"Engineered Explosives"},
                {responseId:"target-player",kind:"player",seat:1,label:"Bob"}]
            require(auditProbe.updateRulesTableFixture(state,target), "Cannot publish target decision")
            require(duelTable().reveal("relic"), "Cannot expose target")
        }, () => duelTable().decisionDock.collapsed)
        add("Select the exposed card and keep the draft", () => {
            require(auditProbe.click(find("forgeCard-relic")), "Cannot select target")
            require(duelTable().tableController.interaction.selectedCount===1, "Selection was not retained")
            require(auditProbe.click(find("forgeDecisionCollapse")), "Cannot restore selection controls")
        }, () => !duelTable().decisionDock.collapsed && find("rulesConfirmTargets"))
        add("Inspect the retained selection and confirmation", () => {
            require(duelTable().tableController.interaction.selectedCount===1, "Showing choice lost the draft")
            require(find("rulesConfirmTargets").enabled, "Confirmation remains inaccessible")
            capture("selection-restored")
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
