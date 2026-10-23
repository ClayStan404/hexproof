// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: driver
    property int step: 0
    property int expectedPicks: 0
    property int savedDeckCount: 0
    property int capturedRound: 0
    property double started: Date.now()
    property bool dispatching: false
    property bool finished: false
    readonly property bool cube: auditProbe.environment("HEXPROOF_AUDIT_VARIANT") === "cube"

    function require(value, message) { if (!value) throw new Error(message) }
    function find(name) { return auditProbe.find(auditWindow, name, {}) }
    function click(name) {
        const item = find(name)
        if (!item) return false
        require(auditProbe.click(item), "Cannot click " + name)
        return true
    }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
    }
    function finish(status, message) {
        finished = true
        const observed = auditProbe.observe(auditWindow)
        auditProbe.record("result", {scenario:"draft-practice", status:status, message:message,
            variant:cube ? "cube" : "set", picks:draftSimulator.state.pool.length,
            deckCount:deckLibrary.count, connected:ws.connected,
            window:{requestedWindowMode:observed.requestedWindowMode, windowMode:observed.windowMode,
                width:observed.width, height:observed.height, dpr:observed.dpr,
                screenGeometry:observed.screenGeometry}, elapsedMs:Date.now() - started,
            requiredScreenshots:["setup.png", "pack-1.png", "pack-2.png", "pack-3.png",
                "construction.png", "saved.png", "resumed.png"]})
        auditProbe.finish(status === "passed" ? 0 : 1)
    }
    Timer {
        interval: 220
        repeat: true
        running: !driver.finished
        onTriggered: {
            if (driver.dispatching || auditWindow.stack.busy) return
            driver.dispatching = true
            try {
                driver.require(Date.now() - driver.started < 180000, "Practice scenario timed out")
                driver.require(!ws.connected && !ws.inRoom, "Practice unexpectedly connected to a hub")
                switch (driver.step) {
                case 0:
                    if (driver.click("mainMenuPackSimulatorButton")) driver.step++
                    break
                case 1:
                    if (driver.click("openDraftPracticeButton")) driver.step++
                    break
                case 2: {
                    if (driver.cube) {
                        const selector = driver.find("draftPracticeSourceSelector")
                        if (!selector) break
                        driver.require(auditProbe.click(selector, selector.width * 0.75, selector.height / 2), "Cannot select Cube")
                        if (!driver.click("draftPracticeSeatSelector")) break
                        driver.require(auditProbe.key(Qt.Key_Home), "Cannot choose two seats")
                        driver.require(auditProbe.key(Qt.Key_Return), "Cannot accept seat count")
                    } else {
                        const search = driver.find("limitedSetSearchField")
                        if (!search) break
                        driver.require(auditProbe.click(search), "Cannot focus set search")
                        driver.require(auditProbe.text("EOE"), "Cannot search EOE")
                    }
                    driver.step++
                    break
                }
                case 3:
                    driver.capture("setup")
                    if (driver.click("startDraftPracticeButton")) driver.step++
                    break
                case 4:
                    driver.require(draftSimulator.state.active, "Practice did not start: " + draftSimulator.lastError)
                    driver.require(draftSimulator.state.participants.length === (driver.cube ? 2 : 8), "Wrong pod size")
                    if (draftSimulator.state.stage === "deck_building") {
                        driver.require(draftSimulator.state.pool.length === 3 * draftSimulator.state.product.cardsPerPack, "Wrong completed pool size")
                        driver.step++
                        break
                    }
                    driver.require(draftSimulator.state.pool.length === driver.expectedPicks, "A pick was lost or repeated")
                    if (driver.capturedRound !== draftSimulator.state.packRound) {
                        driver.capturedRound = draftSimulator.state.packRound
                        driver.require(draftSimulator.state.direction === (driver.capturedRound === 2 ? -1 : 1), "Wrong pass direction")
                        driver.capture("pack-" + driver.capturedRound)
                    }
                    const id = draftSimulator.state.currentPack[0].instanceId
                    const card = driver.find("limitedDraftPackCard-" + id)
                    if (!card) break
                    driver.require(auditProbe.doubleClick(card), "Cannot confirm physical card")
                    driver.expectedPicks++
                    break
                case 5:
                    if (driver.click("keepDraftedCardsButton")) driver.step++
                    break
                case 6:
                    driver.capture("construction")
                    driver.savedDeckCount = deckLibrary.count
                    if (driver.click("limitedSubmitDeckButton")) driver.step++
                    break
                case 7:
                    driver.require(draftSimulator.lastError === "", "Save failed: " + draftSimulator.lastError)
                    driver.require(draftSimulator.state.deckSubmitted, "Save was not acknowledged")
                    driver.require(deckLibrary.count === driver.savedDeckCount + 1, "No local deck was created")
                    driver.capture("saved")
                    if (driver.click("screenBackButton")) driver.step++
                    break
                case 8:
                    if (driver.click("openDraftPracticeButton")) driver.step++
                    break
                case 9:
                    driver.require(draftSimulator.state.deckSubmitted, "Navigation lost saved construction")
                    driver.require(!!driver.find("draftPracticeDeckBuilder"), "Navigation lost builder")
                    driver.capture("resumed")
                    if (driver.click("newDraftPracticeButton")) driver.step++
                    break
                case 10:
                    if (driver.click("cancelButton")) driver.step++
                    break
                case 11:
                    driver.require(draftSimulator.state.active, "Cancelled restart discarded the draft")
                    if (driver.click("newDraftPracticeButton")) driver.step++
                    break
                case 12:
                    if (driver.click("confirmButton")) driver.step++
                    break
                case 13:
                    driver.require(!draftSimulator.state.active, "Confirmed restart did not clear the practice")
                    driver.require(deckLibrary.count === driver.savedDeckCount + 1, "Restart removed the saved deck")
                    driver.finish("passed", "")
                    break
                }
            } catch (error) {
                driver.capture("failure")
                driver.finish("failed", String(error))
            } finally {
                driver.dispatching = false
            }
        }
    }
}
