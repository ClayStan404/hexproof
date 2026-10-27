// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

// Production Qt window and input; isolated room projections are fixture setup.
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
    property bool forge: auditProbe.environment("HEXPROOF_AUDIT_VARIANT") === "forge"
    property var popup: null
    property var table: null
    function require(value, message) { if (!value) throw new Error(message + "; " + auditProbe.lastError) }
    function find(name) { return auditProbe.find(auditWindow, name) }
    function add(name, action, check) { steps.push({name:name, action:action, check:check || (() => true), timeout:20000}) }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }
    function finish(error) {
        if (finished) return
        finished = true
        if (error) capture("failure")
        const geometry = auditProbe.observe(auditWindow)
        auditProbe.record("result", {status:error ? "failed" : "passed", scenario:"keyword-reference",
            mode:forge ? "forge" : "manual", evidence:"native-qt-input", roomSetup:"fixture",
            error:error || "", pendingStep:index < steps.length ? steps[index].name : "",
            assertions:assertions, requiredScreenshots:screenshots, windowGeometry:geometry})
        auditProbe.finish(error ? 1 : 0)
    }
    function prepare() {
        const room = {roomId:"KEYW01",name:"Keyword reference test",format:"modern",deckFormat:"custom",
            rulesMode:forge ? "forge" : "manual",hostingMode:"server",hostConnected:true,maxSeats:2,
            phase:"started",matchMode:"bo1",role:"player",seatIndex:0,host:true,
            seats:[{occupied:true,displayName:"Reference player",host:true,ready:true,loaded:true},
                   {occupied:true,displayName:"Opponent",ready:true,loaded:true}]}
        if (forge) {
            require(auditProbe.applyRulesTableFixture(room, {roomId:"KEYW01",gameId:"keyword-test",
                turn:3,step:"main1",activeSeat:0,prioritySeat:0,
                players:[{seat:0,name:"Reference player",life:20},{seat:1,name:"Opponent",life:20}],
                zones:[{zone:"hand",ownerSeat:0,count:0,cards:[]},{zone:"hand",ownerSeat:1,count:7,cards:[]},
                       {zone:"library",ownerSeat:0,count:40,cards:[]},{zone:"library",ownerSeat:1,count:40,cards:[]}],stack:[]}),
                "Cannot apply Forge fixture")
        } else {
            const seat = index => ({seat:index,displayName:index ? "Opponent" : "Reference player",life:20,
                handCount:0,libraryCount:40,hand:[],battlefield:[],graveyard:[],exile:[],commandZone:[],counters:[]})
            require(auditProbe.applyManualTableFixture(room, {roomId:"KEYW01",gameNumber:1,startingSeat:0,
                turnOrder:[0,1],activeSeat:0,currentPhase:"main_1",seats:[seat(0),seat(1)],stack:[],
                revealed:[],arrows:[],attachments:[],log:[],score:[0,0],result:{},sideboard:{}}), "Cannot apply manual fixture")
        }
        auditProbe.fixture("keyword-reference", {mode:forge ? "forge" : "manual", scope:"Static reference and input isolation; no live engine"})
        preferences.uiLanguage = "zh"
        auditWindow.showTable()
    }
    function search(value) {
        require(auditProbe.click(find("keywordSearch")), "Cannot focus search")
        require(auditProbe.key(Qt.Key_A, Qt.ControlModifier), "Cannot select search")
        require(auditProbe.text(value), "Cannot enter search")
    }
    function openReference() {
        if (forge) require(auditProbe.click(find("forgeGameMenu")), "Cannot open Forge menu")
    }
    function plan() {
        add("Dismiss first-launch notices", () => {
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                const item = find(name)
                if (item) { require(auditProbe.click(item), "Cannot dismiss notice"); return false }
            }
            return !!find("mainMenuSettingsButton")
        })
        add("Mount isolated production table", prepare, () => !!find(forge ? "forgeGameMenu" : "tableKeywordReferenceButton"))
        add("Open reference entry", openReference, () => !forge || !!find("rulesKeywordReferenceButton"))
        add("Click keyword reference", () => {
            const button = find(forge ? "rulesKeywordReferenceButton" : "tableKeywordReferenceButton")
            require(button, "Missing reference entry")
            table = find(forge ? "rulesActionRail" : "tableActionRail").tableController
            require(auditProbe.click(button), "Cannot open reference")
        }, () => !!find("keywordSearch") && find("keywordSearch").activeFocus)
        add("Read the complete browse index", () => {
            popup = table.keywordReference
            require(popup && popup.entries.length === 264 && popup.filteredEntries.length === 264, "Incomplete catalog")
            const geometry = auditProbe.observe(auditWindow)
            require(geometry.windowMode === "maximized", "Primary window must be maximized")
            capture("keywords-browse")
        })
        add("Search mixed-case English", () => search("FlYiNg"), () => popup.filteredEntries.length === 1)
        add("Verify English query and game input isolation", () => {
            require(popup.filteredEntries[0].english === "Flying", "Wrong English result")
            require(auditProbe.key(Qt.Key_Space), "Cannot type space")
            require(auditProbe.key(Qt.Key_Return), "Cannot test Enter")
            require(auditProbe.key(Qt.Key_D, Qt.ControlModifier), "Cannot test table shortcut")
            capture("keywords-english")
        })
        add("Search Chinese", () => search("飞行"), () => popup.filteredEntries.length === 1)
        add("Verify Chinese lookup and explanation", () => {
            require(popup.filteredEntries[0].english === "Flying", "Wrong Chinese result")
            require(popup.chinese && popup.filteredEntries[0].summaryZh.length > 8, "Missing Chinese explanation")
            capture("keywords-chinese")
        })
        add("Read longer legacy ability", () => search("banding"), () => popup.filteredEntries.length > 0)
        add("Inspect long wrapped text", () => capture("keywords-long-entry"))
        add("Show an unmatched query", () => search("<no keyword>"), () => popup.filteredEntries.length === 0)
        add("Verify empty state and Reset", () => {
            require(find("keywordNoResults").visible, "Missing empty state")
            capture("keywords-empty")
            require(auditProbe.click(find("resetKeywordSearch")), "Cannot reset")
        }, () => popup.filteredEntries.length === 264)
        add("Scroll complete list", () => {
            require(auditProbe.wheel(find("keywordResults"), -1600), "Cannot scroll list")
        }, () => find("keywordResults").contentY > 0)
        add("Inspect scrolled list", () => capture("keywords-scrolled"))
        add("Close with Escape and restore table focus", () => {
            require(auditProbe.key(Qt.Key_Escape), "Cannot close with Escape")
        }, () => !popup.visible)
        add("Verify close leaves the match usable", () => {
            require(!popup.visible, "Popup remained open")
            require(forge ? !table.priorityInputBlocked : !table.sessionUi.counterShortcutBlocked(), "Table input remained blocked")
            capture("keywords-closed")
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
