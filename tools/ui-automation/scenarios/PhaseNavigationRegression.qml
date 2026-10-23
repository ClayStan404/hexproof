// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

// Production manual table with an isolated sealed projection. Native evidence
// covers layout and retained authority; command routing has focused QML tests.
Item {
    id: driver
    property int stage: 0
    property int transitionIndex: 0
    property double changedAt: Date.now()
    property double startedAt: Date.now()
    property bool finished: false
    property bool dispatching: false
    property var measurements: []
    property var screenshots: []
    property var transitionWindow: ({})
    readonly property string expectedPhase: "main_2"
    readonly property var states: [
        {scale: 1, language: "zh"},
        {scale: 1.5, language: "de"},
        {scale: 1.35, language: "en"},
        {scale: 1, language: "en"}]

    function require(value, message) {
        if (!value) throw new Error(message + (auditProbe.lastError ? "; " + auditProbe.lastError : ""))
    }
    function lookup(name, scope) {
        const item = scope || auditWindow.contentItem
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const found = lookup(name, child)
            if (found) return found
        }
        return null
    }
    function fixture() {
        const seat = index => ({seat: index, displayName: index === 0 ? "Phase fixture" : "Opponent fixture",
            life: 20, handCount: 0, libraryCount: 40, hand: [], battlefield: [], graveyard: [],
            exile: [], commandZone: [], counters: []})
        const room = {roomId: "PHASE1", name: "Phase acceptance", format: "sealed", deckFormat: "limited",
            rulesMode: "manual", maxSeats: 2, phase: "started", matchMode: "bo3", role: "player",
            seatIndex: 0, host: true, seats: [
                {occupied: true, displayName: "Phase fixture", host: true, ready: true, loaded: true},
                {occupied: true, displayName: "Opponent fixture", ready: true, loaded: true}]}
        const snapshot = {roomId: "PHASE1", gameNumber: 1, startingSeat: 0, turnOrder: [0, 1], activeSeat: 0,
            currentPhase: expectedPhase, seats: [seat(0), seat(1)], stack: [], revealed: [], arrows: [],
            attachments: [], log: [], score: [0, 0], result: {}, sideboard: {}}
        auditProbe.fixture("phase-navigation-regression", {
            description: "Production manual table with an isolated sealed room/session projection",
            referenceCommit: "8529743029c48334ab3e2381a74edd18087ba2e0",
            nativeScope: "Layout, scaling, retranslation and retained authoritative phase; not a live room"})
        require(auditProbe.applyManualTableFixture(room, snapshot), "Cannot apply the manual phase fixture")
        applyState(states[0])
        auditWindow.showTable()
    }
    function applyState(state) {
        preferences.interfaceScale = state.scale
        preferences.uiLanguage = state.language
        changedAt = Date.now()
    }
    function windowGeometry() {
        const observed = auditProbe.observe(auditWindow)
        return {requestedWindowMode: observed.requestedWindowMode, windowMode: observed.windowMode,
            width: observed.width, height: observed.height, dpr: observed.dpr,
            screenGeometry: observed.screenGeometry}
    }
    function measure(label) {
        const strip = lookup("phaseStrip")
        require(strip && strip.visible, "Phase strip is unavailable")
        const selector = lookup("compactPhaseSelector", strip)
        require(selector && selector.count === 11, "All eleven phase choices must remain available")
        require(ws.gameSession.currentPhase === expectedPhase
                && strip.tableController.displayedPhase === expectedPhase,
                "Presentation changes replaced the authoritative phase")
        require(selector.currentIndex === 9, "Selector no longer follows Main 2")
        const assist = lookup("turnAssistButton", strip)
        const land = lookup("landPlayCountControls", strip)
        const boundary = (assist.visible ? assist : land).mapToItem(strip, 0, 0).y
        let completeRows = 0
        if (!selector.visible) {
            for (let index = 0; index < 11; ++index) {
                const button = lookup("phaseButton" + index, strip)
                require(button && button.visible, "Phase row " + index + " is missing")
                const point = button.mapToItem(strip, 0, 0)
                require(point.y >= 0 && point.y + button.height <= boundary + 0.1,
                        "Phase row " + index + " is clipped by persistent actions")
                completeRows++
            }
        }
        const fitsDenseList = strip.height >= strip.compactPhasesMinimumHeight
        require(selector.visible === !fitsDenseList, "Selector replaced a phase list that still fits")
        for (const name of ["landPlayCountControls", "responseStatusButton", "nextPhaseButton", "nextTurnButton"]) {
            const control = lookup(name, strip)
            const point = control.mapToItem(strip, 0, 0)
            require(control.visible && point.y >= 0 && point.y + control.height <= strip.height + 0.1,
                    name + " is outside the usable phase rail")
        }
        const geometry = windowGeometry()
        const sample = {label: label, interfaceScale: preferences.interfaceScale,
            language: preferences.uiLanguage, mode: selector.visible ? "selector" : "list",
            completeRows: completeRows, compactActions: strip.compactControls, actionsReachable: true,
            authoritativePhase: ws.gameSession.currentPhase, stripHeight: strip.height,
            nextPhaseHeight: lookup("nextPhaseButton", strip).height, windowGeometry: geometry}
        measurements.push(sample)
        require(auditProbe.record("phase-measurements", measurements), "Cannot record phase measurements")
        return sample
    }
    function capture(label) {
        require(auditProbe.hover(lookup("nextPhaseButton")), "Cannot hover a reachable phase action")
        require(auditProbe.capture(auditWindow, label), "Cannot capture " + label)
        screenshots.push(label + ".png")
    }
    function finish(error, approved) {
        if (finished) return
        if (!error) {
            if (!auditProbe.record("ui-baseline", {
                schema: "hexproof.ui-baseline-evidence.v1",
                referenceCommit: "8529743029c48334ab3e2381a74edd18087ba2e0",
                scenario: "phase-navigation-regression",
                cases: [
                    {id: "phase.list_at_approved_budget", windowGeometry: approved.windowGeometry,
                        observations: {mode: approved.mode, completeRows: approved.completeRows,
                            actionsReachable: approved.actionsReachable, compactActions: approved.compactActions}},
                    {id: "phase.presentation_transitions", windowGeometry: transitionWindow,
                        observations: {transitions: measurements.length - 1, authoritativePhaseRetained: true,
                            details: measurements}}]
            })) error = "Cannot record baseline evidence"
        }
        finished = true
        auditProbe.record("result", {status: error ? "failed" : "passed", scenario: "phase-navigation-regression",
            error: error || "", measurements: measurements, requiredScreenshots: screenshots,
            nativeScope: "Production manual-table layout and retained authority, not live command acknowledgement"})
        auditProbe.finish(error ? 1 : 0)
    }
    Timer {
        interval: 100
        repeat: true
        running: !driver.finished
        onTriggered: {
            if (driver.dispatching) return
            driver.dispatching = true
            try {
                driver.require(Date.now() - driver.startedAt < 30000, "Phase acceptance timed out")
                if (auditWindow.stack.busy) return
                if (driver.stage === 0) {
                    for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                        const notice = auditProbe.find(auditWindow, name)
                        if (notice) { driver.require(auditProbe.click(notice), "Cannot dismiss " + name); return }
                    }
                    driver.transitionWindow = driver.windowGeometry()
                    driver.require(driver.transitionWindow.windowMode === "maximized",
                                   "The primary phase acceptance must start maximized")
                    driver.fixture()
                    driver.stage = 1
                } else if (Date.now() - driver.changedAt >= 1000 && driver.stage === 1) {
                    driver.measure("maximized-transition-" + driver.transitionIndex)
                    driver.capture("maximized-transition-" + driver.transitionIndex)
                    driver.transitionIndex++
                    if (driver.transitionIndex < driver.states.length) {
                        driver.applyState(driver.states[driver.transitionIndex])
                    } else {
                        auditProbe.fixture("feedback-window-supplement", {
                            description: "Explicit fixed-window regression probe after the primary maximized run",
                            requestedWidth: 1280, requestedHeight: 686, interfaceScale: 1})
                        auditWindow.showNormal()
                        auditWindow.width = 1280
                        auditWindow.height = 686
                        driver.applyState({scale: 1.5, language: "de"})
                        driver.stage = 2
                    }
                } else if (Date.now() - driver.changedAt >= 1000 && driver.stage === 2) {
                    const dense = driver.measure("fixed-selector-transition")
                    driver.require(dense.mode === "selector", "The supplementary dense probe must exercise the selector")
                    driver.require(auditProbe.click(driver.lookup("compactPhaseSelector")), "Cannot open the phase selector")
                    driver.changedAt = Date.now()
                    driver.stage = 3
                } else if (driver.stage === 3) {
                    const selector = driver.lookup("compactPhaseSelector")
                    if (!selector.popup.opened) return
                    driver.require(auditProbe.key(Qt.Key_Escape), "Cannot dismiss the selector without choosing a phase")
                    driver.stage = 4
                } else if (driver.stage === 4) {
                    if (driver.lookup("compactPhaseSelector").popup.opened) return
                    driver.require(ws.gameSession.currentPhase === driver.expectedPhase,
                                   "Opening and dismissing the selector replaced the authoritative phase")
                    driver.applyState({scale: 1, language: "zh"})
                    driver.stage = 5
                } else if (Date.now() - driver.changedAt >= 1000 && driver.stage === 5) {
                    const approved = driver.measure("reported-1280x686")
                    driver.require(approved.windowGeometry.width === 1280 && approved.windowGeometry.height === 686,
                                   "The feedback-window supplement did not reach its requested logical geometry")
                    driver.require(approved.mode === "list" && approved.completeRows === 11
                                   && approved.compactActions && approved.nextPhaseHeight === 26,
                                   "The approved feedback viewport must keep all eleven rows with compact actions")
                    driver.capture("reported-1280x686")
                    driver.finish("", approved)
                }
            } catch (error) { driver.finish(String(error)) }
            finally { driver.dispatching = false }
        }
    }
}
