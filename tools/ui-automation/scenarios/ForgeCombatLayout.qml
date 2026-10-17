// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

// Five creatures share a battlefield with lands, a mana artifact and equipment.
// Snapshot/prompt setup is a fixture; geometry, input and captures use the native client.
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
            scenario: "forge-combat-layout",
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
    property int promptSerial: 1
    function setPhase(step, attached) {
        fixtureSnapshot.step = step
        const cards = fixtureSnapshot.zones[4].cards
        cards.find(card => card.id === "equipment-a").attachedTo = attached ? "creature-0" : ""
        cards.find(card => card.id === "equipment-b").attachedTo = attached ? "creature-1" : ""
        const combat = step === "declare_attackers"
        const prompt = {roomId:"FIX001",gameId:"combat-layout",promptId:++promptSerial,pending:true,
            supported:true,kind:combat ? "chooseAttackers" : "chooseAction",title:"Choose",detail:"",choices:[],cards:[],targets:[],contextCards:[],contextTargets:[],damageTargets:[],scryDestinations:[],totalDamage:0,
            options:combat ? [] : [{responseId:"pass",kind:"pass",label:"Pass"}],
            combatSources:combat ? Array.from({length:5},(_,i)=>({responseId:"source-"+i,objectId:"creature-"+i,
                name:cards[i].identity.name,label:cards[i].identity.name,validTargetIds:["defender"],maxAssignments:1})) : [],
            combatTargets:combat ? [{responseId:"defender",kind:"player",seat:1,label:"Opponent",minAssignments:0,maxAssignments:5}] : []}
        require(auditProbe.updateRulesTableFixture(fixtureSnapshot,prompt), "Cannot update fixture")
    }
    function recordSize(name) {
        const board=duelTable()
        const names=["forgeOwnCreatures","forgeOwnLands","forgeOwnOther"]
        const rows=names.map(name=>{
            const lane=read(name)
            return {name:name,stackCount:lane.stackCount,x:lane.x,y:lane.y,width:lane.width,height:lane.height,
                cardWidth:lane.cardWidth,cardHeight:lane.cardHeight,hasBadges:lane.hasBadges,
                attachmentDepth:lane.attachmentDepth,cellExtra:lane.cellExtra,edgeSpace:lane.edgeSpace}
        })
        auditProbe.record(name,{unit:board.unit,laneHeight:board.laneHeight,
            window:(()=>{const g=auditProbe.observe(auditWindow);return {width:g.width,height:g.height,dpr:g.dpr,windowMode:g.windowMode,screenGeometry:g.screenGeometry}})(),lanes:rows})
        require(read("forgeOwnCreatures").cardWidth >= 160 * board.unit, "Five creatures must remain large")
        for (const name of names) {
            const lane = read(name)
            if (!lane.stackCount) continue
            require(lane.scrollArea.contentHeight <= lane.height + 1, "Ordinary board must fit: " + name)
            if (name !== "forgeOwnCreatures") {
                require(lane.attachmentDepth === 0 && !lane.hasBadges, "Unrelated support row reserves decorations")
            }
        }
        capture(name)
    }
    function plan() {
        add("Dismiss first-launch notices", () => {
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                const item=find(name)
                if (item) { require(auditProbe.click(item),"Cannot dismiss notice");return false }
            }
            return !!find("mainMenuSettingsButton")
        })
        add("Open five creatures, lands, drum and two attachments", () => {
            preferences.tableBackground="astral"; preferences.uiLanguage="zh"
            fixtureRoom={roomId:"FIX001",name:"Forge combat layout verification",format:"modern",deckFormat:"modern",
                rulesMode:"forge",hostingMode:"server",hostConnected:true,maxSeats:2,phase:"started",
                matchMode:"bo1",role:"player",seatIndex:0,host:true,
                seats:[{occupied:true,displayName:"Player",host:true,deckSelected:true,ready:true,loaded:true},
                    {occupied:true,displayName:"Opponent",deckSelected:true,ready:true,loaded:true}]}
            const creatures=[["Ornithopter","M10","216"],["Myr Enforcer","MRD","211"],
                ["Frogmite","MRD","172"],["Sojourner's Companion","MH2","235"],["Somber Hoverguard","MRD","51"]]
                .map((identity,i)=>Object.assign(card("creature-"+i,0,...identity),{power:String(i+1),toughness:String(i+1)}))
            const permanents=creatures.concat([card("land-a",0,"Great Furnace","MRD","282"),
                card("land-b",0,"Silverbluff Bridge","MH2","255"),
                card("drum",0,"Springleaf Drum","LRW","261"),
                Object.assign(card("equipment-a",0,"Bonesplitter","MRD","146"),{attachedTo:"creature-0"}),
                Object.assign(card("equipment-b",0,"Cranial Plating","5DN","113"),{attachedTo:"creature-1"})])
            fixtureSnapshot={roomId:"FIX001",gameId:"combat-layout",turn:5,step:"main1",activeSeat:0,prioritySeat:0,
                players:[{seat:0,name:"Player",life:17},{seat:1,name:"Opponent",life:15}],
                zones:[{zone:"hand",ownerSeat:0,count:0,cards:[]},{zone:"hand",ownerSeat:1,count:6,cards:[]},
                    {zone:"library",ownerSeat:0,count:49,cards:[]},{zone:"library",ownerSeat:1,count:50,cards:[]},
                    {zone:"battlefield",ownerSeat:0,count:permanents.length,cards:permanents},
                    {zone:"battlefield",ownerSeat:1,count:0,cards:[]}],stack:[]}
            apply();auditWindow.showTable();setPhase("main1",true)
        },()=>find("forgeOwnCreatures") && find("forgeOwnCreatures").stackCount===5
            && find("forgeOwnLands").stackCount===2 && find("forgeOwnOther").stackCount===1)
        add("Settle baseline geometry",()=>{require(auditProbe.hover(find("rulesPlayerTarget1")),"Cannot clear hover")},
            ()=>Date.now()-stepStarted>500)
        add("Record attached main phase",()=>recordSize("main1-two-attachments"))
        add("Enter combat with two attachments",()=>setPhase("declare_attackers",true),
            ()=>find("forgeOwnCreatures").combatPresentation && find("forgeOwnCreatures").hasBadges
                && Date.now()-stepStarted>500)
        add("Verify large combat cards",()=>{
            recordSize("combat-two-attachments")
        })
        for (let i = 0; i < 5; ++i) {
            const index = i
            add("Select attacker " + index, () => {
                require(auditProbe.click(find("forgeCard-creature-" + index)), "Cannot select creature")
            }, () => duelTable().tableController.combatInteraction.selectedSource === "source-" + index)
            add("Assign attacker " + index, () => {
                require(auditProbe.click(find("rulesPlayerTarget1")), "Cannot choose defending player")
            }, () => duelTable().tableController.combatInteraction.assignments["source-" + index] === "defender")
        }
        add("Capture five individually assigned attackers", () => recordSize("five-attackers-assigned"))
        add("Second attachment on one of the equipped creatures",()=>{
            const cards=fixtureSnapshot.zones[4].cards
            cards.push(Object.assign(card("equipment-c",0,"Bonesplitter","MRD","146"),{attachedTo:"creature-1"}))
            fixtureSnapshot.zones[4].count=cards.length
            setPhase("declare_attackers",true)
        },()=>find("forgeOwnCreatures").attachmentDepth===2 && Date.now()-stepStarted>500)
        add("Verify depth-two combat cards",()=>recordSize("combat-attachment-depth-two"))
        add("Control: remove the independent artifact row",()=>{
            const zone=fixtureSnapshot.zones[4]
            zone.cards=zone.cards.filter(card=>card.id!=="drum")
            zone.count=zone.cards.length
            setPhase("declare_attackers",true)
        },()=>read("forgeOwnOther").stackCount===0 && Date.now()-stepStarted>500)
        add("Verify empty support row gives space back",()=>recordSize("combat-without-other-row"))
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
